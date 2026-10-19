import AppKit
import Carbon.HIToolbox
import Kit

@main
enum Main {
    @MainActor static func main() { Kit.run { Drawer() } }
}

/// Hides the menu bar icons you don't need to see, like Bartender and Ice, with public API only and no permissions.
///
/// ⌘-drag icons to the left of the │ divider to hide them, or left of the ┆ divider to hide them even while the
/// others show. To hide, a divider grows to fill the menu bar's free space, so the icons to its left have no room
/// and macOS takes them out. It must fit exactly: since macOS 26, a divider wider than the free space (the classic
/// 10,000-point trick) gets taken out itself and hides nothing. Filling the free space is also how Drawer notices
/// clicks and hovers on the empty menu bar.
@MainActor
final class Drawer {
    enum State {
        /// Everything left of │ is hidden.
        case collapsed
        /// Hidden icons show; anything left of ┆ stays hidden.
        case shown
        /// Every icon shows, including the always-hidden ones.
        case all
    }

    private enum Key {
        static let rehideDelay = "rehideDelay"
        static let showOnClick = "showOnClick"
        static let showOnHover = "showOnHover"
        static let showOnScroll = "showOnScroll"
        static let alwaysHidden = "alwaysHiddenSection"
        static let hideAppMenus = "hideAppMenus"
        static let useBar = "showInDrawerBar"
    }

    /// The padding macOS adds around every menu bar item, on top of its length.
    private static let itemPadding: CGFloat = 16
    /// How long the menu bar takes to lay out again after a length changes.
    private static let layoutDelay: Duration = .milliseconds(300)
    /// Halvings in the search for the widest fitting divider: ~1,500 points down to ~2.
    private static let fitSteps = 10
    // ponytail: fixed shortcuts. Bring over Snicker's ShortcutStore if people want to change them.
    private static let toggleShortcut = (keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey)
    private static let showAllShortcut = (keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey | shiftKey)
    private static let rehideChoices: [(title: String, seconds: Int)] = [
        ("Never", 0), ("After 5 Seconds", 5), ("After 15 Seconds", 15), ("After 1 Minute", 60),
    ]
    /// Long enough that moving the pointer across the menu bar on the way somewhere doesn't open the drawer.
    private static let hoverDelay: Duration = .milliseconds(300)
    /// Trackpads send tiny deltas while resting; this filters them out.
    private static let scrollThreshold: CGFloat = 4

    private lazy var chevron = MenuBarItem(
        name: "Drawer",
        symbol: "chevron.left",
        click: .action { [unowned self] in chevronClicked() },
        menuItems: { [unowned self] in menuItems() }
    )
    /// Created after the chevron (see `init`), so on first launch macOS places it just left of the chevron.
    private lazy var divider = Self.makeDivider(autosaveName: "Drawer divider", image: Self.line(dashed: false),
                                                label: "Drawer divider. Icons to its left are hidden.")
    private var alwaysDivider: NSStatusItem?

    private var state = State.collapsed
    private var hotKeys: [HotKey] = []
    private var clickMonitor: Any?
    private var scrollMonitors: [Any] = []
    private var hoverWatcher: HoverWatcher?
    private var hoverTask: Task<Void, Never>?
    private var rehideTimer: Timer?
    private var idleSince = Date()
    /// Each divider's right edge at its normal width; it stays put while the divider grows leftwards.
    private var rightEdges: [String: CGFloat] = [:]
    /// The widest fitting length per divider and frontmost app, whose menus decide how much room is left.
    private var fittedWidths: [String: CGFloat] = [:]
    private var fitTasks: [String: Task<Void, Never>] = [:]
    private var refitObservers: [Any] = []
    /// The app in front before Drawer stepped in to hide its menus; it gets the front back when the icons hide.
    private var appBeforeShowing: NSRunningApplication?
    private lazy var bar = DrawerBar { [unowned self] extra in openFromBar(extra) }
    private let appearance = Appearance()
    /// How long an icon opened from the bar takes to land in the menu bar before it's clicked.
    private static let openDelay: Duration = .milliseconds(400)
    /// The menu bar settles after the icons show; pictures taken sooner catch them mid-move.
    private static let pictureDelay: Duration = .milliseconds(700)

    private var defaults: UserDefaults { .standard }

    init() {
        defaults.register(defaults: [Key.rehideDelay: 15, Key.showOnClick: true, Key.hideAppMenus: true])
        // 0 doesn't count as a position, so the chevron starts at 1.
        Self.seedPosition(of: "Drawer", at: 1)
        Self.seedPosition(of: "Drawer divider", at: 2)
        NSApp.mainMenu = Self.mainMenu()
        _ = chevron
        _ = divider
        if defaults.bool(forKey: Key.alwaysHidden) { alwaysDivider = Self.makeAlwaysDivider() }
        hotKeys = [
            HotKey(keyCode: Self.toggleShortcut.keyCode, modifiers: Self.toggleShortcut.modifiers) { [weak self] in
                MainActor.assumeIsolated { self?.showOrHide() }
            },
            HotKey(keyCode: Self.showAllShortcut.keyCode, modifiers: Self.showAllShortcut.modifiers) { [weak self] in
                MainActor.assumeIsolated { self?.toggleAll() }
            },
        ].compactMap { $0 }
        watchEmptySpace()
        updateScrollMonitors()
        // Another app's menus, or another display, leave a different amount of room.
        refitObservers = [
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.fittedWidths = [:]
                    self?.apply()
                }
            },
        ]
        // Wait a beat so macOS has placed the items before comparing where they are.
        DispatchQueue.main.async { [weak self] in self?.apply() }
    }

    // MARK: State

    /// Which dividers fill the free space in each state; the others are just wide enough for their line.
    nonisolated static func stretched(in state: State, alwaysHidden: Bool) -> (divider: Bool, always: Bool) {
        switch state {
        case .collapsed: return (true, false)
        case .shown: return (false, alwaysHidden)
        case .all: return (false, false)
        }
    }

    /// `makeRoom` is false for hovering: passing the pointer over the menu bar mustn't take the keyboard away.
    private func set(_ new: State, makeRoom: Bool = true) {
        guard new != .collapsed || canCollapse else {
            NSSound.beep()
            Kit.announce("Move Drawer's chevron to the right of its divider first")
            return
        }
        let opening = state == .collapsed && new != .collapsed
        state = new
        if opening && makeRoom { hideAppMenus() } else if new == .collapsed { restoreAppMenus() }
        apply()
    }

    /// On a Mac with a notch, the icons rarely all fit to its right, and macOS squeezes the app's menus to make room.
    /// Drawer has no menus, so bringing it to the front frees the whole menu bar for the icons, as Ice does.
    private func hideAppMenus() {
        guard defaults.bool(forKey: Key.hideAppMenus), let front = NSWorkspace.shared.frontmostApplication, front != .current else { return }
        appBeforeShowing = front
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Gives the front back only if Drawer still has it; if you've moved on to another app, you stay there.
    private func restoreAppMenus() {
        defer { appBeforeShowing = nil }
        guard NSApp.isActive, let app = appBeforeShowing, !app.isTerminated else { return }
        app.activate()
    }

    private func toggle() {
        set(state == .collapsed ? .shown : .collapsed)
    }

    private func toggleAll() {
        guard alwaysDivider != nil else { return toggle() }
        set(state == .all ? .collapsed : .all)
    }

    private func chevronClicked() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true { toggleAll() } else { showOrHide() }
    }

    /// The chevron and ⌃⌥B: the bar when it's on, otherwise the icons in the menu bar itself.
    private func showOrHide() {
        if defaults.bool(forKey: Key.useBar) { toggleBar() } else { toggle() }
    }

    private func apply() {
        if state == .collapsed && !canCollapse { state = .shown }
        let stretched = Self.stretched(in: state, alwaysHidden: alwaysDivider != nil && isAlwaysLeftOfDivider)
        set(divider, name: "divider", stretched: stretched.divider, image: Self.line(dashed: false))
        if let alwaysDivider { set(alwaysDivider, name: "always", stretched: stretched.always, image: Self.line(dashed: true)) }
        if state != .collapsed { takePictures() }
        chevron.setSymbol(state == .collapsed ? "chevron.left" : "chevron.right")
        chevron.statusItem.button?.setAccessibilityLabel(state == .collapsed ? "Show hidden menu bar icons" : "Hide menu bar icons")
        updateRehideTimer()
    }

    // MARK: Drawer Bar

    private func toggleBar() {
        if bar.isShown { return bar.close() }
        let extras = MenuBarExtras.all()
        let hidden = Set(extras.filter(isHidden).map(\.id))
        bar.show(extras: extras, hidden: hidden, under: chevron.statusItem.button?.window?.frame ?? .zero)
    }

    /// Hidden icons are parked off screen while Drawer is collapsed, or sit left of │ while it's open.
    private func isHidden(_ extra: MenuBarExtra) -> Bool {
        guard MenuBarExtras.isOnScreen(extra.frame) else { return true }
        return rightEdges["divider"].map { extra.frame.midX < $0 } ?? false
    }

    /// A hidden icon can't be clicked where macOS parked it, so show the icons, wait for it to land, then open it.
    /// Drawer hides them again on its usual timer, which waits while the icon's menu is open.
    private func openFromBar(_ extra: MenuBarExtra) {
        if MenuBarExtras.isOnScreen(extra.frame), !isHidden(extra) { return MenuBarExtras.open(extra) }
        set(alwaysDivider == nil ? .shown : .all)
        Task {
            try? await Task.sleep(for: Self.openDelay)
            MenuBarExtras.open(extra)
        }
    }

    /// While the icons show, pictures of them are taken for the bar (with Screen Recording permission only).
    private func takePictures() {
        guard MenuBarExtras.canPicture, MenuBarExtras.canRead else { return }
        Task { [weak self] in
            try? await Task.sleep(for: Self.pictureDelay)
            let pictures = await MenuBarExtras.pictures(of: MenuBarExtras.all())
            self?.bar.model.pictures.merge(pictures) { $1 }
        }
    }

    // MARK: Fitting a divider to the free space

    private func set(_ item: NSStatusItem, name: String, stretched: Bool, image: NSImage) {
        fitTasks[name]?.cancel()
        if item.length == NSStatusItem.variableLength, let frame = Self.onScreenFrame(of: item) { rightEdges[name] = frame.maxX }
        guard stretched else {
            item.length = NSStatusItem.variableLength
            item.button?.image = image
            return
        }
        item.button?.image = nil
        fitTasks[name] = Task { [weak self] in await self?.fit(item, name: name) }
    }

    /// Finds the widest length at which the divider still shows. Starts from the free space up to the notch (or the
    /// screen's edge), then halves the step until it lands; what fits is remembered for the frontmost app.
    private func fit(_ item: NSStatusItem, name: String) async {
        if rightEdges[name] == nil {
            // Never seen at its normal width yet (Drawer just launched hidden): measure it first.
            item.length = NSStatusItem.variableLength
            try? await Task.sleep(for: Self.layoutDelay)
            rightEdges[name] = Self.onScreenFrame(of: item)?.maxX
        }
        guard let right = rightEdges[name], !Task.isCancelled else { return }
        let screen = NSScreen.screens.first { $0.frame.minX <= right && right <= $0.frame.maxX } ?? NSScreen.main
        let key = "\(name) \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")"
        if let known = fittedWidths[key], await fits(item, known) { return }

        // On a screen with a notch, the free space ends at the notch's right edge: menu bar icons never go behind it.
        if let notch = screen?.auxiliaryTopRightArea?.minX, right - notch > Self.itemPadding {
            item.length = right - notch - Self.itemPadding
            return
        }
        // Without a notch, the frontmost app's menus are the limit, and only trying tells how wide they are.
        let left = screen?.frame.minX ?? 0
        var low: CGFloat = 0, high = max(right - left - Self.itemPadding, 0)
        if await fits(item, high) {
            fittedWidths[key] = high
            return
        }
        for _ in 0..<Self.fitSteps {
            let middle = ((low + high) / 2).rounded()
            if await fits(item, middle) { low = middle } else { high = middle }
            if Task.isCancelled { return }
        }
        fittedWidths[key] = low
        item.length = low
    }

    /// Tries a length and reports whether macOS still shows the divider at it.
    private func fits(_ item: NSStatusItem, _ length: CGFloat) async -> Bool {
        item.length = length
        try? await Task.sleep(for: Self.layoutDelay)
        return !Task.isCancelled && Self.onScreenFrame(of: item) != nil
    }

    /// The item's frame while it sits in a menu bar. Nil while macOS has it parked off screen (as it does when the
    /// menu bar is out of room) or hasn't placed it yet.
    private static func onScreenFrame(of item: NSStatusItem?) -> CGRect? {
        guard let frame = item?.button?.window?.frame, frame.height > 0 else { return nil }
        let inMenuBar = NSScreen.screens.contains { screen in
            screen.frame.minX <= frame.maxX && frame.maxX <= screen.frame.maxX && frame.maxY >= screen.frame.maxY - 1
        }
        return inMenuBar ? frame : nil
    }

    // MARK: Layout checks

    /// Right edges, because an item grows leftwards: its right edge stays put however wide it gets.
    private func rightEdge(_ item: NSStatusItem?) -> CGFloat? {
        Self.onScreenFrame(of: item)?.maxX
    }

    /// Collapsing with the chevron left of the divider would hide the chevron itself, and with it the way back.
    private var canCollapse: Bool {
        guard let chevronEdge = rightEdge(chevron.statusItem), let dividerEdge = rightEdge(divider) else { return true }
        return chevronEdge > dividerEdge
    }

    /// ┆ only hides anything when it's left of │; dragged elsewhere, it's ignored rather than hiding the wrong icons.
    private var isAlwaysLeftOfDivider: Bool {
        guard let alwaysEdge = rightEdge(alwaysDivider), let dividerEdge = rightEdge(divider) else { return false }
        return alwaysEdge < dividerEdge
    }

    // MARK: Showing from the empty menu bar

    /// Clicks reach the stretched divider because it's our own window. The divider's button is disabled so it never
    /// draws a highlight across the whole menu bar; the local monitor sees the click before the button would.
    private func watchEmptySpace() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            // ⌘-drag is macOS rearranging icons, not a click.
            guard !event.modifierFlags.contains(.command) else { return event }
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated { self?.clicked(windowNumber: windowNumber) }
            return event
        }
        let watcher = HoverWatcher { [weak self] inside in self?.hoverChanged(inside) }
        divider.button?.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                       owner: watcher, userInfo: nil))
        hoverWatcher = watcher
    }

    private func clicked(windowNumber: Int) {
        guard windowNumber == divider.button?.window?.windowNumber else { return }
        if state != .collapsed || defaults.bool(forKey: Key.showOnClick) { toggle() }
    }

    private func hoverChanged(_ inside: Bool) {
        hoverTask?.cancel()
        guard inside, state == .collapsed, defaults.bool(forKey: Key.showOnHover) else { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverDelay)
            guard !Task.isCancelled, let self, state == .collapsed else { return }
            set(.shown, makeRoom: false)
        }
    }

    /// Scrolling or swiping in the menu bar: one way shows, the other hides. Other apps' scrolls arrive through the
    /// global monitor (no permission needed for scroll events), scrolls over our own divider through the local one.
    private func updateScrollMonitors() {
        scrollMonitors.forEach(NSEvent.removeMonitor)
        scrollMonitors = []
        guard defaults.bool(forKey: Key.showOnScroll) else { return }
        let handle: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.scrolled(event) }
        }
        scrollMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: handle),
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in handle(event); return event },
        ].compactMap { $0 }
    }

    private func scrolled(_ event: NSEvent) {
        guard abs(event.scrollingDeltaY) >= Self.scrollThreshold, Self.isPointerInMenuBar else { return }
        if event.scrollingDeltaY > 0, state == .collapsed {
            set(.shown)
        } else if event.scrollingDeltaY < 0, state != .collapsed, canCollapse {
            set(.collapsed)
        }
    }

    // MARK: Hiding again

    private var rehideDelay: Int { defaults.integer(forKey: Key.rehideDelay) }

    /// Runs only while icons show, so a collapsed Drawer costs nothing.
    private func updateRehideTimer() {
        rehideTimer?.invalidate()
        rehideTimer = nil
        guard state != .collapsed, rehideDelay > 0 else { return }
        idleSince = Date()
        rehideTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkRehide() }
        }
    }

    /// The countdown starts over while the pointer is in the menu bar or a menu is open, so an icon never
    /// disappears while you're reaching for it or using its menu.
    private func checkRehide() {
        guard canCollapse else {
            rehideTimer?.invalidate()
            return
        }
        if Self.isPointerInMenuBar || Self.isMenuOpen {
            idleSince = Date()
        } else if Date().timeIntervalSince(idleSince) >= TimeInterval(rehideDelay) {
            set(.collapsed)
        }
    }

    private static var isPointerInMenuBar: Bool {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) else { return false }
        // visibleFrame leaves out the menu bar; with an auto-hiding menu bar it doesn't, so fall back to its thickness.
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        return pointer.y >= screen.frame.maxY - height
    }

    /// Any app's open menu, including menu bar menus. Window levels and bounds need no Screen Recording permission.
    private static var isMenuOpen: Bool {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { $0[kCGWindowLayer as String] as? Int == menuLevel }
    }

    // MARK: Menu

    private func menuItems() -> [NSMenuItem] {
        let show = NSMenuItem(state == .collapsed ? "Show Hidden Icons" : "Hide Icons", symbol: state == .collapsed ? "eye" : "eye.slash") { [unowned self] in
            toggle()
        }
        // Shown beside the item, like any menu shortcut. The global hotkey does the actual work.
        show.keyEquivalent = "b"
        show.keyEquivalentModifierMask = [.control, .option]
        var items = [show]
        if alwaysDivider != nil {
            let all = NSMenuItem(state == .all ? "Hide All Icons" : "Show All Icons", symbol: "eye.circle") { [unowned self] in toggleAll() }
            all.keyEquivalent = "b"
            all.keyEquivalentModifierMask = [.control, .option, .shift]
            items.append(all)
        }
        items += [
            .separator(),
            .submenu("Show Icons When", symbol: "cursorarrow.click", [
                setting("Clicking Empty Menu Bar Space", Key.showOnClick),
                setting("Hovering Over Empty Menu Bar Space", Key.showOnHover),
                setting("Scrolling in the Menu Bar", Key.showOnScroll) { [unowned self] in updateScrollMonitors() },
            ]),
            .submenu("Hide Again", symbol: "timer", Self.rehideChoices.map { choice in
                let item = NSMenuItem(choice.title) { [unowned self] in
                    defaults.set(choice.seconds, forKey: Key.rehideDelay)
                    updateRehideTimer()
                }
                item.state = rehideDelay == choice.seconds ? .on : .off
                return item
            }),
            .submenu("Show Hidden Icons In", symbol: "rectangle.topthird.inset.filled", [
                choice("The Menu Bar", Key.useBar, false),
                choice("Drawer Bar, Under the Menu Bar", Key.useBar, true) {
                    if !MenuBarExtras.canRead { MenuBarExtras.requestReading() }
                },
            ]),
            NSMenuItem("Menu Bar Appearance…", symbol: "paintpalette") { [unowned self] in appearance.showSettings() },
            setting("Hide App Menus While Icons Show", Key.hideAppMenus),
            setting("Always-Hidden Section", Key.alwaysHidden) { [unowned self] in alwaysHiddenChanged() },
            .submenu("Icon Spacing", symbol: "arrow.left.and.right", IconSpacing.allCases.map { spacing in
                let item = NSMenuItem(spacing.title) { spacing.apply() }
                item.state = IconSpacing.current == spacing ? .on : .off
                return item
            } + [.separator(), .label("Apps pick it up as they reopen; log out for all")]),
            .separator(),
            .label("⌘-drag icons left of │ to hide them"),
        ]
        if alwaysDivider != nil { items.append(.label("…or left of ┆ to keep them hidden")) }
        return items
    }

    private func choice(_ title: String, _ key: String, _ value: Bool, chosen: (() -> Void)? = nil) -> NSMenuItem {
        let item = NSMenuItem(title) { [unowned self] in
            defaults.set(value, forKey: key)
            chosen?()
        }
        item.state = defaults.bool(forKey: key) == value ? .on : .off
        return item
    }

    private func setting(_ title: String, _ key: String, changed: (() -> Void)? = nil) -> NSMenuItem {
        let item = NSMenuItem(title) { [unowned self] in
            defaults.set(!defaults.bool(forKey: key), forKey: key)
            changed?()
        }
        item.state = defaults.bool(forKey: key) ? .on : .off
        return item
    }

    /// Turning the section on shows every icon, so the new ┆ divider is there to drag icons past.
    private func alwaysHiddenChanged() {
        if defaults.bool(forKey: Key.alwaysHidden) {
            alwaysDivider = alwaysDivider ?? Self.makeAlwaysDivider()
            DispatchQueue.main.async { [weak self] in self?.set(.all) }
        } else {
            if let alwaysDivider { NSStatusBar.system.removeStatusItem(alwaysDivider) }
            alwaysDivider = nil
            apply()
        }
    }

    /// Drawer's menus, for the moments it's in front: while it clears the app menus away, and while the bar's
    /// search field has focus, where ⌘V and friends only work through an Edit menu.
    private static func mainMenu() -> NSMenu {
        let app = NSMenu()
        app.addItem(withTitle: "Quit Drawer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let menu = NSMenu()
        for submenu in [app, edit] {
            let item = NSMenuItem()
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }

    // MARK: Dividers

    private static func makeDivider(autosaveName: String, image: NSImage, label: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        item.button?.image = image
        item.button?.isEnabled = false
        item.button?.setAccessibilityLabel(label)
        return item
    }

    /// macOS puts a new menu bar item at the far left, which on a full menu bar, or behind the notch, means out of
    /// sight. So Drawer's items start at the far right, next to the system's, and everything else starts out hideable.
    /// This is macOS's own saved position (points from the right edge), so it's set only before the user moves them.
    private static func seedPosition(of autosaveName: String, at position: Int) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(position, forKey: key) }
    }

    private static func makeAlwaysDivider() -> NSStatusItem {
        seedPosition(of: "Drawer always-hidden divider", at: 3)
        return makeDivider(autosaveName: "Drawer always-hidden divider", image: line(dashed: true),
                    label: "Drawer always-hidden divider. Icons to its left stay hidden until you show all icons.")
    }

    /// │ for the divider, ┆ for the always-hidden one. Drawn rather than symbols, so they read as dividers and nothing else.
    private static func line(dashed: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            if dashed {
                for y in stride(from: 1.0, to: rect.height - 1, by: 4.5) {
                    NSBezierPath(roundedRect: NSRect(x: rect.midX - 1, y: y, width: 2, height: 2.5), xRadius: 1, yRadius: 1).fill()
                }
            } else {
                NSBezierPath(roundedRect: NSRect(x: rect.midX - 1, y: 1, width: 2, height: rect.height - 2), xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Space between menu bar icons, through the same system preferences Ice changes. Each app reads them when it opens.
enum IconSpacing: CaseIterable {
    case standard, compact, tight

    private static let spacingKey = "NSStatusItemSpacing" as CFString
    private static let paddingKey = "NSStatusItemSelectionPadding" as CFString

    var title: String {
        switch self {
        case .standard: return "Default"
        case .compact: return "Compact"
        case .tight: return "Tight"
        }
    }

    /// Nil removes the preference, which gives back macOS's own spacing.
    private var values: (spacing: Int, padding: Int)? {
        switch self {
        case .standard: return nil
        case .compact: return (8, 8)
        case .tight: return (4, 4)
        }
    }

    static var current: IconSpacing {
        let spacing = CFPreferencesCopyValue(spacingKey, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
        return allCases.first { $0.values?.spacing == spacing } ?? .standard
    }

    func apply() {
        for (key, value) in [(Self.spacingKey, values?.spacing), (Self.paddingKey, values?.padding)] {
            CFPreferencesSetValue(key, value.map { $0 as CFNumber }, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}

/// Receives the divider's tracking-area events: is the pointer over the empty menu bar space?
private final class HoverWatcher: NSResponder {
    private let changed: (Bool) -> Void

    init(changed: @escaping (Bool) -> Void) {
        self.changed = changed
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) { changed(true) }
    override func mouseExited(with event: NSEvent) { changed(false) }
}
