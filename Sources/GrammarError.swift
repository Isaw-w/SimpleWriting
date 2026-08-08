import Foundation

enum GrammarIssueKind: String, Equatable {
    /// A genuine grammar, spelling, or clarity problem. It must be corrected
    /// before Grammar Gate considers the text ready.
    case error
    /// An optional, high-confidence improvement toward more idiomatic native
    /// wording. It never blocks applying or sending.
    case nativeSuggestion
}

/// The smallest honest unit that needs attention. This controls both the
/// model's target and the label shown to the writer.
enum GrammarIssueScope: String, Equatable {
    case word
    case phrase
    case sentence

    var label: String { rawValue.capitalized }
}

/// Why the text is being flagged. Keep this small and writer-facing: it is a
/// writing goal, not an opaque model category.
enum GrammarIssueFocus: String, Equatable {
    case grammar
    case spelling
    case precision
    case concision
    case passiveVoice
    case adverb
    case nativePhrasing
    case sentenceClarity

    init(modelValue: String?) {
        switch modelValue?.lowercased().replacingOccurrences(of: "_", with: "") {
        case "spelling": self = .spelling
        case "precision", "meaning": self = .precision
        case "concision": self = .concision
        case "passivevoice", "passive": self = .passiveVoice
        case "adverb", "adverbs": self = .adverb
        case "nativephrasing", "native": self = .nativePhrasing
        case "sentenceclarity", "clarity": self = .sentenceClarity
        default: self = .grammar
        }
    }

    var label: String {
        switch self {
        case .grammar: "Grammar"
        case .spelling: "Spelling"
        case .precision: "Precision"
        case .concision: "Concision"
        case .passiveVoice: "Passive voice"
        case .adverb: "Adverb"
        case .nativePhrasing: "Natural phrasing"
        case .sentenceClarity: "Sentence clarity"
        }
    }
}

/// One grammar issue the checker located in the user's text.
///
/// The whole point of Grammar Gate is to locate the issue and give the user a
/// short sentence they can type themselves — never to alter their text.
struct GrammarError: Equatable {
    /// The exact offending substring as it appears in the user's text, used to
    /// locate the highlight range. The LLM returns this verbatim.
    let fragment: String
    /// Short human label for the error category, e.g. "subject-verb agreement",
    /// "article", "tense", "spelling".
    let type: String
    /// Red issues are real errors; yellow issues are optional native phrasing.
    let kind: GrammarIssueKind
    let scope: GrammarIssueScope
    let focus: GrammarIssueFocus
    /// A coaching nudge that points the student toward the fix — the rule to
    /// apply or what to reconsider — WITHOUT ever giving the corrected word or a
    /// rewrite. May be empty. The model is instructed to keep the answer hidden.
    /// Used in **Learn** mode.
    let hint: String
    /// **Coach** mode only: a complete corrected or native-sounding sentence
    /// for the user to type themselves. Empty in Learn mode.
    let suggestion: String
    /// **Coach** mode only: why the suggestion is more natural/correct. Empty in
    /// Learn mode.
    let reason: String
    /// **Coach** mode only: a short targeted spoken intervention generated for
    /// this exact issue.
    let coachLine: String
    /// **Coach** mode only: Apple SSML performance for `coachLine`.
    let coachSSML: String
    /// **Coach** mode only: legacy speaking rate fallback for `coachLine`.
    let coachRate: String
    /// **Coach** mode only: legacy pitch fallback for `coachLine`.
    let coachPitch: String
    /// Range of `fragment` inside the checked text. Resolved locally after the
    /// model responds (LLMs are unreliable at character offsets, so we match the
    /// literal fragment instead of trusting offsets it reports).
    var range: NSRange

    init(
        fragment: String,
        type: String,
        kind: GrammarIssueKind = .error,
        scope: GrammarIssueScope = .phrase,
        focus: GrammarIssueFocus = .grammar,
        hint: String,
        suggestion: String = "",
        reason: String = "",
        coachLine: String = "",
        coachSSML: String = "",
        coachRate: String = "",
        coachPitch: String = "",
        range: NSRange
    ) {
        self.fragment = fragment
        self.type = type
        self.kind = kind
        self.scope = scope
        self.focus = focus
        self.hint = hint
        self.suggestion = suggestion
        self.reason = reason
        self.coachLine = coachLine
        self.coachSSML = coachSSML
        self.coachRate = coachRate
        self.coachPitch = coachPitch
        self.range = range
    }
}
