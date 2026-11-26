import Foundation
import Observation

/// Instagram posts from the public archive. Separate from `LibraryModel` so the
/// blog list and the photo gallery keep their own refresh and cache.
@MainActor
@Observable
final class InstagramArchive {
    private(set) var posts: [InstagramPost] = []
    private(set) var isLoadingInitial = true
    private(set) var loadFailed = false
    private(set) var bannerText: String?
    private(set) var lastUpdated: Date?

    @ObservationIgnored private let cache: InstagramCache
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var refreshInFlight = false

    init(cache: InstagramCache = InstagramCache()) {
        self.cache = cache
    }

    func bootstrap() async {
        guard !didStart else { return }
        didStart = true
        if let snapshot = await cache.load() {
            posts = snapshot.posts
            lastUpdated = snapshot.fetchedAt
            prefetchCovers(snapshot.posts)
        }
        await refresh()
    }

    /// Pull-to-refresh awaits the list fetch. Disk writes and thumbnail
    /// downloads continue after the refresh control lets go of the scroll view.
    func refresh() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }

        if posts.isEmpty && !isLoadingInitial {
            isLoadingInitial = true
        }

        do {
            let fresh = try await BlogAPI.fetchInstagramPosts()
            guard !Task.isCancelled else {
                clearInitialPlaceholder()
                return
            }
            applyFetchedList(fresh)
        } catch is CancellationError {
            clearInitialPlaceholder()
        } catch let error as URLError where error.code == .cancelled {
            clearInitialPlaceholder()
        } catch {
            applyRefreshFailure()
        }
    }

    func post(code: String) -> InstagramPost? {
        posts.first { $0.code == code }
    }

    /// Refreshes one post. A failure leaves the copy already on screen.
    func open(code: String) async {
        guard InstagramPost.isSafeCode(code) else { return }
        do {
            let fresh = try await BlogAPI.fetchInstagramPost(code: code)
            guard !Task.isCancelled else { return }
            merge(fresh)
            let list = posts
            let fetchedAt = lastUpdated ?? Date()
            Task { await cache.save(list, fetchedAt: fetchedAt) }
            ImageStore.prefetch(urls: fresh.photoURLs)
        } catch {
            // Keep the list copy.
        }
    }

    var lastUpdatedText: String? {
        guard let lastUpdated else { return nil }
        return Self.updatedFormatter.string(from: lastUpdated)
    }

    private func applyFetchedList(_ fresh: [InstagramPost]) {
        if fresh != posts {
            posts = fresh
        }
        if loadFailed { loadFailed = false }
        if bannerText != nil { bannerText = nil }
        let now = Date()
        lastUpdated = now
        clearInitialPlaceholder()
        let snapshot = posts
        Task { await cache.save(snapshot, fetchedAt: now) }
        prefetchCovers(snapshot)
    }

    private func applyRefreshFailure() {
        if posts.isEmpty {
            if !loadFailed { loadFailed = true }
            if bannerText != nil { bannerText = nil }
        } else {
            if loadFailed { loadFailed = false }
            let message = "無法更新。目前顯示上次儲存的貼文，下拉可再試一次。"
            if bannerText != message { bannerText = message }
        }
        clearInitialPlaceholder()
    }

    private func merge(_ post: InstagramPost) {
        var next = posts.filter { $0.code != post.code }
        next.append(post)
        let sorted = InstagramSorting.newestFirst(next)
        if sorted != posts {
            posts = sorted
        }
    }

    private func clearInitialPlaceholder() {
        if isLoadingInitial { isLoadingInitial = false }
    }

    private func prefetchCovers(_ posts: [InstagramPost]) {
        ImageStore.prefetch(urls: posts.compactMap(\.coverThumbnailURL))
    }

    private static let updatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter
    }()
}
