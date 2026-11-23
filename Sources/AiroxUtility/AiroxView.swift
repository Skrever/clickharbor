import AppKit
import SwiftUI

struct AiroxView: View {
    @ObservedObject var model: AiroxModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = Page.settings
    @Namespace private var sidebarSelection

    private enum Page: String, CaseIterable {
        case settings = "Настройки"
        case buttons = "Кнопки"

        var symbol: String {
            switch self {
            case .settings: "slider.horizontal.3"
            case .buttons: "cursorarrow.click.2"
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
                        case .buttons:
                            buttons(draft)
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
                    Text("Ступень \(draft.activeStage + 1) из \(draft.stages.count)")
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

            VStack(spacing: 3) {
                ForEach(draft.stages.indices, id: \.self) { index in
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

            DPIField(value: stageValue(index), secondaryValue: draft.stages[index].y,
                     label: "Ступень \(index + 1), DPI")
                .frame(width: 102)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? palette.accent.opacity(0.10) : Color.clear)
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
                                Text(action.label).tag(action)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220)
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
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
