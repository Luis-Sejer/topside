import AppKit
import ApplicationServices
import ScreenCaptureKit

/// Another app's menu bar icon, as Accessibility sees it.
struct MenuBarExtra: Identifiable {
    /// Stable while the app runs: the app plus the icon's place among its own icons.
    let id: String
    let app: NSRunningApplication
    let element: AXUIElement
    /// Accessibility's coordinates: global, with the origin at the top left of the main screen.
    let frame: CGRect
    /// What the icon says (like "W40") or describes itself as, for search and VoiceOver.
    let title: String

    var appName: String { app.localizedName ?? "App" }
}

/// Finding, picturing and clicking other apps' menu bar icons. Since macOS 26 the icons aren't windows other apps
/// can list, so this goes through each app's Accessibility "extras menu bar", as Ice and Bartender do. Needs the
/// Accessibility permission; pictures of the icons also need Screen Recording.
@MainActor
enum MenuBarExtras {
    static var canRead: Bool { AXIsProcessTrusted() }
    static var canPicture: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows macOS's prompt, which leads to System Settings.
    static func requestReading() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    static func requestPicturing() {
        CGRequestScreenCaptureAccess()
    }

    /// Every app's menu bar icons except Drawer's own, left to right.
    static func all() -> [MenuBarExtra] {
        guard canRead else { return [] }
        // Background-only apps (Control Center among them) own menu bar icons too, so every app is asked.
        return NSWorkspace.shared.runningApplications
            .filter { $0 != .current }
            .flatMap(extras(of:))
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func extras(of app: NSRunningApplication) -> [MenuBarExtra] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = element(appElement, kAXExtrasMenuBarAttribute) else { return [] }
        let children = elements(bar, kAXChildrenAttribute)
        return children.enumerated().compactMap { index, element in
            guard let frame = frame(of: element) else { return nil }
            let title = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                .compactMap { string(element, $0) }
                .first { !$0.isEmpty } ?? app.localizedName ?? "Menu bar icon"
            return MenuBarExtra(id: "\(app.processIdentifier)-\(index)", app: app, element: element, frame: frame, title: title)
        }
    }

    /// Opens the icon's menu or window. Accessibility's press works for most; the rest only answer a real click,
    /// which is posted at the icon's centre with the pointer put back afterwards.
    static func open(_ extra: MenuBarExtra) {
        if AXUIElementPerformAction(extra.element, kAXPressAction as CFString) == .success { return }
        guard let frame = frame(of: extra.element) else { return }
        let pointer = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        if let pointer { CGWarpMouseCursorPosition(pointer) }
    }

    /// True while the icon sits in a screen's menu bar, where it can be seen and clicked.
    static func isOnScreen(_ frame: CGRect) -> Bool {
        isInMenuBar(frame, screens: NSScreen.screens.map { ($0.frame, menuBarHeight(of: $0)) })
    }

    /// `frame` is in Accessibility's coordinates (top-left origin); `screens` in AppKit's (bottom-left), main first.
    nonisolated static func isInMenuBar(_ frame: CGRect, screens: [(frame: CGRect, barHeight: CGFloat)]) -> Bool {
        let mainHeight = screens.first?.frame.height ?? 0
        return screens.contains { screen in
            let top = mainHeight - screen.frame.maxY // the screen's top edge in Accessibility's coordinates
            return screen.frame.minX <= frame.midX && frame.midX <= screen.frame.maxX
                && frame.minY >= top - 1 && frame.maxY <= top + screen.barHeight + 1
        }
    }

    /// Where an icon is in a capture of its screen's menu bar, in the capture's pixels.
    nonisolated static func pixelRect(of frame: CGRect, inBarOf screen: CGRect, mainHeight: CGFloat, scale: CGFloat) -> CGRect {
        let top = mainHeight - screen.maxY
        return CGRect(x: (frame.minX - screen.minX) * scale, y: (frame.minY - top) * scale,
                      width: frame.width * scale, height: frame.height * scale)
    }

    static func menuBarHeight(of screen: NSScreen) -> CGFloat {
        max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
    }

    /// Pictures of the icons showing right now, cut from one capture of each screen's menu bar. Drawer takes them
    /// while its icons show, so the bar can show the real icons later, when they're hidden.
    static func pictures(of extras: [MenuBarExtra]) async -> [String: NSImage] {
        guard canPicture, let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return [:] }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        var pictures: [String: NSImage] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == number }) else { continue }
            let height = menuBarHeight(of: screen)
            let scale = screen.backingScaleFactor
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: 0, y: 0, width: screen.frame.width, height: height)
            configuration.width = Int(screen.frame.width * scale)
            configuration.height = Int(height * scale)
            configuration.showsCursor = false
            guard let capture = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []),
                                                                           configuration: configuration) else { continue }
            for extra in extras where isOnScreen(extra.frame) && screen.frame.minX <= extra.frame.midX && extra.frame.midX <= screen.frame.maxX {
                let crop = pixelRect(of: extra.frame, inBarOf: screen.frame, mainHeight: mainHeight, scale: scale)
                if let piece = capture.cropping(to: crop) {
                    pictures[pictureKey(extra)] = NSImage(cgImage: piece, size: extra.frame.size)
                }
            }
        }
        return pictures
    }

    /// Survives the app relaunching, unlike `id`, as long as the icon keeps its title.
    static func pictureKey(_ extra: MenuBarExtra) -> String {
        "\(extra.app.bundleIdentifier ?? extra.appName)|\(extra.title)"
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    // MARK: Accessibility attribute reading

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (copy(element, attribute) as? [AnyObject] ?? []).compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }
}
