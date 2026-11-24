import CHID
import Foundation

extension AuroraController {
    static let onboardProfileCount = 4

    func onboardProfile(on route: AuroraHIDRoute) throws -> Int? {
        try withDevice(on: route) { try readOnboardProfile($0) }
    }

    func selectOnboardProfile(_ index: Int, on route: AuroraHIDRoute) throws -> Int {
        guard (0..<Self.onboardProfileCount).contains(index) else {
            throw AiroxError.invalidSetting("Выберите профиль от 1 до 4.")
        }
        return try withDevice(on: route) { device in
            guard let current = try readOnboardProfile(device) else {
                throw AiroxError.invalidSetting("Прошивка этой Aurora не поддерживает встроенные профили.")
            }
            if current == index { return index }

            do {
                // The first two argument bytes are the unused flash address.
                _ = try command(0x0f, arguments: [0, 0, 1, UInt8(index)], on: device)
            } catch AiroxError.noAuroraReply {
                // Some firmware switches profiles before acknowledging the write.
            }
            for attempt in 0..<3 {
                if attempt > 0 { Thread.sleep(forTimeInterval: 0.15) }
                if (try? readOnboardProfile(device)) == index { return index }
            }
            throw AiroxError.unconfirmed("активный профиль Aurora")
        }
    }

    private func readOnboardProfile(_ device: OpaquePointer) throws -> Int? {
        let reply = try command(0x0e, allowUnsupported: true, on: device)
        if reply[1] == 1 { return nil }
        let index = Int(reply[5])
        guard (0..<Self.onboardProfileCount).contains(index) else {
            throw AiroxError.invalidReply("активный профиль Aurora")
        }
        return index
    }
}
