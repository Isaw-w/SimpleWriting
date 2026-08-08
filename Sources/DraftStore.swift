import Foundation

/// Local, on-disk history of writing drafts. One JSON file per draft under
/// `Application Support/SimpleWriting/Drafts/`, so deleting one draft never
/// rewrites the others and a corrupt file can't take the whole history down.
///
/// The directory is injectable so tests can run against a temp folder.
final class DraftStore {
    static let shared = DraftStore()

    private let directory: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base
                .appendingPathComponent("SimpleWriting", isDirectory: true)
                .appendingPathComponent("Drafts", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// All drafts, most recently edited first. Unreadable files are skipped
    /// rather than crashing the list.
    func allDrafts() -> [WritingDraft] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> WritingDraft? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(WritingDraft.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ draft: WritingDraft) {
        guard let data = try? encoder.encode(draft) else { return }
        try? data.write(to: url(for: draft.id), options: .atomic)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
