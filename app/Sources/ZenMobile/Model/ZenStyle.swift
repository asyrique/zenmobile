import SwiftUI
import ZenCore

extension ZenSpaceTheme {
    /// Desktop's gradient, top-leading to bottom-trailing, at the theme's opacity.
    var gradient: LinearGradient {
        let stops = colors.isEmpty ? [ZenThemeColor.zenDefault] : colors
        return LinearGradient(
            colors: stops.map { $0.color.opacity(max(0.35, opacity)) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }
}

extension ZenThemeColor {
    static let zenDefault = ZenThemeColor(red: 76, green: 45, blue: 130, isPrimary: true)

    var color: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

extension ZenSpace {
    var background: LinearGradient {
        (theme ?? ZenSpaceTheme(colors: [], opacity: 1, texture: 0, rawJson: "")).gradient
    }

    /// Desktop icons are emoji or `chrome://` URLs for Zen's bundled SVGs,
    /// which we don't ship. Those fall back to a dot.
    var emoji: String? {
        guard let icon, !icon.hasPrefix("chrome://"), !icon.hasPrefix("data:") else { return nil }
        return icon
    }
}

extension ZenTab {
    var displayHost: String {
        URL(string: url)?.host ?? url
    }
}
