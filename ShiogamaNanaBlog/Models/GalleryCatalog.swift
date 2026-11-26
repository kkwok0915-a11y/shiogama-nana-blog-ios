import Foundation

/// One photo in the gallery, in newest-post order.
struct GalleryPhoto: Identifiable, Hashable, Sendable {
    var postID: String
    var postTitle: String
    var postDate: String?
    var photo: PhotoBlock
    var indexInPost: Int

    var id: String { "\(postID)#\(indexInPost)#\(photo.src)" }

    var url: URL? { photo.url }
}

struct GallerySection: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var photos: [GalleryPhoto]
}

/// Pure gallery indexing and cache decisions. No UI and no network.
enum GalleryCatalog {
    static func photos(from posts: [Post]) -> [GalleryPhoto] {
        var photos: [GalleryPhoto] = []
        for post in PostSorting.newestFirst(posts) {
            var index = 0
            for block in post.contentBlocks {
                guard case .photo(let photo) = block else { continue }
                photos.append(GalleryPhoto(
                    postID: post.id,
                    postTitle: post.displayTitleZh,
                    postDate: post.postDate,
                    photo: photo,
                    indexInPost: index
                ))
                index += 1
            }
        }
        return photos
    }

    /// Newest month first, because `photos(from:)` already walks posts newest first.
    /// Posts with no `yyyy-MM` date land in a final "日期不明" section.
    static func sections(from posts: [Post]) -> [GallerySection] {
        var grouped: [String: [GalleryPhoto]] = [:]
        var order: [String] = []
        for photo in photos(from: posts) {
            let key = monthKey(for: photo.postDate) ?? "unknown"
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(photo)
        }
        return order.map { key in
            GallerySection(id: key, title: monthTitle(key), photos: grouped[key] ?? [])
        }
    }

    /// Posts whose list payload does not already contain their photos.
    /// When the list includes any photo block, only posts that declare a higher
    /// `photo_count` are fetched. When the list has no photo blocks at all,
    /// every post is fetched except those that explicitly report zero photos.
    static func idsNeedingDetail(listPosts: [Post]) -> [String] {
        let listHasPhotoBlocks = listPosts.contains { $0.imageCount > 0 }
        return listPosts.compactMap { post in
            guard BlogSite.isSafeID(post.id) else { return nil }
            if listHasPhotoBlocks {
                guard let declared = post.photoCount, declared > post.imageCount else { return nil }
                return post.id
            }
            return post.photoCount == 0 ? nil : post.id
        }
    }

    /// The list is the source of truth when it includes a body. An empty list
    /// body keeps a previously cached body so the gallery can open offline.
    static func preferringCachedBody(listPost: Post, cached: Post) -> Post {
        guard cached.id == listPost.id else { return listPost }
        guard listPost.body.isEmpty, !cached.body.isEmpty else { return listPost }
        var merged = listPost
        merged.body = cached.body
        if merged.photoCount == nil {
            merged.photoCount = cached.photoCount
        }
        return merged
    }

    /// A detail response replaces the list row. Empty titles and dates on the
    /// detail fall back to the row already on screen.
    static func applyingDetail(_ detail: Post, onto current: Post) -> Post {
        guard detail.id == current.id else { return current }
        var merged = detail
        if merged.titleZh.isEmpty { merged.titleZh = current.titleZh }
        if merged.titleJp == nil { merged.titleJp = current.titleJp }
        if merged.postDate == nil { merged.postDate = current.postDate }
        if merged.originalUrl == nil { merged.originalUrl = current.originalUrl }
        if merged.photoCount == nil { merged.photoCount = current.photoCount }
        return merged
    }

    /// An empty body must not wipe a stored post that already has content.
    /// A non-empty body is a real post document and may add or remove photos.
    static func shouldReplaceCachedPost(existing: Post, with incoming: Post) -> Bool {
        if incoming.id != existing.id { return false }
        if incoming.body.isEmpty, !existing.body.isEmpty { return false }
        return true
    }

    static func monthKey(for postDate: String?) -> String? {
        guard let postDate else { return nil }
        let parts = postDate.split(separator: "-")
        guard parts.count >= 2,
              parts[0].count == 4,
              parts[0].allSatisfy(\.isNumber),
              (1...2).contains(parts[1].count),
              parts[1].allSatisfy(\.isNumber),
              let month = Int(parts[1]),
              (1...12).contains(month)
        else { return nil }
        return "\(parts[0])-\(String(format: "%02d", month))"
    }

    static func monthTitle(_ key: String) -> String {
        guard key != "unknown" else { return "日期不明" }
        let parts = key.split(separator: "-")
        guard parts.count == 2 else { return key }
        return "\(parts[0]).\(parts[1])"
    }
}
