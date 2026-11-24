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
    var sensor: [UInt8] = []

    func snapshot() throws -> AuroraSnapshot {
        try AuroraSnapshot(general: general, debounce: [0x01, 0x54], buttons: buttons, shortcuts: shortcuts,
                           sensor: sensor)
    }

    static func expanded() -> Self {
        var fixture = Self()
        fixture.general += [
            0x3f, 0x3f, 0x00, 0xd7, 0x3f, 0x3f, 0x00, 0xd7, 0x3f, 0x3f, 0x00, 0xd7, 0x3f, 0x3f, 0x00, 0xd7,
            0xff, 0xf7, 0x00, 0x5f, 0xee, 0x00, 0xff, 0x68, 0xff, 0xff, 0xff, 0x58, 0xff, 0xff, 0xff, 0x58,
            0xff, 0x00, 0xff, 0x57, 0xff, 0x00, 0xff, 0x57, 0xff, 0x00, 0xff, 0x57, 0xff, 0x00, 0xff, 0x57,
            0x02, 0x53, 0x80, 0xd5, 0x03, 0x52, 0x00, 0x55,
        ]
        fixture.sensor = [
            0x01, 0x54, 0x01, 0x54, 0x96, 0xbf, 0x00, 0x55, 0x00, 0x55, 0x00, 0x55,
            0x00, 0x55, 0x06, 0x4f, 0x00, 0x55,
        ]
        return fixture
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

@Test func auroraRoundTripsIndependentAxesAndCustomShortcuts() throws {
    var fixture = AuroraFixture()
    let snapshot = try fixture.snapshot()
    var proposed = snapshot.settings
    proposed.stages[2] = DPIStage(x: 1800, y: 26000)
    proposed.buttons[3] = ButtonAction(0x70, 0x0a, 0x07)
    proposed.buttons[4] = ButtonAction(0x70, 0, 0x53)

    for write in try snapshot.changes(for: proposed).flatMap(\.writes) {
        if write.address < AuroraMemory.buttons {
            fixture.general.replaceSubrange(write.address..<(write.address + write.updated.count), with: write.updated)
        } else if write.address >= AuroraMemory.shortcuts {
            let index = (write.address - AuroraMemory.shortcuts) / AuroraMemory.shortcutLength
            fixture.shortcuts[index]?.replaceSubrange(0..<write.updated.count, with: write.updated)
        }
    }
    #expect(try fixture.snapshot().settings == proposed)
}

@Test func auroraRejectsCorruptDPIRecord() {
    var fixture = AuroraFixture()
    fixture.general[15] ^= 1
    #expect(throws: AiroxError.self) { try fixture.snapshot() }
}

@Test func auroraRoundTripsDPIColorsIndicatorAndSensorParameters() throws {
    var fixture = AuroraFixture.expanded()
    let snapshot = try fixture.snapshot()
    #expect(snapshot.settings.advanced.stageColors == [
        MouseRGB(255, 247, 0), MouseRGB(238, 0, 255), MouseRGB(255, 255, 255), MouseRGB(255, 255, 255),
    ])
    #expect(snapshot.settings.advanced.sleepSeconds == 1500)
    #expect(snapshot.settings.advanced.motionSync == true)
    #expect(snapshot.settings.advanced.dpiIndicator == MouseDPIIndicator(enabled: false, mode: 2, brightness: 128, speed: 3))

    var proposed = snapshot.settings
    proposed.advanced.stageColors[0] = MouseRGB(0x12, 0x34, 0x56)
    proposed.advanced.dpiIndicator = MouseDPIIndicator(enabled: true, mode: 1, brightness: 210, speed: 5)
    proposed.advanced.liftOff = 2
    proposed.advanced.sleepSeconds = 900
    proposed.advanced.sensorMode = 1
    proposed.advanced.motionSync = false
    proposed.advanced.angleSnapping = true
    proposed.advanced.rippleControl = true
    proposed.advanced.highPerformance = true
    proposed.advanced.highPerformanceSeconds = 600
    let writes = try snapshot.changes(for: proposed).flatMap(\.writes)
    #expect(writes.map(\.address) == [0x2c, 0x4c, 0x4e, 0x50, 0x52, 0x0a, 0xad, 0xb9, 0xab, 0xaf, 0xb1, 0xb7, 0xb5])
    #expect(writes[0].original == [0xff, 0xf7, 0x00, 0x5f])
    #expect(writes[0].updated == [0x12, 0x34, 0x56, 0xb9])
    for write in writes {
        if write.address >= AuroraMemory.debounce {
            let start = write.address - AuroraMemory.debounce
            fixture.sensor.replaceSubrange(start..<(start + write.updated.count), with: write.updated)
        } else {
            fixture.general.replaceSubrange(write.address..<(write.address + write.updated.count), with: write.updated)
        }
    }
    #expect(try fixture.snapshot().settings == proposed)
}

@Test func auroraKeepsAnActiveDPIStageDuringStageCountChanges() throws {
    var fixture = AuroraFixture.expanded()
    let snapshot = try fixture.snapshot()
    var proposed = snapshot.settings
    proposed.enabledStageCount = 2
    proposed.activeStage = 1
    let writes = try snapshot.changes(for: proposed).flatMap(\.writes)
    #expect(writes.map(\.address) == [0x04, 0x02])
    for write in writes {
        fixture.general.replaceSubrange(write.address..<(write.address + 2), with: write.updated)
    }

    let reduced = try fixture.snapshot()
    #expect(reduced.settings == proposed)
    #expect(reduced.settings.stages.count == 4)
    #expect(reduced.settings.advanced.stageColors.count == 4)
    let increase = try reduced.changes(for: snapshot.settings).flatMap(\.writes)
    #expect(increase.map(\.address) == [0x02, 0x04])
}

@Test func auroraPreservesLeftClickWhenRemappingButtons() throws {
    let snapshot = try AuroraFixture().snapshot()
    var proposed = snapshot.settings
    proposed.buttons[0] = ButtonAction(0x60, 0)
    #expect(throws: AiroxError.self) { try snapshot.changes(for: proposed) }

    proposed.buttons[2] = ButtonAction(0x10, 0x01)
    let writes = try snapshot.changes(for: proposed).flatMap(\.writes)
    #expect(writes.map(\.address) == [0x68, 0x60])

    var preexisting = AuroraFixture()
    preexisting.buttons[0] = [0, 0, 0, 0x55]
    let existing = try preexisting.snapshot()
    #expect(try existing.changes(for: existing.settings).isEmpty)
}
