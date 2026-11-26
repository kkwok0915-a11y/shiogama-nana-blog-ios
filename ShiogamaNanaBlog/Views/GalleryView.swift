import SwiftUI

struct GalleryView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(InstagramArchive.self) private var archive
    @Environment(\.colorScheme) private var colorScheme
    @State private var path = NavigationPath()
    @State private var presentedPhotos: [PresentedPhoto] = []
    @State private var selection: ViewerSelection?
    @State private var pendingPostID: String?
    @State private var pendingInstagramCode: String?
    @State private var source: GallerySource = .all
    /// The day the user asked for. Nil means every day.
    @State private var requestedDate: String?

    private var allPhotos: [MixedGalleryPhoto] {
        GalleryCatalog.mixedPhotos(blog: library.posts, instagram: archive.posts)
    }

    private var showSourceFilter: Bool {
        !archive.posts.isEmpty
    }

    private var effectiveSource: GallerySource {
        showSourceFilter ? source : .all
    }

    private var sourcePhotos: [MixedGalleryPhoto] {
        GalleryCatalog.filtering(allPhotos, source: effectiveSource)
    }

    private var availableDates: [String] {
        GalleryCatalog.uniqueDates(in: sourcePhotos)
    }

    private var shownDate: String? {
        GalleryCatalog.nearestDate(in: availableDates, want: requestedDate)
    }

    private var photos: [MixedGalleryPhoto] {
        GalleryCatalog.filtering(sourcePhotos, day: shownDate)
    }

    private var counts: GalleryCounts {
        GalleryCatalog.counts(in: allPhotos, day: shownDate)
    }

    private var sections: [MixedGallerySection] {
        GalleryCatalog.mixedSections(from: photos)
    }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("照片")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
                .navigationDestination(for: PostRoute.self) { route in
                    PostDetailView(postID: route.id)
                }
                .fullScreenCover(item: $selection, onDismiss: openPending) { selection in
                    PhotoViewer(
                        photos: presentedPhotos,
                        initialID: selection.id,
                        onClose: { self.selection = nil },
                        onOpenPost: { postID in
                            pendingPostID = postID
                            self.selection = nil
                        },
                        onOpenInstagram: { code in
                            pendingInstagramCode = code
                            self.selection = nil
                        }
                    )
                }
                .onChange(of: source) { _, _ in selection = nil }
                .onChange(of: requestedDate) { _, _ in selection = nil }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var content: some View {
        if allPhotos.isEmpty && (library.isLoadingInitial || archive.isLoadingInitial) {
            ProgressView("載入照片…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if allPhotos.isEmpty {
            unavailableScroll {
                if library.isHydratingPhotos {
                    ProgressView("讀取文章中的照片…")
                } else if library.posts.isEmpty && library.loadFailed {
                    ContentUnavailableView {
                        Label("無法載入", systemImage: "wifi.slash")
                    } description: {
                        Text("連不上部落格。連線後再試一次；成功讀過的照片會留在這支手機上。")
                    } actions: {
                        Button("再試一次") { Task { await refreshAll() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if archive.posts.isEmpty && archive.loadFailed && library.posts.isEmpty {
                    ContentUnavailableView {
                        Label("無法載入", systemImage: "wifi.slash")
                    } description: {
                        Text("連不上 Instagram。連線後再試一次；成功讀過的照片會留在這支手機上。")
                    } actions: {
                        Button("再試一次") { Task { await refreshAll() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("還沒有照片", systemImage: "photo")
                    } description: {
                        Text(archive.bannerText ?? "下拉可以再檢查一次。")
                    }
                }
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                filterRow
                if let requestedDate, let shownDate, requestedDate != shownDate {
                    Text("\(Self.display(requestedDate)) 沒有照片，已顯示最接近的 \(Self.display(shownDate))。")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 16)
                        .accessibilityLabel("\(Self.display(requestedDate)) 沒有照片，已顯示最接近的 \(Self.display(shownDate))。")
                }
                countLine
                if let banner = library.photoBannerText ?? library.bannerText ?? archive.bannerText {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .accessibilityLabel(banner)
                }
                if photos.isEmpty {
                    ContentUnavailableView {
                        Label("這個範圍還沒有照片", systemImage: "photo")
                    } description: {
                        Text("換個日期或來源再看一次。")
                    }
                    .padding(.top, 24)
                } else {
                    LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(section.photos) { photo in
                                        cell(photo)
                                    }
                                }
                            } header: {
                                sectionHeader(section)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .refreshable { await refreshAll() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filterRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if showSourceFilter {
                sourcePicker
            } else {
                Spacer(minLength: 0)
            }
            GalleryDateFilter(dates: availableDates, value: shownDate) { requestedDate = $0 }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var sourcePicker: some View {
        Picker("照片來源", selection: $source) {
            Text("全部 \(counts.all)").tag(GallerySource.all)
            Text("Blog \(counts.blog)").tag(GallerySource.blog)
            Text("Instagram \(counts.instagram)").tag(GallerySource.instagram)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("照片來源")
    }

    private var countLine: some View {
        Text(countText)
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .accessibilityLabel(countText)
    }

    private var countText: String {
        if shownDate != nil || effectiveSource != .all {
            return "找到 \(photos.count) 張照片"
        }
        if library.isHydratingPhotos || archive.isLoadingInitial {
            return "\(photos.count) 張照片，更新中"
        }
        return "\(photos.count) 張照片"
    }

    private func sectionHeader(_ section: MixedGallerySection) -> some View {
        Text(section.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.background)
            .accessibilityAddTraits(.isHeader)
    }

    private func cell(_ photo: MixedGalleryPhoto) -> some View {
        Button {
            presentedPhotos = photos.map { item in
                PresentedPhoto(
                    id: item.id,
                    url: item.url,
                    alt: item.alt,
                    postID: item.blogID,
                    postTitle: item.blogTitle,
                    instagramCode: item.instagramCode,
                    instagramURL: item.instagramLink(in: archive.posts)
                )
            }
            selection = ViewerSelection(id: photo.id)
        } label: {
            Rectangle()
                .fill(Theme.card)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    CachedImage(
                        url: photo.thumbnailURL ?? photo.url,
                        fallbackURL: photo.thumbnailURL == nil ? nil : photo.url,
                        maxPixel: 640,
                        contentMode: .fill
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .topTrailing) {
                    if effectiveSource == .all, !photo.isBlog {
                        Text("IG")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
                .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo.alt)
        .accessibilityHint("點一下以全螢幕檢視")
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

    private func openPending() {
        if let postID = pendingPostID {
            pendingPostID = nil
            path.append(PostRoute(id: postID))
        }
        if let code = pendingInstagramCode {
            pendingInstagramCode = nil
            archive.requestOpen(code: code)
        }
    }

    private static func display(_ day: String) -> String {
        day.replacingOccurrences(of: "-", with: ".")
    }
}

private extension MixedGalleryPhoto {
    var blogID: String? {
        if case .blog(let postID, _) = kind { return postID }
        return nil
    }

    var blogTitle: String? {
        if case .blog(_, let title) = kind { return title }
        return nil
    }

    var instagramCode: String? {
        if case .instagram(let code, _) = kind { return code }
        return nil
    }

    func instagramLink(in posts: [InstagramPost]) -> URL? {
        guard case .instagram(let code, let slideIndex) = kind else { return nil }
        if let post = posts.first(where: { $0.code == code }) {
            return post.instagramURL(slidePosition: slideIndex + 1)
        }
        return InstagramLink.postURL(permalink: nil, code: code)
    }
}

private struct ViewerSelection: Identifiable {
    var id: String
}
