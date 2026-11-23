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

@MainActor
final class AiroxModel: ObservableObject {
    @Published var draft: AiroxSettings?
    @Published private(set) var busy = false
    @Published private(set) var status = "Поиск мыши"
    @Published private(set) var error: String?
    @Published private(set) var selected: MouseConnection?
    @Published private(set) var available: [MouseConnection] = []
    @Published private(set) var unsupportedMousePresent = false

    private let airox = AiroxController()
    private let aurora = AuroraController()
    private var baseline: AiroxSettings?

    var deviceName: String { selected?.model.rawValue ?? "ClickHarbor" }
    var connected: Bool { baseline != nil }
    var hasChanges: Bool { connected && draft != baseline }
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
    }
}
