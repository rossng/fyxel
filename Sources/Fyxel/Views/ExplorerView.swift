import FyxelCore
import SwiftUI

/// Raw GET access to any endpoint, for poking at things the UI doesn't cover.
struct ExplorerView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("explorer.path") private var path = "/cgi-bin/DAL?oid=lanhosts"
    @State private var result: JSONValue?
    @State private var error: String?
    @State private var loading = false
    @State private var filter = ""
    @State private var elapsed: TimeInterval = 0

    static let known = [
        "status", "cardpage_status", "lanhosts", "Traffic_Status", "wlan", "wifi_easy_mesh", "wifi_mlo", "wps",
        "lan", "lanadv", "static_dhcp", "ipalias", "nat", "nat_conf", "nat_trigger", "nat_addr_map", "nat_pcp",
        "firewall", "firewall_acl", "macfilter", "ipfilter", "paren_ctl", "URL_BlackList", "URL_WhiteList",
        "static_route", "policy_route", "dns_route", "mgmt_srv", "user_account", "logset", "tr69", "qos",
        "qos_class", "qos_queue", "OperationMode", "usb_info", "intf_group", "speedCtl",
    ]
    static let other = [
        "/cgi-bin/getBasicInformation", "/cgi-bin/RoutingTable_handle", "/cgi-bin/WAN_LAN_LIST_Get",
        "/cgi-bin/LAN_PORT_LIST_Get", "/cgi-bin/OTHER_INFO", "/cgi-bin/loginAccountLevel",
        "/cgi-bin/Traffic_Status?mode=NATStatus_handle", "/cgi-bin/getWebGuiFlag",
    ]

    var body: some View {
        HSplitView {
            List {
                SwiftUI.Section("DAL objects") {
                    ForEach(Self.known, id: \.self) { o in
                        Button(o) { path = "/cgi-bin/DAL?oid=\(o)"; Task { await go() } }.buttonStyle(.plain).mono()
                    }
                }
                SwiftUI.Section("Other") {
                    ForEach(Self.other, id: \.self) { p in
                        Button(p.replacingOccurrences(of: "/cgi-bin/", with: "")) { path = p; Task { await go() } }.buttonStyle(.plain).mono()
                    }
                }
            }
            .frame(minWidth: 180, idealWidth: 210, maxWidth: 280)

            VStack(spacing: 0) {
                HStack {
                    Text("GET").font(.caption.bold()).foregroundStyle(.secondary)
                    TextField("/cgi-bin/DAL?oid=…", text: $path).textFieldStyle(.roundedBorder).mono().onSubmit { Task { await go() } }
                    Button("Send") { Task { await go() } }.keyboardShortcut(.return, modifiers: .command)
                    if let r = result { Button("Copy") { copyToPasteboard(r.prettyString) } }
                }
                .padding(10)
                HStack {
                    Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                    TextField("Filter lines", text: $filter).textFieldStyle(.plain)
                    Spacer()
                    if loading { ProgressView().controlSize(.small) }
                    if let r = result { Text("\(r.compactString.utf8.count) bytes · \(Int(elapsed * 1000)) ms").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 10).padding(.bottom, 6)
                Divider()
                ScrollView([.vertical, .horizontal]) {
                    Text(rendered)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            }
        }
    }

    var rendered: String {
        if let error { return error }
        guard let result else { return "Pick an endpoint or type a path. Read-only: this only sends GETs." }
        let s = result.prettyString
        guard !filter.isEmpty else { return s }
        return s.split(separator: "\n").filter { $0.localizedCaseInsensitiveContains(filter) }.joined(separator: "\n")
    }

    func go() async {
        loading = true; error = nil
        let start = Date()
        defer { loading = false; elapsed = Date().timeIntervalSince(start) }
        var p = path.trimmingCharacters(in: .whitespaces)
        if !p.hasPrefix("/") { p = "/cgi-bin/DAL?oid=" + p }
        do { result = try await model.client.get(p) } catch { self.error = error.localizedDescription; result = nil }
    }
}
