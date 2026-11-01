import Foundation

/// Remote-management access flags ↔ the router's `Mode` strings (separate LAN/WLAN variant).
public enum MgmtMode {
    static let table: [(lan: Bool, wlan: Bool, wan: Bool, trust: Bool, mode: String)] = [
        (true, true, false, false, "LAN_ONLY"), (true, true, true, false, "LAN_WAN"), (true, true, false, true, "LAN_TstDm"),
        (false, true, true, false, "WL_WAN"), (false, true, false, true, "WL_Trust_Dm"), (false, true, false, false, "WL_ONLY"),
        (true, false, false, false, "LAN_withoutWL"), (true, false, true, false, "LAN_withoutWL_WAN"),
        (true, false, false, true, "LAN_withoutWL_TstDm"), (false, false, true, false, "WAN_ONLY"), (false, false, false, true, "Trust_Dm"),
    ]

    public static func mode(lan: Bool, wlan: Bool, wan: Bool, trust: Bool) -> String? {
        table.first { $0.lan == lan && $0.wlan == wlan && $0.wan == wan && $0.trust == trust }?.mode
    }

    public static func flags(_ mode: String) -> (lan: Bool, wlan: Bool, wan: Bool, trust: Bool) {
        let lan = mode.contains("LAN")
        let wlan = (mode.contains("WL") && !mode.contains("withoutWL")) || ["LAN_ONLY", "LAN_WAN", "LAN_TstDm"].contains(mode)
        return (lan, wlan, mode.contains("WAN"), mode.contains("Dm"))
    }

    public static func flagsJSON(_ mode: String) -> JSONValue {
        let f = flags(mode)
        return ["LANEnable": .bool(f.lan), "WLANEnable": .bool(f.wlan), "WANEnable": .bool(f.wan), "TrustDmEnable": .bool(f.trust)]
    }
}

extension Specs {
    public static let system: [ObjectSpec] = [userAccount, remoteManagement, trustDomains, time]

    static let userAccount = ObjectSpec(
        oid: "user_account", title: "Login Policy", shape: .fixedList,
        fields: [
            .init("Username", "Account", .readOnly, column: true),
            .init("group", "Group", .readOnly, column: true),
            .init("AccountIdleTime", "Idle logout", .seconds, help: "60–3600 s", column: true),
            .init("AccountRetryTime", "Failed attempts before lock", .int(min: 0, max: 5), column: true),
            .init("AccountLockTime", "Lock duration", .seconds, help: "0–5400 s", column: true),
        ],
        writeQuery: { _, _ in ["timedelay": "1"] },
        transform: { _, e in
            // No password change: send an empty Password (see Maintenance for changing it).
            e.merging(["Index": .string(e["Index"].str), "Password": "", "verifyNewpassword": "", "oldPw": ""])
        })

    static let remoteManagement = ObjectSpec(
        oid: "mgmt_srv", title: "Remote Management",
        summary: "Which networks may reach each router service. Ports can't be changed here, and HTTPS must stay reachable from the LAN.",
        shape: .fixedList,
        fields: [
            .init("Name", "Service", .readOnly, column: true),
            .init("Enable", "Enabled", .bool, column: true),
            .init("LANEnable", "LAN", .bool, column: true),
            .init("WLANEnable", "Wi-Fi", .bool, column: true),
            .init("WANEnable", "Internet", .bool, help: "Exposes the service to the internet.", column: true),
            .init("TrustDmEnable", "Trusted domains only", .bool, column: true),
            .init("Port", "Port", .readOnly, column: true),
        ],
        confirm: "Changing access to the web interface can lock this app out.",
        validator: { o in
            var p: [String] = []
            if ["HTTPS", "HTTP"].contains(o["Name"].str), !(o["LANEnable"].bool || o["WLANEnable"].bool) {
                p.append("\(o["Name"].str) must stay reachable from the LAN or Wi-Fi")
            }
            if MgmtMode.mode(lan: o["LANEnable"].bool, wlan: o["WLANEnable"].bool, wan: o["WANEnable"].bool, trust: o["TrustDmEnable"].bool) == nil {
                p.append("The router doesn't support this combination (Internet and trusted domains are exclusive)")
            }
            return p
        },
        loadTransform: { rows in
            rows.map { $0.merging(MgmtMode.flagsJSON($0["Mode"].str)) }
        },
        prepare: { api, _, e in
            // One PUT of the whole array, rebuilt from the router's current copy.
            let cur = try await api.dal("mgmt_srv")
            var out: [JSONValue] = cur.map { r in
                var o = r["Index"] == e["Index"] ? r.merging(e) : r.merging(MgmtMode.flagsJSON(r["Mode"].str))
                o["Mode"] = .string(MgmtMode.mode(lan: o["LANEnable"].bool, wlan: o["WLANEnable"].bool, wan: o["WANEnable"].bool,
                                                  trust: o["TrustDmEnable"].bool) ?? "")
                o["Enable"] = .bool(o["Enable"].bool)
                o["Protocol"] = "https"
                o["RestartDeamon"] = .bool(["HTTP", "HTTPS"].contains(o["Name"].str))
                return o
            }
            if !out.isEmpty {
                // Mirrors the GUI, including its positional httpport/httpsport.
                let port = cur.first { $0["Name"] == "HTTPS" }?["Port"] ?? 443
                out[out.count - 1] = out[out.count - 1].merging(["origport": port, "httpport": out[0]["Port"],
                                                                 "httpsport": out.count > 1 ? out[1]["Port"] : -1])
            }
            return .array(out)
        })

    static let trustDomains = ObjectSpec(
        oid: "trust_domain", title: "Trusted Domains", summary: "Addresses allowed when a service is set to trusted domains only.",
        shape: .list,
        fields: [
            .init("Enable", "Enabled", .bool, default: true, column: true),
            .init("IPAddressPrefix", "Address/prefix", .text(placeholder: "198.51.100.0/24"), required: true, column: true),
        ],
        sendOnlyKnownFields: true)

    static let ntpChoices = ["None", "pool.ntp.org", "time.cloudflare.com", "time.apple.com", "time.nist.gov", "clock.fmt.he.net"]

    static let time = ObjectSpec(
        oid: "time", title: "Time & NTP",
        fields: [
            .init("Date", "Date", .readOnly), .init("Time", "Time", .readOnly),
            .init("X_ZYXEL_TimeZone", "Time zone", .text(placeholder: "CET-1CEST,M3.5.0,M10.5.0/3")),
            .init("NTPServer1", "NTP server 1", .text(placeholder: "pool.ntp.org")),
            .init("NTPServer2", "NTP server 2", .text(placeholder: "None")),
            .init("NTPServer3", "NTP server 3", .text(placeholder: "None")),
            .init("DaylightSavings", "Daylight saving", .bool),
        ],
        transform: { _, e in var b = e; b["TimeZone"] = .null; return b.droppingNulls() })

    public static let logSettings = ObjectSpec(
        oid: "logset", title: "Log Settings",
        fields: [
            .init("Enable", "Logging", .bool),
            .init("LogMode", "Destination", .choice([.init("Local", "This router"), .init("Remote", "Syslog server"), .init("LocalRemote", "Both")])),
            .init("LogServer", "Syslog server", .text(placeholder: "192.168.1.10"), when: ("LogMode", ["Remote", "LocalRemote"]), required: true),
            .init("UDPPort", "UDP port", .int(min: 1, max: 65535), when: ("LogMode", ["Remote", "LocalRemote"])),
            .init("System", "System", .bool), .init("Firewall", "Firewall", .bool), .init("Attack", "Attacks", .bool),
            .init("Account", "Logins", .bool), .init("Wireless", "Wi-Fi", .bool), .init("DHCP Server", "DHCP server", .bool),
            .init("WAN-DHCP", "WAN DHCP", .bool), .init("UPNP", "UPnP", .bool), .init("MAC Filter", "MAC filter", .bool),
            .init("EasyMesh", "EasyMesh", .bool), .init("Voice", "Voice", .bool), .init("TR-069", "TR-069", .bool),
        ])

    // MARK: Phone, USB, cellular

    public static let services: [ObjectSpec] = [
        ObjectSpec(
            oid: "phone", title: "Phone Ports", shape: .fixedList,
            fields: [
                .init("PhoneID", "Port", .readOnly, column: true),
                .init("InterNum", "Internal number", .readOnly, column: true),
                .init("DialEnable", "Outgoing calls", .bool, column: true),
                .init("phoneBoundingList", "Incoming lines", .text(placeholder: "VoiceProfile.1.Line.1"), column: true),
            ],
            transform: { _, e in
                ["Index": e["Index"], "LineSelect": e["LineSelect"], "phoneBoundingList": e["phoneBoundingList"],
                 "DialEnable": e["DialEnable"], "DectLineSelect": ""]
            }),
        ObjectSpec(
            oid: "region", title: "Phone Region",
            fields: [
                .init("Region", "Region", .text(placeholder: "NL")),
                .init("FxsCIDMode", "Caller ID mode", .choice([
                    .init("Default", "Default"), .init("onhook_ring", "After first ring"), .init("onhook_RPAS", "RP-AS"),
                    .init("onhook_DTAS", "DT-AS"), .init("onhook_LRAS", "LR-AS"), .init("onhook_LRCARIR", "LR + CAR/IR"),
                ])),
                .init("FxsCIDSigProtocol", "Caller ID signalling", .choice([.init("Default", "Default"), .init("FSK", "FSK"), .init("DTMF", "DTMF")])),
            ],
            transform: { _, e in
                e.picking(["Region", "FxsCIDMode", "FxsCIDSigProtocol"]).merging(["Service_Mode": e["Service_Mode"].isNull ? "Europe_Type" : e["Service_Mode"]])
            }),
        ObjectSpec(
            oid: "sip_account", title: "SIP Accounts", summary: "Usually managed by the ISP.", shape: .fixedList,
            fields: [
                .init("Enable", "Enabled", .bool, column: true),
                .init("DirectoryNumber", "Number", .readOnly, column: true),
                .init("AuthUserName", "Username", .text(), column: true),
                .init("AuthPassword", "Password", .password),
            ]),
        ObjectSpec(
            oid: "media_server", title: "Media Server (DLNA)",
            fields: [
                .init("Enable", "Enabled", .bool),
                .init("MediaRelativePath", "Folder", .text(placeholder: "/mnt/"), when: ("Enable", [true])),
            ],
            transform: { _, e in e.picking(["Enable", "Interface", "MediaRelativePath"]) }),
        ObjectSpec(
            oid: "usb_filesharing", title: "USB File Shares", summary: "Shared folders on attached USB storage (SMB).",
            shape: .list,
            fields: [
                .init("HostName", "Volume", .text(placeholder: "usb1_sda1"), required: true, column: true),
                .init("FolderName", "Folder", .text(), required: true, column: true),
                .init("Description", "Description", .text(), required: true, column: true),
                .init("Public", "Public", .bool, default: true, column: true),
                .init("ValidUsers_GUI", "Users", .text(placeholder: "admin"), when: ("Public", [false])),
            ],
            addTemplate: ["Browseable": true],
            loadTransform: { rows in
                rows.first?["Samba"].array.map { s in
                    s.merging(["Description": s["Share Description"], "FolderName": .string(s["Share Path"].str.split(separator: "/").dropFirst(2).joined(separator: "/")),
                               "HostName": .string(s["Share Path"].str.split(separator: "/").dropFirst().first.map(String.init) ?? "")])
                } ?? []
            },
            transform: { _, e in
                var b = e.picking(["Index", "HostName", "FolderName", "Description", "Browseable", "Public", "ValidUsers_GUI"])
                b["ValidUsers_GUI"] = e["Public"].bool ? "" : .string(e["ValidUsers_GUI"].str.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) + " " }.joined())
                return b
            }),
        ObjectSpec(
            oid: "cellular", title: "Cellular Backup", summary: "Fail over to a USB LTE modem when the main WAN is down.",
            fields: [
                .init("Enable_3G", "Enabled", .bool),
                .init("APN", "APN", .text(), when: ("Enable_3G", [true])),
                .init("Username", "Username", .text(), when: ("Enable_3G", [true])),
                .init("Password", "Password", .password, when: ("Enable_3G", [true])),
                .init("ConnectionTrigger", "Connect", .choice([.init("AlwaysOn", "Always on"), .init("OnDemand", "On demand")]), when: ("Enable_3G", [true])),
                .init("Backup_Interval", "Fail over after", .seconds, when: ("Enable_3G", [true])),
                .init("Recovery_Interval", "Return after", .seconds, when: ("Enable_3G", [true])),
            ]),
    ]
}

