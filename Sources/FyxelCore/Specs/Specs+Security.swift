import Foundation

extension Specs {
    static let protoChoices: [Choice] = [.init("TCP", "TCP"), .init("UDP", "UDP"), .init("ALL", "TCP/UDP")]

    public static let firewall: [ObjectSpec] = [
        ObjectSpec(
            oid: "firewall", title: "Firewall",
            fields: [
                .init("IPv4_Enable", "IPv4 firewall", .bool),
                .init("IPv6_Enable", "IPv6 firewall", .bool),
                // The GUI's labels are shifted against the stored values.
                .init("Level_GUI", "Level", .choice([
                    .init("Off", "Low: allow everything"),
                    .init("Low", "Medium: block unsolicited inbound (recommended)"),
                    .init("High", "High: also restrict outbound to common services"),
                ])),
            ],
            transform: { _, e in
                ["IPv4_Enable": e["IPv4_Enable"], "IPv6_Enable": e["IPv6_Enable"], "Level_GUI": e["Level_GUI"],
                 "Firewall_Enable": .bool(e["IPv4_Enable"].bool || e["IPv6_Enable"].bool)]
            }),
        ObjectSpec(
            oid: "firewall", title: "DoS Protection",
            fields: [.init("enableDos", "Block DoS attacks", .bool)],
            transform: { _, e in ["enableDos": e["enableDos"]] }),
        macFilterGlobal, macFilterEntries, acl, firewallServices,
    ]

    // MARK: LAN MAC filter (macfilter): settings + positional list, written as one PUT array.

    static let macFilterGlobal = ObjectSpec(
        oid: "macfilter", title: "LAN MAC Filter",
        summary: "Applies to wired devices. In Allow mode only listed devices get on the network, so list this Mac first.",
        fields: [
            .init("Filter_Enable", "Enabled", .bool),
            .init("Restrict", "Mode", .choice([.init(false, "Allow only listed"), .init(true, "Block listed")]), when: ("Filter_Enable", [true])),
        ],
        confirm: "A wrong MAC filter can disconnect wired devices, including this Mac.",
        validator: { o in
            o["Filter_Enable"].bool && !o["Restrict"].bool && o["count"].int == 0 ? ["Allow mode needs at least one listed device"] : []
        },
        loadTransform: { rows in rows.prefix(1).map { r in r["MAC"].merging(["count": .int(Int64(r["whitelist"].array.count))]) } },
        transform: { _, e in [["Filter_Enable": e["Filter_Enable"], "Restrict": e["Restrict"]]] })

    static let macFilterEntries = ObjectSpec(
        oid: "macfilter", title: "MAC Filter List", shape: .list,
        fields: [
            .init("List_Enable", "Active", .bool, default: true, column: true),
            .init("HostName", "Name", .text(), required: true, column: true),
            .init("MACAddress", "MAC", .mac, required: true, column: true),
        ],
        addMethod: .PUT,
        loadTransform: { rows in
            guard let r = rows.first else { return [] }
            return r["whitelist"].array.enumerated().map { i, w in
                w.merging(["Index": .int(Int64(i + 1)), "_Filter_Enable": r["MAC"]["Filter_Enable"], "_Restrict": r["MAC"]["Restrict"]])
            }
        },
        prepare: { api, o, e in
            // The router wants the global settings as the first element of every write.
            let cur = try await api.dal("macfilter").first?["MAC"] ?? [:]
            let isNew = o.isNull
            let item: JSONValue = ["Action": isNew ? "ADD" : "EDIT", "Index": isNew ? 0 : e["Index"],
                                   "HostName": e["HostName"], "List_Enable": e["List_Enable"],
                                   "MACAddress": .string(e["MACAddress"].str.uppercased().replacingOccurrences(of: "-", with: ":"))]
            return [["Filter_Enable": cur["Filter_Enable"], "Restrict": cur["Restrict"]], item]
        })

    // MARK: ACL

    static let acl = ObjectSpec(
        oid: "firewall_acl", title: "Access Control Rules",
        summary: "Evaluated in order. A LAN-to-router drop rule can cut off this app.",
        shape: .list,
        fields: [
            .init("Order", "Order", .int(min: 1, max: 32), default: 1, column: true),
            .init("Name", "Name", .text(), required: true, column: true),
            .init("Direction", "Direction", .choice([
                .init("WAN_TO_LAN", "WAN → LAN"), .init("LAN_TO_WAN", "LAN → WAN"),
                .init("WAN_TO_ROUTER", "WAN → router"), .init("LAN_TO_ROUTER", "LAN → router"),
            ]), column: true),
            .init("Target", "Action", .choice([.init("Accept", "Accept"), .init("Drop", "Drop"), .init("Reject", "Reject")]), column: true),
            .init("IPVersion", "IP version", .choice([.init("IPv4", "IPv4"), .init("IPv6", "IPv6")])),
            .init("SourceIP", "Source IP", .text(placeholder: "blank = any"), column: true),
            .init("SourceMask", "Source prefix", .int(min: 0, max: 128), default: 32),
            .init("DestIP", "Destination IP", .text(placeholder: "blank = any"), column: true),
            .init("DestMask", "Destination prefix", .int(min: 0, max: 128), default: 32),
            .init("Protocol", "Protocol", .choice([
                .init("ALL", "Any"), .init("TCP", "TCP"), .init("UDP", "UDP"), .init("TCPUDP", "TCP/UDP"), .init("ICMP", "ICMP"), .init("ICMPv6", "ICMPv6"),
            ]), column: true),
            .init("DestPort", "Dest port", .int(min: -1, max: 65535, unit: "-1 = any"), default: -1, when: ("Protocol", ["TCP", "UDP", "TCPUDP"])),
            .init("DestPortRangeMax", "Dest port end", .int(min: -1, max: 65535), default: -1, when: ("Protocol", ["TCP", "UDP", "TCPUDP"])),
            .init("Log", "Log matches", .bool),
        ],
        addTemplate: ["Enable": 1, "MACAddress": "AnyMACAddress", "X_ZYXEL_ServiceIndex": 0, "X_ZYXEL_ScheduleRule": "",
                      "SourcePort": -1, "SourcePortRangeMax": -1, "ICMPType": -1, "ICMPTypeCode": -1, "LimitRateUnit": "minute"],
        confirm: "Firewall rules apply immediately and can block this Mac from the router.",
        loadTransform: { rows in
            rows.sorted { ($0["Order"].int ?? 0) < ($1["Order"].int ?? 0) }
                .map { $0["Protocol"] == "TCP/UDP" ? $0.merging(["Protocol": "TCPUDP"]) : $0 }
        })

    static let firewallServices = ObjectSpec(
        oid: "firewall_proto", title: "Firewall Services", summary: "Named port definitions used by access rules.",
        shape: .list,
        fields: [
            .init("Name", "Name", .text(), required: true, column: true),
            .init("Description", "Description", .text(), column: true),
            .init("Protocol", "Protocol", .choice([.init("TCP", "TCP"), .init("UDP", "UDP"), .init("ICMP", "ICMP"), .init("ICMPv6", "ICMPv6")]), column: true),
            .init("DestPort", "Port", .int(min: -1, max: 65535, unit: "-1 = any"), default: -1, when: ("Protocol", ["TCP", "UDP"]), column: true),
            .init("DestPortEnd", "Port end", .int(min: -1, max: 65535), default: -1, when: ("Protocol", ["TCP", "UDP"])),
        ],
        addTemplate: ["SourcePort": -1, "SourcePortEnd": -1, "ICMPType": -1, "ICMPTypeCode": -1],
        loadTransform: { rows in
            rows.map { r in
                let p = ["6": "TCP", "17": "UDP", "1": "ICMP", "58": "ICMPv6"][r["Protocol"].str] ?? r["Protocol"].str
                return r.merging(["Protocol": .string(p)])
            }
        })

    // MARK: Parental control (gen2 encoding)

    public static let parental: [ObjectSpec] = [
        ObjectSpec(
            oid: "paren_ctl", title: "Parental Control",
            fields: [.init("PrentalCtlEnable", "Enabled", .bool, help: "Master switch for all profiles below.")],
            loadTransform: { Array($0.prefix(1)) },
            transform: { _, e in ["PrentalCtlEnable": .bool(e["PrentalCtlEnable"].bool)] }),
        ObjectSpec(
            oid: "paren_ctl", title: "Profiles",
            summary: "Each profile blocks internet access for its devices during the listed times.",
            shape: .list,
            fields: [
                .init("pcpEnable", "Active", .bool, default: true, column: true),
                .init("pcpName", "Name", .text(), required: true, column: true),
                .init("MACAddressList", "Devices (MACs)", .text(placeholder: "aa:bb:cc:dd:ee:ff, …"), required: true, column: true),
                .init("Days", "Days", .text(placeholder: "Mon,Tue,Wed,Thu,Fri"), help: "Comma-separated; separate rows with ':'", default: "Mon,Tue,Wed,Thu,Fri", column: true),
                .init("TimeRangeList", "Blocked times", .text(placeholder: "21:00-23:59"), help: "H:MM-H:MM, one per row", default: "21:00-23:59", required: true, column: true),
            ],
            addTemplate: ["ServicePolicy": "Block", "UrlPolicy": "Block", "WebRedirect": 0, "URLFilter": "", "NetworkServiceList": ""],
            loadTransform: { Array($0.dropFirst()) },
            transform: { _, e in
                var b = e
                let rows = e["TimeRangeList"].str.split(separator: ",").count
                b["TimeType"] = .string(Array(repeating: "Normal", count: max(rows, 1)).joined(separator: ","))
                b["TimeEnable"] = .string(Array(repeating: "1", count: max(rows, 1)).joined(separator: ","))
                b["MACAddressList"] = .string(e["MACAddressList"].str.split(whereSeparator: { $0 == "," || $0 == " " }).joined(separator: ","))
                b["pcpEnable"] = .bool(e["pcpEnable"].bool)
                return b.picking(["Index", "pcpEnable", "pcpName", "MACAddressList", "Days", "TimeRangeList", "TimeType", "TimeEnable",
                                  "ServicePolicy", "UrlPolicy", "WebRedirect", "URLFilter", "NetworkServiceList"])
            }),
        urlList("URL_BlackList", "Blocked Sites", key: "BlackList"),
        urlList("URL_WhiteList", "Always-Allowed Sites", key: "WhiteList"),
    ]

    static func urlList(_ oid: String, _ title: String, key: String) -> ObjectSpec {
        ObjectSpec(
            oid: oid, title: title, shape: .list,
            fields: [.init(key, "Site", .text(placeholder: "example.com"), required: true, column: true)],
            loadTransform: { rows in rows.enumerated().map { i, r in r.merging(["Index": .int(Int64(i + 1))]) } },
            transform: { _, e in
                var u = e[key].str.lowercased()
                for p in ["https://", "http://"] where u.hasPrefix(p) { u.removeFirst(p.count) }
                if let slash = u.firstIndex(of: "/") { u = String(u[..<slash]) }
                var o: JSONValue = ["Index": "1", "Name": "UserDefined"]
                o[key] = .string(u)
                return o
            })
    }
}

