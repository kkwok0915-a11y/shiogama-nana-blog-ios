import SwiftUI

/// 動態: blog posts and Instagram posts in one timeline.
struct FeedView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(InstagramArchive.self) private var archive
    @Environment(\.colorScheme) private var colorScheme
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var source: GallerySource = .all
    @State private var requestedDate: String?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchedBlog: [Post] {
        library.posts.filter { $0.matchesTitle(trimmedQuery) }
    }

    private var searchedInstagram: [InstagramPost] {
        archive.posts.filter { FeedCatalog.matches($0, query: trimmedQuery) }
    }

    private var allEntries: [FeedEntry] {
        FeedCatalog.entries(blog: searchedBlog, instagram: searchedInstagram)
    }

    private var showSourceFilter: Bool {
        !archive.posts.isEmpty
    }

    private var effectiveSource: GallerySource {
        showSourceFilter ? source : .all
    }

    private var sourceEntries: [FeedEntry] {
        FeedCatalog.filtering(allEntries, source: effectiveSource)
    }

    private var availableDates: [String] {
        GalleryCatalog.uniqueDates(sourceEntries.map(\.day))
    }

    private var shownDate: String? {
        GalleryCatalog.nearestDate(in: availableDates, want: requestedDate)
    }

    private var entries: [FeedEntry] {
        FeedCatalog.filtering(sourceEntries, day: shownDate)
    }

    private var counts: GalleryCounts {
        let dated = FeedCatalog.filtering(allEntries, day: shownDate)
        return FeedCatalog.counts(in: dated)
    }

    private var sections: [FeedSection] {
        FeedCatalog.sections(from: entries)
    }

    private var waiting: Bool {
        allEntries.isEmpty
            && trimmedQuery.isEmpty
            && (library.isLoadingInitial || archive.isLoadingInitial)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("動態")
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋文章或貼文")
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
                .navigationDestination(for: PostRoute.self) { route in
                    PostDetailView(postID: route.id)
                }
                .navigationDestination(for: InstagramRoute.self) { route in
                    InstagramDetailView(code: route.code)
                }
                .onAppear(perform: openRequestedPost)
                .onChange(of: archive.openRequest) { _, _ in
                    openRequestedPost()
                }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var content: some View {
        if waiting {
            skeleton
        } else if library.posts.isEmpty && archive.posts.isEmpty {
            unavailableScroll {
                if library.loadFailed || archive.loadFailed {
                    ContentUnavailableView {
                        Label("無法載入", systemImage: "wifi.slash")
                    } description: {
                        Text("連不上部落格。連線後再試一次；成功讀過的內容會留在這支手機上。")
                    } actions: {
                        Button("再試一次") { Task { await refreshAll() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("還沒有動態", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("下拉可以再檢查一次。")
                    }
                }
            }
        } else {
            feed
        }
    }

    private var skeleton: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    FeedCardSkeleton()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .accessibilityLabel("載入動態")
        .refreshable { await refreshAll() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                filterRow
                if let requestedDate, let shownDate, requestedDate != shownDate {
                    Text("\(Self.display(requestedDate)) 沒有動態，已顯示最接近的 \(Self.display(shownDate))。")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 16)
                }
                Text(countText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                if let banner = library.bannerText ?? archive.bannerText {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 20)
                }
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("找不到符合的動態", systemImage: "magnifyingglass")
                    } description: {
                        Text(trimmedQuery.isEmpty ? "換個日期或來源再看一次。" : "沒有內容符合「\(trimmedQuery)」。")
                    }
                    .padding(.top, 24)
                } else {
                    LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                VStack(spacing: 12) {
                                    ForEach(section.entries) { entry in
                                        row(entry)
                                    }
                                }
                                .padding(.horizontal, 16)
                            } header: {
                                Text(section.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Theme.background)
                                    .accessibilityAddTraits(.isHeader)
                            }
                        }
                    }
                }
                if trimmedQuery.isEmpty, let updated = library.lastUpdatedText ?? archive.lastUpdatedText {
                    Text("更新於 \(updated)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await refreshAll() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filterRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if showSourceFilter {
                Picker("動態來源", selection: $source) {
                    Text("全部 \(counts.all)").tag(GallerySource.all)
                    Text("Blog \(counts.blog)").tag(GallerySource.blog)
                    Text("IG \(counts.instagram)").tag(GallerySource.instagram)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("動態來源")
            } else {
                Spacer(minLength: 0)
            }
            GalleryDateFilter(dates: availableDates, value: shownDate) { requestedDate = $0 }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var countText: String {
        if shownDate != nil || effectiveSource != .all || !trimmedQuery.isEmpty {
            return "找到 \(entries.count) 則動態"
        }
        if library.isLoadingInitial || archive.isLoadingInitial {
            return "\(entries.count) 則動態，更新中"
        }
        return "\(entries.count) 則動態，由新到舊"
    }

    @ViewBuilder
    private func row(_ entry: FeedEntry) -> some View {
        if entry.isBlog, let id = entry.blogID, let post = library.resolvedPost(id: id) {
            NavigationLink(value: PostRoute(id: id)) {
                BlogFeedCard(post: post)
            }
            .buttonStyle(.plain)
            .accessibilityHint("點一下閱讀全文")
        } else if let code = entry.instagramCode, let post = archive.post(code: code) {
            NavigationLink(value: InstagramRoute(code: code)) {
                InstagramFeedCard(post: post)
            }
            .buttonStyle(.plain)
            .accessibilityHint("點一下查看貼文")
        }
    }

    private func unavailableScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.top, 32)
                .frame(maxWidth: .infinity)
        }
        .refreshable { await refreshAll() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refreshAll() async {
        async let posts: Void = library.refresh()
        async let instagram: Void = archive.refresh()
        _ = await (posts, instagram)
    }

    private func openRequestedPost() {
        guard let code = archive.takeOpenRequest() else { return }
        path.append(InstagramRoute(code: code))
    }

    private static func display(_ day: String) -> String {
        day.replacingOccurrences(of: "-", with: ".")
    }
}

private struct FeedCardSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Shimmer(cornerRadius: 10)
                .frame(width: 84, height: 112)
            VStack(alignment: .leading, spacing: 8) {
                Shimmer(cornerRadius: 4)
                    .frame(width: 96, height: 12)
                Shimmer(cornerRadius: 4)
                    .frame(height: 18)
                Shimmer(cornerRadius: 4)
                    .frame(height: 14)
                Shimmer(cornerRadius: 4)
                    .frame(height: 36)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct BlogFeedCard: View {
    let post: Post

    var body: some View {
        FeedCardShell(
            imageURL: post.coverURL,
            thumbnailURL: post.coverURL.flatMap { GalleryCatalog.previewURL(for: $0) },
            badge: "Blog",
            date: post.dateLabel,
            title: post.displayTitleZh,
            subtitle: post.displayTitleJp,
            excerpt: FeedCatalog.excerpt(of: post),
            count: post.imageCount > 1 ? post.imageCount : nil,
            fallbackMark: "菜"
        )
    }
}

private struct InstagramFeedCard: View {
    let post: InstagramPost

    private var lines: [String] {
        FeedCatalog.captionLines(post.captionText ?? "")
    }

    var body: some View {
        FeedCardShell(
            imageURL: post.coverPhoto?.url,
            thumbnailURL: post.coverThumbnailURL,
            badge: "IG",
            date: post.dayLabel,
            title: lines.first ?? "Instagram 貼文",
            subtitle: nil,
            excerpt: lines.dropFirst().joined(separator: " ").nilIfBlank,
            count: post.slides.count > 1 ? post.slides.count : nil,
            fallbackMark: "IG"
        )
    }
}

private struct FeedCardShell: View {
    var imageURL: URL?
    var thumbnailURL: URL?
    var badge: String
    var date: String
    var title: String
    var subtitle: String?
    var excerpt: String?
    var count: Int?
    var fallbackMark: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumb
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !date.isEmpty {
                        Text(date)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                    Spacer(minLength: 0)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var thumb: some View {
        Rectangle()
            .fill(Theme.background)
            .frame(width: 84, height: 112)
            .overlay {
                if imageURL != nil || thumbnailURL != nil {
                    CachedImage(
                        url: thumbnailURL ?? imageURL,
                        fallbackURL: thumbnailURL == nil ? nil : imageURL,
                        maxPixel: 480,
                        contentMode: .fill
                    )
                } else {
                    Text(fallbackMark)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let count {
                    Text("📷 \(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
