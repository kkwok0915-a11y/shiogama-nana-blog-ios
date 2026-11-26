import SwiftUI

struct PostDetailView: View {
    let postID: String

    @Environment(LibraryModel.self) private var library
    @Environment(\.colorScheme) private var colorScheme
    @State private var presented: PresentedPhoto?
    @State private var attemptedID: String?

    var body: some View {
        Group {
            if let post = library.resolvedPost(id: postID) {
                detail(for: post)
            } else if attemptedID != postID {
                ProgressView("載入文章…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("找不到這篇文章", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("它不在上次儲存的清單裡。回到列表後下拉更新。")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(library.resolvedPost(id: postID)?.dateLabel ?? "文章")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        .task(id: postID) {
            await library.open(id: postID)
            attemptedID = postID
        }
    }

    @ViewBuilder
    private func detail(for post: Post) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    if !post.dateLabel.isEmpty {
                        Text(post.dateLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(post.displayTitleZh)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let titleJp = post.displayTitleJp {
                        Text(titleJp)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let originalURL = post.originalURL {
                    Link(destination: originalURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "safari")
                            Text("閱讀官方原文")
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .accessibilityHint("在 Safari 開啟官方原文")
                }

                ForEach(blockItems(in: post)) { item in
                    switch item.block {
                    case .text(let text):
                        PostBodyText(text: text)
                    case .photo(let photo):
                        if let url = photo.url {
                            Button {
                                presented = PresentedPhoto(id: item.id, url: url, alt: photo.altText)
                            } label: {
                                CachedImage(
                                    url: url,
                                    maxPixel: 2048,
                                    contentMode: .fit,
                                    placeholderAspect: photo.aspectRatio.map { CGFloat($0) }
                                )
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(photo.altText)
                            .accessibilityHint("點一下以全螢幕檢視")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await library.open(id: postID)
        }
        .fullScreenCover(item: $presented) { photo in
            PhotoViewer(photo: photo) { presented = nil }
        }
    }

    private func blockItems(in post: Post) -> [BlockItem] {
        post.contentBlocks.enumerated().map { index, block in
            let id: String
            switch block {
            case .text:
                id = "t\(index)"
            case .photo(let photo):
                id = "p\(index)|\(photo.src)"
            }
            return BlockItem(id: id, block: block)
        }
    }
}

private struct BlockItem: Identifiable {
    var id: String
    var block: ContentBlock
}

private struct PostBodyText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(Self.attributed(paragraph))
                    .font(.body)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private var paragraphs: [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static let links = try? NSRegularExpression(pattern: #"https?://[^\s<>（）()\[\]「」]+"#)
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?。，、")

    private static func attributed(_ paragraph: String) -> AttributedString {
        let source = paragraph as NSString
        guard let links, source.length > 0 else { return colored(paragraph) }
        let matches = links.matches(in: paragraph, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return colored(paragraph) }

        var result = AttributedString()
        var cursor = 0
        for match in matches {
            let range = match.range
            if range.location > cursor {
                let piece = source.substring(with: NSRange(location: cursor, length: range.location - cursor))
                result += colored(piece)
            }
            let raw = source.substring(with: range)
            let (urlText, suffix) = splitTrailingPunctuation(raw)
            if let url = BlogSite.webURL(from: urlText) {
                var link = AttributedString(urlText)
                link.link = url
                link.foregroundColor = Theme.accent
                link.underlineStyle = .single
                result += link
                if !suffix.isEmpty {
                    result += colored(suffix)
                }
            } else {
                result += colored(raw)
            }
            cursor = range.location + range.length
        }
        if cursor < source.length {
            result += colored(source.substring(from: cursor))
        }
        return result
    }

    private static func colored(_ text: String) -> AttributedString {
        var value = AttributedString(text)
        value.foregroundColor = Theme.ink
        return value
    }

    private static func splitTrailingPunctuation(_ raw: String) -> (String, String) {
        var urlText = raw
        var suffix = ""
        while let scalar = urlText.unicodeScalars.last, trailingPunctuation.contains(scalar) {
            suffix = String(scalar) + suffix
            urlText.unicodeScalars.removeLast()
        }
        if urlText.isEmpty { return (raw, "") }
        return (urlText, suffix)
    }
}
