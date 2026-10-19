import AppKit
import EventKit
import Kit

@main
enum Main {
    @MainActor static func main() { Kit.run { Upnext() } }
}

/// "Standup in 4 min" in the menu bar, and the meeting's Teams, Zoom or Meet link one click away.
/// Reads Calendar through EventKit, so no accounts and no backend.
@MainActor
final class Upnext {
    /// Further away than this, the menu bar shows only the icon.
    private static let countdownWindow: TimeInterval = 60 * 60
    private static let lookAhead: TimeInterval = 36 * 60 * 60
    private static let titleLimit = 20
    private static let menuLimit = 8
    /// The menu bar counts in minutes, so a check twice a minute is plenty.
    private static let refreshInterval: TimeInterval = 30

    private let store = EKEventStore()
    private lazy var item = MenuBarItem(name: "Upnext", symbol: "calendar.badge.clock", click: .menu { [unowned self] in menu() })
    private var timer: Timer?
    private var changeObserver: Any?

    init() {
        _ = item
        Task { await requestAccess() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    private func requestAccess() async {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        refresh()
    }

    /// Timed events that haven't ended, soonest first. All-day events are never "in 4 min".
    private func upcoming(now: Date = Date()) -> [EKEvent] {
        guard hasAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-Self.lookAhead), end: now.addingTimeInterval(Self.lookAhead), calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
    }

    private func refresh() {
        let now = Date()
        guard let next = upcoming(now: now).first, next.startDate.timeIntervalSince(now) < Self.countdownWindow else {
            item.setTitle("")
            return
        }
        item.setTitle("\(Self.shortTitle(next)) \(Self.countdown(to: next.startDate, now: now))")
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        guard hasAccess else {
            menu.addItem(.label("Upnext needs access to your calendar."))
            menu.addItem(NSMenuItem("Open Privacy Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            })
            return menu
        }
        let events = upcoming().prefix(Self.menuLimit)
        if events.isEmpty { menu.addItem(.label("Nothing coming up")) }
        for event in events {
            let time = "\(event.startDate.formatted(date: .omitted, time: .shortened))–\(event.endDate.formatted(date: .omitted, time: .shortened))"
            let day = Calendar.current.isDateInToday(event.startDate) ? "" : " · \(event.startDate.formatted(.dateTime.weekday(.abbreviated)))"
            let link = MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
            let item = NSMenuItem("\(time)\(day)  \(event.title ?? "Untitled")", symbol: link == nil ? nil : "video.fill") {
                if let link { NSWorkspace.shared.open(link) }
            }
            item.isEnabled = link != nil
            menu.addItem(item)
        }
        return menu
    }

    private static func shortTitle(_ event: EKEvent) -> String {
        let title = event.title ?? "Meeting"
        return title.count > titleLimit ? String(title.prefix(titleLimit - 1)) + "…" : title
    }

    nonisolated static func countdown(to start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= 0 ? "now" : "in \(minutes) min"
    }
}

/// Finds the video call link in an event's URL, location or notes.
enum MeetingLink {
    /// Hosts of the call services people paste into invites. Subdomains count, as in us02web.zoom.us.
    private static let hosts = ["teams.microsoft.com", "teams.live.com", "zoom.us", "meet.google.com", "webex.com", "whereby.com", "facetime.apple.com"]
    private static let urlPattern = try! NSRegularExpression(pattern: #"https?://[^\s<>"']+"#)
    /// Punctuation that ends a sentence rather than the link.
    private static let trailing = CharacterSet(charactersIn: ".,;:!?)]")

    static func find(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in urlPattern.matches(in: text, range: range) {
                guard let swiftRange = Range(match.range, in: text) else { continue }
                let candidate = String(text[swiftRange]).trimmingCharacters(in: trailing)
                if let url = URL(string: candidate), let host = url.host?.lowercased(),
                   hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    return url
                }
            }
        }
        return nil
    }
}
