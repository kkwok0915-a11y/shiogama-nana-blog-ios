import Foundation

struct PhotoDetailBatch: Sendable {
    var posts: [Post]
    var failureCount: Int
}

/// Loads post JSON a few requests at a time. The list endpoint sometimes
/// omits photo blocks; the gallery fills those in from each post.
enum PhotoDetailLoader {
    static let defaultLimit = 4

    static func fetch(ids: [String], limit: Int = defaultLimit) async -> PhotoDetailBatch {
        let results = await LimitedTask.collect(count: ids.count, limit: limit) { index in
            try await BlogAPI.fetchPost(id: ids[index])
        }
        var posts: [Post] = []
        var failureCount = 0
        for result in results {
            switch result {
            case .success(let post):
                posts.append(post)
            case .failure:
                failureCount += 1
            case nil:
                break
            }
        }
        return PhotoDetailBatch(posts: posts, failureCount: failureCount)
    }
}

/// Runs `count` operations with at most `limit` of them in flight.
enum LimitedTask {
    static func collect<T: Sendable>(
        count: Int,
        limit: Int,
        _ operation: @escaping @Sendable (Int) async throws -> T
    ) async -> [Result<T, Error>?] {
        var results = Array<Result<T, Error>?>(repeating: nil, count: count)
        guard count > 0 else { return results }
        let width = max(1, limit)
        await withTaskGroup(of: (Int, Result<T, Error>?).self) { group in
            var next = 0
            func schedule() {
                guard !Task.isCancelled, next < count else { return }
                let index = next
                next += 1
                group.addTask {
                    do {
                        let value = try await operation(index)
                        return (index, .success(value))
                    } catch is CancellationError {
                        return (index, nil)
                    } catch let error as URLError where error.code == .cancelled {
                        return (index, nil)
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for _ in 0..<min(width, count) {
                schedule()
            }
            for await (index, result) in group {
                if results.indices.contains(index) {
                    results[index] = result
                }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                schedule()
            }
        }
        return results
    }
}
