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

    private var listener: NWListener?
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
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                params.includePeerToPeer = true
                let nwPort = NWEndpoint.Port(rawValue: requestedPort)
                let listener = try NWListener(using: params, on: nwPort ?? .any)
                listener.service = NWListener.Service(
                    name: "isonim-stream",
                    type: "_isonim-stream._tcp")
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let p = listener.port?.rawValue {
                            os_log("FrameStreamServer ready on port %{public}d",
                                   log: self.log, type: .info, Int(p))
                        }
                    case .failed(let err):
                        os_log("FrameStreamServer failed: %{public}@",
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
                os_log("FrameStreamServer failed to start: %{public}@",
                       log: self.log, type: .error,
                       String(describing: error))
            }
        }
    }

    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn else { return }
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
