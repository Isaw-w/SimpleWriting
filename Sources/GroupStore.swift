import Foundation

/// Persists the list of groups to a single JSON file next to the drafts, in
/// `Application Support/SimpleWriting/groups.json`.
final class GroupStore {
    static let shared = GroupStore()

    private let url: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted]; return e
    }()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let base = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("SimpleWriting", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("groups.json")
    }

    func load() -> [WritingGroup] {
        guard let data = try? Data(contentsOf: url),
              let groups = try? decoder.decode([WritingGroup].self, from: data) else { return [] }
        return groups.sorted { $0.order < $1.order }
    }

    func save(_ groups: [WritingGroup]) {
        guard let data = try? encoder.encode(groups) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
