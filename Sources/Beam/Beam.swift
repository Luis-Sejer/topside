import AppKit
import CoreImage.CIFilterBuiltins
import Kit
import SwiftUI

@main
enum Main {
    @MainActor static func main() { Kit.run { Beam() } }
}

/// Whatever is on the clipboard, as a QR code: point your phone's camera at it to open the link there.
@MainActor
final class Beam {
    private let model = BeamModel()
    private lazy var item = MenuBarItem(
        name: "Beam",
        symbol: "qrcode",
        click: .popover(AnyView(BeamView(model: model)), size: NSSize(width: 300, height: 360))
    )

    init() {
        // Read on open only, never in the background. macOS asks once whether Beam may read the clipboard.
        item.onShow = { [model] in model.text = NSPasteboard.general.string(forType: .string) }
    }
}

final class BeamModel: ObservableObject {
    @Published var text: String?

    /// Nil when the text is too long for a QR code.
    var code: NSImage? {
        guard let text, !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: output.extent.size)
    }
}

struct BeamView: View {
    @ObservedObject var model: BeamModel

    var body: some View {
        VStack(spacing: 14) {
            if let text = model.text, !text.isEmpty {
                if let code = model.code {
                    Image(nsImage: code)
                        .interpolation(.none) // keep the modules sharp; smoothing blurs them and phones misread it
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("QR code for the clipboard")
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else {
                    ContentUnavailableView("Too Long for a QR Code", systemImage: "qrcode", description: Text("Copy a link or some shorter text."))
                }
            } else {
                ContentUnavailableView("Nothing to Beam", systemImage: "qrcode", description: Text("Copy a link or some text, then open Beam."))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
