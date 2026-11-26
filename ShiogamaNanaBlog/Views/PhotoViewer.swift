import SwiftUI
import UIKit

struct PresentedPhoto: Identifiable {
    var id: String
    var url: URL
    var alt: String
}

struct PhotoViewer: View {
    let photo: PresentedPhoto
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var failed = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .accessibilityLabel(photo.alt)
                        .accessibilityHint("雙指開合可以放大，往下拖可以關閉")
                        .accessibilityAddTraits(.isImage)
                        .accessibilityZoomAction { action in
                            if action.direction == .zoomIn {
                                setScale(min(scale + 1, 5))
                            } else if action.direction == .zoomOut {
                                setScale(max(scale - 1, 1))
                            }
                        }
                        .gesture(magnify)
                        .simultaneousGesture(drag)
                        .onTapGesture(count: 2) {
                            setScale(scale > 1 ? 1 : 2.5)
                        }
                } else if failed {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                        Text("照片無法顯示")
                            .font(.body)
                    }
                    .foregroundStyle(.white)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIgnoresInvertColors(true)

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel("關閉")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityAction(.escape, onClose)
        .task(id: photo.url) {
            let loaded = await ImageStore.shared.image(for: photo.url, maxPixel: 2048)
            guard !Task.isCancelled else { return }
            image = loaded
            failed = loaded == nil
        }
    }

    private var backdropOpacity: Double {
        guard scale <= 1.01 else { return 1 }
        return max(0.45, 1 - Double(abs(offset.height) / 500))
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if scale > 1 {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                } else {
                    offset = CGSize(width: 0, height: value.translation.height)
                }
            }
            .onEnded { value in
                if scale <= 1 {
                    if abs(value.translation.height) > 140 {
                        onClose()
                    } else {
                        settleOffset(.zero)
                    }
                } else {
                    lastOffset = offset
                }
            }
    }

    private func setScale(_ newScale: CGFloat) {
        let clamped = min(max(newScale, 1), 5)
        let apply = {
            scale = clamped
            lastScale = clamped
            if clamped <= 1 {
                offset = .zero
                lastOffset = .zero
            }
        }
        if reduceMotion {
            apply()
        } else {
            withAnimation(.spring(duration: 0.25)) { apply() }
        }
    }

    private func settleOffset(_ target: CGSize) {
        if reduceMotion {
            offset = target
            lastOffset = target
        } else {
            withAnimation(.spring(duration: 0.25)) {
                offset = target
                lastOffset = target
            }
        }
    }
}
