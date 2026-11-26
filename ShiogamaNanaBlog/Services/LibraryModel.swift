import Foundation
import Observation

@MainActor
@Observable
final class LibraryModel {
    private(set) var posts: [Post] = []
    private(set) var isLoadingInitial = false
    private(set) var isHydratingPhotos = false
    private(set) var loadFailed = false
    private(set) var bannerText: String?
    private(set) var photoBannerText: String?
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
            posts = enrich(snapshot.posts)
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
            let resolved = enrich(fresh)
            posts = resolved
            for post in fresh { extras.removeValue(forKey: post.id) }
            lastUpdated = now
            loadFailed = false
            bannerText = nil
            photoBannerText = nil
            cache.saveList(resolved, fetchedAt: now)
            for post in resolved { cache.savePost(post) }
            ImageStore.prefetch(urls: resolved.flatMap(\.photoURLs))
            await hydratePhotoDetails(listPosts: fresh)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            photoBannerText = nil
            if posts.isEmpty {
                loadFailed = true
                bannerText = nil
            } else {
                loadFailed = false
                bannerText = "無法更新。目前顯示上次儲存的文章，下拉可再試一次。"
            }
        }
    }

    /// When the list JSON has no photo blocks, load each post (a few at a
    /// time) and keep the result on disk so the gallery works offline.
    private func hydratePhotoDetails(listPosts: [Post]) async {
        let ids = GalleryCatalog.idsNeedingDetail(listPosts: listPosts)
        guard !ids.isEmpty else { return }
        isHydratingPhotos = true
        defer { isHydratingPhotos = false }
        let batch = await PhotoDetailLoader.fetch(ids: ids, limit: PhotoDetailLoader.defaultLimit)
        for post in batch.posts {
            storeFetchedDetail(post)
        }
        if !batch.posts.isEmpty {
            cache.saveList(posts, fetchedAt: lastUpdated ?? Date())
        }
        guard !Task.isCancelled else { return }
        if batch.failureCount > 0 {
            if posts.contains(where: { $0.imageCount > 0 }) {
                photoBannerText = "無法更新全部照片。目前顯示已儲存的內容，下拉可再試一次。"
            } else {
                photoBannerText = "無法讀取照片。連線後下拉再試一次。"
            }
        }
    }

    private func storeFetchedDetail(_ detail: Post) {
        let merged: Post
        if let index = posts.firstIndex(where: { $0.id == detail.id }) {
            merged = GalleryCatalog.applyingDetail(detail, onto: posts[index])
            posts[index] = merged
        } else {
            merged = detail
            extras[detail.id] = detail
        }
        cache.savePost(merged)
        ImageStore.prefetch(urls: merged.photoURLs)
    }

    private func enrich(_ listPosts: [Post]) -> [Post] {
        PostSorting.newestFirst(listPosts.map { post in
            guard let cached = cache.loadPost(id: post.id) else { return post }
            return GalleryCatalog.preferringCachedBody(listPost: post, cached: cached)
        })
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
