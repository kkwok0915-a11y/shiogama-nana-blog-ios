import Foundation

struct ListSnapshot: Codable, Sendable {
    var fetchedAt: Date
    var posts: [Post]
}

/// On-device copy of the last fetched list and of each post that was saved.
/// Files live in Application Support so iOS does not purge them with Caches,
/// and the folder is excluded from backups.
///
/// Disk reads and writes run on this actor, not on the main actor.
actor PostCache {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = base.appendingPathComponent("BlogArchive", isDirectory: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadList() -> ListSnapshot? {
        prepare()
        guard let data = try? Data(contentsOf: listURL) else { return nil }
        guard let snapshot = try? decoder.decode(ListSnapshot.self, from: data) else {
            try? FileManager.default.removeItem(at: listURL)
            return nil
        }
        let posts = PostSorting.newestFirst(snapshot.posts.compactMap { $0.normalized() })
        return ListSnapshot(fetchedAt: snapshot.fetchedAt, posts: posts)
    }

    func saveList(_ posts: [Post], fetchedAt: Date) {
        prepare()
        let snapshot = ListSnapshot(fetchedAt: fetchedAt, posts: PostSorting.newestFirst(posts))
        write(snapshot, to: listURL)
    }

    func saveSnapshot(_ posts: [Post], fetchedAt: Date) {
        saveList(posts, fetchedAt: fetchedAt)
        for post in posts {
            savePost(post)
        }
    }

    /// Keeps a cached body only when the list payload has none. Skips disk
    /// when every post already includes its body.
    func enrich(_ listPosts: [Post]) -> [Post] {
        prepare()
        return PostSorting.newestFirst(listPosts.map { post in
            guard post.body.isEmpty, let cached = loadPost(id: post.id) else { return post }
            return GalleryCatalog.preferringCachedBody(listPost: post, cached: cached)
        })
    }

    func loadPost(id: String) -> Post? {
        prepare()
        guard BlogSite.isSafeID(id) else { return nil }
        let url = postURL(id: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? decoder.decode(Post.self, from: data),
              let post = decoded.normalized(),
              post.id == id
        else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return post
    }

    func savePost(_ post: Post) {
        prepare()
        guard let post = post.normalized(), BlogSite.isSafeID(post.id) else { return }
        if let existing = loadPost(id: post.id),
           !GalleryCatalog.shouldReplaceCachedPost(existing: existing, with: post) {
            return
        }
        write(post, to: postURL(id: post.id))
    }

    func savePosts(_ posts: [Post]) {
        for post in posts {
            savePost(post)
        }
    }

    private var listURL: URL {
        root.appendingPathComponent("list.json")
    }

    private var postsDirectory: URL {
        root.appendingPathComponent("posts", isDirectory: true)
    }

    private func postURL(id: String) -> URL {
        // `id` has already passed BlogSite.isSafeID, so it cannot escape this directory.
        postsDirectory.appendingPathComponent(id).appendingPathExtension("json")
    }

    private func prepare() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: postsDirectory, withIntermediateDirectories: true)
        #if os(iOS)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        #endif
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
