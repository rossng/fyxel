import FyxelCore
import SwiftUI

struct PortForwardingView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Int?
    @State private var editing: PortForwardRule?
    @State private var deleting: PortForwardRule?

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 0) {
                header("Port Forwards", "\(model.natRules.count) rules")
                Table(model.natRules, selection: $selection) {
                    TableColumn("On") { r in StatusDot(on: r.enabled) }.width(24)
                    TableColumn("Description") { r in Text(r.description).lineLimit(1) }.width(min: 120, ideal: 180)
                    TableColumn("Proto") { r in Text(r.protoLabel).mono() }.width(65)
                    TableColumn("External") { r in Text(verbatim: range(r.externalStart, r.externalEnd)).mono() }.width(min: 80, ideal: 100)
                    TableColumn("→") { _ in Image(systemName: "arrow.right").foregroundStyle(.secondary) }.width(16)
                    TableColumn("Internal") { r in Text(verbatim: "\(r.internalClient):\(range(r.internalStart, r.internalEnd))").mono() }.width(min: 150, ideal: 190)
                    TableColumn("Device") { r in Text(deviceName(r.internalClient)).foregroundStyle(.secondary).lineLimit(1) }.width(min: 100, ideal: 150)
                    TableColumn("Source") { r in Text(r.remoteHost.isEmpty ? "any" : r.remoteHost).mono().foregroundStyle(.secondary) }.width(min: 70, ideal: 110)
                }
                .contextMenu(forSelectionType: Int.self) { ids in
                    if let id = ids.first, let r = model.natRules.first(where: { $0.index == id }) {
                        Button("Edit…") { editing = r }
                        Button(r.enabled ? "Disable" : "Enable") { toggle(r) }
                        Button("Duplicate…") { var c = r; c.raw = .null; c.index = 0; c.description += " copy"; editing = c }
                        Divider()
                        Button("Delete…", role: .destructive) { deleting = r }
                    }
                } primaryAction: { ids in
                    if let id = ids.first { editing = model.natRules.first { $0.index == id } }
                }
                .overlay { if model.natRules.isEmpty { Text("No port forwards. ⌘N to add one.").foregroundStyle(.secondary) } }
            }
            .frame(minHeight: 180)

            VStack(alignment: .leading, spacing: 0) {
                header("UPnP / NAT-PMP mappings", "created by devices; read-only")
                Table(model.upnp) {
                    TableColumn("Description") { m in Text(m.description).lineLimit(1) }.width(min: 120, ideal: 180)
                    TableColumn("Proto") { m in Text(m.proto).mono() }.width(50)
                    TableColumn("External") { m in Text(verbatim: "\(m.externalPort)").mono() }.width(70)
                    TableColumn("Internal") { m in Text(verbatim: "\(m.destination):\(m.internalPort)").mono() }.width(min: 150, ideal: 180)
                    TableColumn("Device") { m in Text(deviceName(m.destination)).foregroundStyle(.secondary) }.width(min: 100, ideal: 160)
                }
            }
            .frame(minHeight: 140)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                let dmz = model.natConf["DMZHost"].str
                Text("DMZ: \(dmz.isEmpty || dmz == "0.0.0.0" ? "off" : dmz)")
                Text("·")
                Text("ALGs: " + ["SIP_ALG", "RTSP_ALG", "PPTP_ALG", "IPSEC_ALG"].filter { model.natConf[$0].bool }.map { $0.replacingOccurrences(of: "_ALG", with: "") }.joined(separator: ", "))
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
        }
        .toolbar {
            ToolbarItem {
                Button { editing = .new() } label: { Label("Add Rule", systemImage: "plus") }.keyboardShortcut("n")
            }
            ToolbarItem {
                Button { deleting = model.natRules.first { $0.index == selection } } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selection == nil)
                    .keyboardShortcut(.delete)
            }
        }
        .onChange(of: model.request, initial: true) { _, r in
            switch r?.intent {
            case .addPortForward?: model.request = nil; editing = .new()
            case .editPortForward(let i)?:
                model.request = nil
                selection = i
                editing = model.natRules.first { $0.index == i }
            default: break
            }
        }
        .sheet(item: $editing) { r in PortForwardEditor(rule: r) }
        .confirmationDialog("Delete \"\(deleting?.description ?? "")\"?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let d = deleting { Task { await model.write("Delete rule") { try await model.client.deletePortForward(index: d.index) } } }
            }
        }
    }

    func header(_ t: String, _ sub: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(t).font(.headline)
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    func range(_ a: Int, _ b: Int) -> String { b > a ? "\(a)–\(b)" : "\(a)" }

    func deviceName(_ ip: String) -> String {
        model.hosts.first { $0.ip == ip }.map { model.customNames[$0.mac] ?? $0.displayName } ?? ""
    }

    func toggle(_ r: PortForwardRule) {
        var c = r; c.enabled.toggle()
        Task { await model.write("Port forward") { try await model.client.savePortForward(c) } }
    }
}

struct PortForwardEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var rule: PortForwardRule
    @State private var saving = false

    var valid: Bool {
        (1...65535).contains(rule.externalStart) && (1...65535).contains(rule.internalStart)
            && rule.externalEnd >= rule.externalStart && rule.internalClient.split(separator: ".").count == 4
            && !rule.description.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Toggle("Enabled", isOn: $rule.enabled)
                TextField("Description", text: $rule.description)
                Picker("Protocol", selection: $rule.proto) {
                    Text("TCP").tag("TCP"); Text("UDP").tag("UDP"); Text("TCP/UDP").tag("ALL")
                }.pickerStyle(.segmented)
                LabeledContent("External ports") {
                    HStack {
                        TextField("start", value: $rule.externalStart, format: .number.grouping(.never)).mono()
                        Text("–")
                        TextField("end", value: $rule.externalEnd, format: .number.grouping(.never)).mono()
                    }
                }
                LabeledContent("Internal host") {
                    HStack {
                        TextField("192.168.1.x", text: $rule.internalClient).mono()
                        Menu {
                            ForEach(model.hosts.filter(\.active).sorted { $0.displayName < $1.displayName }) { h in
                                Button("\(model.customNames[h.mac] ?? h.displayName) — \(h.ip)") { rule.internalClient = h.ip }
                            }
                        } label: { Image(systemName: "laptopcomputer") }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }
                LabeledContent("Internal ports") {
                    HStack {
                        TextField("start", value: $rule.internalStart, format: .number.grouping(.never)).mono()
                        Text("–")
                        TextField("end", value: $rule.internalEnd, format: .number.grouping(.never)).mono()
                    }
                }
                TextField("Source IP (blank = any)", text: $rule.remoteHost).mono()
            }
            .formStyle(.grouped)
            .onChange(of: rule.externalStart) { o, n in
                if rule.externalEnd == o || rule.externalEnd < n { rule.externalEnd = n }
                if rule.internalStart == o || rule.internalStart == 0 { rule.internalStart = n }
            }
            .onChange(of: rule.internalStart) { o, n in
                if rule.internalEnd == o || rule.internalEnd < n { rule.internalEnd = n }
            }

            HStack {
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(rule.index == 0 ? "Add" : "Save") {
                    saving = true
                    Task {
                        let ok = await model.write("Port forward") { try await model.client.savePortForward(rule) }
                        saving = false
                        if ok { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid || saving)
            }
            .padding()
        }
        .frame(width: 440)
    }
}
