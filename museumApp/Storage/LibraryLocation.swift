import Foundation

/// Remembers which folder you chose as your library across launches, using a
/// security-scoped bookmark so the sandbox keeps allowing access.
enum LibraryLocation {
    private static let key = "libraryFolderBookmark"

    #if os(macOS)
    private static let creationOptions: URL.BookmarkCreationOptions = .withSecurityScope
    private static let resolutionOptions: URL.BookmarkResolutionOptions = .withSecurityScope
    #else
    private static let creationOptions: URL.BookmarkCreationOptions = []
    private static let resolutionOptions: URL.BookmarkResolutionOptions = []
    #endif

    /// Call while access to `url` is active (e.g. right after the folder picker returns it).
    static func remember(_ url: URL) throws {
        let data = try url.bookmarkData(options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// The remembered folder, if there is one and it still resolves.
    static func restore() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale, url.startAccessingSecurityScopedResource() {
            try? remember(url)
            url.stopAccessingSecurityScopedResource()
        }
        return url
    }
}
