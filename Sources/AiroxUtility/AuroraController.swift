import CHID
import Foundation

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

    func apply(from baseline: AiroxSettings, to draft: AiroxSettings, on route: AuroraHIDRoute) throws -> AiroxSettings {
        try withDevice(on: route) { device in
            let editedShortcuts = Set(draft.buttons.indices.filter {
                baseline.buttons.indices.contains($0) &&
                baseline.buttons[$0] != draft.buttons[$0] &&
                AuroraButtons.shortcut(for: draft.buttons[$0]) != nil
            })
            let current = try snapshot(device, editedShortcuts: editedShortcuts)
            let proposed = current.settings.mergingEdits(from: baseline, to: draft)
            for change in try current.changes(for: proposed) {
                try commit(change, on: device)
            }
            let actual = try snapshot(device).settings
            guard actual == proposed else { throw AiroxError.unconfirmed("настройки мыши") }
            return actual
        }
    }

    private func withDevice<T>(on route: AuroraHIDRoute, _ operation: (OpaquePointer) throws -> T) throws -> T {
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
        let general = try readBlock(device, address: 0, count: AuroraMemory.dpiTable + 4 * 4)
        let debounce = try readBlock(device, address: AuroraMemory.debounce, count: 2)
        let buttons = try readBlock(device, address: AuroraMemory.buttons, count: AuroraButtons.count * 4)
        let records = stride(from: 0, to: buttons.count, by: 4).map { Array(buttons[$0..<($0 + 4)]) }
        var shortcuts: [Int: [UInt8]] = [:]
        for index in records.indices where records[index][0] == AuroraButtons.shortcutKind || editedShortcuts.contains(index) {
            shortcuts[index] = try readBlock(device, address: AuroraButtons.shortcutAddress(index),
                                             count: AuroraMemory.shortcutLength)
        }
        return try AuroraSnapshot(general: general, debounce: debounce, buttons: records, shortcuts: shortcuts)
    }

    private func readBlock(_ device: OpaquePointer, address: Int, count: Int) throws -> [UInt8] {
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

    private func commit(_ change: AuroraChange, on device: OpaquePointer) throws {
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
