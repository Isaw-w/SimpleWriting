import Foundation

/// Shared validation + merge logic for grammar findings (extracted from the main
/// app's edit controller so the standalone Writer behaves identically).
enum FindingMerge {
    /// Keep only findings whose exact fragment still sits at their range, deduped
    /// and sorted. A completed check is authoritative for the text it checked.
    static func validatedErrors(_ freshErrors: [GrammarError], in text: String) -> [GrammarError] {
        let current = text as NSString
        var seen: Set<String> = []
        return freshErrors.filter { error in
            let range = error.range
            guard range.location >= 0,
                  NSMaxRange(range) <= current.length,
                  current.substring(with: range) == error.fragment else { return false }
            let key = "\(range.location):\(range.length):\(error.fragment):\(error.kind.rawValue)"
            return seen.insert(key).inserted
        }.sorted {
            $0.range.location == $1.range.location
                ? $0.range.length < $1.range.length
                : $0.range.location < $1.range.location
        }
    }

    /// Re-find each finding's exact fragment in the current text and move its
    /// range there, dropping only fragments that are truly gone. Unlike
    /// `validatedErrors` (which requires the fragment to still sit at its old
    /// offset), this survives edits elsewhere in the document — so fixing one
    /// error no longer makes the others vanish until the next check.
    /// Find `fragment` at or after `from`, requiring word boundaries so a
    /// fragment like "perceive" does NOT match inside "perceives" — that
    /// substring match kept a fixed error alive as a stale mark.
    static func wholeWordRange(of fragment: String, in ns: NSString, from: Int) -> NSRange {
        let firstIsWord = fragment.unicodeScalars.first.map { CharacterSet.alphanumerics.contains($0) } ?? false
        let lastIsWord = fragment.unicodeScalars.last.map { CharacterSet.alphanumerics.contains($0) } ?? false
        var searchStart = max(0, min(from, ns.length))
        while searchStart <= ns.length {
            let range = ns.range(of: fragment, options: [], range: NSRange(location: searchStart, length: ns.length - searchStart))
            if range.location == NSNotFound { return range }
            var ok = true
            if firstIsWord, range.location > 0,
               let before = Unicode.Scalar(ns.character(at: range.location - 1)),
               CharacterSet.alphanumerics.contains(before) { ok = false }
            let after = NSMaxRange(range)
            if lastIsWord, after < ns.length,
               let a = Unicode.Scalar(ns.character(at: after)),
               CharacterSet.alphanumerics.contains(a) { ok = false }
            if ok { return range }
            searchStart = range.location + 1
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    static func relocate(_ errors: [GrammarError], in text: String) -> [GrammarError] {
        let ns = text as NSString
        let ordered = errors.sorted { $0.range.location < $1.range.location }
        var cursor = 0
        var claimed = Set<String>()
        var result: [GrammarError] = []
        for error in ordered {
            let fragment = error.fragment
            guard !fragment.isEmpty else { continue }
            let from = min(cursor, ns.length)
            var range = wholeWordRange(of: fragment, in: ns, from: from)
            if range.location == NSNotFound { range = wholeWordRange(of: fragment, in: ns, from: 0) }
            guard range.location != NSNotFound else { continue }
            let key = "\(range.location):\(range.length):\(fragment):\(error.kind.rawValue)"
            guard !claimed.contains(key) else { continue }
            claimed.insert(key)
            cursor = NSMaxRange(range)
            var mapped = error
            mapped.range = range
            result.append(mapped)
        }
        return result.sorted {
            $0.range.location == $1.range.location
                ? $0.range.length < $1.range.length
                : $0.range.location < $1.range.location
        }
    }

    /// Combine model findings with local ones, dropping a local finding that
    /// overlaps a model finding (the model note wins).
    static func mergeLocalFindings(into llm: [GrammarError], local: [GrammarError]) -> [GrammarError] {
        let kept = local.filter { finding in
            !llm.contains { NSIntersectionRange($0.range, finding.range).length > 0 }
        }
        return (llm + kept).sorted {
            $0.range.location == $1.range.location
                ? $0.range.length < $1.range.length
                : $0.range.location < $1.range.location
        }
    }
}
