import Foundation

/// The editor's word count, shown as the window or navigation subtitle:
/// "1,234 words · 5 min read", or "56 of 1,234 words" with a selection.
struct WordCount: Equatable {
    var words = 0
    /// Nil when nothing is selected.
    var selectedWords: Int?

    /// A common silent-reading speed for adults.
    static let wordsPerMinute = 238.0

    var summary: String {
        let total = "\(words.formatted()) \(words == 1 ? "word" : "words")"
        if let selectedWords {
            return "\(selectedWords.formatted()) of \(total)"
        }
        guard words > 0 else { return total }
        let minutes = max(1, Int((Double(words) / Self.wordsPerMinute).rounded()))
        return "\(total) · \(minutes) min read"
    }

    /// Words as the system's word boundaries see them, so punctuation,
    /// hyphenation and non-Latin scripts count the way they do elsewhere.
    static func count(in text: String, range: NSRange? = nil) -> Int {
        let string = text as NSString
        let full = NSRange(location: 0, length: string.length)
        var count = 0
        string.enumerateSubstrings(in: range.map { NSIntersectionRange($0, full) } ?? full,
                                   options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

/// Recounts once typing pauses, off the main thread, so long documents
/// never slow down typing. The first count after opening is immediate.
@MainActor
final class WordCounter {
    var onUpdate: ((WordCount) -> Void)?

    private var pending: Task<Void, Never>?
    private var hasCounted = false

    func schedule(text: String, selection: NSRange) {
        pending?.cancel()
        let delay: Duration = hasCounted ? .milliseconds(250) : .zero
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) {
                WordCount(
                    words: WordCount.count(in: text),
                    selectedWords: selection.length > 0 ? WordCount.count(in: text, range: selection) : nil
                )
            }.value
            guard !Task.isCancelled, let self else { return }
            self.hasCounted = true
            self.onUpdate?(result)
        }
    }
}
