import Photos
import SwiftUI
import UIKit

struct PresentedPhoto: Identifiable, Hashable {
    var id: String
    var url: URL
    var alt: String
    var postID: String? = nil
    var postTitle: String? = nil
    var instagramCode: String? = nil
    /// Permalink for this slide, including `img_index` when it is an Instagram photo.
    var instagramURL: URL? = nil
}

struct PhotoViewer: View {
    private let photos: [PresentedPhoto]
    private let onClose: () -> Void
    private let onOpenPost: ((String) -> Void)?
    private let onOpenInstagram: ((String) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index: Int
    @State private var images: [URL: UIImage] = [:]
    @State private var failed: Set<URL> = []
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @State private var lastZoomOffset: CGSize = .zero
    @State private var drag: CGSize = .zero
    @State private var pageWidth: CGFloat = 0
    @State private var paging = false
    @State private var pageToken = 0
    @State private var isSaving = false
    @State private var saveMessage: String?

    init(photo: PresentedPhoto, onClose: @escaping () -> Void) {
        self.init(photos: [photo], initialID: photo.id, onClose: onClose, onOpenPost: nil)
    }

    init(
        photos: [PresentedPhoto],
        initialID: String,
        onClose: @escaping () -> Void,
        onOpenPost: ((String) -> Void)?,
        onOpenInstagram: ((String) -> Void)? = nil
    ) {
        self.photos = photos
        self.onClose = onClose
        self.onOpenPost = onOpenPost
        self.onOpenInstagram = onOpenInstagram
        let start = photos.firstIndex(where: { $0.id == initialID }) ?? 0
        _index = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)
                ZStack {
                    if showsNeighbor(-1) {
                        page(at: index - 1, width: width, height: height)
                            .offset(x: -width + drag.width)
                    }
                    page(at: index, width: width, height: height)
                        .scaleEffect(scale)
                        .offset(currentOffset)
                    if showsNeighbor(1) {
                        page(at: index + 1, width: width, height: height)
                            .offset(x: width + drag.width)
                    }
                }
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .gesture(magnify)
                .simultaneousGesture(pagingDrag)
                .onTapGesture(count: 2) {
                    setScale(scale > 1 ? 1 : 2.5)
                }
                .onAppear { pageWidth = width }
                .onChange(of: width) { _, newValue in
                    pageWidth = newValue
                }
                .accessibilityElement(children: .contain)
                .accessibilityAdjustableAction { direction in
                    if direction == .increment {
                        turnPage(1)
                    } else if direction == .decrement {
                        turnPage(-1)
                    }
                }
            }

            chrome
        }
        .preferredColorScheme(.dark)
        .accessibilityAction(.escape, onClose)
        .task(id: index) {
            await load(index)
            await load(index - 1)
            await load(index + 1)
            pruneImages()
        }
        .task(id: saveMessage) {
            guard saveMessage != nil else { return }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            saveMessage = nil
        }
    }

    private var currentPhoto: PresentedPhoto? {
        guard photos.indices.contains(index) else { return nil }
        return photos[index]
    }

    private var currentOffset: CGSize {
        if scale > 1.01 {
            return zoomOffset
        }
        return drag
    }

    private var backdropOpacity: Double {
        guard scale <= 1.01 else { return 1 }
        return max(0.45, 1 - Double(abs(drag.height) / 500))
    }

    private func showsNeighbor(_ delta: Int) -> Bool {
        guard scale <= 1.01, photos.indices.contains(index + delta) else { return false }
        if paging { return true }
        return delta < 0 ? drag.width > 0 : drag.width < 0
    }

    @ViewBuilder
    private func page(at offset: Int, width: CGFloat, height: CGFloat) -> some View {
        let photo = photos.indices.contains(offset) ? photos[offset] : nil
        Group {
            if let photo, let image = images[photo.url] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(photo.alt)
                    .accessibilityHint(accessibilityHint)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityZoomAction { action in
                        guard offset == index else { return }
                        if action.direction == .zoomIn {
                            setScale(min(scale + 1, 5))
                        } else if action.direction == .zoomOut {
                            setScale(max(scale - 1, 1))
                        }
                    }
            } else if let photo, failed.contains(photo.url) {
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
        .frame(width: width, height: height)
        .accessibilityHidden(offset != index)
        .accessibilityIgnoresInvertColors(true)
    }

    private var accessibilityHint: String {
        if photos.count > 1 {
            return "左右滑動可以換照片，雙指開合可以放大，往下拖可以關閉"
        }
        return "雙指開合可以放大，往下拖可以關閉"
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                Button(action: saveCurrentPhoto) {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.body.weight(.bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
                }
                .disabled(isSaving || currentPhoto == nil)
                .accessibilityLabel("儲存到照片")

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
                .allowsHitTesting(false)

            bottomBar
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let saveMessage {
                Text(saveMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .accessibilityLabel(saveMessage)
            }
            if photos.count > 1 {
                Text("\(index + 1) / \(photos.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .monospacedDigit()
                    .allowsHitTesting(false)
                    .accessibilityLabel("第 \(index + 1) 張，共 \(photos.count) 張")
            }
            if let photo = currentPhoto, let postID = photo.postID, let onOpenPost {
                Button {
                    onOpenPost(postID)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("查看文章")
                                .font(.subheadline.weight(.semibold))
                            if let title = photo.postTitle, !title.isEmpty {
                                Text(title)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityHint("開啟這張照片的文章")
            }
            if let photo = currentPhoto, photo.instagramCode != nil || photo.instagramURL != nil {
                HStack(spacing: 8) {
                    if let code = photo.instagramCode, let onOpenInstagram {
                        Button {
                            onOpenInstagram(code)
                        } label: {
                            Text("查看貼文")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .accessibilityHint("開啟這張照片的 Instagram 貼文")
                    }
                    if let url = photo.instagramURL {
                        Link(destination: url) {
                            Text("Instagram ↗")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .accessibilityHint("在 Safari 開啟這一張")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    zoomOffset = .zero
                    lastZoomOffset = .zero
                }
            }
    }

    private var pagingDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !paging else { return }
                if scale > 1.01 {
                    zoomOffset = CGSize(
                        width: lastZoomOffset.width + value.translation.width,
                        height: lastZoomOffset.height + value.translation.height
                    )
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                if photos.count > 1, abs(dx) > abs(dy) {
                    drag = CGSize(width: resisted(dx), height: 0)
                } else {
                    drag = CGSize(width: 0, height: dy)
                }
            }
            .onEnded { value in
                guard !paging else { return }
                if scale > 1.01 {
                    lastZoomOffset = zoomOffset
                    drag = .zero
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                let predicted = value.predictedEndTranslation.width
                let pagingSwipe = photos.count > 1
                    && abs(dx) > abs(dy)
                    && (abs(dx) > 64 || abs(predicted) > 180)
                if pagingSwipe {
                    turnPage(dx < 0 ? 1 : -1)
                } else if abs(dy) > 140, abs(dy) >= abs(dx) {
                    onClose()
                } else {
                    settleDrag()
                }
            }
    }

    private func resisted(_ dx: CGFloat) -> CGFloat {
        let atStart = index == 0 && dx > 0
        let atEnd = index == photos.count - 1 && dx < 0
        if atStart || atEnd { return dx * 0.3 }
        return dx
    }

    private func turnPage(_ delta: Int) {
        let target = index + delta
        guard photos.indices.contains(target) else {
            settleDrag()
            return
        }
        if reduceMotion || pageWidth < 20 {
            index = target
            drag = .zero
            resetZoom()
            return
        }
        pageToken += 1
        let token = pageToken
        let travel = pageWidth
        paging = true
        withAnimation(.easeOut(duration: 0.22)) {
            drag = CGSize(width: delta > 0 ? -travel : travel, height: 0)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(230))
            guard token == pageToken else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                index = target
                drag = .zero
                resetZoom()
                paging = false
            }
        }
    }

    private func setScale(_ newScale: CGFloat) {
        let clamped = min(max(newScale, 1), 5)
        let apply = {
            scale = clamped
            lastScale = clamped
            if clamped <= 1 {
                zoomOffset = .zero
                lastZoomOffset = .zero
            }
        }
        if reduceMotion {
            apply()
        } else {
            withAnimation(.spring(duration: 0.25)) { apply() }
        }
    }

    private func settleDrag() {
        if reduceMotion {
            drag = .zero
        } else {
            withAnimation(.spring(duration: 0.25)) {
                drag = .zero
            }
        }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        zoomOffset = .zero
        lastZoomOffset = .zero
    }

    private func load(_ offset: Int) async {
        guard photos.indices.contains(offset) else { return }
        let url = photos[offset].url
        if images[url] != nil { return }
        let loaded = await ImageStore.shared.image(for: url, maxPixel: 2048)
        guard !Task.isCancelled else { return }
        if let loaded {
            images[url] = loaded
            failed.remove(url)
        } else if images[url] == nil {
            failed.insert(url)
        }
    }

    private func pruneImages() {
        guard !photos.isEmpty else { return }
        let lower = max(0, index - 3)
        let upper = min(photos.count, index + 4)
        let keep = Set(photos[lower..<upper].map(\.url))
        images = images.filter { keep.contains($0.key) }
    }

    private func saveCurrentPhoto() {
        guard !isSaving, let photo = currentPhoto else { return }
        isSaving = true
        saveMessage = nil
        let url = photo.url
        Task {
            let data = await ImageStore.shared.data(for: url)
            let outcome: PhotoLibrarySave.Outcome
            if let data {
                outcome = await PhotoLibrarySave.saveImageData(data)
            } else {
                outcome = .failed
            }
            isSaving = false
            switch outcome {
            case .saved:
                saveMessage = "已儲存到照片"
            case .denied:
                saveMessage = "沒有加入照片的權限"
            case .failed:
                saveMessage = "無法儲存這張照片"
            }
        }
    }
}

private enum PhotoLibrarySave {
    enum Outcome: Sendable {
        case saved
        case denied
        case failed
    }

    static func saveImageData(_ data: Data) async -> Outcome {
        let status = await addOnlyStatus()
        guard status == .authorized || status == .limited else { return .denied }
        let wrote = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
        return wrote ? .saved : .failed
    }

    private static func addOnlyStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
