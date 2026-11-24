import Testing
@testable import AiroxUtility

@Test func auroraMacroEncodesTheVendorEventLayout() throws {
    let macro = MouseMacro(name: "A", events: [
        MouseMacroEvent(kind: .key, value: 4, pressed: true, delayMs: 0),
        MouseMacroEvent(kind: .key, value: 4, pressed: false, delayMs: 300),
    ])
    let expected: [UInt8] = [1, 65] + Array(repeating: 0xff, count: 29) +
        [2, 0x81, 4, 0, 0, 0, 0x41, 4, 0, 1, 44, 0x5c]
    let encoded = try AuroraMacroMemory.encode(macro)
    #expect(encoded == expected)
    #expect(AuroraMacroMemory.decode(encoded) == macro)
    #expect(AuroraMacroMemory.decode(Array(encoded.dropLast()) + [0]) == nil)
}

@Test func auroraMacroRejectsDataBeyondOneSlot() throws {
    let event = MouseMacroEvent(kind: .menu, value: 1, pressed: true, delayMs: .max)
    let macro = MouseMacro(name: "A", events: Array(repeating: event, count: 70))
    #expect(try AuroraMacroMemory.encode(macro).count == 383)
    #expect(AuroraMacroMemory.address(of: 15) == 0x1980)
    #expect(AuroraMacroMemory.address(of: 16) == nil)
    #expect(throws: AiroxError.self) {
        try AuroraMacroMemory.encode(MouseMacro(name: "A", events: macro.events + [event]))
    }
}

@Test func auroraMacroAssignmentUsesTheSlotAndRepeatBytes() throws {
    let action = try #require(ButtonAction.auroraMacro(slot: 2, repeat: .whileHeld))
    let record: [UInt8] = [6, 2, 0xfe, 0x4f]
    #expect(AuroraMacroMemory.assignmentRecord(for: action) == record)
    #expect(AuroraMacroMemory.assignment(from: record) == action)
    #expect(action.auroraMacroAssignment?.repeat == .whileHeld)
    #expect(ButtonAction.auroraMacro(slot: 16, repeat: .times(1)) == nil)
    #expect(ButtonAction.auroraMacro(slot: 0, repeat: .times(251)) == nil)
}
