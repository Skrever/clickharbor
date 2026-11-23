import CHID
import Foundation

actor AiroxController {
    func isPresent() -> Bool { airox_hid_present() }
    func hasUnsupportedMouse() -> Bool { io_unsupported_mouse_present() }

    func read() throws -> AiroxSettings {
        try withDevice { try snapshot($0).settings }
    }

    func apply(from baseline: AiroxSettings, to draft: AiroxSettings) throws -> AiroxSettings {
        try withDevice { device in
            let current = try snapshot(device)
            let proposed = current.settings.mergingEdits(from: baseline, to: draft)
            let writes = try current.writes(for: proposed)
            for write in writes {
                let result = write.packet.withUnsafeBufferPointer { airox_hid_write(device, $0.baseAddress!) }
                guard result == 0 else { throw Self.transportError(result) }
                try verify(write, on: device)
            }
            let actual = try snapshot(device).settings
            guard actual == proposed else {
                throw AiroxError.unconfirmed("настройки мыши")
            }
            return actual
        }
    }

    private func withDevice<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        var status: Int32 = 0
        guard let device = airox_hid_open(&status) else { throw Self.transportError(status) }
        defer { airox_hid_close(device) }
        let identity = try readPage(.identity, on: device)
        guard identity.starts(with: [0x45, 0x30, 0x32, 0x35]), identity.count >= 7, identity[6] == 0x95 else {
            throw AiroxError.unsupported
        }
        return try operation(device)
    }

    private func snapshot(_ device: OpaquePointer) throws -> AiroxSnapshot {
        try AiroxSnapshot(
            dpi: readPage(.dpi, on: device),
            rate: readPage(.reportRate, on: device),
            power: readPage(.debounce, on: device),
            buttons: readPage(.buttons, on: device)
        )
    }

    private func readPage(_ page: AiroxPage, on device: OpaquePointer) throws -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 32)
        for _ in 0..<2 {
            let status = packet.withUnsafeMutableBufferPointer {
                airox_hid_query(device, page.query, $0.baseAddress!)
            }
            if status == AiroxHIDNoReply { continue }
            guard status == 0 else { throw Self.transportError(status) }
            if let payload = try? page.payload(from: packet), !payload.isEmpty { return payload }
        }
        throw AiroxError.invalidReply(page.name)
    }

    private func verify(_ write: AiroxWrite, on device: OpaquePointer) throws {
        for attempt in 0..<4 {
            if try readPage(write.page, on: device) == write.expectedPayload { return }
            if attempt < 3 { Thread.sleep(forTimeInterval: 0.12) }
        }
        throw AiroxError.unconfirmed(write.page.name)
    }

    private static func transportError(_ status: Int32) -> AiroxError {
        .transport(status, notFound: Int32(AiroxHIDNotFound), ambiguous: Int32(AiroxHIDAmbiguous))
    }
}
