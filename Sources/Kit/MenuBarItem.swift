import AppKit
import ServiceManagement
import SwiftUI

/// One menu bar icon, the whole interface of most apps in the suite. A click runs `click`; right-click
/// (or Control-click) shows the app menu: an update when there is one, the app's own `menuItems`, then Check for
/// Updates, Open at Login, About and Quit.
@MainActor
public final class MenuBarItem: NSObject {
    public enum Click {
        /// The size is fixed up front: letting SwiftUI size a popover after showing makes it grow up under the menu bar.
        case popover(AnyView, size: NSSize)
        /// Built on every click, so it always shows the current state. About and Quit are added at the bottom.
        case menu(() -> NSMenu)
        case action(() -> Void)
    }

    public let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    /// Called as the popover opens and after it closes, so anything live (a camera, a clock) runs only while it shows.
    public var onShow: (() -> Void)?
    public var onClose: (() -> Void)?

    private let name: String
    private let click: Click
    private let menuItems: () -> [NSMenuItem]
    private var popover: NSPopover?
    private var outsideClickMonitor: Any?
    private var symbol: String?
    private var title = ""
    private var flashTask: Task<Void, Never>?

    private static let flashDuration: Duration = .milliseconds(900)

    public init(name: String, symbol: String?, click: Click, menuItems: @escaping () -> [NSMenuItem] = { [] }) {
        self.name = name
        self.click = click
        self.menuItems = menuItems
        super.init()
        // Lets the user ⌘-drag the icon to a new place and keeps it there across launches.
        statusItem.autosaveName = name
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        setSymbol(symbol)
    }

    /// An SF Symbol name, or nil for a text-only item.
    public func setSymbol(_ symbol: String?) {
        self.symbol = symbol
        guard flashTask == nil else { return } // the flash puts the latest symbol back when it ends
        statusItem.button?.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        updateLayout()
    }

    /// Text beside the icon; empty shows the icon alone.
    public func setTitle(_ title: String) {
        self.title = title
        statusItem.button?.title = title
        updateLayout()
    }

    /// Red for a state that must not be missed, such as a muted microphone. Nil follows the menu bar.
    public func setTint(_ color: NSColor?) {
        statusItem.button?.contentTintColor = color
    }

    /// Briefly swaps the icon to confirm something that happened without opening anything, like a copy.
    public func flash(_ symbol: String = "checkmark.circle.fill") {
        flashTask?.cancel()
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flashDuration)
            guard let self, !Task.isCancelled else { return }
            flashTask = nil
            setSymbol(self.symbol)
        }
    }

    public func closePopover() {
        popover?.performClose(nil)
    }

    private func updateLayout() {
        guard let button = statusItem.button else { return }
        button.imagePosition = title.isEmpty ? .imageOnly : (symbol == nil ? .noImage : .imageLeading)
        button.setAccessibilityLabel(title.isEmpty ? name : "\(name), \(title)")
    }

    @objc private func clicked() {
        Updater.shared.checkIfDue()
        // VoiceOver and other Accessibility presses arrive without a mouse event; they count as a click.
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            closePopover()
            show(appMenu(with: menuItems()))
            return
        }
        switch click {
        case let .popover(view, size): togglePopover(view, size: size)
        case let .menu(make): show(appMenu(with: make().items.map { item in item.menu?.removeItem(item); return item }))
        case let .action(action): action()
        }
    }

    private func show(_ menu: NSMenu) {
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
    }

    private func appMenu(with items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let version = Updater.shared.availableVersion {
            menu.addItem(NSMenuItem("Update to Topside \(version)…", symbol: "arrow.down.circle") { Updater.shared.offerUpdate() })
            menu.addItem(.separator())
        }
        items.forEach(menu.addItem)
        if !items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(NSMenuItem("Check for Updates…") { Updater.shared.checkNow() })
        let login = NSMenuItem("Open at Login") { Self.toggleOpenAtLogin() }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("About \(name)", #selector(showAbout)))
        menu.addItem(item("Quit \(name)", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func togglePopover(_ view: AnyView, size: NSSize) {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = popover ?? makePopover(view, size: size)
        self.popover = popover
        guard let button = statusItem.button else { return }
        onShow?()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopover(_ view: AnyView, size: NSSize) -> NSPopover {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = size
        popover.contentViewController = hosting
        popover.delegate = self
        // A transient popover stops closing on outside clicks once a context menu has been open (learned in Snicker),
        // so close it ourselves. Global monitors only see clicks in other apps and need no permission for the mouse.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak popover] _ in
            if popover?.isShown == true { popover?.performClose(nil) }
        }
        return popover
    }

    /// Some Macs ask the user to approve login items first; System Settings opens at the right place for that.
    private static func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSSound.beep()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc private func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(string: Kit.credits, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
            .link: Kit.websiteURL,
        ])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension MenuBarItem: NSPopoverDelegate {
    public func popoverDidClose(_ notification: Notification) {
        onClose?()
    }
}

extension NSMenuItem {
    /// A menu item that runs a closure, so apps don't each need an `@objc` method per item.
    public convenience init(_ title: String, symbol: String? = nil, key: String = "", action: (() -> Void)?) {
        self.init(title: title, action: nil, keyEquivalent: key)
        image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        guard let action else {
            isEnabled = false
            return
        }
        let handler = ClosureHandler(action)
        target = handler
        self.action = #selector(ClosureHandler.run)
        representedObject = handler // the item holds the handler; `target` alone is weak
    }

    /// An item that opens a submenu of `items`.
    public static func submenu(_ title: String, symbol: String? = nil, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title, symbol: symbol, action: nil)
        item.isEnabled = true
        let menu = NSMenu()
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    /// A gray line that only informs, like "Awake until 22:15".
    public static func label(_ title: String) -> NSMenuItem {
        NSMenuItem(title, action: nil)
    }

    /// For a global shortcut another app already holds, which `HotKey` reports by being nil: says so, instead of
    /// listing a shortcut that does nothing.
    public static func shortcutTaken(_ shortcut: String) -> NSMenuItem {
        NSMenuItem("\(shortcut) is used by another app", symbol: "exclamationmark.triangle", action: nil)
    }
}

private final class ClosureHandler: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}
