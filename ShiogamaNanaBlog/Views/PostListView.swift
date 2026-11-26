import SwiftUI

struct PostListView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredPosts: [Post] {
        library.posts.filter { $0.matchesTitle(trimmedQuery) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                content
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("塩釜菜那")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋中文或日文標題")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .navigationDestination(for: PostRoute.self) { route in
                PostDetailView(postID: route.id)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let bannerText = library.bannerText {
                    Text(bannerText)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                        .accessibilityLabel(bannerText)
                }
            }
        }
        .tint(Theme.accent)
        .task { await library.bootstrap() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("部落格中文翻譯")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
            if !library.posts.isEmpty {
                Text(trimmedQuery.isEmpty ? "\(library.posts.count) 篇，由新到舊" : "找到 \(filteredPosts.count) 篇")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if library.isLoadingInitial && library.posts.isEmpty {
            ProgressView("載入文章…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.posts.isEmpty {
            unavailableScroll {
                if library.loadFailed {
                    ContentUnavailableView {
                        Label("無法載入", systemImage: "wifi.slash")
                    } description: {
                        Text("連不上部落格。連線後再試一次；成功讀過的文章會留在這支手機上。")
                    } actions: {
                        Button("再試一次") {
                            Task { await library.refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("還沒有文章", systemImage: "doc.text")
                    } description: {
                        Text("下拉可以再檢查一次。")
                    }
                }
            }
        } else if filteredPosts.isEmpty {
            unavailableScroll {
                ContentUnavailableView {
                    Label("找不到文章", systemImage: "magnifyingglass")
                } description: {
                    Text("沒有標題符合「\(trimmedQuery)」。")
                }
            }
        } else {
            list
        }
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

    private var list: some View {
        List {
            ForEach(filteredPosts) { post in
                NavigationLink(value: PostRoute(id: post.id)) {
                    PostRow(post: post)
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.16), lineWidth: 1)
                        }
                }
                .navigationLinkIndicatorVisibility(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .accessibilityHint("點一下閱讀全文")
            }

            if trimmedQuery.isEmpty, let updated = library.lastUpdatedText {
                Text("更新於 \(updated)")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await library.refresh() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PostRow: View {
    let post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                if !post.dateLabel.isEmpty {
                    Text(post.dateLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text(post.displayTitleZh)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let titleJp = post.displayTitleJp {
                    Text(titleJp)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if post.imageCount > 0 {
                    Text("\(post.imageCount) 張照片")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let coverURL = post.coverURL {
            CachedImage(url: coverURL, maxPixel: 640, contentMode: .fill)
                .frame(width: 84, height: 112)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.accent.opacity(0.14))
                .frame(width: 84, height: 112)
                .overlay {
                    Text("菜")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityHidden(true)
        }
    }
}
