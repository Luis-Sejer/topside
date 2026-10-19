import AppKit
import SwiftUI

/// This version's CHANGELOG section, shown once after an update (from Snicker). build.sh bundles it as whats-new.md.
public enum WhatsNew {
    static let changelogURL = URL(string: "https://github.com/Luis-Sejer/topside/blob/main/CHANGELOG.md")!
    private static let lastSeenKey = "lastSeenVersion"
    /// Every app carries the same notes, so updating them together should show them once, not eleven times.
    private static let suite = UserDefaults(suiteName: "dk.sejer.topside")
    private static let shownKey = "whatsNewShownVersion"
    @MainActor private static var window: NSWindow?

    /// Only after an update: a fresh install has nothing new to show. And only if no other app showed these notes.
    nonisolated static func shouldShow(version: String, lastSeen: String?, shown: String?) -> Bool {
        guard let lastSeen, Updater.isVersion(version, newerThan: lastSeen) else { return false }
        return shown.map { Updater.isVersion(version, newerThan: $0) } ?? true
    }

    @MainActor
    static func showIfPending() {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return }
        let lastSeen = UserDefaults.standard.string(forKey: lastSeenKey)
        UserDefaults.standard.set(version, forKey: lastSeenKey)
        guard shouldShow(version: version, lastSeen: lastSeen, shown: suite?.string(forKey: shownKey)),
              let url = Bundle.main.url(forResource: "whats-new", withExtension: "md"),
              let notes = try? String(contentsOf: url, encoding: .utf8),
              !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        suite?.set(version, forKey: shownKey)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 480), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "What’s New"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WhatsNewView(version: version, notes: notes) { window.close() })
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct WhatsNewView: View {
    let version: String
    let notes: String
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("What’s New in Topside \(version)")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        lineView(line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
            }

            VStack(spacing: 10) {
                Button(action: dismiss) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                Link("See the Full Changelog", destination: WhatsNew.changelogURL)
                    .font(.callout)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private var lines: [String] {
        notes
            .replacingOccurrences(of: "<kbd>", with: "")
            .replacingOccurrences(of: "</kbd>", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The CHANGELOG uses "### Added"-style headings and "- " bullets; anything else shows as plain text.
    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("### ") {
            Text(line.dropFirst(4))
                .font(.headline)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
        } else if line.hasPrefix("- ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(markdown(String(line.dropFirst(2))))
            }
        } else {
            Text(markdown(line))
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
