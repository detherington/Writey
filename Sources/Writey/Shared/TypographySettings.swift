import SwiftUI

/// Font, size, line spacing and column width, with a live sample. Rows for
/// a Settings form on either platform.
struct TypographySettings: View {
    @EnvironmentObject var writing: WritingSettings

    var body: some View {
        Picker("Font", selection: $writing.typography.family) {
            ForEach(Typography.Family.allCases) { Text($0.label).tag($0) }
        }
        Picker("Size", selection: $writing.typography.size) {
            ForEach(Typography.Size.allCases) { Text($0.label).tag($0) }
        }
        Picker("Line Spacing", selection: $writing.typography.lineSpacing) {
            ForEach(Typography.LineSpacing.allCases) { Text($0.label).tag($0) }
        }
        Picker("Column Width", selection: $writing.typography.columnWidth) {
            ForEach(Typography.ColumnWidth.allCases) { Text($0.label).tag($0) }
        }
        sample
    }

    private var sample: some View {
        let typography = writing.typography
        let heading = typography.font(level: 2, bold: false, italic: false)
        let body = typography.font(level: 0, bold: false, italic: false)
        return VStack(alignment: .leading, spacing: 6) {
            Text("A quiet place to write")
                .font(Font(heading as CTFont))
            Text("The quick brown fox jumps over the lazy dog, then settles in for a few more pages.")
                .font(Font(body as CTFont))
                // Roughly the editor's line height multiple.
                .lineSpacing((typography.lineSpacing.multiple - 1) * body.pointSize * 1.2)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sample text")
    }
}

/// The same choices as menu items, where people look for a font: the
/// editor's Font menu, the iPhone's … menu and View in the menu bar. The
/// fonts sit inline with checkmarks; the rest are submenus.
struct TypographyMenuItems: View {
    @ObservedObject var writing: WritingSettings
    var includesFocus = true

    var body: some View {
        Picker("Font", selection: $writing.typography.family) {
            ForEach(Typography.Family.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.inline)
        Picker("Size", selection: $writing.typography.size) {
            ForEach(Typography.Size.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.menu)
        Picker("Line Spacing", selection: $writing.typography.lineSpacing) {
            ForEach(Typography.LineSpacing.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.menu)
        Picker("Column Width", selection: $writing.typography.columnWidth) {
            ForEach(Typography.ColumnWidth.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.menu)
        if includesFocus {
            Divider()
            Toggle("Focus Mode", isOn: $writing.focusMode)
        }
    }
}

/// Focus mode on or off, and whether it follows the sentence or the
/// paragraph.
struct FocusSettings: View {
    @EnvironmentObject var writing: WritingSettings

    var body: some View {
        Toggle("Focus Mode", isOn: $writing.focusMode)
        Picker("Focus On", selection: $writing.focusUnit) {
            ForEach(FocusUnit.allCases) { Text($0.label).tag($0) }
        }
    }

    static let explanation = "Dims everything but the sentence or paragraph you're writing, and keeps it in the middle of the screen."
}
