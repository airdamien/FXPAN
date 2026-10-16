import CoreBluetooth
import Foundation

/// The Mini D1 trigger. It advertises as FXPAN-D1 and speaks the same lines as the Pi Zero.
enum BLELink {
    private static let gate = NSLock()
    private static var live: Hub?

    static func ping() async -> Bool {
        let hub = hub()
        if hub.isBusy { return hub.isLinked }
        let wait: TimeInterval = hub.isLinked ? 2 : 6
        guard let line = try? await hub.send("PING", wait: wait, owns: false) else { return false }
        return line.hasPrefix("OK")
    }

    /// A round trip after USB has closed. Closing the cameras can drop the link, and a PING is safe to send again.
    static func ensure() async -> Bool {
        let hub = hub()
        await hub.makeRoomForPing()
        let deadline = Date().addingTimeInterval(6)
        while hub.isBusy, Date() < deadline {
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        guard let line = try? await hub.send("PING", wait: 6, owns: false) else { return false }
        return line.hasPrefix("OK")
    }

    static func fire(_ photo: Photo) async throws -> String {
        let ms = SyncLink.hold(photo)
        let command = ms == 300 ? "FIRE" : "FIRE \(ms)"
        let line = try await hub().send(command, wait: Double(ms) / 1000 + 8, owns: true)
        guard line.hasPrefix("OK") else { throw PTPError.message(line) }
        return line
    }

    /// Drops the link when release is not BT, so USB and Sync send nothing over Bluetooth.
    static func stop() {
        gate.lock()
        let hub = live
        gate.unlock()
        hub?.stop()
    }

    private static func hub() -> Hub {
        gate.lock()
        defer { gate.unlock() }
        if let live { return live }
        let made = Hub()
        live = made
        return made
    }
}

private final class Hub: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let rxID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let txID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    private let queue = DispatchQueue(label: "fxpan.ble")
    private let state = NSLock()
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    private var tx: CBCharacteristic?
    private var wanted = false
    private var busy = false
    private var linked = false
    private var waiting = false
    private var pending = ""
    private var owns = false
    private var sent = false
    private var ticket = 0
    private var inbox = Data()
    private var waiter: ((Result<String, Error>) -> Void)?
    private var next: Pending?

    private struct Pending {
        var line: String
        var wait: TimeInterval
        var owns: Bool
        var cont: CheckedContinuation<String, Error>
    }

    var isBusy: Bool { state.withLock { busy || waiting } }
    var isLinked: Bool { state.withLock { linked } }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.wanted = false
            self.central.stopScan()
            if let peripheral = self.peripheral {
                self.central.cancelPeripheralConnection(peripheral)
            }
            self.state.withLock { self.linked = false }
            self.finish(.failure(PTPError.message("Bluetooth closed")))
        }
    }

    /// Drops a ready-check that has not been written yet, so a shutter press is not told the board is busy.
    func makeRoomForPing() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                if self.waiter != nil, !self.owns, !self.sent {
                    self.finish(.failure(PTPError.message("Bluetooth closed")))
                }
                cont.resume()
            }
        }
    }

    func send(_ line: String, wait: TimeInterval, owns: Bool) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async {
                if self.waiter != nil {
                    if owns, !self.owns, !self.sent {
                        self.finish(.failure(PTPError.message("Bluetooth closed")))
                    } else if owns, !self.owns, self.next == nil {
                        self.next = Pending(line: line, wait: wait, owns: owns, cont: cont)
                        return
                    } else {
                        cont.resume(throwing: PTPError.message("Trigger board is busy"))
                        return
                    }
                }
                self.begin(line, wait: wait, owns: owns, cont: cont)
            }
        }
    }

    private func begin(_ line: String, wait: TimeInterval, owns: Bool, cont: CheckedContinuation<String, Error>) {
        wanted = true
        self.owns = owns
        state.withLock {
            if owns { busy = true }
            waiting = true
        }
        pending = line
        sent = false
        inbox.removeAll()
        ticket += 1
        let mine = ticket
        waiter = { result in
            cont.resume(with: result)
        }
        kick()
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.ticket == mine else { return }
            self.finish(.failure(PTPError.message("Trigger board did not answer")))
        }
    }

    private func kick() {
        guard wanted else { return }
        guard central.state == .poweredOn else { return }
        if linked { writePending(); return }
        if peripheral == nil {
            central.scanForPeripherals(withServices: [Self.service], options: nil)
            return
        }
        if peripheral?.state != .connected {
            if let peripheral { central.connect(peripheral, options: nil) }
        }
    }

    private func writePending() {
        guard waiter != nil, !sent, let peripheral, let rx, let tx, peripheral.state == .connected, tx.isNotifying else { return }
        let kind: CBCharacteristicWriteType = rx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        if kind == .withoutResponse, !peripheral.canSendWriteWithoutResponse { return }
        sent = true
        peripheral.writeValue(Data((pending + "\n").utf8), for: rx, type: kind)
    }

    private func finish(_ result: Result<String, Error>) {
        guard let resume = waiter else { return }
        ticket += 1
        waiter = nil
        sent = false
        let follow = next
        next = nil
        state.withLock {
            if owns { busy = false }
            waiting = false
        }
        owns = false
        resume(result)
        if let follow {
            begin(follow.line, wait: follow.wait, owns: follow.owns, cont: follow.cont)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            kick()
        case .poweredOff, .unauthorized, .unsupported:
            state.withLock { linked = false }
            finish(.failure(PTPError.message("Bluetooth is off")))
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        guard name == "FXPAN-D1" else { return }
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        state.withLock { linked = false }
        if wanted { central.scanForPeripherals(withServices: [Self.service], options: nil) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let retry = waiter != nil && !(owns && sent)
        state.withLock { linked = false }
        rx = nil
        tx = nil
        self.peripheral = nil
        if retry {
            sent = false
            inbox.removeAll()
        } else if waiter != nil {
            finish(.failure(PTPError.message("Trigger board dropped the link")))
        }
        if wanted { central.scanForPeripherals(withServices: [Self.service], options: nil) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { finish(.failure(error)); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else { return }
        peripheral.discoverCharacteristics([Self.rxID, Self.txID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { finish(.failure(error)); return }
        rx = service.characteristics?.first { $0.uuid == Self.rxID }
        guard let found = service.characteristics?.first(where: { $0.uuid == Self.txID }) else { return }
        tx = found
        peripheral.setNotifyValue(true, for: found)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { finish(.failure(error)); return }
        guard characteristic.isNotifying else { return }
        state.withLock { linked = true }
        writePending()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { finish(.failure(error)); return }
        guard let data = characteristic.value, !data.isEmpty else { return }
        inbox.append(data)
        guard let split = inbox.firstIndex(of: 0x0A) else { return }
        let raw = inbox[..<split]
        inbox.removeSubrange(...split)
        let line = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        state.withLock { linked = true }
        finish(.success(line))
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { finish(.failure(error)) }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        writePending()
    }
}
