import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension NSAttributedString.Key {
    /// Writey's style for a run of text the editor shows in the reader's
    /// typography: 0 body, 1 title, 2 heading, 3 subheading. Editor-only;
    /// `writeyCanonicalForm()` maps the run back and removes it.
    static let writeyTextStyle = NSAttributedString.Key("WriteyTextStyle")
}

/// How the editor shows text: font, size, line spacing and column width.
///
/// Display only, like the theme. Files keep Writey's standard styles
/// (system font, 16pt body, 28/22/18pt headings, 1.4 line spacing), so a
/// document looks the same in other apps, in Markdown and in Google Docs,
/// whatever each reader picks. Text with a font of its own — pasted, or
/// pulled from Google Docs — keeps it.
struct Typography: Equatable {
    enum Family: String, CaseIterable, Identifiable {
        case sans, serif, mono
        var id: String { rawValue }
        var label: String {
            switch self {
            case .sans:  return "Sans"
            case .serif: return "Serif"
            case .mono:  return "Mono"
            }
        }
    }

    enum Size: String, CaseIterable, Identifiable {
        case small, standard, large, larger, largest
        var id: String { rawValue }
        var label: String {
            switch self {
            case .small:    return "Small"
            case .standard: return "Default"
            case .large:    return "Large"
            case .larger:   return "Larger"
            case .largest:  return "Largest"
            }
        }
        /// Body size; headings scale with it. None of these scales lands a
        /// style on another style's standard size, which is what lets
        /// `level(of:)` tell a Writey style from its size alone.
        var bodySize: CGFloat {
            switch self {
            case .small:    return 14
            case .standard: return 16
            case .large:    return 19
            case .larger:   return 21
            case .largest:  return 24
            }
        }
        var scale: CGFloat { bodySize / 16 }
    }

    enum LineSpacing: String, CaseIterable, Identifiable {
        case tight, standard, relaxed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tight:    return "Tight"
            case .standard: return "Default"
            case .relaxed:  return "Relaxed"
            }
        }
        var multiple: CGFloat {
            switch self {
            case .tight:    return 1.2
            case .standard: return Typography.standardLineSpacing
            case .relaxed:  return 1.7
            }
        }
    }

    enum ColumnWidth: String, CaseIterable, Identifiable {
        case narrow, medium, wide, full
        var id: String { rawValue }
        var label: String {
            switch self {
            case .narrow: return "Narrow"
            case .medium: return "Medium"
            case .wide:   return "Wide"
            case .full:   return "Full Width"
            }
        }
        /// Widest the writing column gets, insets included; nil fills the window.
        var maxWidth: CGFloat? {
            switch self {
            case .narrow: return 560
            case .medium: return 720
            case .wide:   return 900
            case .full:   return nil
            }
        }
    }

    var family: Family = .sans
    var size: Size = .standard
    var lineSpacing: LineSpacing = .standard
    var columnWidth: ColumnWidth = .medium

    static var standardLineSpacing: CGFloat { WriteyDocument.defaultParagraphStyle().lineHeightMultiple }

    // MARK: - Display

    /// The font the editor shows for a Writey style. Headings are already
    /// heavy, so bold only applies to body text — as in Markdown.
    func font(level: Int, bold: Bool, italic: Bool) -> PlatformFont {
        let key = "\(family.rawValue)-\(size.rawValue)-\(level)-\(bold)-\(italic)" as NSString
        if let cached = Self.fontCache.object(forKey: key) { return cached }
        let standard = WriteyDocument.font(forHeadingLevel: level)
        let font = standard
            .writeyResized(to: standard.pointSize * size.scale)
            .writeyWithDesign(family)
            .writeyWithTraits(bold: bold && level == 0, italic: italic)
        Self.fontCache.setObject(font, forKey: key)
        return font
    }

    private static let fontCache = NSCache<NSString, PlatformFont>()

    func paragraphStyle(from style: NSParagraphStyle?) -> NSParagraphStyle {
        let paragraph = Self.standardParagraphStyle(from: style)
        paragraph.lineHeightMultiple = lineSpacing.multiple
        if !paragraph.textLists.isEmpty {
            paragraph.headIndent = WriteyDocument.listIndent * size.scale
        }
        return paragraph
    }

    /// Re-styles the Writey text in `range` for display and tags it with its
    /// style, leaving text with a font of its own alone.
    func applyDisplay(to text: NSMutableAttributedString, in range: NSRange) {
        text.enumerateAttributes(in: range) { attributes, run, _ in
            guard let font = attributes[.font] as? PlatformFont,
                  let level = level(of: font, tagged: attributes[.writeyTextStyle] as? Int)
            else { return }
            text.addAttributes([
                .font: self.font(level: level, bold: font.writeyIsBold, italic: font.writeyIsItalic),
                .writeyTextStyle: level,
                .paragraphStyle: paragraphStyle(from: attributes[.paragraphStyle] as? NSParagraphStyle)
            ], range: run)
        }
    }

    /// The same, for a text view's typing attributes.
    func displayAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        guard let font = attributes[.font] as? PlatformFont,
              let level = level(of: font, tagged: attributes[.writeyTextStyle] as? Int)
        else { return attributes }
        var shown = attributes
        shown[.font] = self.font(level: level, bold: font.writeyIsBold, italic: font.writeyIsItalic)
        shown[.writeyTextStyle] = level
        shown[.paragraphStyle] = paragraphStyle(from: attributes[.paragraphStyle] as? NSParagraphStyle)
        return shown
    }

    /// Writey's style for a run: its tag, else a standard Writey font, else a
    /// font shown in this typography that lost its tag (copied and pasted).
    /// Nil for text with a font of its own.
    func level(of font: PlatformFont, tagged: Int?) -> Int? {
        if let tagged { return tagged }
        if let level = Self.standardLevel(of: font) { return level }
        let shownFamily = self.font(level: 0, bold: false, italic: false).familyName
        guard font.familyName == shownFamily else { return nil }
        return (0...3).first { abs(font.pointSize - WriteyDocument.font(forHeadingLevel: $0).pointSize * size.scale) < 0.1 }
    }

    // MARK: - Standard styles (what files keep)

    static func standardLevel(of font: PlatformFont) -> Int? {
        guard font.writeyIsSystemFont else { return nil }
        return (0...3).first { abs(font.pointSize - WriteyDocument.font(forHeadingLevel: $0).pointSize) < 0.1 }
    }

    static func standardFont(level: Int, bold: Bool, italic: Bool) -> PlatformFont {
        WriteyDocument.font(forHeadingLevel: level).writeyWithTraits(bold: bold && level == 0, italic: italic)
    }

    static func standardParagraphStyle(from style: NSParagraphStyle?) -> NSMutableParagraphStyle {
        let paragraph = (style?.mutableCopy() as? NSMutableParagraphStyle) ?? WriteyDocument.defaultParagraphStyle()
        paragraph.lineHeightMultiple = standardLineSpacing
        if !paragraph.textLists.isEmpty {
            paragraph.headIndent = WriteyDocument.listIndent
            paragraph.firstLineHeadIndent = 0
        }
        return paragraph
    }
}

// MARK: - Font helpers

extension PlatformFont {
    /// The font of Writey's standard styles: the system font, under any of
    /// the names it comes back as when Writey's .rtf files are reopened. The
    /// RTF writer can't store the system font as such, so it saves it as
    /// "HelveticaNeue" on the Mac and ".SFUI-Regular" on iOS, and each
    /// platform reads those back as its own family.
    var writeyIsSystemFont: Bool {
        writeyFamilyName.map(Self.standardFamilyNames.contains) ?? false
    }

    /// `familyName` is optional on the Mac only.
    var writeyFamilyName: String? { familyName }

    private static let standardFamilyNames: Set<String> = {
        func family(readingRTFFont name: String) -> String? {
            let rtf = "{\\rtf1\\ansi{\\fonttbl\\f0\\fnil\\fcharset0 \(name);}\\f0\\fs32 x}"
            let text = try? NSAttributedString(
                data: Data(rtf.utf8),
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return (text?.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.writeyFamilyName
        }
        // A name no font has shows what the reader falls back to; that
        // family isn't Writey's, so it never counts.
        let fallback = family(readingRTFFont: "WriteyNoSuchFont")
        var names: Set<String> = ["Helvetica Neue"]
        if let system = PlatformFont.systemFont(ofSize: 16).writeyFamilyName { names.insert(system) }
        for name in ["HelveticaNeue", ".SFUI-Regular", ".SFNS-Regular", ".AppleSystemUIFont"] {
            if let read = family(readingRTFFont: name), read != fallback { names.insert(read) }
        }
        return names
    }()

    #if canImport(AppKit)
    var writeyIsBold: Bool { fontDescriptor.symbolicTraits.contains(.bold) }
    var writeyIsItalic: Bool { fontDescriptor.symbolicTraits.contains(.italic) }

    func writeyWithTraits(bold: Bool, italic: Bool) -> NSFont {
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        guard traits != fontDescriptor.symbolicTraits else { return self }
        return NSFont(descriptor: fontDescriptor.withSymbolicTraits(traits), size: pointSize) ?? self
    }

    func writeyResized(to size: CGFloat) -> NSFont {
        size == pointSize ? self : NSFont(descriptor: fontDescriptor, size: size) ?? self
    }

    func writeyWithDesign(_ family: Typography.Family) -> NSFont {
        let design: NSFontDescriptor.SystemDesign
        switch family {
        case .sans:  return self
        case .serif: design = .serif
        case .mono:  design = .monospaced
        }
        guard let descriptor = fontDescriptor.withDesign(design) else { return self }
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
    #else
    var writeyIsBold: Bool { fontDescriptor.symbolicTraits.contains(.traitBold) }
    var writeyIsItalic: Bool { fontDescriptor.symbolicTraits.contains(.traitItalic) }

    func writeyWithTraits(bold: Bool, italic: Bool) -> UIFont {
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard traits != fontDescriptor.symbolicTraits,
              let descriptor = fontDescriptor.withSymbolicTraits(traits)
        else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }

    func writeyResized(to size: CGFloat) -> UIFont {
        size == pointSize ? self : withSize(size)
    }

    func writeyWithDesign(_ family: Typography.Family) -> UIFont {
        let design: UIFontDescriptor.SystemDesign
        switch family {
        case .sans:  return self
        case .serif: design = .serif
        case .mono:  design = .monospaced
        }
        guard let descriptor = fontDescriptor.withDesign(design) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
    #endif
}
