import Foundation

struct MouseMacroEvent: Codable, Equatable, Sendable {
    enum Kind: UInt8, Codable, CaseIterable, Sendable {
        case modifier = 0
        case key = 1
        case mouse = 4
        case menu = 7
    }

    var kind: Kind
    var value: UInt16
    var pressed: Bool
    var delayMs: UInt16
}

struct MouseMacro: Codable, Equatable, Sendable {
    var name: String
    var events: [MouseMacroEvent]
}

enum MouseMacroRepeat: Codable, Equatable, Sendable {
    case times(Int)
    case whileHeld
    case untilPressedAgain
    case untilAnyPressed
}

enum AuroraMacroMemory {
    static let slotCount = 16
    static let slotLength = 384
    static let headerLength = 32
    static let maximumNameLength = 30
    static let maximumEventCount = 70

    private static let firstAddress = 768
    private static let eventLength = 5
    private static let eventCountOffset = headerLength - 1
    private static let maximumRepeats = 250
    private static let assignmentKind: UInt8 = 6
    private static let kindMask: UInt8 = 0x0f

    static func address(of slot: Int) -> Int? {
        guard (0..<slotCount).contains(slot) else { return nil }
        return firstAddress + slotLength * slot
    }

    static func encodedLength(header: [UInt8]) -> Int? {
        guard header.count >= headerLength,
              (1...maximumNameLength).contains(Int(header[0])) else { return nil }
        let eventCount = Int(header[eventCountOffset])
        guard (1...maximumEventCount).contains(eventCount) else { return nil }
        return headerLength + eventLength * eventCount + 1
    }

    static func encode(_ macro: MouseMacro) throws -> [UInt8] {
        let name = Array(macro.name.utf8)
        guard (1...maximumNameLength).contains(name.count) else {
            throw AiroxError.invalidSetting("Укажите имя макроса длиной до 30 байт UTF-8.")
        }
        guard (1...maximumEventCount).contains(macro.events.count) else {
            throw AiroxError.invalidSetting("Макрос должен содержать от 1 до 70 событий.")
        }
        var bytes = [UInt8](repeating: 0xff, count: headerLength)
        bytes[0] = UInt8(name.count)
        bytes.replaceSubrange(1..<(1 + name.count), with: name)
        bytes[eventCountOffset] = UInt8(macro.events.count)
        for event in macro.events {
            let direction: UInt8 = event.pressed ? 0x80 : 0x40
            bytes.append(direction | event.kind.rawValue)
            bytes.append(UInt8(truncatingIfNeeded: event.value))
            bytes.append(UInt8(event.value >> 8))
            bytes.append(UInt8(event.delayMs >> 8))
            bytes.append(UInt8(truncatingIfNeeded: event.delayMs))
        }
        bytes.append(AuroraMemory.sumByte(Array(bytes[eventCountOffset...])))
        return bytes
    }

    static func decode(_ bytes: [UInt8]) -> MouseMacro? {
        guard let length = encodedLength(header: bytes), bytes.count >= length,
              AuroraMemory.check(Array(bytes[eventCountOffset..<length])),
              let name = String(bytes: bytes[1..<(1 + Int(bytes[0]))], encoding: .utf8) else { return nil }

        var events: [MouseMacroEvent] = []
        for offset in stride(from: headerLength, to: length - 1, by: eventLength) {
            let flags = bytes[offset]
            let direction = flags & 0xf0
            guard direction == 0x80 || direction == 0x40,
                  let kind = MouseMacroEvent.Kind(rawValue: flags & kindMask) else { return nil }
            let value = UInt16(bytes[offset + 1]) | UInt16(bytes[offset + 2]) << 8
            let delay = UInt16(bytes[offset + 3]) << 8 | UInt16(bytes[offset + 4])
            events.append(MouseMacroEvent(kind: kind, value: value, pressed: direction == 0x80, delayMs: delay))
        }
        return MouseMacro(name: name, events: events)
    }

    static func assignmentRecord(for action: ButtonAction) -> [UInt8]? {
        guard action.auroraMacroAssignment != nil else { return nil }
        let bytes = [assignmentKind, action.first, action.second]
        return bytes + [AuroraMemory.sumByte(bytes)]
    }

    static func assignment(from record: [UInt8]) -> ButtonAction? {
        guard record.count == 4, record[0] == assignmentKind, AuroraMemory.check(record),
              let mode = repeatMode(record[2]) else { return nil }
        return ButtonAction.auroraMacro(slot: Int(record[1]), repeat: mode)
    }

    static func repeatByte(_ rule: MouseMacroRepeat) -> UInt8? {
        switch rule {
        case .times(let count):
            guard (1...maximumRepeats).contains(count) else { return nil }
            return UInt8(count)
        case .whileHeld: return 0xfe
        case .untilPressedAgain: return 0xfd
        case .untilAnyPressed: return 0xff
        }
    }

    static func repeatMode(_ byte: UInt8) -> MouseMacroRepeat? {
        switch byte {
        case 1...UInt8(maximumRepeats): .times(Int(byte))
        case 0xfe: .whileHeld
        case 0xfd: .untilPressedAgain
        case 0xff: .untilAnyPressed
        default: nil
        }
    }
}

extension ButtonAction {
    private static let auroraMacroKind: UInt8 = 0x7e

    static func auroraMacro(slot: Int, repeat rule: MouseMacroRepeat) -> ButtonAction? {
        guard AuroraMacroMemory.address(of: slot) != nil,
              let repeatByte = AuroraMacroMemory.repeatByte(rule) else { return nil }
        return ButtonAction(Self.auroraMacroKind, UInt8(slot), repeatByte)
    }

    var auroraMacroAssignment: (slot: Int, repeat: MouseMacroRepeat)? {
        guard kind == Self.auroraMacroKind, AuroraMacroMemory.address(of: Int(first)) != nil,
              let rule = AuroraMacroMemory.repeatMode(second) else { return nil }
        return (Int(first), rule)
    }
}
