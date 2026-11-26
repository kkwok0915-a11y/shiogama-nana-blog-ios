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

enum GallerySource: String, Hashable, Sendable, CaseIterable {
    case all
    case blog
    case instagram
}

struct GalleryCounts: Equatable, Sendable {
    var all: Int
    var blog: Int
    var instagram: Int
}

/// One tile in the mixed gallery. Blog photos are listed before Instagram
/// photos, then the whole list is sorted newest day first. Swift's sort is
/// stable, so a shared day keeps blog photos ahead of Instagram.
struct MixedGalleryPhoto: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case blog(postID: String, title: String)
        case instagram(code: String, slideIndex: Int)
    }

    var id: String
    var kind: Kind
    /// `yyyy-MM-dd`. Instagram uses the Japan calendar day.
    var day: String?
    var url: URL
    var thumbnailURL: URL?
    var alt: String

    var isBlog: Bool {
        if case .blog = kind { return true }
        return false
    }
}

struct MixedGallerySection: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var photos: [MixedGalleryPhoto]
}

extension GalleryCatalog {
    static func mixedPhotos(blog posts: [Post], instagram: [InstagramPost]) -> [MixedGalleryPhoto] {
        var blogPhotos: [MixedGalleryPhoto] = []
        for post in PostSorting.newestFirst(posts) {
            for block in post.contentBlocks {
                guard case .photo(let photo) = block, let url = photo.url else { continue }
                blogPhotos.append(MixedGalleryPhoto(
                    id: "b-\(post.id)-\(photo.src)",
                    kind: .blog(postID: post.id, title: post.displayTitleZh),
                    day: dayKey(post.postDate),
                    url: url,
                    thumbnailURL: thumbnailURL(for: photo.src),
                    alt: photo.altText
                ))
            }
        }

        var instagramPhotos: [MixedGalleryPhoto] = []
        for post in instagram {
            for (index, slide) in post.slides.enumerated() {
                guard let photo = slide.photo, let url = photo.url else { continue }
                let position = index + 1
                instagramPhotos.append(MixedGalleryPhoto(
                    id: "i-\(post.code)-\(index)",
                    kind: .instagram(code: post.code, slideIndex: index),
                    day: dayKey(post.dayLabel.replacingOccurrences(of: ".", with: "-")),
                    url: url,
                    thumbnailURL: photo.thumbnailURL ?? thumbnailURL(for: photo.src),
                    alt: post.dateLabel.isEmpty
                        ? "Instagram 第 \(position) 張照片"
                        : "Instagram \(post.dateLabel) 第 \(position) 張照片"
                ))
            }
        }

        return (blogPhotos + instagramPhotos).sorted { lhs, rhs in
            (lhs.day ?? "") > (rhs.day ?? "")
        }
    }

    static func filtering(_ items: [MixedGalleryPhoto], source: GallerySource) -> [MixedGalleryPhoto] {
        switch source {
        case .all:
            return items
        case .blog:
            return items.filter(\.isBlog)
        case .instagram:
            return items.filter { !$0.isBlog }
        }
    }

    /// Newest `yyyy-MM-dd` first. Only real calendar days are kept.
    static func uniqueDates(in items: [MixedGalleryPhoto]) -> [String] {
        var seen = Set<String>()
        var dates: [String] = []
        for item in items {
            guard let day = item.day, isCalendarDay(day), seen.insert(day).inserted else { continue }
            dates.append(day)
        }
        return dates.sorted { $0 > $1 }
    }

    /// Closest available day to `want`. An exact match wins. A tie keeps the
    /// newer day, because `dates` is newest first and only a strictly closer
    /// day replaces the current best.
    static func nearestDate(in dates: [String], want: String?) -> String? {
        guard let want, !dates.isEmpty else { return nil }
        if dates.contains(want) { return want }
        guard let target = dayNumber(want) else { return dates.first }
        var best = dates[0]
        var bestDistance = abs((dayNumber(best) ?? target) - target)
        for day in dates.dropFirst() {
            guard let number = dayNumber(day) else { continue }
            let distance = abs(number - target)
            if distance < bestDistance {
                best = day
                bestDistance = distance
            }
        }
        return best
    }

    static func filtering(_ items: [MixedGalleryPhoto], day: String?) -> [MixedGalleryPhoto] {
        guard let day else { return items }
        return items.filter { $0.day == day }
    }

    /// Counts for the snapped day across every source. `day` nil counts everything.
    static func counts(in items: [MixedGalleryPhoto], day: String?) -> GalleryCounts {
        let scoped = filtering(items, day: day)
        let blog = scoped.reduce(into: 0) { if $1.isBlog { $0 += 1 } }
        return GalleryCounts(all: scoped.count, blog: blog, instagram: scoped.count - blog)
    }

    static func mixedSections(from items: [MixedGalleryPhoto]) -> [MixedGallerySection] {
        var grouped: [String: [MixedGalleryPhoto]] = [:]
        var order: [String] = []
        for photo in items {
            let key = monthKey(for: photo.day) ?? "unknown"
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(photo)
        }
        return order.map { key in
            MixedGallerySection(id: key, title: monthTitle(key), photos: grouped[key] ?? [])
        }
    }

    static func thumbnailURL(for src: String) -> URL? {
        guard let small = InstagramImage.smallSource(from: src) else { return nil }
        return BlogSite.imageURL(from: small)
    }

    static func dayKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }
        let day = String(trimmed.prefix(10))
        return isCalendarDay(day) ? day : nil
    }

    private static func isCalendarDay(_ day: String) -> Bool {
        guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let parts = day.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let dayNumber = Int(parts[2]),
              (1...12).contains(month)
        else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(abbreviation: "UTC") ?? .current
        let components = DateComponents(year: year, month: month, day: dayNumber)
        guard let date = calendar.date(from: components) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == dayNumber
    }

    private static func dayNumber(_ day: String) -> Int? {
        guard isCalendarDay(day) else { return nil }
        let parts = day.split(separator: "-")
        guard let year = Int(parts[0]), let month = Int(parts[1]), let dayNumber = Int(parts[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(abbreviation: "UTC") ?? .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: dayNumber)) else { return nil }
        return Int(date.timeIntervalSince1970 / 86_400)
    }
}
