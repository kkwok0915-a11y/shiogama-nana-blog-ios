import Foundation
import Observation

@MainActor
@Observable
final class LibraryModel {
    private(set) var posts: [Post] = []
    private(set) var isLoadingInitial = false
    private(set) var loadFailed = false
    private(set) var bannerText: String?
    private(set) var lastUpdated: Date?

    @ObservationIgnored private let cache: PostCache
    private var extras: [String: Post] = [:]
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var refreshInFlight = false

    init(cache: PostCache = PostCache()) {
        self.cache = cache
    }

    func bootstrap() async {
        guard !didStart else { return }
        didStart = true
        if let snapshot = cache.loadList() {
            posts = snapshot.posts
            lastUpdated = snapshot.fetchedAt
            ImageStore.prefetch(urls: posts.flatMap(\.photoURLs))
        }
        await refresh()
    }

    func refresh() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        if posts.isEmpty { isLoadingInitial = true }
        defer { isLoadingInitial = false }

        do {
            let fresh = try await BlogAPI.fetchPosts()
            let now = Date()
            posts = fresh
            for post in fresh { extras.removeValue(forKey: post.id) }
            lastUpdated = now
            loadFailed = false
            bannerText = nil
            cache.saveList(fresh, fetchedAt: now)
            for post in fresh { cache.savePost(post) }
            ImageStore.prefetch(urls: fresh.flatMap(\.photoURLs))
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            if posts.isEmpty {
                loadFailed = true
                bannerText = nil
            } else {
                loadFailed = false
                bannerText = "無法更新。目前顯示上次儲存的文章，下拉可再試一次。"
            }
        }
    }

    func resolvedPost(id: String) -> Post? {
        if let post = posts.first(where: { $0.id == id }) { return post }
        return extras[id]
    }

    func open(id: String) async {
        if resolvedPost(id: id) == nil, let cached = cache.loadPost(id: id) {
            extras[id] = cached
        }
        if let current = resolvedPost(id: id) {
            cache.savePost(current)
            ImageStore.prefetch(urls: current.photoURLs)
        }
        do {
            let fresh = try await BlogAPI.fetchPost(id: id)
            if let index = posts.firstIndex(where: { $0.id == id }) {
                posts[index] = fresh
                cache.saveList(posts, fetchedAt: lastUpdated ?? Date())
            } else {
                extras[id] = fresh
            }
            cache.savePost(fresh)
            ImageStore.prefetch(urls: fresh.photoURLs)
        } catch {
            // Keep the list copy or the previously opened copy on screen.
        }
    }

    var lastUpdatedText: String? {
        guard let lastUpdated else { return nil }
        return Self.updatedFormatter.string(from: lastUpdated)
    }

    private static let updatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter
    }()
}
