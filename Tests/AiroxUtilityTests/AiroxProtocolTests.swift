import Testing
@testable import AiroxUtility

private func example() throws -> AiroxSnapshot {
    try AiroxSnapshot(
        dpi: [0x46, 15, 0, 15, 0, 31, 0, 31, 0, 47, 0, 47, 0, 63, 0, 63, 0, 115, 0, 115, 0, 143, 0, 143, 0],
        rate: [1],
        power: [30, 1, 0, 8, 0],
        buttons: [0x10, 1, 0, 0x10, 2, 0, 0x10, 4, 0, 0x90, 0x14, 2, 0x10, 16, 0, 0x40, 1, 0]
    )
}

@Test func selectingAStageKeepsTheFullDPITable() throws {
    let snapshot = try example()
    var draft = snapshot.settings
    draft.activeStage = 1
    let write = try #require(try snapshot.writes(for: draft).only)
    #expect(Array(write.packet.prefix(5)) == [3, 0, 1, 0x25, 0x16])
    #expect(write.packet[31] == 0x52)
    #expect(write.expectedPayload[5..<9] == [31, 0, 31, 0])
}

@Test func writesPreserveSleepAndUnrecognizedButtonAssignments() throws {
    let snapshot = try example()
    var draft = snapshot.settings
    draft.reportRate = 500
    draft.debounce = 9
    draft.buttons[5] = ButtonAction(0x40, 2)
    let writes = try snapshot.writes(for: draft)
    #expect(writes.count == 3)
    #expect(Array(writes[0].packet.prefix(5)) == [2, 0, 1, 1, 2])
    #expect(Array(writes[1].packet.prefix(8)) == [7, 0, 1, 4, 30, 1, 0, 9])
    #expect(writes[1].expectedPayload == [30, 1, 0, 9, 0])
    #expect(Array(writes[2].packet.prefix(4)) == [9, 0, 1, 0x0f])
    #expect(writes[2].expectedPayload[9..<12] == [0x90, 0x14, 2])
    #expect(writes[2].expectedPayload[15..<18] == [0x40, 2, 0])
}

@Test func applyingAControlRetainsANewerUneditedDPIStep() throws {
    let original = try example().settings
    var current = original
    current.activeStage = 3
    var draft = original
    draft.debounce = 12
    let merged = current.mergingEdits(from: original, to: draft)
    #expect(merged.activeStage == 3)
    #expect(merged.debounce == 12)
}

@Test(arguments: [UInt8(0xcd), 0xb5, 0xb6])
func mediaActionsAreSelectableAndEncodedAsConsumerUsages(_ usage: UInt8) throws {
    let snapshot = try example()
    let action = ButtonAction(0x80, usage)
    #expect(ButtonAction.choices.contains(action))

    var draft = snapshot.settings
    draft.buttons[4] = action
    let write = try #require(try snapshot.writes(for: draft).only)
    #expect(write.packet[16..<19] == [0x80, usage, 0])
    #expect(write.expectedPayload[12..<15] == [0x80, usage, 0])
}

@Test func checksumErrorsAndUnsupportedDPIValuesAreRejected() throws {
    var packet: [UInt8] = [0x12, 0, 1, 1, 1] + Array(repeating: 0, count: 27)
    #expect(throws: AiroxError.self) { try AiroxPage.reportRate.payload(from: packet) }
    packet[31] = 1
    #expect(try AiroxPage.reportRate.payload(from: packet) == [1])

    let snapshot = try example()
    var draft = snapshot.settings
    draft.stages[0] = DPIStage(x: 123, y: 123)
    #expect(throws: AiroxError.self) { try snapshot.writes(for: draft) }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
