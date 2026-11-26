import SwiftUI

struct GalleryView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.colorScheme) private var colorScheme
    @State private var path = NavigationPath()
    @State private var presentedPhotos: [PresentedPhoto] = []
    @State private var selection: ViewerSelection?
    @State private var pendingPostID: String?

    private var photos: [GalleryPhoto] {
        GalleryCatalog.photos(from: library.posts)
    }

    private var sections: [GallerySection] {
        GalleryCatalog.sections(from: library.posts)
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
                .fullScreenCover(item: $selection, onDismiss: openPendingPost) { selection in
                    PhotoViewer(
                        photos: presentedPhotos,
                        initialID: selection.id,
                        onClose: { self.selection = nil },
                        onOpenPost: { postID in
                            pendingPostID = postID
                            self.selection = nil
                        }
                    )
                }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var content: some View {
        if library.isLoadingInitial && library.posts.isEmpty {
            ProgressView("載入照片…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.posts.isEmpty {
            unavailableScroll {
                if library.loadFailed {
                    ContentUnavailableView {
                        Label("無法載入", systemImage: "wifi.slash")
                    } description: {
                        Text("連不上部落格。連線後再試一次；成功讀過的照片會留在這支手機上。")
                    } actions: {
                        Button("再試一次") {
                            Task { await library.refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("還沒有照片", systemImage: "photo")
                    } description: {
                        Text("下拉可以再檢查一次。")
                    }
                }
            }
        } else if photos.isEmpty {
            unavailableScroll {
                if library.isHydratingPhotos {
                    ProgressView("讀取文章中的照片…")
                } else if library.loadFailed || library.photoBannerText != nil {
                    ContentUnavailableView {
                        Label("無法載入照片", systemImage: "wifi.slash")
                    } description: {
                        Text(library.photoBannerText ?? "連不上部落格。連線後再試一次。")
                    } actions: {
                        Button("再試一次") {
                            Task { await library.refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("還沒有照片", systemImage: "photo")
                    } description: {
                        Text("這些文章裡還沒有照片。下拉可以再檢查一次。")
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
                countLine
                if let banner = library.photoBannerText ?? library.bannerText {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .accessibilityLabel(banner)
                }
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
            .padding(.bottom, 12)
        }
        .refreshable { await library.refresh() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        if library.isHydratingPhotos {
            return "\(photos.count) 張照片，更新中"
        }
        return "\(photos.count) 張照片"
    }

    private func sectionHeader(_ section: GallerySection) -> some View {
        Text(section.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.background)
            .accessibilityAddTraits(.isHeader)
    }

    private func cell(_ photo: GalleryPhoto) -> some View {
        Button {
            presentedPhotos = photos.compactMap { item in
                guard let url = item.url else { return nil }
                return PresentedPhoto(
                    id: item.id,
                    url: url,
                    alt: item.photo.altText,
                    postID: item.postID,
                    postTitle: item.postTitle
                )
            }
            selection = ViewerSelection(id: photo.id)
        } label: {
            Rectangle()
                .fill(Theme.card)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    CachedImage(url: photo.url, maxPixel: 640, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo.photo.altText)
        .accessibilityHint("點一下以全螢幕檢視")
    }

    private func unavailableScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.top, 32)
                .frame(maxWidth: .infinity)
        }
        .refreshable { await library.refresh() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openPendingPost() {
        guard let postID = pendingPostID else { return }
        pendingPostID = nil
        path.append(PostRoute(id: postID))
    }
}

private struct ViewerSelection: Identifiable {
    var id: String
}
