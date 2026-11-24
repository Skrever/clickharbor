import CHID

extension AuroraController {
    func readMacros(on route: AuroraHIDRoute) throws -> [MouseMacro?] {
        try withDevice(on: route) { device in
            try (0..<AuroraMacroMemory.slotCount).map { slot in
                try readMacro(in: slot, on: device)
            }
        }
    }

    func readMacro(in slot: Int, on device: OpaquePointer) throws -> MouseMacro? {
        guard let address = AuroraMacroMemory.address(of: slot) else { return nil }
        let firstByte = try readBlock(device, address: address, count: 1)[0]
        guard (1...AuroraMacroMemory.maximumNameLength).contains(Int(firstByte)) else { return nil }
        let header = try readBlock(device, address: address, count: AuroraMacroMemory.headerLength)
        guard let length = AuroraMacroMemory.encodedLength(header: header) else { return nil }
        let events = try readBlock(device, address: address + header.count, count: length - header.count)
        return AuroraMacroMemory.decode(header + events)
    }

    func writeMacro(_ macro: MouseMacro, to slot: Int, on route: AuroraHIDRoute) throws {
        let bytes = try AuroraMacroMemory.encode(macro)
        try writeMacroBytes(bytes, to: slot, on: route)
    }

    func eraseMacro(in slot: Int, on route: AuroraHIDRoute) throws {
        try writeMacroBytes([UInt8](repeating: 0, count: AuroraMacroMemory.slotLength),
                            to: slot, on: route, requireUnassigned: true)
    }

    private func writeMacroBytes(_ bytes: [UInt8], to slot: Int, on route: AuroraHIDRoute,
                                 requireUnassigned: Bool = false) throws {
        guard let address = AuroraMacroMemory.address(of: slot) else {
            throw AiroxError.invalidSetting("Выберите ячейку макроса от 1 до 16.")
        }
        try withDevice(on: route) { device in
            if requireUnassigned {
                let buttons = try readBlock(device, address: AuroraMemory.buttons, count: AuroraButtons.count * 4)
                let isAssigned = stride(from: 0, to: buttons.count, by: 4).contains { offset in
                    let record = Array(buttons[offset..<(offset + 4)])
                    return AuroraMacroMemory.assignment(from: record)?.auroraMacroAssignment?.slot == slot
                }
                guard !isAssigned else {
                    throw AiroxError.invalidSetting("Сначала измените назначение кнопки, которая запускает этот макрос.")
                }
            }
            let original = try readBlock(device, address: address, count: bytes.count)
            guard original != bytes else { return }
            let write = AuroraWrite(address: address, original: original, updated: bytes)
            try commit(AuroraChange(name: "макрос \(slot + 1)", writes: [write]), on: device)
        }
    }
}
