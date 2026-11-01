import Foundation

extension Specs {
    public static let nat: [ObjectSpec] = [
        ObjectSpec(
            oid: "nat_conf", title: "DMZ",
            summary: "Forward all unsolicited inbound traffic to one device. Port forwards still take priority.",
            fields: [.init("DMZHost", "DMZ host", .ipv4, help: "Blank or 0.0.0.0 turns DMZ off.")],
            transform: { o, e in
                let h = e["DMZHost"].str
                let off = h.isEmpty || h == "0.0.0.0"
                return o.merging(["DmzHost": .string(off ? "0.0.0.0" : h), "DmzHost_Enable": .bool(!off)])
            }),
        ObjectSpec(
            oid: "nat_conf", title: "Application Gateways (ALG)",
            summary: "Protocol helpers that rewrite addresses inside SIP, RTSP, PPTP and IPsec traffic.",
            fields: [
                .init("NAT_ALG", "NAT ALG", .bool), .init("SIP_ALG", "SIP ALG", .bool), .init("RTSP_ALG", "RTSP ALG", .bool),
                .init("PPTP_ALG", "PPTP ALG", .bool), .init("IPSEC_ALG", "IPsec ALG", .bool),
            ],
            transform: { _, e in
                e.merging(["Nat": e["NAT_ALG"], "Sip": e["SIP_ALG"], "Rtsp": e["RTSP_ALG"], "Pptp": e["PPTP_ALG"], "Ipsec": e["IPSEC_ALG"]])
            }),
        ObjectSpec(
            oid: "nat_conf", title: "NAT Sessions",
            fields: [.init("MaxSessionPerHost", "Max sessions per device", .int(min: 0, max: 16000))]),

        ObjectSpec(
            oid: "nat_trigger", title: "Port Triggering",
            summary: "When a device sends to the trigger port, the open ports are forwarded back to it for a while.",
            shape: .list,
            fields: [
                .init("Enable", "Enabled", .bool, default: true, column: true),
                .init("Description", "Description", .text(), required: true, column: true),
                .init("TriggerProtocol", "Trigger proto", .choice(protoChoices), column: true),
                .init("TriggerPortStart", "Trigger port", .int(min: 1, max: 65535), required: true, column: true),
                .init("TriggerPortEnd", "Trigger port end", .int(min: 1, max: 65535)),
                .init("OpenProtocol", "Open proto", .choice(protoChoices), column: true),
                .init("OpenPortStart", "Open port", .int(min: 1, max: 65535), required: true, column: true),
                .init("OpenPortEnd", "Open port end", .int(min: 1, max: 65535)),
            ],
            deleteKey: "idx",
            addTemplate: ["Interface": "", "X_ZYXEL_AutoDetectWanStatus": false],
            validator: { o in
                (o["OpenPortStart"].int ?? 0) <= 7547 && 7547 <= max(o["OpenPortEnd"].int ?? 0, o["OpenPortStart"].int ?? 0)
                    ? ["Open ports can't include 7547 (the ISP's management port)"] : []
            },
            // Reads and writes use different names.
            loadTransform: { rows in
                rows.map { r in
                    r.merging(["TriggerPortStart": r["TriggerPort"], "TriggerPortEnd": r["TriggerPortEndRange"],
                               "OpenPortStart": r["OpenPort"], "OpenPortEnd": r["OpenPortEndRange"], "OpenProtocol": r["Protocol"]])
                }
            },
            transform: { _, e in
                var b = e.picking(["Enable", "Interface", "TriggerPortStart", "TriggerPortEnd", "TriggerProtocol", "OpenPortStart",
                                   "OpenPortEnd", "OpenProtocol", "Description", "Index", "idx", "X_ZYXEL_AutoDetectWanStatus"])
                if (b["TriggerPortEnd"].int ?? 0) < (b["TriggerPortStart"].int ?? 0) { b["TriggerPortEnd"] = b["TriggerPortStart"] }
                if (b["OpenPortEnd"].int ?? 0) < (b["OpenPortStart"].int ?? 0) { b["OpenPortEnd"] = b["OpenPortStart"] }
                if b["Interface"].isNull { b["Interface"] = "" }
                return b
            }),

        ObjectSpec(
            oid: "nat_addr_map", title: "Address Mapping", shape: .list,
            fields: [
                .init("Enable", "Enabled", .bool, default: true, column: true),
                .init("MappingRuleName", "Name", .text(), required: true, column: true),
                .init("Type", "Type", .choice([.init("One-to-One", "One-to-one"), .init("Many-to-One", "Many-to-one"), .init("Many-to-Many", "Many-to-many")]), column: true),
                .init("LocalStartIP", "Local start", .ipv4, required: true, column: true),
                .init("LocalEndIP", "Local end", .ipv4, when: ("Type", ["Many-to-One", "Many-to-Many"])),
                .init("GlobalStartIP", "Public start", .ipv4, required: true, column: true),
                .init("GlobalEndIP", "Public end", .ipv4, when: ("Type", ["Many-to-Many"])),
                .init("Description", "Description", .text()),
            ],
            addTemplate: ["Interface": "", "MappingSet": "", "X_ZYXEL_AutoDetectWanStatus": false],
            transform: { _, e in
                var b = e
                if b["Type"] == "One-to-One" { b["LocalEndIP"] = ""; b["GlobalEndIP"] = "" }
                if b["Type"] == "Many-to-One" { b["GlobalEndIP"] = "" }
                return b
            }),
    ]

    // MARK: Routing & QoS (refused below the "high" account level)

    public static let routing: [ObjectSpec] = [
        ObjectSpec(
            oid: "static_route", title: "Static Routes", shape: .list,
            fields: [
                .init("Enable", "Enabled", .bool, default: true, column: true),
                .init("Name", "Name", .text(), required: true, column: true),
                .init("ipver", "IP version", .choice([.init("IPv4", "IPv4"), .init("IPv6", "IPv6")])),
                .init("DestIPAddress", "Destination", .ipv4, when: ("ipver", ["IPv4"]), required: true, column: true),
                .init("DestSubnetMask", "Mask", .ipv4, when: ("ipver", ["IPv4"]), required: true, column: true),
                .init("GatewayIPAddress", "Gateway", .ipv4, when: ("ipver", ["IPv4"]), column: true),
                .init("DestIPPrefix", "Prefix", .text(placeholder: "2001:db8::/48"), when: ("ipver", ["IPv6"]), required: true),
                .init("NextHop", "Next hop", .text(), when: ("ipver", ["IPv6"])),
                .init("Interface", "Interface", .text(placeholder: "IP.Interface.N"), required: true, column: true),
            ],
            addTemplate: ["IPType": 0, "UseGateIpAddr": true, "DestIPPrefixLen": 1],
            confirm: "A wrong route can cut off the internet or the LAN."),
        ObjectSpec(
            oid: "policy_route", title: "Policy Routes", shape: .list,
            fields: [
                .init("Enable", "Enabled", .bool, default: true, column: true),
                .init("RouteName", "Name", .text(), required: true, column: true),
                .init("SourceIpAddress", "Source IP", .ipv4, column: true),
                .init("SourceSubnetMask", "Source mask", .ipv4),
                .init("SourceMacAddress", "Source MAC", .mac),
                .init("Protocol", "Protocol", .choice([.init("ALL", "Any"), .init("TCP", "TCP"), .init("UDP", "UDP")])),
                .init("SourcePort", "Source port", .int(min: 0, max: 65535), when: ("Protocol", ["TCP", "UDP"])),
                .init("SourceIfName", "Source interface", .text(placeholder: "LAN1 or br0")),
                .init("WANInterface", "Via WAN", .text(placeholder: "IP.Interface.N"), required: true, column: true),
            ],
            validator: { o in
                ["SourceIpAddress", "SourceMacAddress", "SourceIfName"].allSatisfy { o[$0].str.isEmpty } && (o["SourcePort"].int ?? 0) == 0
                    ? ["Set at least one of source IP, MAC, port or interface"] : []
            }),
        ObjectSpec(
            oid: "dns_route", title: "DNS Routes", summary: "Send lookups for a domain via a specific WAN.",
            shape: .list,
            fields: [
                .init("Enable", "Enabled", .bool, default: true, column: true),
                .init("DomainName", "Domain", .text(placeholder: "*.corp.example"), required: true, column: true),
                .init("SubnetMask", "Mask", .ipv4, column: true),
                .init("Interface", "Via WAN", .text(placeholder: "IP.Interface.N"), required: true, column: true),
            ]),
        ObjectSpec(
            oid: "qos", title: "QoS",
            fields: [
                .init("Enable", "Enabled", .bool),
                .init("UpRate", "Upstream bandwidth", .int(min: 0, unit: "kbit/s"), when: ("Enable", [true])),
                .init("AutoMapType", "Auto classification", .choice([
                    .init("None", "None"), .init("EthernetPriority", "Ethernet priority"), .init("IPPrecedence", "IP precedence"),
                    .init("PacketLength", "Packet length"),
                ]), when: ("Enable", [true])),
            ],
            loadTransform: { rows in rows.prefix(1).map { r in r.merging(["AutoMapType": .string(r["AutoMapType"].str.replacingOccurrences(of: " ", with: ""))]) } }),
        ObjectSpec(
            oid: "qos_queue", title: "QoS Queues", shape: .list,
            fields: [
                .init("Enable", "Enabled", .bool, default: true, column: true),
                .init("Name", "Name", .text(), required: true, column: true),
                .init("Priority", "Priority", .choice((1...8).map { Choice(.string("\($0)"), "\($0)\($0 == 1 ? " (highest)" : "")") }), column: true),
                .init("Weight", "Weight", .choice((1...8).map { Choice(.string("\($0)"), "\($0)") }), column: true),
                .init("RateLimit", "Rate limit", .int(min: -1, unit: "kbit/s, -1 = none"), default: -1, column: true),
            ],
            deleteKey: "idx",
            addTemplate: ["BufferManagement": "DT", "DropAlgorithm": "DT", "Interface": "WAN"],
            transform: { _, e in e.merging(["ShapingRate": e["RateLimit"]]) }),
        ObjectSpec(
            oid: "qos_shaper", title: "QoS Shapers", shape: .list,
            fields: [
                .init("Enable", "Enabled", .bool, default: true, column: true),
                .init("Interface", "Interface", .text(placeholder: "IP.Interface.N or Ethernet.Interface.N"), required: true, column: true),
                .init("ShapingRate", "Rate", .text(placeholder: "kbit/s"), required: true, column: true),
            ],
            deleteKey: "idx"),
    ]
}
