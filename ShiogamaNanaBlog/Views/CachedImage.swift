import SwiftUI
import UIKit

struct CachedImage: View {
    let url: URL?
    /// Tried only when `url` cannot be decoded. Grid thumbnails pass the
    /// full-size JPEG here and the smaller WebP as `url`.
    var fallbackURL: URL? = nil
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
        .task(id: "\(url?.absoluteString ?? "")|\(fallbackURL?.absoluteString ?? "")") {
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
            } else if url != nil || fallbackURL != nil {
                ProgressView()
            }
        }
    }

    private func load() async {
        let primary = url
        let secondary = fallbackURL
        guard primary != nil || secondary != nil else {
            image = nil
            failed = true
            return
        }
        failed = false
        if let primary {
            let loaded = await ImageStore.shared.image(for: primary, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            if let loaded {
                image = loaded
                failed = false
                return
            }
        }
        if let secondary, secondary != primary {
            let loaded = await ImageStore.shared.image(for: secondary, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            image = loaded
            failed = loaded == nil
            return
        }
        image = nil
        failed = true
    }
}
