import AppKit

/// CleanShot's own tools, reached through its URL scheme: the annotate
/// editor, the pin window, the Quick Access Overlay. Tendedero only hands
/// the file over; everything after that is CleanShot's own UI.
enum CleanShotTools {
    private static let bundleID = "pl.maketheweb.cleanshotx"

    /// Whether CleanShot is installed, before offering its menu.
    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Commands used here: "open-annotate", "pin",
    /// "add-quick-access-overlay". Opening the URL launches CleanShot if it
    /// is not running.
    static func open(_ command: String, file: URL) {
        var components = URLComponents()
        components.scheme = "cleanshot"
        components.host = command
        components.queryItems = [URLQueryItem(name: "filepath", value: file.path)]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
