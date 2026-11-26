import SwiftUI
import UIKit

struct CachedImage: View {
    let url: URL?
    var maxPixel: CGFloat = 1600
    var contentMode: ContentMode = .fit
    var placeholderAspect: CGFloat? = nil

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if contentMode == .fill {
                placeholder
            } else {
                placeholder
                    .aspectRatio(placeholderAspect ?? 0.75, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
        .accessibilityIgnoresInvertColors(image != nil)
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Theme.background)
            if failed {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(Theme.inkSoft)
            } else if url != nil {
                ProgressView()
            }
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            failed = true
            return
        }
        failed = false
        let loaded = await ImageStore.shared.image(for: url, maxPixel: maxPixel)
        guard !Task.isCancelled else { return }
        image = loaded
        failed = loaded == nil
    }
}
