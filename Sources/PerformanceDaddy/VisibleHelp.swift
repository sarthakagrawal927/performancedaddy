import SwiftUI

struct HelpAnchor {
    let text: String
    let leading: Bool
    let bounds: Anchor<CGRect>
}

struct HelpAnchorKey: PreferenceKey {
    static var defaultValue: [HelpAnchor] { [] }
    static func reduce(value: inout [HelpAnchor], nextValue: () -> [HelpAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

private struct VisibleHelp: ViewModifier {
    let text: String
    var leading = false
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .help(text)
            .onHover { hovering = $0 }
            .anchorPreference(key: HelpAnchorKey.self, value: .bounds) { bounds in
                hovering ? [HelpAnchor(text: text, leading: leading, bounds: bounds)] : []
            }
            .onDisappear { hovering = false }
    }
}

extension View {
    func visibleHelp(_ text: String, leading: Bool = false) -> some View { modifier(VisibleHelp(text: text, leading: leading)) }

    /// Resolve anchors at the page level so native lists and split panes cannot
    /// clip or paint over the bubble. Help never intercepts a click or focus.
    func helpOverlay() -> some View {
        overlayPreferenceValue(HelpAnchorKey.self) { anchors in
            GeometryReader { geometry in
                if let help = anchors.last {
                    let bounds = geometry[help.bounds]
                    let width = min(270, max(0, geometry.size.width - 24))
                    let proposedX = help.leading ? bounds.minX : bounds.maxX - width
                    let x = max(12, min(proposedX, geometry.size.width - width - 12))
                    Text(help.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PerformanceTheme.secondaryInk)
                        .lineSpacing(3)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(width: width, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(Color(red: 0.055, green: 0.085, blue: 0.073), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(PerformanceTheme.mintInk.opacity(0.28), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 5)
                        .offset(x: x, y: bounds.maxY + 9)
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true).zIndex(10_000)
        }
    }
}
