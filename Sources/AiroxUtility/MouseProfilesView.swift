import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct MouseProfile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var model: MouseModel
    var settings: AiroxSettings

    func applying(to current: AiroxSettings) -> AiroxSettings {
        var edits = current
        for index in current.stages.indices where settings.stages.indices.contains(index) {
            let stage = settings.stages[index]
            if model.dpiRange.contains(stage.x), model.dpiRange.contains(stage.y) {
                edits.stages[index] = stage
            }
        }
        if let count = settings.enabledStageCount, current.enabledStageCount != nil,
           (1...current.stages.count).contains(count) { edits.enabledStageCount = count }
        if current.stages.indices.contains(settings.activeStage) { edits.activeStage = settings.activeStage }
        if AiroxSettings.reportRates.contains(settings.reportRate) { edits.reportRate = settings.reportRate }
        if model.debounceValues.contains(settings.debounce) { edits.debounce = settings.debounce }
        for index in current.buttons.indices where settings.buttons.indices.contains(index) {
            let action = settings.buttons[index]
            if model.buttonChoices.contains(action) || action.keyboardShortcut { edits.buttons[index] = action }
        }

        for index in current.advanced.stageColors.indices where settings.advanced.stageColors.indices.contains(index) {
            edits.advanced.stageColors[index] = settings.advanced.stageColors[index]
        }
        if let saved = settings.advanced.dpiIndicator, var indicator = current.advanced.dpiIndicator {
            indicator.enabled = saved.enabled
            if AuroraAdvancedSnapshot.indicatorModes.contains(saved.mode) { indicator.mode = saved.mode }
            if AuroraAdvancedSnapshot.indicatorBrightness.contains(saved.brightness) { indicator.brightness = saved.brightness }
            if AuroraAdvancedSnapshot.indicatorSpeeds.contains(saved.speed) { indicator.speed = saved.speed }
            edits.advanced.dpiIndicator = indicator
        }
        if current.advanced.liftOff != nil, let value = settings.advanced.liftOff, (1...2).contains(value) {
            edits.advanced.liftOff = value
        }
        if current.advanced.sensorMode != nil, let value = settings.advanced.sensorMode, (0...1).contains(value) {
            edits.advanced.sensorMode = value
        }
        if current.advanced.sleepSeconds != nil, let value = settings.advanced.sleepSeconds,
           model.sleepValues.contains(value) { edits.advanced.sleepSeconds = value }
        if current.advanced.highPerformanceSeconds != nil, let value = settings.advanced.highPerformanceSeconds,
           AuroraAdvancedSnapshot.highPerformanceSeconds.contains(value) { edits.advanced.highPerformanceSeconds = value }
        for field: WritableKeyPath<MouseAdvancedSettings, Bool?> in [
            \.motionSync, \.angleSnapping, \.rippleControl, \.wakeOnMovement, \.lightsOffOnMovement, \.highPerformance,
        ] where current.advanced[keyPath: field] != nil {
            edits.advanced[keyPath: field] = settings.advanced[keyPath: field] ?? current.advanced[keyPath: field]
        }
        return current.mergingEdits(from: current, to: edits)
    }
}

struct MouseProfilesView: View {
    let model: MouseModel
    @Binding var settings: AiroxSettings
    @AppStorage("mouseProfiles.v1") private var storage = Data()
    @State private var name = ""
    @State private var feedback: String?
    @State private var removing: MouseProfile?

    private var profiles: [MouseProfile] {
        (try? JSONDecoder().decode([MouseProfile].self, from: storage)) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сохраняйте настройки \(model.rawValue) на Mac, чтобы применять их снова или переносить между компьютерами.")
                .foregroundStyle(.secondary)

            HStack {
                TextField("Название профиля", text: $name)
                    .textFieldStyle(.roundedBorder)
                Button("Сохранить текущие") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Импорт…") { importProfile() }
            }

            let available = profiles.filter { $0.model == model }
            if available.isEmpty {
                Text("Сохранённых профилей пока нет")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }

            ForEach(available) { profile in
                Divider()
                HStack {
                    Text(profile.name).fontWeight(.medium)
                    Spacer()
                    Button("Загрузить") {
                        settings = profile.applying(to: settings)
                        feedback = "Профиль загружен. Нажмите «Применить», чтобы записать его в мышь."
                    }
                    Menu {
                        Button("Экспорт…") { export(profile) }
                        Button("Удалить…", role: .destructive) { removing = profile }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Действия с профилем \(profile.name)")
                    .fixedSize()
                }
            }

            if let feedback {
                Text(feedback).font(.callout).foregroundStyle(.secondary)
            }
        }
        .alert("Удалить профиль?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { profile in
            Button("Удалить", role: .destructive) { persist(profiles.filter { $0.id != profile.id }) }
            Button("Отмена", role: .cancel) {}
        } message: { profile in
            Text(profile.name)
        }
    }

    private func save() {
        let cleanedName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard !cleanedName.isEmpty else { return }
        var profile = MouseProfile(name: cleanedName, model: model, settings: settings)
        var updated = profiles
        if let index = updated.firstIndex(where: { $0.model == model && $0.name == cleanedName }) {
            profile.id = updated[index].id
            updated[index] = profile
        } else {
            updated.append(profile)
        }
        persist(updated)
        name = ""
    }

    private func persist(_ updated: [MouseProfile]) {
        do {
            storage = try JSONEncoder().encode(updated)
            feedback = nil
        } catch {
            feedback = "Не удалось сохранить список профилей."
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 65_536 else { throw CocoaError(.fileReadCorruptFile) }
            var imported = try JSONDecoder().decode(MouseProfile.self, from: data)
            guard imported.model == model else {
                feedback = "Этот профиль создан для \(imported.model.rawValue)."
                return
            }
            imported.name = String(imported.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
            guard !imported.name.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            imported.id = UUID()
            persist(profiles + [imported])
        } catch {
            feedback = "Не удалось прочитать профиль ClickHarbor."
        }
    }

    private func export(_ profile: MouseProfile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ClickHarbor-profile.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(profile).write(to: url, options: .atomic)
        } catch {
            feedback = "Не удалось экспортировать профиль."
        }
    }
}
