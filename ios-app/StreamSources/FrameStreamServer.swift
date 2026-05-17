import Foundation
import Network
import os.log

/// Thin TCP-listener wrapper used by `FrameStreamingViewController` to
/// publish F-packets to whatever host-side launcher dials in.
///
/// * Listens on a fixed TCP port (defaults to 8200 — picked to match the
///   spec; if `NWListener` rejects it because something else owns it
///   the listener will try ephemeral ports and log the bound port).
/// * Advertises itself via Bonjour as `_isonim-stream._tcp.` so the
///   host launcher can discover it without static configuration.
/// * Broadcast is fan-out: every connected `NWConnection` receives the
///   same packet. The current revision targets a single host launcher
///   per session, but multi-client doesn't cost us anything.
///
/// Concurrency: all listener / connection state lives on a single
/// serial dispatch queue (`streamQueue`); the view controller calls
/// `broadcast(...)` from the main thread and we hop over via
/// `async`. `hasActiveClients` is the only cross-thread read; it's
/// guarded by an atomic flag updated from `streamQueue`.
final class FrameStreamServer {

    static let shared = FrameStreamServer()
    private init() {}

    private let log = OSLog(subsystem: "com.metacraft.isonim.stream",
                            category: "FrameStreamServer")
    private let streamQueue = DispatchQueue(label: "isonim.stream.server",
                                            qos: .userInitiated)

    // We run TWO parallel NWListeners on the same TCP port:
    //
    //   1. `listener` — the default-parameters listener that handles
    //      Wi-Fi (and historically advertised Bonjour). It uses
    //      `includePeerToPeer = true`, which on iOS opts the listener
    //      into peer-to-peer transports (AWDL / Wi-Fi Direct / BT).
    //      That flag does NOT widen the interface set; on the contrary,
    //      empirically the bundle of P2P-only params it pulls in skips
    //      USB-tethered ethernet adapters entirely. So a host on the
    //      Mac side that routes to the iPhone's USB link-local IPv6
    //      address (FE80::...%enXX) gets "Connection refused" because
    //      nothing is listening on that interface.
    //
    //   2. `usbListener` — a second listener with parameters explicitly
    //      pinned to `.wiredEthernet`. iOS exposes the USB-tethered
    //      network adapter (the host-side `en10`/`en11` pair) as
    //      wired ethernet from the device's perspective, so this
    //      listener binds the USB interface and accepts TCP from
    //      `nc -6 FE80::...%enXX 8200`.
    //
    // Both listeners share the same `accept(_:)` callback, the same
    // serial `streamQueue`, and the same connection list, so the
    // broadcast fan-out treats USB and Wi-Fi clients identically.
    private var listener: NWListener?
    private var usbListener: NWListener?
    private var connections: [NWConnection] = []
    private var activeClientCount: Int32 = 0  // atomic via OSAtomic

    /// Cheap probe used by the view controller to skip readback when no
    /// client is connected.
    var hasActiveClients: Bool {
        return activeClientCount > 0
    }

    func start(port requestedPort: UInt16) {
        streamQueue.async { [weak self] in
            guard let self else { return }
            guard self.listener == nil else { return }
            let nwPort = NWEndpoint.Port(rawValue: requestedPort) ?? .any

            // ---- Listener #1: Wi-Fi + peer-to-peer + Bonjour ----
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                params.includePeerToPeer = true
                let listener = try NWListener(using: params, on: nwPort)
                listener.service = NWListener.Service(
                    name: "isonim-stream",
                    type: "_isonim-stream._tcp")
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let p = listener.port?.rawValue {
                            os_log("FrameStreamServer (wifi) ready on port %{public}d",
                                   log: self.log, type: .info, Int(p))
                        }
                    case .failed(let err):
                        os_log("FrameStreamServer (wifi) failed: %{public}@",
                               log: self.log, type: .error,
                               String(describing: err))
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] conn in
                    self?.accept(conn)
                }
                listener.start(queue: self.streamQueue)
                self.listener = listener
            } catch {
                os_log("FrameStreamServer (wifi) failed to start: %{public}@",
                       log: self.log, type: .error,
                       String(describing: error))
            }

            // ---- Listener #2: USB-tethered wired ethernet ----
            //
            // Pinning `requiredInterfaceType = .wiredEthernet` is what
            // gets us the USB interface. We deliberately do NOT set
            // `includePeerToPeer` here (the two are orthogonal — P2P
            // wants AWDL, USB wants the wired adapter) and we do NOT
            // attach a Bonjour service (the Wi-Fi listener already
            // advertises; broadcasting the same name twice would
            // confuse mDNS resolution).
            do {
                let usbParams = NWParameters.tcp
                usbParams.allowLocalEndpointReuse = true
                usbParams.requiredInterfaceType = .wiredEthernet
                let usb = try NWListener(using: usbParams, on: nwPort)
                usb.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let p = usb.port?.rawValue {
                            os_log("FrameStreamServer (usb) ready on port %{public}d",
                                   log: self.log, type: .info, Int(p))
                        }
                    case .failed(let err):
                        os_log("FrameStreamServer (usb) failed: %{public}@",
                               log: self.log, type: .error,
                               String(describing: err))
                    default:
                        break
                    }
                }
                usb.newConnectionHandler = { [weak self] conn in
                    self?.accept(conn)
                }
                usb.start(queue: self.streamQueue)
                self.usbListener = usb
            } catch {
                // Non-fatal: Wi-Fi path is still live.
                os_log("FrameStreamServer (usb) failed to start: %{public}@",
                       log: self.log, type: .error,
                       String(describing: error))
            }
        }
    }

    private func accept(_ conn: NWConnection) {
        // Hold conn strongly inside the state handler. NWListener hands
        // the connection to us, but nothing else strong-references it —
        // if we capture `[weak conn]` here, ARC tears the connection
        // down before its state machine reaches `.ready`, so the
        // `.ready` branch never fires and `activeClientCount` stays at
        // zero. Capturing `conn` strongly keeps it alive until we drop
        // it from `connections` on `.failed` / `.cancelled`.
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                os_log("FrameStreamServer client connected", log: self.log, type: .info)
                self.connections.append(conn)
                OSAtomicIncrement32(&self.activeClientCount)
                // Drain any inbound bytes — we don't process I-packets in
                // this milestone but we must keep the read pump going so
                // the OS doesn't backpressure the connection.
                self.pumpReads(conn)
            case .failed, .cancelled:
                self.drop(conn)
            default:
                break
            }
        }
        conn.start(queue: streamQueue)
    }

    private func pumpReads(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
            [weak self, weak conn] _, _, isComplete, err in
            guard let self, let conn else { return }
            if isComplete || err != nil {
                self.drop(conn)
            } else {
                self.pumpReads(conn)
            }
        }
    }

    private func drop(_ conn: NWConnection) {
        if let idx = connections.firstIndex(where: { $0 === conn }) {
            connections.remove(at: idx)
            OSAtomicDecrement32(&activeClientCount)
            os_log("FrameStreamServer client disconnected",
                   log: log, type: .info)
        }
        conn.cancel()
    }

    func broadcast(_ packet: Data) {
        streamQueue.async { [weak self] in
            guard let self else { return }
            for conn in self.connections {
                conn.send(content: packet, completion: .contentProcessed({ [weak self, weak conn] err in
                    guard let self, let conn else { return }
                    if err != nil {
                        self.drop(conn)
                    }
                }))
            }
        }
    }

    // ----------------------------------------------------------------
    // F-packet codec — kept identical to
    // `isonim-render-serve/src/isonim_render_serve/packet.nim`'s
    // `encodeFrame` for a fkFull / full-frame variant.
    // ----------------------------------------------------------------

    static func encodeFramePacket(width: UInt32,
                                  height: UInt32,
                                  payload: Data) -> Data {
        var data = Data()
        data.reserveCapacity(14 + payload.count)
        data.append(UInt8(ascii: "F"))
        data.append(0)                          // flags: not diff, not video
        appendU32LE(&data, width)
        appendU32LE(&data, height)
        appendU32LE(&data, UInt32(payload.count))
        data.append(payload)
        return data
    }

    private static func appendU32LE(_ data: inout Data, _ v: UInt32) {
        data.append(UInt8(v        & 0xFF))
        data.append(UInt8((v >>  8) & 0xFF))
        data.append(UInt8((v >> 16) & 0xFF))
        data.append(UInt8((v >> 24) & 0xFF))
    }
}
