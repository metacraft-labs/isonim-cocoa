import UIKit

// Stream variant of the IsoNim-Cocoa iOS app.
//
// This binary is a thin shell around `FrameStreamingViewController`:
//   * It hands the controller's `view` to `isonim_start()` so the Nim
//     branded UI renders into it (same content as the Branded scheme).
//   * It spins up a TCP listener on port 8200 (also advertised over
//     Bonjour as `_isonim-stream._tcp.`) that the host-side launcher
//     binary connects to. Every CADisplayLink tick the controller
//     reads back the rendered pixels and emits one F-packet
//     (`'F' | u8 flags | u32 LE width | u32 LE height | u32 LE len |
//     RGBA8888`) per active client.

@_silgen_name("isonim_start")
func isonim_start(_ rootView: UnsafeMutableRawPointer,
                  _ width: Double, _ height: Double,
                  _ safeTop: Double, _ safeBottom: Double)

@main
class StreamAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let win = UIWindow(frame: UIScreen.main.bounds)
        let vc = FrameStreamingViewController()
        win.rootViewController = vc
        win.makeKeyAndVisible()
        window = win
        return true
    }
}
