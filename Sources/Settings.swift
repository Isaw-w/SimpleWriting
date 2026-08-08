import Foundation

/// The app's own settings, stored in its own `UserDefaults` (no dependency on
/// any other app). The grammar checker talks to any OpenAI-compatible chat API,
/// so all it needs is a base URL, a model name, and an API key — all editable in
/// the Settings window.
enum Settings {
    static let baseURLKey = "api.baseURL"
    static let modelKey = "api.model"
    static let apiKeyKey = "api.key"

    /// Shown as placeholders and used as defaults, so a fresh install already
    /// points at a working OpenAI-compatible endpoint; the user only adds a key.
    static let defaultBaseURL = "https://api.deepseek.com/beta"
    static let defaultModel = "deepseek-chat"

    private static var store: UserDefaults { .standard }

    static var baseURL: String {
        get { trimmed(baseURLKey) ?? defaultBaseURL }
        set { store.set(newValue, forKey: baseURLKey) }
    }
    static var model: String {
        get { trimmed(modelKey) ?? defaultModel }
        set { store.set(newValue, forKey: modelKey) }
    }
    static var apiKey: String {
        get { trimmed(apiKeyKey) ?? "" }
        set { store.set(newValue, forKey: apiKeyKey) }
    }

    /// Configured once there is a key to authenticate with.
    static var isConfigured: Bool { !apiKey.isEmpty }

    private static func trimmed(_ key: String) -> String? {
        let v = store.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }
}
