import AppKit
import Kit

@main
enum Main {
    @MainActor static func main() { Kit.run { Pipette() } }
}

/// Click the icon, click any pixel on screen, and its hex code is on the clipboard.
/// Right-click lists recent colors to copy again as hex, RGB or SwiftUI.
@MainActor
final class Pipette {
    private static let recentsKey = "recentColors"
    private static let recentsLimit = 10

    private lazy var item = MenuBarItem(
        name: "Pipette",
        symbol: "eyedropper",
        click: .action { [unowned self] in pick() },
        menuItems: { [unowned self] in recentItems() }
    )
    private let sampler = NSColorSampler()

    private var recents: [RGB] {
        get { (UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []).compactMap(RGB.init(hex:)) }
        set { UserDefaults.standard.set(newValue.prefix(Self.recentsLimit).map(\.hex), forKey: Self.recentsKey) }
    }

    init() {
        _ = item
    }

    /// The system's magnifier; no Screen Recording permission needed.
    private func pick() {
        sampler.show { [weak self] color in
            // AppKit calls back on the main thread.
            MainActor.assumeIsolated {
                guard let self, let color = color.flatMap(RGB.init) else { return }
                self.recents = [color] + self.recents.filter { $0 != color }
                self.copy(color.hex)
            }
        }
    }

    private func copy(_ text: String) {
        Kit.copy(text)
        item.flash()
        Kit.announce("Copied \(text)")
    }

    private func recentItems() -> [NSMenuItem] {
        var items = [NSMenuItem("Pick a Color", symbol: "eyedropper") { [unowned self] in pick() }]
        guard !recents.isEmpty else { return items }
        items.append(.separator())
        for color in recents {
            let item = NSMenuItem.submenu(color.hex, [color.hex, color.rgb, color.swiftUI].map { text in
                NSMenuItem("Copy \(text)") { [unowned self] in copy(text) }
            })
            item.image = color.swatch
            items.append(item)
        }
        items.append(NSMenuItem("Clear Recent Colors") { [unowned self] in recents = [] })
        return items
    }
}

/// An sRGB color in 0–255 steps, the precision designers copy colors in.
struct RGB: Equatable {
    let red: Int, green: Int, blue: Int

    init(red: Int, green: Int, blue: Int) {
        (self.red, self.green, self.blue) = (red, green, blue)
    }

    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        func step(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        self.init(red: step(srgb.redComponent), green: step(srgb.greenComponent), blue: step(srgb.blueComponent))
    }

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init(red: value >> 16 & 0xFF, green: value >> 8 & 0xFF, blue: value & 0xFF)
    }

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    var rgb: String { "rgb(\(red), \(green), \(blue))" }
    var swiftUI: String {
        func unit(_ value: Int) -> String { String(format: "%.3f", Double(value) / 255) }
        return "Color(red: \(unit(red)), green: \(unit(green)), blue: \(unit(blue)))"
    }

    var swatch: NSImage {
        let color = NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        return NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            color.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            return true
        }
    }
}
