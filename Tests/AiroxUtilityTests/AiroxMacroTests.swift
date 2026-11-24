import Testing
@testable import AiroxUtility

@Test func airoxMacroEncodesReportsAndButtonAssignment() throws {
    let macro = MouseMacro(name: "Example", events: [
        MouseMacroEvent(kind: .modifier, value: 8, pressed: true, delayMs: 1),
        MouseMacroEvent(kind: .key, value: 4, pressed: true, delayMs: 300),
        MouseMacroEvent(kind: .key, value: 4, pressed: false, delayMs: 1),
        MouseMacroEvent(kind: .modifier, value: 8, pressed: false, delayMs: 0),
        MouseMacroEvent(kind: .mouse, value: 16, pressed: true, delayMs: 1),
        MouseMacroEvent(kind: .mouse, value: 16, pressed: false, delayMs: 0),
    ])
    let reports = try AiroxMacroMemory.packets(for: macro, button: 4)
    let report = try #require(reports.first)
    #expect(reports.count == 1)
    #expect(report.prefix(5) == [0x08, 0, 1, 25, 4])
    #expect(report[5..<29] == [0x20, 1, 0, 8, 0x30, 44, 1, 4, 0xb0, 1, 0, 4,
                              0xa0, 0, 0, 8, 0x10, 1, 0, 16, 0x90, 0, 0, 16])
    #expect(report[31] == AiroxWrite.checksum(report))

    let assignment = try #require(ButtonAction.airoxMacro(button: 4, repeat: .times(5)))
    #expect(assignment.bytes == [0x90, 0x24, 5])
    #expect(assignment.airoxMacroAssignment?.button == 4)
    #expect(assignment.airoxMacroAssignment?.repeat == .times(5))
    #expect(ButtonAction.airoxMacro(button: 4, repeat: .whileHeld)?.bytes == [0x90, 0x14, 0])
    #expect(ButtonAction.airoxMacro(button: 4, repeat: .untilAnyPressed)?.bytes == [0x90, 0x44, 0])
    #expect(ButtonAction.airoxMacro(button: 4, repeat: .untilPressedAgain) == nil)
}

@Test func airoxMacroChunksContinuousPayloadWithEachPacketLength() throws {
    let event = MouseMacroEvent(kind: .key, value: 4, pressed: true, delayMs: 500)
    let macro = MouseMacro(name: "Example", events: Array(repeating: event, count: 7))
    let packets = try AiroxMacroMemory.packets(for: macro, button: 5)
    #expect(packets.map { Array($0.prefix(4)) } == [[0x08, 0, 0x02, 27], [0x08, 0, 0x12, 2]])
    #expect(packets[1][4..<6] == [1, 4])
    #expect(packets[1][6..<31].allSatisfy { $0 == 0 })

    let tooLong = MouseMacro(name: "Example", events: Array(repeating: event, count: 102))
    #expect(throws: AiroxError.self) { try AiroxMacroMemory.packets(for: tooLong, button: 5) }
}
