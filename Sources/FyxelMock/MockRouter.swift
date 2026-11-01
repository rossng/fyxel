import Foundation
import FyxelCore

/// An in-memory stand-in for the router, speaking the same plaintext JSON protocol as
/// `RouterClient` after decryption. DAL objects live in tables keyed by oid and support the
/// router's GET / POST (add) / PUT (edit) / DELETE semantics, so every operation in FyxelCore
/// works against it unchanged. Traffic counters, uptime and CPU move over time.
///
///     let api: any RouterAPI = MockRouter()            // instead of RouterClient(host:)
public actor MockRouter: RouterAPI {
    public nonisolated let host: String
    public var accountLevel: String { loggedIn ? level : "" }

    private let level: String
    private let latency: Duration
    private var loggedIn = false
    private var tables: [String: [JSONValue]] = [:]
    /// oids the account level isn't allowed to read (mimics ZCFG_REQUEST_REJECT).
    private var rejected: Set<String>
    private var devices = Fixtures.devices
    private var hostCounters: [String: (sent: Int64, received: Int64)] = [:]
    private var wanCounters: (sent: Int64, received: Int64) = (8_310_224_118, 162_448_901_337)
    private var lastTick = Date()
    private let started = Date()
    private var customNames: [String: String] = [:]
    private var blocked: Set<String> = []
    private var leds = true
    private var diag: (kind: Int, host: String, started: Date)?
    private var clearedLogs: Set<String> = []
    private var handlers: [String: @Sendable (MockRouter, [String: String], JSONValue?) async throws -> JSONValue] = [:]
    /// Every write the mock received, oldest first. Handy in tests.
    public private(set) var writeLog: [(method: HTTPMethod, path: String, body: JSONValue?)] = []

    /// - Parameters:
    ///   - level: account level to emulate. "medium" rejects the same oids the real firmware does.
    ///   - latency: simulated round-trip time per request.
    public init(host: String = "demo.router", level: String = "high", latency: Duration = .milliseconds(60)) {
        self.host = host
        self.level = level
        self.latency = latency
        rejected = level == "high" ? [] : Self.mediumRejected
        var t: [String: [JSONValue]] = Fixtures.misc.merging(Fixtures.settings) { _, b in b }
        t["wlan"] = Fixtures.wlan()
        t["static_dhcp"] = Fixtures.reservations
        t["nat"] = Fixtures.nat
        t["lan"] = [Fixtures.lan]
        t["lanadv"] = Fixtures.lanadv
        t["nat_conf"] = [Fixtures.natConf]
        tables = t
        for d in Fixtures.devices { hostCounters[d.mac] = (Int64.random(in: 1...9) << 26, Int64.random(in: 1...9) << 29) }
    }

    static let mediumRejected: Set<String> = [
        "wan", "qos", "qos_class", "qos_queue", "qos_shaper", "qos_policer", "static_route", "policy_route",
        "dns_route", "time", "system", "sip_account", "sip_sp", "tr69", "snmp", "rip", "intf_group", "igmp_mld",
        "ethctl", "scheduler", "speeddial", "email_ntfy", "cellular",
    ]

    // MARK: RouterAPI

    public func login(username: String, password: String) async throws {
        try await Task.sleep(for: latency * 4)
        guard !password.isEmpty else { throw RouterError.loginFailed("Invalid Username or Password") }
        loggedIn = true
    }

    public func logout() async { loggedIn = false }
    public func setCredentialProvider(_ p: CredentialProvider?) async {}
    public nonisolated var pinnedFingerprint: String? { "mock — no TLS" }
    public nonisolated func forgetPinnedCertificate() {}

    public func upload(_ path: String, field: String, fileName: String, data: Data) async throws -> JSONValue {
        guard loggedIn else { throw RouterError.notLoggedIn }
        try await Task.sleep(for: latency * 10)
        writeLog.append((.POST, path, ["file": .string(fileName), "bytes": .int(Int64(data.count))]))
        return ["result": "ZCFG_SUCCESS"]
    }

    public func isReachable() async -> Bool { true }

    public func download(_ path: String) async throws -> Data {
        guard loggedIn else { throw RouterError.notLoggedIn }
        try await Task.sleep(for: latency * 5)
        return JSONValue.object(tables.mapValues { .array($0) }).encoded(pretty: true)
    }

    public func request(_ method: HTTPMethod, _ path: String, query: [String: String], body: JSONValue?) async throws -> JSONValue {
        guard loggedIn else { throw RouterError.notLoggedIn }
        try await Task.sleep(for: latency)
        var q = query
        var base = path
        if let comps = URLComponents(string: path) {
            base = comps.path
            for item in comps.queryItems ?? [] { q[item.name] = item.value ?? "" }
        }
        if method != .GET { writeLog.append((method, path, body ?? .object(q.mapValues { .string($0) }))) }
        if let h = handlers[base] { return try await h(self, q, body) }
        switch base {
        case "/cgi-bin/DAL":
            return dal(method, oid: q["oid"] ?? "", query: q, body: body)
        case "/cgi-bin/RoutingTable_handle":
            return Fixtures.routes
        case "/cgi-bin/Diagnostic_Result":
            guard let d = diag else { return [["result": ""]] }
            let step = Int(Date().timeIntervalSince(d.started))
            return [["result": .string(Fixtures.pingOutput(d.kind, host: d.host, step: step))]]
        case "/cgi-bin/Traffic_Status" where q["mode"] == "NATStatus_handle":
            let text = devices.filter(\.active).map { d in
                "\(d.ip) \(d.mac) \(max(1, Int((d.rate.down + d.rate.up) / 4000) + Int.random(in: 0...6)))"
            }.joined(separator: " ")
            return [["result": .string(text + " ")]]
        case "/cgi-bin/NATSession_handle":
            return [["CurrentNatSession": .int(Int64(1180 + Int.random(in: -40...40))), "MaxNatSession": 16384]]
        case "/cgi-bin/ARPTable_handle":
            let v4: [JSONValue] = devices.filter(\.active).map { ["ip": .string($0.ip), "mac": .string($0.mac), "intf": "br0", "name": ""] }
            let v6: [JSONValue] = devices.filter(\.active).prefix(4).enumerated().map { i, d in
                ["ip": .string("fe80::\(String(format: "%x", 0x1a2b + i * 0x111)):ff:fe\(String(d.mac.suffix(5)).replacingOccurrences(of: ":", with: ""))"),
                 "mac": .string(d.mac), "intf": "br0", "name": ""]
            }
            return [["result": .array(v4), "resultv6": .array(v6)]]
        case "/cgi-bin/McastSt":
            return ["igmpSt": [
                ["intf": "br0", "grp": "239.255.255.250", "fmode": "EXCLUDE",
                 "member": [["host": "192.168.1.41"], ["host": "192.168.1.75"], ["host": "192.168.1.10"]], "source": []],
                ["intf": "br0", "grp": "224.0.0.251", "fmode": "EXCLUDE", "member": [["host": "192.168.1.23"], ["host": "192.168.1.24"]], "source": []],
            ], "mldSt": []]
        case "/cgi-bin/LEDStatus":
            if method == .PUT { leds = body?["status"].bool ?? leds }
            return ["isactive": .bool(leds)]
        case "/cgi-bin/GetMTDSize":
            return [["CompareSize": .int(q["from"] == "config" ? 1 << 20 : 64 << 20)]]
        case "/cgi-bin/LogResult":
            let kind = q["iid"]?.hasPrefix("[2") == true ? "securitylog" : "syslog"
            if q["action"] == "DEL_LOG" { clearedLogs.insert(kind); return [["Ret": "ZCFG_SUCCESS"]] }
            var lines = clearedLogs.contains(kind) ? [] : Fixtures.logLines(kind)
            if let c = q["category"], !c.isEmpty { lines = lines.filter { $0.hasPrefix("[\(c)]") } }
            return [["Ret": "ZCFG_SUCCESS", "result": .array(lines.map { .string($0) })]]
        case "/cgi-bin/Wireless", "/cgi-bin/Reboot", "/cgi-bin/UserLogout":
            return ["result": "ZCFG_SUCCESS"]
        case "/cgi-bin/Home_Networking":
            return [["Ret": "ZCFG_SUCCESS"]]
        default:
            return ["result": "ZCFG_NOT_FOUND", "ReplyMsg": .string("mock has no handler for \(base)")]
        }
    }

    // MARK: Extension points

    /// Register a handler for a non-DAL path (e.g. "/cgi-bin/Ping"). Replaces the default.
    public func handle(_ path: String, _ h: @escaping @Sendable (MockRouter, [String: String], JSONValue?) async throws -> JSONValue) {
        handlers[path] = h
    }

    /// Replace or seed a DAL table.
    public func setTable(_ oid: String, _ objects: [JSONValue]) { tables[oid] = objects }
    public func table(_ oid: String) -> [JSONValue] { tables[oid] ?? [] }

    // MARK: DAL emulation

    private func ok(_ extra: JSONValue = .null) -> JSONValue {
        var o: JSONValue = ["result": "ZCFG_SUCCESS", "ReplyMsg": "", "ReplyMsgMultiLang": ""]
        if !extra.isNull { o["Object"] = extra }
        return o
    }

    private func dal(_ method: HTTPMethod, oid: String, query q: [String: String], body: JSONValue?) -> JSONValue {
        if rejected.contains(oid) { return ["result": "ZCFG_REQUEST_REJECT", "ReplyMsg": "Request reject"] }
        if method == .GET, let dyn = dynamic(oid, query: q) { return ok(.array(dyn)) }
        if oid == "PINGTEST", method == .PUT, let b = body {
            diag = (b["type"].int ?? 0, b["Host"].str, Date())
            return ok()
        }
        if method == .PUT, let r = putHook(oid, body ?? .null) { return r }
        guard var rows = tables[oid] else {
            return ["result": "ZCFG_NOT_FOUND", "ReplyMsg": .string("mock has no table for \(oid)")]
        }
        switch method {
        case .GET:
            if q["DalGetOneObject"] == "y", let i = q["Index"].flatMap(Int.init) {
                return ok(.array(rows.filter { $0["Index"].int == i }))
            }
            return ok(.array(rows))
        case .POST:
            guard var o = body, o.object != nil else { return ok() }
            o["Index"] = .int(Int64((rows.compactMap { $0["Index"].int }.max() ?? 0) + 1))
            o["referenceIndex"] = .null
            rows.append(o.droppingNulls())
        case .PUT:
            for o in (body.map { $0.array.isEmpty ? [$0] : $0.array } ?? []) {
                if let i = o["Index"].int, let at = rows.firstIndex(where: { $0["Index"].int == i }) {
                    rows[at] = rows[at].merging(o)
                } else if rows.count == 1, o["Index"].isNull {
                    rows[0] = rows[0].merging(o)
                } else if rows.isEmpty {
                    rows = [o]
                }
            }
        case .DELETE:
            let i = (q["Index"] ?? q["idx"] ?? q["index"]).flatMap(Int.init)
            rows.removeAll { $0["Index"].int == i }
        }
        tables[oid] = rows
        return ok()
    }

    /// Objects whose contents are computed on each GET.
    private func dynamic(_ oid: String, query q: [String: String]) -> [JSONValue]? {
        switch oid {
        case "log":
            return (Fixtures.logCategories[q["Category"] ?? ""] ?? []).map { ["Name": .string($0)] }
        case "PINGTEST":
            guard let d = diag else { return [["DiagnosticsState": "None"]] }
            let done = Date().timeIntervalSince(d.started) > (d.kind == 2 ? 2 : 5.5)
            return [["DiagnosticsState": done ? "Complete" : "Requested"]]
        case "status":
            let up = Int(Date().timeIntervalSince(started))
            let cpu = 8 + Int(abs(sin(Date().timeIntervalSince1970 / 7)) * 18) + Int.random(in: 0...4)
            return [Fixtures.status(uptime: 86400 * 12 + 3600 * 7 + up, cpu: cpu,
                                    freeKB: 401_000 + Int.random(in: -6000...6000), wanUptime: 86400 * 3 + up)]
        case "lanhosts":
            let off = Int(Date().timeIntervalSince(started))
            var hosts = devices.map { Fixtures.lanhost($0, uptimeOffset: off) }
            for i in hosts.indices {
                let mac = hosts[i]["PhysAddress"].str
                if let n = customNames[mac] { hosts[i]["DeviceName"] = .string(n); hosts[i]["curHostName"] = .string(n) }
                hosts[i]["Internet_Blocking_Enable"] = .bool(blocked.contains(mac))
                if let c = hostCounters[mac] {
                    hosts[i]["X_ZYXEL_BytesSent"] = .int(c.sent); hosts[i]["X_ZYXEL_BytesReceived"] = .int(c.received)
                }
            }
            return [["lanhosts": .array(hosts)]]
        case "Traffic_Status":
            advanceCounters()
            let hosts: [JSONValue] = devices.map { d in
                let c = hostCounters[d.mac] ?? (0, 0)
                return ["PhysAddress": .string(d.mac), "X_ZYXEL_BytesSent": .int(c.sent), "X_ZYXEL_BytesReceived": .int(c.received)]
            }
            let names: [JSONValue] = customNames.map { ["MacAddress": .string($0.key), "HostName": .string($0.value)] }
            return [[
                "ipIface": [
                    ["Name": "LAN", "X_ZYXEL_IfName": "br0", "Status": "Up", "X_ZYXEL_DefaultGatewayIface": false],
                    ["Name": "WAN", "X_ZYXEL_IfName": "eth1.3", "Status": "Up", "X_ZYXEL_DefaultGatewayIface": true],
                ],
                "ipIfaceSt": [
                    ["BytesSent": 0, "BytesReceived": 0],
                    ["BytesSent": .int(wanCounters.sent), "BytesReceived": .int(wanCounters.received)],
                ],
                "hosts": .array(hosts), "changeIconName": .array(names),
            ]]
        default:
            return nil
        }
    }

    private func putHook(_ oid: String, _ body: JSONValue) -> JSONValue? {
        switch oid {
        case "lanhosts":
            let mac = body["MacAddress"].str.lowercased()
            if !body["HostName"].str.isEmpty { customNames[mac] = body["HostName"].str }
            if body["Internet_Blocking_Enable"].bool { blocked.insert(mac) } else { blocked.remove(mac) }
            return ok()
        case "wlan":
            var rows = tables["wlan"] ?? []
            for o in body.array.isEmpty ? [body] : body.array {
                guard let at = rows.firstIndex(where: { $0["Index"] == o["Index"] }) else { continue }
                var r = rows[at]
                for k in ["wlEnable", "SSID", "wlHide"] where !o[k].isNull { r[k] = o[k] }
                if let p = o["psk_value"].string { r["PskDisplay"] = .string(p); r["AutoGenPSK"] = false }
                if let c = o["channel"].int { r["AutoChannelEnable"] = .bool(c == 0); if c > 0 { r["channel"] = .int(Int64(c)) } }
                if let b = o["bandwidth"].string { r["bandwidth"] = .string((b == "0" ? "40" : b) + "MHz") }
                for k in ["X_ZYXEL_BssIdIsolation", "IsolationEnable", "SecurityMode", "wlpmf", "MaxAssociatedDevices"] where !o[k].isNull {
                    r[k] = o[k]
                }
                if let m = o["wpaMode"].string {
                    r["SecurityMode"] = .string(["wpa2psk": "WPA2-Personal", "wpa3sae": "WPA3-Personal",
                                                 "wpa2pskwpa3sae": "WPA3-Personal-Transition", "wpawpa2psk": "WPA-WPA2-Personal",
                                                 "none": "None"][m] ?? r["SecurityMode"].str)
                }
                if o["secMode"].int == 0 { r["SecurityMode"] = "None" }
                rows[at] = r
            }
            tables["wlan"] = rows
            return ok()
        default:
            return nil
        }
    }

    private func advanceCounters() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard dt > 0 else { return }
        let t = now.timeIntervalSince1970
        var totalDown = 0.0, totalUp = 0.0
        for (i, d) in devices.enumerated() where d.active {
            // Each device gets its own slow wave plus occasional bursts.
            let wave = 0.55 + 0.45 * sin(t / (11 + Double(i) * 3) + Double(i))
            let burst = Double.random(in: 0...1) > 0.93 ? Double.random(in: 2...6) : 1
            let down = d.rate.down * wave * burst * Double.random(in: 0.8...1.2) * dt
            let up = d.rate.up * wave * Double.random(in: 0.8...1.2) * dt
            var c = hostCounters[d.mac] ?? (0, 0)
            c.received += Int64(down); c.sent += Int64(up)
            hostCounters[d.mac] = c
            totalDown += down; totalUp += up
        }
        wanCounters.received += Int64(totalDown * 1.04)
        wanCounters.sent += Int64(totalUp * 1.04)
    }
}

