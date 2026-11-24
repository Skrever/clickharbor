import Combine
import Foundation
import CHID

enum MouseConnection: CaseIterable, Sendable {
    case airoxCable
    case auroraCable
    case auroraReceiver

    var model: MouseModel { self == .airoxCable ? .airox : .aurora }

    var menuLabel: String {
        switch self {
        case .airoxCable: "IO Airox · USB"
        case .auroraCable: "IO Aurora · USB"
        case .auroraReceiver: "IO Aurora · 2,4 ГГц"
        }
    }
}

struct MouseDeviceDetails {
    let batteryPercent: Int?
    let charging: Bool?
    let firmwareVersion: String?
    let receiverFirmwareVersion: String?
    var canFactoryReset = false
}

@MainActor
final class AiroxModel: ObservableObject {
    @Published var draft: AiroxSettings?
    @Published private(set) var busy = false
    @Published private(set) var status = "Поиск мыши"
    @Published private(set) var error: String?
    @Published private(set) var selected: MouseConnection?
    @Published private(set) var available: [MouseConnection] = []
    @Published private(set) var unsupportedMousePresent = false
    @Published private(set) var deviceMacros: [MouseMacro?]?
    @Published private(set) var deviceDetails: MouseDeviceDetails?
    @Published private(set) var onboardProfile: Int?

    private let airox = AiroxController()
    private let aurora = AuroraController()
    private var baseline: AiroxSettings?

    var deviceName: String { selected?.model.rawValue ?? "ClickHarbor" }
    var connected: Bool { baseline != nil }
    var hasChanges: Bool { connected && draft != baseline }
    var canPairReceiver: Bool { selected == .auroraReceiver }
    private var auroraRoute: AuroraHIDRoute? {
        switch selected {
        case .auroraCable: AuroraHIDCable
        case .auroraReceiver: AuroraHIDReceiver
        default: nil
        }
    }
    var connectionStatus: String {
        if selected == .auroraReceiver {
            return connected ? "Подключена по 2,4 ГГц" : "Приёмник 2,4 ГГц подключён"
        }
        return connected ? "Подключена по USB" : "Ожидание подключения"
    }

    func watchConnection() async {
        refresh()
        var nextReceiverCheck = ContinuousClock.now
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !busy else { continue }
            let present = await scan()
            guard !busy else { continue }
            if present != available {
                available = present
                if let selected, present.contains(selected) { continue }
                refresh()
            } else if !connected, selected == .auroraReceiver, ContinuousClock.now >= nextReceiverCheck {
                nextReceiverCheck = ContinuousClock.now.advanced(by: .seconds(6))
                if await aurora.receiverIsResponsive(), !busy, selected == .auroraReceiver, !connected {
                    refresh()
                }
            }
        }
    }

    func select(_ connection: MouseConnection) {
        guard !busy, connection != selected, available.contains(connection) else { return }
        selected = connection
        clearSettings()
        refresh()
    }

    func refresh() {
        guard !busy else { return }
        busy = true
        error = nil
        status = "Чтение настроек…"
        Task {
            defer { busy = false }
            available = await scan()
            if let selected, !available.contains(selected) {
                self.selected = nil
                clearSettings()
            }
            selected = selected ?? available.first
            guard let selected else {
                clearSettings()
                status = "Мышь отключена"
                return
            }
            do {
                let settings = try await read(selected)
                baseline = settings
                draft = settings
                status = "Настройки считаны с мыши"
            } catch {
                clearSettings()
                self.error = error.localizedDescription
                status = "Настройки недоступны"
            }
        }
    }

    func apply() {
        guard !busy, hasChanges, let selected, let baseline, let draft else { return }
        busy = true
        error = nil
        status = "Запись и проверка…"
        Task {
            defer { busy = false }
            do {
                let actual: AiroxSettings
                switch selected {
                case .airoxCable: actual = try await airox.apply(from: baseline, to: draft)
                case .auroraCable: actual = try await aurora.apply(from: baseline, to: draft, on: AuroraHIDCable)
                case .auroraReceiver: actual = try await aurora.apply(from: baseline, to: draft, on: AuroraHIDReceiver)
                }
                self.baseline = actual
                self.draft = actual
                status = "Настройки сохранены в мыши"
            } catch {
                let message = error.localizedDescription
                if let actual = try? await read(selected) {
                    self.baseline = actual
                    self.draft = actual.mergingEdits(from: baseline, to: draft)
                    status = "Текущие значения считаны с мыши"
                } else {
                    clearSettings()
                    status = "Настройки недоступны"
                }
                self.error = message
            }
        }
    }

    func readDeviceMacros() {
        guard let route = auroraRoute else { return }
        operate("Чтение макросов…", done: "Макросы считаны с мыши") {
            self.deviceMacros = try await self.aurora.readMacros(on: route)
        }
    }

    func saveDeviceMacro(_ macro: MouseMacro, slot: Int) {
        guard let route = auroraRoute else { return }
        operate("Запись макроса…", done: "Макрос сохранён в мыши") {
            try await self.aurora.writeMacro(macro, to: slot, on: route)
            self.deviceMacros?[slot] = macro
        }
    }

    func eraseDeviceMacro(slot: Int) {
        guard let route = auroraRoute else { return }
        operate("Удаление макроса…", done: "Макрос удалён из мыши") {
            guard self.draft?.buttons.contains(where: { $0.auroraMacroAssignment?.slot == slot }) != true else {
                throw AiroxError.invalidSetting("Сначала измените назначение кнопки, которая запускает этот макрос.")
            }
            try await self.aurora.eraseMacro(in: slot, on: route)
            self.deviceMacros?[slot] = nil
        }
    }

    func assignAuroraMacro(slot: Int, button: Int, rule: MouseMacroRepeat) {
        guard let macros = deviceMacros, macros.indices.contains(slot), macros[slot] != nil,
              draft?.buttons.indices.contains(button) == true,
              let action = ButtonAction.auroraMacro(slot: slot, repeat: rule) else { return }
        draft?.buttons[button] = action
    }

    func installAiroxMacro(_ macro: MouseMacro, button: Int, rule: MouseMacroRepeat) {
        guard selected == .airoxCable, !hasChanges else { return }
        operate("Запись макроса и назначения…", done: "Макрос назначен на кнопку") {
            let actual = try await self.airox.writeMacro(macro, to: button, repeat: rule)
            self.baseline = actual
            self.draft = actual
        }
    }

    func readDeviceDetails() {
        guard let selected else { return }
        operate("Чтение сведений об устройстве…", done: "Сведения об устройстве обновлены") {
            if let route = self.auroraRoute {
                let info = try await self.aurora.deviceInfo(on: route)
                self.deviceDetails = MouseDeviceDetails(batteryPercent: info.batteryPercent, charging: info.charging,
                                                        firmwareVersion: info.firmwareVersion,
                                                        receiverFirmwareVersion: info.receiverFirmwareVersion,
                                                        canFactoryReset: info.canFactoryReset)
                self.onboardProfile = try? await self.aurora.onboardProfile(on: route)
            } else if selected == .airoxCable {
                let info = try await self.airox.deviceInfo()
                self.deviceDetails = MouseDeviceDetails(batteryPercent: info.batteryPercent, charging: info.charging,
                                                        firmwareVersion: info.firmwareVersion, receiverFirmwareVersion: nil)
            }
        }
    }

    func switchOnboardProfile(_ profile: Int) {
        guard let route = auroraRoute, onboardProfile != nil, !hasChanges else { return }
        operate("Переключение профиля…", done: "Профиль мыши переключён") {
            do {
                self.onboardProfile = try await self.aurora.selectOnboardProfile(profile, on: route)
                let actual = try await self.aurora.read(on: route)
                self.baseline = actual
                self.draft = actual
                self.deviceMacros = nil
            } catch {
                self.clearSettings()
                if let actual = try? await self.aurora.read(on: route) {
                    self.baseline = actual
                    self.draft = actual
                }
                throw error
            }
        }
    }

    func resetAurora() {
        guard let route = auroraRoute, deviceDetails?.canFactoryReset == true else { return }
        operate("Восстановление заводских настроек…", done: "Заводские настройки считаны с Aurora") {
            self.clearSettings()
            do {
                let actual = try await self.aurora.factoryReset(on: route)
                self.baseline = actual
                self.draft = actual
            } catch {
                if let actual = try? await self.aurora.read(on: route) {
                    self.baseline = actual
                    self.draft = actual
                }
                throw error
            }
        }
    }

    func pairAurora() {
        guard canPairReceiver else { return }
        operate("Поиск мыши для сопряжения…", done: "Aurora сопряжена с приёмником", requiresSettings: false) {
            self.clearSettings()
            let result = try await self.aurora.pairReceiver(on: AuroraHIDReceiver) { [weak self] remaining in
                Task { @MainActor in
                    guard let self, self.busy, self.canPairReceiver, let remaining else { return }
                    self.status = "Поиск мыши · ещё \(remaining) с"
                }
            }
            switch result {
            case .paired:
                let actual = try await self.aurora.read(on: AuroraHIDReceiver)
                self.baseline = actual
                self.draft = actual
            case .notFound, .timedOut:
                throw AiroxError.invalidSetting("Приёмник не нашёл Aurora в режиме сопряжения.")
            case .unconfirmed:
                throw AiroxError.unconfirmed("сопряжение Aurora")
            }
        }
    }

    private func operate(_ message: String, done: String, requiresSettings: Bool = true,
                         task: @escaping () async throws -> Void) {
        guard !busy, !requiresSettings || connected else { return }
        busy = true
        error = nil
        status = message
        Task {
            defer { busy = false }
            do {
                try await task()
                status = done
            } catch {
                self.error = error.localizedDescription
                status = "Операция не выполнена"
            }
        }
    }

    private func scan() async -> [MouseConnection] {
        var connections: [MouseConnection] = []
        if await airox.isPresent() { connections.append(.airoxCable) }
        if await aurora.isPresent(on: AuroraHIDCable) { connections.append(.auroraCable) }
        if await aurora.isPresent(on: AuroraHIDReceiver) { connections.append(.auroraReceiver) }
        let unsupported = await airox.hasUnsupportedMouse()
        if unsupported != unsupportedMousePresent { unsupportedMousePresent = unsupported }
        return connections
    }

    private func read(_ connection: MouseConnection) async throws -> AiroxSettings {
        switch connection {
        case .airoxCable: try await airox.read()
        case .auroraCable: try await aurora.read(on: AuroraHIDCable)
        case .auroraReceiver: try await aurora.read(on: AuroraHIDReceiver)
        }
    }

    private func clearSettings() {
        baseline = nil
        draft = nil
        deviceMacros = nil
        deviceDetails = nil
        onboardProfile = nil
    }
}
