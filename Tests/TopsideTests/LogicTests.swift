import AppKit
import Testing
@testable import Drawer
@testable import Pipette
@testable import Scrub
@testable import Upnext
@testable import Week
@testable import Zones

@Test func scrubRemovesTrackingAndKeepsTheRest() {
    #expect(LinkCleaner.clean("https://example.com/a?utm_source=x&utm_medium=y&id=7#top") == "https://example.com/a?id=7#top")
    #expect(LinkCleaner.clean("https://example.com/?fbclid=abc") == "https://example.com/")
    #expect(LinkCleaner.clean("  https://youtu.be/dQw4w9WgXcQ?si=abc123\n") == "https://youtu.be/dQw4w9WgXcQ")
    #expect(LinkCleaner.clean("https://www.youtube.com/watch?v=abc&si=x") == "https://www.youtube.com/watch?v=abc")
    // "t" is a timestamp on YouTube, tracking only on X.
    #expect(LinkCleaner.clean("https://www.youtube.com/watch?v=abc&t=42") == nil)
    #expect(LinkCleaner.clean("https://x.com/user/status/1?s=20&t=abc") == "https://x.com/user/status/1")
    // Percent-encoding survives untouched.
    #expect(LinkCleaner.clean("https://example.com/search?q=a%20b&gclid=1") == "https://example.com/search?q=a%20b")
}

@Test func scrubLeavesNonLinksAlone() {
    #expect(LinkCleaner.clean("https://example.com/?id=1") == nil)
    #expect(LinkCleaner.clean("read https://example.com/?utm_source=x now") == nil)
    #expect(LinkCleaner.clean("mailto:a@b.dk?utm_source=x") == nil)
    #expect(LinkCleaner.clean("just text") == nil)
}

@Test func upnextFindsMeetingLinks() {
    let teams = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d"
    #expect(MeetingLink.find(in: [nil, "Room 4", "Join: <\(teams)>"])?.absoluteString == teams)
    #expect(MeetingLink.find(in: [nil, "https://us02web.zoom.us/j/123?pwd=x.", nil])?.absoluteString == "https://us02web.zoom.us/j/123?pwd=x")
    #expect(MeetingLink.find(in: ["https://meet.google.com/abc-defg-hij"])?.host == "meet.google.com")
    // Links to other sites, even look-alike hosts, aren't meetings.
    #expect(MeetingLink.find(in: ["https://example.com/agenda", "Agenda: https://notzoom.us/j/1"]) == nil)
}

@Test func upnextCountsDownInWholeMinutes() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(Upnext.countdown(to: now.addingTimeInterval(3 * 60 + 10), now: now) == "in 4 min")
    #expect(Upnext.countdown(to: now, now: now) == "now")
    #expect(Upnext.countdown(to: now.addingTimeInterval(-60), now: now) == "now")
}

@Test func pipetteFormats() {
    let color = RGB(red: 0, green: 113, blue: 227)
    #expect(color.hex == "#0071E3")
    #expect(RGB(hex: "#0071e3") == color)
    #expect(RGB(hex: "0071E3") == color)
    #expect(RGB(hex: "#123") == nil)
    #expect(color.rgb == "rgb(0, 113, 227)")
    #expect(color.swiftUI == "Color(red: 0.000, green: 0.443, blue: 0.890)")
}

@Test func weekUsesISOWeeks() throws {
    let calendar = Calendar.iso8601
    let firstOfJanuary2027 = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
    // 1 January 2027 is a Friday, so it still belongs to week 53 of 2026.
    #expect(Week.label(for: firstOfJanuary2027, danish: true) == "Uge 53")
    let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3)))
    #expect(Week.label(for: today, danish: false) == "W40")
    // October 2026 starts on a Thursday and ends on a Saturday: weeks 40 to 44.
    let weeks = calendar.weekStarts(inMonthOf: today).map { calendar.component(.weekOfYear, from: $0) }
    #expect(weeks == [40, 41, 42, 43, 44])
}

@Test func zonesOffsets() throws {
    let copenhagen = try #require(TimeZone(identifier: "Europe/Copenhagen"))
    let summer = Date(timeIntervalSince1970: 1_782_000_000) // June 2026
    #expect(Zones.offset(of: try #require(TimeZone(identifier: "America/New_York")), at: summer, local: copenhagen) == "−6 h")
    #expect(Zones.offset(of: try #require(TimeZone(identifier: "Asia/Kolkata")), at: summer, local: copenhagen) == "+3.5 h")
    #expect(Zones.offset(of: copenhagen, at: summer, local: copenhagen) == "same time")
    #expect(Zones.city(try #require(TimeZone(identifier: "America/Argentina/Buenos_Aires"))) == "Buenos Aires")
}

@Test func drawerTellsHiddenIconsFromShownOnes() {
    // Measured on a MacBook Pro with a notch on macOS 27: the » button, an icon stacked behind it, the same icon laid
    // out left of the notch while the hidden icons show, and the first icon that fits.
    let overflow = CGRect(x: 1008, y: 1, width: 17.5, height: 30)
    let stacked = CGRect(x: 991, y: 4, width: 34, height: 26)
    let laidOut = CGRect(x: 550, y: 4, width: 34, height: 26)
    let shown = CGRect(x: 1032, y: 4, width: 51, height: 26)
    #expect(MenuBarExtras.isHidden(stacked, overflow: overflow))
    #expect(MenuBarExtras.isHidden(laidOut, overflow: overflow))
    #expect(!MenuBarExtras.isHidden(shown, overflow: overflow))
    #expect(!MenuBarExtras.isHidden(stacked, overflow: nil)) // everything fits: no button, nothing hidden
    #expect(MenuBarExtras.isStacked(stacked, overflow: overflow))
    #expect(!MenuBarExtras.isStacked(laidOut, overflow: overflow))
    #expect(!MenuBarExtras.isStacked(shown, overflow: overflow))
}

@Test func drawerBarIsOneRowUntilItWraps() {
    let one = DrawerBar.size(for: 3), full = DrawerBar.size(for: DrawerBar.maxColumns), wrapped = DrawerBar.size(for: DrawerBar.maxColumns + 1)
    #expect(one.width == 240) // the search field's minimum
    #expect(full.height == one.height)
    #expect(wrapped.width == full.width)
    #expect(wrapped.height == full.height + DrawerBar.cell.height + DrawerBar.spacing)
    #expect(DrawerBar.size(for: 0).height == one.height) // room for "Everything fits"
}

@Test func drawerFindsIconsInTheMenuBar() {
    // A MacBook screen with a 33 pt menu bar, and a display to its right whose top lines up with it.
    let screens = [(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), barHeight: CGFloat(33)),
                   (frame: CGRect(x: 1512, y: -98, width: 1920, height: 1080), barHeight: CGFloat(24))]
    #expect(MenuBarExtras.isInMenuBar(CGRect(x: 1300, y: 0, width: 26, height: 33), screens: screens))
    #expect(MenuBarExtras.isInMenuBar(CGRect(x: 2000, y: 0, width: 30, height: 24), screens: screens))
    // A placeholder macOS keeps below the bottom of the main screen.
    #expect(!MenuBarExtras.isInMenuBar(CGRect(x: 0, y: 982, width: 26, height: 33), screens: screens))
    #expect(!MenuBarExtras.isInMenuBar(CGRect(x: 2000, y: 300, width: 30, height: 24), screens: screens))
}

@Test func drawerCutsIconPicturesFromTheCapture() {
    let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    #expect(MenuBarExtras.pixelRect(of: CGRect(x: 1300, y: 0, width: 26, height: 33), inBarOf: main, mainHeight: 982, scale: 2)
        == CGRect(x: 2600, y: 0, width: 52, height: 66))
    let side = CGRect(x: 1512, y: -98, width: 1920, height: 1080)
    #expect(MenuBarExtras.pixelRect(of: CGRect(x: 2000, y: 0, width: 30, height: 24), inBarOf: side, mainHeight: 982, scale: 1)
        == CGRect(x: 488, y: 0, width: 30, height: 24))
}

@Test func drawerBarSearchesEveryIcon() {
    let app = NSRunningApplication.current
    let element = AXUIElementCreateApplication(getpid())
    let model = BarModel()
    model.all = [
        MenuBarExtra(id: "a", app: app, element: element, frame: .zero, title: "Wi-Fi"),
        MenuBarExtra(id: "b", app: app, element: element, frame: .zero, title: "Battery"),
        MenuBarExtra(id: "c", app: app, element: element, frame: .zero, title: "W40"),
    ]
    model.hiddenIDs = ["b"]
    #expect(model.shown.map(\.id) == ["b"])
    model.query = "w"
    #expect(model.shown.map(\.id) == ["a", "c"])
    model.query = "  battery "
    #expect(model.shown.map(\.id) == ["b"])
}

@Test func drawerShapesTheMenuBar() {
    let notch: ClosedRange<CGFloat> = 664...848
    #expect(MenuBarOverlay.sections(for: .fullWidth, width: 1512, notch: notch) == [0...1512])
    #expect(MenuBarOverlay.sections(for: .rounded, width: 1512, notch: notch) == [4...1508])
    #expect(MenuBarOverlay.sections(for: .split, width: 1512, notch: notch) == [4...656, 856...1508])
    #expect(MenuBarOverlay.sections(for: .split, width: 1920, notch: nil) == [4...1916])
}

@Test func drawerKeepsTheMenuBarStyle() throws {
    #expect(!MenuBarStyle().isVisible)
    var style = MenuBarStyle()
    style.fill = .gradient
    style.shape = .split
    style.border = true
    let saved = try JSONEncoder().encode(style)
    #expect(try JSONDecoder().decode(MenuBarStyle.self, from: saved) == style)
    #expect(style.isVisible)
}

@Test func drawerCutsIconsOutOfTheMenuBar() throws {
    // A white square on the dark grey a menu bar can have behind it, 10 × 10 pixels with the square in the middle.
    let context = try #require(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.22, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 3, y: 3, width: 4, height: 4))
    let square = try #require(context.makeImage())
    let picture = try #require(MenuBarExtras.cutOut(square))
    let pixels = try #require(picture.dataProvider?.data as Data?)
    let alpha = { (x: Int, y: Int) in pixels[(y * picture.bytesPerRow) + x * 4 + 3] }
    #expect(alpha(5, 5) == 255)
    #expect(alpha(0, 0) == 0)
    #expect(MenuBarExtras.isMonochrome(picture))
}
