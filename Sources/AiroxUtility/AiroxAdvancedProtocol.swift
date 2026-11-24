struct AiroxAdvancedSnapshot {
    static let liftOffValues = [1, 2]
    static let sleepValues = [60, 120, 300, 360, 600, 1200, 1800]

    let settings: MouseAdvancedSettings
    private let sensor: [UInt8]?
    private let power: [UInt8]

    init(colors: [UInt8]?, sensor: [UInt8]?, power: [UInt8]) throws {
        guard colors == nil || colors?.count == 18 else { throw AiroxError.invalidReply(AiroxPage.dpiColors.name) }
        guard sensor == nil || sensor?.count == 5 else { throw AiroxError.invalidReply(AiroxPage.sensor.name) }
        guard (4...5).contains(power.count) else { throw AiroxError.invalidReply(AiroxPage.debounce.name) }

        var settings = MouseAdvancedSettings()
        if let colors {
            settings.stageColors = stride(from: 0, to: colors.count, by: 3).map {
                MouseRGB(colors[$0], colors[$0 + 1], colors[$0 + 2])
            }
        }
        if let sensor {
            settings.liftOff = Int(sensor[0])
            settings.angleSnapping = sensor[1] == 1
            settings.rippleControl = sensor[2] == 1
        }
        settings.sleepSeconds = Int(power[0]) * 10
        settings.wakeOnMovement = power[1] == 1
        settings.lightsOffOnMovement = power[2] == 1

        self.settings = settings
        self.sensor = sensor
        self.power = power
    }

    func writes(for proposed: AiroxSettings) throws -> [AiroxWrite] {
        let updated = proposed.advanced
        var writes: [AiroxWrite] = []
        if updated.stageColors != settings.stageColors {
            guard !settings.stageColors.isEmpty, updated.stageColors.count == settings.stageColors.count else {
                throw AiroxError.invalidSetting("Нужно указать цвет каждой ступени DPI.")
            }
            writes.append(AiroxWrite(page: .dpiColors, code: 0x04, opcode: 0x12,
                                     payload: updated.stageColors.flatMap(\.bytes)))
        }

        if let write = try sensorWrite(for: updated) { writes.append(write) }
        if let write = try powerWrite(for: updated, debounce: proposed.debounce) { writes.append(write) }
        return writes
    }

    private func sensorWrite(for updated: MouseAdvancedSettings) throws -> AiroxWrite? {
        guard updated.liftOff != settings.liftOff || updated.angleSnapping != settings.angleSnapping
            || updated.rippleControl != settings.rippleControl else { return nil }
        guard let sensor, let liftOff = updated.liftOff, let angleSnapping = updated.angleSnapping,
              let rippleControl = updated.rippleControl else {
            throw AiroxError.invalidSetting("Мышь не предоставила параметры сенсора.")
        }
        var payload = sensor
        if liftOff != settings.liftOff {
            guard Self.liftOffValues.contains(liftOff) else {
                throw AiroxError.invalidSetting("Выберите расстояние отрыва 1 или 2 мм.")
            }
            payload[0] = UInt8(liftOff)
        }
        if angleSnapping != settings.angleSnapping { payload[1] = angleSnapping ? 1 : 0 }
        if rippleControl != settings.rippleControl { payload[2] = rippleControl ? 1 : 0 }
        // The OEM writes two zero bytes. Firmware can return different values in these positions.
        payload[3] = 0
        payload[4] = 0
        return AiroxWrite(page: .sensor, code: 0x06, opcode: 0x05, payload: payload, checkedPrefix: 3)
    }

    private func powerWrite(for updated: MouseAdvancedSettings, debounce: Int) throws -> AiroxWrite? {
        var readback = power
        if updated.sleepSeconds != settings.sleepSeconds {
            guard let seconds = updated.sleepSeconds, Self.sleepValues.contains(seconds) else {
                throw AiroxError.invalidSetting("Выберите поддерживаемое время перехода в сон.")
            }
            readback[0] = UInt8(seconds / 10)
        }
        guard let wakeOnMovement = updated.wakeOnMovement, let lightsOffOnMovement = updated.lightsOffOnMovement else {
            throw AiroxError.invalidSetting("Мышь не предоставила параметры пробуждения.")
        }
        if wakeOnMovement != settings.wakeOnMovement { readback[1] = wakeOnMovement ? 1 : 0 }
        if lightsOffOnMovement != settings.lightsOffOnMovement { readback[2] = lightsOffOnMovement ? 1 : 0 }
        if debounce != Int(power[3]) {
            guard AiroxSettings.debounceValues.contains(debounce) else {
                throw AiroxError.invalidSetting("Выберите дебаунс от 4 до 20 мс.")
            }
            readback[3] = UInt8(debounce)
        }
        guard readback != power else { return nil }
        return AiroxWrite(page: .debounce, code: 0x07, opcode: 0x04,
                          payload: Array(readback.prefix(4)), expected: readback)
    }
}
