import UIKit

/// Hosts the Nim-rendered branded UI **and** drives the frame-readback
/// loop. Pixels are pulled with `UIGraphicsImageRenderer` once per
/// `CADisplayLink` tick (rate-limited to ~12-15 fps to stay under the
/// "12-15 fps" envelope quoted in the spec for IsoNim's pbIos backend)
/// and pushed to the singleton `FrameStreamServer`. The server applies
/// back-pressure: if no client is connected, the readback is skipped.
final class FrameStreamingViewController: UIViewController {

    // Throttle: target ~12 fps. iPhone 14 runs the display link at 60 Hz,
    // so we sample every 5th tick (60 / 5 = 12 fps). The exact rate is
    // observed and reported via Bonjour TXT; the host launcher's display
    // budget is the real ceiling.
    private static let displayLinkDivisor: Int = 5

    private var displayLink: CADisplayLink?
    private var tickCount: Int = 0

    // Captured the first time we receive a non-empty `view.bounds` so
    // readback dimensions stay stable for the WS lifetime; the host
    // launcher caches them per session.
    private var captureSize: CGSize = .zero
    private var captureScale: CGFloat = 1.0

    // Re-use the format/renderer pair across ticks: `UIGraphicsImageRenderer`
    // is cheap to keep alive and skips per-frame autorelease bookkeeping.
    private var renderer: UIGraphicsImageRenderer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0xF8/255.0, green: 0xFA/255.0,
                                       blue: 0xFC/255.0, alpha: 1)
        // Hand the view to Nim — same entry point as the Branded scheme.
        view.layoutIfNeeded()
        let bounds = view.bounds
        let insets = view.safeAreaInsets
        let ptr = Unmanaged.passUnretained(view).toOpaque()
        isonim_start(ptr,
                     Double(bounds.width), Double(bounds.height),
                     Double(insets.top), Double(insets.bottom))

        // Start the stream server *after* Nim has laid out subviews so the
        // first frame the host sees is non-empty.
        FrameStreamServer.shared.start(port: 8200)

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 60   // run at native, throttle in tick
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The first time the OS gives us a real bounds, lock the
        // readback dimensions. We never re-resize during a session — the
        // host launcher only knows how to decode F-packets with the
        // dimensions in the header it first saw, but resize support
        // would arrive via M-packets in a later milestone.
        if captureSize == .zero, view.bounds.size != .zero {
            captureSize = view.bounds.size
            captureScale = view.window?.screen.scale ?? UIScreen.main.scale
            let format = UIGraphicsImageRendererFormat.preferred()
            format.scale = captureScale
            format.opaque = true
            format.preferredRange = .standard      // sRGB, no HDR
            renderer = UIGraphicsImageRenderer(size: captureSize, format: format)
        }
    }

    deinit {
        displayLink?.invalidate()
    }

    @objc private func tick() {
        tickCount &+= 1
        if tickCount % Self.displayLinkDivisor != 0 { return }
        guard FrameStreamServer.shared.hasActiveClients else { return }
        guard let renderer else { return }

        // `drawHierarchy(in:afterScreenUpdates:)` is the documented path
        // for off-screen capture of a UIView tree that contains UIKit
        // controls (UILabel/UIButton — both used by the Nim renderer).
        // We pass `false` to skip the extra layout pass; the display
        // link guarantees us a fresh frame already.
        let image = renderer.image { ctx in
            view.drawHierarchy(in: CGRect(origin: .zero, size: captureSize),
                               afterScreenUpdates: false)
        }
        guard let cg = image.cgImage else { return }
        let pixelW = cg.width
        let pixelH = cg.height

        // Pull RGBA8888 non-premultiplied bytes via CoreGraphics. The
        // F-packet protocol mandates non-premultiplied sRGB.
        let bytesPerRow = pixelW * 4
        let total = bytesPerRow * pixelH
        var buffer = Data(count: total)
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 =
            CGImageAlphaInfo.noneSkipLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let cgctx = CGContext(data: base,
                                        width: pixelW,
                                        height: pixelH,
                                        bitsPerComponent: 8,
                                        bytesPerRow: bytesPerRow,
                                        space: cs,
                                        bitmapInfo: bitmapInfo)
            else { return false }
            cgctx.draw(cg, in: CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
            return true
        }
        guard ok else { return }
        // CGContext above produced RGBX (alpha skipped). Patch the alpha
        // byte to 0xFF so the wire bytes are "RGBA8888, non-premultiplied"
        // exactly as the host launcher expects.
        buffer.withUnsafeMutableBytes { raw in
            guard let p = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var i = 3
            while i < total {
                p[i] = 0xFF
                i += 4
            }
        }

        let packet = FrameStreamServer.encodeFramePacket(
            width: UInt32(pixelW), height: UInt32(pixelH), payload: buffer)
        FrameStreamServer.shared.broadcast(packet)
    }
}
