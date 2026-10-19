import AppKit
import SwiftUI

/// How the menu bar looks: a tint behind it, its shape, a border and a shadow, like Bartender's and Ice's styles.
struct MenuBarStyle: Codable, Equatable {
    enum Fill: String, Codable, CaseIterable { case none, solid, gradient }
    enum Shape: String, Codable, CaseIterable { case fullWidth, rounded, split }

    var fill = Fill.none
    var color = RGBA(red: 0, green: 0.443, blue: 0.890, alpha: 0.35)
    var gradientEnd = RGBA(red: 0.686, green: 0.322, blue: 0.871, alpha: 0.35)
    var shape = Shape.fullWidth
    var border = false
    var borderColor = RGBA(red: 1, green: 1, blue: 1, alpha: 0.5)
    var borderWidth: Double = 1
    var shadow = false

    var isVisible: Bool { fill != .none || border || shadow }
}

/// A color that can be saved. sRGB, 0–1.
struct RGBA: Codable, Equatable {
    var red, green, blue, alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }

    init(_ color: Color) {
        let srgb = NSColor(color).usingColorSpace(.sRGB) ?? .clear
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// Draws the style behind every screen's menu bar. The overlay sits one level below the menu bar and lets clicks
/// through, so the menu bar's own text and icons draw on top of it.
@MainActor
final class Appearance: ObservableObject {
    private static let defaultsKey = "menuBarStyle"
    /// Room under the menu bar for the shadow to fall into.
    private static let shadowRoom: CGFloat = 12

    @Published var style: MenuBarStyle {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(style), forKey: Self.defaultsKey)
            redraw()
        }
    }

    private var overlays: [NSWindow] = []
    private var screenObserver: Any?
    private lazy var settingsWindow = makeSettingsWindow()

    init() {
        style = UserDefaults.standard.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(MenuBarStyle.self, from: $0) } ?? MenuBarStyle()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.redraw() }
        }
        redraw()
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    /// One overlay per screen, rebuilt when screens or the style change. Nothing is drawn while the style is plain.
    private func redraw() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        guard style.isVisible else { return }
        for screen in NSScreen.screens {
            let height = MenuBarExtras.menuBarHeight(of: screen)
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height - Self.shadowRoom, width: screen.frame.width, height: height + Self.shadowRoom)
            // The notch as a range across the menu bar, for the split shape.
            let notch: ClosedRange<CGFloat>? = {
                guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
                return (left.maxX - screen.frame.minX)...(right.minX - screen.frame.minX)
            }()
            let window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
            // Every desktop, but not full-screen apps, whose menu bar hides.
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: MenuBarOverlay(style: style, barHeight: height, notch: notch))
            window.orderFrontRegardless()
            overlays.append(window)
        }
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: AppearanceSettings(appearance: self)))
        window.title = "Menu Bar Appearance"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

/// macOS moves windows out from under the menu bar; this one has to sit exactly there.
private final class OverlayWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

struct MenuBarOverlay: View {
    let style: MenuBarStyle
    let barHeight: CGFloat
    let notch: ClosedRange<CGFloat>?

    /// Gaps around the rounded and split shapes, so they read as shapes rather than the menu bar's edge.
    private static let inset: CGFloat = 4
    private static let notchGap: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.sections(for: style.shape, width: geometry.size.width, notch: notch).enumerated()), id: \.offset) { _, section in
                    piece(width: section.upperBound - section.lowerBound)
                        .offset(x: section.lowerBound, y: style.shape == .fullWidth ? 0 : Self.inset / 2)
                }
            }
        }
    }

    /// Where the shapes go, left to right. Split leaves the notch out; without a notch it matches rounded.
    nonisolated static func sections(for shape: MenuBarStyle.Shape, width: CGFloat, notch: ClosedRange<CGFloat>?) -> [ClosedRange<CGFloat>] {
        switch shape {
        case .fullWidth:
            return [0...width]
        case .rounded:
            return [Self.inset...(width - Self.inset)]
        case .split:
            guard let notch else { return [Self.inset...(width - Self.inset)] }
            return [Self.inset...(notch.lowerBound - Self.notchGap), (notch.upperBound + Self.notchGap)...(width - Self.inset)]
        }
    }

    private func piece(width: CGFloat) -> some View {
        let height = style.shape == .fullWidth ? barHeight : barHeight - Self.inset
        let corner = style.shape == .fullWidth ? 0 : height / 2
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return shape
            .fill(fill)
            .overlay(style.border ? shape.strokeBorder(style.borderColor.color, lineWidth: style.borderWidth) : nil)
            .frame(width: max(width, 0), height: height)
            .shadow(color: style.shadow ? .black.opacity(0.35) : .clear, radius: 5, y: 3)
    }

    private var fill: AnyShapeStyle {
        switch style.fill {
        case .none: return AnyShapeStyle(Color.clear)
        case .solid: return AnyShapeStyle(style.color.color)
        case .gradient: return AnyShapeStyle(LinearGradient(colors: [style.color.color, style.gradientEnd.color], startPoint: .leading, endPoint: .trailing))
        }
    }
}

struct AppearanceSettings: View {
    @ObservedObject var appearance: Appearance

    var body: some View {
        Form {
            Picker("Tint", selection: $appearance.style.fill) {
                Text("None").tag(MenuBarStyle.Fill.none)
                Text("Solid").tag(MenuBarStyle.Fill.solid)
                Text("Gradient").tag(MenuBarStyle.Fill.gradient)
            }
            if appearance.style.fill != .none {
                ColorPicker(appearance.style.fill == .gradient ? "From" : "Color", selection: color(\.color))
            }
            if appearance.style.fill == .gradient {
                ColorPicker("To", selection: color(\.gradientEnd))
            }
            Picker("Shape", selection: $appearance.style.shape) {
                Text("Full Width").tag(MenuBarStyle.Shape.fullWidth)
                Text("Rounded").tag(MenuBarStyle.Shape.rounded)
                Text("Split Around the Notch").tag(MenuBarStyle.Shape.split)
            }
            Toggle("Border", isOn: $appearance.style.border)
            if appearance.style.border {
                ColorPicker("Border Color", selection: color(\.borderColor))
                Stepper("Border Width: \(Int(appearance.style.borderWidth)) pt", value: $appearance.style.borderWidth, in: 1...4)
            }
            Toggle("Shadow", isOn: $appearance.style.shadow)
            Button("Reset to Plain") { appearance.style = MenuBarStyle() }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// ColorPicker works in SwiftUI colors; the style saves plain numbers.
    private func color(_ keyPath: WritableKeyPath<MenuBarStyle, RGBA>) -> Binding<Color> {
        Binding(get: { appearance.style[keyPath: keyPath].color },
                set: { appearance.style[keyPath: keyPath] = RGBA($0) })
    }
}
