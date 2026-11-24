import Foundation

enum AiroxError: LocalizedError {
    case disconnected
    case ambiguous
    case accessDenied
    case unsupported
    case transport(Int32)
    case invalidReply(String)
    case invalidSetting(String)
    case unconfirmed(String)
    case recoveryFailed(String)
    case noAuroraReply
    case receiverNoReply

    var errorDescription: String? {
        switch self {
        case .disconnected: "Подключите мышь кабелем или вставьте приёмник Aurora."
        case .ambiguous: "Подключено несколько мышей одной модели. Оставьте подключённой одну."
        case .accessDenied: "macOS запретила доступ к интерфейсу мыши."
        case .unsupported: "Подключённая мышь сообщила несовместимую модель или версию контроллера."
        case let .transport(status): "Не удалось связаться с мышью (\(String(format: "0x%08x", UInt32(bitPattern: status))))."
        case let .invalidReply(name): "Мышь не вернула корректный ответ для «\(name)»."
        case let .invalidSetting(message): message
        case let .unconfirmed(name): "Мышь не подтвердила сохранение настройки «\(name)»."
        case let .recoveryFailed(name): "Не удалось подтвердить запись или восстановление настройки «\(name)». Считайте текущее состояние мыши."
        case .noAuroraReply: "Мышь не ответила на запрос настроек."
        case .receiverNoReply: "Включите Aurora или слегка подвигайте её, чтобы восстановить связь с приёмником."
        }
    }

    static func transport(_ status: Int32, notFound: Int32, ambiguous: Int32) -> AiroxError {
        switch status {
        case notFound, Int32(bitPattern: 0xe00002c0): .disconnected
        case ambiguous: .ambiguous
        case Int32(bitPattern: 0xe00002e2), Int32(bitPattern: 0xe00002c1): .accessDenied
        default: .transport(status)
        }
    }
}

enum AiroxPage: CaseIterable {
    case identity, dpi, reportRate, debounce, buttons, dpiColors, sensor, firmwareVersion

    var query: UInt8 {
        switch self {
        case .identity: 0x10
        case .buttons: 0x11
        case .reportRate: 0x12
        case .dpi: 0x13
        case .dpiColors: 0x14
        case .sensor: 0x16
        case .debounce: 0x17
        case .firmwareVersion: 0x20
        }
    }

    var name: String {
        switch self {
        case .identity: "модель"
        case .dpi: "DPI"
        case .reportRate: "частота опроса"
        case .debounce: "питание и дебаунс"
        case .buttons: "назначения кнопок"
        case .dpiColors: "цвета ступеней DPI"
        case .sensor: "параметры сенсора"
        case .firmwareVersion: "версия прошивки"
        }
    }

    func payload(from report: [UInt8]) throws -> [UInt8] {
        guard report.count == 32, Array(report.prefix(3)) == [query, 0, 1],
              report[3] <= 27, report[31] == AiroxWrite.checksum(report) else {
            throw AiroxError.invalidReply(name)
        }
        return Array(report[4..<(4 + Int(report[3]))])
    }
}

struct AiroxDeviceInfo: Sendable {
    let batteryPercent: Int?
    let charging: Bool?
    let firmwareVersion: String?

    init(identity: [UInt8], version: [UInt8]?) {
        if identity.count >= 10, identity[9] <= 100 {
            batteryPercent = Int(identity[9])
            charging = identity[8] == 1
        } else {
            batteryPercent = nil
            charging = nil
        }
        if let version, version.count >= 2 {
            firmwareVersion = String(format: "v%X.%02X", Int(version[0]), Int(version[1]))
        } else {
            firmwareVersion = nil
        }
    }
}

struct AiroxWrite {
    let page: AiroxPage
    let packet: [UInt8]
    let expectedPayload: [UInt8]
    private let checkedPrefix: Int?

    static func checksum(_ report: [UInt8]) -> UInt8 {
        report[4..<31].reduce(0, &+)
    }

    init(page: AiroxPage, code: UInt8, opcode: UInt8, payload: [UInt8],
         expected: [UInt8]? = nil, checkedPrefix: Int? = nil) {
        self.page = page
        var bytes: [UInt8] = [code, 0, 1, opcode] + payload
        bytes += Array(repeating: 0, count: 32 - bytes.count)
        bytes[31] = Self.checksum(bytes)
        packet = bytes
        expectedPayload = expected ?? payload
        self.checkedPrefix = checkedPrefix
    }

    func matches(_ readback: [UInt8]) -> Bool {
        guard let checkedPrefix else { return readback == expectedPayload }
        return readback.count == expectedPayload.count
            && readback.prefix(checkedPrefix) == expectedPayload.prefix(checkedPrefix)
    }
}

struct AiroxSnapshot {
    let settings: AiroxSettings
    private let advanced: AiroxAdvancedSnapshot

    init(dpi: [UInt8], rate: [UInt8], power: [UInt8], buttons: [UInt8],
         colors: [UInt8]? = nil, sensor: [UInt8]? = nil) throws {
        guard dpi.count == 25 else { throw AiroxError.invalidReply(AiroxPage.dpi.name) }
        let count = Int(dpi[0] & 15)
        let active = Int(dpi[0] >> 4)
        guard (1...6).contains(count), active < count else { throw AiroxError.invalidReply(AiroxPage.dpi.name) }
        guard rate.count == 1, [1, 2, 4, 8].contains(rate[0]) else {
            throw AiroxError.invalidReply(AiroxPage.reportRate.name)
        }
        guard buttons.count == 18 else { throw AiroxError.invalidReply(AiroxPage.buttons.name) }
        let advanced = try AiroxAdvancedSnapshot(colors: colors, sensor: sensor, power: power)

        settings = AiroxSettings(
            activeStage: active,
            stages: stride(from: 1, to: 25, by: 4).map {
                DPIStage(x: Self.dpi(dpi[$0], dpi[$0 + 1]), y: Self.dpi(dpi[$0 + 2], dpi[$0 + 3]))
            },
            reportRate: 1000 / Int(rate[0]),
            debounce: Int(power[3]),
            buttons: stride(from: 0, to: 18, by: 3).map {
                ButtonAction(buttons[$0], buttons[$0 + 1], buttons[$0 + 2])
            },
            enabledStageCount: count,
            advanced: advanced.settings
        )
        self.advanced = advanced
    }

    func writes(for proposed: AiroxSettings) throws -> [AiroxWrite] {
        var result: [AiroxWrite] = []
        if proposed.reportRate != settings.reportRate {
            guard AiroxSettings.reportRates.contains(proposed.reportRate) else {
                throw AiroxError.invalidSetting("Выберите поддерживаемую частоту опроса.")
            }
            result.append(AiroxWrite(page: .reportRate, code: 0x02, opcode: 0x01,
                                     payload: [UInt8(1000 / proposed.reportRate)]))
        }
        result += try advanced.writes(for: proposed)
        if proposed.buttons != settings.buttons {
            guard proposed.buttons.count == settings.buttons.count else {
                throw AiroxError.invalidSetting("Нужно указать назначения для шести кнопок.")
            }
            if settings.buttons.contains(.leftClick), !proposed.buttons.contains(.leftClick) {
                throw AiroxError.invalidSetting("Оставьте левый щелчок хотя бы на одной кнопке.")
            }
            result.append(AiroxWrite(page: .buttons, code: 0x09, opcode: 0x0f,
                                     payload: proposed.buttons.flatMap(\.bytes)))
        }
        if proposed.activeStage != settings.activeStage || proposed.stages != settings.stages
            || proposed.enabledStageCount != settings.enabledStageCount {
            guard let count = proposed.enabledStageCount, (1...settings.stages.count).contains(count),
                  (0..<count).contains(proposed.activeStage), proposed.stages.count == settings.stages.count else {
                throw AiroxError.invalidSetting("Выберите одну из активных ступеней DPI.")
            }
            for (edited, current) in zip(proposed.stages, settings.stages) where edited != current {
                guard [edited.x, edited.y].allSatisfy({ AiroxSettings.dpiRange.contains($0) && $0.isMultiple(of: AiroxSettings.dpiStep) }) else {
                    throw AiroxError.invalidSetting("DPI должен быть от 100 до 26 000 с шагом 50.")
                }
            }
            let selector = UInt8(proposed.activeStage << 4 | count)
            let payload = [selector] + proposed.stages.flatMap { Self.encode($0.x) + Self.encode($0.y) }
            result.append(AiroxWrite(page: .dpi, code: 0x03, opcode: 0x25, payload: payload))
        }
        return result
    }

    private static func dpi(_ low: UInt8, _ high: UInt8) -> Int {
        (1 + Int(low) + Int(high) * 256) * AiroxSettings.dpiStep
    }

    private static func encode(_ dpi: Int) -> [UInt8] {
        let value = UInt16(dpi / AiroxSettings.dpiStep - 1)
        return [UInt8(truncatingIfNeeded: value), UInt8(value >> 8)]
    }
}
