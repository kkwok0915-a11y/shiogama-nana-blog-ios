import SwiftUI

enum RootTab: Hashable {
    case feed
    case photos
}

@main
struct ShiogamaNanaBlogApp: App {
    @State private var library = LibraryModel()
    @State private var instagram = InstagramArchive()
    @State private var tab = RootTab.feed

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                FeedView()
                    .tabItem {
                        Label("動態", systemImage: "list.bullet")
                    }
                    .tag(RootTab.feed)
                GalleryView()
                    .tabItem {
                        Label("相簿", systemImage: "photo.on.rectangle.angled")
                    }
                    .tag(RootTab.photos)
            }
            .tint(Theme.accent)
            .environment(library)
            .environment(instagram)
            .onChange(of: instagram.openRequest) { _, code in
                if code != nil {
                    tab = .feed
                }
            }
            .task { await library.bootstrap() }
            .task { await instagram.bootstrap() }
        }
    }
}
