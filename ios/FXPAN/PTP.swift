import Foundation

enum PTP {
    static let ok: UInt16 = 0x2001
    static let nikonVendor: Int = 0x04B0

    enum Op: UInt16 {
        case getDeviceInfo = 0x1001
        case getStorageIDs = 0x1004
        case getObjectHandles = 0x1007
        case getObject = 0x1009
        case initiateCapture = 0x100E
        case getPropDesc = 0x1014
        case getProp = 0x1015
        case setProp = 0x1016
        case captureSDRAM = 0x90C0
        case changeMode = 0x90C2
        case getEvent = 0x90C7
        case deviceReady = 0x90C8
        case startLiveView = 0x9201
        case endLiveView = 0x9202
        case getLiveView = 0x9203
    }

    enum Prop: UInt16 {
        case battery = 0x5001
        case compression = 0x5004
        case whiteBalance = 0x5005
        case fNumber = 0x5007
        case exposureTime = 0x500D
        case program = 0x500E
        case iso = 0x500F
        case isoAuto = 0xD054
        case recordingMedia = 0xD10B
        case isoAutoHi = 0xD16A
    }

    static let objectAdded: UInt16 = 0x4002

    struct Reply {
        var code: UInt16
        var params: [UInt32]
        var data: Data
        var raw: Data = Data()
        var ok: Bool { code == PTP.ok || code == 0 }
    }

    struct PropDesc {
        var code: UInt16
        var dataType: UInt16
        var getSet: UInt8
        var current: UInt64
        var enums: [UInt64]
        var writable: Bool { getSet != 0 }
    }

    struct DeviceInfo {
        var model: String
        var serial: String
        var properties: Set<UInt16>
    }

    static func command(code: UInt16, transaction: UInt32, params: [UInt32] = []) -> Data {
        var data = Data()
        let length = UInt32(12 + params.count * 4)
        data.appendLE(length)
        data.appendLE(UInt16(1))
        data.appendLE(code)
        data.appendLE(transaction)
        for p in params { data.appendLE(p) }
        return data
    }

    /// Delegate PTP gives the data phase and the response container separately.
    static func reply(data: Data, response: Data) -> Reply {
        if response.count >= 12, response.u16(4) == 3 {
            let code = response.u16(6)
            var params: [UInt32] = []
            var i = 12
            let end = min(response.count, max(12, Int(response.u32(0))))
            while i + 4 <= end {
                params.append(response.u32(i))
                i += 4
            }
            return Reply(code: code, params: params, data: dataset(data), raw: data)
        }
        return interpret(data, response)
    }

    static func interpret(_ a: Data, _ b: Data) -> Reply {
        func container(_ d: Data) -> (UInt16, [UInt32])? {
            guard d.count >= 12 else { return nil }
            let type = d.u16(4)
            guard type == 1 || type == 2 || type == 3 || type == 4 else { return nil }
            let code = d.u16(6)
            var params: [UInt32] = []
            var i = 12
            let declared = Int(d.u32(0))
            let end = min(d.count, max(12, declared))
            while i + 4 <= end {
                params.append(d.u32(i))
                i += 4
            }
            return (code, params)
        }
        if a.u16(4) == 3, let c = container(a) {
            return Reply(code: c.0, params: c.1, data: dataset(b), raw: b)
        }
        if b.u16(4) == 3, let c = container(b) {
            return Reply(code: c.0, params: c.1, data: dataset(a), raw: a)
        }
        let payload = a.count >= b.count ? a : b
        return Reply(code: ok, params: [], data: dataset(payload), raw: payload)
    }

    static func jpeg(in data: Data) -> Data? {
        guard let start = data.range(of: Data([0xFF, 0xD8])) else { return nil }
        let slice = data.subdata(in: start.lowerBound..<data.endIndex)
        if let end = slice.range(of: Data([0xFF, 0xD9]), options: .backwards) {
            return slice.subdata(in: 0..<end.upperBound)
        }
        return slice
    }

    static func parseDeviceInfo(_ data: Data) -> DeviceInfo? {
        let body = dataset(data)
        if body.count != data.count, let parsed = parseDeviceInfoBody(body) { return parsed }
        return parseDeviceInfoBody(data)
    }

    private static func parseDeviceInfoBody(_ data: Data) -> DeviceInfo? {
        var r = Reader(data: data)
        guard r.skip(2 + 4 + 2) else { return nil }
        _ = r.ptpString()
        guard r.skip(2) else { return nil } // FunctionalMode
        guard r.skipArray16() else { return nil } // OperationsSupported
        guard r.skipArray16() else { return nil } // EventsSupported
        guard let props = r.array16() else { return nil } // DevicePropertiesSupported
        guard r.skipArray16() else { return nil } // CaptureFormats
        guard r.skipArray16() else { return nil } // ImageFormats
        _ = r.ptpString() // Manufacturer
        let model = r.ptpString() ?? ""
        _ = r.ptpString() // DeviceVersion
        let serial = usable(r.ptpString() ?? "")
        return DeviceInfo(model: model, serial: serial, properties: Set(props))
    }

    /// A run of zeros is what Nikon sends when it will not give a real serial. Treat that as missing.
    static func usable(_ serial: String) -> String {
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || !trimmed.contains(where: { $0 != "0" }) { return "" }
        return trimmed
    }

    /// ImageCapture sometimes wraps the dataset in a PTP data container. Strip that header when it is one.
    static func dataset(_ data: Data) -> Data {
        guard data.count >= 12 else { return data }
        let type = data.u16(4)
        guard type == 2 else { return data }
        let declared = Int(data.u32(0))
        guard declared >= 12, declared <= data.count else { return data }
        return data.subdata(in: 12..<declared)
    }

    static func parsePropDesc(_ data: Data) -> PropDesc? {
        var r = Reader(data: data)
        guard let code = r.u16(), let type = r.u16(), let getSet = r.u8() else { return nil }
        guard r.skipValue(type) else { return nil }
        guard let current = r.readValue(type) else { return nil }
        guard let form = r.u8() else { return nil }
        var enums: [UInt64] = []
        if form == 2, let count = r.u16() {
            for _ in 0..<count {
                if let v = r.readValue(type) { enums.append(v) }
            }
        }
        return PropDesc(code: code, dataType: type, getSet: getSet, current: current, enums: enums)
    }

    static func encode(_ value: UInt64, type: UInt16) -> Data {
        var data = Data()
        switch type {
        case 0x0001, 0x0002: data.append(UInt8(value & 0xFF))
        case 0x0003, 0x0004: data.appendLE(UInt16(value & 0xFFFF))
        case 0x0005, 0x0006: data.appendLE(UInt32(value & 0xFFFF_FFFF))
        default: data.appendLE(UInt16(value & 0xFFFF))
        }
        return data
    }

    static func nearest(_ want: UInt64, in values: [UInt64]) -> UInt64? {
        guard !values.isEmpty else { return nil }
        return values.min { abs(Int64(bitPattern: $0) - Int64(bitPattern: want)) < abs(Int64(bitPattern: $1) - Int64(bitPattern: want)) }
    }

    struct Reader {
        var data: Data
        var i = 0

        mutating func skip(_ n: Int) -> Bool {
            guard i + n <= data.count else { return false }
            i += n
            return true
        }

        mutating func u8() -> UInt8? {
            guard i < data.count else { return nil }
            defer { i += 1 }
            return data[i]
        }

        mutating func u16() -> UInt16? {
            guard i + 2 <= data.count else { return nil }
            let v = data.u16(i)
            i += 2
            return v
        }

        mutating func u32() -> UInt32? {
            guard i + 4 <= data.count else { return nil }
            let v = data.u32(i)
            i += 4
            return v
        }

        mutating func ptpString() -> String? {
            guard let n = u8() else { return nil }
            if n == 0 { return "" }
            let bytes = Int(n) * 2
            guard i + bytes <= data.count else { return nil }
            let slice = data.subdata(in: i..<(i + bytes))
            i += bytes
            let units = stride(from: 0, to: slice.count, by: 2).map { slice.u16($0) }
            let chars = units.prefix { $0 != 0 }.map { UnicodeScalar(UInt32($0)).map(Character.init) ?? "?" }
            return String(chars)
        }

        func size(_ type: UInt16) -> Int? {
            switch type {
            case 0x0001, 0x0002: return 1
            case 0x0003, 0x0004: return 2
            case 0x0005, 0x0006: return 4
            case 0x0007, 0x0008: return 8
            default: return nil
            }
        }

        mutating func skipArray16() -> Bool {
            guard let n = u32() else { return false }
            return skip(Int(n) * 2)
        }

        mutating func array16() -> [UInt16]? {
            guard let n = u32() else { return nil }
            var out: [UInt16] = []
            out.reserveCapacity(Int(n))
            for _ in 0..<n {
                guard let v = u16() else { return nil }
                out.append(v)
            }
            return out
        }

        mutating func skipValue(_ type: UInt16) -> Bool {
            if type == 0xFFFF { return ptpString() != nil }
            guard let n = size(type) else { return false }
            return skip(n)
        }

        mutating func readValue(_ type: UInt16) -> UInt64? {
            switch type {
            case 0x0001, 0x0002: return u8().map(UInt64.init)
            case 0x0003, 0x0004: return u16().map(UInt64.init)
            case 0x0005, 0x0006: return u32().map(UInt64.init)
            default:
                _ = skipValue(type)
                return nil
            }
        }
    }
}

extension Data {
    func u16(_ offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func u32(_ offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    mutating func appendLE(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
    }

    mutating func appendLE(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
}

enum PTPError: LocalizedError {
    case refused(UInt16)
    case timeout
    case noSession
    case message(String)

    var errorDescription: String? {
        switch self {
        case .refused(let code): return String(format: "Camera refused PTP %04X", code)
        case .timeout: return "Camera did not answer"
        case .noSession: return "No camera session"
        case .message(let s): return s
        }
    }
}
