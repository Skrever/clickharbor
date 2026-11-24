import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MouseMacrosView: View {
    @ObservedObject var model: AiroxModel
    let mouse: MouseModel
    @AppStorage("mouseMacros.v1") private var storage = Data()
    @State private var macro = MouseMacro(name: "", events: [])
    @State private var slot = 0
    @State private var button = 4
    @State private var rule = 0
    @State private var repetitions = 1
    @State private var isRecording = false
    @State private var lastEventTime: TimeInterval?
    @State private var heldEvents: [MouseMacroEvent] = []
    @State private var confirmation: String?
    @State private var feedback: String?

    private var library: [MouseMacro] { (try? JSONDecoder().decode([MouseMacro].self, from: storage)) ?? [] }
    private var maximumEvents: Int {
        mouse == .airox ? AiroxMacroMemory.maximumEventCount : AuroraMacroMemory.maximumEventCount
    }
    private var maximumRepeats: Int { mouse == .airox ? AiroxMacroMemory.maximumRepeats : 250 }
    private var currentDeviceMacro: MouseMacro? { model.deviceMacros?[slot] ?? nil }
    private var cleanName: String { macro.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var ready: Bool {
        guard !isRecording, !cleanName.isEmpty, (1...maximumEvents).contains(macro.events.count) else { return false }
        return mouse == .airox ? !macro.events.contains { $0.kind == .menu } : cleanName.utf8.count <= AuroraMacroMemory.maximumNameLength
    }
    private var repeatMode: MouseMacroRepeat {
        switch rule {
        case 1: .whileHeld
        case 2: .untilPressedAgain
        case 3: .untilAnyPressed
        default: .times(repetitions)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            editor
            Divider()
            assignment
            if let feedback { Text(feedback).font(.callout).foregroundStyle(.secondary) }
        }
        .alert(confirmation ?? "Изменить макрос?", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            let action = confirmation
            Button("Продолжить", role: .destructive) {
                if action == "Удалить макрос из мыши?" { model.eraseDeviceMacro(slot: slot) }
                else if action == "Удалить макрос с Mac?" { persist(library.filter { $0.name != cleanName }) }
                else { model.saveDeviceMacro(preparedMacro, slot: slot) }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                TextField("Название макроса", text: $macro.name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isRecording)
                Menu("Библиотека") {
                    if library.isEmpty { Text("Сохранённых макросов пока нет") }
                    ForEach(library, id: \.name) { item in
                        Button(item.name) { macro = item }
                    }
                    Divider()
                    Button("Новый макрос") { macro = MouseMacro(name: "", events: []) }
                    Button("Сохранить на Mac") {
                        persist(library.filter { $0.name != cleanName } + [preparedMacro])
                    }
                    .disabled(!ready)
                    Button("Удалить с Mac…", role: .destructive) { confirmation = "Удалить макрос с Mac?" }
                        .disabled(!library.contains { $0.name == cleanName })
                    Divider()
                    Button("Импорт…") { importMacro() }
                    Button("Экспорт…") { exportMacro() }.disabled(!ready)
                }
                .fixedSize()
                .disabled(isRecording)
            }

            HStack {
                if isRecording {
                    Button("Остановить запись") { finishRecording() }
                } else {
                    Button {
                        lastEventTime = nil
                        heldEvents = []
                        isRecording = true
                    } label: {
                        Label("Начать запись", systemImage: "record.circle")
                    }
                    .disabled(macro.events.count >= maximumEvents)
                }
                Menu("Добавить событие") {
                    addEvent("Клавиша", .key, 4)
                    addEvent("Модификатор", .modifier, 2)
                    addEvent("Кнопка мыши", .mouse, 1)
                    if mouse == .aurora { addEvent("Контекстное меню", .menu, 1) }
                }
                .fixedSize()
                .disabled(isRecording || macro.events.count >= maximumEvents)
                Spacer(minLength: 0)
                Text("\(macro.events.count) / \(maximumEvents)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(macro.events.count) из \(maximumEvents) событий")
            }

            if isRecording {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.tint.opacity(0.11))
                    Text("Нажимайте клавиши или щёлкайте в этой области")
                        .font(.callout)
                    MouseMacroRecorder { event, time in capture(event, time: time) }
                        .accessibilityLabel("Область записи макроса")
                }
                .frame(height: 70)
            } else {
                if !macro.events.isEmpty {
                    Text("Действие и задержка после него")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(macro.events.indices, id: \.self) { index in
                    eventRow(index)
                }
            }
        }
    }

    private func eventRow(_ index: Int) -> some View {
        let event = macro.events[index]
        let values: [(UInt16, String)] = switch event.kind {
        case .key: MouseMacroInput.keys
        case .modifier: MouseMacroInput.modifiers
        case .mouse: MouseMacroInput.mouseButtons
        case .menu: [(1, "Меню")]
        }
        return HStack(spacing: 7) {
            Picker("Действие", selection: $macro.events[index].pressed) {
                Text("Нажатие").tag(true)
                Text("Отпускание").tag(false)
            }
            .labelsHidden()
            .frame(width: 105)
            Picker("Клавиша или кнопка", selection: $macro.events[index].value) {
                ForEach(values, id: \.0) { value, label in Text(label).tag(value) }
                if !values.contains(where: { $0.0 == event.value }) {
                    Text("HID \(String(event.value, radix: 16))").tag(event.value)
                }
            }
            .labelsHidden()
            .frame(minWidth: 68, maxWidth: .infinity, alignment: .leading)
            TextField("Задержка, мс", value: $macro.events[index].delayMs, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 53)
            Text("мс").font(.caption).foregroundStyle(.secondary)
            Menu {
                Button("Выше") { macro.events.swapAt(index, index - 1) }.disabled(index == 0)
                Button("Ниже") { macro.events.swapAt(index, index + 1) }.disabled(index == macro.events.count - 1)
                Button("Удалить", role: .destructive) { macro.events.remove(at: index) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Действия с событием \(index + 1)")
            .fixedSize()
        }
    }

    private var assignment: some View {
        VStack(alignment: .leading, spacing: 9) {
            if mouse == .aurora {
                HStack {
                    Picker("Ячейка", selection: $slot) {
                        ForEach(0..<AuroraMacroMemory.slotCount, id: \.self) { index in
                            Text("\(index + 1) · \(model.deviceMacros?[index]?.name ?? (model.deviceMacros == nil ? "—" : "Пусто"))")
                                .tag(index)
                        }
                    }
                    Button("Считать ячейки") { model.readDeviceMacros() }
                }
                HStack {
                    Button("Сохранить в мышь") {
                        if currentDeviceMacro == nil { model.saveDeviceMacro(preparedMacro, slot: slot) }
                        else { confirmation = "Заменить макрос в ячейке \(slot + 1)?" }
                    }
                    .disabled(!ready || model.deviceMacros == nil)
                    if let currentDeviceMacro {
                        Button("Открыть") { macro = currentDeviceMacro }.disabled(isRecording)
                        Button("Удалить…", role: .destructive) { confirmation = "Удалить макрос из мыши?" }
                    }
                }
            }
            Picker("Кнопка", selection: $button) {
                ForEach(AiroxSettings.buttonNames.indices, id: \.self) { index in
                    Text(mouse.buttonName(at: index)).tag(index)
                }
            }
            Picker("Повтор", selection: $rule) {
                Text("Заданное число раз").tag(0)
                Text("Пока кнопка удерживается").tag(1)
                if mouse == .aurora { Text("До следующего нажатия той же кнопки").tag(2) }
                Text("До нажатия любой кнопки").tag(3)
            }
            if rule == 0 {
                Stepper("Повторов \(repetitions)", value: $repetitions, in: 1...maximumRepeats)
            }
            Button("Назначить на кнопку") {
                if mouse == .aurora {
                    model.assignAuroraMacro(slot: slot, button: button, rule: repeatMode)
                } else {
                    model.installAiroxMacro(preparedMacro, button: button, rule: repeatMode)
                }
            }
            .disabled(mouse == .aurora ? currentDeviceMacro == nil : !ready || model.hasChanges)
            .help(mouse == .aurora ? "Запишите назначение кнопки через «Применить»" : "Сначала примените другие изменения, если они есть")
        }
        .disabled(isRecording)
    }

    private func addEvent(_ title: String, _ kind: MouseMacroEvent.Kind, _ value: UInt16) -> some View {
        Button(title) { macro.events.append(MouseMacroEvent(kind: kind, value: value, pressed: true, delayMs: 0)) }
    }

    private var preparedMacro: MouseMacro { MouseMacro(name: cleanName, events: macro.events) }

    private func capture(_ event: MouseMacroEvent, time: TimeInterval) {
        guard isRecording, macro.events.count < maximumEvents else { return }
        let heldIndex = heldEvents.firstIndex { $0.kind == event.kind && $0.value == event.value }
        if event.pressed {
            guard heldIndex == nil else { return }
            guard macro.events.count + heldEvents.count + 2 <= maximumEvents else {
                finishRecording()
                return
            }
            heldEvents.append(event)
        } else {
            guard let heldIndex else { return }
            heldEvents.remove(at: heldIndex)
        }
        if let lastEventTime, let index = macro.events.indices.last {
            macro.events[index].delayMs = UInt16(clamping: Int((max(0, time - lastEventTime) * 1000).rounded()))
        }
        macro.events.append(event)
        lastEventTime = time
        if macro.events.count == maximumEvents { finishRecording() }
    }

    private func finishRecording() {
        for var event in heldEvents.reversed() {
            event.pressed = false
            macro.events.append(event)
        }
        heldEvents = []
        isRecording = false
        lastEventTime = nil
    }

    private func persist(_ updated: [MouseMacro]) {
        do {
            storage = try JSONEncoder().encode(updated)
            feedback = nil
        } catch {
            feedback = "Не удалось сохранить библиотеку макросов."
        }
    }

    private func importMacro() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 65_536 else { throw CocoaError(.fileReadCorruptFile) }
            let imported = try JSONDecoder().decode(MouseMacro.self, from: data)
            guard (1...maximumEvents).contains(imported.events.count) else { throw CocoaError(.fileReadCorruptFile) }
            macro = imported
            feedback = nil
        } catch {
            feedback = "Не удалось прочитать макрос ClickHarbor."
        }
    }

    private func exportMacro() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ClickHarbor-macro.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preparedMacro).write(to: url, options: .atomic)
        } catch {
            feedback = "Не удалось экспортировать макрос."
        }
    }
}
