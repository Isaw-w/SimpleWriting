import Foundation

/// A named group of drafts — a theme the writer keeps their notes under. Just
/// data; persistence lives in `GroupStore`.
struct WritingGroup: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var order: Int

    init(id: UUID = UUID(), name: String, order: Int) {
        self.id = id
        self.name = name
        self.order = order
    }
}
