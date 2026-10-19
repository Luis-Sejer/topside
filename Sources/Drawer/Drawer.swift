import AppKit
import Carbon.HIToolbox
import Kit

@main
enum Main {
    @MainActor static func main() { Kit.run { Drawer() } }
}

/// A second menu bar for the icons that don't fit in the first. Since macOS 27, macOS hides those itself, stacked
/// behind its own » button. Drawer's chevron drops down a bar with them, with a search. Opening one has macOS show the
/// hidden icons for a moment, so the menu hangs from the real icon, clear of the notch; then they hide again.
///
/// Needs Accessibility to list and open other apps' icons. Screen Recording is optional: it lets the bar show the real
/// icons instead of their apps' icons.
@MainActor
final class Drawer {
    private enum Key {
        static let showAll = "showAllIcons"
    }

    // ponytail: a fixed shortcut. Bring over Snicker's ShortcutStore if people want to change it.
    private static let toggleShortcut = (keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey)
    /// How often, and how many times, Drawer checks whether macOS has laid out the hidden icons after » is clicked.
    private static let layoutPoll: Duration = .milliseconds(50)
    private static let layoutPolls = 20
    /// How often Drawer checks whether the opened icon's menu has closed, and for how long at most (ten minutes).
    private static let menuPoll: Duration = .milliseconds(250)
    private static let menuPolls = 2_400
    /// Some icons open a window, or nothing, instead of a menu. After this many polls without one, stop waiting.
    private static let noMenuPolls = 6
    /// The menu bar settles after the hidden icons show; pictures taken sooner catch them mid-move.
    private static let pictureDelay: Duration = .milliseconds(400)

    private lazy var chevron = MenuBarItem(
        name: "Drawer",
        symbol: "chevron.down",
        click: .action { [unowned self] in toggleBar() },
        menuItems: { [unowned self] in menuItems() }
    )
    private lazy var bar = DrawerBar(open: { [unowned self] extra in open(extra) },
                                     closed: { [unowned self] in chevron.setSymbol("chevron.down") })
    private let appearance = Appearance()
    private var hotKeys: [HotKey] = []
    private var openTask: Task<Void, Never>?
    /// Icons Drawer has already tried to photograph, so a failed capture doesn't make the menu bar flicker every time.
    private var photographed: Set<String> = []

    private var defaults: UserDefaults { .standard }

    init() {
        NSApp.mainMenu = Self.mainMenu()
        _ = chevron
        hotKeys = [
            HotKey(keyCode: Self.toggleShortcut.keyCode, modifiers: Self.toggleShortcut.modifiers) { [weak self] in
                MainActor.assumeIsolated { self?.toggleBar() }
            },
        ].compactMap { $0 }
    }

    // MARK: The bar

    private func toggleBar() {
        if bar.isShown { return bar.close() }
        let extras = MenuBarExtras.all()
        let keys = extras.map(MenuBarExtras.pictureKey)
        bar.model.pictures.merge(PictureStore.load(keys.filter { bar.model.pictures[$0] == nil })) { $1 }
        // Hidden icons without a picture yet: show them for a moment to photograph them, then open the bar.
        let missing = Set(keys.filter { bar.model.pictures[$0] == nil }).subtracting(photographed)
        if MenuBarExtras.canPicture, !missing.isEmpty, let overflow = MenuBarExtras.overflowButton(),
           extras.contains(where: { missing.contains(MenuBarExtras.pictureKey($0)) && MenuBarExtras.isStacked($0.frame, overflow: overflow) }) {
            photographed.formUnion(missing)
            openTask = Task { [weak self] in
                await self?.photographHidden(overflow: overflow)
                self?.showBar()
            }
        } else {
            showBar()
        }
    }

    private func showBar() {
        let extras = MenuBarExtras.all()
        let overflow = MenuBarExtras.overflowButton()
        let hidden = defaults.bool(forKey: Key.showAll) ? extras : extras.filter { MenuBarExtras.isHidden($0.frame, overflow: overflow) }
        bar.show(extras: extras, hidden: Set(hidden.map(\.id)), under: chevron.statusItem.button?.window?.frame ?? .zero)
        chevron.setSymbol("chevron.up")
        takePictures(of: extras, overflow: overflow)
    }

    /// Clicks », photographs the icons it lays out, and clicks it again.
    private func photographHidden(overflow: CGRect) async {
        MenuBarExtras.click(at: CGPoint(x: overflow.midX, y: overflow.midY))
        try? await Task.sleep(for: Self.pictureDelay)
        let showing = MenuBarExtras.all().filter { !MenuBarExtras.isStacked($0.frame, overflow: overflow) }
        keep(await MenuBarExtras.pictures(of: showing))
        if showing.contains(where: { MenuBarExtras.isHidden($0.frame, overflow: overflow) }),
           let button = MenuBarExtras.overflowButton() {
            MenuBarExtras.click(at: CGPoint(x: button.midX, y: button.midY))
            try? await Task.sleep(for: Self.pictureDelay)
        }
    }

    private func keep(_ pictures: [String: NSImage]) {
        guard !pictures.isEmpty else { return }
        bar.model.pictures.merge(pictures) { $1 }
        PictureStore.save(pictures)
    }

    /// An icon that shows can be pressed where it is. A hidden one is stacked behind macOS's » button, where its menu
    /// would open under the notch: click », wait for macOS to lay the hidden icons out, press it, and hide them again
    /// once its menu closes.
    private func open(_ extra: MenuBarExtra) {
        openTask?.cancel()
        openTask = Task { [weak self] in
            guard let overflow = MenuBarExtras.overflowButton(), MenuBarExtras.isStacked(extra.frame, overflow: overflow) else {
                return MenuBarExtras.open(extra)
            }
            MenuBarExtras.click(at: CGPoint(x: overflow.midX, y: overflow.midY))
            for _ in 0..<Self.layoutPolls {
                try? await Task.sleep(for: Self.layoutPoll)
                if let frame = MenuBarExtras.frame(of: extra.element), !MenuBarExtras.isStacked(frame, overflow: overflow) { break }
            }
            guard !Task.isCancelled else { return }
            MenuBarExtras.open(extra)
            self?.takePictures(of: MenuBarExtras.all(), overflow: overflow)
            await self?.hideAgain(after: extra, overflow: overflow)
        }
    }

    /// Hides the icons again once the opened menu closes, as if Drawer had never shown them.
    private func hideAgain(after extra: MenuBarExtra, overflow: CGRect) async {
        var menuSeen = false, quiet = 0
        for poll in 0..<Self.menuPolls {
            try? await Task.sleep(for: Self.menuPoll)
            if Task.isCancelled { return }
            if MenuBarExtras.hasOpenMenu(extra.app) {
                menuSeen = true
                quiet = 0
            } else {
                quiet += 1
            }
            // Twice in a row, so the moment between a menu and its submenu doesn't count as closed.
            if menuSeen ? quiet >= 2 : poll >= Self.noMenuPolls { break }
        }
        // Only if they still show: you may have clicked » yourself in the meantime.
        guard let frame = MenuBarExtras.frame(of: extra.element), !MenuBarExtras.isStacked(frame, overflow: overflow),
              let button = MenuBarExtras.overflowButton() else { return }
        MenuBarExtras.click(at: CGPoint(x: button.midX, y: button.midY))
    }

    /// With Screen Recording, pictures of the icons that show right now, so the bar can show the real icons later.
    private func takePictures(of extras: [MenuBarExtra], overflow: CGRect?) {
        guard MenuBarExtras.canPicture, MenuBarExtras.canRead else { return }
        Task { [weak self] in
            try? await Task.sleep(for: Self.pictureDelay)
            // Read the frames again: the icons have moved since the list was made.
            let showing = MenuBarExtras.all().filter { extra in overflow.map { !MenuBarExtras.isStacked(extra.frame, overflow: $0) } ?? true }
            self?.keep(await MenuBarExtras.pictures(of: showing))
        }
    }

    // MARK: Menu

    private func menuItems() -> [NSMenuItem] {
        let show = NSMenuItem(bar.isShown ? "Hide Drawer Bar" : "Show Drawer Bar", symbol: "rectangle.topthird.inset.filled") { [unowned self] in
            toggleBar()
        }
        // Shown beside the item, like any menu shortcut. The global hotkey does the actual work.
        show.keyEquivalent = "b"
        show.keyEquivalentModifierMask = [.control, .option]
        var items = [show, .separator()]
        if !MenuBarExtras.canRead {
            items.append(NSMenuItem("Allow Accessibility…", symbol: "lock.open") { MenuBarExtras.requestReading() })
        }
        if !MenuBarExtras.canPicture {
            items.append(NSMenuItem("Show Real Icons (Screen Recording)…", symbol: "photo") { MenuBarExtras.requestPicturing() })
        }
        items += [
            setting("Show Every Icon in the Bar", Key.showAll),
            NSMenuItem("Menu Bar Appearance…", symbol: "paintpalette") { [unowned self] in appearance.showSettings() },
            .submenu("Icon Spacing", symbol: "arrow.left.and.right", IconSpacing.allCases.map { spacing in
                let item = NSMenuItem(spacing.title) { spacing.apply() }
                item.state = IconSpacing.current == spacing ? .on : .off
                return item
            } + [.separator(), .label("Apps pick it up as they reopen; log out for all")]),
        ]
        return items
    }

    private func setting(_ title: String, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title) { [unowned self] in defaults.set(!defaults.bool(forKey: key), forKey: key) }
        item.state = defaults.bool(forKey: key) ? .on : .off
        return item
    }

    /// Drawer's menus, for the moments it's in front: while the bar's search field has focus, ⌘V and friends only
    /// work through an Edit menu.
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
