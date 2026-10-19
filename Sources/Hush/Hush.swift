import AppKit
import Carbon.HIToolbox
import CoreAudio
import Kit

@main
enum Main {
    @MainActor static func main() { Kit.run { Hush() } }
}

/// Mutes the microphone itself, so it works the same in Teams, Zoom, Meet and everything else.
/// Click the icon or press ⌃⌥M from any app. Red means muted; a filled mic means an app is listening.
@MainActor
final class Hush {
    // ponytail: fixed shortcut. Bring over Snicker's ShortcutStore if people want to change it.
    private static let shortcut = (keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey, display: "⌃⌥M")
    // ponytail: polls Core Audio every second instead of property listeners, which need re-registering whenever the default mic changes.
    private static let pollInterval: TimeInterval = 1

    private lazy var item = MenuBarItem(
        name: "Hush",
        symbol: "mic",
        click: .action { [unowned self] in toggle() },
        menuItems: { [unowned self] in menuItems() }
    )
    private var hotKey: HotKey?
    private var timer: Timer?
    private var terminateObserver: Any?
    /// The microphone Hush muted, so quitting gives that one back instead of leaving it silently off, even after
    /// switching mics. Saved, so a relaunch in between doesn't forget it.
    private var mutedByHush: String? {
        get { UserDefaults.standard.string(forKey: Self.mutedByHushKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.mutedByHushKey) }
    }
    private static let mutedByHushKey = "mutedMicrophoneUID"

    init() {
        hotKey = HotKey(keyCode: Self.shortcut.keyCode, modifiers: Self.shortcut.modifiers) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
        update()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let uid = self.mutedByHush else { return }
                Microphone(uid: uid)?.isMuted = false
                self.mutedByHush = nil
            }
        }
    }

    private func toggle() {
        guard let mic = Microphone.current, mic.canMute else {
            NSSound.beep()
            Kit.announce(Microphone.current.map { "Hush can't mute \($0.name)" } ?? "No microphone found")
            return
        }
        let mute = !mic.isMuted
        mic.isMuted = mute
        // Some devices accept the change and ignore it; only say what really happened.
        guard mic.isMuted == mute else {
            NSSound.beep()
            Kit.announce("Hush couldn't \(mute ? "mute" : "unmute") \(mic.name)")
            update()
            return
        }
        mutedByHush = mute ? mic.uid : nil
        NSSound(named: mute ? "Bottle" : "Pop")?.play()
        Kit.announce(mute ? "Microphone muted" : "Microphone on")
        update()
    }

    private func update() {
        // Unmuted somewhere else (System Settings, the mic's own button): nothing for Hush to give back.
        if let uid = mutedByHush, Microphone(uid: uid)?.isMuted != true { mutedByHush = nil }
        guard let mic = Microphone.current else {
            item.setSymbol("mic.slash")
            item.setTint(nil)
            return
        }
        if mic.isMuted {
            item.setSymbol("mic.slash.fill")
            item.setTint(.systemRed)
        } else {
            item.setSymbol(mic.isInUse ? "mic.fill" : "mic")
            item.setTint(nil)
        }
    }

    private func menuItems() -> [NSMenuItem] {
        guard let mic = Microphone.current else { return [.label("No microphone found")] }
        guard mic.canMute else { return [.label(mic.name), .label("This microphone can't be muted")] }
        return [
            .label(mic.name),
            .label(mic.isInUse ? "In use by an app" : "Not in use"),
            NSMenuItem(mic.isMuted ? "Unmute" : "Mute", symbol: mic.isMuted ? "mic" : "mic.slash") { [unowned self] in toggle() },
            hotKey == nil ? .shortcutTaken(Self.shortcut.display) : .label("Shortcut: \(Self.shortcut.display)"),
        ]
    }
}

/// The default input device, through Core Audio.
struct Microphone {
    let id: AudioObjectID

    static var current: Microphone? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? Microphone(id: id) : nil
    }

    /// The device with this UID, if it's still connected.
    init?(uid: String) {
        var address = Self.address(kAudioHardwarePropertyTranslateUIDToDevice, scope: kAudioObjectPropertyScopeGlobal)
        var uid = uid as CFString
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), pointer, &size, &id)
        }
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        self.id = id
    }

    init(id: AudioObjectID) {
        self.id = id
    }

    var name: String { string(kAudioObjectPropertyName) ?? "Microphone" }

    /// Stays the same across reconnects and restarts, unlike `id`.
    var uid: String? { string(kAudioDevicePropertyDeviceUID) }

    /// Whether Hush can silence it at all: through its own mute, or its input volume.
    var canMute: Bool {
        isSettable(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
            || isSettable(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
    }

    private func string(_ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector, scope: kAudioObjectPropertyScopeGlobal)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// True while any app is recording from it.
    var isInUse: Bool {
        get32(kAudioDevicePropertyDeviceIsRunningSomewhere, scope: kAudioObjectPropertyScopeGlobal) == 1
    }

    /// Uses the device's own mute where it has one. Many built-in mics don't, so those get their input
    /// volume set to zero, with the old volume kept to put back.
    var isMuted: Bool {
        get {
            if isSettable(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput) {
                return get32(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput) == 1
            }
            return (getVolume() ?? 1) == 0
        }
        nonmutating set {
            if isSettable(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput) {
                set32(kAudioDevicePropertyMute, newValue ? 1 : 0)
            } else if newValue {
                UserDefaults.standard.set(getVolume() ?? 1, forKey: Self.savedVolumeKey)
                setVolume(0)
            } else {
                let saved = UserDefaults.standard.object(forKey: Self.savedVolumeKey) as? Float32
                setVolume(saved.map { $0 > 0 ? $0 : 1 } ?? 1)
            }
        }
    }

    private static let savedVolumeKey = "volumeBeforeMute"

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func isSettable(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> Bool {
        var address = Self.address(selector, scope: scope)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(id, &address) && AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
    }

    private func get32(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> UInt32? {
        var address = Self.address(selector, scope: scope)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func set32(_ selector: AudioObjectPropertySelector, _ value: UInt32) {
        var address = Self.address(selector, scope: kAudioObjectPropertyScopeInput)
        var value = value
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func getVolume() -> Float32? {
        var address = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &volume) == noErr ? volume : nil
    }

    private func setVolume(_ volume: Float32) {
        var address = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        var volume = volume
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
    }
}
