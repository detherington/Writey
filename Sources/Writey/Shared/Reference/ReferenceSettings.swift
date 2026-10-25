import SwiftUI

/// Where references open, and a way to sign out of the websites opened in
/// them. Rows for a Settings form on either platform.
struct ReferenceSettings: View {
    @EnvironmentObject var writing: WritingSettings
    @State private var confirmingClear = false
    @State private var cleared = false

    var body: some View {
        Picker("Reference Side", selection: $writing.referenceSide) {
            ForEach(ReferenceSide.allCases) { Text($0.label).tag($0) }
        }
        Button(cleared ? "Website Data Cleared" : "Clear Website Data…") {
            confirmingClear = true
        }
        .disabled(cleared)
        .confirmationDialog("Clear website data?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear Website Data", role: .destructive) {
                Task {
                    await ReferenceController.clearWebsiteData()
                    cleared = true
                }
            }
        } message: {
            Text("You'll be signed out of websites you've opened as references, and their cookies and caches will be removed.")
        }
    }

    static let explanation = "Each document remembers its own reference and side. Websites you open keep you signed in until you clear their data."
}
