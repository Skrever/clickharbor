struct AuroraAdvancedSnapshot {
    static let liftOffValues = [1, 2]
    static let sensorModes = [0, 1]
    static let sleepSeconds = [10, 30, 60, 120, 180, 300, 600, 900, 1200, 1500, 1800, 2100, 2400]
    static let highPerformanceSeconds = [10, 30, 60, 120, 180, 300, 600, 900, 1500, 1800, 2100, 2400]
    static let indicatorBrightness = [16, 30, 60, 90, 128, 150, 180, 210, 230, 255]
    static let indicatorModes = [1, 2]
    static let indicatorSpeeds = 1...5

    static let generalLength = 0x54
    static let sensorLength = 0x12

    private static let liftOff = 0x0a
    private static let dpiColors = 0x2c
    private static let indicatorMode = 0x4c
    private static let indicatorLevel = 0x4e
    private static let indicatorSpeed = 0x50
    private static let indicatorEnabled = 0x52
    private static let motionSync = 0xab
    private static let sleepTime = 0xad
    private static let angleSnapping = 0xaf
    private static let rippleControl = 0xb1
    private static let highPerformanceEnabled = 0xb5
    private static let highPerformanceTime = 0xb7
    private static let sensorMode = 0xb9

    let settings: MouseAdvancedSettings
    private let general: [UInt8]
    private let sensor: [UInt8]

    init(general: [UInt8], sensor: [UInt8], stageCount: Int) {
        self.general = general
        self.sensor = sensor

        let colors = (0..<stageCount).compactMap { index -> MouseRGB? in
            guard let bytes = Self.record(in: general, offset: Self.dpiColors + index * 4, count: 4) else {
                return nil
            }
            return MouseRGB(bytes[0], bytes[1], bytes[2])
        }
        func generalValue(_ address: Int) -> Int? {
            Self.record(in: general, offset: address, count: 2).map { Int($0[0]) }
        }
        func sensorValue(_ address: Int) -> Int? {
            Self.record(in: sensor, offset: address - AuroraMemory.debounce, count: 2).map { Int($0[0]) }
        }
        var settings = MouseAdvancedSettings()
        if colors.count == stageCount { settings.stageColors = colors }
        if let mode = generalValue(Self.indicatorMode), let brightness = generalValue(Self.indicatorLevel),
           let speed = generalValue(Self.indicatorSpeed),
           let enabled = Self.flag(generalValue(Self.indicatorEnabled)) {
            settings.dpiIndicator = MouseDPIIndicator(enabled: enabled, mode: mode, brightness: brightness, speed: speed)
        }
        settings.liftOff = generalValue(Self.liftOff)
        settings.sleepSeconds = sensorValue(Self.sleepTime).map { $0 * 10 }
        settings.sensorMode = sensorValue(Self.sensorMode)
        settings.motionSync = Self.flag(sensorValue(Self.motionSync))
        settings.angleSnapping = Self.flag(sensorValue(Self.angleSnapping))
        settings.rippleControl = Self.flag(sensorValue(Self.rippleControl))
        settings.highPerformance = Self.flag(sensorValue(Self.highPerformanceEnabled))
        settings.highPerformanceSeconds = sensorValue(Self.highPerformanceTime).map { $0 * 10 }
        self.settings = settings
    }

    func changes(for proposed: MouseAdvancedSettings) throws -> [AuroraChange] {
        guard proposed.stageColors.count == settings.stageColors.count else {
            throw AiroxError.invalidSetting("Набор цветов DPI не соответствует мыши.")
        }
        var changes: [AuroraChange] = []
        for index in proposed.stageColors.indices where proposed.stageColors[index] != settings.stageColors[index] {
            let bytes = proposed.stageColors[index].bytes
            let address = Self.dpiColors + index * 4
            let color = bytes + [AuroraMemory.sumByte(bytes)]
            changes.append(AuroraChange(name: "цвет ступени DPI \(index + 1)",
                                        writes: [try write(address: address, updated: color)]))
        }

        if proposed.dpiIndicator != settings.dpiIndicator {
            guard let old = settings.dpiIndicator, let new = proposed.dpiIndicator else {
                throw AiroxError.invalidSetting("Недоступная настройка индикатора DPI.")
            }
            var writes: [AuroraWrite] = []
            if old.enabled && !new.enabled {
                writes.append(try scalarWrite(address: Self.indicatorEnabled, value: 0))
            }
            func addWrite(_ previous: Int, _ value: Int, _ allowedValues: some Collection<Int>, address: Int) throws {
                guard let change = try scalarChange(previous, value, allowedValues, address: address, name: "индикатор DPI") else {
                    return
                }
                writes += change.writes
            }
            try addWrite(old.mode, new.mode, Self.indicatorModes, address: Self.indicatorMode)
            try addWrite(old.brightness, new.brightness, Self.indicatorBrightness, address: Self.indicatorLevel)
            try addWrite(old.speed, new.speed, Self.indicatorSpeeds, address: Self.indicatorSpeed)
            if !old.enabled && new.enabled {
                writes.append(try scalarWrite(address: Self.indicatorEnabled, value: 1))
            }
            changes.append(AuroraChange(name: "индикатор DPI", writes: writes))
        }

        let sleep = try scalarChange(settings.sleepSeconds, proposed.sleepSeconds, Self.sleepSeconds,
                                     address: Self.sleepTime, name: "время до сна", scale: 10)
        let liftOff = try scalarChange(settings.liftOff, proposed.liftOff, Self.liftOffValues,
                                       address: Self.liftOff, name: "высота отрыва")
        let mode = try scalarChange(settings.sensorMode, proposed.sensorMode, Self.sensorModes,
                                    address: Self.sensorMode, name: "режим сенсора")
        let motion = try flagChange(settings.motionSync, proposed.motionSync, address: Self.motionSync, name: "Motion Sync")
        let angle = try flagChange(settings.angleSnapping, proposed.angleSnapping, address: Self.angleSnapping,
                                   name: "коррекция траектории")
        let ripple = try flagChange(settings.rippleControl, proposed.rippleControl, address: Self.rippleControl,
                                    name: "фильтрация дрожания")
        changes += [liftOff, sleep, mode, motion, angle, ripple].compactMap { $0 }
        let performance = try flagChange(settings.highPerformance, proposed.highPerformance,
                                         address: Self.highPerformanceEnabled, name: "полная производительность")
        let duration = try scalarChange(settings.highPerformanceSeconds, proposed.highPerformanceSeconds,
                                        Self.highPerformanceSeconds, address: Self.highPerformanceTime,
                                        name: "время полной производительности", scale: 10)
        changes += [duration, performance].compactMap { $0 }
        return changes
    }

    private static func flag(_ value: Int?) -> Bool? {
        guard let value, (0...1).contains(value) else { return nil }
        return value == 1
    }

    private static func record(in bytes: [UInt8], offset: Int, count: Int) -> [UInt8]? {
        guard offset >= 0, offset + count <= bytes.count else { return nil }
        let record = Array(bytes[offset..<(offset + count)])
        return AuroraMemory.check(record) ? record : nil
    }

    private func write(address: Int, updated: [UInt8]) throws -> AuroraWrite {
        let bytes = address >= AuroraMemory.debounce ? sensor : general
        let offset = address >= AuroraMemory.debounce ? address - AuroraMemory.debounce : address
        guard let original = Self.record(in: bytes, offset: offset, count: updated.count) else {
            throw AiroxError.invalidReply("расширенные настройки")
        }
        return AuroraWrite(address: address, original: original, updated: updated)
    }

    private func scalarWrite(address: Int, value: Int) throws -> AuroraWrite {
        try write(address: address, updated: AuroraMemory.scalar(value))
    }

    private func scalarChange(_ previous: Int?, _ proposed: Int?, _ values: some Collection<Int>,
                              address: Int, name: String, scale: Int = 1) throws -> AuroraChange? {
        guard previous != proposed else { return nil }
        guard previous != nil, let proposed, values.contains(proposed) else {
            throw AiroxError.invalidSetting("Недопустимое значение параметра «\(name)».")
        }
        let write = try scalarWrite(address: address, value: proposed / scale)
        return AuroraChange(name: name, writes: [write])
    }

    private func flagChange(_ previous: Bool?, _ proposed: Bool?, address: Int, name: String) throws -> AuroraChange? {
        try scalarChange(previous.map { $0 ? 1 : 0 }, proposed.map { $0 ? 1 : 0 }, 0...1,
                         address: address, name: name)
    }
}
