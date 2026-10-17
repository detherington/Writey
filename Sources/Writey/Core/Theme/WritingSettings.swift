import SwiftUI

/// The reader's typography and focus mode. Kept per device, like the
/// theme: they change how Writey shows text, never the documents.
@MainActor
final class WritingSettings: ObservableObject {
    @Published var typography: Typography { didSet { save() } }
    @Published var focusMode: Bool { didSet { save() } }
    @Published var focusUnit: FocusUnit { didSet { save() } }

    private let defaults: UserDefaults

    private enum Key {
        static let family = "WriteyFontFamily"
        static let size = "WriteyTextSize"
        static let lineSpacing = "WriteyLineSpacing"
        static let columnWidth = "WriteyColumnWidth"
        static let focusMode = "WriteyFocusMode"
        static let focusUnit = "WriteyFocusUnit"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var typography = Typography()
        if let family = defaults.string(forKey: Key.family).flatMap(Typography.Family.init) { typography.family = family }
        if let size = defaults.string(forKey: Key.size).flatMap(Typography.Size.init) { typography.size = size }
        if let spacing = defaults.string(forKey: Key.lineSpacing).flatMap(Typography.LineSpacing.init) { typography.lineSpacing = spacing }
        if let width = defaults.string(forKey: Key.columnWidth).flatMap(Typography.ColumnWidth.init) { typography.columnWidth = width }
        self.typography = typography
        self.focusMode = defaults.bool(forKey: Key.focusMode)
        self.focusUnit = defaults.string(forKey: Key.focusUnit).flatMap(FocusUnit.init) ?? .sentence
    }

    private func save() {
        defaults.set(typography.family.rawValue, forKey: Key.family)
        defaults.set(typography.size.rawValue, forKey: Key.size)
        defaults.set(typography.lineSpacing.rawValue, forKey: Key.lineSpacing)
        defaults.set(typography.columnWidth.rawValue, forKey: Key.columnWidth)
        defaults.set(focusMode, forKey: Key.focusMode)
        defaults.set(focusUnit.rawValue, forKey: Key.focusUnit)
    }

    // MARK: - View ▸ Bigger / Smaller

    var canMakeTextBigger: Bool { typography.size != Typography.Size.allCases.last }
    var canMakeTextSmaller: Bool { typography.size != Typography.Size.allCases.first }

    func makeTextBigger() { stepTextSize(by: 1) }
    func makeTextSmaller() { stepTextSize(by: -1) }

    private func stepTextSize(by step: Int) {
        let sizes = Typography.Size.allCases
        guard let index = sizes.firstIndex(of: typography.size), sizes.indices.contains(index + step) else { return }
        typography.size = sizes[index + step]
    }
}
