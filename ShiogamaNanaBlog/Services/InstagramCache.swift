import Foundation

/// On-device copy of the last Instagram list. The list payload already includes
/// captions and slides, so one file is enough. Reads and writes stay off the main actor.
actor InstagramCache {
    struct Snapshot: Codable, Sendable {
        var fetchedAt: Date
        var posts: [InstagramPost]
    }

    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = base.appendingPathComponent("BlogArchive/instagram", isDirectory: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(InstagramTime.string(from: date))
        }
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = InstagramTime.parse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Instagram date is not ISO-8601."
                )
            }
            return date
        }
        self.decoder = decoder
    }

    func load() -> Snapshot? {
        prepare()
        guard let data = try? Data(contentsOf: listURL) else { return nil }
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else {
            try? FileManager.default.removeItem(at: listURL)
            return nil
        }
        let posts = InstagramSorting.newestFirst(snapshot.posts.compactMap { $0.normalized() })
        return Snapshot(fetchedAt: snapshot.fetchedAt, posts: posts)
    }

    func save(_ posts: [InstagramPost], fetchedAt: Date) {
        prepare()
        let snapshot = Snapshot(
            fetchedAt: fetchedAt,
            posts: InstagramSorting.newestFirst(posts.compactMap { $0.normalized() })
        )
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: listURL, options: .atomic)
    }

    private var listURL: URL {
        root.appendingPathComponent("list.json")
    }

    private func prepare() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #if os(iOS)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        #endif
    }
}

extension InstagramTime {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
