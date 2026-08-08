import Foundation

/// Instant, offline Hemingway-style signals computed locally — no model call.
///
/// Two things live here, both pure functions over a string so they are cheap
/// to run on every keystroke and trivial to test:
///   1. `-ly` adverbs, returned as optional `GrammarError`s so they flow through
///      the edit panel's existing highlight / click-popover machinery unchanged.
///   2. A readability grade (Automated Readability Index) for the summary line.
///
/// The model handles correctness, concision, and passive voice; adverbs are
/// local because `-ly` detection is instant and needs no network round-trip —
/// the core of the Hemingway feel. Adverbs are recomputed fresh on the current
/// text every time, so unlike model findings they can never go stale or need
/// range remapping.
enum LocalStyleDetector {
    /// Words that end in `-ly` but are not adverbs (nouns, adjectives, verbs).
    /// Flagging these was the main false-positive source in Hemingway-style
    /// detectors, so we exclude the common ones outright. Compared lowercased.
    private static let nonAdverbLyWords: Set<String> = [
        // nouns
        "family", "reply", "supply", "ally", "rally", "tally", "belly", "jelly",
        "folly", "bully", "dolly", "lily", "rely", "italy", "july", "assembly",
        "anomaly", "monopoly", "melancholy", "butterfly", "dragonfly",
        // adjectives ending -ly
        "only", "early", "holy", "ugly", "silly", "lonely", "lovely", "likely",
        "lively", "friendly", "deadly", "costly", "elderly", "orderly", "timely",
        "homely", "worldly", "ghostly", "ghastly", "curly", "burly", "gnarly",
        "measly", "wobbly", "bubbly", "grisly", "portly", "comely", "courtly",
        "saintly", "unruly", "wily", "oily", "daily", "weekly", "monthly",
        "yearly", "hourly", "cuddly", "prickly", "crumbly", "wriggly",
        // verbs / other
        "apply", "imply", "comply", "multiply", "reply", "fly", "ply",
    ]

    /// Locate every `-ly` adverb in `text`, returned as optional findings.
    /// A word qualifies when it ends in `ly`, is at least four letters long, and
    /// is not in the block-list above. Ranges are exact UTF-16 ranges into
    /// `text`, so they line up with `NSTextView`/`NSString` operations.
    static func adverbs(in text: String) -> [GrammarError] {
        let ns = text as NSString
        var results: [GrammarError] = []
        var index = 0
        let length = ns.length

        while index < length {
            // Skip to the start of the next letter run.
            while index < length, !isLetter(ns.character(at: index)) {
                index += 1
            }
            let wordStart = index
            while index < length, isLetter(ns.character(at: index)) {
                index += 1
            }
            guard index > wordStart else { continue }

            let range = NSRange(location: wordStart, length: index - wordStart)
            let word = ns.substring(with: range)
            guard isAdverb(word) else { continue }
            results.append(
                GrammarError(
                    fragment: word,
                    type: "adverb",
                    kind: .nativeSuggestion,
                    scope: .word,
                    focus: .adverb,
                    hint: "Adverb — a stronger verb usually says it better, or cut it.",
                    range: range
                )
            )
        }
        return results
    }

    static func isAdverb(_ word: String) -> Bool {
        let lower = word.lowercased()
        guard lower.count >= 4, lower.hasSuffix("ly") else { return false }
        return !nonAdverbLyWords.contains(lower)
    }

    // MARK: - Passive voice

    /// Forms of "to be" that can head a passive clause.
    private static let beForms: Set<String> = [
        "is", "are", "was", "were", "be", "been", "being", "am",
    ]

    /// Irregular past participles that don't end in `-ed`. Not exhaustive — it
    /// covers the common verbs, and the `-ed` rule handles the regular majority.
    /// A short list is deliberate: missing a rare participle only means one
    /// passive goes un-highlighted, never a wrong flag on unrelated text.
    private static let irregularParticiples: Set<String> = [
        "awoken", "born", "borne", "beaten", "become", "begun", "bent", "bound",
        "bitten", "bled", "blown", "broken", "brought", "built", "bought",
        "caught", "chosen", "come", "cut", "done", "drawn", "driven", "drunk",
        "eaten", "fallen", "fed", "felt", "fought", "found", "flown",
        "forgotten", "frozen", "given", "gone", "grown", "hung", "heard",
        "hidden", "hit", "held", "kept", "known", "laid", "led", "left", "lent",
        "lain", "lost", "made", "meant", "met", "paid", "put", "read", "ridden",
        "rung", "risen", "run", "said", "seen", "sold", "sent", "set", "shaken",
        "shone", "shot", "shown", "shut", "sung", "sunk", "sat", "slept",
        "spoken", "spent", "stood", "stolen", "stuck", "struck", "swum", "taken",
        "taught", "told", "thought", "thrown", "understood", "woken", "worn",
        "won", "written", "hurt", "spread", "sought", "torn",
    ]

    static func isPastParticiple(_ word: String) -> Bool {
        let lower = word.lowercased()
        if irregularParticiples.contains(lower) { return true }
        // Regular participles end in -ed. This also catches some -ed adjectives
        // ("was tired"); Hemingway makes the same trade, and the false positive
        // is harmless — an optional highlight, never a blocking error.
        return lower.count >= 4 && lower.hasSuffix("ed")
    }

    /// Locate passive-voice clauses: a "to be" form followed by a past
    /// participle, allowing one adverb in between ("was quickly eaten"). The
    /// span runs from the "be" word through the participle.
    static func passiveVoice(in text: String) -> [GrammarError] {
        let tokens = words(in: text)
        var results: [GrammarError] = []
        let ns = text as NSString
        var index = 0
        while index < tokens.count {
            guard beForms.contains(tokens[index].word) else { index += 1; continue }
            var participleIndex = index + 1
            // Skip a single adverb sitting between the be-form and the verb.
            if participleIndex < tokens.count, isAdverb(tokens[participleIndex].word) {
                participleIndex += 1
            }
            guard participleIndex < tokens.count,
                  isPastParticiple(tokens[participleIndex].word) else { index += 1; continue }
            let start = tokens[index].range.location
            let end = NSMaxRange(tokens[participleIndex].range)
            let range = NSRange(location: start, length: end - start)
            results.append(
                GrammarError(
                    fragment: ns.substring(with: range),
                    type: "passive voice",
                    kind: .nativeSuggestion,
                    scope: .phrase,
                    focus: .passiveVoice,
                    hint: "Passive voice — name who does the action for a more direct sentence.",
                    range: range
                )
            )
            index = participleIndex + 1
        }
        return results
    }

    // MARK: - Qualifiers (weakeners)

    /// Conservative set of non-`-ly` weakeners (the `-ly` ones are already caught
    /// as adverbs). Flagging these is a core Hemingway signal.
    private static let qualifierWords: Set<String> = ["very", "rather", "somewhat", "fairly", "quite"]

    static func qualifiers(in text: String) -> [GrammarError] {
        let ns = text as NSString
        return words(in: text).compactMap { token in
            guard qualifierWords.contains(token.word) else { return nil }
            return GrammarError(
                fragment: ns.substring(with: token.range),
                type: "qualifier",
                kind: .nativeSuggestion,
                scope: .word,
                focus: .concision,
                hint: "Qualifier — the sentence is usually stronger without it.",
                range: token.range
            )
        }
    }

    // MARK: - Long sentences

    /// Sentences of `minWords`+ words, a Hemingway "hard sentence" signal. These
    /// are sentence-scope, rendered as an underline rather than a fill so they
    /// coexist with word-level highlights.
    static func longSentences(in text: String, minWords: Int = 28) -> [GrammarError] {
        let ns = text as NSString
        let length = ns.length
        var results: [GrammarError] = []
        var start = 0
        func flush(_ end: Int) {
            defer { start = end }
            var s = start
            while s < end {
                let ch = ns.character(at: s)
                guard ch == 0x20 || ch == 0x0A || ch == 0x09 || ch == 0x0D else { break }
                s += 1
            }
            guard end > s else { return }
            let range = NSRange(location: s, length: end - s)
            let sentence = ns.substring(with: range)
            guard wordCount(in: sentence) >= minWords else { return }
            results.append(GrammarError(
                fragment: sentence,
                type: "long sentence",
                kind: .nativeSuggestion,
                scope: .sentence,
                focus: .sentenceClarity,
                hint: "Long sentence — try splitting it so each idea stands on its own.",
                range: range
            ))
        }
        for i in 0..<length {
            let ch = ns.character(at: i)
            if ch == 0x2E || ch == 0x21 || ch == 0x3F { flush(i + 1) } // . ! ?
        }
        flush(length)
        return results
    }

    // MARK: - Combined offline findings

    /// Every finding the panel can produce without a model call: passive voice
    /// plus adverbs. This is the offline core of the Hemingway experience and
    /// the always-on layer even when the model check is enabled. Passive spans
    /// win over an adverb sitting inside them, so a character is never painted by
    /// two overlapping fills.
    static func localFindings(in text: String) -> [GrammarError] {
        let passive = passiveVoice(in: text)
        func clearOfPassive(_ finding: GrammarError) -> Bool {
            !passive.contains { NSIntersectionRange($0.range, finding.range).length > 0 }
        }
        let adverbsKept = adverbs(in: text).filter(clearOfPassive)
        let qualifiersKept = qualifiers(in: text).filter(clearOfPassive)
        // Long sentences are sentence-scope and rendered as an underline, so they
        // deliberately overlap the word-level findings inside them.
        let sentences = longSentences(in: text)
        return (passive + adverbsKept + qualifiersKept + sentences).sorted {
            $0.range.location == $1.range.location
                ? $0.range.length < $1.range.length
                : $0.range.location < $1.range.location
        }
    }

    // MARK: - Metrics & summary

    /// Number of words (maximal letter runs) in `text`.
    static func wordCount(in text: String) -> Int {
        words(in: text).count
    }

    /// The calm one-line Hemingway summary: readability grade first, then a
    /// count for each category actually present. Shared by the edit panel and
    /// the standalone editor so both read identically.
    static func summaryLine(errors: [GrammarError], text: String) -> String {
        var parts: [String] = []
        if let grade = readabilityGrade(for: text) {
            parts.append("Grade \(grade)")
        }
        let required = errors.filter { $0.kind == .error }.count
        func count(_ focus: GrammarIssueFocus) -> Int { errors.filter { $0.focus == focus }.count }
        let adverbs = count(.adverb)
        let passive = count(.passiveVoice)
        let wordy = count(.concision)
        if required > 0 { parts.append("\(required) error\(required == 1 ? "" : "s")") }
        if adverbs > 0 { parts.append("\(adverbs) adverb\(adverbs == 1 ? "" : "s")") }
        if passive > 0 { parts.append("\(passive) passive") }
        if wordy > 0 { parts.append("\(wordy) wordy") }
        if parts.isEmpty { return "Looks clean" }
        if parts.count == 1, parts[0].hasPrefix("Grade") { parts.append("clean") }
        return parts.joined(separator: " · ")
    }

    /// Split `text` into letter-run tokens with their exact ranges, lowercased
    /// for matching. Shared by the adverb and passive passes.
    private static func words(in text: String) -> [(range: NSRange, word: String)] {
        let ns = text as NSString
        let length = ns.length
        var tokens: [(range: NSRange, word: String)] = []
        var index = 0
        while index < length {
            while index < length, !isLetter(ns.character(at: index)) { index += 1 }
            let start = index
            while index < length, isLetter(ns.character(at: index)) { index += 1 }
            guard index > start else { continue }
            let range = NSRange(location: start, length: index - start)
            tokens.append((range, ns.substring(with: range).lowercased()))
        }
        return tokens
    }

    /// U.S.-grade readability via the Automated Readability Index. ARI uses only
    /// characters, words, and sentences — no syllable guessing — so the result
    /// is fully deterministic and safe to recompute on every keystroke. Returns
    /// `nil` for a fragment too short to grade honestly (fewer than three words).
    static func readabilityGrade(for text: String) -> Int? {
        let ns = text as NSString
        let length = ns.length

        var letterOrDigitCount = 0
        var wordCount = 0
        var sentenceCount = 0
        var inWord = false

        for i in 0..<length {
            let c = ns.character(at: i)
            let scalar = Unicode.Scalar(c)
            if isLetter(c) || (scalar.map { CharacterSet.decimalDigits.contains($0) } ?? false) {
                letterOrDigitCount += 1
                if !inWord { wordCount += 1; inWord = true }
            } else {
                inWord = false
                if c == 0x2E || c == 0x21 || c == 0x3F { // . ! ?
                    sentenceCount += 1
                }
            }
        }

        guard wordCount >= 3 else { return nil }
        let sentences = Double(max(1, sentenceCount))
        let words = Double(wordCount)
        let characters = Double(letterOrDigitCount)

        let ari = 4.71 * (characters / words) + 0.5 * (words / sentences) - 21.43
        // ARI can dip below 1 for very plain text and run high for dense prose;
        // clamp to a sane display band so the summary never shows "Grade -3".
        return min(16, max(1, Int(ari.rounded())))
    }

    private static func isLetter(_ utf16Unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(utf16Unit) else { return false }
        return CharacterSet.letters.contains(scalar)
    }
}
