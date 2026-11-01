import FyxelCore
import SwiftUI

struct WLANRow: Identifiable {
    var id: Int { index }
    var index: Int
    var rec: JSONValue
    var ssid: String { rec["SSID"].str }
    var band: String { rec["band"].str }
    var enabled: Bool { rec["wlEnable"].bool }
    var main: Bool { rec["MainSSID"].bool }
    var hidden: Bool { rec["wlHide"].bool }
    var security: String { rec["SecurityMode"].str }
    var isolated: Bool { rec["X_ZYXEL_BssIdIsolation"].bool || rec["IsolationEnable"].bool }
    var bssid: String { rec["BSSID"].str }
    var radioOn: Bool { rec["radioenable"].bool }
}

struct WiFiView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Int?
    @State private var editing: WLANRow?
    @State private var busy = false
    @State private var revealed: Set<Int> = []
    @State private var confirmOff: WLANRow?

    var rows: [WLANRow] {
        model.wlan.enumerated().map { i, r in WLANRow(index: r["Index"].int ?? i + 1, rec: r) }
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            if let one = rows.first?.rec["oneSsidEnable"].bool, one {
                Label("One-SSID mode is on: the main 2.4 and 5 GHz networks share a name and password, so edits to either apply to both.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            Table(rows, selection: $selection) {
                TableColumn("On") { r in
                    Toggle("", isOn: Binding(get: { r.enabled }, set: { v in toggle(r, v) }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden().disabled(busy)
                }.width(40)
                TableColumn("#") { r in Text("\(r.index)").monospacedDigit().foregroundStyle(.secondary) }.width(22)
                TableColumn("SSID") { r in
                    HStack(spacing: 4) {
                        Text(r.ssid).bold(r.main).lineLimit(1)
                        if r.hidden { Image(systemName: "eye.slash").foregroundStyle(.secondary).help("Hidden") }
                        if r.isolated { Text("guest").font(.caption2).padding(.horizontal, 4).background(.quaternary, in: Capsule()) }
                    }
                }.width(min: 150, ideal: 220)
                TableColumn("Band") { r in Text(r.band) }.width(55)
                TableColumn("Password") { r in
                    let pw = WiFiEdit(r.rec).password
                    HStack {
                        Text(revealed.contains(r.index) ? pw : String(repeating: "•", count: min(pw.count, 12))).mono().lineLimit(1)
                        Spacer()
                        Button { if revealed.contains(r.index) { revealed.remove(r.index) } else { revealed.insert(r.index) } } label: {
                            Image(systemName: revealed.contains(r.index) ? "eye.slash" : "eye")
                        }.buttonStyle(.borderless)
                        Button { copyToPasteboard(pw) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Copy password")
                    }
                }.width(min: 150, ideal: 200)
                TableColumn("Security") { r in Text(r.security.replacingOccurrences(of: "-Personal", with: "").replacingOccurrences(of: "-Transition", with: " (WPA2 compat)")).foregroundStyle(.secondary).lineLimit(1).help(r.security) }.width(min: 90, ideal: 150)
                TableColumn("Channel") { r in
                    Text(r.main ? "\(r.rec["channel"].int ?? 0)\(r.rec["AutoChannelEnable"].bool ? " auto" : "") · \(r.rec["bandwidth"].str)" : "")
                        .mono().foregroundStyle(.secondary)
                }.width(min: 90, ideal: 120)
                TableColumn("Clients") { r in Text("\(clients(r))").monospacedDigit() }.width(45)
                TableColumn("BSSID") { r in Text(r.bssid == "00:00:00:00:00:00" ? "" : r.bssid).mono().foregroundStyle(.secondary) }.width(min: 120, ideal: 135)
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                if let id = ids.first, let r = rows.first(where: { $0.index == id }) {
                    Button("Edit…") { editing = r }
                    Button("Copy SSID") { copyToPasteboard(r.ssid) }
                    Button("Copy Password") { copyToPasteboard(WiFiEdit(r.rec).password) }
                }
            } primaryAction: { ids in
                if let id = ids.first { editing = rows.first { $0.index == id } }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { editing = rows.first { $0.index == selection } } label: { Label("Edit", systemImage: "pencil") }
                    .disabled(selection == nil)
            }
            if busy { ToolbarItem { ProgressView().controlSize(.small) } }
        }
        .sheet(item: $editing) { r in WiFiEditor(row: r, all: rows) }
        .confirmationDialog("Turn off \"\(confirmOff?.ssid ?? "")\" (\(confirmOff?.band ?? ""))?",
                            isPresented: Binding(get: { confirmOff != nil }, set: { if !$0 { confirmOff = nil } })) {
            Button("Turn Off", role: .destructive) { if let r = confirmOff { apply(r, false) } }
        } message: {
            Text("Devices on this network will be disconnected. If this Mac is on it, Fyxel will lose the router too.")
        }
    }

    func clients(_ r: WLANRow) -> Int {
        model.hosts.filter { $0.active && $0.raw["Layer1Interface"].str.hasSuffix("WiFi.SSID.\(r.index)") }.count
    }

    func toggle(_ r: WLANRow, _ on: Bool) {
        if on { apply(r, true) } else { confirmOff = r }
    }

    func apply(_ r: WLANRow, _ on: Bool) {
        busy = true
        Task {
            await model.write("Wi-Fi") { try await model.client.setWiFiEnabled([(r.index, on)]) }
            busy = false
        }
    }
}

struct WiFiEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var row: WLANRow
    var all: [WLANRow]
    @State private var edit: WiFiEdit
    @State private var showPassword = false
    @State private var saving = false
    @State private var confirm = false

    init(row: WLANRow, all: [WLANRow]) {
        self.row = row
        self.all = all
        _edit = State(initialValue: WiFiEdit(row.rec))
    }

    /// In one-SSID mode the main SSIDs on both bands are kept in sync.
    var linked: WLANRow? {
        guard row.main, row.rec["oneSsidEnable"].bool else { return nil }
        return all.first { $0.main && $0.index != row.index }
    }

    var channels: [Int] { row.rec["PossibleChannels"].str.split(separator: ",").compactMap { Int($0) } }
    var bandwidths: [String] { row.band.hasPrefix("2.4") ? ["20", "40"] : ["20", "40", "80", "160"] }
    var pskValid: Bool {
        !WiFiSecurity.needsPassword(edit.security)
            || ((8...63).contains(edit.password.count) && edit.password.allSatisfy { $0.isASCII && !$0.isWhitespace })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                SwiftUI.Section {
                    Toggle("Enabled", isOn: $edit.enabled)
                    TextField("SSID", text: $edit.ssid).mono()
                    HStack {
                        if !WiFiSecurity.needsPassword(edit.security) { EmptyView() }
                    else if showPassword { TextField("Password", text: $edit.password).mono() }
                        else { SecureField("Password", text: $edit.password) }
                        Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }.buttonStyle(.borderless)
                    }
                    if !pskValid { Text("Password must be 8–63 printable characters without spaces").font(.caption).foregroundStyle(.red) }
                    Toggle("Hide SSID", isOn: $edit.hidden)
                    Picker("Security", selection: $edit.security) {
                        ForEach(WiFiSecurity.supported(row.rec), id: \.self) { Text(WiFiSecurity.labels[$0] ?? $0).tag($0) }
                    }
                    if edit.security == "None" {
                        Text("Anyone nearby can join and see unencrypted traffic.").font(.caption).foregroundStyle(.orange)
                    }
                } header: {
                    Text("\(row.ssid) · \(row.band) · #\(row.index)")
                }
                if row.main {
                    SwiftUI.Section("Radio (\(row.band))") {
                        Picker("Channel", selection: $edit.channel) {
                            Text("Auto").tag(0)
                            ForEach(channels, id: \.self) { Text("\($0)").tag($0) }
                        }
                        Picker("Bandwidth", selection: $edit.bandwidth) {
                            ForEach(bandwidths, id: \.self) { Text("\($0) MHz").tag($0) }
                        }
                    }
                }
                if let l = linked {
                    Text("Name, password and visibility will also be applied to \(l.band) (#\(l.index)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Raw Record") { copyToPasteboard(row.rec.prettyString) }.help("Copy this SSID's JSON")
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { confirm = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || edit == WiFiEdit(row.rec) || !pskValid || edit.ssid.isEmpty)
            }
            .padding()
        }
        .frame(width: 460)
        .confirmationDialog("Apply Wi-Fi changes?", isPresented: $confirm) {
            Button("Apply") { save() }
        } message: {
            Text("The radio restarts, so devices on this network will briefly disconnect. If you're on this Wi-Fi yourself, you may need to reconnect.")
        }
    }

    func save() {
        saving = true
        var edits: [(record: JSONValue, edit: WiFiEdit)] = [(row.rec, edit)]
        if let l = linked {
            var e2 = WiFiEdit(l.rec)
            e2.ssid = edit.ssid; e2.password = edit.password; e2.hidden = edit.hidden; e2.enabled = edit.enabled
            e2.security = edit.security
            edits.append((l.rec, e2))
        }
        Task {
            let ok = await model.write("Wi-Fi") { try await model.client.saveWiFi(edits) }
            saving = false
            if ok { dismiss() }
        }
    }
}
