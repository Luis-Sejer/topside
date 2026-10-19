import AppKit
import Kit
import SwiftUI

@main
enum Main {
    @MainActor static func main() { Kit.run { Shelf() } }
}

/// Drop files on the menu bar icon to park them, then drag them out wherever they're going next.
/// The shelf holds references, not copies, and forgets them when Shelf quits.
@MainActor
final class Shelf: NSObject {
    private let shelf = ShelfModel()
    private lazy var item = MenuBarItem(
        name: "Shelf",
        symbol: "tray",
        click: .popover(AnyView(ShelfView(shelf: shelf)), size: NSSize(width: 300, height: 340))
    )

    override init() {
        super.init()
        shelf.onChange = { [weak self] in self?.update() }
        // The status bar button can't be subclassed, but its window passes drag events on to its delegate.
        let window = item.statusItem.button?.window
        window?.registerForDraggedTypes([.fileURL])
        window?.delegate = self
        update()
    }

    private func update() {
        item.setSymbol(shelf.files.isEmpty ? "tray" : "tray.full")
        item.setTitle(shelf.files.isEmpty ? "" : "\(shelf.files.count)")
    }
}

extension Shelf: NSWindowDelegate, NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        item.setSymbol("tray.and.arrow.down.fill")
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        update()
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        shelf.add(urls)
        item.flash("tray.and.arrow.down.fill")
        return !urls.isEmpty
    }
}

final class ShelfModel: ObservableObject {
    @Published private(set) var files: [URL] = [] { didSet { onChange?() } }
    var onChange: (() -> Void)?

    func add(_ urls: [URL]) {
        files += urls.filter { !files.contains($0) }
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
    }

    func clear() {
        files = []
    }
}

struct ShelfView: View {
    @ObservedObject var shelf: ShelfModel

    var body: some View {
        VStack(spacing: 0) {
            if shelf.files.isEmpty {
                ContentUnavailableView("Shelf Is Empty", systemImage: "tray",
                                       description: Text("Drop files on the menu bar icon or here, then drag them out when you need them."))
            } else {
                List(shelf.files, id: \.self) { url in
                    row(url)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                Divider()
                HStack {
                    Text("Drag files out to use them").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { shelf.clear() }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls.filter(\.isFileURL))
            return true
        }
    }

    private func row(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button { shelf.remove(url) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(url.lastPathComponent)")
        }
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
    }
}
