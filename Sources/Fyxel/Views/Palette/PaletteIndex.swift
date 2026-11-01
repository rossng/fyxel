import FyxelCore
import SwiftUI

/// One thing the command palette can find: a page, a panel, a setting, an action, or a
/// configured object (SSID, device, reservation, rule, or a value typed into a settings page).
struct PaletteItem: Identifiable {
    enum Kind: Int {
        case section, action, panel, setting, wifi, device, reservation, rule, value

        var label: String {
            switch self {
            case .section: "Page"
            case .action: "Action"
            case .panel: "Panel"
            case .setting: "Setting"
            case .wifi: "Wi-Fi"
            case .device: "Device"
            case .reservation: "Reservation"
            case .rule: "Port forward"
            case .value: "Value"
            }
        }

        /// Tie-breaker between kinds when matches are equally good.
        var weight: Int {
            switch self {
            case .section: 6
            case .action: 4
            case .panel, .wifi: 3
            case .device: 2
            case .setting, .reservation, .rule: 1
            case .value: 0
            }
        }
    }

    /// Stable across launches (used for "recently used").
    var id: String
    var kind: Kind
    var title: String
    /// Where it lives ("LAN › LAN & DHCP Server") or a one-line description.
    var subtitle: String
    /// Extra text that matches but isn't shown.
    var keywords = ""
    var icon: String
    /// Right-aligned hint, e.g. a keyboard shortcut.
    var hint: String?
    var run: @MainActor (AppModel) -> Void
}

@MainActor
enum PaletteIndex {
    struct Panel {
        var section: Section, anchor: String, title: String, icon: String, keywords: String
    }

    /// Hand-written panels (spec panels are found from `Section.specs`).
    static let panels: [Panel] = [
        .init(section: .overview, anchor: Anchor.throughput, title: "WAN Throughput", icon: "chart.xyaxis.line", keywords: "graph speed bandwidth download upload"),
        .init(section: .overview, anchor: Anchor.internet, title: "Internet", icon: "globe", keywords: "wan public ip gateway dns uptime"),
        .init(section: .overview, anchor: Anchor.system, title: "System", icon: "cpu", keywords: "cpu memory uptime firmware model"),
        .init(section: .overview, anchor: Anchor.ethernet, title: "Ethernet", icon: "cable.connector", keywords: "ports link speed"),
        .init(section: .overview, anchor: Anchor.wifiSummary, title: "Wi-Fi Radios", icon: "wifi", keywords: "channel bandwidth"),
        .init(section: .overview, anchor: Anchor.lanSummary, title: "LAN Summary", icon: "network", keywords: "dhcp pool"),
        .init(section: .overview, anchor: Anchor.routes, title: "Routing Table", icon: "point.topleft.down.to.point.bottomright.curvepath", keywords: "routes"),
        .init(section: .maintenance, anchor: Anchor.device, title: "Device", icon: "wifi.router", keywords: "reboot restart leds lights model firmware uptime"),
        .init(section: .maintenance, anchor: Anchor.config, title: "Configuration Backup", icon: "externaldrive", keywords: "back up restore settings file"),
        .init(section: .maintenance, anchor: Anchor.firmware, title: "Firmware", icon: "cpu", keywords: "upgrade update flash"),
        .init(section: .maintenance, anchor: Anchor.password, title: "Admin Password", icon: "key", keywords: "change login"),
        .init(section: .diagnostics, anchor: Anchor.netTools, title: "Network Tools", icon: "point.3.connected.trianglepath.dotted", keywords: "ping traceroute nslookup dns"),
        .init(section: .diagnostics, anchor: Anchor.natSessions, title: "NAT Sessions", icon: "arrow.left.arrow.right.circle", keywords: "connections conntrack"),
        .init(section: .diagnostics, anchor: Anchor.arp, title: "ARP / Neighbours", icon: "list.bullet.indent", keywords: "neighbor mac table"),
        .init(section: .diagnostics, anchor: Anchor.multicast, title: "Multicast Groups", icon: "dot.radiowaves.left.and.right", keywords: "igmp mld"),
    ]

    static func build(_ model: AppModel) -> [PaletteItem] {
        sections() + actions() + panelItems() + specItems() + wifiItems(model) + deviceItems(model)
            + reservationItems(model) + ruleItems(model) + valueItems(model)
    }

    static func sections() -> [PaletteItem] {
        Section.allCases.map { s in
            PaletteItem(id: "section:\(s.rawValue)", kind: .section, title: s.rawValue, subtitle: s.group.rawValue,
                        keywords: s.keywords, icon: s.icon, hint: s.shortcut.map { "⌘\($0.character)" }) { $0.go(s) }
        }
    }

    static func actions() -> [PaletteItem] {
        func a(_ id: String, _ title: String, _ sub: String, _ icon: String, keywords: String = "", hint: String? = nil,
               _ run: @escaping @MainActor (AppModel) -> Void) -> PaletteItem {
            PaletteItem(id: "action:\(id)", kind: .action, title: title, subtitle: sub, keywords: keywords, icon: icon, hint: hint, run: run)
        }
        var items = [
            a("refresh", "Refresh Everything", "Reload status, devices and settings", "arrow.clockwise", keywords: "reload", hint: "⌘R") { m in
                Task { await m.refreshAll() }
            },
            a("reboot", "Reboot Router…", "Asks first", "power", keywords: "restart") { m in m.request = NavRequest(intent: .reboot) },
            a("logout", "Log Out", "End this router session", "rectangle.portrait.and.arrow.right", keywords: "sign out", hint: "⇧⌘L") { m in
                Task { await m.logout() }
            },
            a("add-forward", "Add Port Forward…", "Port Forwarding", "plus", keywords: "new rule nat open port") { $0.go(.ports, .addPortForward) },
            a("add-reservation", "Add DHCP Reservation…", "DHCP Reservations", "plus", keywords: "new static lease fixed ip") { $0.go(.dhcp, .addReservation) },
            a("backup", "Back Up or Restore Configuration…", "Maintenance › Configuration", "externaldrive", keywords: "save settings file") {
                $0.go(.maintenance, .reveal(Anchor.config))
            },
            a("firmware", "Upgrade Firmware…", "Maintenance › Firmware", "cpu", keywords: "update flash") { $0.go(.maintenance, .reveal(Anchor.firmware)) },
            a("password", "Change Admin Password…", "Maintenance › Admin Password", "key") { $0.go(.maintenance, .reveal(Anchor.password)) },
            a("leds", "Turn LEDs On or Off", "Maintenance › Device", "lightbulb", keywords: "lights") { $0.go(.maintenance, .reveal(Anchor.device)) },
            a("log-settings", "Log Settings…", "Logs", "gearshape", keywords: "syslog remote level") { $0.go(.logs, .logSettings) },
        ]
        for k in DiagnosticKind.allCases {
            items.append(a("tool-\(k.label)", "\(k.label)…", "Diagnostics › Network Tools, run from the router", "point.3.connected.trianglepath.dotted") {
                $0.go(.diagnostics, .netTool(k))
            })
        }
        for k in LogKind.allCases {
            items.append(a("log-\(k.rawValue)", "Show \(k.label) Log", "Logs", "doc.text.magnifyingglass") { $0.go(.logs, .logs(k)) })
        }
        return items
    }

    static func panelItems() -> [PaletteItem] {
        let custom = panels.map { p in
            PaletteItem(id: "panel:\(p.anchor)", kind: .panel, title: p.title, subtitle: p.section.rawValue, keywords: p.keywords,
                        icon: p.icon) { $0.go(p.section, .reveal(p.anchor)) }
        }
        let spec = Section.allCases.flatMap { s in
            s.specs.map { spec in
                PaletteItem(id: "panel:\(Anchor.spec(spec))", kind: .panel, title: spec.title, subtitle: s.rawValue,
                            keywords: (spec.summary ?? "") + " " + spec.oid, icon: s.icon) { $0.go(s, .reveal(Anchor.spec(spec))) }
            }
        }
        return custom + spec
    }

    /// Every field of every spec panel.
    static func specItems() -> [PaletteItem] {
        Section.allCases.flatMap { s in
            s.specs.flatMap { spec in
                var seen = Set<String>()
                return spec.fields.compactMap { f -> PaletteItem? in
                    // Skip continuation labels like "(min)" and repeats.
                    guard !f.label.hasPrefix("("), seen.insert(f.label).inserted else { return nil }
                    let anchor = Anchor.spec(spec)
                    return PaletteItem(id: "field:\(spec.id):\(f.key)", kind: .setting, title: f.label,
                                       subtitle: "\(s.rawValue) › \(spec.title)", keywords: (f.help ?? "") + " " + f.key,
                                       icon: icon(for: f.kind)) { $0.go(s, .reveal(anchor, field: f.key)) }
                }
            }
        } + [
            // Log settings live in a sheet on the Logs page rather than a spec page.
            PaletteItem(id: "panel:logset", kind: .panel, title: Specs.logSettings.title, subtitle: "Logs",
                        keywords: Specs.logSettings.fields.map(\.label).joined(separator: " "), icon: "gearshape") { $0.go(.logs, .logSettings) },
        ]
    }

    static func wifiItems(_ model: AppModel) -> [PaletteItem] {
        model.wlan.enumerated().flatMap { i, rec -> [PaletteItem] in
            let ssid = rec["SSID"].str, idx = rec["Index"].int ?? i + 1, band = rec["band"].str, on = rec["wlEnable"].bool
            guard !ssid.isEmpty else { return [] }
            let guest = rec["X_ZYXEL_BssIdIsolation"].bool || rec["IsolationEnable"].bool
            let where_ = "\(band) · #\(idx)\(guest ? " · guest" : "")\(on ? "" : " · off")"
            return [
                PaletteItem(id: "wifi:\(idx)", kind: .wifi, title: ssid, subtitle: "Edit network · \(where_)",
                            keywords: "ssid wireless \(rec["SecurityMode"].str)", icon: on ? "wifi" : "wifi.slash") { $0.go(.wifi, .editWiFi(idx)) },
                PaletteItem(id: "wifi-copy:\(idx)", kind: .action, title: "Copy Password: \(ssid)", subtitle: "Wi-Fi · \(where_)",
                            keywords: "psk key", icon: "doc.on.doc") { _ in copyToPasteboard(WiFiEdit(rec).password) },
                PaletteItem(id: "wifi-toggle:\(idx)", kind: .action, title: "Turn \(on ? "Off" : "On") \(ssid)", subtitle: "Wi-Fi · \(where_)",
                            keywords: on ? "disable" : "enable", icon: on ? "wifi.slash" : "wifi") { $0.go(.wifi, .toggleWiFi(idx, on: !on)) },
            ]
        }
    }

    static func deviceItems(_ model: AppModel) -> [PaletteItem] {
        model.hosts.map { h in
            let name = model.customNames[h.mac] ?? h.displayName
            let sub = [h.active ? h.ip : "offline", h.mac, h.vendor].filter { !$0.isEmpty }.joined(separator: " · ")
            return PaletteItem(id: "device:\(h.mac)", kind: .device, title: name, subtitle: sub,
                               keywords: "\(h.hostName) \(h.ip) \(h.reservedIP) \(h.connection)",
                               icon: h.isWifi ? "laptopcomputer.and.iphone" : "desktopcomputer") { $0.go(.devices, .showDevice(mac: h.mac)) }
        }
    }

    static func reservationItems(_ model: AppModel) -> [PaletteItem] {
        model.reservations.map { r in
            let name = model.name(for: r.mac) ?? "unknown device"
            return PaletteItem(id: "reservation:\(r.index)", kind: .reservation, title: "\(r.ip) — \(name)",
                               subtitle: "DHCP Reservations · \(r.mac)\(r.enabled ? "" : " · off")", keywords: "static lease",
                               icon: "pin") { $0.go(.dhcp, .editReservation(r.index)) }
        }
    }

    static func ruleItems(_ model: AppModel) -> [PaletteItem] {
        model.natRules.map { r in
            let ports = r.externalEnd > r.externalStart ? "\(r.externalStart)–\(r.externalEnd)" : "\(r.externalStart)"
            return PaletteItem(id: "rule:\(r.index)", kind: .rule, title: r.description.isEmpty ? "Rule \(r.index)" : r.description,
                               subtitle: "\(r.protoLabel) \(ports) → \(r.internalClient):\(r.internalStart)\(r.enabled ? "" : " · off")",
                               keywords: "port forward nat \(ports)", icon: "arrow.left.arrow.right") { $0.go(.ports, .editPortForward(r.index)) }
        }
    }

    /// Text, address and MAC values from any spec panel loaded this session (local DNS names,
    /// DDNS host, static routes, filter lists…). Wi-Fi names come from `wifiItems` instead.
    static func valueItems(_ model: AppModel) -> [PaletteItem] {
        var out: [PaletteItem] = []
        var seen = Set<String>()
        for s in Section.allCases {
            for spec in s.specs where spec.oid != "wlan" {
                guard let rows = model.specRows[spec.id] else { continue }
                let anchor = Anchor.spec(spec)
                for (i, row) in rows.enumerated() {
                    for f in spec.fields where f.isVisible(in: row) {
                        switch f.kind { case .text, .ipv4, .mac: break; default: continue }
                        let v = row[f.key].str.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard v.count >= 2, v != "0.0.0.0", seen.insert("\(spec.id)|\(f.key)|\(v)").inserted else { continue }
                        out.append(PaletteItem(id: "value:\(spec.id):\(i):\(f.key)", kind: .value, title: v,
                                               subtitle: "\(s.rawValue) › \(spec.title) › \(f.label)", icon: "character.cursor.ibeam") {
                            $0.go(s, .reveal(anchor, field: f.key))
                        })
                    }
                }
            }
        }
        return out
    }

    static func icon(for kind: FieldSpec.Kind) -> String {
        switch kind {
        case .bool: "switch.2"
        case .int, .seconds: "number"
        case .ipv4, .mac: "network"
        case .password: "key"
        case .choice: "list.bullet"
        case .text, .readOnly: "textformat"
        }
    }
}

/// Ranks items against a query. Each whitespace-separated word has to match the title or,
/// for less, the subtitle/keywords, so "guest pass" finds "Password" under Guest Networks.
struct PaletteRanker {
    struct Ranked { var item: PaletteItem; var score: Int; var titleHits: [Int] }

    var recent: [String]

    func rank(_ items: [PaletteItem], query: String, limit: Int = 60) -> [Ranked] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.isEmpty {
            // Recently used first, then pages and actions.
            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let rec = recent.compactMap { byID[$0] }
            let recIDs = Set(rec.map(\.id))
            let rest = items.filter { ($0.kind == .section || $0.kind == .action) && !recIDs.contains($0.id) }
            return (rec + rest).prefix(limit).map { Ranked(item: $0, score: 0, titleHits: []) }
        }
        var out: [Ranked] = []
        for item in items {
            var total = 0, hits = Set<Int>(), ok = true
            let context = item.subtitle + " " + item.keywords
            for w in words {
                if let r = FuzzyMatch.match(w, item.title), r.score > 0 {
                    total += r.score; hits.formUnion(r.positions)
                } else if let r = FuzzyMatch.match(w, context), r.score > 0 {
                    total += r.score / 2
                } else {
                    ok = false; break
                }
            }
            guard ok else { continue }
            if let i = recent.firstIndex(of: item.id) { total += 8 - min(i, 7) }
            out.append(Ranked(item: item, score: total + item.kind.weight, titleHits: hits.sorted()))
        }
        out.sort { $0.score != $1.score ? $0.score > $1.score : $0.item.title.count < $1.item.title.count }
        return Array(out.prefix(limit))
    }
}
