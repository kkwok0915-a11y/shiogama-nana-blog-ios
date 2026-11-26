import SwiftUI

@main
struct ShiogamaNanaBlogApp: App {
    @State private var library = LibraryModel()

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
            }
            .tint(Theme.accent)
            .environment(library)
            .task { await library.bootstrap() }
        }
    }
}
