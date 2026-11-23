import Testing
@testable import AiroxUtility

private struct AuroraFixture {
    var general: [UInt8] = [
        0x08, 0x4d, 0x04, 0x51, 0x03, 0x52, 0x00, 0x55, 0x00, 0x55, 0x01, 0x54,
        0x07, 0x07, 0x00, 0x47, 0x0f, 0x0f, 0x00, 0x37,
        0x17, 0x17, 0x00, 0x27, 0x9b, 0x9b, 0x00, 0x1f,
    ]
    var buttons: [[UInt8]] = [
        [0x01, 0x01, 0x00, 0x53], [0x01, 0x02, 0x00, 0x52], [0x01, 0x04, 0x00, 0x50],
        [0x05, 0x00, 0x00, 0x50], [0x05, 0x00, 0x00, 0x50], [0x07, 0x00, 0x00, 0x4e],
    ]
    var shortcuts: [Int: [UInt8]] = [
        2: Array(repeating: 0xff, count: 32),
        3: [0x02, 0x82, 0xb6, 0x00, 0x42, 0xb6, 0x00, 0x23] + Array(repeating: 0xff, count: 24),
        4: [0x02, 0x82, 0xb5, 0x00, 0x42, 0xb5, 0x00, 0x25] + Array(repeating: 0xff, count: 24),
    ]

    func snapshot() throws -> AuroraSnapshot {
        try AuroraSnapshot(general: general, debounce: [0x01, 0x54], buttons: buttons, shortcuts: shortcuts)
    }
}

@Test func auroraDecodesTheWiredMouseReadback() throws {
    let settings = try AuroraFixture().snapshot().settings
    #expect(settings.activeStage == 3)
    #expect(settings.stages == [400, 800, 1200, 7800].map { DPIStage(x: $0, y: $0) })
    #expect(settings.reportRate == 125)
    #expect(settings.debounce == 1)
    #expect(settings.buttons[3] == ButtonAction(0x80, 0xb6))
    #expect(settings.buttons[4] == ButtonAction(0x80, 0xb5))
    #expect(settings.buttons[5] == .cycleReportRate)
}

@Test func auroraWritesChecksummedScalarsAndHighDPI() throws {
    let snapshot = try AuroraFixture().snapshot()
    var proposed = snapshot.settings
    proposed.reportRate = 1000
    proposed.debounce = 8
    proposed.stages[2] = DPIStage(x: 26000, y: 26000)
    proposed.activeStage = 1

    let writes = try snapshot.changes(for: proposed).flatMap(\.writes)
    #expect(writes.map(\.address) == [0x00, 0xa9, 0x14, 0x04])
    #expect(writes.map(\.original) == [[0x08, 0x4d], [0x01, 0x54], [0x17, 0x17, 0x00, 0x27], [0x03, 0x52]])
    #expect(writes.map(\.updated) == [[0x01, 0x54], [0x08, 0x4d], [0x07, 0x07, 0x88, 0xbf], [0x01, 0x54]])
}

@Test func auroraWritesMediaShortcutBeforeSelectingItAndPreservesOtherButtons() throws {
    var fixture = AuroraFixture()
    let snapshot = try fixture.snapshot()
    var proposed = snapshot.settings
    proposed.buttons[2] = ButtonAction(0x80, 0xcd)

    let writes = try snapshot.changes(for: proposed).flatMap(\.writes)
    try #require(writes.count == 2)
    #expect(writes.map(\.address) == [0x140, 0x68])
    #expect(writes[0].original == Array(repeating: 0xff, count: 8))
    #expect(writes[0].updated == [0x02, 0x82, 0xcd, 0x00, 0x42, 0xcd, 0x00, 0xf5])
    #expect(writes[1].original == [0x01, 0x04, 0x00, 0x50])
    #expect(writes[1].updated == [0x05, 0x00, 0x00, 0x50])

    fixture.shortcuts[2]?.replaceSubrange(0..<8, with: writes[0].updated)
    fixture.buttons[2] = writes[1].updated
    #expect(try fixture.snapshot().settings.buttons == proposed.buttons)
}

@Test func auroraRejectsCorruptDPIRecord() {
    var fixture = AuroraFixture()
    fixture.general[15] ^= 1
    #expect(throws: AiroxError.self) { try fixture.snapshot() }
}
