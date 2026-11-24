import AppKit
import SwiftUI

struct AiroxView: View {
    @ObservedObject var model: AiroxModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = Page.settings
    @State private var showingPairing = false
    @State private var confirmingReset = false
    @State private var separateAxes = false
    @State private var shortcutButton: Int?
    @Namespace private var sidebarSelection

    private enum Page: String, CaseIterable {
        case settings = "Настройки"
        case lighting = "Подсветка"
        case buttons = "Кнопки"
        case advanced = "Сенсор и питание"
        case profiles = "Профили"
        case macros = "Макросы"

        var symbol: String {
            switch self {
            case .settings: "slider.horizontal.3"
            case .lighting: "lightbulb"
            case .buttons: "cursorarrow.click.2"
            case .advanced: "scope"
            case .profiles: "square.stack"
            case .macros: "command"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(palette.border)
                .frame(width: 1)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                workspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                footer
            }
        }
        .frame(minWidth: 710, idealWidth: 900, minHeight: 540, idealHeight: 685)
        .background(palette.workspace)
        .tint(palette.accent)
        .sheet(isPresented: $showingPairing) { pairingInstructions }
        .sheet(isPresented: Binding(get: { shortcutButton != nil }, set: { if !$0 { shortcutButton = nil } })) {
            if let index = shortcutButton, let action = model.draft?.buttons[index] {
                MouseShortcutEditor(name: selectedModel.buttonName(at: index), action: action) {
                    model.draft?.buttons[index] = $0
                }
            }
        }
        .alert("Сбросить настройки Aurora?", isPresented: $confirmingReset) {
            Button("Сбросить", role: .destructive) { model.resetAurora() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Настройки в памяти мыши и назначения кнопок будут заменены заводскими.")
        }
    }

    private var palette: HarborPalette { HarborPalette(dark: colorScheme == .dark) }
    private var selectedModel: MouseModel { model.selected?.model ?? .airox }
    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.24) }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [palette.inkTeal, palette.button],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .accessibilityHidden(true)

                Text("ClickHarbor")
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(-0.65)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 3)

            deviceCard

            VStack(spacing: 4) {
                ForEach(Page.allCases, id: \.self) { item in
                    navigationItem(item)
                }
            }
            .disabled(!model.connected)
            .opacity(model.connected ? 1 : 0.75)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 22)
        .frame(width: 206)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.sidebar)
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Устройство")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if model.available.count > 1, let selected = model.selected {
                Picker("Мышь", selection: Binding(get: { model.selected ?? selected }, set: { model.select($0) })) {
                    ForEach(model.available, id: \.self) { connection in
                        Text(connection.menuLabel).tag(connection)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(model.busy)
            } else {
                Text(model.selected != nil ? model.deviceName : "Мышь не выбрана")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 2 }
                    .accessibilityHidden(true)

                Text(model.unsupportedMousePresent && model.selected == nil ? "Мышь не распознана" : model.connectionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let battery = model.deviceDetails?.batteryPercent {
                Label("\(battery)%", systemImage: model.deviceDetails?.charging == true ? "battery.100percent.bolt" : "battery.75percent")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(model.deviceDetails?.charging == true ? "Зарядка, \(battery)%" : "Заряд, \(battery)%")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11).strokeBorder(palette.border)
                .allowsHitTesting(false)
        }
    }

    private var statusColor: Color {
        if model.connected { return palette.accent }
        if model.unsupportedMousePresent || model.error != nil { return palette.warning }
        return Color.secondary.opacity(0.55)
    }

    private func navigationItem(_ item: Page) -> some View {
        let selected = item == page
        return Button {
            withAnimation(motion) { page = item }
        } label: {
            Label(item.rawValue, systemImage: item.symbol)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? palette.accent : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.accent.opacity(0.12))
                            .matchedGeometryEffect(id: "selected", in: sidebarSelection)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var workspace: some View {
        if let draft = model.draft, model.connected {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Text(page.rawValue)
                        .font(.system(size: 29, weight: .semibold))
                        .tracking(-0.8)
                        .accessibilityAddTraits(.isHeader)

                    if model.unsupportedMousePresent { unsupportedNotice }

                    Group {
                        switch page {
                        case .settings:
                            VStack(spacing: 13) {
                                sensitivityHero(draft)
                                stages(draft)
                                performance(draft)
                            }
                        case .lighting:
                            lighting(draft)
                        case .buttons:
                            buttons(draft)
                        case .advanced:
                            advanced(draft.advanced)
                        case .profiles:
                            profiles(draft)
                        case .macros:
                            panel { MouseMacrosView(model: model, mouse: selectedModel).id(model.selected) }
                        }
                    }
                    .id(page)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 5)))
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 20)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
            }
            .disabled(model.busy)
        } else {
            connectionView
        }
    }

    private func sensitivityHero(_ draft: AiroxSettings) -> some View {
        let current = draft.stages.indices.contains(draft.activeStage) ? draft.stages[draft.activeStage] : nil
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Активная чувствительность")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if let current {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(current.x == current.y
                             ? String(current.x)
                             : "\(current.x) × \(current.y)")
                            .font(.system(size: 39, weight: .semibold, design: .rounded).monospacedDigit())
                            .tracking(-1.4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(motion, value: current.x)
                        Text("DPI")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .accessibilityElement(children: .combine)
                    Text("Ступень \(draft.activeStage + 1) из \(draft.enabledStageCount ?? draft.stages.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").font(.largeTitle)
                }
            }

            Spacer(minLength: 2)
            HarborSignal(color: palette.accent, wireless: model.selected == .auroraReceiver, active: true)
                .frame(width: 151, height: 92)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(LinearGradient(colors: [palette.card, palette.hero],
                                     startPoint: .leading, endPoint: .trailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15).strokeBorder(palette.accent.opacity(0.24))
                .allowsHitTesting(false)
        }
    }

    private func stages(_ draft: AiroxSettings) -> some View {
        panel {
            HStack(alignment: .firstTextBaseline) {
                Label("Ступени DPI", systemImage: "scope")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(selectedModel.dpiRange.lowerBound)–\(selectedModel.dpiRange.upperBound) · шаг \(AiroxSettings.dpiStep)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let count = draft.enabledStageCount {
                HStack {
                    Text("Число ступеней")
                    Spacer()
                    Picker("Число ступеней", selection: Binding(get: { model.draft?.enabledStageCount ?? count }, set: { value in
                        model.draft?.enabledStageCount = value
                        if let active = model.draft?.activeStage, active >= value {
                            model.draft?.activeStage = value - 1
                        }
                    })) {
                        ForEach(1...draft.stages.count, id: \.self) { value in
                            Text(String(value)).tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            Toggle("Редактировать DPI по осям", isOn: $separateAxes)
                .toggleStyle(.checkbox)

            VStack(spacing: 3) {
                ForEach(draft.stages.indices.prefix(draft.enabledStageCount ?? draft.stages.count), id: \.self) { index in
                    stageRow(index, draft)
                }
            }
        }
    }

    private func stageRow(_ index: Int, _ draft: AiroxSettings) -> some View {
        let selected = index == draft.activeStage
        return HStack(spacing: 12) {
            Button {
                withAnimation(motion) { model.draft?.activeStage = index }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(selected ? palette.accent : Color.secondary)
                        .accessibilityHidden(true)
                    Text("Ступень \(index + 1)")
                        .fontWeight(selected ? .semibold : .regular)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])

            if separateAxes {
                axisField("X", index: index, coordinate: \.x, value: draft.stages[index].x)
                axisField("Y", index: index, coordinate: \.y, value: draft.stages[index].y)
            } else {
                DPIField(value: stageValue(index), secondaryValue: draft.stages[index].y,
                         label: "Ступень \(index + 1), DPI")
                    .frame(width: 102)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? palette.accent.opacity(0.10) : Color.clear)
        }
    }

    private func axisField(_ axis: String, index: Int, coordinate: WritableKeyPath<DPIStage, Int>, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(axis).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            DPIField(value: Binding(get: {
                guard let stages = model.draft?.stages, stages.indices.contains(index) else { return value }
                return stages[index][keyPath: coordinate]
            }, set: { newValue in
                guard model.draft?.stages.indices.contains(index) == true else { return }
                model.draft?.stages[index][keyPath: coordinate] = newValue
            }), secondaryValue: value, label: "Ступень \(index + 1), ось \(axis), DPI")
            .frame(width: 65)
        }
    }

    private func performance(_ draft: AiroxSettings) -> some View {
        panel {
            Label("Отклик", systemImage: "bolt.horizontal")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: 17) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Частота опроса").foregroundStyle(.secondary)
                    Picker("Частота опроса", selection: binding(\.reportRate, fallback: draft.reportRate)) {
                        ForEach(options(AiroxSettings.reportRates, current: draft.reportRate), id: \.self) { rate in
                            Text("\(String(rate)) Гц").tag(rate)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Дебаунс кнопок").foregroundStyle(.secondary)
                    Picker("Дебаунс кнопок", selection: binding(\.debounce, fallback: draft.debounce)) {
                        ForEach(options(selectedModel.debounceValues, current: draft.debounce), id: \.self) { value in
                            Text("\(value) мс").tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func lighting(_ draft: AiroxSettings) -> some View {
        VStack(spacing: 13) {
            if draft.advanced.stageColors.isEmpty && draft.advanced.dpiIndicator == nil {
                panel {
                    Text("Мышь не предоставила настройки подсветки")
                        .foregroundStyle(.secondary)
                }
            }
            if !draft.advanced.stageColors.isEmpty {
                panel {
                    Label("Цвета ступеней DPI", systemImage: "paintpalette")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(draft.advanced.stageColors.indices.prefix(draft.enabledStageCount ?? draft.stages.count), id: \.self) { index in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(Color(mouseRGB: draft.advanced.stageColors[index]))
                                .overlay { Circle().strokeBorder(Color.primary.opacity(0.17)) }
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                            Text("Ступень \(index + 1)")
                            if draft.stages.indices.contains(index) {
                                Text("\(String(draft.stages[index].x)) DPI")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ColorPicker("Цвет ступени \(index + 1)", selection: stageColor(index, draft.advanced.stageColors[index]), supportsOpacity: false)
                                .labelsHidden()
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            if let indicator = draft.advanced.dpiIndicator {
                panel {
                    Label("Индикатор DPI", systemImage: "lightbulb")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Picker("Режим", selection: indicatorMode(indicator)) {
                        Text("Выключен").tag(0)
                        Text("Постоянный свет").tag(1)
                        Text("Пульсация").tag(2)
                        if indicator.enabled && !(1...2).contains(indicator.mode) {
                            Text("Текущий режим").tag(indicator.mode)
                        }
                    }

                    if indicator.enabled {
                        Picker("Яркость", selection: indicatorValue(\.brightness, fallback: indicator.brightness)) {
                            if !Self.indicatorBrightness.contains(indicator.brightness) {
                                Text("Текущая яркость").tag(indicator.brightness)
                            }
                            ForEach(Self.indicatorBrightness.indices, id: \.self) { index in
                                Text("\(index + 1) из 10").tag(Self.indicatorBrightness[index])
                            }
                        }
                        if indicator.mode == 2 {
                            Picker("Скорость пульсации", selection: indicatorValue(\.speed, fallback: indicator.speed)) {
                                ForEach(options(Array(1...5), current: indicator.speed), id: \.self) { speed in
                                    Text("\(speed) из 5").tag(speed)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func advanced(_ settings: MouseAdvancedSettings) -> some View {
        VStack(spacing: 13) {
            panel {
                Label("Сенсор", systemImage: "scope")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                if let liftOff = settings.liftOff {
                    Picker("Высота отрыва", selection: advancedValue(\.liftOff, fallback: liftOff)) {
                        ForEach(options([1, 2], current: liftOff), id: \.self) { height in
                            Text("\(height) мм").tag(height)
                        }
                    }
                }
                if let mode = settings.sensorMode {
                    Picker("Режим сенсора", selection: advancedValue(\.sensorMode, fallback: mode)) {
                        Text("Обычный").tag(0)
                        Text("Высокая производительность").tag(1)
                        if !(0...1).contains(mode) { Text("Текущий режим").tag(mode) }
                    }
                }
                if let motionSync = settings.motionSync {
                    Toggle("Синхронизация движения", isOn: advancedValue(\.motionSync, fallback: motionSync))
                }
                if let snapping = settings.angleSnapping {
                    Toggle("Выпрямление траектории", isOn: advancedValue(\.angleSnapping, fallback: snapping))
                }
                if let rippleControl = settings.rippleControl {
                    Toggle("Подавление дрожания курсора", isOn: advancedValue(\.rippleControl, fallback: rippleControl))
                }
            }

            panel {
                Label("Питание", systemImage: "battery.75percent")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                if let sleepSeconds = settings.sleepSeconds {
                    durationPicker("Сон после простоя", \.sleepSeconds, current: sleepSeconds, values: selectedModel.sleepValues)
                }
                if let performance = settings.highPerformance {
                    Toggle("Режим полной производительности", isOn: advancedValue(\.highPerformance, fallback: performance))
                    if performance, let seconds = settings.highPerformanceSeconds {
                        durationPicker("Выход из режима после простоя", \.highPerformanceSeconds, current: seconds,
                                       values: AuroraAdvancedSnapshot.highPerformanceSeconds)
                    }
                }
                if let wake = settings.wakeOnMovement {
                    Toggle("Пробуждение движением", isOn: advancedValue(\.wakeOnMovement, fallback: wake))
                }
                if let lightsOff = settings.lightsOffOnMovement {
                    Toggle("Гасить подсветку при движении", isOn: advancedValue(\.lightsOffOnMovement, fallback: lightsOff))
                }
            }

            panel {
                HStack {
                    Label("Сведения об устройстве", systemImage: "info.circle")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Считать") { model.readDeviceDetails() }
                }
                if let info = model.deviceDetails {
                    if let battery = info.batteryPercent {
                        LabeledContent("Заряд", value: info.charging == true ? "\(battery)% · заряжается" : "\(battery)%")
                    }
                    if let version = info.firmwareVersion { LabeledContent("Прошивка мыши", value: version) }
                    if let version = info.receiverFirmwareVersion { LabeledContent("Прошивка приёмника", value: version) }
                    if info.batteryPercent == nil && info.firmwareVersion == nil && info.receiverFirmwareVersion == nil {
                        Text("Устройство не предоставило сведения").font(.callout).foregroundStyle(.secondary)
                    }
                }
                if selectedModel == .aurora {
                    HStack {
                        if model.canPairReceiver {
                            Button("Сопряжение с приёмником…") { showingPairing = true }.disabled(model.hasChanges)
                        }
                        if model.deviceDetails?.canFactoryReset == true {
                            Button("Сбросить настройки…", role: .destructive) { confirmingReset = true }
                        }
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .toggleStyle(.switch)
    }

    private func durationPicker(_ title: String, _ field: WritableKeyPath<MouseAdvancedSettings, Int?>,
                                current: Int, values: [Int]) -> some View {
        Picker(title, selection: advancedValue(field, fallback: current)) {
            ForEach(options(values, current: current), id: \.self) { duration in
                Text(duration % 60 == 0 && duration > 0 ? "\(duration / 60) мин" : "\(duration) с").tag(duration)
            }
        }
    }

    private func profiles(_ draft: AiroxSettings) -> some View {
        VStack(spacing: 13) {
            panel {
                MouseProfilesView(model: selectedModel,
                                  settings: Binding(get: { model.draft ?? draft }, set: { model.draft = $0 }))
                    .id(selectedModel)
            }
            if selectedModel == .aurora {
                panel {
                    HStack {
                        Label("Профили в мыши", systemImage: "externaldrive")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Проверить поддержку") { model.readDeviceDetails() }
                    }
                    if let current = model.onboardProfile {
                        Picker("Активный профиль", selection: Binding(get: { model.onboardProfile ?? current }, set: { model.switchOnboardProfile($0) })) {
                            ForEach(0..<AuroraController.onboardProfileCount, id: \.self) { index in
                                Text("Профиль \(index + 1)").tag(index)
                            }
                        }
                        .disabled(model.hasChanges)
                    } else if model.deviceDetails != nil {
                        Text("Прошивка не предоставила встроенные профили").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func advancedValue<Value>(_ field: WritableKeyPath<MouseAdvancedSettings, Value?>, fallback: Value) -> Binding<Value> {
        Binding(get: { model.draft?.advanced[keyPath: field] ?? fallback },
                set: { model.draft?.advanced[keyPath: field] = $0 })
    }

    private func indicatorMode(_ indicator: MouseDPIIndicator) -> Binding<Int> {
        Binding {
            let value = model.draft?.advanced.dpiIndicator ?? indicator
            return value.enabled ? value.mode : 0
        } set: { value in
            model.draft?.advanced.dpiIndicator?.enabled = value != 0
            if value != 0 { model.draft?.advanced.dpiIndicator?.mode = value }
        }
    }

    private func indicatorValue(_ field: WritableKeyPath<MouseDPIIndicator, Int>, fallback: Int) -> Binding<Int> {
        Binding(get: { model.draft?.advanced.dpiIndicator?[keyPath: field] ?? fallback },
                set: { model.draft?.advanced.dpiIndicator?[keyPath: field] = $0 })
    }

    private static let indicatorBrightness = AuroraAdvancedSnapshot.indicatorBrightness

    private func stageColor(_ index: Int, _ fallback: MouseRGB) -> Binding<Color> {
        Binding {
            guard let colors = model.draft?.advanced.stageColors, colors.indices.contains(index) else {
                return Color(mouseRGB: fallback)
            }
            return Color(mouseRGB: colors[index])
        } set: { color in
            guard model.draft?.advanced.stageColors.indices.contains(index) == true,
                  let value = NSColor(color).usingColorSpace(.sRGB) else { return }
            model.draft?.advanced.stageColors[index] = MouseRGB(
                UInt8(clamping: Int((value.redComponent * 255).rounded())),
                UInt8(clamping: Int((value.greenComponent * 255).rounded())),
                UInt8(clamping: Int((value.blueComponent * 255).rounded()))
            )
        }
    }

    private func buttons(_ draft: AiroxSettings) -> some View {
        panel {
            VStack(spacing: 0) {
                ForEach(draft.buttons.indices, id: \.self) { index in
                    let name = AiroxSettings.buttonNames.indices.contains(index)
                        ? selectedModel.buttonName(at: index) : "Кнопка \(index + 1)"
                    let current = draft.buttons[index]

                    HStack(spacing: 12) {
                        Image(systemName: buttonSymbol(index))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.accent)
                            .frame(width: 30, height: 30)
                            .background(palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityHidden(true)

                        Text(name)
                            .fontWeight(.medium)
                        Spacer(minLength: 8)

                        Picker(name, selection: buttonValue(index, fallback: current)) {
                            ForEach(options(selectedModel.buttonChoices, current: current), id: \.self) { action in
                                Text(buttonActionName(action)).tag(action)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220)

                        Button {
                            shortcutButton = index
                        } label: {
                            Image(systemName: "keyboard")
                        }
                        .help("Назначить клавишу или сочетание")
                        .accessibilityLabel("Назначить сочетание для кнопки \(name)")
                    }
                    .padding(.vertical, 7)

                    if index != draft.buttons.indices.last {
                        Rectangle().fill(palette.border).frame(height: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func buttonSymbol(_ index: Int) -> String {
        switch index {
        case 0: "cursorarrow.click"
        case 1: "cursorarrow.click.2"
        case 2: "arrow.up.and.down"
        case 3: "chevron.left"
        case 4: "chevron.right"
        default: "scope"
        }
    }

    private func buttonActionName(_ action: ButtonAction) -> String {
        if let assignment = action.auroraMacroAssignment {
            return model.deviceMacros?[assignment.slot]?.name ?? "Макрос \(assignment.slot + 1)"
        }
        if action.airoxMacroAssignment != nil { return "Макрос Airox" }
        return action.label
    }

    private var connectionView: some View {
        VStack(spacing: 13) {
            HarborSignal(color: model.unsupportedMousePresent && model.selected == nil ? palette.warning : palette.accent,
                         wireless: model.selected == .auroraReceiver,
                         active: model.busy || !model.unsupportedMousePresent)
                .frame(width: 214, height: 137)

            Text(connectionTitle)
                .font(.system(size: 25, weight: .semibold))
                .tracking(-0.42)
                .accessibilityAddTraits(.isHeader)

            Text(connectionHelp)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 295)

            if model.unsupportedMousePresent && model.selected != nil {
                unsupportedNotice
            }
            if model.canPairReceiver {
                Button("Сопряжение с приёмником…") { showingPairing = true }
                    .disabled(model.busy)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pairingInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Сопряжение Aurora", systemImage: "antenna.radiowaves.left.and.right")
                .font(.title2.weight(.semibold))
            Text("Подключите приёмник к Mac, отсоедините кабель от мыши и переведите её в режим 2,4 ГГц.")
            Text("Удерживайте левую и правую кнопки вместе с колесом до мигания жёлтого индикатора.")
            Text("Держите мышь рядом с приёмником до завершения поиска.")
            HStack {
                Spacer()
                Button("Отмена") { showingPairing = false }.keyboardShortcut(.cancelAction)
                Button("Начать сопряжение") {
                    showingPairing = false
                    model.pairAurora()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canPairReceiver || model.busy)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 420)
    }

    private var unsupportedNotice: some View {
        Label("Другая подключённая мышь не распознана", systemImage: "exclamationmark.circle")
            .foregroundStyle(palette.warning)
            .font(.callout)
    }

    private var connectionTitle: String {
        if model.busy { return "Считываем настройки" }
        if model.selected == .auroraReceiver { return "Ожидаем Aurora" }
        if model.unsupportedMousePresent && model.selected == nil { return "Мышь не распознана" }
        if model.error != nil && model.selected != nil { return "Настройки недоступны" }
        return "Подключите мышь"
    }

    private var connectionHelp: String {
        if let error = model.error { return error }
        if model.selected == .auroraReceiver {
            return "Включите Aurora в режиме 2,4 ГГц. Если мышь спит, слегка подвигайте её."
        }
        return "Поддерживаются IO Airox по USB и IO Aurora по USB или через приёмник 2,4 ГГц."
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                if model.busy {
                    ProgressView().controlSize(.mini).accessibilityHidden(true)
                } else if model.error != nil || model.hasChanges {
                    Image(systemName: model.error == nil ? "circle.dotted" : "exclamationmark.triangle")
                        .foregroundStyle(model.error == nil ? palette.accent : palette.warning)
                        .accessibilityHidden(true)
                }

                Text(footerStatus)
                    .font(.caption)
                    .foregroundStyle(model.error == nil ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.refresh()
            } label: {
                Label("Считать", systemImage: "arrow.clockwise")
            }
            .help("Считать текущие настройки с мыши")
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.busy)

            Button("Применить") {
                model.apply()
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.button)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.busy || !model.hasChanges)
        }
        .controlSize(.regular)
        .padding(.horizontal, 23)
        .padding(.vertical, 11)
        .background(palette.card)
    }

    private var footerStatus: String {
        if let error = model.error { return model.connected ? error : model.status }
        if model.hasChanges && !model.busy { return "Есть неприменённые изменения" }
        if model.unsupportedMousePresent && model.selected == nil { return "Подключено неизвестное устройство" }
        return model.status
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9, content: content)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13).strokeBorder(palette.border)
                    .allowsHitTesting(false)
            }
    }

    private func binding<Value>(_ field: WritableKeyPath<AiroxSettings, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { model.draft?[keyPath: field] ?? fallback },
                set: { model.draft?[keyPath: field] = $0 })
    }

    private func stageValue(_ index: Int) -> Binding<Int> {
        Binding {
            guard let stages = model.draft?.stages, stages.indices.contains(index) else {
                return selectedModel.dpiRange.lowerBound
            }
            return stages[index].x
        } set: { value in
            guard model.draft?.stages.indices.contains(index) == true else { return }
            model.draft?.stages[index] = DPIStage(x: value, y: value)
        }
    }

    private func buttonValue(_ index: Int, fallback: ButtonAction) -> Binding<ButtonAction> {
        Binding {
            guard let buttons = model.draft?.buttons, buttons.indices.contains(index) else { return fallback }
            return buttons[index]
        } set: { action in
            guard model.draft?.buttons.indices.contains(index) == true else { return }
            model.draft?.buttons[index] = action
        }
    }

    private func options<Value: Equatable>(_ values: [Value], current: Value) -> [Value] {
        values.contains(current) ? values : [current] + values
    }
}

private struct MouseShortcutEditor: View {
    let name: String
    let apply: (ButtonAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var modifiers: UInt8
    @State private var key: UInt8

    init(name: String, action: ButtonAction, apply: @escaping (ButtonAction) -> Void) {
        self.name = name
        self.apply = apply
        _modifiers = State(initialValue: action.keyboardShortcut ? action.first : 0)
        _key = State(initialValue: action.keyboardShortcut ? action.second : 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Клавиша или сочетание").font(.title2.weight(.semibold))
            Text(name).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                modifier("⌃ Control", bit: 1)
                modifier("⇧ Shift", bit: 2)
                modifier("⌥ Option", bit: 4)
                modifier("⌘ Command", bit: 8)
            }
            .toggleStyle(.checkbox)
            Picker("Клавиша", selection: $key) {
                ForEach(MouseMacroInput.keys, id: \.0) { usage, label in Text(label).tag(UInt8(usage)) }
                if !MouseMacroInput.keys.contains(where: { $0.0 == UInt16(key) }) {
                    Text("HID \(String(key, radix: 16))").tag(key)
                }
            }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Назначить") {
                    apply(ButtonAction(0x70, modifiers, key))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 390)
    }

    private func modifier(_ name: String, bit: UInt8) -> some View {
        let bothSides = bit | bit << 4
        return Toggle(name, isOn: Binding(get: { modifiers & bothSides != 0 }, set: { enabled in
            if enabled { modifiers |= bit } else { modifiers &= ~bothSides }
        }))
    }
}

private extension Color {
    init(mouseRGB: MouseRGB) {
        self.init(.sRGB, red: Double(mouseRGB.red) / 255, green: Double(mouseRGB.green) / 255,
                  blue: Double(mouseRGB.blue) / 255, opacity: 1)
    }
}

private struct HarborPalette {
    let dark: Bool

    var workspace: Color { dark ? Color(red: 0.093, green: 0.113, blue: 0.119) : Color(red: 0.968, green: 0.978, blue: 0.977) }
    var sidebar: Color { dark ? Color(red: 0.073, green: 0.091, blue: 0.096) : Color(red: 0.923, green: 0.947, blue: 0.947) }
    var card: Color { dark ? Color(red: 0.125, green: 0.148, blue: 0.155) : .white }
    var hero: Color { dark ? Color(red: 0.115, green: 0.208, blue: 0.211) : Color(red: 0.884, green: 0.956, blue: 0.941) }
    var accent: Color { dark ? Color(red: 0.42, green: 0.87, blue: 0.79) : Color(red: 0.08, green: 0.40, blue: 0.39) }
    var button: Color { dark ? Color(red: 0.10, green: 0.43, blue: 0.41) : Color(red: 0.07, green: 0.40, blue: 0.38) }
    var inkTeal: Color { Color(red: 0.09, green: 0.20, blue: 0.22) }
    var warning: Color { dark ? Color(red: 1, green: 0.75, blue: 0.43) : Color(red: 0.60, green: 0.32, blue: 0.10) }
    var border: Color { Color.primary.opacity(dark ? 0.12 : 0.095) }
}

private struct HarborSignal: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    let color: Color
    let wireless: Bool
    let active: Bool

    private static let grid: Path = {
        var path = Path()
        for column in -8...8 {
            for row in -4...4 where abs(column) + abs(row) < 10 {
                let x = CGFloat(column * 10)
                let y = CGFloat(row * 10)
                path.addEllipse(in: CGRect(x: x - 0.65, y: y - 0.65, width: 1.3, height: 1.3))
            }
        }
        return path
    }()

    var body: some View {
        let animate = active && appearsActive && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animate)) { timeline in
            let t = animate ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 108) : 0.85
            Canvas { context, size in
                var context = context
                context.translateBy(x: size.width / 2, y: size.height / 2)
                let scale = min(size.width / 190, size.height / 112)
                context.scaleBy(x: scale, y: scale)
                drawSignal(context, time: t)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func drawSignal(_ context: GraphicsContext, time: Double) {
        let shift = 2.0 * sin(time * .pi / 2)
        context.fill(Self.grid, with: .radialGradient(
            Gradient(colors: [color.opacity(0.29), color.opacity(0.02)]),
            center: .zero, startRadius: 12, endRadius: 87
        ))
        for ring in 0..<3 {
            let phase = (time / 2.7 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
            let expansion = phase * (2 - phase)
            let width = 84 + expansion * 98
            let height = 38 + expansion * 51
            let glow = Path(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                            cornerRadius: height / 2)
            context.stroke(glow, with: .color(color.opacity(sin(.pi * phase) * 0.21)), lineWidth: 0.85)
        }

        var mouse = context
        mouse.translateBy(x: 0, y: shift)
        let shell = Path(roundedRect: CGRect(x: -24, y: -35, width: 48, height: 70), cornerRadius: 22)
        mouse.fill(shell, with: .color(color.opacity(0.16)))
        mouse.stroke(shell, with: .color(color), lineWidth: 1.7)

        var seam = Path()
        seam.move(to: CGPoint(x: 0, y: -34))
        seam.addLine(to: CGPoint(x: 0, y: -7))
        seam.move(to: CGPoint(x: -22, y: -7))
        seam.addQuadCurve(to: CGPoint(x: 22, y: -7), control: CGPoint(x: 0, y: -3))
        mouse.stroke(seam, with: .color(color.opacity(0.80)), lineWidth: 1)

        let wheel = Path(roundedRect: CGRect(x: -3.25, y: -26, width: 6.5, height: 13), cornerRadius: 3.25)
        mouse.fill(wheel, with: .color(color))
        let sensor = Path(ellipseIn: CGRect(x: -1.5, y: 19, width: 3, height: 3))
        mouse.fill(sensor, with: .color(color.opacity(0.55 + 0.20 * sin(time * .pi))))

        if wireless {
            for index in 0..<2 {
                var arc = Path()
                let radius = CGFloat(6 + 4 * index)
                arc.addArc(center: CGPoint(x: 47, y: 1), radius: radius,
                           startAngle: .degrees(-142), endAngle: .degrees(-38), clockwise: false)
                context.stroke(arc, with: .color(color.opacity(0.48 + 0.16 * sin(time * .pi - Double(index)))),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
            let dot = Path(ellipseIn: CGRect(x: 45.8, y: 0.2, width: 2.4, height: 2.4))
            context.fill(dot, with: .color(color.opacity(0.64)))
        } else {
            var cable = Path()
            cable.move(to: CGPoint(x: 0, y: -35))
            cable.addCurve(to: CGPoint(x: 31, y: -49), control1: CGPoint(x: -1, y: -53),
                           control2: CGPoint(x: 17, y: -51))
            mouse.stroke(cable, with: .color(color.opacity(0.54)),
                         style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
    }
}

private struct DPIField: View {
    @Binding var value: Int
    var secondaryValue: Int
    var label: String
    @State private var edit = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: Binding(get: { focused ? edit : displayValue }, set: { input in
            update(input)
        }))
        .labelsHidden()
        .accessibilityLabel(label)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .font(.body.monospacedDigit())
        .focused($focused)
        .onChange(of: focused) { _, isFocused in
            if isFocused { edit = String(value) }
        }
        .onChange(of: value) { _, newValue in
            if focused && newValue != (Int(edit) ?? 0) { edit = String(newValue) }
        }
    }

    private var displayValue: String {
        value == secondaryValue ? String(value) : "\(value) × \(secondaryValue)"
    }

    private func update(_ input: String) {
        edit = String(input.filter { "0123456789".contains($0) }.prefix(5))
        value = Int(edit) ?? 0
    }
}
