import SwiftUI

enum RootTab: Hashable {
    case posts
    case photos
    case instagram
}

@main
struct ShiogamaNanaBlogApp: App {
    @State private var library = LibraryModel()
    @State private var instagram = InstagramArchive()
    @State private var tab = RootTab.posts

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                PostListView()
                    .tabItem {
                        Label("文章", systemImage: "doc.text")
                    }
                    .tag(RootTab.posts)
                GalleryView()
                    .tabItem {
                        Label("照片", systemImage: "photo.on.rectangle.angled")
                    }
                    .tag(RootTab.photos)
                InstagramView()
                    .tabItem {
                        Label("Instagram", systemImage: "camera")
                    }
                    .tag(RootTab.instagram)
            }
            .tint(Theme.accent)
            .environment(library)
            .environment(instagram)
            .onChange(of: instagram.openRequest) { _, code in
                if code != nil {
                    tab = .instagram
                }
            }
            .task { await library.bootstrap() }
            .task { await instagram.bootstrap() }
        }
    }
}
