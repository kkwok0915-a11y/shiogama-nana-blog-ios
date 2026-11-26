import SwiftUI

struct InstagramDetailView: View {
    let code: String

    @Environment(InstagramArchive.self) private var archive
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0
    @State private var presented: PresentedPhoto?
    @State private var attemptedCode: String?

    var body: some View {
        Group {
            if let post = archive.post(code: code) {
                detail(for: post)
            } else if attemptedCode != code {
                ProgressView("載入貼文…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("找不到這則貼文", systemImage: "camera")
                } description: {
                    Text("它不在上次儲存的清單裡。回到列表後下拉更新。")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        .task(id: code) {
            await archive.open(code: code)
            attemptedCode = code
        }
        .onChange(of: code) { _, _ in
            page = 0
        }
        .onChange(of: archive.post(code: code)?.slides.count ?? 0) { _, _ in
            clampPage()
        }
    }

    private var title: String {
        let day = archive.post(code: code)?.dayLabel ?? ""
        return day.isEmpty ? "Instagram" : day
    }

    private func detail(for post: InstagramPost) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if post.slides.isEmpty {
                    emptySlides
                } else {
                    InstagramCarousel(post: post, page: $page) { photo in
                        presented = photo
                    }
                }

                if !post.dateLabel.isEmpty {
                    Text(post.dateLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel(post.dateLabel)
                }

                if let caption = post.captionText {
                    Text(caption)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if let url = post.instagramURL {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera")
                            Text("在 Instagram 開啟")
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
                    .accessibilityHint("在 Safari 開啟這則 Instagram")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            await archive.open(code: code)
        }
        .fullScreenCover(item: $presented) { photo in
            zoomViewer(photo, in: post)
        }
    }

    private func zoomViewer(_ photo: PresentedPhoto, in post: InstagramPost) -> some View {
        let photos = viewerPhotos(for: post)
        return PhotoViewer(
            photos: photos.isEmpty ? [photo] : photos,
            initialID: photo.id,
            onClose: { presented = nil },
            onOpenPost: nil
        )
    }

    private var emptySlides: some View {
        Text("這一則沒有存檔。")
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func viewerPhotos(for post: InstagramPost) -> [PresentedPhoto] {
        post.slides.enumerated().compactMap { index, slide in
            guard let photo = slide.photo, let url = photo.url else { return nil }
            return PresentedPhoto(id: "\(post.code)#\(index)", url: url, alt: post.photoAlt)
        }
    }

    private func clampPage() {
        let count = archive.post(code: code)?.slides.count ?? 0
        if count == 0 {
            if page != 0 { page = 0 }
        } else if page >= count {
            page = count - 1
        } else if page < 0 {
            page = 0
        }
    }
}

private struct InstagramCarousel: View {
    let post: InstagramPost
    @Binding var page: Int
    var onZoom: (PresentedPhoto) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        Color.clear
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    TabView(selection: $page) {
                        ForEach(Array(post.slides.enumerated()), id: \.offset) { index, slide in
                            slidePage(slide, index: index, size: proxy.size)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: post.slides.count > 1 ? .always : .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("貼文照片")
    }

    @ViewBuilder
    private func slidePage(_ slide: InstagramSlide, index: Int, size: CGSize) -> some View {
        Group {
            if let photo = slide.photo, let url = photo.url {
                CachedImage(
                    url: url,
                    previewURL: photo.thumbnailURL,
                    maxPixel: 2048,
                    contentMode: .fit,
                    placeholderAspect: photo.aspectRatio.map { CGFloat($0) }
                )
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    onZoom(PresentedPhoto(id: "\(post.code)#\(index)", url: url, alt: post.photoAlt))
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("放大照片")
                .accessibilityHint("點一下以全螢幕檢視")
            } else {
                placeholder(for: slide, index: index)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第 \(index + 1) 張，共 \(post.slides.count) 張")
    }

    private func placeholder(for slide: InstagramSlide, index: Int) -> some View {
        VStack(spacing: 14) {
            Image(systemName: slide.isVideo ? "video" : "photo")
                .font(.largeTitle)
                .foregroundStyle(Theme.inkSoft)
            Text(message(for: slide))
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            if let url = post.instagramURL(slidePosition: index + 1) {
                Button {
                    _ = openURL(url)
                } label: {
                    Text("在 Instagram 觀看")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("在 Safari 開啟這一張")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(for slide: InstagramSlide) -> String {
        if slide.isVideo {
            return "這一張是影片，無法存檔。"
        }
        return "這一張未能存檔。"
    }
}
