import AppKit

/// Cached once; Dock animation never decodes artwork on each frame.
@MainActor
public enum TepalIconArtwork {
    public static let image: CGImage = {
        let packaged = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("Tepal_TepalMac.bundle")) }
        let bundle = packaged ?? .module
        guard let url = bundle.url(forResource: "creature", withExtension: "png"),
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            preconditionFailure("Missing Tepal icon artwork")
        }
        // Trim the transparent export margin; the Dock allocates space to the pet itself.
        return cgImage.cropping(to: CGRect(x: 204, y: 20, width: 871, height: 1198)) ?? cgImage
    }()
}
