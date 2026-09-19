import SwiftUI

enum PerformanceTheme {
    // Daddy series: exact StorageDaddy Tints and app-owned black surfaces.
    static let fog = Color.black
    static let surface = Color.black
    static let ink = Color.white
    static let secondaryInk = Color(red: 0.78, green: 0.90, blue: 0.86)
    static let coral = Color(red: 0.90, green: 0.46, blue: 0.40)
    static let coralWash = coral.opacity(0.12)
    static let mintInk = Color(red: 0.42, green: 0.79, blue: 0.62)
    static let mint = mintInk.opacity(0.18)
    static let action = mintInk
    static let blue = Color(red: 0.33, green: 0.58, blue: 0.83)
    static let cyan = Color(red: 0.27, green: 0.70, blue: 0.75)
    static let amber = Color(red: 0.87, green: 0.67, blue: 0.28)
    static let divider = secondaryInk.opacity(0.18)
}

/// Shared Daddy-series control pattern, copied from StorageButtonStyle.
struct DaddyButtonStyle: ButtonStyle {
    var prominent = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.black : PerformanceTheme.mintInk)
            .background(prominent ? PerformanceTheme.mintInk : (hovering && isEnabled ? PerformanceTheme.mint : Color.black), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(PerformanceTheme.mintInk.opacity(prominent ? 1 : 0.35), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovering = $0 }
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DaddyButtonStyle(prominent: true).makeBody(configuration: configuration)
    }
}
