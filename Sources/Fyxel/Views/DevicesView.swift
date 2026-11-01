import FyxelCore
import SwiftUI

struct DeviceRow: Identifiable {
    var id: String { host.mac }
    var host: LanHost
    var name: String
    var down: Double
    var up: Double
    var total: Int64 { host.bytesSent + host.bytesReceived }
    var ipSort: UInt32 {
        host.ip.split(separator: ".").compactMap { UInt32($0) }.reduce(0) { $0 << 8 | $1 }
    }
    var rssiSort: Int { host.rssi ?? -999 }
    var phySort: Int { host.phyRateMbps ?? 0 }
    var activeSort: Int { host.active ? 1 : 0 }
}

struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var onlineOnly = true
    @State private var selection: Set<String> = []
    @State private var sort = [KeyPathComparator(\DeviceRow.down, order: .reverse)]
    @State private var inspecting: LanHost?
    @State private var reserving: LanHost?
    @State private var renaming: LanHost?

    var rows: [DeviceRow] {
        model.hosts
            .filter { !onlineOnly || $0.active }
            .map { h in
                let r = model.hostRates[h.mac]
                return DeviceRow(host: h, name: model.customNames[h.mac] ?? h.displayName, down: r?.down ?? 0, up: r?.up ?? 0)
            }
            .filter { r in
                guard !search.isEmpty else { return true }
                let q = search.lowercased()
                return [r.name, r.host.ip, r.host.mac, r.host.vendor, r.host.hostName, r.host.connection]
                    .contains { $0.lowercased().contains(q) }
            }
            .sorted(using: sort)
    }

    var body: some View {
        let rows = rows
        Table(rows, selection: $selection, sortOrder: $sort) {
            identityColumns
            metricColumns
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .modifier(DeviceMenus(model: model, inspecting: $inspecting, reserving: $reserving, renaming: $renaming))
        .searchable(text: $search, placement: .toolbar, prompt: "Name, IP, MAC, vendor")
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $onlineOnly) { Label("Online only", systemImage: "line.3.horizontal.decrease.circle") }
                    .help("Show only online devices")
            }
        }
        .safeAreaInset(edge: .bottom) { footer(rows) }
        .onChange(of: model.request, initial: true) { _, r in
            guard case .showDevice(let mac)? = r?.intent else { return }
            model.request = nil
            if model.host(forMAC: mac)?.active == false { onlineOnly = false }
            search = mac
            selection = [mac]
        }
        .sheet(item: $inspecting) { h in JSONInspector(title: model.customNames[h.mac] ?? h.displayName, value: h.raw) }
        .sheet(item: $renaming) { h in RenameSheet(host: h, name: model.customNames[h.mac] ?? h.displayName) }
        .sheet(item: $reserving) { h in
            ReservationEditor(original: nil, prefillMAC: h.mac, prefillIP: h.ip)
        }
    }

    func footer(_ rows: [DeviceRow]) -> some View {
        let tDown = rows.reduce(0) { $0 + $1.down }, tUp = rows.reduce(0) { $0 + $1.up }
        return HStack {
            Text("\(rows.count) devices").foregroundStyle(.secondary)
            Spacer()
            Text("LAN ↓ \(Fmt.bits(tDown))  ↑ \(Fmt.bits(tUp))").monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }

    @TableColumnBuilder<DeviceRow, KeyPathComparator<DeviceRow>>
    var identityColumns: some TableColumnContent<DeviceRow, KeyPathComparator<DeviceRow>> {
            TableColumn("", value: \.activeSort) { r in StatusDot(on: r.host.active) }.width(14)
            TableColumn("Name", value: \.name) { r in
                HStack(spacing: 6) {
                    Image(systemName: r.host.isWifi ? "wifi" : "cable.connector").foregroundStyle(.secondary).frame(width: 16)
                    Text(r.name).lineLimit(1)
                    if r.host.blocked { Image(systemName: "nosign").foregroundStyle(.red).help("Internet blocked") }
                }
            }.width(min: 140, ideal: 190)
            TableColumn("IP", value: \.ipSort) { r in
                HStack(spacing: 4) {
                    Text(r.host.ip).mono()
                    if !r.host.reservedIP.isEmpty { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary).help("Reserved") }
                }
            }.width(min: 118, ideal: 125)
            TableColumn("MAC", value: \.host.mac) { r in Text(r.host.mac).mono().foregroundStyle(.secondary) }.width(min: 145, ideal: 150)
            TableColumn("Vendor", value: \.host.vendor) { r in Text(r.host.vendor).lineLimit(1).foregroundStyle(.secondary) }.width(min: 80, ideal: 130)
            TableColumn("Link", value: \.host.connection) { r in Text(linkText(r.host)).lineLimit(1) }.width(min: 80, ideal: 120)
    }

    @TableColumnBuilder<DeviceRow, KeyPathComparator<DeviceRow>>
    var metricColumns: some TableColumnContent<DeviceRow, KeyPathComparator<DeviceRow>> {
            TableColumn("RSSI", value: \.rssiSort) { r in
                if let rssi = r.host.rssi { SignalView(rssi: rssi) } else { Text("") }
            }.width(70)
            TableColumn("PHY", value: \.phySort) { r in
                Text(r.host.phyRateMbps.map { "\($0) Mb/s" } ?? "").monospacedDigit().foregroundStyle(.secondary)
            }.width(min: 60, ideal: 75)
            TableColumn("↓", value: \.down) { r in rate(r.down, .blue) }.width(min: 70, ideal: 85)
            TableColumn("↑", value: \.up) { r in rate(r.up, .orange) }.width(min: 70, ideal: 85)
            TableColumn("Total", value: \.total) { r in Text(Fmt.bytes(r.total)).monospacedDigit().foregroundStyle(.secondary) }.width(min: 60, ideal: 75)
            TableColumn("Up for", value: \.host.uptime) { r in Text(Fmt.duration(r.host.uptime)).monospacedDigit().foregroundStyle(.secondary) }.width(min: 55, ideal: 65)
    }

    func linkText(_ h: LanHost) -> String {
        if h.isWifi { return [h.connection.replacingOccurrences(of: "Wi-Fi ", with: ""), h.standard.isEmpty ? "" : "11\(h.standard)"].filter { !$0.isEmpty }.joined(separator: " ") }
        return h.connection.isEmpty ? h.interfaceType : h.connection
    }

    func rate(_ v: Double, _ c: Color) -> some View {
        Text(v < 1000 ? "" : Fmt.bits(v)).monospacedDigit().foregroundStyle(v > 1_000_000 ? c : .secondary)
    }
}

struct SignalView: View {
    var rssi: Int
    var body: some View {
        let bars = rssi >= -55 ? 4 : rssi >= -65 ? 3 : rssi >= -75 ? 2 : 1
        HStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(1...4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i <= bars ? color(bars) : Color.secondary.opacity(0.25))
                        .frame(width: 3, height: CGFloat(3 + i * 3))
                }
            }
            Text("\(rssi)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .help("\(rssi) dBm")
    }
    func color(_ b: Int) -> Color { b >= 3 ? .green : b == 2 ? .yellow : .red }
}


struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var host: LanHost
    @State var name: String
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename \(host.mac)").font(.headline)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit(save)
            HStack {
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(name.isEmpty || name.count > 64 || saving)
            }
        }
        .padding()
        .frame(width: 360)
    }

    func save() {
        saving = true
        Task {
            let ok = await model.write("Rename") { try await model.client.updateHost(host, name: name) }
            if ok { await model.refreshTraffic() }
            saving = false
            if ok { dismiss() }
        }
    }
}

struct DeviceMenus: ViewModifier {
    var model: AppModel
    @Binding var inspecting: LanHost?
    @Binding var reserving: LanHost?
    @Binding var renaming: LanHost?

    func body(content: Content) -> some View {
        content.contextMenu(forSelectionType: String.self) { macs in
            if let mac = macs.first, let h = model.host(forMAC: mac) { menu(h) }
        } primaryAction: { macs in
            if let mac = macs.first { inspecting = model.host(forMAC: mac) }
        }
    }

    @ViewBuilder func menu(_ h: LanHost) -> some View {
        Button("Copy IP") { copyToPasteboard(h.ip) }
        Button("Copy MAC") { copyToPasteboard(h.mac) }
        Button("Copy Name") { copyToPasteboard(model.customNames[h.mac] ?? h.displayName) }
        Divider()
        if h.reservedIP.isEmpty {
            Button("Reserve IP \(h.ip)…") { reserving = h }
        } else {
            Text("Reserved: \(h.reservedIP)")
        }
        Button("Rename…") { renaming = h }
        Button(h.blocked ? "Unblock Internet" : "Block Internet") {
            Task { await model.write("Block internet") { try await model.client.updateHost(h, blockInternet: !h.blocked) } }
        }
        Button("Wake on LAN") {
            Task { await model.write("Wake on LAN") { try await model.client.wakeOnLAN(mac: h.mac, ip: h.ip) } }
        }
        Button("Open http://\(h.ip)") { NSWorkspace.shared.open(URL(string: "http://\(h.ip)")!) }
        Divider()
        Button("Show Raw Record") { inspecting = h }
    }
}
