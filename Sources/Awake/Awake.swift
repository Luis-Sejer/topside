import AppKit
import IOKit.pwr_mgt
import Kit

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
        return menu
    }

    private func turnOn(minutes: Int?) {
        if assertion == nil {
            var id = IOPMAssertionID(0)
            let status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Awake is keeping the Mac awake" as CFString, &id)
            guard status == kIOReturnSuccess else {
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
