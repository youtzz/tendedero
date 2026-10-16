import AppKit

/// CleanShot X, from the clipboard. Every capture is copied as one
/// pasteboard item holding both the picture and a file URL into CleanShot's
/// own media folder, saved or not. Tendedero normally skips anything with a
/// file URL, so this opt-in exception accepts exactly that shape: a capture
/// hangs the instant it is taken, whether or not it was saved afterwards.
enum CleanShotCapture {
    private static let enabledKey = "cleanShotClipboardEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Where CleanShot keeps every capture, saved or not.
    static let mediaFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CleanShot/media", isDirectory: true)

    /// One item holding the picture and a URL that points inside CleanShot's
    /// media folder. Finder copies (no image data) and other apps' formats do
    /// not match.
    static func matches(_ items: [NSPasteboardItem]) -> Bool {
        guard items.count == 1, let item = items.first,
              item.types.contains(.png) || item.types.contains(.tiff),
              let raw = item.string(forType: .fileURL),
              let url = URL(string: raw), url.isFileURL
        else { return false }
        return url.standardizedFileURL.path.hasPrefix(mediaFolder.standardizedFileURL.path + "/")
    }
}
