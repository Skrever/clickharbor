import CHID
import Foundation

enum AuroraPairingResult: Equatable, Sendable {
    case paired
    case notFound
    case timedOut
    case unconfirmed
}

extension AuroraController {
    func pairReceiver(on route: AuroraHIDRoute,
                      onProgress: (@Sendable (Int?) -> Void)? = nil) throws -> AuroraPairingResult {
        guard route == AuroraHIDReceiver else {
            throw AiroxError.invalidSetting("Подключите приёмник Aurora для сопряжения.")
        }
        return try withDevice(on: route) { device in
            guard aurora_hid_is_pairable_receiver(device) else {
                throw AiroxError.invalidSetting("Устройство не распознано как приёмник Aurora.")
            }
            try Task.checkCancellation()
            do {
                // The receiver expects the model family byte even though the declared length is two.
                let start = try command(0x05, arguments: [0, 0, 2, 0, 0, 26],
                                        allowUnsupported: true, on: device)
                guard start[1] == 0 else { return .unconfirmed }
                onProgress?(nil)

                let deadline = ContinuousClock.now + .seconds(20)
                while ContinuousClock.now < deadline {
                    try Task.checkCancellation()
                    Thread.sleep(forTimeInterval: 1)
                    let state = try command(0x06, allowUnsupported: true, on: device)
                    guard state[1] == 0 else { return .unconfirmed }
                    switch state[5] {
                    case 1:
                        let remaining = Int(state[6])
                        onProgress?((1...20).contains(remaining) ? remaining : nil)
                    case 2:
                        return .notFound
                    case 3:
                        return try confirmPairedReceiver(device)
                    default:
                        return .unconfirmed
                    }
                }
                return .timedOut
            } catch AiroxError.noAuroraReply {
                return .unconfirmed
            }
        }
    }

    private func confirmPairedReceiver(_ device: OpaquePointer) throws -> AuroraPairingResult {
        for attempt in 0..<3 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.20) }
            try Task.checkCancellation()
            let online = try command(0x03, allowUnsupported: true, on: device)
            if online[1] == 1 || online[5] == 1 { return .paired }
        }
        return .unconfirmed
    }
}
