import Foundation

/// Public site the app is allowed to read. Image paths in post JSON are
/// relative to this origin. Photo bytes may also come from `photoHost`.
enum BlogSite {
    static let host = "shiogama-nana-blog.vercel.app"
    /// Public Vercel Blob store. `/photos/*` on `host` 308s here, same path.
    static let photoHost = "oulym35m6pqzgo1d.public.blob.vercel-storage.com"
    static let origin = URL(string: "https://shiogama-nana-blog.vercel.app")!
    static let postsURL = URL(string: "https://shiogama-nana-blog.vercel.app/api/posts")!

    static func postURL(id: String) -> URL? {
        guard isSafeID(id) else { return nil }
        guard var components = URLComponents(url: postsURL, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url
    }

    /// Resolves a photo `src` from the posts API. Absolute URLs must already
    /// point at this site, or at `photoHost` under `/photos/`. Relative URLs
    /// stay on the site origin so disk-cache keys do not change.
    static func imageURL(from src: String) -> URL? {
        let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty else { return nil }
        guard !lower.contains(".."), !lower.contains("%2e%2e"), !lower.contains("%00"), !lower.contains("\\"), !lower.contains("@") else {
            return nil
        }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            if allows(absolute) { return absolute }
            if absolute.host?.lowercased() == photoHost, allowsPhoto(absolute) { return absolute }
            return nil
        }
        guard trimmed.hasPrefix("/"), !trimmed.hasPrefix("//") else { return nil }
        guard let resolved = URL(string: trimmed, relativeTo: origin)?.absoluteURL else { return nil }
        return allows(resolved) ? resolved : nil
    }

    static func webURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil
        else { return nil }
        return url
    }

    static func isSafeID(_ id: String) -> Bool {
        guard id != ".", id != ".." else { return false }
        return id.range(of: #"^[A-Za-z0-9._-]{1,80}$"#, options: .regularExpression) != nil
    }

    static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == host,
              url.user == nil,
              url.password == nil
        else { return false }
        return true
    }

    /// Blog host or the public blob store. Comparison is case-insensitive.
    static func isTrustedPhotoHost(_ host: String?) -> Bool {
        guard let lowered = host?.lowercased() else { return false }
        return lowered == Self.host || lowered == photoHost
    }

    /// HTTPS photo URL on a trusted host. The path must stay under `/photos/`
    /// and must not contain `.` or `..` segments.
    static func allowsPhoto(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              isTrustedPhotoHost(url.host),
              url.user == nil,
              url.password == nil,
              isPhotosPath(url)
        else { return false }
        return true
    }

    /// Fetch URL for a photo. Blog-host `/photos/` URLs are rewritten onto
    /// `photoHost` with the same path so the 308 can be skipped. Callers keep
    /// using the original URL as the disk-cache key.
    static func photoRequestURL(for url: URL) -> URL? {
        guard allowsPhoto(url) else { return nil }
        guard url.host?.lowercased() == host else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        components.host = photoHost
        components.port = nil
        components.user = nil
        components.password = nil
        guard let rewritten = components.url,
              allowsPhoto(rewritten),
              rewritten.path == url.path
        else { return url }
        return rewritten
    }

    private static func isPhotosPath(_ url: URL) -> Bool {
        guard url.path.hasPrefix("/photos/") else { return false }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count >= 2, segments.first == "photos" else { return false }
        return segments.allSatisfy { $0 != "." && $0 != ".." }
    }
}

struct PostRoute: Hashable, Sendable {
    var id: String
}

struct PhotoBlock: Hashable, Sendable {
    var src: String
    var alt: String?
    var width: Int?
    var height: Int?

    var url: URL? { BlogSite.imageURL(from: src) }

    var aspectRatio: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }

    var altText: String {
        let trimmed = alt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "部落格照片" : trimmed
    }
}

/// One block of a post body. The live API uses `text` and `photo`.
/// `image` is accepted so a future rename of that block type still renders.
enum ContentBlock: Hashable, Sendable {
    case text(String)
    case photo(PhotoBlock)
}

struct Post: Identifiable, Hashable, Sendable {
    var id: String
    var titleZh: String
    var titleJp: String?
    var postDate: String?
    var originalUrl: String?
    var body: [ContentBlock]
    var photoCount: Int?
    var addedAt: String?
    var published: Bool?

    var displayTitleZh: String {
        titleZh.isEmpty ? "未命名文章" : titleZh
    }

    var displayTitleJp: String? { titleJp }

    var dateLabel: String {
        guard let postDate, !postDate.isEmpty else { return "" }
        let parts = postDate.split(separator: "-")
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return postDate }
        return parts.joined(separator: ".")
    }

    var originalURL: URL? {
        guard let originalUrl else { return nil }
        return BlogSite.webURL(from: originalUrl)
    }

    var photoURLs: [URL] {
        body.compactMap { block in
            if case .photo(let photo) = block { return photo.url }
            return nil
        }
    }

    var coverURL: URL? { photoURLs.first }

    var imageCount: Int { photoURLs.count }

    var contentBlocks: [ContentBlock] {
        body.compactMap { block in
            switch block {
            case .text(let text):
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .text(text)
            case .photo(let photo):
                return photo.url == nil ? nil : .photo(photo)
            }
        }
    }

    func matchesTitle(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return true }
        let haystack = "\(displayTitleZh)\n\(displayTitleJp ?? "")"
        return terms.allSatisfy { haystack.localizedStandardContains($0) }
    }

    func normalized() -> Post? {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, published != false else { return nil }
        return Post(
            id: trimmedID,
            titleZh: titleZh.trimmingCharacters(in: .whitespacesAndNewlines),
            titleJp: titleJp?.blankToNil,
            postDate: postDate?.blankToNil,
            originalUrl: originalUrl?.blankToNil,
            body: body,
            photoCount: photoCount,
            addedAt: addedAt,
            published: published
        )
    }
}

enum PostSorting {
    static func newestFirst(_ posts: [Post]) -> [Post] {
        var seen = Set<String>()
        return posts.sorted(by: isNewer).filter { seen.insert($0.id).inserted }
    }

    private static func isNewer(_ lhs: Post, _ rhs: Post) -> Bool {
        let leftDate = lhs.postDate ?? ""
        let rightDate = rhs.postDate ?? ""
        if leftDate != rightDate { return leftDate > rightDate }
        if let leftID = Int(lhs.id), let rightID = Int(rhs.id), leftID != rightID {
            return leftID > rightID
        }
        return lhs.id.compare(rhs.id, options: .numeric) == .orderedDescending
    }
}

extension Post: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case titleZh = "title_zh"
        case titleJp = "title_jp"
        case postDate = "post_date"
        case originalUrl = "original_url"
        case body
        case photoCount = "photo_count"
        case addedAt = "added_at"
        case published
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let numberID = try? container.decode(Int.self, forKey: .id) {
            id = String(numberID)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Post id is missing."
            )
        }
        titleZh = (try? container.decode(String.self, forKey: .titleZh)) ?? ""
        titleJp = try? container.decode(String.self, forKey: .titleJp)
        postDate = try? container.decode(String.self, forKey: .postDate)
        originalUrl = try? container.decode(String.self, forKey: .originalUrl)
        body = (try? container.decode([ContentBlock].self, forKey: .body)) ?? []
        photoCount = flexibleInt(container, .photoCount)
        addedAt = try? container.decode(String.self, forKey: .addedAt)
        published = try? container.decode(Bool.self, forKey: .published)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(titleZh, forKey: .titleZh)
        try container.encodeIfPresent(titleJp, forKey: .titleJp)
        try container.encodeIfPresent(postDate, forKey: .postDate)
        try container.encodeIfPresent(originalUrl, forKey: .originalUrl)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(photoCount, forKey: .photoCount)
        try container.encodeIfPresent(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(published, forKey: .published)
    }
}

extension ContentBlock: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case text
        case src
        case alt
        case width
        case height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? ""
        switch type {
        case "text":
            self = .text((try? container.decode(String.self, forKey: .text)) ?? "")
        case "photo", "image":
            let src = (try? container.decode(String.self, forKey: .src)) ?? ""
            let alt = try? container.decode(String.self, forKey: .alt)
            guard !src.isEmpty else {
                self = .text("")
                return
            }
            self = .photo(PhotoBlock(
                src: src,
                alt: alt,
                width: flexibleInt(container, .width),
                height: flexibleInt(container, .height)
            ))
        default:
            self = .text("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .photo(let photo):
            try container.encode("photo", forKey: .type)
            try container.encode(photo.src, forKey: .src)
            try container.encodeIfPresent(photo.alt, forKey: .alt)
            try container.encodeIfPresent(photo.width, forKey: .width)
            try container.encodeIfPresent(photo.height, forKey: .height)
        }
    }
}

private func flexibleInt<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> Int? {
    if let value = try? container.decode(Int.self, forKey: key) { return value }
    if let value = try? container.decode(Double.self, forKey: key) { return Int(value.rounded()) }
    if let value = try? container.decode(String.self, forKey: key) { return Int(value) }
    return nil
}

private extension String {
    var blankToNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
