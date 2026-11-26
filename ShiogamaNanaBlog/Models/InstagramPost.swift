import Foundation

extension BlogSite {
    static let instagramURL = URL(string: "https://shiogama-nana-blog.vercel.app/api/instagram")!

    static func instagramPostURL(code: String) -> URL? {
        guard InstagramPost.isSafeCode(code) else { return nil }
        guard var components = URLComponents(url: instagramURL, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        return components.url
    }
}

struct InstagramRoute: Hashable, Sendable {
    var code: String
}

enum InstagramDecodeError: Error {
    case badResponse
}

struct InstagramPhoto: Hashable, Codable, Sendable {
    var src: String
    var width: Int?
    var height: Int?

    var url: URL? { BlogSite.imageURL(from: src) }

    /// Smaller sibling used for the grid. Nil when this `src` has no `-sm.webp`.
    var thumbnailURL: URL? {
        guard let small = InstagramImage.smallSource(from: src) else { return nil }
        return BlogSite.imageURL(from: small)
    }

    var aspectRatio: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }
}

/// One carousel page. Unknown types stay in the list so `img_index` still
/// matches the post on Instagram.
enum InstagramSlide: Hashable, Sendable {
    case photo(InstagramPhoto)
    case video
    case missing
    case unknown(String)

    var photo: InstagramPhoto? {
        if case .photo(let photo) = self { return photo }
        return nil
    }

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }

    fileprivate init(json: Any) {
        guard let object = json as? [String: Any] else {
            self = .unknown("")
            return
        }
        let type = (object["type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch type {
        case "video":
            self = .video
        case "photo":
            let src = (object["src"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !src.isEmpty, BlogSite.imageURL(from: src) != nil else {
                self = .missing
                return
            }
            self = .photo(InstagramPhoto(
                src: src,
                width: instagramInt(object["width"]),
                height: instagramInt(object["height"])
            ))
        default:
            self = .unknown(type)
        }
    }
}

struct InstagramPost: Identifiable, Hashable, Sendable {
    var code: String
    var takenAt: Date?
    var caption: String?
    var permalink: String?
    var slides: [InstagramSlide]
    var photoCount: Int?
    var addedAt: String?

    var id: String { code }

    var dateLabel: String { InstagramDates.label(for: takenAt) }

    var dayLabel: String { InstagramDates.day(for: takenAt) }

    var photoAlt: String {
        dateLabel.isEmpty ? "Instagram 照片" : "\(dateLabel) Instagram 照片"
    }

    /// Caption ready to show. Internal line breaks stay; a blank caption is hidden.
    var captionText: String? {
        guard let caption else { return nil }
        let normalized = caption
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var coverPhoto: InstagramPhoto? {
        slides.compactMap(\.photo).first { $0.url != nil }
    }

    var coverThumbnailURL: URL? {
        guard let coverPhoto else { return nil }
        return coverPhoto.thumbnailURL ?? coverPhoto.url
    }

    var photoURLs: [URL] {
        slides.compactMap { $0.photo?.url }
    }

    /// The post on instagram.com. An unusable `permalink` is replaced with one built from `code`.
    var instagramURL: URL? {
        InstagramLink.postURL(permalink: permalink, code: code)
    }

    /// Same post, opened on a slide. `position` is 1-based, matching `img_index`.
    func instagramURL(slidePosition: Int) -> URL? {
        guard slidePosition > 0, let instagramURL else { return nil }
        guard var components = URLComponents(url: instagramURL, resolvingAgainstBaseURL: false) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "img_index" }
        items.append(URLQueryItem(name: "img_index", value: String(slidePosition)))
        components.queryItems = items
        guard let url = components.url, InstagramLink.isInstagram(url) else { return nil }
        return url
    }

    func normalized() -> InstagramPost? {
        guard Self.isSafeCode(code) else { return nil }
        return self
    }

    static func isSafeCode(_ code: String) -> Bool {
        code.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil
    }

    /// Accepts a JSON array, or one post object from `?code=`.
    /// Items without a usable `code` are skipped. An array that is not empty
    /// but contains no posts is rejected.
    static func decodeList(from data: Data) throws -> [InstagramPost] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw InstagramDecodeError.badResponse
        }
        let items: [Any]
        if let array = json as? [Any] {
            items = array
        } else if let object = json as? [String: Any] {
            items = [object]
        } else {
            throw InstagramDecodeError.badResponse
        }
        if items.isEmpty { return [] }
        let parser = InstagramJSONParser()
        var posts: [InstagramPost] = []
        posts.reserveCapacity(items.count)
        for item in items {
            guard let object = item as? [String: Any],
                  let post = InstagramPost(json: object, parser: parser)
            else { continue }
            posts.append(post)
        }
        if posts.isEmpty { throw InstagramDecodeError.badResponse }
        return InstagramSorting.newestFirst(posts)
    }

    private init?(json: [String: Any], parser: InstagramJSONParser) {
        guard let rawCode = json["code"] as? String else { return nil }
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafeCode(code) else { return nil }
        self.code = code
        takenAt = parser.date(from: json["taken_at"])
        if let caption = json["caption"] as? String {
            self.caption = caption
        } else {
            caption = nil
        }
        if let permalink = json["permalink"] as? String {
            self.permalink = permalink
        } else {
            permalink = nil
        }
        if let rawSlides = json["slides"] as? [Any] {
            slides = rawSlides.map { InstagramSlide(json: $0) }
        } else {
            slides = []
        }
        photoCount = instagramInt(json["photo_count"])
        if let addedAt = json["added_at"] as? String {
            self.addedAt = addedAt
        } else {
            addedAt = nil
        }
    }
}

enum InstagramSorting {
    /// Newest `taken_at` first. Posts with no date stay at the end, in the
    /// order they were given. The same `code` is kept once, preferring the newer row.
    static func newestFirst(_ posts: [InstagramPost]) -> [InstagramPost] {
        let sorted = posts.sorted { lhs, rhs in
            switch (lhs.takenAt, rhs.takenAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return false
            }
        }
        var seen = Set<String>()
        return sorted.filter { seen.insert($0.code).inserted }
    }
}

enum InstagramDates {
    private static let tokyo = TimeZone(identifier: "Asia/Tokyo")
        ?? TimeZone(secondsFromGMT: 9 * 60 * 60)
        ?? TimeZone(abbreviation: "UTC")
        ?? TimeZone.current

    static func label(for date: Date?) -> String {
        guard let parts = parts(for: date) else { return "" }
        return String(format: "%04d.%02d.%02d %02d:%02d JST", parts.year, parts.month, parts.day, parts.hour, parts.minute)
    }

    static func day(for date: Date?) -> String {
        guard let parts = parts(for: date) else { return "" }
        return String(format: "%04d.%02d.%02d", parts.year, parts.month, parts.day)
    }

    private struct Parts {
        var year: Int
        var month: Int
        var day: Int
        var hour: Int
        var minute: Int
    }

    private static func parts(for date: Date?) -> Parts? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute
        else { return nil }
        return Parts(year: year, month: month, day: day, hour: hour, minute: minute)
    }
}

enum InstagramTime {
    static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return InstagramJSONParser().date(from: trimmed)
    }
}

enum InstagramLink {
    static func postURL(permalink: String?, code: String) -> URL? {
        if let permalink,
           let url = BlogSite.webURL(from: permalink),
           isInstagram(url) {
            return url
        }
        guard InstagramPost.isSafeCode(code) else { return nil }
        return URL(string: "https://www.instagram.com/p/\(code)/")
    }

    static func isInstagram(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "www.instagram.com" || host == "instagram.com",
              url.user == nil,
              url.password == nil
        else { return false }
        return true
    }
}

enum InstagramImage {
    private static let smallVariant = try? NSRegularExpression(
        pattern: #"^(/photos/(?:\d+|ig/[A-Za-z0-9_-]+)/\d+)\.(?:jpe?g|png|webp)$"#,
        options: [.caseInsensitive]
    )

    static func smallSource(from src: String) -> String? {
        guard let smallVariant else { return nil }
        let range = NSRange(src.startIndex..<src.endIndex, in: src)
        guard let match = smallVariant.firstMatch(in: src, options: [], range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: src)
        else { return nil }
        return "\(src[capture])-sm.webp"
    }
}

private struct InstagramJSONParser {
    private let fractional: ISO8601DateFormatter
    private let plain: ISO8601DateFormatter

    init() {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractional = fractional
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        self.plain = plain
    }

    func date(from value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return date(from: string)
    }

    func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return fractional.date(from: trimmed) ?? plain.date(from: trimmed)
    }
}

private func instagramInt(_ value: Any?) -> Int? {
    if value == nil || value is NSNull { return nil }
    if let int = value as? Int { return int }
    if let double = value as? Double, double.isFinite {
        guard double <= Double(Int.max), double >= Double(Int.min) else { return nil }
        return Int(double.rounded())
    }
    if let string = value as? String {
        return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if let number = value as? NSNumber {
        let double = number.doubleValue
        guard double.isFinite, double <= Double(Int.max), double >= Double(Int.min) else { return nil }
        return Int(double.rounded())
    }
    return nil
}

extension InstagramPost: Codable {
    enum CodingKeys: String, CodingKey {
        case code
        case takenAt = "taken_at"
        case caption
        case permalink
        case slides
        case photoCount = "photo_count"
        case addedAt = "added_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? container.decode(String.self, forKey: .code)) ?? ""
        if let takenAt = try? container.decode(Date.self, forKey: .takenAt) {
            self.takenAt = takenAt
        } else if let takenAt = try? container.decode(String.self, forKey: .takenAt) {
            self.takenAt = InstagramTime.parse(takenAt)
        } else {
            takenAt = nil
        }
        caption = try? container.decode(String.self, forKey: .caption)
        permalink = try? container.decode(String.self, forKey: .permalink)
        slides = (try? container.decode([InstagramSlide].self, forKey: .slides)) ?? []
        photoCount = instagramFlexibleInt(container, .photoCount)
        addedAt = try? container.decode(String.self, forKey: .addedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(takenAt, forKey: .takenAt)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encodeIfPresent(permalink, forKey: .permalink)
        try container.encode(slides, forKey: .slides)
        try container.encodeIfPresent(photoCount, forKey: .photoCount)
        try container.encodeIfPresent(addedAt, forKey: .addedAt)
    }
}

extension InstagramSlide: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case src
        case width
        case height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? ""
        switch type {
        case "video":
            self = .video
        case "missing":
            self = .missing
        case "photo":
            let src = (try? container.decode(String.self, forKey: .src)) ?? ""
            guard !src.isEmpty, BlogSite.imageURL(from: src) != nil else {
                self = .missing
                return
            }
            self = .photo(InstagramPhoto(
                src: src,
                width: instagramFlexibleInt(container, .width),
                height: instagramFlexibleInt(container, .height)
            ))
        default:
            self = .unknown(type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .photo(let photo):
            try container.encode("photo", forKey: .type)
            try container.encode(photo.src, forKey: .src)
            try container.encodeIfPresent(photo.width, forKey: .width)
            try container.encodeIfPresent(photo.height, forKey: .height)
        case .video:
            try container.encode("video", forKey: .type)
        case .missing:
            try container.encode("missing", forKey: .type)
        case .unknown(let type):
            try container.encode(type.isEmpty ? "unknown" : type, forKey: .type)
        }
    }
}

private func instagramFlexibleInt<Key: CodingKey>(
    _ container: KeyedDecodingContainer<Key>,
    _ key: Key
) -> Int? {
    if let value = try? container.decode(Int.self, forKey: key) { return value }
    if let value = try? container.decode(Double.self, forKey: key), value.isFinite {
        return Int(value.rounded())
    }
    if let value = try? container.decode(String.self, forKey: key) {
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
}
