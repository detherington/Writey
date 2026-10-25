import SwiftUI

/// The writing and the reference side by side, split by a draggable
/// divider. The editor keeps the same place in the view tree whether the
/// reference is shown, hidden or swapped, so its cursor, scroll position
/// and undo history are never reset.
struct EditorSplitLayout<Editor: View, Reference: View>: View {
    let showsReference: Bool
    let side: ReferenceSide
    @Binding var fraction: Double
    var onResizeEnded: () -> Void = {}
    @ViewBuilder var editor: () -> Editor
    @ViewBuilder var reference: () -> Reference

    static var minimumEditorWidth: CGFloat { 420 }
    static var minimumReferenceWidth: CGFloat { 320 }

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let total = geometry.size.width
            let width = referenceWidth(in: total)
            HStack(spacing: 0) {
                if showsReference && side == .left {
                    reference().frame(width: width)
                    divider(total: total, width: width)
                }
                editor()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsReference && side == .right {
                    divider(total: total, width: width)
                    reference().frame(width: width)
                }
            }
        }
    }

    private func referenceWidth(in total: CGFloat) -> CGFloat {
        let wanted = total * fraction
        let widest = max(Self.minimumReferenceWidth, total - Self.minimumEditorWidth)
        return min(max(wanted, Self.minimumReferenceWidth), widest)
    }

    /// A hairline flush with both panes, with a wider grab area laid over
    /// their edges. Dragging toward the editor makes the reference wider.
    private func divider(total: CGFloat, width: CGFloat) -> some View {
        Rectangle()
            .fill(EditorPalette.chromeStroke(colorScheme))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay { grabArea(total: total, width: width) }
            // Above both panes, so the grab area's overhang gets the drag.
            .zIndex(1)
    }

    private func grabArea(total: CGFloat, width: CGFloat) -> some View {
        Color.clear
            .frame(width: 9)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStartWidth ?? width
                        dragStartWidth = start
                        let delta = side == .right ? -drag.translation.width : drag.translation.width
                        fraction = Double((start + delta) / max(total, 1))
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        onResizeEnded()
                    }
            )
            #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            #else
            .hoverEffect(.highlight)
            #endif
            .accessibilityLabel("Resize reference")
    }
}
