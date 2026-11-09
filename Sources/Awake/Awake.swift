import AppKit
import IOKit.pwr_mgt
import Kit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import SwiftUI

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

/// Blurs every screen and shuts out the keyboard and mouse while the Mac stays awake and signed in, so an agent can
/// keep working (and signing commits) while you step away. Touch ID or the login password lifts it. Holding the power
/// button only ends at the login window, and ⌃⌘Q still locks the Mac the usual way.
@MainActor
private final class Curtain {
    /// Hides the Dock and menu bar and blocks ⌘Tab, Force Quit and log out while the curtain is down.
    private static let kiosk: NSApplication.PresentationOptions = [
        .hideDock, .hideMenuBar, .disableProcessSwitching, .disableForceQuit, .disableSessionTermination, .disableHideApplication,
    ]
    /// Just under the password panel, which macOS draws at the screen saver level, and above everything else.
    private static let level = NSWindow.Level(NSWindow.Level.screenSaver.rawValue - 1)

    private let assertion: IOPMAssertionID
    private let onLift: () -> Void
    private let model: CurtainModel
    private let hasTouchID = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    private var windows: [CurtainWindow] = []
    /// The context behind the Touch ID glyph in the card; nil while it isn't listening.
    private var fingerContext: LAContext?
    private var authenticating = false

    /// Nil when the display can't be kept awake: it would sleep, and macOS would lock the Mac anyway.
    init?(onLift: @escaping () -> Void) {
        guard let assertion = Awake.preventDisplaySleep("Awake is covering the screen") else { return nil }
        self.assertion = assertion
        self.onLift = onLift
        model = CurtainModel(phase: hasTouchID ? .touchID : .password)
        // ponytail: one window per screen at the moment it covers; a display plugged in later stays uncovered.
        windows = NSScreen.screens.enumerated().map { index, screen in
            let window = CurtainWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = Self.level
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.onInput = { [unowned self] in unlockWithPassword() }
            // One context drives one glyph, so only the main screen's card listens for a finger.
            window.contentView = NSHostingView(rootView: CurtainView(model: model, listens: index == 0))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = Self.kiosk
        windows.first?.makeKey()
        if let screen = NSScreen.screens.first {
            CGWarpMouseCursorPosition(CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        }
        freezePointer(true)
        if hasTouchID { listenForFinger() }
        Kit.announce("Screen covered")
    }

    /// Touch ID inside the card: the glyph is macOS's own view, so the fingerprint never leaves macOS.
    private func listenForFinger() {
        let context = LAContext()
        fingerContext = context
        model.fingerView = LAAuthenticationView(context: context, controlSize: .small) // 32 pt, the lock's size; .large is 128
        Task {
            do {
                _ = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "uncover the screen")
                guard context === fingerContext else { return }
                open()
            } catch {
                guard context === fingerContext else { return } // cancelled for the password panel
                if (error as? LAError)?.code == .authenticationFailed {
                    model.phase = .retry
                    listenForFinger()
                } else {
                    // Locked out, or cancelled by macOS: a key brings up the password panel instead.
                    stopListening()
                    model.phase = .password
                }
            }
        }
    }

    private func stopListening() {
        let context = fingerContext
        fingerContext = nil
        model.fingerView = nil
        context?.invalidate()
    }

    /// Any key or click: macOS's own panel, which takes the login password (and Touch ID, where there is one).
    private func unlockWithPassword() {
        guard !authenticating, !model.phase.isUnlocked else { return }
        let context = LAContext()
        // A Mac without a login password has nothing to check against, and the curtain must never trap anyone.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return lift() }
        authenticating = true
        stopListening()
        model.phase = .password
        freezePointer(false) // the prompt's Use Password and Cancel buttons need the pointer
        Task {
            let unlocked = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "uncover the screen")) ?? false
            authenticating = false
            if unlocked { return open() }
            freezePointer(true)
            if hasTouchID {
                model.phase = .touchID
                listenForFinger()
            }
        }
    }

    /// The lock springs open, then the card and the blur fade away. Reduce Motion skips straight to the fade.
    private func open() {
        stopListening()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { model.phase = .unlocked }
        Kit.announce("Unlocked")
        Task {
            if !reduceMotion {
                try? await Task.sleep(for: Self.lockPause)
                model.phase = .open
                try? await Task.sleep(for: Self.openPause)
                withAnimation(.easeIn(duration: Self.fade)) { model.leaving = true }
            }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fade
                windows.forEach { $0.animator().alphaValue = 0 }
            }
            lift()
        }
    }

    private static let lockPause = Duration.milliseconds(150)
    private static let openPause = Duration.milliseconds(600)
    private static let fade = 0.3

    /// Hot corners still work under the kiosk options, and one set to Start Screen Saver locks the Mac when the screen
    /// saver ends. A frozen pointer can't reach a corner.
    private func freezePointer(_ frozen: Bool) {
        CGAssociateMouseAndMouseCursorPosition(frozen ? 0 : 1)
    }

    private func lift() {
        stopListening()
        NSApp.presentationOptions = []
        freezePointer(false)
        windows.forEach { $0.close() }
        windows = []
        IOPMAssertionRelease(assertion)
        Kit.announce("Screen uncovered")
        onLift()
    }
}

@MainActor
private final class CurtainModel: ObservableObject {
    enum Phase {
        case touchID, retry, password, unlocked, open
        var isUnlocked: Bool { self == .unlocked || self == .open }
    }

    @Published var phase: Phase
    @Published var fingerView: LAAuthenticationView?
    @Published var leaving = false

    init(phase: Phase) { self.phase = phase }
}

/// The desktop, blurred past reading and dimmed, under a glass card that says how to get back in.
private struct CurtainView: View {
    @ObservedObject var model: CurtainModel
    let listens: Bool

    var body: some View {
        ZStack {
            Blur().ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 10) {
                glyph
                    .frame(width: 56, height: 56)
                    .padding(.bottom, 6)
                Text("Privacy Mode Enabled")
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                if fingerListening {
                    Text("or press any key to use your password")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 32)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .scaleEffect(model.leaving ? 0.94 : 1)
            .accessibilityElement(children: .combine)
        }
        .environment(\.colorScheme, .dark)
    }

    private var fingerListening: Bool { model.phase == .touchID || model.phase == .retry }

    @ViewBuilder private var glyph: some View {
        if fingerListening, listens, let view = model.fingerView {
            FingerGlyph(view: view)
                .id(ObjectIdentifier(view)) // a new context comes with a new view
                .accessibilityLabel("Touch ID")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else {
            Image(systemName: model.phase == .open ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 34, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .touchID: "Touch ID to unlock"
        case .retry: "Try again"
        case .password: "Press any key to unlock"
        case .unlocked, .open: "Unlocked"
        }
    }
}

/// macOS's own Touch ID glyph, which shows the prompt for its context in place of the system panel.
private struct FingerGlyph: NSViewRepresentable {
    let view: LAAuthenticationView

    func makeNSView(context: Context) -> LAAuthenticationView { view }
    func updateNSView(_ view: LAAuthenticationView, context: Context) {}
}

/// What's behind the window, blurred by the window server; SwiftUI's own blur only reaches its own views.
private struct Blur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A borderless window that can take the keyboard and reports any key or click.
private final class CurtainWindow: NSWindow {
    var onInput: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onInput?() }
    override func mouseDown(with event: NSEvent) { onInput?() }
}
