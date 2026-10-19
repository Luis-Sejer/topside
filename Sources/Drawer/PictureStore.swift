import AppKit
import CryptoKit

/// Pictures of menu bar icons, kept on disk so the bar shows the real icons straight away, even after a relaunch.
/// Taking one needs Screen Recording, and on macOS 27 a hidden icon is only drawn while macOS's » shows it.
@MainActor
enum PictureStore {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Drawer/Pictures", directoryHint: .isDirectory)
    }

    /// Keys hold app names and icon titles, so the file name is a hash of the key.
    private static func file(for key: String) -> URL {
        folder.appending(path: SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".png")
    }

    static func load(_ keys: [String]) -> [String: NSImage] {
        keys.reduce(into: [:]) { pictures, key in
            if let image = NSImage(contentsOf: file(for: key)), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                pictures[key] = MenuBarExtras.picture(cgImage, size: image.size)
            }
        }
    }

    static func save(_ pictures: [String: NSImage]) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (key, image) in pictures {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: file(for: key), options: .atomic)
        }
    }
}
