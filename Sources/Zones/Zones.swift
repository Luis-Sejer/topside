import AppKit
import Kit

@main
enum Main {
    @MainActor static func main() { Kit.run { Zones() } }
}

/// What time it is for the people you work with. The menu lists their cities; one can sit in the menu bar.
@MainActor
final class Zones {
    private static let zonesKey = "zones"
    private static let pinnedKey = "pinned"
    /// The menu bar shows minutes, so a few checks a minute keep it on time without a timer per second.
    private static let refreshInterval: TimeInterval = 15

    private lazy var item = MenuBarItem(name: "Zones", symbol: "globe", click: .menu { [unowned self] in menu() })
    private var timer: Timer?

    private var zones: [TimeZone] {
        get { (UserDefaults.standard.stringArray(forKey: Self.zonesKey) ?? []).compactMap(TimeZone.init(identifier:)) }
        set { UserDefaults.standard.set(newValue.map(\.identifier), forKey: Self.zonesKey); refresh() }
    }

    /// The city shown in the menu bar, if any.
    private var pinned: String? {
        get { UserDefaults.standard.string(forKey: Self.pinnedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.pinnedKey); refresh() }
    }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        guard let pinned, let zone = TimeZone(identifier: pinned) else {
            item.setSymbol("globe")
            item.setTitle("")
            return
        }
        item.setSymbol(nil)
        item.setTitle("\(Self.city(zone)) \(Self.time(in: zone))")
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        if zones.isEmpty { menu.addItem(.label("Add the cities your team works in")) }
        for zone in zones {
            let title = "\(Self.city(zone))  \(Self.time(in: zone))  \(Self.offset(of: zone))"
            let show = NSMenuItem(title) { [unowned self] in pinned = pinned == zone.identifier ? nil : zone.identifier }
            show.state = pinned == zone.identifier ? .on : .off
            show.toolTip = "Click to show in the menu bar. Hold ⌥ to remove."
            menu.addItem(show)
            // Shown in place of the item above while ⌥ is held.
            let remove = NSMenuItem("Remove \(Self.city(zone))", symbol: "minus.circle") { [unowned self] in
                if pinned == zone.identifier { pinned = nil }
                zones.removeAll { $0 == zone }
            }
            remove.isAlternate = true
            remove.keyEquivalentModifierMask = .option
            menu.addItem(remove)
        }
        menu.addItem(.separator())
        menu.addItem(.submenu("Add City", symbol: "plus", cityItems()))
        return menu
    }

    /// Every time zone, grouped by region (Europe, America…), so adding a city needs no typing.
    private func cityItems() -> [NSMenuItem] {
        let byRegion = Dictionary(grouping: TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") }) { $0.components(separatedBy: "/")[0] }
        return byRegion.keys.sorted().map { region in
            .submenu(region, byRegion[region, default: []].sorted().compactMap(TimeZone.init(identifier:)).map { zone in
                let city = NSMenuItem(Self.city(zone)) { [unowned self] in
                    if !zones.contains(zone) { zones.append(zone) }
                }
                city.state = zones.contains(zone) ? .on : .off
                return city
            })
        }
    }

    /// "America/Argentina/Buenos_Aires" → "Buenos Aires".
    nonisolated static func city(_ zone: TimeZone) -> String {
        (zone.identifier.components(separatedBy: "/").last ?? zone.identifier).replacingOccurrences(of: "_", with: " ")
    }

    /// The time there, with the weekday when it's already tomorrow or still yesterday.
    nonisolated static func time(in zone: TimeZone, at date: Date = Date(), local: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        var there = Calendar.current
        there.timeZone = zone
        var here = Calendar.current
        here.timeZone = local
        guard there.component(.day, from: date) != here.component(.day, from: date) else { return date.formatted(style) }
        var weekday = Date.FormatStyle().weekday(.abbreviated)
        weekday.timeZone = zone
        return "\(date.formatted(weekday)) \(date.formatted(style))"
    }

    /// How far ahead or behind, like "+6 h" or "−5.5 h". Half-hour zones exist (India, Adelaide).
    nonisolated static func offset(of zone: TimeZone, at date: Date = Date(), local: TimeZone = .current) -> String {
        let seconds = zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
        guard seconds != 0 else { return "same time" }
        let hours = Double(abs(seconds)) / 3600
        let number = hours.rounded() == hours ? String(Int(hours)) : String(format: "%.1f", hours)
        return "\(seconds > 0 ? "+" : "−")\(number) h"
    }
}
