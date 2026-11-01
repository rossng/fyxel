import FyxelCore
import SwiftUI

struct DiagnosticsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NetToolPanel()
                NATSessionsPanel()
                HStack(alignment: .top, spacing: 14) {
                    ARPPanel()
                    MulticastPanel()
                }
            }
            .padding(16)
        }
    }
}

/// Ping / traceroute / nslookup, run from the router.
struct NetToolPanel: View {
    @Environment(AppModel.self) private var model
    @AppStorage("diag.host") private var host = "1.1.1.1"
    @State private var kind: DiagnosticKind = .ping
    @State private var ipv6 = false
    @State private var output = ""
    @State private var running: Task<Void, Never>?

    var body: some View {
        Panel(title: "Network Tools", systemImage: "point.3.connected.trianglepath.dotted") {
            HStack {
                Picker("", selection: $kind) { ForEach(DiagnosticKind.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                TextField("host or IP", text: $host).mono().frame(maxWidth: 320).onSubmit(run)
                if kind != .nslookup { Toggle("IPv6", isOn: $ipv6).toggleStyle(.checkbox) }
                if running != nil {
                    Button("Stop") { running?.cancel(); running = nil }
                    ProgressView().controlSize(.small)
                } else {
                    Button("Run", action: run).keyboardShortcut(.defaultAction).disabled(host.isEmpty)
                }
                Spacer()
                if !output.isEmpty { Button("Copy") { copyToPasteboard(output) } }
            }
            ScrollView {
                Text(output.isEmpty ? "Runs on the router, so results show what it can reach." : output)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(output.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 220)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    func run() {
        guard !host.isEmpty, running == nil else { return }
        output = ""
        let api = model.client, k = kind, h = host.trimmingCharacters(in: .whitespaces), v6 = ipv6
        running = Task {
            do {
                for try await text in api.runDiagnostic(k, host: h, ipv6: v6) { output = text }
                if output.isEmpty { output = "(no output)" }
            } catch is CancellationError {
            } catch {
                output += "\n\(error.localizedDescription)"
            }
            running = nil
        }
    }
}

struct NATSessionsPanel: View {
    @Environment(AppModel.self) private var model
    @State private var counts: [NATSessionCount] = []
    @State private var totals: NATSessionTotals?
    @State private var error: String?

    var body: some View {
        Panel(title: "NAT Sessions", systemImage: "arrow.left.arrow.right.circle") {
            HStack {
                if let t = totals {
                    Meter(fraction: Double(t.current) / Double(max(t.max, 1)), label: "\(t.current) / \(t.max) sessions")
                        .frame(maxWidth: 420)
                }
                Spacer()
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            let top = counts.sorted { $0.sessions > $1.sessions }
            let peak = top.first?.sessions ?? 1
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                ForEach(top.prefix(15)) { c in
                    GridRow {
                        Text(model.name(for: c.mac) ?? "unknown").lineLimit(1).frame(minWidth: 160, alignment: .leading)
                        Text(c.ip).mono().foregroundStyle(.secondary)
                        Capsule().fill(Color.accentColor.opacity(0.7))
                            .frame(width: max(3, 260 * CGFloat(c.sessions) / CGFloat(max(peak, 1))), height: 6)
                        Text("\(c.sessions)").monospacedDigit()
                    }
                }
            }
        }
        .task { await load() }
    }

    func load() async {
        do {
            async let c = model.client.natSessionCounts()
            async let t = model.client.natSessionTotals()
            counts = try await c
            totals = try? await t
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ARPPanel: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [ARPEntry] = []
    @State private var error: String?

    var body: some View {
        Panel(title: "ARP / Neighbours", systemImage: "list.bullet.indent") {
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow { Text("Address"); Text("MAC"); Text("Interface") }.font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(rows) { r in
                    GridRow {
                        Text(r.ip).mono().lineLimit(1)
                        Text(r.mac).mono().foregroundStyle(.secondary)
                        Text(r.name.isEmpty ? r.interface : r.name).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
            }
            .textSelection(.enabled)
        }
        .task {
            do { rows = try await model.client.arpTable() } catch { self.error = error.localizedDescription }
        }
    }
}

struct MulticastPanel: View {
    @Environment(AppModel.self) private var model
    @State private var groups: [MulticastGroup] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Panel(title: "Multicast Groups", systemImage: "dot.radiowaves.left.and.right") {
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            if loaded, groups.isEmpty, error == nil { Text("No IGMP/MLD groups joined.").foregroundStyle(.secondary) }
            ForEach(groups) { g in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(g.group).mono()
                        Text(g.interface).foregroundStyle(.secondary)
                        if !g.filterMode.isEmpty { Text(g.filterMode).font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(g.members.map { m in model.hosts.first { $0.ip == m }.map { model.customNames[$0.mac] ?? $0.displayName } ?? m }
                        .joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task {
            do { groups = try await model.client.multicastGroups() } catch { self.error = error.localizedDescription }
            loaded = true
        }
    }
}
