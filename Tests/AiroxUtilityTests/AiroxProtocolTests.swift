import Testing
@testable import AiroxUtility

private func example() throws -> AiroxSnapshot {
    try AiroxSnapshot(
        dpi: [0x46, 15, 0, 15, 0, 31, 0, 31, 0, 47, 0, 47, 0, 63, 0, 63, 0, 115, 0, 115, 0, 143, 0, 143, 0],
        rate: [1],
        power: [30, 1, 0, 8, 0],
        buttons: [0x10, 1, 0, 0x10, 2, 0, 0x10, 4, 0, 0x90, 0x14, 2, 0x10, 16, 0, 0x40, 1, 0],
        colors: [0, 0, 255, 0, 255, 0, 255, 0, 255, 255, 255, 0, 0, 255, 255, 255, 255, 255],
        sensor: [2, 0, 0, 1, 0]
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

@Test func changingStageCountKeepsInactiveDPIAndRGBEntries() throws {
    let snapshot = try example()
    let baseline = snapshot.settings
    #expect(baseline.enabledStageCount == 6)
    #expect(baseline.advanced.stageColors.first == MouseRGB(0, 0, 255))

    var draft = baseline
    draft.enabledStageCount = 3
    draft.advanced.stageColors[1] = MouseRGB(14, 71, 211)
    let merged = baseline.mergingEdits(from: baseline, to: draft)
    let writes = try snapshot.writes(for: merged)

    #expect(merged.activeStage == 2)
    #expect(writes.count == 2)
    #expect(writes[0].packet.prefix(10) == [4, 0, 1, 18, 0, 0, 255, 14, 71, 211])
    #expect(writes[0].expectedPayload.suffix(3) == [255, 255, 255])
    #expect(writes[1].packet.prefix(5) == [3, 0, 1, 0x25, 0x23])
    #expect(writes[1].expectedPayload.suffix(4) == [143, 0, 143, 0])
}

@Test func sensorWriteVerifiesUserSettingsAndIgnoresFirmwareStatusBytes() throws {
    let snapshot = try example()
    var draft = snapshot.settings
    #expect(draft.advanced.liftOff == 2)
    #expect(draft.advanced.angleSnapping == false)
    #expect(draft.advanced.rippleControl == false)
    draft.advanced.liftOff = 1
    draft.advanced.rippleControl = true
    let write = try #require(try snapshot.writes(for: draft).only)

    #expect(write.packet.prefix(9) == [6, 0, 1, 5, 1, 0, 1, 0, 0])
    #expect(write.matches([1, 0, 1, 1, 0]))
    #expect(!write.matches([1, 1, 1, 1, 0]))
    #expect(!write.matches([1, 0, 1]))
}

@Test func powerEditsShareOneWriteWithDebounce() throws {
    let snapshot = try example()
    var draft = snapshot.settings
    #expect(draft.advanced.sleepSeconds == 300)
    #expect(draft.advanced.wakeOnMovement == true)
    #expect(draft.advanced.lightsOffOnMovement == false)
    draft.advanced.sleepSeconds = 600
    draft.advanced.wakeOnMovement = false
    draft.advanced.lightsOffOnMovement = true
    draft.debounce = 4
    let write = try #require(try snapshot.writes(for: draft).only)
    #expect(write.packet.prefix(8) == [7, 0, 1, 4, 60, 0, 1, 4])
    #expect(write.matches([60, 0, 1, 4, 0]))
}

@Test func airoxDeviceInfoDecodesBatteryAndFirmwareFields() {
    let device = AiroxDeviceInfo(identity: [0x45, 0x30, 0x32, 0x35, 0x84, 1, 0x95, 1, 1, 100, 1],
                                version: [0x84, 1])
    #expect(device.batteryPercent == 100)
    #expect(device.charging == true)
    #expect(device.firmwareVersion == "v84.01")

    let partial = AiroxDeviceInfo(identity: [0x45, 0x30, 0x32, 0x35], version: [2])
    #expect(partial.batteryPercent == nil)
    #expect(partial.charging == nil)
    #expect(partial.firmwareVersion == nil)
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

@Test func editingOneAxisRetainsTheCurrentValueOfTheOther() throws {
    let baseline = try example().settings
    var current = baseline
    current.stages[1].y = 1750
    var draft = baseline
    draft.stages[1].x = 1650
    let merged = current.mergingEdits(from: baseline, to: draft)
    let write = try #require(try example().writes(for: merged).only)

    #expect(merged.stages[1] == DPIStage(x: 1650, y: 1750))
    #expect(write.expectedPayload[5..<9] == [32, 0, 34, 0])
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
