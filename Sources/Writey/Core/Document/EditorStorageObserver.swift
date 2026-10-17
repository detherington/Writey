import Foundation

#if canImport(AppKit)
import AppKit
typealias TextStorageEditActions = NSTextStorageEditActions
#elseif canImport(UIKit)
import UIKit
typealias TextStorageEditActions = NSTextStorage.EditActions
#endif

/// Text-storage delegate shared by both editors.
///
/// Every edit — typing, paste, native ⌘B, toolbar formatting, undo, a sync
/// pull, loading a document — passes through `processEditing`, so this is
/// the one place that (a) shows Writey's styles in the reader's typography,
/// (b) gives newly inserted text the theme color, so pasted or pulled text
/// never renders black-on-black, and (c) tells the editor the text changed
/// so it can copy it into the document.
final class EditorStorageObserver: NSObject, NSTextStorageDelegate {
    var textColor: PlatformColor?
    var typography: Typography?
    var onChange: ((NSTextStorage) -> Void)?

    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: TextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedRange.length > 0 else { return }
        typography?.applyDisplay(to: textStorage, in: editedRange)
        if editedMask.contains(.editedCharacters), let textColor {
            textStorage.addAttribute(.foregroundColor, value: textColor, range: editedRange)
        }
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: TextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        onChange?(textStorage)
    }
}
