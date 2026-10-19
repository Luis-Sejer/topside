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

/// Finding, picturing and clicking other apps' menu bar icons. Since macOS 27 one process, MenuBarAgent, draws the
/// whole menu bar, so the icons aren't windows anyone can list; this goes through each app's Accessibility "extras
/// menu bar" instead. Needs the Accessibility permission; pictures of the icons also need Screen Recording.
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

    private static let menuBarAgent = "com.apple.MenuBarAgent"

    /// Every app's menu bar icons except Drawer's own, left to right. MenuBarAgent's are macOS's own (Wi-Fi, the clock
    /// and the like), which can't be pressed from outside, so they're left out too.
    static func all() -> [MenuBarExtra] {
        guard canRead else { return [] }
        // Background-only apps own menu bar icons too, so every app is asked.
        return NSWorkspace.shared.runningApplications
            .filter { $0 != .current && $0.bundleIdentifier != menuBarAgent }
            .flatMap(extras(of:))
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// macOS's » button, which shows and hides the icons that don't fit. It's the only button among MenuBarAgent's
    /// items; its label is translated, its role isn't. Nil when everything fits and there is no button.
    static func overflowButton() -> CGRect? {
        guard canRead, let agent = NSRunningApplication.runningApplications(withBundleIdentifier: menuBarAgent).first,
              let bar = element(AXUIElementCreateApplication(agent.processIdentifier), kAXExtrasMenuBarAttribute) else { return nil }
        return elements(bar, kAXChildrenAttribute).first { string($0, kAXRoleAttribute) == kAXButtonRole }.flatMap(frame(of:))
    }

    /// Hidden icons sit left of the » button: stacked behind it, or laid out left of the notch while it's open.
    nonisolated static func isHidden(_ frame: CGRect, overflow: CGRect?) -> Bool {
        overflow.map { frame.midX < $0.maxX } ?? false
    }

    /// While the hidden icons are hidden, macOS stacks them under the » button, out of sight.
    nonisolated static func isStacked(_ frame: CGRect, overflow: CGRect) -> Bool {
        frame.intersects(overflow)
    }

    /// Whether the app shows a menu, popover or panel: any window above the normal level. Window owners and levels
    /// need no Screen Recording permission.
    static func hasOpenMenu(_ app: NSRunningApplication) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0 }
    }

    private static func extras(of app: NSRunningApplication) -> [MenuBarExtra] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = element(appElement, kAXExtrasMenuBarAttribute) else { return [] }
        let children = elements(bar, kAXChildrenAttribute)
        return children.enumerated().compactMap { index, element in
            // Only icons that can be pressed, and that are in a menu bar (macOS keeps a few placeholders off screen).
            guard actions(of: element).contains(kAXPressAction), let frame = frame(of: element), isOnScreen(frame) else { return nil }
            let title = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                .compactMap { string(element, $0) }
                .first { !$0.isEmpty } ?? app.localizedName ?? "Menu bar icon"
            return MenuBarExtra(id: "\(app.processIdentifier)-\(index)", app: app, element: element, frame: frame, title: title)
        }
    }

    /// How long Drawer waits for an app to answer Accessibility. An app showing a menu can be slow to say so.
    private static let pressTimeout: Float = 0.5

    /// Opens the icon's menu or window with Accessibility's press. An app that opens a menu often reports "cannot
    /// complete" while the menu shows, so only an app that doesn't answer at all gets a real click instead.
    static func open(_ extra: MenuBarExtra) {
        AXUIElementSetMessagingTimeout(extra.element, pressTimeout)
        let result = AXUIElementPerformAction(extra.element, kAXPressAction as CFString)
        guard result == .actionUnsupported || result == .failure, let frame = frame(of: extra.element) else { return }
        click(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    /// A real click, for what Accessibility can't press (like macOS's » button), with the pointer put back after.
    static func click(at point: CGPoint) {
        let pointer = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
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

    /// Pictures of the icons showing right now, cut from one capture of each screen's menu bar, so the bar can show
    /// the real icons later, when they're hidden. The menu bar is see-through on macOS 27, so the capture leaves out
    /// the wallpaper, and each icon is then cut out of what's left behind it.
    static func pictures(of extras: [MenuBarExtra]) async -> [String: NSImage] {
        guard canPicture, let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return [:] }
        // Everything below the normal window level: the wallpaper, the desktop's icons and widgets, whoever draws them.
        let wallpaper = content.windows.filter { $0.windowLayer < 0 }
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
            guard let capture = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: wallpaper),
                                                                           configuration: configuration) else { continue }
            for extra in extras where isOnScreen(extra.frame) && screen.frame.minX <= extra.frame.midX && extra.frame.midX <= screen.frame.maxX {
                let crop = pixelRect(of: extra.frame, inBarOf: screen.frame, mainHeight: mainHeight, scale: scale)
                if let piece = capture.cropping(to: crop).flatMap(cutOut) {
                    pictures[pictureKey(extra)] = picture(piece, size: extra.frame.size)
                }
            }
        }
        return pictures
    }

    /// Most menu bar icons are one colour, drawn white or black to suit the wallpaper. Those become templates, which
    /// the bar draws in its own text colour; icons in colour keep theirs.
    static func picture(_ image: CGImage, size: NSSize) -> NSImage {
        let picture = NSImage(cgImage: image, size: size)
        picture.isTemplate = isMonochrome(image)
        return picture
    }

    /// True when every visible pixel is a grey: no channel more than a little apart from the others.
    nonisolated static func isMonochrome(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in 0..<width * height where pixels[i * 4 + 3] > 64 {
            let channels = [pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2]].map(Int.init)
            if channels.max()! - channels.min()! > 40 { return false }
        }
        return true
    }

    /// The icon without what's behind it. The background is the most common colour along the picture's edge, where an
    /// icon never reaches; each pixel's distance from it becomes its opacity, so anti-aliased edges stay smooth, and
    /// its colour is what's left once the background is taken out.
    nonisolated static func cutOut(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 2, height > 2,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        func rgb(_ i: Int) -> SIMD3<Double> { SIMD3(Double(pixels[i * 4]), Double(pixels[i * 4 + 1]), Double(pixels[i * 4 + 2])) }
        var edge: [Int] = []
        for x in 0..<width { edge += [x, (height - 1) * width + x] }
        for y in 0..<height { edge += [y * width, y * width + width - 1] }
        // The median of each channel along the edge: a stray bit of icon there doesn't move it.
        let sorted = (0..<3).map { channel in edge.map { rgb($0)[channel] }.sorted() }
        let background = SIMD3(sorted[0][edge.count / 2], sorted[1][edge.count / 2], sorted[2][edge.count / 2])
        let distances: [Double] = (0..<width * height).map { i in
            let difference = rgb(i) - background
            return (difference * difference).sum().squareRoot()
        }
        // The farthest pixel counts as fully opaque; below a little noise, nothing is.
        guard let farthest = distances.max(), farthest > 24 else { return nil }
        for i in 0..<width * height {
            let alpha = min(max((distances[i] - 12) / (farthest - 12), 0), 1)
            let behind: SIMD3<Double> = background * (1 - alpha)
            let color: SIMD3<Double> = alpha > 0 ? (rgb(i) - behind) / alpha : .zero
            for channel in 0..<3 { pixels[i * 4 + channel] = UInt8(min(max(color[channel] * alpha, 0), 255)) }
            pixels[i * 4 + 3] = UInt8(alpha * 255)
        }
        return context.makeImage()
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

    private static func actions(of element: AXUIElement) -> [String] {
        var names: CFArray?
        return AXUIElementCopyActionNames(element, &names) == .success ? names as? [String] ?? [] : []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }
}
