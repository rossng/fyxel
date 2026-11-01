import FyxelCore
import SwiftUI

struct DHCPView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Int?
    @State private var editing: DHCPReservation?
    @State private var adding = false
    @State private var deleting: DHCPReservation?

    var body: some View {
        Table(model.reservations, selection: $selection) {
            TableColumn("On") { r in StatusDot(on: r.enabled) }.width(24)
            TableColumn("#") { r in Text("\(r.index)").monospacedDigit().foregroundStyle(.secondary) }.width(24)
            TableColumn("Device") { r in
                let h = model.host(forMAC: r.mac)
                HStack {
                    StatusDot(on: h?.active ?? false)
                    Text(model.name(for: r.mac) ?? "unknown").lineLimit(1)
                }
            }.width(min: 140, ideal: 200)
            TableColumn("IP") { r in Text(r.ip).mono() }.width(min: 118, ideal: 125)
            TableColumn("MAC") { r in Text(r.mac).mono().foregroundStyle(.secondary) }.width(min: 145, ideal: 150)
            TableColumn("Current IP") { r in
                let cur = model.host(forMAC: r.mac)?.ip ?? ""
                Text(cur).mono().foregroundStyle(cur.isEmpty || cur == r.ip ? Color.secondary : Color.orange)
                    .help(cur.isEmpty || cur == r.ip ? "" : "Device currently has a different IP; it picks up the reservation on lease renewal")
            }.width(min: 118, ideal: 125)
            TableColumn("Vendor") { r in Text(model.host(forMAC: r.mac)?.vendor ?? "").foregroundStyle(.secondary).lineLimit(1) }.width(min: 80, ideal: 140)
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            if let id = ids.first, let r = model.reservations.first(where: { $0.index == id }) {
                Button("Edit…") { editing = r }
                Button("Copy IP") { copyToPasteboard(r.ip) }
                Button("Copy MAC") { copyToPasteboard(r.mac) }
                Divider()
                Button("Delete…", role: .destructive) { deleting = r }
            }
        } primaryAction: { ids in
            if let id = ids.first { editing = model.reservations.first { $0.index == id } }
        }
        .safeAreaInset(edge: .bottom) {
            let l = model.lanConfig
            HStack {
                Text("Pool \(l["DHCP_MinAddress"].str) – \(l["DHCP_MaxAddress"].str) · lease \(Fmt.duration(TimeInterval(l["DHCP_LeaseTime"].int ?? 0))) · DNS \(l["DNS_Type"].str)")
                Spacer()
                Text("\(model.reservations.count) reservations")
            }
            .font(.caption).foregroundStyle(.secondary).mono()
            .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
        }
        .toolbar {
            ToolbarItem { Button { adding = true } label: { Label("Add", systemImage: "plus") }.keyboardShortcut("n") }
            ToolbarItem {
                Button { deleting = model.reservations.first { $0.index == selection } } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selection == nil).keyboardShortcut(.delete)
            }
        }
        .sheet(item: $editing) { r in ReservationEditor(original: r) }
        .sheet(isPresented: $adding) { ReservationEditor(original: nil) }
        .confirmationDialog("Delete reservation for \(deleting?.ip ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let d = deleting { Task { await model.write("Delete reservation") { try await model.client.deleteReservation(index: d.index) } } }
            }
        }
    }
}

struct ReservationEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var original: DHCPReservation?
    @State private var mac: String
    @State private var ip: String
    @State private var enabled: Bool
    @State private var saving = false

    init(original: DHCPReservation?, prefillMAC: String = "", prefillIP: String = "") {
        self.original = original
        _mac = State(initialValue: original?.mac ?? prefillMAC)
        _ip = State(initialValue: original?.ip ?? prefillIP)
        _enabled = State(initialValue: original?.enabled ?? true)
    }

    var macValid: Bool { mac.range(of: #"^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$"#, options: .regularExpression) != nil }
    var ipValid: Bool { ip.split(separator: ".").compactMap { UInt8($0) }.count == 4 }
    var conflict: String? {
        if let r = model.reservations.first(where: { $0.ip == ip && $0.index != original?.index }) {
            return "\(ip) is already reserved for \(model.name(for: r.mac) ?? r.mac)"
        }
        if let h = model.hosts.first(where: { $0.ip == ip && $0.active && $0.mac != mac.lowercased() }) {
            return "\(ip) is currently in use by \(model.customNames[h.mac] ?? h.displayName)"
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Toggle("Enabled", isOn: $enabled)
                LabeledContent("Device") {
                    HStack {
                        TextField("aa:bb:cc:dd:ee:ff", text: $mac).mono()
                        Menu {
                            ForEach(model.hosts.sorted { $0.displayName < $1.displayName }) { h in
                                Button("\(model.customNames[h.mac] ?? h.displayName) — \(h.ip)") { mac = h.mac; if ip.isEmpty || original == nil { ip = h.ip } }
                            }
                        } label: { Image(systemName: "laptopcomputer") }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }
                if let n = model.name(for: mac), macValid { LabeledContent("Name", value: n) }
                TextField("IP address", text: $ip).mono()
                if let c = conflict { Text(c).font(.caption).foregroundStyle(.orange) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add" : "Save") {
                    saving = true
                    Task {
                        let ok = await model.write("Reservation") {
                            try await model.client.saveReservation(index: original?.index ?? 0, mac: mac, ip: ip, enabled: enabled,
                                                                    brWan: original?.brWan ?? "Default")
                        }
                        saving = false
                        if ok { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!macValid || !ipValid || saving)
            }
            .padding()
        }
        .frame(width: 420)
    }
}
