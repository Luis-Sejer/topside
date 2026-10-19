import AppKit
import SwiftUI

/// The hidden icons in a panel under the menu bar, like Ice Bar and Bartender Bar, so they never have to squeeze into
/// the menu bar or hide behind the notch. Typing searches every menu bar icon, hidden or not; Return opens the first.
@MainActor
final class DrawerBar: NSObject {
    private static let width: CGFloat = 380
    private static let columns = 9
    private static let rowHeight: CGFloat = 40
    /// The search field, the padding and the hint line under the icons.
    private static let chrome: CGFloat = 96
    private static let gapBelowMenuBar: CGFloat = 6

    let model = BarModel()
    private lazy var panel: NSPanel = makePanel()

    var isShown: Bool { panel.isVisible }

    init(open: @escaping (MenuBarExtra) -> Void) {
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
        let rows = max(1, Int(ceil(Double(max(hidden.count, 1)) / Double(Self.columns))))
        let height = Self.chrome + CGFloat(rows) * Self.rowHeight
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let top = (screen?.visibleFrame.maxY ?? anchor.minY) - Self.gapBelowMenuBar
        let right = min(anchor.maxX, screen?.frame.maxX ?? anchor.maxX)
        panel.setFrame(NSRect(x: right - Self.width, y: top - height, width: Self.width, height: height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusSearch = true
    }

    func close() {
        panel.orderOut(nil)
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
        panel.contentView = NSHostingView(rootView: BarView(model: model))
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
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search menu bar", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { model.shown.first.map(model.open) }
            if !model.canRead {
                permissionPrompt
            } else if model.shown.isEmpty {
                Text(model.query.isEmpty ? "No hidden icons. ⌘-drag icons left of │ to hide them." : "No menu bar icon matches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 9), alignment: .leading, spacing: 6) {
                    ForEach(model.shown) { extra in
                        Button { model.open(extra) } label: { picture(of: extra) }
                            .buttonStyle(.plain)
                            .help("\(extra.appName): \(extra.title)")
                            .accessibilityLabel("\(extra.appName): \(extra.title)")
                    }
                }
            }
            Spacer(minLength: 0)
            Text(model.query.isEmpty ? "Click an icon to open it. Type to search every icon." : "Return opens the first match.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onExitCommand { model.close() }
        .onChange(of: model.focusSearch) { _, focus in
            if focus {
                searchFocused = true
                model.focusSearch = false
            }
        }
    }

    private func picture(of extra: MenuBarExtra) -> some View {
        Group {
            if let picture = model.pictures[MenuBarExtras.pictureKey(extra)] {
                Image(nsImage: picture).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: extra.app.icon ?? NSImage()).resizable().aspectRatio(contentMode: .fit).padding(4)
            }
        }
        .frame(width: 34, height: 30)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
