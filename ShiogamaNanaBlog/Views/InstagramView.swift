import SwiftUI

struct InstagramView: View {
    @Environment(InstagramArchive.self) private var archive
    @Environment(\.colorScheme) private var colorScheme
    @State private var path = NavigationPath()

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Instagram")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
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

    private func openRequestedPost() {
        guard let code = archive.takeOpenRequest() else { return }
        path.append(InstagramRoute(code: code))
    }

    @ViewBuilder
    private var content: some View {
        if archive.isLoadingInitial && archive.posts.isEmpty {
            ProgressView("載入 Instagram…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if archive.posts.isEmpty {
            unavailableScroll {
                if archive.loadFailed {
                    ContentUnavailableView {
                        Label("無法載入", systemImage: "wifi.slash")
                    } description: {
                        Text("連不上 Instagram。連線後再試一次；成功讀過的貼文會留在這支手機上。")
                    } actions: {
                        Button("再試一次") {
                            Task { await archive.refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("還沒有貼文", systemImage: "camera")
                    } description: {
                        Text("下拉可以再檢查一次。")
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
                if let banner = archive.bannerText {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .accessibilityLabel(banner)
                }
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(archive.posts) { post in
                        NavigationLink(value: InstagramRoute(code: post.code)) {
                            tile(post)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label(for: post))
                        .accessibilityHint("點一下查看貼文")
                    }
                }
                if let updated = archive.lastUpdatedText {
                    Text("更新於 \(updated)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(.bottom, 12)
        }
        .refreshable { await archive.refresh() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var countLine: some View {
        Text("\(archive.posts.count) 則貼文")
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .accessibilityLabel("\(archive.posts.count) 則貼文")
    }

    private func tile(_ post: InstagramPost) -> some View {
        Rectangle()
            .fill(Theme.card)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let photo = post.coverPhoto {
                    CachedImage(
                        url: photo.thumbnailURL ?? photo.url,
                        fallbackURL: photo.thumbnailURL == nil ? nil : photo.url,
                        maxPixel: 480,
                        contentMode: .fill
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("IG")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if post.slides.count > 1 {
                    Text("\(post.slides.count)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottom) {
                if !post.dayLabel.isEmpty {
                    Text(post.dayLabel)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .accessibilityHidden(true)
                }
            }
            .clipped()
    }

    private func label(for post: InstagramPost) -> String {
        let date = post.dateLabel.isEmpty ? "日期不明" : post.dateLabel
        if post.slides.count > 1 {
            return "\(date) 的 Instagram 貼文（\(post.slides.count) 張）"
        }
        return "\(date) 的 Instagram 貼文"
    }

    private func unavailableScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.top, 32)
                .frame(maxWidth: .infinity)
        }
        .refreshable { await archive.refresh() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
