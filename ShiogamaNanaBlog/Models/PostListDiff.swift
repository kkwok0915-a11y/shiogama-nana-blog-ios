import Foundation

/// Matches a fetched list to the one already on screen by `Post.id`.
///
/// Returns nil when `incoming` has the same ids in the same order and each
/// post compares equal. Callers must leave the stored array untouched in that
/// case so SwiftUI does not rebuild the list or reset its scroll position.
enum PostListDiff {
    static func merging(_ incoming: [Post], into current: [Post]) -> [Post]? {
        if sameList(current, incoming) { return nil }
        if current.isEmpty { return incoming }

        var currentByID: [String: Post] = [:]
        currentByID.reserveCapacity(current.count)
        for post in current where currentByID[post.id] == nil {
            currentByID[post.id] = post
        }
        let merged = incoming.map { post -> Post in
            guard let existing = currentByID[post.id], existing == post else { return post }
            return existing
        }
        if sameList(current, merged) { return nil }
        return merged
    }

    private static func sameList(_ lhs: [Post], _ rhs: [Post]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            if left.id != right.id || left != right { return false }
        }
        return true
    }
}
