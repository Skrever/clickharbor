enum AiroxMacroMemory {
    static let buttonCount = 6
    static let maximumRepeats = 255
    static let maximumEventCount = 101

    private static let chunkSize = 27

    static func packets(for macro: MouseMacro, button: Int) throws -> [[UInt8]] {
        guard (0..<buttonCount).contains(button) else {
            throw AiroxError.invalidSetting("Выберите кнопку для запуска макроса.")
        }
        guard (1...maximumEventCount).contains(macro.events.count) else {
            throw AiroxError.invalidSetting("Макрос Airox должен содержать от 1 до 101 события.")
        }
        let data = [UInt8(button)] + (try macro.events.flatMap(eventBytes))
        let chunkCount = (data.count + chunkSize - 1) / chunkSize

        return (0..<chunkCount).map { index in
            let start = index * chunkSize
            let end = min(start + chunkSize, data.count)
            let sequence = UInt8(index << 4 | chunkCount)
            var packet: [UInt8] = [0x08, 0, sequence, UInt8(end - start)]
            packet += data[start..<end]
            packet += Array(repeating: 0, count: 32 - packet.count)
            packet[31] = AiroxWrite.checksum(packet)
            return packet
        }
    }

    private static func eventBytes(_ event: MouseMacroEvent) throws -> [UInt8] {
        let code: UInt8
        switch event.kind {
        case .mouse where [1, 2, 4, 8, 16].contains(event.value): code = 0x10
        case .modifier where event.value <= 0xff && event.value.nonzeroBitCount == 1: code = 0x20
        case .key where (4..<0xe0).contains(event.value): code = 0x30
        default:
            throw AiroxError.invalidSetting("Airox поддерживает в макросах кнопки мыши и клавиши.")
        }
        return [event.pressed ? code : code | 0x80,
                UInt8(truncatingIfNeeded: event.delayMs), UInt8(event.delayMs >> 8), UInt8(event.value)]
    }
}

extension ButtonAction {
    static func airoxMacro(button: Int, repeat rule: MouseMacroRepeat) -> Self? {
        guard (0..<AiroxMacroMemory.buttonCount).contains(button) else { return nil }
        let button = UInt8(button)
        switch rule {
        case .times(let count):
            guard (1...AiroxMacroMemory.maximumRepeats).contains(count) else { return nil }
            return Self(0x90, button | 0x20, UInt8(count))
        case .whileHeld: return Self(0x90, button | 0x10)
        case .untilAnyPressed: return Self(0x90, button | 0x40)
        case .untilPressedAgain: return nil
        }
    }

    var airoxMacroAssignment: (button: Int, repeat: MouseMacroRepeat)? {
        guard kind == 0x90 else { return nil }
        let button = Int(first & 0x0f)
        guard (0..<AiroxMacroMemory.buttonCount).contains(button) else { return nil }
        switch first & 0xf0 {
        case 0x10: return (button, .whileHeld)
        case 0x20 where second > 0: return (button, .times(Int(second)))
        case 0x40: return (button, .untilAnyPressed)
        default: return nil
        }
    }
}
