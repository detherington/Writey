import SwiftUI

/// One document in the home screen list (iOS) or library window (Mac).
struct DocumentRow: View {
    let item: DocumentLibrary.Item
    let preview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                if !item.isDownloaded {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Downloading from iCloud")
                }
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let date = Self.format(item.modified)
        guard let preview else { return date }
        return "\(date)  \(preview.isEmpty ? "Empty" : preview)"
    }

    /// Today shows the time, yesterday says so, older shows the date — like Notes.
    private static func format(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
