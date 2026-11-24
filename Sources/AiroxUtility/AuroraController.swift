import CHID
import Foundation

struct AuroraDeviceInfo: Sendable {
    var batteryPercent: Int? = nil
    var charging: Bool? = nil
    var firmwareVersion: String? = nil
    var receiverFirmwareVersion: String? = nil
    var canFactoryReset = false
}

actor AuroraController {
    func isPresent(on route: AuroraHIDRoute) -> Bool { aurora_hid_present(route) }

    func receiverIsResponsive() -> Bool {
        (try? withDevice(on: AuroraHIDReceiver) { device in
            let rate = try readBlock(device, address: AuroraMemory.rate, count: 2)
            return AuroraMemory.check(rate) && [1, 2, 4, 8].contains(rate[0])
        }) ?? false
    }

    func read(on route: AuroraHIDRoute) throws -> AiroxSettings {
        try withDevice(on: route) { try snapshot($0).settings }
    }

    func deviceInfo(on route: AuroraHIDRoute) throws -> AuroraDeviceInfo {
        try withDevice(on: route) { device in
            let battery = try? command(0x04, on: device)
            let mouseVersion = try? command(0x12, on: device)
            let receiverVersion = route == AuroraHIDReceiver ? try? command(0x1d, on: device) : nil
            let charging = battery.map { $0[6] == 1 }
            return AuroraDeviceInfo(
                batteryPercent: battery.map { Self.batteryPercent(from: $0) },
                charging: charging,
                firmwareVersion: mouseVersion.map { Self.firmwareVersion(from: $0) },
                receiverFirmwareVersion: receiverVersion.map { Self.firmwareVersion(from: $0) },
                canFactoryReset: aurora_hid_is_aurora_product(device)
            )
        }
    }

    func factoryReset(on route: AuroraHIDRoute) throws -> AiroxSettings {
        try withDevice(on: route) { device in
            guard aurora_hid_is_aurora_product(device) else {
                throw AiroxError.invalidSetting("Устройство не распознано как IO Aurora для заводского сброса.")
            }
            do {
                _ = try command(0x09, timeoutMilliseconds: 6000, on: device)
            } catch AiroxError.noAuroraReply {
                throw AiroxError.unconfirmed("заводской сброс Aurora")
            }
            return try snapshot(device).settings
        }
    }

    private static func firmwareVersion(from bytes: [UInt8]) -> String {
        String(format: "v%d.%02x", Int(bytes[5]), Int(bytes[6]))
    }

    private static func batteryPercent(from bytes: [UInt8]) -> Int {
        if bytes[9] == 1 { return min(100, Int(bytes[10])) }
        let percentage = min(100, Int(bytes[5]))
        let millivolts = (Int(bytes[7]) << 8) | Int(bytes[8])
        guard percentage == 0, bytes[6] != 1, millivolts > 0 else { return percentage }

        let curve = [3050, 3170, 3230, 3300, 3600, 3660, 3720, 3760, 3800, 3840, 3880, 3920,
                     3940, 3960, 3980, 4000, 4020, 4040, 4060, 4080, 4110]
        guard millivolts > curve[0] else { return 0 }
        guard let upper = curve.firstIndex(where: { $0 >= millivolts }) else { return 100 }
        let lower = upper - 1
        let fraction = Double(millivolts - curve[lower]) / Double(curve[upper] - curve[lower])
        return Int(((Double(lower) + fraction) * 5).rounded())
    }

    func apply(from baseline: AiroxSettings, to draft: AiroxSettings, on route: AuroraHIDRoute) throws -> AiroxSettings {
        try withDevice(on: route) { device in
            let editedShortcuts = Set(draft.buttons.indices.filter {
                baseline.buttons.indices.contains($0) &&
                baseline.buttons[$0] != draft.buttons[$0] &&
                AuroraButtons.shortcut(for: draft.buttons[$0]) != nil
            })
            let current = try snapshot(device, editedShortcuts: editedShortcuts)
            let proposed = current.settings.mergingEdits(from: baseline, to: draft)
            let changes = try current.changes(for: proposed)
            for index in proposed.buttons.indices where proposed.buttons[index] != current.settings.buttons[index] {
                if let slot = proposed.buttons[index].auroraMacroAssignment?.slot,
                   try readMacro(in: slot, on: device) == nil {
                    throw AiroxError.invalidSetting("В ячейке \(slot + 1) нет сохранённого макроса.")
                }
            }
            for change in changes {
                try commit(change, on: device)
            }
            let actual = try snapshot(device).settings
            guard actual == proposed else { throw AiroxError.unconfirmed("настройки мыши") }
            return actual
        }
    }

    func withDevice<T>(on route: AuroraHIDRoute, _ operation: (OpaquePointer) throws -> T) throws -> T {
        var status: Int32 = 0
        guard let device = aurora_hid_open(route, &status) else { throw Self.transportError(status) }
        defer { aurora_hid_close(device) }
        do {
            return try operation(device)
        } catch AiroxError.noAuroraReply where route == AuroraHIDReceiver {
            throw AiroxError.receiverNoReply
        }
    }

    private func snapshot(_ device: OpaquePointer, editedShortcuts: Set<Int> = []) throws -> AuroraSnapshot {
        let general = try readBlock(device, address: 0, count: AuroraAdvancedSnapshot.generalLength)
        let sensor = try readBlock(device, address: AuroraMemory.debounce, count: AuroraAdvancedSnapshot.sensorLength)
        let debounce = Array(sensor.prefix(2))
        let buttons = try readBlock(device, address: AuroraMemory.buttons, count: AuroraButtons.count * 4)
        let records = stride(from: 0, to: buttons.count, by: 4).map { Array(buttons[$0..<($0 + 4)]) }
        var shortcuts: [Int: [UInt8]] = [:]
        for index in records.indices where records[index][0] == AuroraButtons.shortcutKind || editedShortcuts.contains(index) {
            shortcuts[index] = try readBlock(device, address: AuroraButtons.shortcutAddress(index),
                                             count: AuroraMemory.shortcutLength)
        }
        return try AuroraSnapshot(general: general, debounce: debounce, buttons: records, shortcuts: shortcuts,
                                  sensor: sensor)
    }

    func readBlock(_ device: OpaquePointer, address: Int, count: Int) throws -> [UInt8] {
        var block = [UInt8](repeating: 0, count: count)
        for offset in stride(from: 0, to: count, by: 10) {
            let length = min(10, count - offset)
            let status = block.withUnsafeMutableBufferPointer {
                aurora_hid_read(device, UInt16(address + offset), UInt8(length), $0.baseAddress!.advanced(by: offset))
            }
            if status == AiroxHIDNoReply { throw AiroxError.noAuroraReply }
            guard status == 0 else { throw Self.transportError(status) }
        }
        return block
    }

    func command(_ opcode: UInt8, arguments: [UInt8] = [], timeoutMilliseconds: UInt32 = 350,
                 allowUnsupported: Bool = false, on device: OpaquePointer) throws -> [UInt8] {
        guard arguments.count <= 13 else { throw AiroxError.invalidSetting("Слишком длинная команда Aurora.") }
        var reply = [UInt8](repeating: 0, count: 17)
        let status = arguments.withUnsafeBufferPointer { arguments in
            reply.withUnsafeMutableBufferPointer { reply in
                aurora_hid_command(device, opcode, UInt8(arguments.count), arguments.baseAddress,
                                   timeoutMilliseconds, reply.baseAddress)
            }
        }
        if status == AiroxHIDNoReply { throw AiroxError.noAuroraReply }
        guard status == 0 else { throw Self.transportError(status) }
        guard reply[2] == 0 || (allowUnsupported && reply[2] == 1) else {
            throw AiroxError.invalidReply("команда Aurora \(opcode)")
        }
        return Array(reply.dropFirst())
    }

    func commit(_ change: AuroraChange, on device: OpaquePointer) throws {
        var attempted: [AuroraWrite] = []
        do {
            for write in change.writes {
                attempted.append(write)
                try writeAndVerify(write.updated, address: write.address, name: change.name, on: device)
            }
        } catch {
            var recovered = true
            for write in attempted.reversed() {
                if (try? readBlock(device, address: write.address, count: write.original.count)) == write.original {
                    continue
                }
                do {
                    try writeAndVerify(write.original, address: write.address, name: change.name, on: device)
                } catch {
                    recovered = false
                }
            }
            guard recovered else { throw AiroxError.recoveryFailed(change.name) }
            throw error
        }
    }

    private func writeAndVerify(_ bytes: [UInt8], address: Int, name: String, on device: OpaquePointer) throws {
        for offset in stride(from: 0, to: bytes.count, by: 10) {
            let length = min(10, bytes.count - offset)
            let status = bytes.withUnsafeBufferPointer {
                aurora_hid_write(device, UInt16(address + offset), UInt8(length), $0.baseAddress!.advanced(by: offset))
            }
            guard status == 0 else { throw Self.transportError(status) }
        }
        for attempt in 0..<3 {
            if (try? readBlock(device, address: address, count: bytes.count)) == bytes { return }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.06) }
        }
        throw AiroxError.unconfirmed(name)
    }

    private static func transportError(_ status: Int32) -> AiroxError {
        .transport(status, notFound: Int32(AiroxHIDNotFound), ambiguous: Int32(AiroxHIDAmbiguous))
    }
}
