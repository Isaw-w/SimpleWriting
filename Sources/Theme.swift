import AppKit

/// Light/dark theme for SimpleWriting, stored in the app's own defaults and
/// defaulting to light when nothing is set.
enum Theme: String {
    case white
    case black

    static let defaultsKey = "theme"

    static var current: Theme {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey), let theme = Theme(rawValue: raw) { return theme }
        return .white
    }

    var isDark: Bool { self == .black }
    var appearanceName: NSAppearance.Name { isDark ? .darkAqua : .aqua }

    var primaryText: NSColor {
        isDark ? NSColor(calibratedWhite: 0.95, alpha: 1) : NSColor(calibratedWhite: 0.12, alpha: 1)
    }
    var readableSecondaryText: NSColor {
        isDark ? NSColor.white.withAlphaComponent(0.85) : NSColor.black.withAlphaComponent(0.68)
    }
    var readableTertiaryText: NSColor {
        isDark ? NSColor.white.withAlphaComponent(0.60) : NSColor.black.withAlphaComponent(0.48)
    }
}
