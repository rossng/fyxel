import Foundation

/// Active NAT sessions per LAN host, from the System Monitor's NAT page.
public struct NATSessionCount: Sendable, Identifiable, Hashable {
    public var id: String { ip + mac }
    public var ip: String
    public var mac: String
    public var sessions: Int
}

extension RouterAPI {
    /// GET /cgi-bin/Traffic_Status?mode=NATStatus_handle → `[{result: "ip mac n ip mac n …"}]`.
    public func natSessionCounts() async throws -> [NATSessionCount] {
        let j = try await get("/cgi-bin/Traffic_Status?mode=NATStatus_handle")
        let text = j[0]["result"].string ?? j["result"].str
        return Self.parseNATCounts(text)
    }

    public static func parseNATCounts(_ text: String) -> [NATSessionCount] {
        let t = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var out: [NATSessionCount] = []
        var i = 0
        while i + 2 < t.count {
            if let n = Int(t[i + 2]) { out.append(NATSessionCount(ip: t[i], mac: t[i + 1].lowercased(), sessions: n)) }
            i += 3
        }
        return out
    }
}

// MARK: - Ping / traceroute / nslookup

public enum DiagnosticKind: Int, Sendable, CaseIterable, Identifiable {
    case ping = 0, traceroute = 1, nslookup = 2
    public var id: Int { rawValue }
    public var label: String { ["Ping", "Traceroute", "NSLookup"][rawValue] }
    var repetitions: Int { self == .ping ? 4 : 3 }
}

public struct NATSessionTotals: Sendable { public var current: Int; public var max: Int }

public struct ARPEntry: Sendable, Identifiable, Hashable {
    public var id: String { ip + mac + interface }
    public var ip, mac, interface, name: String
    public var isIPv6: Bool
}

public struct MulticastGroup: Sendable, Identifiable, Hashable {
    public var id: String { interface + group }
    public var interface, group, filterMode: String
    public var members: [String]
    public var sources: [String]
    public var isIPv6: Bool
}

extension RouterAPI {
    /// Starts a test on the router and streams the growing output text. Ends when the router
    /// reports a terminal state, or after `timeout`.
    public func runDiagnostic(_ kind: DiagnosticKind, host: String, ipv6: Bool = false,
                              timeout: Duration = .seconds(90)) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                do {
                    let obj: [String: String] = [
                        "ProtocolVersion": kind == .nslookup ? "" : (ipv6 ? "IPv6" : "IPv4"), "Host": host,
                        "DiagnosticsState": "Requested", "DNSServer": kind == .nslookup ? "127.0.0.1" : "",
                        "NumberOfRepetitions": String(kind.repetitions), "type": String(kind.rawValue),
                    ]
                    var body = JSONValue.object(obj.mapValues { .string($0) })
                    body["NumberOfRepetitions"] = .int(Int64(kind.repetitions))
                    body["type"] = .int(Int64(kind.rawValue))
                    try await dalWrite(.PUT, oid: "PINGTEST", body)
                    let deadline = ContinuousClock.now + timeout
                    var last = ""
                    while ContinuousClock.now < deadline {
                        try await Task.sleep(for: .seconds(1))
                        var q = obj; q["DalGetOneObject"] = "y"
                        let state = (try? await dal("PINGTEST", query: q).first?["DiagnosticsState"].str) ?? ""
                        let r = try await get("/cgi-bin/Diagnostic_Result")
                        let text = r[0]["result"].string ?? r["result"].str
                        if text != last { last = text; cont.yield(text) }
                        if !state.isEmpty, state != "Requested", state != "None" { break }
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    public func natSessionTotals() async throws -> NATSessionTotals {
        let j = try await get("/cgi-bin/NATSession_handle")
        let o = j.array.first ?? j
        return NATSessionTotals(current: o["CurrentNatSession"].int ?? 0, max: o["MaxNatSession"].int ?? 0)
    }

    public func arpTable() async throws -> [ARPEntry] {
        let j = try await get("/cgi-bin/ARPTable_handle")
        let o = j.array.first ?? j
        func parse(_ a: JSONValue, v6: Bool) -> [ARPEntry] {
            a.array.map { ARPEntry(ip: $0["ip"].str, mac: $0["mac"].str.lowercased(), interface: $0["intf"].str, name: $0["name"].str, isIPv6: v6) }
        }
        return parse(o["result"], v6: false) + parse(o["resultv6"], v6: true)
    }

    public func multicastGroups() async throws -> [MulticastGroup] {
        let j = try await get("/cgi-bin/McastSt?action=get")
        let o = j.array.first ?? j
        func parse(_ a: JSONValue, v6: Bool) -> [MulticastGroup] {
            a.array.map { g in
                MulticastGroup(interface: g["intf"].str, group: g["grp"].str, filterMode: g["fmode"].str,
                               members: (g["member"].array + g["Member"].array).map { $0["host"].str },
                               sources: g["source"].array.map { $0["addr"].str }, isIPv6: v6)
            }
        }
        return parse(o["igmpSt"], v6: false) + parse(o["mldSt"], v6: true)
    }
}

// MARK: - Logs

public struct LogLine: Sendable, Identifiable, Hashable {
    public var id: Int
    public var raw: String
    public var category: String
    public var time: String
    public var facility: String
    public var level: String
    public var message: String

    /// `[category] Mon DD HH:MM:SS facility.level message…` (syslog pads single-digit days).
    public init(id: Int, raw: String) {
        self.id = id
        self.raw = raw
        var rest = Substring(raw)
        category = ""
        if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            category = String(rest[rest.index(after: rest.startIndex)..<close])
            rest = rest[rest.index(after: close)...]
        }
        let parts = rest.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        if parts.count >= 5, parts[3].contains(".") {
            time = "\(parts[0]) \(parts[1]) \(parts[2])"
            let fl = parts[3].split(separator: ".", maxSplits: 1)
            facility = String(fl[0])
            level = fl.count > 1 ? String(fl[1]) : ""
            message = String(parts[4])
        } else {
            time = ""; facility = ""; level = ""
            message = rest.trimmingCharacters(in: .whitespaces)
        }
    }

    public static let levels = ["emerg", "alert", "crit", "err", "warning", "notice", "info", "debug"]
    public var severity: Int { Self.levels.firstIndex(of: level) ?? 6 }
}

public enum LogKind: String, Sendable, CaseIterable, Identifiable {
    case system = "syslog", security = "securitylog"
    public var id: String { rawValue }
    var iid: String { self == .system ? "[1,0,0,0,0,0]" : "[2,0,0,0,0,0]" }
    public var label: String { self == .system ? "System" : "Security" }
}

extension RouterAPI {
    public func logCategories(_ kind: LogKind) async throws -> [String] {
        try await dal("log", query: ["DalGetOneObject": "y", "Category": kind.rawValue]).map { $0["Name"].str }
    }

    /// Oldest first.
    public func logLines(_ kind: LogKind, category: String? = nil) async throws -> [LogLine] {
        var path = "/cgi-bin/LogResult?action=GET_LOG&oid=RDM_OID_LOG_CLASSIFY&iid=\(kind.iid)"
        if let c = category, !c.isEmpty { path += "&category=\(c)" }
        let j = try await get(path)
        let o = j.array.first ?? j
        return o["result"].array.enumerated().map { LogLine(id: $0.offset, raw: $0.element.str) }
    }

    public func clearLog(_ kind: LogKind) async throws {
        _ = try await request(.POST, "/cgi-bin/LogResult?action=DEL_LOG&oid=RDM_OID_LOG_CLASSIFY&sid=\(kind.rawValue)&iid=\(kind.iid)",
                              query: [:], body: nil)
    }
}
