import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Markdown ⇄ Writey's rich text, for .md files.
///
/// Only the Markdown Writey's toolbar can make is converted: `#`, `##` and
/// `###` headings, `**bold**`, `*italic*`, `<u>underline</u>`, and `-`
/// bulleted and `1.` numbered lists. Everything else — links, code, quotes,
/// tables, front matter, nested lists — stays as the text it was, shown as
/// typed and written back unchanged, so opening and saving a file never
/// loses Markdown that Writey doesn't model.
///
/// Each line of the file is one paragraph in the editor, blank lines
/// included, so the file's layout survives a round trip. Emphasis follows
/// CommonMark's delimiter rules both ways, so what Writey writes reads back
/// the same, here and in other Markdown apps.
enum MarkdownConverter {

    // MARK: - Reading

    static func attributedString(from markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        // "\r\n" is a single Character in Swift, so CRLF files need it named.
        let lines = markdown.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }
        var fence: Substring?
        var inFrontMatter = false
        var previousBlock: Block?
        var numberedList: NSTextList?
        var bulletList: NSTextList?

        for (index, line) in lines.enumerated() {
            let block: Block
            if index == 0 && line == "---" {
                inFrontMatter = true
                block = .literal(line)
            } else if inFrontMatter {
                if line == "---" || line == "..." { inFrontMatter = false }
                block = .literal(line)
            } else if let open = fence {
                if isClosingFence(line, for: open) { fence = nil }
                block = .literal(line)
            } else if let open = openingFence(line) {
                fence = open
                block = .literal(line)
            } else {
                block = Self.block(for: line)
            }

            // Consecutive items share one list so they count 1, 2, 3.
            var paragraph = WriteyDocument.defaultParagraphStyle()
            switch block {
            case .bullet:
                if case .bullet = previousBlock, let bulletList {
                    paragraph = listStyle(bulletList)
                } else {
                    let list = NSTextList(markerFormat: WriteyDocument.bulletListFormat, options: 0)
                    bulletList = list
                    paragraph = listStyle(list)
                }
            case .numbered(let number, _):
                if case .numbered = previousBlock, let numberedList {
                    paragraph = listStyle(numberedList)
                } else {
                    let list = NSTextList(markerFormat: WriteyDocument.numberedListFormat, options: 0)
                    list.startingItemNumber = number
                    numberedList = list
                    paragraph = listStyle(list)
                }
            default:
                break
            }
            previousBlock = block

            let baseFont: PlatformFont
            let text: Substring
            var parsesInline = true
            var isHeading = false
            switch block {
            case .literal(let line):
                baseFont = WriteyDocument.font(forHeadingLevel: 0)
                text = line
                parsesInline = false
            case .body(let line), .bullet(let line), .numbered(_, let line):
                baseFont = WriteyDocument.font(forHeadingLevel: 0)
                text = line
            case .heading(let level, let line):
                baseFont = WriteyDocument.font(forHeadingLevel: level)
                text = line
                isHeading = true
            }

            let spans = parsesInline ? inlineSpans(in: text) : [Span(text: String(text), style: InlineStyle())]
            for span in spans where !span.text.isEmpty {
                var attributes: [NSAttributedString.Key: Any] = [
                    // Headings are already heavy, so bold only applies to body text.
                    .font: baseFont.writeyWithTraits(bold: span.style.strong && !isHeading, italic: span.style.emphasis),
                    .paragraphStyle: paragraph
                ]
                if span.style.underline {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                output.append(NSAttributedString(string: span.text, attributes: attributes))
            }
            if index < lines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: [
                    .font: WriteyDocument.font(forHeadingLevel: 0),
                    .paragraphStyle: paragraph
                ]))
            }
        }
        return output
    }

    private enum Block {
        /// Shown and written exactly as it is.
        case literal(Substring)
        case body(Substring)
        case heading(level: Int, text: Substring)
        case bullet(Substring)
        case numbered(number: Int, text: Substring)
    }

    private static func block(for line: Substring) -> Block {
        if let heading = line.wholeMatch(of: #/(#{1,3})[ \t](.+)/#) {
            return .heading(level: heading.output.1.count, text: heading.output.2)
        }
        // `* * *` and `---` are rules, not list items.
        if line.wholeMatch(of: #/[ ]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*/#) != nil {
            return .literal(line)
        }
        if let bullet = line.wholeMatch(of: #/[-*+][ \t](.*)/#) {
            return .bullet(bullet.output.1)
        }
        if let numbered = line.wholeMatch(of: #/(\d{1,9})[.)][ \t](.*)/#), let number = Int(numbered.output.1) {
            return .numbered(number: number, text: numbered.output.2)
        }
        return .body(line)
    }

    private static func openingFence(_ line: Substring) -> Substring? {
        line.prefixMatch(of: #/[ ]{0,3}(`{3,}|~{3,})/#)?.output.1
    }

    private static func isClosingFence(_ line: Substring, for open: Substring) -> Bool {
        guard let close = line.wholeMatch(of: #/[ ]{0,3}(`{3,}|~{3,})[ \t]*/#)?.output.1 else { return false }
        return close.first == open.first && close.count >= open.count
    }

    private static func listStyle(_ list: NSTextList) -> NSMutableParagraphStyle {
        let style = WriteyDocument.defaultParagraphStyle()
        style.textLists = [list]
        style.headIndent = WriteyDocument.listIndent
        style.firstLineHeadIndent = 0
        return style
    }

    // MARK: Inline emphasis

    struct InlineStyle: Equatable {
        var strong = false
        var emphasis = false
        var underline = false
    }

    struct Span: Equatable {
        var text: String
        var style: InlineStyle
    }

    private enum Emphasis { case strong, emphasis }

    private struct Token {
        enum Kind { case text, delimiter, underlineOpen, underlineClose }
        var kind: Kind
        var text = ""
        // Delimiter runs (`*` or `_`):
        var character: Character = "*"
        var count = 0
        var originalCount = 0
        var canOpen = false
        var canClose = false
        var opens: [Emphasis] = []   // innermost first
        var closes: [Emphasis] = []  // innermost first
    }

    /// Splits a line into styled spans. Code spans, backslash escapes and
    /// unmatched delimiters stay literal.
    static func inlineSpans(in line: Substring) -> [Span] {
        var tokens = tokenize(Array(line))
        processEmphasis(&tokens)

        var spans: [Span] = []
        var strong = 0, emphasis = 0, underline = 0
        func append(_ text: String) {
            guard !text.isEmpty else { return }
            let style = InlineStyle(strong: strong > 0, emphasis: emphasis > 0, underline: underline > 0)
            if let last = spans.last, last.style == style {
                spans[spans.count - 1].text += text
            } else {
                spans.append(Span(text: text, style: style))
            }
        }
        for token in tokens {
            switch token.kind {
            case .text:
                append(token.text)
            case .underlineOpen:
                underline += 1
            case .underlineClose:
                underline = max(0, underline - 1)
            case .delimiter:
                for closed in token.closes {
                    if closed == .strong { strong = max(0, strong - 1) } else { emphasis = max(0, emphasis - 1) }
                }
                append(String(repeating: token.character, count: token.count))
                for opened in token.opens.reversed() {
                    if opened == .strong { strong += 1 } else { emphasis += 1 }
                }
            }
        }
        return spans
    }

    private static func tokenize(_ chars: [Character]) -> [Token] {
        var tokens: [Token] = []
        var text = ""
        func flush() {
            if !text.isEmpty { tokens.append(Token(kind: .text, text: text)); text = "" }
        }
        // `<u>` pairs, matched up front so a stray tag stays literal.
        var underlineOpens: Set<Int> = [], underlineCloses: Set<Int> = []
        var pendingOpens: [Int] = []
        var scan = 0
        while scan < chars.count {
            if chars[scan] == "\\" {
                scan += 2
            } else if chars[scan] == "`" {
                let run = runLength(chars, at: scan)
                scan = closingBacktickRun(chars, from: scan + run, length: run).map { $0 + run } ?? scan + run
            } else if hasPrefix(chars, at: scan, "<u>") {
                pendingOpens.append(scan); scan += 3
            } else if hasPrefix(chars, at: scan, "</u>"), let open = pendingOpens.popLast() {
                underlineOpens.insert(open); underlineCloses.insert(scan); scan += 4
            } else {
                scan += 1
            }
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                text.append(c); text.append(chars[i + 1]); i += 2
            } else if c == "`" {
                let run = runLength(chars, at: i)
                if let close = closingBacktickRun(chars, from: i + run, length: run) {
                    text.append(contentsOf: chars[i..<(close + run)]); i = close + run
                } else {
                    text.append(contentsOf: chars[i..<(i + run)]); i += run
                }
            } else if underlineOpens.contains(i) {
                flush(); tokens.append(Token(kind: .underlineOpen)); i += 3
            } else if underlineCloses.contains(i) {
                flush(); tokens.append(Token(kind: .underlineClose)); i += 4
            } else if c == "*" || c == "_" {
                flush()
                let run = runLength(chars, at: i)
                let before: Character? = i > 0 ? chars[i - 1] : nil
                let after: Character? = i + run < chars.count ? chars[i + run] : nil
                let left = isLeftFlanking(before: before, after: after)
                let right = isRightFlanking(before: before, after: after)
                var token = Token(kind: .delimiter, character: c, count: run, originalCount: run)
                if c == "*" {
                    token.canOpen = left
                    token.canClose = right
                } else {
                    // `_` can't open or close inside a word (snake_case stays literal).
                    token.canOpen = left && (!right || isPunctuation(before))
                    token.canClose = right && (!left || isPunctuation(after))
                }
                tokens.append(token)
                i += run
            } else {
                text.append(c); i += 1
            }
        }
        flush()
        return tokens
    }

    /// CommonMark's "process emphasis": match each closer with the nearest
    /// opener of the same character, using two characters (strong) when both
    /// runs have them, else one (emphasis).
    private static func processEmphasis(_ tokens: inout [Token]) {
        for closer in tokens.indices where tokens[closer].kind == .delimiter {
            while tokens[closer].canClose && tokens[closer].count > 0 {
                var opener: Int?
                var candidate = closer - 1
                while candidate >= 0 {
                    let o = tokens[candidate]
                    if o.kind == .delimiter, o.character == tokens[closer].character, o.canOpen, o.count > 0 {
                        let c = tokens[closer]
                        let ruleOfThree = (o.canClose || c.canOpen)
                            && (o.originalCount + c.originalCount) % 3 == 0
                            && !(o.originalCount % 3 == 0 && c.originalCount % 3 == 0)
                        if !ruleOfThree { opener = candidate; break }
                    }
                    candidate -= 1
                }
                guard let opener else { break }
                let use = tokens[opener].count >= 2 && tokens[closer].count >= 2 ? 2 : 1
                let kind: Emphasis = use == 2 ? .strong : .emphasis
                tokens[opener].count -= use
                tokens[closer].count -= use
                tokens[opener].opens.append(kind)
                tokens[closer].closes.append(kind)
                for between in (opener + 1)..<closer where tokens[between].kind == .delimiter {
                    tokens[between].canOpen = false
                    tokens[between].canClose = false
                }
            }
        }
    }

    private static func runLength(_ chars: [Character], at start: Int) -> Int {
        var end = start
        while end < chars.count && chars[end] == chars[start] { end += 1 }
        return end - start
    }

    private static func closingBacktickRun(_ chars: [Character], from start: Int, length: Int) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == "`" {
                let run = runLength(chars, at: i)
                if run == length { return i }
                i += run
            } else {
                i += 1
            }
        }
        return nil
    }

    private static func hasPrefix(_ chars: [Character], at index: Int, _ prefix: String) -> Bool {
        let p = Array(prefix)
        return index + p.count <= chars.count && Array(chars[index..<(index + p.count)]) == p
    }

    private static func isWhitespace(_ c: Character?) -> Bool { c.map(\.isWhitespace) ?? true }
    private static func isPunctuation(_ c: Character?) -> Bool { c.map { $0.isPunctuation || $0.isSymbol } ?? false }

    private static func isLeftFlanking(before: Character?, after: Character?) -> Bool {
        guard !isWhitespace(after) else { return false }
        return !isPunctuation(after) || isWhitespace(before) || isPunctuation(before)
    }

    private static func isRightFlanking(before: Character?, after: Character?) -> Bool {
        guard !isWhitespace(before) else { return false }
        return !isPunctuation(before) || isWhitespace(after) || isPunctuation(after)
    }

    // MARK: - Writing

    static func markdown(from text: NSAttributedString) -> String {
        var lines: [String] = []
        var previousNumber: Int?
        var location = 0
        for line in text.string.components(separatedBy: "\n") {
            let length = (line as NSString).length
            let range = NSRange(location: location, length: length)
            // An empty paragraph's style lives on its newline, if it has one.
            let styleIndex = location < text.length ? location : nil
            location += length + 1

            let paragraph = styleIndex.flatMap { text.attribute(.paragraphStyle, at: $0, effectiveRange: nil) as? NSParagraphStyle }
            let content = text.attributedSubstring(from: range)

            if let list = paragraph?.textLists.first {
                if isNumbered(list) {
                    let number = previousNumber.map { $0 + 1 } ?? list.startingItemNumber
                    lines.append("\(number). " + inlineMarkdown(content, isHeading: false))
                    previousNumber = number
                } else {
                    lines.append("- " + inlineMarkdown(content, isHeading: false))
                    previousNumber = nil
                }
                continue
            }
            previousNumber = nil

            guard length > 0 else {
                lines.append("")
                continue
            }
            let level = headingLevel(of: content)
            if level > 0 {
                lines.append(String(repeating: "#", count: level) + " " + inlineMarkdown(content, isHeading: true))
            } else {
                lines.append(inlineMarkdown(content, isHeading: false))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func isNumbered(_ list: NSTextList) -> Bool {
        list.markerFormat == WriteyDocument.numberedListFormat || list.markerFormat.rawValue.contains("decimal")
    }

    /// Writey's heading sizes are 28, 22 and 18 against a 16pt body.
    private static func headingLevel(of paragraph: NSAttributedString) -> Int {
        let firstVisible = (paragraph.string as NSString).rangeOfCharacter(from: CharacterSet.whitespaces.inverted)
        guard firstVisible.location != NSNotFound,
              let font = paragraph.attribute(.font, at: firstVisible.location, effectiveRange: nil) as? PlatformFont
        else { return 0 }
        switch font.pointSize {
        case 25...: return 1
        case 20..<25: return 2
        case 17..<20: return 3
        default: return 0
        }
    }

    private struct Run {
        var text: String
        var style: InlineStyle
        var link: String?
    }

    private static func inlineMarkdown(_ paragraph: NSAttributedString, isHeading: Bool) -> String {
        var runs: [Run] = []
        paragraph.enumerateAttributes(in: NSRange(location: 0, length: paragraph.length)) { attributes, range, _ in
            let font = attributes[.font] as? PlatformFont
            let style = InlineStyle(
                strong: !isHeading && font?.writeyIsBold == true,
                emphasis: font?.writeyIsItalic == true,
                underline: (attributes[.underlineStyle] as? Int ?? 0) != 0
            )
            let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
            let text = (paragraph.string as NSString).substring(with: range)
            if let last = runs.last, last.style == style, last.link == link {
                runs[runs.count - 1].text += text
            } else {
                runs.append(Run(text: text, style: style, link: link))
            }
        }

        var output = ""
        for group in grouped(runs, by: \.link) {
            let inner = emitStrong(group)
            if let link = group[0].link {
                output += "[\(inner)](\(link))"
            } else {
                output += inner
            }
        }
        return output
    }

    // Bold outermost, then italic, then underline, so nesting is always
    // well formed: **a *b* c**.
    private static func emitStrong(_ runs: [Run]) -> String {
        grouped(runs, by: \.style.strong).map { wrap(emitEmphasis($0), "**", "**", when: $0[0].style.strong) }.joined()
    }

    private static func emitEmphasis(_ runs: [Run]) -> String {
        grouped(runs, by: \.style.emphasis).map { wrap(emitUnderline($0), "*", "*", when: $0[0].style.emphasis) }.joined()
    }

    private static func emitUnderline(_ runs: [Run]) -> String {
        grouped(runs, by: \.style.underline).map { group in
            wrap(group.map(\.text).joined(), "<u>", "</u>", when: group[0].style.underline)
        }.joined()
    }

    /// Markers can't sit next to whitespace, so edge spaces go outside them.
    private static func wrap(_ content: String, _ open: String, _ close: String, when active: Bool) -> String {
        guard active else { return content }
        let lead = content.prefix(while: \.isWhitespace)
        let rest = content.dropFirst(lead.count)
        let trail = rest.reversed().prefix(while: \.isWhitespace)
        let core = rest.dropLast(trail.count)
        guard !core.isEmpty else { return content }
        return String(lead) + open + String(core) + close + String(trail.reversed())
    }

    private static func grouped<Key: Equatable>(_ runs: [Run], by key: KeyPath<Run, Key>) -> [[Run]] {
        var groups: [[Run]] = []
        for run in runs {
            if let last = groups.last?.last, last[keyPath: key] == run[keyPath: key] {
                groups[groups.count - 1].append(run)
            } else {
                groups.append([run])
            }
        }
        return groups
    }
}
