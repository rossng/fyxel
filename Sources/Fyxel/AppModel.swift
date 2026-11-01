import Foundation
import FyxelCore
import FyxelMock
import Observation
import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case overview = "Overview", devices = "Devices"
    case wifi = "Wi-Fi", wifiAdvanced = "Wi-Fi Settings", lan = "LAN", dhcp = "DHCP Reservations"
    case ports = "Port Forwarding", nat = "NAT", routing = "Routing & QoS"
    case firewall = "Firewall", parental = "Parental Control"
    case diagnostics = "Diagnostics", logs = "Logs", maintenance = "Maintenance", services = "Phone & USB"
    case explorer = "API Explorer"

    var id: String { rawValue }

    enum Group: String, CaseIterable { case status = "Status", network = "Network", security = "Security", system = "System" }

    var group: Group {
        switch self {
        case .overview, .devices: .status
        case .wifi, .wifiAdvanced, .lan, .dhcp, .ports, .nat, .routing: .network
        case .firewall, .parental: .security
        case .diagnostics, .logs, .maintenance, .services, .explorer: .system
        }
    }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .devices: "laptopcomputer.and.iphone"
        case .wifi: "wifi"
        case .wifiAdvanced: "wifi.router"
        case .lan: "network"
        case .dhcp: "list.bullet.rectangle"
        case .ports: "arrow.left.arrow.right"
        case .nat: "arrow.triangle.branch"
        case .routing: "point.topleft.down.to.point.bottomright.curvepath"
        case .firewall: "flame"
        case .parental: "figure.and.child.holdinghands"
        case .diagnostics: "stethoscope"
        case .logs: "doc.text.magnifyingglass"
        case .maintenance: "wrench.and.screwdriver"
        case .services: "phone.connection"
        case .explorer: "curlybraces"
        }
    }

    /// Spec-driven settings panels on this page (generic pages, and the palette's index).
    var specs: [ObjectSpec] {
        switch self {
        case .wifiAdvanced: Specs.wifi
        case .lan: Specs.lan
        case .nat: Specs.nat
        case .routing: Specs.routing
        case .firewall: Specs.firewall
        case .parental: Specs.parental
        case .maintenance: Specs.system
        case .services: Specs.services
        default: []
        }
    }

    /// Extra words the palette matches this section by.
    var keywords: String {
        switch self {
        case .overview: "status dashboard throughput wan internet public ip cpu memory"
        case .devices: "hosts clients computers phones"
        case .wifi: "wireless wlan ssid password network"
        case .wifiAdvanced: "wireless guest wps mesh radio schedule"
        case .lan: "dhcp dns ipv6 upnp ddns subnet"
        case .dhcp: "static lease reservation fixed ip"
        case .ports: "port forwarding nat upnp virtual server"
        case .nat: "dmz alg triggering"
        case .routing: "routes qos static policy"
        case .firewall: "acl dos security mac filter"
        case .parental: "kids schedule block sites"
        case .diagnostics: "ping traceroute nslookup arp multicast sessions"
        case .logs: "syslog security log"
        case .maintenance: "reboot firmware backup restore password time ntp remote management"
        case .services: "phone voip sip usb dlna cellular lte"
        case .explorer: "api json cgi debug"
        }
    }

    /// ⌘1…⌘9 for the first nine sections.
    var shortcut: KeyEquivalent? {
        let i = Section.allCases.firstIndex(of: self) ?? 99
        return i < 9 ? KeyEquivalent(Character(String(i + 1))) : nil
    }
}

/// Something to do once a section is showing: scroll to a panel, open an editor, etc. The
/// view that owns the relevant state picks it up and clears `AppModel.request`.
enum NavIntent: Equatable {
    /// Scroll to a `.revealAnchor` and flash it; `field` also highlights a spec field's label.
    case reveal(String, field: String? = nil)
    case editWiFi(Int), toggleWiFi(Int, on: Bool)
    case showDevice(mac: String)
    case addReservation, editReservation(Int)
    case addPortForward, editPortForward(Int)
    case netTool(DiagnosticKind)
    case logs(LogKind), logSettings
    case reboot
}

struct NavRequest: Equatable {
    let id = UUID()
    var intent: NavIntent
}

struct RateSample: Identifiable {
    var id: Date { at }
    var at: Date
    var down: Double  // bits/s
    var up: Double
}

struct HostRate { var down: Double; var up: Double }

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case loggedOut, loggingIn, loggedIn }

    // Settings
    var host: String { didSet { UserDefaults.standard.set(host, forKey: "host") } }
    var username: String { didSet { UserDefaults.standard.set(username, forKey: "username") } }

    var phase: Phase = .loggedOut
    var loginError: String?
    var lastError: String?
    var section: Section = .overview
    var lastUpdated: Date?
    /// Command palette (⌘K) and the navigation request it leaves for the destination view.
    var paletteOpen = false
    var request: NavRequest?
    /// What each spec section last loaded, so the palette can search configured values.
    var specRows: [String: [JSONValue]] = [:]
    /// Router account level ("high", "medium"…); some pages are refused below "high".
    var accountLevel = ""

    // Data
    var status: SystemStatus?
    var hosts: [LanHost] = []
    var hostRates: [String: HostRate] = [:]
    var customNames: [String: String] = [:]
    var rates: [RateSample] = []
    var reservations: [DHCPReservation] = []
    var lanConfig: JSONValue = .null
    var wlan: [JSONValue] = []
    var natRules: [PortForwardRule] = []
    var natConf: JSONValue = .null
    var upnp: [UPnPMapping] = []
    var firewall: JSONValue = .null
    var routes: [JSONValue] = []

    /// The only way the app reaches a router. Real hardware or `MockRouter`.
    private(set) var client: any RouterAPI
    /// Demo mode: talk to `MockRouter` instead of hardware (login screen button or FYXEL_MOCK=1).
    private(set) var isDemo = false
    /// Seconds between traffic polls. The demo polls faster so graphs fill up quickly.
    var pollInterval: Double { isDemo ? 1 : 3 }
    private var password: String?
    private var pollTask: Task<Void, Never>?
    private var lastTraffic: TrafficSnapshot?
    /// Borrowed session (dev hook): never log it out, it belongs to someone else.
    private(set) var borrowedSession = false

    init() {
        let d = UserDefaults.standard
        host = d.string(forKey: "host") ?? "192.168.1.1"
        username = d.string(forKey: "username") ?? "admin"
        client = RouterClient(host: d.string(forKey: "host") ?? "192.168.1.1")
        let env = ProcessInfo.processInfo.environment
        if env["FYXEL_MOCK"] != nil {
            startDemo(level: env["FYXEL_MOCK_LEVEL"] ?? "high")
        } else {
            restoreFromEnvironment()
        }
    }

    /// Switch to the in-memory mock router and log in to it.
    func startDemo(level: String = "high") {
        isDemo = true
        client = MockRouter(level: level)
        Task { await login(password: "demo", remember: false) }
    }

    /// Dev hook: reuse an existing session (same env vars as fyxelctl) instead of logging in.
    private func restoreFromEnvironment() {
        let env = ProcessInfo.processInfo.environment
        guard let cookie = env["FYXEL_SESSION"], let k = env["FYXEL_AESKEY"], let key = Data(base64Encoded: k) else { return }
        let s = RouterSession(cookie: cookie, aesKey: key, csrfToken: env["FYXEL_CSRF"] ?? "")
        guard let c = client as? RouterClient else { return }
        borrowedSession = true
        phase = .loggedIn
        Task {
            await c.restore(s)
            startPolling()
        }
    }

    var hasSavedPassword: Bool { CredentialStore.hasPassword(user: username, host: host) }

    // MARK: Auth

    func unlockWithKeychain() async {
        do {
            let pw = try await CredentialStore.unlock(user: username, host: host)
            await login(password: pw, remember: false)
        } catch {
            loginError = error.localizedDescription
        }
    }

    func login(password pw: String, remember: Bool) async {
        phase = .loggingIn
        loginError = nil
        if !isDemo, client.host != host { client = RouterClient(host: host) }
        do {
            try await client.login(username: username, password: pw)
            password = pw
            let user = username
            await client.setCredentialProvider { (user, pw) }
            if remember, !isDemo { try CredentialStore.save(password: pw, user: username, host: host) }
            accountLevel = await client.accountLevel
            phase = .loggedIn
            startPolling()
        } catch {
            phase = .loggedOut
            loginError = error.localizedDescription
        }
    }

    func logout() async {
        pollTask?.cancel()
        await client.setCredentialProvider(nil)
        if !borrowedSession { await client.logout() }
        borrowedSession = false
        password = nil
        phase = .loggedOut
        status = nil; hosts = []; rates = []; lastTraffic = nil
        specRows = [:]; paletteOpen = false; request = nil
        if isDemo { isDemo = false; client = RouterClient(host: host) }
    }

    func forgetSavedPassword() { CredentialStore.delete(user: username, host: host) }

    func trustNewCertificate() {
        client.forgetPinnedCertificate()
        lastError = nil
        loginError = nil
    }

    // MARK: Polling

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var tick = 0
            await self?.refreshAll()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 3))
                guard let self, !Task.isCancelled else { return }
                tick += 1
                await self.refreshTraffic()
                if tick % 2 == 0 { await self.refreshHosts() }
                if tick % 5 == 0 { await self.refreshStatus() }
            }
        }
    }

    func refreshAll() async {
        async let a: Void = refreshStatus()
        async let b: Void = refreshTraffic()
        async let c: Void = refreshHosts()
        async let d: Void = refreshConfig()
        _ = await (a, b, c, d)
    }

    private func run<T>(_ what: String, _ op: () async throws -> T) async -> T? {
        do {
            let v = try await op()
            lastUpdated = Date()
            if lastError?.hasPrefix(what) == true { lastError = nil }
            return v
        } catch is CancellationError {
            return nil
        } catch {
            if let e = error as? RouterError, e == .sessionExpired || e == .notLoggedIn {
                pollTask?.cancel(); phase = .loggedOut; loginError = "Session expired — log in again."
            }
            lastError = "\(what): \(error.localizedDescription)"
            return nil
        }
    }

    func refreshStatus() async {
        if let o = await run("Status", { try await client.dal("status") }), let first = o.first {
            status = SystemStatus(first)
        }
    }

    func refreshTraffic() async {
        guard let o = await run("Traffic", { try await client.dal("Traffic_Status") }), let j = o.first else { return }
        let snap = TrafficSnapshot(j)
        customNames = snap.customNames
        if let prev = lastTraffic, let w = snap.wan, let pw = prev.wan, w.ifName == pw.ifName {
            let dt = snap.at.timeIntervalSince(prev.at)
            let down = Double(w.bytesReceived - pw.bytesReceived) * 8 / dt
            let up = Double(w.bytesSent - pw.bytesSent) * 8 / dt
            if dt > 0.5, down >= 0, up >= 0 {
                rates.append(RateSample(at: snap.at, down: down, up: up))
                if rates.count > 200 { rates.removeFirst(rates.count - 200) }
            }
            var hr: [String: HostRate] = [:]
            for (mac, b) in snap.hostBytes {
                guard let p = prev.hostBytes[mac], dt > 0.5 else { continue }
                // Host counters are from the device's point of view: "sent" = upload.
                let up = Double(b.sent - p.sent) * 8 / dt, down = Double(b.received - p.received) * 8 / dt
                if up >= 0, down >= 0 { hr[mac] = HostRate(down: down, up: up) }
            }
            hostRates = hr
        }
        lastTraffic = snap
    }

    func refreshHosts() async {
        if let o = await run("Devices", { try await client.dal("lanhosts") }) {
            hosts = o.first?["lanhosts"].array.map(LanHost.init) ?? []
        }
    }

    func refreshConfig() async {
        async let r = run("DHCP") { try await client.dal("static_dhcp") }
        async let l = run("LAN") { try await client.dal("lan") }
        async let w = run("Wi-Fi") { try await client.dal("wlan") }
        async let n = run("NAT") { try await client.dal("nat") }
        async let nc = run("NAT") { try await client.dal("nat_conf") }
        async let u = run("UPnP") { try await client.dal("lanadv") }
        async let f = run("Firewall") { try await client.dal("firewall") }
        async let rt = run("Routes") { try await client.get("/cgi-bin/RoutingTable_handle") }
        if let v = await r { reservations = v.map(DHCPReservation.init) }
        if let v = await l { lanConfig = v.first ?? .null }
        if let v = await w { wlan = v }
        if let v = await n { natRules = v.map(PortForwardRule.init) }
        if let v = await nc { natConf = v.first ?? .null }
        if let v = await u { upnp = v.count > 1 ? v[1].array.map(UPnPMapping.init) : [] }
        if let v = await f { firewall = v.first ?? .null }
        if let v = await rt { routes = v[0]["result"].array }
    }

    // MARK: Maintenance

    /// Shown as a banner while the router is rebooting / flashing.
    var maintenanceStatus: String?

    func rebootAndWait() async {
        do { try await client.reboot() } catch {
            // The router often drops the connection mid-reply; only report real refusals.
            if case RouterError.dal = error { lastError = "Reboot: \(error.localizedDescription)"; return }
        }
        await waitForRouterAndRelogin()
    }

    /// After a reboot (reboot, restore, firmware): wait for the web server, then log in again.
    func waitForRouterAndRelogin() async {
        pollTask?.cancel()
        let started = Date()
        maintenanceStatus = "Router is restarting…"
        let ok = await client.waitUntilBack { _ in
            Task { @MainActor in self.maintenanceStatus = "Router is restarting… \(Fmt.duration(Date().timeIntervalSince(started)))" }
        }
        maintenanceStatus = nil
        guard ok else { lastError = "The router didn't come back within 10 minutes."; return }
        if let pw = password {
            await login(password: pw, remember: false)
        } else {
            startPolling()
        }
    }

    /// Changes the admin password, updates the Keychain item if there is one, and logs back in.
    func changePassword(old: String, new: String) async -> Bool {
        do {
            try await client.changePassword(account: username, old: old, new: new)
        } catch {
            lastError = "Password: \(error.localizedDescription)"
            return false
        }
        if !isDemo, CredentialStore.hasPassword(user: username, host: host) {
            try? CredentialStore.save(password: new, user: username, host: host)
        }
        password = new
        await login(password: new, remember: false)
        return true
    }

    // MARK: Helpers

    /// Show a section, optionally with something for it to do when it appears.
    func go(_ s: Section, _ intent: NavIntent? = nil) {
        section = s
        request = intent.map { NavRequest(intent: $0) }
    }

    func name(for mac: String) -> String? {
        let m = mac.lowercased()
        if let n = customNames[m] { return n }
        return hosts.first { $0.mac == m }.map(\.displayName)
    }

    func host(forMAC mac: String) -> LanHost? { hosts.first { $0.mac == mac.lowercased() } }

    /// Runs a write, surfaces errors, then reloads config. Returns true on success.
    @discardableResult
    func write(_ what: String, _ op: () async throws -> Void) async -> Bool {
        do {
            try await op()
            lastError = nil
            await refreshConfig()
            await refreshHosts()
            return true
        } catch {
            lastError = "\(what): \(error.localizedDescription)"
            return false
        }
    }
}
