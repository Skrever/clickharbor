struct MouseRGB: Equatable, Sendable, Codable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var bytes: [UInt8] { [red, green, blue] }
}

struct MouseDPIIndicator: Equatable, Sendable, Codable {
    var enabled: Bool
    var mode: Int
    var brightness: Int
    var speed: Int

    func mergingEdits(from baseline: Self, to edited: Self) -> Self {
        var result = self
        if edited.enabled != baseline.enabled { result.enabled = edited.enabled }
        if edited.mode != baseline.mode { result.mode = edited.mode }
        if edited.brightness != baseline.brightness { result.brightness = edited.brightness }
        if edited.speed != baseline.speed { result.speed = edited.speed }
        return result
    }
}

struct MouseAdvancedSettings: Equatable, Sendable, Codable {
    var stageColors: [MouseRGB] = []
    var dpiIndicator: MouseDPIIndicator?
    var liftOff: Int?
    var sleepSeconds: Int?
    var sensorMode: Int?
    var highPerformance: Bool?
    var highPerformanceSeconds: Int?
    var motionSync: Bool?
    var angleSnapping: Bool?
    var rippleControl: Bool?
    var wakeOnMovement: Bool?
    var lightsOffOnMovement: Bool?

    func mergingEdits(from baseline: Self, to edited: Self) -> Self {
        var result = self
        for index in stageColors.indices where baseline.stageColors.indices.contains(index) && edited.stageColors.indices.contains(index) {
            if edited.stageColors[index] != baseline.stageColors[index] {
                result.stageColors[index] = edited.stageColors[index]
            }
        }
        if let current = dpiIndicator, let old = baseline.dpiIndicator, let new = edited.dpiIndicator {
            result.dpiIndicator = current.mergingEdits(from: old, to: new)
        }
        if edited.liftOff != baseline.liftOff { result.liftOff = edited.liftOff }
        if edited.sleepSeconds != baseline.sleepSeconds { result.sleepSeconds = edited.sleepSeconds }
        if edited.sensorMode != baseline.sensorMode { result.sensorMode = edited.sensorMode }
        if edited.highPerformance != baseline.highPerformance { result.highPerformance = edited.highPerformance }
        if edited.highPerformanceSeconds != baseline.highPerformanceSeconds { result.highPerformanceSeconds = edited.highPerformanceSeconds }
        if edited.motionSync != baseline.motionSync { result.motionSync = edited.motionSync }
        if edited.angleSnapping != baseline.angleSnapping { result.angleSnapping = edited.angleSnapping }
        if edited.rippleControl != baseline.rippleControl { result.rippleControl = edited.rippleControl }
        if edited.wakeOnMovement != baseline.wakeOnMovement { result.wakeOnMovement = edited.wakeOnMovement }
        if edited.lightsOffOnMovement != baseline.lightsOffOnMovement { result.lightsOffOnMovement = edited.lightsOffOnMovement }
        return result
    }
}
