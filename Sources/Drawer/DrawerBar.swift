import AppKit
import SwiftUI

/// The hidden icons in a strip that drops down from Drawer's chevron, like a second menu bar: one row of icons,
/// wrapping only when there are many. Typing searches every menu bar icon, hidden or not; Return opens the first.
@MainActor
final class DrawerBar: NSObject {
    nonisolated static let cell = CGSize(width: 32, height: 26)
    nonisolated static let spacing: CGFloat = 4
    nonisolated static let maxColumns = 14
    nonisolated static let padding: CGFloat = 8
    /// The search field above the icons, and the gap under it.
    private nonisolated static let searchHeight: CGFloat = 30
    /// Wide enough for the search field when only a few icons are hidden.
    private nonisolated static let minWidth: CGFloat = 240
    /// Room for the search field and the permission prompt, before Drawer may read the menu bar.
    private static let permissionSize = CGSize(width: 340, height: 140)
    private static let gapBelowMenuBar: CGFloat = 4

    let model = BarModel()
    private lazy var panel: NSPanel = makePanel()
    private let closed: () -> Void

    var isShown: Bool { panel.isVisible }

    init(open: @escaping (MenuBarExtra) -> Void, closed: @escaping () -> Void) {
        self.closed = closed
        super.init()
        model.open = { [weak self] extra in
            self?.close()
            open(extra)
        }
        model.close = { [weak self] in self?.close() }
    }

    /// Shows the bar under the menu bar, its right edge lined up with `anchor` (the chevron's frame on screen).
    func show(extras: [MenuBarExtra], hidden: Set<String>, under anchor: NSRect) {
        model.query = ""
        model.canRead = MenuBarExtras.canRead
        model.all = extras
        model.hiddenIDs = hidden
        let size = model.canRead ? Self.size(for: hidden.count) : Self.permissionSize
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let top = (screen?.visibleFrame.maxY ?? anchor.minY) - Self.gapBelowMenuBar
        let right = min(anchor.maxX, screen?.frame.maxX ?? anchor.maxX)
        panel.setFrame(NSRect(x: right - size.width, y: top - size.height, width: size.width, height: size.height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusSearch = true
    }

    /// One row per `maxColumns` icons; with none, room for the one-line message instead.
    nonisolated static func size(for icons: Int) -> CGSize {
        let columns = min(max(icons, 1), maxColumns)
        let rows = max(1, Int((Double(icons) / Double(maxColumns)).rounded(.up)))
        let width = CGFloat(columns) * cell.width + CGFloat(columns - 1) * spacing + 2 * padding
        let height = searchHeight + CGFloat(rows) * cell.height + CGFloat(rows - 1) * spacing + 2 * padding
        return CGSize(width: max(width, minWidth), height: height)
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        closed()
    }

    private func makePanel() -> NSPanel {
        let panel = BarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: BarView(model: model))
        // The bar's size is set in `show`; left to itself, SwiftUI grows the panel to fit long text.
        host.sizingOptions = []
        panel.contentView = host
        panel.delegate = self
        return panel
    }
}

extension DrawerBar: NSWindowDelegate {
    /// Clicking anywhere else closes the bar, like a menu.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// Borderless panels can't take typing unless they say so.
private final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class BarModel: ObservableObject {
    @Published var query = ""
    @Published var all: [MenuBarExtra] = []
    @Published var hiddenIDs: Set<String> = []
    /// Pictures of the icons, taken while they showed. Missing ones fall back to the app's icon.
    @Published var pictures: [String: NSImage] = [:]
    @Published var focusSearch = false
    /// Whether Drawer has Accessibility permission, checked each time the bar opens.
    @Published var canRead = true
    var open: (MenuBarExtra) -> Void = { _ in }
    var close: () -> Void = {}

    /// The hidden icons, or with a search, every icon whose title or app matches.
    var shown: [MenuBarExtra] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all.filter { hiddenIDs.contains($0.id) } }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.appName.localizedCaseInsensitiveContains(query) }
    }
}

struct BarView: View {
    @ObservedObject var model: BarModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search menu bar", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .focused($searchFocused)
                .onSubmit { model.shown.first.map(model.open) }
            if !model.canRead {
                permissionPrompt
            } else if model.shown.isEmpty {
                Text(model.query.isEmpty ? "Everything fits in the menu bar." : "No menu bar icon matches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                let columns = Array(repeating: GridItem(.fixed(DrawerBar.cell.width), spacing: DrawerBar.spacing),
                                    count: min(model.shown.count, DrawerBar.maxColumns))
                LazyVGrid(columns: columns, alignment: .trailing, spacing: DrawerBar.spacing) {
                    ForEach(model.shown) { extra in
                        Button { model.open(extra) } label: { picture(of: extra) }
                            .buttonStyle(IconButtonStyle())
                            .help("\(extra.appName): \(extra.title)")
                            .accessibilityLabel("\(extra.appName): \(extra.title)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(DrawerBar.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onExitCommand { model.close() }
        .onChange(of: model.focusSearch) { _, focus in
            if focus {
                searchFocused = true
                model.focusSearch = false
            }
        }
    }

    /// The real icon when there's a picture of it, otherwise the app's icon, small, the way a menu bar icon is.
    private func picture(of extra: MenuBarExtra) -> some View {
        Group {
            if let picture = model.pictures[MenuBarExtras.pictureKey(extra)] {
                Image(nsImage: picture).renderingMode(picture.isTemplate ? .template : .original)
                    .resizable().aspectRatio(contentMode: .fit).foregroundStyle(.primary)
            } else {
                Image(nsImage: extra.app.icon ?? NSImage()).resizable().aspectRatio(contentMode: .fit).padding(3)
            }
        }
        .frame(width: DrawerBar.cell.width, height: DrawerBar.cell.height)
    }

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To list and open other apps' menu bar icons, Drawer needs Accessibility permission. Screen Recording is optional: it lets the bar show the real icons.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Allow Accessibility…") { MenuBarExtras.requestReading() }
                Button("Allow Screen Recording…") { MenuBarExtras.requestPicturing() }
            }
        }
    }
}

/// A menu bar icon's highlight: nothing until the pointer is over it, then a soft rounded square, darker when pressed.
private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration)
    }

    private struct IconButton: View {
        let configuration: ButtonStyleConfiguration
        // An ObservableObject rather than @State, which needs Xcode's macro plugins on the macOS 27 SDK (AGENTS.md).
        @StateObject private var hover = Hover()

        var body: some View {
            configuration.label
                .background(.primary.opacity(configuration.isPressed ? 0.18 : hover.isOver ? 0.1 : 0),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .onHover { hover.isOver = $0 }
        }
    }

    private final class Hover: ObservableObject {
        @Published var isOver = false
    }
}
