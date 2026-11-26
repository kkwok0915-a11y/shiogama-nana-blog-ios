import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Memory plus disk cache for photos on the blog host. Disk files are the
/// original bytes; views downsample when they display them.
actor ImageStore {
    static let shared = ImageStore()

    private let directory: URL
    private let session: URLSession
    private var memory: [String: UIImage] = [:]
    private var memoryOrder: [String] = []
    private let memoryLimit = 40

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("BlogArchive/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        session = BlogAPI.session
    }

    static func prefetch(urls: [URL]) {
        var seen = Set<String>()
        let unique = Array(urls.filter { seen.insert($0.absoluteString).inserted }.prefix(200))
        guard !unique.isEmpty else { return }
        let lanes = 4
        let slices: [[URL]] = (0..<lanes).map { lane in
            unique.enumerated().compactMap { index, url in index % lanes == lane ? url : nil }
        }
        Task {
            await withTaskGroup(of: Void.self) { group in
                for slice in slices where !slice.isEmpty {
                    group.addTask {
                        for url in slice {
                            _ = await ImageStore.shared.data(for: url)
                        }
                    }
                }
            }
        }
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)|\(Int(maxPixel.rounded()))"
        if let cached = memory[key] {
            touch(key)
            return cached
        }
        guard let data = await data(for: url) else { return nil }
        if let cached = memory[key] {
            touch(key)
            return cached
        }
        guard let image = await Self.decodedThumbnail(data: data, maxPixel: maxPixel) else { return nil }
        remember(image, key: key)
        return image
    }

    func data(for url: URL) async -> Data? {
        if let cached = await read(url) { return cached }
        return await download(url)
    }

    private func download(_ url: URL) async -> Data? {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == BlogSite.host else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let finalURL = http.url,
                  finalURL.scheme?.lowercased() == "https",
                  finalURL.host?.lowercased() == BlogSite.host,
                  data.count > 32,
                  data.count < 20 * 1024 * 1024
            else { return nil }
            let file = fileURL(for: url)
            let accepted = await Task.detached(priority: .utility) {
                guard Self.isImage(data) else { return false }
                try? data.write(to: file, options: .atomic)
                return true
            }.value
            return accepted ? data : nil
        } catch {
            return nil
        }
    }

    private func read(_ url: URL) async -> Data? {
        let file = fileURL(for: url)
        return await Task.detached(priority: .utility) {
            Self.readImageFile(at: file)
        }.value
    }

    private nonisolated static func readImageFile(at file: URL) -> Data? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        guard isImage(data) else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return data
    }

    /// ImageIO downsampling is CPU-heavy. Keep it off the main actor and off
    /// this actor's serial executor so cache hits are not stuck behind it.
    private nonisolated static func decodedThumbnail(data: Data, maxPixel: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            downsample(data: data, maxPixel: maxPixel)
        }.value
    }

    private func fileURL(for url: URL) -> URL {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("img")
    }

    private func remember(_ image: UIImage, key: String) {
        touch(key)
        memory[key] = image
        while memoryOrder.count > memoryLimit {
            let oldest = memoryOrder.removeFirst()
            memory.removeValue(forKey: oldest)
        }
    }

    private func touch(_ key: String) {
        if let index = memoryOrder.firstIndex(of: key) {
            memoryOrder.remove(at: index)
        }
        memoryOrder.append(key)
    }

    private static func isImage(_ data: Data) -> Bool {
        let options = [kCGImageSourceShouldCache: kCFBooleanFalse] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    private static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: kCFBooleanFalse] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
