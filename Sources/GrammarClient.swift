import Foundation

/// A slim grammar checker for any OpenAI-compatible chat API. It reads the base
/// URL, model, and key from the app's own `Settings`, so pointing it at DeepSeek,
/// OpenAI, OpenRouter, Groq, or a local server is just a matter of the settings.
final class GrammarClient {
    private struct Endpoint {
        let url: URL
        let apiKey: String
        let model: String
        let disableThinking: Bool
    }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        session = URLSession(configuration: config)
    }

    var isConfigured: Bool { resolveEndpoint() != nil }

    /// Reasoning models run a long hidden pass by default; for a short grammar
    /// JSON that only adds latency and cost, so we disable it for them.
    private func isReasoner(_ model: String) -> Bool {
        let m = model.lowercased()
        return m.contains("kimi-k2") || (m.contains("deepseek") && (m.contains("flash") || m.contains("v4") || m.contains("reasoner")))
    }

    private func resolveEndpoint() -> Endpoint? {
        guard Settings.isConfigured, let url = Self.chatURL(Settings.baseURL) else { return nil }
        let model = Settings.model
        return Endpoint(url: url, apiKey: Settings.apiKey, model: model, disableThinking: isReasoner(model))
    }

    private static func chatURL(_ base: String) -> URL? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.hasSuffix("/chat/completions") { trimmed += "/chat/completions" }
        return URL(string: trimmed)
    }

    private static let systemPrompt = """
    You are a careful copy-editor with a very light touch. Judge only grammar, spelling, and punctuation, and trust the writer's voice, word choices, register, and style.
    Flag a span only when it is objectively and unambiguously wrong — the kind of mistake every editor would fix: subject–verb agreement, verb tense or form, plurals, pronoun case, homophones (their/there, its/it's, your/you're), a wrong article (a vs an), clear misspellings, and clearly missing or incorrect punctuation.
    Accept the writer's choices — do not flag them: generic bare nouns and missing articles that are a matter of register ("Human perceives the world"), possessive forms including plural possessives ("models' world", "the agent's world"), the indicative after perception or belief verbs ("I feel that it is beautiful"), and any phrasing that is merely stylistic. When in doubt, trust the writer and skip it — a false alarm is worse than a miss.
    Mark the SMALLEST wrong span: for a subject–verb agreement error mark only the verb ("give"), for a misspelling only the misspelled word, for a wrong article only "a"/"an" — never the surrounding phrase, clause, or sentence.
    Return raw JSON only: {"errors":[{"fragment":"exact substring, copied verbatim","focus":"grammar|spelling","type":"short category","hint":"the rule to apply, never the correction"}]}
    Return {"errors":[]} when the writing is grammatically sound.
    """

    @discardableResult
    func check(text: String, completion: @escaping (Result<[GrammarError], Error>) -> Void) -> URLSessionTask? {
        guard let endpoint = resolveEndpoint() else {
            completion(.failure(NSError(domain: "GrammarClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not configured"])))
            return nil
        }
        var payload: [String: Any] = [
            "model": endpoint.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": "Text to check:\n\(text)"],
            ],
            "response_format": ["type": "json_object"],
            "max_tokens": 4000,
        ]
        // Temperature 0 always — this is what makes the checker consistent run to
        // run. Disabling reasoning must NOT skip it (that left it at the provider
        // default ~1.0, so every check flagged a different subset).
        payload["temperature"] = 0.0
        if endpoint.disableThinking { payload["thinking"] = ["type": "disabled"] }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(NSError(domain: "GrammarClient", code: 2)))
            return nil
        }
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let task = session.dataTask(with: request) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(.failure(NSError(domain: "GrammarClient", code: 3, userInfo: [NSLocalizedDescriptionKey: "Bad response"])))
                return
            }
            completion(.success(Self.parse(content: content, in: text)))
        }
        task.resume()
        return task
    }

    /// A fragment that spans a sentence boundary (". ", "? ", "! ") or runs past
    /// ~8 words is a whole-sentence flag, not a pinpointed error — drop it.
    private static func isTooBroad(_ fragment: String) -> Bool {
        if fragment.contains(". ") || fragment.contains("? ") || fragment.contains("! ") { return true }
        return fragment.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count > 8
    }

    private static func parse(content: String, in text: String) -> [GrammarError] {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") else { return [] }
        guard let data = String(content[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawErrors = object["errors"] as? [[String: Any]] else { return [] }
        let ns = text as NSString
        var searchStart = 0
        var results: [GrammarError] = []
        for raw in rawErrors {
            guard let fragment = raw["fragment"] as? String, !fragment.isEmpty else { continue }
            // Reject whole-sentence spans: the highlight should sit on the wrong
            // word or short phrase, not light up a whole sentence. Drop a fragment
            // that spans a sentence boundary or runs too long.
            guard !Self.isTooBroad(fragment) else { continue }
            var range = FindingMerge.wholeWordRange(of: fragment, in: ns, from: searchStart)
            if range.location == NSNotFound { range = FindingMerge.wholeWordRange(of: fragment, in: ns, from: 0) }
            guard range.location != NSNotFound else { continue }
            searchStart = NSMaxRange(range)
            // The prompt now returns only real correctness errors, so every one
            // is a genuine error (shown red), never an optional style nudge.
            results.append(GrammarError(
                fragment: fragment,
                type: (raw["type"] as? String) ?? "issue",
                kind: .error,
                scope: .phrase,
                focus: GrammarIssueFocus(modelValue: raw["focus"] as? String),
                hint: (raw["hint"] as? String) ?? "",
                range: range
            ))
        }
        return results
    }
}
