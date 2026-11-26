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
    @ObservationIgnored private var hydrationTask: Task<Void, Never>?

    init(cache: PostCache = PostCache()) {
        self.cache = cache
    }

    func bootstrap() async {
        guard !didStart else { return }
        didStart = true
        if let snapshot = await cache.loadList() {
            let enriched = await cache.enrich(snapshot.posts)
            posts = enriched
            lastUpdated = snapshot.fetchedAt
            ImageStore.prefetch(urls: enriched.flatMap(\.photoURLs))
        }
        await refresh()
    }

    /// Pull-to-refresh awaits only the list fetch. JSON decode and disk reads
    /// happen off the main actor. Photo hydration, image prefetch, and disk
    /// writes are not awaited, so the system refresh control can release the
    /// scroll view. An unchanged id list does not replace `posts`.
    func refresh() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        hydrationTask?.cancel()
        defer { refreshInFlight = false }

        let showPlaceholder = posts.isEmpty
        if showPlaceholder && !isLoadingInitial {
            isLoadingInitial = true
        }

        do {
            let fresh = try await BlogAPI.fetchPosts()
            guard !Task.isCancelled else {
                clearInitialPlaceholder()
                return
            }
            await applyFetchedList(fresh)
        } catch is CancellationError {
            clearInitialPlaceholder()
        } catch let error as URLError where error.code == .cancelled {
            clearInitialPlaceholder()
        } catch {
            applyRefreshFailure()
        }
    }

    func resolvedPost(id: String) -> Post? {
        if let post = posts.first(where: { $0.id == id }) { return post }
        return extras[id]
    }

    func open(id: String) async {
        if resolvedPost(id: id) == nil, let cached = await cache.loadPost(id: id) {
            extras[id] = cached
        }
        if let current = resolvedPost(id: id) {
            let snapshot = current
            Task { await cache.savePost(snapshot) }
            ImageStore.prefetch(urls: snapshot.photoURLs)
        }
        do {
            let fresh = try await BlogAPI.fetchPost(id: id)
            if let index = posts.firstIndex(where: { $0.id == id }) {
                if posts[index] != fresh {
                    var updated = posts
                    updated[index] = fresh
                    posts = updated
                    let list = posts
                    let fetchedAt = lastUpdated ?? Date()
                    Task { await cache.saveList(list, fetchedAt: fetchedAt) }
                }
            } else if extras[id] != fresh {
                extras[id] = fresh
            }
            Task { await cache.savePost(fresh) }
            ImageStore.prefetch(urls: fresh.photoURLs)
        } catch {
            // Keep the list copy or the previously opened copy on screen.
        }
    }

    var lastUpdatedText: String? {
        guard let lastUpdated else { return nil }
        return Self.updatedFormatter.string(from: lastUpdated)
    }

    private func applyFetchedList(_ fresh: [Post]) async {
        let resolved = await cache.enrich(fresh)
        guard !Task.isCancelled else {
            clearInitialPlaceholder()
            return
        }
        if let merged = PostListDiff.merging(resolved, into: posts) {
            posts = merged
        }
        dropExtras(for: fresh)
        if loadFailed { loadFailed = false }
        if bannerText != nil { bannerText = nil }
        if photoBannerText != nil { photoBannerText = nil }
        let now = Date()
        let stamp = Self.updatedFormatter.string(from: now)
        if lastUpdated == nil || lastUpdatedText != stamp {
            lastUpdated = now
        }
        clearInitialPlaceholder()
        let snapshot = resolved
        Task { await cache.saveSnapshot(snapshot, fetchedAt: now) }
        ImageStore.prefetch(urls: snapshot.flatMap(\.photoURLs))
        schedulePhotoHydration(listPosts: fresh)
    }

    private func applyRefreshFailure() {
        if photoBannerText != nil { photoBannerText = nil }
        if posts.isEmpty {
            if !loadFailed { loadFailed = true }
            if bannerText != nil { bannerText = nil }
        } else {
            if loadFailed { loadFailed = false }
            let message = "無法更新。目前顯示上次儲存的文章，下拉可再試一次。"
            if bannerText != message { bannerText = message }
        }
        clearInitialPlaceholder()
    }

    private func clearInitialPlaceholder() {
        if isLoadingInitial { isLoadingInitial = false }
    }

    private func dropExtras(for fresh: [Post]) {
        guard fresh.contains(where: { extras[$0.id] != nil }) else { return }
        var copy = extras
        for post in fresh {
            copy.removeValue(forKey: post.id)
        }
        extras = copy
    }

    /// When the list JSON has no photo blocks, load each post (a few at a
    /// time) and keep the result on disk so the gallery works offline.
    /// Started after the list refresh returns so pull-to-refresh is not held
    /// open, and applied as a single posts update.
    private func schedulePhotoHydration(listPosts: [Post]) {
        let ids = GalleryCatalog.idsNeedingDetail(listPosts: listPosts)
        guard !ids.isEmpty else { return }
        hydrationTask?.cancel()
        hydrationTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            await self.hydratePhotoDetails(ids: ids)
        }
    }

    private func hydratePhotoDetails(ids: [String]) async {
        if !isHydratingPhotos { isHydratingPhotos = true }
        defer {
            if isHydratingPhotos { isHydratingPhotos = false }
        }
        let batch = await PhotoDetailLoader.fetch(ids: ids, limit: PhotoDetailLoader.defaultLimit)
        guard !Task.isCancelled else { return }

        var next = posts
        var changed = false
        var toSave: [Post] = []
        var urls: [URL] = []
        for detail in batch.posts {
            if let index = next.firstIndex(where: { $0.id == detail.id }) {
                let merged = GalleryCatalog.applyingDetail(detail, onto: next[index])
                if merged != next[index] {
                    next[index] = merged
                    changed = true
                }
                toSave.append(merged)
                urls.append(contentsOf: merged.photoURLs)
            } else {
                if extras[detail.id] != detail {
                    extras[detail.id] = detail
                }
                toSave.append(detail)
                urls.append(contentsOf: detail.photoURLs)
            }
        }
        if changed, let merged = PostListDiff.merging(next, into: posts) {
            posts = merged
        }
        if !urls.isEmpty {
            ImageStore.prefetch(urls: urls)
        }
        if !toSave.isEmpty {
            let list = posts
            let fetchedAt = lastUpdated ?? Date()
            let saved = toSave
            Task {
                await cache.savePosts(saved)
                await cache.saveList(list, fetchedAt: fetchedAt)
            }
        }
        guard !Task.isCancelled else { return }
        if batch.failureCount > 0 {
            let message = posts.contains(where: { $0.imageCount > 0 })
                ? "無法更新全部照片。目前顯示已儲存的內容，下拉可再試一次。"
                : "無法讀取照片。連線後下拉再試一次。"
            if photoBannerText != message { photoBannerText = message }
        }
    }

    private static let updatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter
    }()
}
