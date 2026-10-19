import AppKit

/// What every app in the suite shares: a menu bar app with no Dock icon, built around one `MenuBarItem`.
public enum Kit {
    /// Shown in every About panel.
    public static let credits = "Made by Luis Sejer Oliver. Part of Topside."
    public static let websiteURL = URL(string: "https://luissejer.dk")!

    /// Starts the app. `make` builds the app's one object once launched; it lives until the app quits.
    @MainActor
    public static func run(_ make: @escaping @MainActor () -> AnyObject) {
        let app = NSApplication.shared
        let delegate = Delegate(make: make)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Copies plain text, the way every app in the suite hands something back.
    @MainActor
    public static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Tells VoiceOver what just happened when nothing on screen changes, such as a copy from the menu bar.
    @MainActor
    public static func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}

@MainActor
private final class Delegate: NSObject, NSApplicationDelegate {
    private let make: @MainActor () -> AnyObject
    private var app: AnyObject?

    init(make: @escaping @MainActor () -> AnyObject) {
        self.make = make
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        app = make()
        WhatsNew.showIfPending()
        Updater.shared.checkIfDue()
    }
}
