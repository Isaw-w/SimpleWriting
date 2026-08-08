import AppKit

/// One source of truth for the Hemingway highlight colors, shared by the Grammar
/// Gate edit panel and the standalone Writing Editor so the two never drift. Each
/// category maps to a hue in the spirit of the Hemingway Editor: red for blocking
/// errors, blue for adverbs, green for passive voice, purple for wordy/precision,
/// amber for hard sentences, cyan for phrasing.
enum HemingwayPalette {
    /// Base (fully opaque) color for a finding — used for popover accents and as
    /// the source color for the translucent text fill.
    static func color(for error: GrammarError, dark: Bool) -> NSColor {
        guard error.kind == .nativeSuggestion else { return errorColor(dark) }
        switch error.focus {
        case .precision, .concision: return precisionColor(dark)
        case .adverb: return adverbColor(dark)
        case .passiveVoice: return passiveColor(dark)
        case .sentenceClarity: return warnColor(dark)
        case .nativePhrasing: return clarityColor(dark)
        case .grammar, .spelling: return warnColor(dark)
        }
    }

    /// Alpha for the text-background fill. Kept light enough that the writer's
    /// text stays fully readable on top in both themes.
    static func fillAlpha(dark: Bool) -> CGFloat { dark ? 0.34 : 0.22 }

    static func fillColor(for error: GrammarError, dark: Bool) -> NSColor {
        color(for: error, dark: dark).withAlphaComponent(fillAlpha(dark: dark))
    }

    // MARK: - Hues

    static func warnColor(_ dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.40, alpha: 1)
             : NSColor(calibratedRed: 0.80, green: 0.52, blue: 0.05, alpha: 1)
    }

    static func errorColor(_ dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.42, alpha: 1)
             : NSColor(calibratedRed: 0.82, green: 0.16, blue: 0.16, alpha: 1)
    }

    static func precisionColor(_ dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.78, green: 0.60, blue: 1.0, alpha: 1)
             : NSColor(calibratedRed: 0.43, green: 0.26, blue: 0.72, alpha: 1)
    }

    static func clarityColor(_ dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.34, green: 0.84, blue: 1.0, alpha: 1)
             : NSColor(calibratedRed: 0.03, green: 0.43, blue: 0.65, alpha: 1)
    }

    /// Hemingway blue for adverbs.
    static func adverbColor(_ dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.40, green: 0.66, blue: 1.0, alpha: 1)
             : NSColor(calibratedRed: 0.13, green: 0.40, blue: 0.80, alpha: 1)
    }

    /// Hemingway green for passive voice.
    static func passiveColor(_ dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.40, green: 0.82, blue: 0.53, alpha: 1)
             : NSColor(calibratedRed: 0.09, green: 0.52, blue: 0.28, alpha: 1)
    }
}
