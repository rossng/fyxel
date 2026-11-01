import Charts
import FyxelCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView { OverviewContent() }
    }
}

struct OverviewContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let s = model.status {
                VStack(spacing: 14) {
                    ThroughputPanel()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14, alignment: .top)], spacing: 14) {
                        InternetPanel(status: s)
                        SystemPanel(status: s)
                        PortsPanel(status: s)
                        WiFiSummaryPanel(status: s)
                        LANPanel()
                        RoutesPanel()
                    }
                }
                .padding(16)
            } else {
                ProgressView().padding(80)
            }
        }
    }
}

struct ThroughputPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let samples = model.rates
        let peakDown = samples.map(\.down).max() ?? 0
        let peakUp = samples.map(\.up).max() ?? 0
        Panel(title: "WAN Throughput", systemImage: "chart.xyaxis.line") {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                stat("Down", samples.last?.down ?? 0, .blue)
                stat("Up", samples.last?.up ?? 0, .orange)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("peak ↓ \(Fmt.bits(peakDown))  ↑ \(Fmt.bits(peakUp))")
                    Text("last \(Fmt.duration(samples.last.map { $0.at.timeIntervalSince(samples[0].at) } ?? 0))")
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Chart(samples) { s in
                AreaMark(x: .value("t", s.at), y: .value("bps", s.down), series: .value("dir", "down"))
                    .foregroundStyle(.blue.opacity(0.25))
                LineMark(x: .value("t", s.at), y: .value("bps", s.down), series: .value("dir", "down"))
                    .foregroundStyle(.blue)
                LineMark(x: .value("t", s.at), y: .value("bps", s.up), series: .value("dir", "up"))
                    .foregroundStyle(.orange)
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.bits(d)) } }
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .minute)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute()) } }
            .frame(height: 160)
        }
    }

    func stat(_ label: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Fmt.bits(v)).font(.system(.title2, design: .monospaced).weight(.semibold)).foregroundStyle(c)
        }
    }
}

struct InternetPanel: View {
    var status: SystemStatus
    var body: some View {
        Panel(title: "Internet", systemImage: "globe") {
            if let w = status.activeWan {
                Grid(alignment: .leading, verticalSpacing: 4) {
                    KV(k: "Status", v: "\(w.status) · \(w.encapsulation) over \(w.linkType)")
                    KV(k: "Public IP", v: w.ipv4, mono: true)
                    KV(k: "Netmask", v: w.mask, mono: true)
                    KV(k: "Gateway", v: w.gateway, mono: true)
                    KV(k: "DNS", v: w.dns.joined(separator: "\n"), mono: true)
                    if !w.ipv6.isEmpty { KV(k: "IPv6", v: w.ipv6.joined(separator: "\n"), mono: true) }
                    KV(k: "Interface", v: "\(w.serviceName) (\(w.ifName))", mono: true)
                    KV(k: "Connected", v: Fmt.duration(w.uptime))
                }
            } else {
                Label("No WAN connection", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            let others = status.wan.filter { $0.id != status.activeWan?.id }
            if !others.isEmpty {
                Divider()
                ForEach(others) { w in
                    HStack {
                        StatusDot(on: w.isUp)
                        Text(w.serviceName).mono()
                        Spacer()
                        Text(w.isUp ? (w.ipv4.isEmpty ? w.status : w.ipv4) : w.status).foregroundStyle(.secondary).mono()
                    }.font(.caption)
                }
            }
        }
    }
}

struct SystemPanel: View {
    var status: SystemStatus
    var body: some View {
        Panel(title: "System", systemImage: "cpu") {
            Grid(alignment: .leading, verticalSpacing: 4) {
                KV(k: "Model", v: status.model)
                KV(k: "Firmware", v: status.firmware, mono: true)
                KV(k: "Serial", v: status.serial, mono: true)
                KV(k: "Uptime", v: Fmt.duration(status.uptime))
                KV(k: "Reboots", v: "\(status.rebootCount) (last: \(status.lastRebootCause))")
                GridRow {
                    Text("CPU").foregroundStyle(.secondary)
                    Meter(fraction: Double(status.cpu) / 100, label: "\(status.cpu)%")
                }
                GridRow {
                    let used = status.memTotalKB - status.memFreeKB
                    Text("Memory").foregroundStyle(.secondary)
                    Meter(fraction: Double(used) / Double(max(status.memTotalKB, 1)),
                          label: "\(Fmt.bytes(Int64(used) * 1024)) / \(Fmt.bytes(Int64(status.memTotalKB) * 1024))")
                }
                KV(k: "Firewall", v: status.firewallEnabled ? "On (\(status.firewallLevel))" : "Off")
            }
        }
    }
}

struct PortsPanel: View {
    var status: SystemStatus
    var body: some View {
        Panel(title: "Ethernet", systemImage: "cable.connector") {
            HStack(spacing: 10) {
                ForEach(status.lanPorts.sorted { $0.label < $1.label }) { p in
                    VStack(spacing: 4) {
                        Image(systemName: "rectangle.connected.to.line.below")
                            .font(.title2)
                            .foregroundStyle(p.isUp ? Color.green : Color.secondary.opacity(0.4))
                        Text(p.label).font(.caption.bold())
                        Text(p.isUp ? speed(p.bitRate) : "—").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(p.name) \(p.mac) \(p.duplex)")
                }
            }
        }
    }
    func speed(_ mbps: Int) -> String { mbps >= 1000 ? "\(Double(mbps) / 1000)G" : "\(mbps)M" }
}

struct WiFiSummaryPanel: View {
    @Environment(AppModel.self) private var model
    var status: SystemStatus
    var body: some View {
        Panel(title: "Wi-Fi", systemImage: "wifi") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(status.wifi.filter(\.enabled)) { w in
                    GridRow {
                        StatusDot(on: w.enabled)
                        Text(w.ssid).bold().lineLimit(1)
                        Text(w.band).foregroundStyle(.secondary)
                        Text("ch \(w.channel)\(w.autoChannel ? "ᵃ" : "") · \(w.bandwidth.replacingOccurrences(of: "MHz", with: ""))")
                            .mono().font(.caption).lineLimit(1).fixedSize()
                            .help(w.autoChannel ? "auto channel" : "fixed channel")
                        Text("\(clients(w.path))").monospacedDigit().foregroundStyle(.secondary).help("clients")
                    }
                }
            }
            let off = status.wifi.filter { !$0.enabled }.count
            if off > 0 { Text("\(off) more SSIDs disabled").font(.caption).foregroundStyle(.secondary) }
        }
    }
    func clients(_ path: String) -> Int {
        model.hosts.filter { $0.active && $0.raw["Layer1Interface"].str.hasSuffix(path) }.count
    }
}

struct LANPanel: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let l = model.lanConfig
        let active = model.hosts.filter(\.active)
        Panel(title: "LAN", systemImage: "network") {
            Grid(alignment: .leading, verticalSpacing: 4) {
                KV(k: "Router IP", v: "\(l["IPAddress"].str)/\(RoutesPanel.prefixLength(l["SubnetMask"].str))", mono: true)
                KV(k: "DHCP", v: l["EnableDHCP"].bool ? "\(l["DHCP_MinAddress"].str) – \(l["DHCP_MaxAddress"].str)" : "off", mono: true)
                KV(k: "Lease", v: Fmt.duration(TimeInterval(l["DHCP_LeaseTime"].int ?? 0)))
                KV(k: "DNS", v: l["DNS_Type"].str)
                KV(k: "Devices", v: "\(active.count) online (\(active.filter(\.isWifi).count) Wi-Fi, \(active.filter { !$0.isWifi }.count) wired) · \(model.hosts.count) known")
                KV(k: "Reservations", v: "\(model.reservations.count)")
            }
        }
    }
}

struct RoutesPanel: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Panel(title: "Routing Table", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                GridRow {
                    Text("Destination"); Text("Gateway"); Text("Iface")
                }.font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(Array(model.routes.enumerated()), id: \.offset) { _, r in
                    GridRow {
                        Text("\(r["network"].str)/\(Self.prefixLength(r["mask"].str))")
                        Text(r["gateway"].str == "0.0.0.0" ? "link" : r["gateway"].str)
                        Text(r["intf"].str)
                    }.font(.system(size: 11, design: .monospaced))
                }
            }
            .textSelection(.enabled)
        }
    }
    static func prefixLength(_ mask: String) -> Int {
        mask.split(separator: ".").compactMap { UInt8($0) }.reduce(0) { $0 + $1.nonzeroBitCount }
    }
}

struct Meter: View {
    var fraction: Double
    var label: String
    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(fraction > 0.85 ? Color.red : fraction > 0.6 ? .orange : .accentColor)
                        .frame(width: max(4, g.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 6)
            Text(label).font(.callout.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
        }
    }
}
