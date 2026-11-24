struct AuroraWrite {
    let address: Int
    let original: [UInt8]
    let updated: [UInt8]
}

struct AuroraChange {
    let name: String
    let writes: [AuroraWrite]
}

enum AuroraMemory {
    static let rate = 0x00
    static let dpiCount = 0x02
    static let activeDPI = 0x04
    static let dpiTable = 0x0c
    static let buttons = 0x60
    static let debounce = 0xa9
    static let shortcuts = 0x100
    static let shortcutLength = 32

    static func sumByte(_ bytes: [UInt8]) -> UInt8 {
        0x55 &- bytes.reduce(0, &+)
    }

    static func check(_ bytes: [UInt8]) -> Bool { sumByte(bytes) == 0 }

    static func scalar(_ value: Int) -> [UInt8] {
        let data = [UInt8(value)]
        return data + [sumByte(data)]
    }
}

enum AuroraButtons {
    static let count = 6
    static let shortcutKind: UInt8 = 5
    private static let scrollLeft = ButtonAction(0x20, 0x02)
    private static let scrollRight = ButtonAction(0x20, 0xfe)
    private static let toggleIndicator = ButtonAction(0x7d, 1)

    private static let direct: [ButtonAction: [UInt8]] = [
        .init(0x10, 0x01): [1, 0x01, 0],
        .init(0x10, 0x02): [1, 0x02, 0],
        .init(0x10, 0x04): [1, 0x04, 0],
        .init(0x10, 0x08): [1, 0x08, 0],
        .init(0x10, 0x10): [1, 0x10, 0],
        .init(0x30, 0x32, 0x03): [4, 50, 2],
        .init(0x20, 0x01): [11, 1, 0],
        .init(0x20, 0xff): [11, 2, 0],
        .init(0x40, 0x01): [2, 1, 0],
        .init(0x40, 0x02): [2, 2, 0],
        .init(0x40, 0x03): [2, 3, 0],
        .init(0x60, 0): [0, 0, 0],
        .cycleReportRate: [7, 0, 0],
        scrollLeft: [3, 1, 0],
        scrollRight: [3, 2, 0],
        toggleIndicator: [8, 1, 0],
    ]

    static let choices = ButtonAction.choices.filter {
        direct[$0] != nil || shortcut(for: $0) != nil
    } + [.cycleReportRate, scrollLeft, scrollRight, toggleIndicator]

    static func label(for action: ButtonAction) -> String? {
        switch action {
        case scrollLeft: "Прокрутка влево"
        case scrollRight: "Прокрутка вправо"
        case toggleIndicator: "Переключить индикатор DPI"
        default: nil
        }
    }

    static func slotAddress(_ index: Int) -> Int { AuroraMemory.buttons + index * 4 }
    static func shortcutAddress(_ index: Int) -> Int { AuroraMemory.shortcuts + index * AuroraMemory.shortcutLength }

    static func record(for action: ButtonAction) -> [UInt8]? {
        let bytes: [UInt8]
        if let direct = direct[action] {
            bytes = direct
        } else if shortcut(for: action) != nil {
            bytes = [shortcutKind, 0, 0]
        } else {
            return AuroraMacroMemory.assignmentRecord(for: action)
        }
        return bytes + [AuroraMemory.sumByte(bytes)]
    }

    static func shortcut(for action: ButtonAction) -> [UInt8]? {
        let bytes: [UInt8]
        switch action.kind {
        case 0x80:
            bytes = [2, 0x82, action.first, action.second, 0x42, action.first, action.second]
        case 0x70:
            guard action.keyboardShortcut else { return nil }
            if action.first == 0 {
                bytes = [2, 0x81, action.second, 0, 0x41, action.second, 0]
            } else {
                bytes = [4, 0x80, action.first, 0, 0x81, action.second, 0,
                         0x40, action.first, 0, 0x41, action.second, 0]
            }
        default:
            return nil
        }
        return bytes + [AuroraMemory.sumByte(bytes)]
    }

    static func action(record: [UInt8], shortcut: [UInt8]?, index: Int) -> ButtonAction {
        if let macro = AuroraMacroMemory.assignment(from: record) { return macro }
        if record[0] == shortcutKind, let shortcut {
            let candidate: ButtonAction? = if shortcut.count >= 14 && shortcut[0] == 4 {
                ButtonAction(0x70, shortcut[2], shortcut[5])
            } else if shortcut.count >= 8 && shortcut[0] == 2 && shortcut[1] == 0x81 {
                ButtonAction(0x70, 0, shortcut[2])
            } else if shortcut.count >= 8 && shortcut[0] == 2 && shortcut[1] == 0x82 {
                ButtonAction(0x80, shortcut[2], shortcut[3])
            } else {
                nil
            }
            if let candidate, let encoded = self.shortcut(for: candidate), shortcut.starts(with: encoded) { return candidate }
        } else if let action = choices.first(where: { self.record(for: $0) == record }) {
            return action
        }
        return ButtonAction(0xfe, record[0], UInt8(index))
    }
}

struct AuroraSnapshot {
    static let dpiRange = 50...26000
    static let debounceRange = 1...20
    static let maximumStageCount = 4
    private static let rates = [125: 8, 250: 4, 500: 2, 1000: 1]

    let settings: AiroxSettings
    private let general: [UInt8]
    private let debounce: [UInt8]
    private let buttons: [[UInt8]]
    private let shortcuts: [Int: [UInt8]]
    private let advanced: AuroraAdvancedSnapshot

    init(general: [UInt8], debounce: [UInt8], buttons: [[UInt8]], shortcuts: [Int: [UInt8]],
         sensor: [UInt8] = []) throws {
        guard general.count >= AuroraMemory.dpiTable,
              AuroraMemory.check(Array(general[0..<2])),
              AuroraMemory.check(Array(general[2..<4])),
              AuroraMemory.check(Array(general[4..<6])),
              let rate = Self.rates.first(where: { $0.value == Int(general[0]) })?.key else {
            throw AiroxError.invalidReply("DPI и частота опроса")
        }
        let count = Int(general[AuroraMemory.dpiCount])
        let active = Int(general[AuroraMemory.activeDPI])
        guard (1...Self.maximumStageCount).contains(count), active < count,
              general.count >= AuroraMemory.dpiTable + 4 * count else {
            throw AiroxError.invalidReply("ступени DPI")
        }
        guard debounce.count == 2, AuroraMemory.check(debounce) else {
            throw AiroxError.invalidReply("дебаунс")
        }
        guard buttons.count == AuroraButtons.count, buttons.allSatisfy({ $0.count == 4 && AuroraMemory.check($0) }) else {
            throw AiroxError.invalidReply("назначения кнопок")
        }
        var stages: [DPIStage] = []
        let storedCount = min(Self.maximumStageCount, (general.count - AuroraMemory.dpiTable) / 4)
        for index in 0..<storedCount {
            let offset = AuroraMemory.dpiTable + index * 4
            let record = Array(general[offset..<(offset + 4)])
            if !AuroraMemory.check(record), index >= count { break }
            guard AuroraMemory.check(record) else { throw AiroxError.invalidReply("значение DPI") }
            let x = ((Int(record[2] >> 2) & 3) << 8) | Int(record[0])
            let y = ((Int(record[2] >> 6) & 3) << 8) | Int(record[1])
            stages.append(DPIStage(x: (x + 1) * 50, y: (y + 1) * 50))
        }
        let advanced = AuroraAdvancedSnapshot(general: general, sensor: sensor, stageCount: stages.count)
        settings = AiroxSettings(
            activeStage: active,
            stages: stages,
            reportRate: rate,
            debounce: Int(debounce[0]),
            buttons: buttons.indices.map { AuroraButtons.action(record: buttons[$0], shortcut: shortcuts[$0], index: $0) },
            enabledStageCount: stages.count == Self.maximumStageCount ? count : nil,
            advanced: advanced.settings
        )
        self.general = general
        self.debounce = debounce
        self.buttons = buttons
        self.shortcuts = shortcuts
        self.advanced = advanced
    }

    func changes(for proposed: AiroxSettings) throws -> [AuroraChange] {
        var result: [AuroraChange] = []
        if proposed.reportRate != settings.reportRate {
            guard let rate = Self.rates[proposed.reportRate] else {
                throw AiroxError.invalidSetting("Выберите поддерживаемую частоту опроса.")
            }
            let write = generalWrite(address: AuroraMemory.rate, value: AuroraMemory.scalar(rate))
            result.append(AuroraChange(name: "частота опроса", writes: [write]))
        }
        if proposed.debounce != settings.debounce {
            guard Self.debounceRange.contains(proposed.debounce) else {
                throw AiroxError.invalidSetting("Выберите дебаунс от 1 до 20 мс.")
            }
            let write = AuroraWrite(address: AuroraMemory.debounce, original: debounce,
                                    updated: AuroraMemory.scalar(proposed.debounce))
            result.append(AuroraChange(name: "дебаунс", writes: [write]))
        }
        let previousCount = settings.enabledStageCount ?? settings.stages.count
        let proposedCount = proposed.enabledStageCount ?? proposed.stages.count
        guard proposed.stages.count == settings.stages.count,
              (1...settings.stages.count).contains(proposedCount),
              (0..<proposedCount).contains(proposed.activeStage),
              (settings.enabledStageCount == nil) == (proposed.enabledStageCount == nil) else {
            throw AiroxError.invalidSetting("Выберите одну из активных ступеней DPI.")
        }
        for index in proposed.stages.indices where proposed.stages[index] != settings.stages[index] {
            let stage = proposed.stages[index]
            guard [stage.x, stage.y].allSatisfy({ Self.dpiRange.contains($0) && $0.isMultiple(of: AiroxSettings.dpiStep) }) else {
                throw AiroxError.invalidSetting("DPI должен быть от 50 до 26 000 с шагом 50.")
            }
            let address = AuroraMemory.dpiTable + index * 4
            let value = stage.x / 50 - 1
            let y = stage.y / 50 - 1
            let flags = general[address + 2] & 0x33
            let bytes = [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: y),
                         flags | UInt8(value >> 8) << 2 | UInt8(y >> 8) << 6]
            let write = generalWrite(address: address, value: bytes + [AuroraMemory.sumByte(bytes)])
            result.append(AuroraChange(name: "ступень DPI \(index + 1)", writes: [write]))
        }
        var selectionWrites: [AuroraWrite] = []
        if proposedCount > previousCount {
            selectionWrites.append(generalWrite(address: AuroraMemory.dpiCount, value: AuroraMemory.scalar(proposedCount)))
        }
        if proposed.activeStage != settings.activeStage {
            selectionWrites.append(generalWrite(address: AuroraMemory.activeDPI, value: AuroraMemory.scalar(proposed.activeStage)))
        }
        if proposedCount < previousCount {
            selectionWrites.append(generalWrite(address: AuroraMemory.dpiCount, value: AuroraMemory.scalar(proposedCount)))
        }
        if !selectionWrites.isEmpty {
            result.append(AuroraChange(name: "активные ступени DPI", writes: selectionWrites))
        }
        result += try advanced.changes(for: proposed.advanced)
        guard proposed.buttons.count == buttons.count else {
            throw AiroxError.invalidSetting("Нужно указать назначения для шести кнопок.")
        }
        let leftClick = ButtonAction(0x10, 0x01)
        guard !settings.buttons.contains(leftClick) || proposed.buttons.contains(leftClick) else {
            throw AiroxError.invalidSetting("Оставьте левый щелчок хотя бы на одной кнопке Aurora.")
        }
        let edited = proposed.buttons.indices.filter { proposed.buttons[$0] != settings.buttons[$0] }
        let newLeftClicks = edited.filter { proposed.buttons[$0] == leftClick }
        let remaining = edited.filter { proposed.buttons[$0] != leftClick }
        for index in newLeftClicks + remaining {
            let action = proposed.buttons[index]
            guard let record = AuroraButtons.record(for: action) else {
                throw AiroxError.invalidSetting("Выберите доступное назначение кнопки.")
            }
            var writes: [AuroraWrite] = []
            if let shortcut = AuroraButtons.shortcut(for: action) {
                guard let previous = shortcuts[index], previous.count >= shortcut.count else {
                    throw AiroxError.invalidReply("сочетание клавиш")
                }
                writes.append(AuroraWrite(address: AuroraButtons.shortcutAddress(index),
                                          original: Array(previous.prefix(shortcut.count)), updated: shortcut))
            }
            writes.append(AuroraWrite(address: AuroraButtons.slotAddress(index),
                                      original: buttons[index], updated: record))
            let name = MouseModel.aurora.buttonName(at: index)
            result.append(AuroraChange(name: name, writes: writes))
        }
        return result
    }

    private func generalWrite(address: Int, value: [UInt8]) -> AuroraWrite {
        AuroraWrite(address: address, original: Array(general[address..<(address + value.count)]), updated: value)
    }
}
