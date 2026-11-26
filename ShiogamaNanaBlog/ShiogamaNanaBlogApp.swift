import SwiftUI

@main
struct ShiogamaNanaBlogApp: App {
    @State private var library = LibraryModel()
    @State private var instagram = InstagramArchive()

    var body: some Scene {
        WindowGroup {
            TabView {
                PostListView()
                    .tabItem {
                        Label("文章", systemImage: "doc.text")
                    }
                GalleryView()
                    .tabItem {
                        Label("照片", systemImage: "photo.on.rectangle.angled")
                    }
                InstagramView()
                    .tabItem {
                        Label("Instagram", systemImage: "camera")
                    }
            }
            .tint(Theme.accent)
            .environment(library)
            .environment(instagram)
            .task { await library.bootstrap() }
            .task { await instagram.bootstrap() }
        }
    }
}
