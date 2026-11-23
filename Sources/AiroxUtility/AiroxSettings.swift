struct DPIStage: Equatable, Sendable {
    var x: Int
    var y: Int
}

enum MouseModel: String, CaseIterable, Sendable {
    case airox = "IO Airox"
    case aurora = "IO Aurora"

    var debounceValues: [Int] {
        switch self {
        case .airox: AiroxSettings.debounceValues
        case .aurora: Array(AuroraSnapshot.debounceRange)
        }
    }

    var dpiRange: ClosedRange<Int> {
        switch self {
        case .airox: AiroxSettings.dpiRange
        case .aurora: AuroraSnapshot.dpiRange
        }
    }

    var buttonChoices: [ButtonAction] {
        switch self {
        case .airox: ButtonAction.choices
        case .aurora: AuroraButtons.choices
        }
    }

    func buttonName(at index: Int) -> String {
        if self == .aurora, index == 5 { return "Нижняя кнопка" }
        return AiroxSettings.buttonNames[index]
    }
}

struct ButtonAction: Hashable, Sendable {
    let kind: UInt8
    let first: UInt8
    let second: UInt8

    init(_ kind: UInt8, _ first: UInt8, _ second: UInt8 = 0) {
        self.kind = kind
        self.first = first
        self.second = second
    }

    private static let namedActions: [(ButtonAction, String)] = [
        (.init(0x10, 0x01), "Левый щелчок"),
        (.init(0x10, 0x02), "Правый щелчок"),
        (.init(0x10, 0x04), "Средний щелчок"),
        (.init(0x10, 0x08), "Назад"),
        (.init(0x10, 0x10), "Вперёд"),
        (.init(0x30, 0x32, 0x03), "Двойной щелчок"),
        (.init(0x20, 0x01), "Прокрутка вверх"),
        (.init(0x20, 0xff), "Прокрутка вниз"),
        (.init(0x40, 0x01), "Следующая ступень DPI"),
        (.init(0x40, 0x02), "Увеличить DPI"),
        (.init(0x40, 0x03), "Уменьшить DPI"),
        (.init(0x80, 0xcd), "Воспроизведение / пауза"),
        (.init(0x80, 0xb5), "Следующий трек"),
        (.init(0x80, 0xb6), "Предыдущий трек"),
        (.init(0x70, 0x08, 0x06), "Копировать ⌘C"),
        (.init(0x70, 0x08, 0x19), "Вставить ⌘V"),
        (.init(0x70, 0x08, 0x1b), "Вырезать ⌘X"),
        (.init(0x70, 0x08, 0x1d), "Отменить ⌘Z"),
        (.init(0x60, 0), "Отключена"),
    ]

    static let choices = namedActions.map(\.0)
    static let cycleReportRate = Self(0x7f, 0)

    var label: String {
        if self == Self.cycleReportRate { return "Следующая частота опроса" }
        return Self.namedActions.first { $0.0 == self }?.1 ?? "Назначение на устройстве"
    }

    var bytes: [UInt8] { [kind, first, second] }
}

struct AiroxSettings: Equatable, Sendable {
    static let dpiRange = 100...26000
    static let dpiStep = 50
    static let reportRates = [125, 250, 500, 1000]
    static let debounceValues = Array(4...20)
    static let buttonNames = ["Левая", "Правая", "Колесо", "Боковая «Назад»", "Боковая «Вперёд»", "Кнопка DPI"]

    var activeStage: Int
    var stages: [DPIStage]
    var reportRate: Int
    var debounce: Int
    var buttons: [ButtonAction]

    func mergingEdits(from baseline: Self, to edited: Self) -> Self {
        var merged = self
        if edited.activeStage != baseline.activeStage { merged.activeStage = edited.activeStage }
        if edited.reportRate != baseline.reportRate { merged.reportRate = edited.reportRate }
        if edited.debounce != baseline.debounce { merged.debounce = edited.debounce }
        for index in stages.indices where baseline.stages.indices.contains(index) && edited.stages.indices.contains(index) {
            if edited.stages[index] != baseline.stages[index] {
                merged.stages[index] = edited.stages[index]
            }
        }
        for index in buttons.indices where baseline.buttons.indices.contains(index) && edited.buttons.indices.contains(index) {
            if edited.buttons[index] != baseline.buttons[index] {
                merged.buttons[index] = edited.buttons[index]
            }
        }
        return merged
    }
}
