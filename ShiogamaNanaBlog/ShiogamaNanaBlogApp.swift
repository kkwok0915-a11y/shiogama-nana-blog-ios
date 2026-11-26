import SwiftUI

@main
struct ShiogamaNanaBlogApp: App {
    @State private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            PostListView()
                .environment(library)
        }
    }
}
