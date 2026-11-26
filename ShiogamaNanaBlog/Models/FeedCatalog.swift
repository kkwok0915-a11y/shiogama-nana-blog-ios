import Foundation

/// One row in the 動態 timeline. Blog rows are built first, then Instagram,
/// and the list is sorted newest day first. The sort is stable, so a shared
/// day keeps the blog post ahead of the Instagram post.
struct FeedEntry: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case blog
        case instagram
    }

    var id: String
    var kind: Kind
    /// `yyyy-MM-dd`. Instagram uses the Japan calendar day.
    var day: String?
    var blogID: String?
    var instagramCode: String?

    var isBlog: Bool { kind == .blog }
}

struct FeedSection: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var entries: [FeedEntry]
}

enum FeedCatalog {
    static func entries(blog posts: [Post], instagram: [InstagramPost]) -> [FeedEntry] {
        let blog = PostSorting.newestFirst(posts).map { post in
            FeedEntry(
                id: "b-\(post.id)",
                kind: .blog,
                day: GalleryCatalog.dayKey(post.postDate),
                blogID: post.id,
                instagramCode: nil
            )
        }
        let ig = instagram.map { post in
            FeedEntry(
                id: "i-\(post.code)",
                kind: .instagram,
                day: GalleryCatalog.dayKey(post.dayLabel.replacingOccurrences(of: ".", with: "-")),
                blogID: nil,
                instagramCode: post.code
            )
        }
        return (blog + ig).sorted { ($0.day ?? "") > ($1.day ?? "") }
    }

    static func filtering(_ entries: [FeedEntry], source: GallerySource) -> [FeedEntry] {
        switch source {
        case .all:
            return entries
        case .blog:
            return entries.filter(\.isBlog)
        case .instagram:
            return entries.filter { !$0.isBlog }
        }
    }

    static func filtering(_ entries: [FeedEntry], day: String?) -> [FeedEntry] {
        guard let day else { return entries }
        return entries.filter { $0.day == day }
    }

    static func counts(in entries: [FeedEntry]) -> GalleryCounts {
        let blog = entries.reduce(into: 0) { if $1.isBlog { $0 += 1 } }
        return GalleryCounts(all: entries.count, blog: blog, instagram: entries.count - blog)
    }

    static func sections(from entries: [FeedEntry]) -> [FeedSection] {
        var grouped: [String: [FeedEntry]] = [:]
        var order: [String] = []
        for entry in entries {
            let key = GalleryCatalog.monthKey(for: entry.day) ?? "unknown"
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(entry)
        }
        return order.map { key in
            FeedSection(id: key, title: GalleryCatalog.monthTitle(key), entries: grouped[key] ?? [])
        }
    }

    static func matches(_ post: InstagramPost, query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return true }
        let haystack = "\(post.captionText ?? "")\n\(post.dateLabel)\n\(post.dayLabel)"
        return terms.allSatisfy { haystack.localizedStandardContains($0) }
    }

    /// First caption lines that are not spacers (`・`) or hashtag-only lines.
    static func captionLines(_ caption: String) -> [String] {
        caption
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                containsLetterOrNumber(line) && !isHashtagsOnly(line)
            }
    }

    /// Short preview of a blog post, skipping the fixed greeting lines.
    static func excerpt(of post: Post) -> String? {
        var lines: [String] = []
        for block in post.contentBlocks {
            guard case .text(let text) = block else { continue }
            lines.append(contentsOf: text.components(separatedBy: "\n"))
        }
        while let first = lines.first {
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || isGreeting(trimmed) {
                lines.removeFirst()
            } else {
                break
            }
        }
        let flat = lines
            .joined(separator: " ")
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        if flat.count > 90 {
            return String(flat.prefix(90)) + "…"
        }
        return flat
    }

    private static func containsLetterOrNumber(_ line: String) -> Bool {
        line.unicodeScalars.contains { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
    }

    private static func isHashtagsOnly(_ line: String) -> Bool {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            part.hasPrefix("#") && part.count > 1
        }
    }

    private static func isGreeting(_ line: String) -> Bool {
        line.hasPrefix("おやっとさ") || line.hasPrefix("歡迎來到我的部落格") || line.hasPrefix("ようこそ")
    }
}
