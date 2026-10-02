import Foundation
import Network

/// The Pi Zero W on the USB gadget. It listens at 10.55.0.1:2323 and pulses the 10-pin jacks.
enum SyncLink {
    static let address = "10.55.0.1"
    static let port: UInt16 = 2323

    static func ping() async -> Bool {
        guard let line = try? await send("PING", wait: 2) else { return false }
        return line.hasPrefix("OK")
    }

    /// Normal releases use a 300 ms press. Bulb holds the pin for the shutter time on screen.
    static func hold(_ photo: Photo) -> Int {
        guard photo.light.bulb else { return 300 }
        let raw = photo.light.shutter.trimmingCharacters(in: .whitespaces)
        guard let sec = Double(raw), sec > 0 else { return 300 }
        return min(120_000, max(1, Int((sec * 1000).rounded())))
    }

    static func fire(_ photo: Photo) async throws -> String {
        let ms = hold(photo)
        let command = ms == 300 ? "FIRE" : "FIRE \(ms)"
        let line = try await send(command, wait: Double(ms) / 1000 + 8)
        guard line.hasPrefix("OK") else { throw PTPError.message(line) }
        return line
    }

    private static func send(_ line: String, wait: TimeInterval) async throws -> String {
        let connection = NWConnection(
            host: NWEndpoint.Host(address),
            port: NWEndpoint.Port(rawValue: port) ?? 2323,
            using: .tcp
        )
        let inbox = Inbox()
        return try await withCheckedThrowingContinuation { cont in
            let once = Once()
            func finish(_ result: Result<String, Error>) {
                once.run {
                    connection.cancel()
                    cont.resume(with: result)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data((line + "\n").utf8), completion: .contentProcessed { error in
                        if let error { finish(.failure(error)) }
                    })
                    func read() {
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { data, _, complete, error in
                            if let data, !data.isEmpty {
                                inbox.add(data)
                                if let reply = inbox.line() {
                                    finish(.success(reply))
                                    return
                                }
                            }
                            if let error {
                                finish(.failure(error))
                                return
                            }
                            if complete {
                                finish(.failure(PTPError.message("Sync closed")))
                                return
                            }
                            read()
                        }
                    }
                    read()
                case .failed(let error):
                    finish(.failure(error))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + wait) {
                finish(.failure(PTPError.message("Trigger board did not answer")))
            }
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        if done { return }
        done = true
        body()
    }
}

private final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func add(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func line() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let split = data.firstIndex(of: 0x0A) else { return nil }
        let raw = data[..<split]
        data.removeSubrange(...split)
        return String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
