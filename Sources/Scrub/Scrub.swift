import AppKit
import Kit

@main
enum Main {
    @MainActor static func main() { Kit.run { Scrub() } }
}

/// Strips tracking parameters (utm_source, fbclid, si…) from links as they're copied, so what you paste is clean.
@MainActor
final class Scrub {
    private static let pausedKey = "paused"
    private static let cleanedKey = "cleanedCount"
    // ponytail: macOS has no clipboard-changed notification, so poll the change count (no pasteboard read, no prompt).
    private static let pollInterval: TimeInterval = 0.5

    private lazy var item = MenuBarItem(name: "Scrub", symbol: "link", click: .menu { [unowned self] in menu() })
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastCleaned: String?

    private var isPaused: Bool {
        get { UserDefaults.standard.bool(forKey: Self.pausedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.pausedKey); updateIcon() }
    }

    init() {
        updateIcon()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func updateIcon() {
        item.statusItem.button?.appearsDisabled = isPaused
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !isPaused else { return }
        Task {
            // Detecting a URL doesn't trigger macOS's paste prompt; reading the text does, so read only when it's a link.
            guard let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL]),
                  patterns.contains(\.probableWebURL),
                  pasteboard.changeCount == lastChangeCount,
                  let text = pasteboard.string(forType: .string),
                  let cleaned = LinkCleaner.clean(text) else { return }
            pasteboard.clearContents()
            pasteboard.setString(cleaned, forType: .string)
            lastChangeCount = pasteboard.changeCount // our own write isn't a new copy
            lastCleaned = cleaned
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: Self.cleanedKey) + 1, forKey: Self.cleanedKey)
            item.flash("sparkles")
        }
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        let count = UserDefaults.standard.integer(forKey: Self.cleanedKey)
        menu.addItem(.label(count == 1 ? "1 link cleaned" : "\(count) links cleaned"))
        if let lastCleaned {
            menu.addItem(.label("Last: \(lastCleaned.count > 50 ? String(lastCleaned.prefix(49)) + "…" : lastCleaned)"))
        }
        if NSPasteboard.general.accessBehavior == .alwaysDeny {
            menu.addItem(NSMenuItem("Allow Pasteboard Access…", symbol: "exclamationmark.triangle") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!)
            })
        }
        menu.addItem(.separator())
        let pause = NSMenuItem("Pause") { [unowned self] in isPaused.toggle() }
        pause.state = isPaused ? .on : .off
        menu.addItem(pause)
        return menu
    }
}

enum LinkCleaner {
    /// Tracking parameters on any site.
    private static let everywhere: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "li_fat_id",
        "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "igshid", "oly_anon_id", "oly_enc_id", "vero_id", "_ga", "_gl",
        "ref_src", "ref_url",
    ]
    private static let prefixes = ["utm_", "pk_", "mtm_"]
    /// Parameters that only track on these sites; elsewhere they may mean something.
    private static let perSite: [String: Set<String>] = [
        "youtube.com": ["si", "feature", "pp"],
        "youtu.be": ["si", "feature"],
        "spotify.com": ["si", "context"],
        "x.com": ["s", "t"],
        "twitter.com": ["s", "t"],
        "instagram.com": ["igsh", "img_index"],
        "linkedin.com": ["trk", "trackingId", "lipi", "refId", "rcm"],
        "tiktok.com": ["is_from_webapp", "sender_device", "_r", "_t"],
    ]

    /// The link without tracking parameters, or nil when the text isn't one link or had nothing to remove.
    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              var components = URLComponents(string: trimmed),
              ["http", "https"].contains(components.scheme?.lowercased()),
              let host = components.host?.lowercased(),
              let items = components.percentEncodedQueryItems else { return nil }
        let siteParameters = perSite.first { host == $0.key || host.hasSuffix("." + $0.key) }?.value ?? []
        let kept = items.filter { item in
            let name = item.name.lowercased()
            return !everywhere.contains(name) && !siteParameters.contains(item.name) && !prefixes.contains { name.hasPrefix($0) }
        }
        guard kept.count < items.count else { return nil }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.string
    }
}
