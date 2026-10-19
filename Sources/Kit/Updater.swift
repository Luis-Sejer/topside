import AppKit

/// Asks GitHub whether a newer Topside release exists, and installs this app from it with the README's script
/// (from Snicker). All the apps are released together, so each one checks the same release.
@MainActor
public final class Updater {
    public static let shared = Updater()

    static let releasesURL = URL(string: "https://github.com/Luis-Sejer/topside/releases/latest")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/Luis-Sejer/topside/releases/latest")!
    private static let installScript = "https://raw.githubusercontent.com/Luis-Sejer/topside/main/install.sh"
    /// A check at launch, then at most one a day, made when the icon is clicked: a hidden app costs nothing.
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    /// Downloading one small app takes seconds; past this, something is stuck and GitHub is the way out.
    private static let installTimeout: Duration = .seconds(90)

    /// The newer version GitHub has, once a check found one.
    public private(set) var availableVersion: String?
    private var lastCheck: Date?
    private var isFetching = false
    private var isInstalling = false

    var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ProcessInfo.processInfo.processName
    }

    public func checkIfDue() {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        fetch(reporting: false)
    }

    /// Check for Updates… in the menu: always checks, and says what it found.
    func checkNow() {
        fetch(reporting: true)
    }

    private func fetch(reporting: Bool) {
        guard !isFetching else { return }
        isFetching = true
        Task {
            defer { isFetching = false }
            let latest = await Self.latestVersion()
            if let latest {
                lastCheck = Date()
                availableVersion = Self.isVersion(latest, newerThan: installedVersion) ? latest : nil
            }
            guard reporting else { return }
            if availableVersion != nil {
                offerUpdate()
            } else {
                tell(latest == nil ? "Couldn’t Check for Updates" : "\(appName) Is Up to Date",
                     latest == nil ? "GitHub can’t be reached right now. Try again later." : "You have Topside \(installedVersion), the newest version.")
            }
        }
    }

    /// Nil when GitHub can't be reached; the next check tries again.
    private static func latestVersion() async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: latestReleaseAPI),
              let release = try? JSONDecoder().decode(Release.self, from: data) else { return nil }
        return release.version
    }

    /// "Update to 1.1.0…" in the menu, and a found update after Check for Updates….
    func offerUpdate() {
        guard let version = availableVersion, !isInstalling else { return }
        let alert = NSAlert()
        alert.messageText = "Topside \(version) Is Available"
        alert.informativeText = "You have \(installedVersion). \(appName) quits, updates and opens again in a few seconds."
        alert.addButton(withTitle: "Update \(appName)")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "What’s New")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: install()
        case .alertThirdButtonReturn: NSWorkspace.shared.open(Self.releasesURL)
        default: break
        }
    }

    /// The script quits this app and opens the new version itself. If this app is still running when the script
    /// succeeds, its `open` only brought this old copy forward, so quit and relaunch from here.
    private func install() {
        isInstalling = true
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "curl -fsSL \(Self.installScript) | sh -s -- \"$0\"", appName]
        process.terminationHandler = { process in
            let succeeded = process.terminationStatus == 0
            Task { @MainActor in
                if succeeded { Self.relaunch() } else { Updater.shared.installFailed() }
            }
        }
        do {
            try process.run()
        } catch {
            return installFailed()
        }
        Task {
            try? await Task.sleep(for: Self.installTimeout)
            if isInstalling { installFailed() }
        }
    }

    private func installFailed() {
        guard isInstalling else { return }
        isInstalling = false
        let alert = NSAlert()
        alert.messageText = "\(appName) Couldn’t Update"
        alert.informativeText = "Download the new version from GitHub instead."
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(Self.releasesURL) }
    }

    private func tell(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// A detached shell waits for this process to exit, then opens the freshly installed app.
    private static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// Compares dotted versions number by number, so 1.10.0 is newer than 1.9.0.
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    private struct Release: Decodable {
        let tagName: String
        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }
}
