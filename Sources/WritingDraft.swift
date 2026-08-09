import Foundation

/// One saved piece of writing. Stored as plain-text Markdown plus timestamps, so
/// a draft is just data — no AppKit, easy to persist and to test.
struct WritingDraft: Codable, Equatable, Identifiable {
    let id: UUID
    var body: String
    let createdAt: Date
    var updatedAt: Date
    /// The group (theme) this draft belongs to. Optional and defaulted so drafts
    /// saved before groups existed still decode — they're adopted into the
    /// default group on load.
    var groupID: UUID?

    init(id: UUID = UUID(), body: String = "", createdAt: Date = Date(), updatedAt: Date = Date(), groupID: UUID? = nil) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.groupID = groupID
    }

    /// Title for the history list: the first non-empty line, with any leading
    /// Markdown heading marks stripped. Falls back to "Untitled".
    var displayTitle: String {
        for rawLine in body.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let cleaned = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return cleaned.isEmpty ? "Untitled" : cleaned
        }
        return "Untitled"
    }

    /// True for a brand-new draft the writer never typed into. Used to avoid
    /// leaving empty files behind when the editor closes.
    var isEmpty: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
