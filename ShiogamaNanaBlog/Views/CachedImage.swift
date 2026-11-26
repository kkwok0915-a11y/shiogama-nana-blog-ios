import SwiftUI
import UIKit

struct CachedImage: View {
    let url: URL?
    /// Tried only when `url` cannot be decoded. Grid thumbnails pass the
    /// full-size JPEG here and the smaller WebP as `url`.
    var fallbackURL: URL? = nil
    /// Blurred stand-in for a full-size photo, usually the `-sm.webp` thumbnail.
    var previewURL: URL? = nil
    var maxPixel: CGFloat = 1600
    var contentMode: ContentMode = .fit
    var placeholderAspect: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var preview: UIImage?
    @State private var failed = false
    /// 0 while the sharp photo is hidden, 1 after it has faded in.
    @State private var cover: CGFloat = 0

    var body: some View {
        framed
            .accessibilityHidden(true)
            .accessibilityIgnoresInvertColors(image != nil)
            .task(id: "\(url?.absoluteString ?? "")|\(fallbackURL?.absoluteString ?? "")|\(previewURL?.absoluteString ?? "")") {
                await load()
            }
    }

    private var stack: some View {
        ZStack {
            backdrop
                .opacity(image == nil ? 1 : Double(1 - cover))
            if let image {
                photo(image)
                    .opacity(reduceMotion ? 1 : cover)
            }
        }
    }

    @ViewBuilder
    private var framed: some View {
        if contentMode == .fit, let ratio = placeholderAspect {
            stack.aspectRatio(ratio, contentMode: .fit)
        } else if contentMode == .fit, image == nil, preview == nil {
            stack.aspectRatio(0.75, contentMode: .fit)
        } else {
            stack
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if let preview {
            photo(preview)
                .blur(radius: reduceMotion ? 0 : 14)
        } else if failed {
            ZStack {
                Rectangle().fill(Theme.background)
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(Theme.inkSoft)
            }
        } else if url != nil || fallbackURL != nil || previewURL != nil {
            Shimmer()
        } else {
            Rectangle().fill(Theme.background)
        }
    }

    private func photo(_ uiImage: UIImage) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: contentMode)
    }

    private func load() async {
        cover = 0
        preview = nil
        image = nil
        failed = false
        if let previewURL, previewURL != url {
            let loaded = await ImageStore.shared.image(for: previewURL, maxPixel: 360)
            guard !Task.isCancelled else { return }
            preview = loaded
        }
        if let primary = url {
            if let loaded = await ImageStore.shared.image(for: primary, maxPixel: maxPixel) {
                guard !Task.isCancelled else { return }
                show(loaded)
                return
            }
            guard !Task.isCancelled else { return }
        }
        if let secondary = fallbackURL, secondary != url {
            if let loaded = await ImageStore.shared.image(for: secondary, maxPixel: maxPixel) {
                guard !Task.isCancelled else { return }
                show(loaded)
                return
            }
            guard !Task.isCancelled else { return }
        }
        if url == nil && fallbackURL == nil {
            failed = true
            return
        }
        image = nil
        failed = true
    }

    private func show(_ loaded: UIImage) {
        image = loaded
        failed = false
        if reduceMotion {
            cover = 1
        } else {
            withAnimation(.easeOut(duration: 0.45)) {
                cover = 1
            }
        }
    }
}
