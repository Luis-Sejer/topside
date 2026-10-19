import AppKit
import AVFoundation
import Kit
import SwiftUI

@main
enum Main {
    @MainActor static func main() { Kit.run { Mirror() } }
}

/// The camera, mirrored, one click from the menu bar: a look at yourself before a call.
/// The camera runs only while the popover shows, so its light goes off the moment it closes.
@MainActor
final class Mirror {
    private let camera = Camera()
    private lazy var item = MenuBarItem(
        name: "Mirror",
        symbol: "person.crop.square",
        click: .popover(AnyView(MirrorView(camera: camera)), size: NSSize(width: 400, height: 260))
    )

    init() {
        item.onShow = { [camera] in camera.start() }
        item.onClose = { [camera] in camera.stop() }
    }
}

final class Camera: ObservableObject {
    enum Status { case starting, running, denied, missing }

    let session = AVCaptureSession()
    @Published private(set) var status = Status.starting
    /// `startRunning` blocks for a moment, so the session lives on its own queue.
    private let queue = DispatchQueue(label: "camera")
    private var isConfigured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { granted ? self?.run() : (self?.status = .denied) }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        queue.async { [session] in session.stopRunning() }
    }

    private func run() {
        queue.async { [weak self] in
            guard let self else { return }
            if !isConfigured {
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    DispatchQueue.main.async { self.status = .missing }
                    return
                }
                session.addInput(input)
                isConfigured = true
            }
            session.startRunning()
            DispatchQueue.main.async { self.status = .running }
        }
    }
}

struct MirrorView: View {
    @ObservedObject var camera: Camera

    var body: some View {
        ZStack {
            Color.black
            Preview(session: camera.session)
                .accessibilityLabel("Camera preview")
            switch camera.status {
            case .starting, .running:
                EmptyView()
            case .denied:
                message("Mirror needs your permission to use the camera.", button: "Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            case .missing:
                message("No camera found.")
            }
        }
    }

    private func message(_ text: String, button: String? = nil, action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash").font(.largeTitle).accessibilityHidden(true)
            Text(text).multilineTextAlignment(.center)
            if let button { Button(button, action: action) }
        }
        .foregroundStyle(.white)
        .padding()
    }
}

/// The live camera layer, flipped so it moves like a mirror does.
private struct Preview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
