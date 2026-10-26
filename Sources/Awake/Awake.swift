import AppKit
import IOKit.pwr_mgt
import Kit
import LocalAuthentication

@main
enum Main {
    @MainActor static func main() { Kit.run { Awake() } }
}

/// Keeps the Mac and its display awake for a while, or until turned off.
@MainActor
final class Awake {
    private static let durations: [(title: String, minutes: Int)] = [
        ("For 15 Minutes", 15), ("For 1 Hour", 60), ("For 2 Hours", 120), ("For 4 Hours", 240),
    ]

    private lazy var item = MenuBarItem(name: "Awake", symbol: "cup.and.saucer", click: .menu { [unowned self] in menu() })
    private var assertion: IOPMAssertionID?
    /// Nil while on means until turned off.
    private var until: Date?
    private var timer: Timer?
    private var curtain: Curtain?

    init() {
        _ = item
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        if assertion != nil {
            menu.addItem(.label(until.map { "Awake until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Awake until turned off"))
            menu.addItem(NSMenuItem("Turn Off", symbol: "moon") { [unowned self] in turnOff() })
            menu.addItem(.separator())
        }
        for duration in Self.durations {
            menu.addItem(NSMenuItem(duration.title) { [unowned self] in turnOn(minutes: duration.minutes) })
        }
        menu.addItem(NSMenuItem("Until Turned Off") { [unowned self] in turnOn(minutes: nil) })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem("Cover Screen", symbol: "eye.slash") { [unowned self] in coverScreen() })
        return menu
    }

    /// Nil when macOS refuses the assertion.
    fileprivate static func preventDisplaySleep(_ reason: String) -> IOPMAssertionID? {
        var id = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
        return status == kIOReturnSuccess ? id : nil
    }

    private func coverScreen() {
        guard curtain == nil else { return }
        curtain = Curtain { [unowned self] in curtain = nil }
        if curtain == nil { NSSound.beep() }
    }

    private func turnOn(minutes: Int?) {
        if assertion == nil {
            guard let id = Self.preventDisplaySleep("Awake is keeping the Mac awake") else {
                NSSound.beep()
                return
            }
            assertion = id
        }
        timer?.invalidate()
        until = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        if let minutes {
            timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.turnOff() }
            }
        }
        item.setSymbol("cup.and.saucer.fill")
    }

    /// The system also drops the assertion if Awake quits, so the Mac never stays awake by accident.
    private func turnOff() {
        timer?.invalidate()
        timer = nil
        until = nil
        if let assertion { IOPMAssertionRelease(assertion) }
        assertion = nil
        item.setSymbol("cup.and.saucer")
    }
}

/// Covers every screen and shuts out the keyboard and mouse while the Mac stays awake and signed in, so an agent can
/// keep working (and signing commits) while you step away. Touch ID or the login password lifts it. Holding the power
/// button only ends at the login window, and ⌃⌘Q still locks the Mac the usual way.
@MainActor
private final class Curtain {
    /// Hides the Dock and menu bar and blocks ⌘Tab, Force Quit and log out while the curtain is down.
    private static let kiosk: NSApplication.PresentationOptions = [
        .hideDock, .hideMenuBar, .disableProcessSwitching, .disableForceQuit, .disableSessionTermination, .disableHideApplication,
    ]
    /// Just under the Touch ID prompt, which macOS draws at the screen saver level, and above everything else.
    private static let level = NSWindow.Level(NSWindow.Level.screenSaver.rawValue - 1)

    private let assertion: IOPMAssertionID
    private let onLift: () -> Void
    private var windows: [CurtainWindow] = []
    private var authenticating = false

    /// Nil when the display can't be kept awake: it would sleep, and macOS would lock the Mac anyway.
    init?(onLift: @escaping () -> Void) {
        guard let assertion = Awake.preventDisplaySleep("Awake is covering the screen") else { return nil }
        self.assertion = assertion
        self.onLift = onLift
        // ponytail: one window per screen at the moment it covers; a display plugged in later stays uncovered.
        windows = NSScreen.screens.map { screen in
            let window = CurtainWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.level = Self.level
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.onInput = { [unowned self] in unlock() }
            let label = NSTextField(labelWithString: "Press any key to unlock")
            label.textColor = NSColor(white: 1, alpha: 0.35)
            label.translatesAutoresizingMaskIntoConstraints = false
            if let content = window.contentView {
                content.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                ])
            }
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = Self.kiosk
        windows.first?.makeKey()
        Kit.announce("Screen covered")
    }

    private func unlock() {
        guard !authenticating else { return }
        let context = LAContext()
        // A Mac without a login password has nothing to check against, and the curtain must never trap anyone.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return lift() }
        authenticating = true
        Task {
            let unlocked = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "uncover the screen")) ?? false
            authenticating = false
            if unlocked { lift() }
        }
    }

    private func lift() {
        NSApp.presentationOptions = []
        windows.forEach { $0.close() }
        windows = []
        IOPMAssertionRelease(assertion)
        Kit.announce("Screen uncovered")
        onLift()
    }
}

/// A borderless window that can take the keyboard and reports any key or click.
private final class CurtainWindow: NSWindow {
    var onInput: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onInput?() }
    override func mouseDown(with event: NSEvent) { onInput?() }
}
