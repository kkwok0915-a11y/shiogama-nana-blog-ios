import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum BlogAPIError: Error, Sendable {
    case badURL
    case badStatus(Int)
    case badResponse
    case notFound
    case badID
}

/// Reads the public JSON API only. There is no API key and no direct database access.
enum BlogAPI {
    private static let redirectLock = RedirectLock()

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration, delegate: redirectLock, delegateQueue: nil)
    }()

    static func fetchPosts() async throws -> [Post] {
        let data = try await fetchData(from: BlogSite.postsURL)
        return try await decodeOffMain(data)
    }

    static func fetchPost(id: String) async throws -> Post {
        guard let url = BlogSite.postURL(id: id) else { throw BlogAPIError.badID }
        let data = try await fetchData(from: url)
        let posts = try await decodeOffMain(data)
        guard let post = posts.first(where: { $0.id == id }) else {
            throw BlogAPIError.notFound
        }
        return post
    }

    /// JSON work is detached from the caller's actor. `LibraryModel` is on the
    /// main actor, and pull-to-refresh awaits this fetch.
    static func decodeOffMain(_ data: Data) async throws -> [Post] {
        try await Task.detached(priority: .userInitiated) {
            try decodePosts(from: data)
        }.value
    }

    static func decodePosts(from data: Data) throws -> [Post] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw BlogAPIError.badResponse
        }
        let items: [Any]
        if let array = json as? [Any] {
            items = array
        } else if let object = json as? [String: Any], object["id"] != nil {
            items = [object]
        } else {
            throw BlogAPIError.badResponse
        }

        if items.isEmpty { return [] }

        let decoder = JSONDecoder()
        var posts: [Post] = []
        for item in items {
            guard JSONSerialization.isValidJSONObject(item),
                  let itemData = try? JSONSerialization.data(withJSONObject: item),
                  let post = try? decoder.decode(Post.self, from: itemData),
                  let normalized = post.normalized()
            else { continue }
            posts.append(normalized)
        }
        if posts.isEmpty { throw BlogAPIError.badResponse }
        return PostSorting.newestFirst(posts)
    }

    private static func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ShiogamaNanaBlog/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BlogAPIError.badResponse }
        guard let finalURL = http.url, BlogSite.allows(finalURL) else { throw BlogAPIError.badResponse }
        if http.statusCode == 404 { throw BlogAPIError.notFound }
        guard (200..<300).contains(http.statusCode) else { throw BlogAPIError.badStatus(http.statusCode) }
        return data
    }
}

/// Refuses redirects that leave the public blog host.
private final class RedirectLock: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == BlogSite.host,
              url.user == nil
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
