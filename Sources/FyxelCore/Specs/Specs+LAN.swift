import Foundation

/// Every settings page's object descriptions. Grouped by page; see the per-area files.
public enum Specs {}

extension Specs {
    static let ipOrEmpty = FieldSpec.Kind.ipv4

    /// Defaults the GUI merges under the `lan` GET before every PUT (it sends the full LANSetup object).
    static let lanDefaults: JSONValue = [
        "Name": "Default", "IPAddress": "", "SubnetMask": "", "DHCPType": "DHCPServer", "EnableDHCP": false,
        "DHCP_MinAddress": "", "DHCP_MaxAddress": "", "DHCP_AutoReserveLanIp": false, "DHCP_LeaseTime": 0,
        "DHCP_RelayAddr": "", "DNS_Type": "DNSProxy", "DNS_Servers1": "", "DNS_Servers2": "",
        "IGMPSnoopingMode": "Disabled", "IPv6_LanEnable": false, "IPv6_LinkLocalAddressType": "EUI64",
        "IPv6_LinkLocalAddress": "", "IPv6_IdentifierType": "EUI64", "IPv6_Identifier": "",
        "ip6LANPrefixDelegated": false, "IPv6_PrefixType": "DelegateFromWan", "IPv6_PrefixWan": "Default",
        "IPv6_Prefix": "", "MLDSnoopingMode": "Disabled", "IPv6_DNSAssign": "RA_DHCP", "IPv6_LanAddrAssign": "Stateless",
        "Ipv6_MinAddress": "", "Ipv6_MaxAddress": "", "Ipv6_DNSSuffix": "", "Ipv6_DNSServer1": "ISP",
        "Ipv6_DNSServer2": "ISP", "Ipv6_DNSServer3": "None", "DNSQueryScenario": "IPv4IPv6",
        "IPv6_SubprefixEnable": false, "IPv6_Subprefix": "",
    ]

    static func lanChanged(_ o: JSONValue, _ e: JSONValue) -> Bool {
        o["IPAddress"] != e["IPAddress"] || o["SubnetMask"] != e["SubnetMask"]
    }

    /// Full LANSetup body, like the GUI: defaults ← GET ← edits, with the DNS clean-ups it applies.
    static let lanTransform: ObjectSpec.Transform = { o, e in
        var b = lanDefaults.merging(o).merging(e)
        b["subnet"] = .null
        if b["DNS_Type"] == "DNSProxy" { b["DNS_Servers1"] = ""; b["DNS_Servers2"] = "" }
        if b["DNS_Type"] == "Static", b["DNS_Servers2"].str.isEmpty { b["DNS_Servers2"] = .null }
        if b["IPv6_IdentifierType"] == "EUI-64" { b["IPv6_IdentifierType"] = "EUI64" }
        b["logout"] = lanChanged(o, e) ? 1 : 0
        return b.droppingNulls()
    }

    static let lanQuery: ObjectSpec.WriteQuery = { o, e in
        ["Logout": lanChanged(o, e) ? "1" : "0", "timedelay": "1"]
    }

    static let ipv6DNSChoices: [Choice] = [.init("ISP", "From ISP"), .init("Proxy", "DNS proxy"), .init("None", "None")]

    public static let lan: [ObjectSpec] = [
        ObjectSpec(
            oid: "lan", title: "LAN & DHCP Server",
            summary: "Changing the router address or mask ends this session; log in again at the new address.",
            fields: [
                .init("IPAddress", "Router IP", .ipv4, required: true),
                .init("SubnetMask", "Subnet mask", .ipv4, required: true),
                .init("EnableDHCP", "DHCP", .bool),
                .init("DHCPType", "Mode", .choice([.init("DHCPServer", "Server"), .init("DHCPRelay", "Relay")]), when: ("EnableDHCP", [true])),
                .init("DHCP_RelayAddr", "Relay to", .ipv4, when: ("DHCPType", ["DHCPRelay"]), required: true),
                .init("DHCP_MinAddress", "Pool start", .ipv4, when: ("DHCPType", ["DHCPServer"]), required: true),
                .init("DHCP_MaxAddress", "Pool end", .ipv4, when: ("DHCPType", ["DHCPServer"]), required: true),
                .init("DHCP_LeaseTime", "Lease time", .seconds, help: "60 s – 1 year", when: ("DHCPType", ["DHCPServer"])),
                .init("DHCP_AutoReserveLanIp", "Auto-reserve IPs", .bool, help: "Keep giving each device the address it got first."),
                .init("DNS_Type", "DNS for clients", .choice([.init("DNSProxy", "Router (DNS proxy)"), .init("Static", "Static"), .init("FromISP", "From ISP")])),
                .init("DNS_Servers1", "DNS server 1", .ipv4, when: ("DNS_Type", ["Static"]), required: true),
                .init("DNS_Servers2", "DNS server 2", .ipv4, when: ("DNS_Type", ["Static"])),
                .init("IGMPSnoopingMode", "IGMP snooping", .choice([.init("Disabled", "Off"), .init("Blocking", "Blocking"), .init("Standard", "Standard")])),
            ],
            confirm: "Clients may need to renew their DHCP lease. If you changed the router's address, this session ends.",
            loadTransform: { $0.prefix(1).map { lanDefaults.merging($0) } },
            writeQuery: lanQuery, transform: lanTransform),

        ObjectSpec(
            oid: "lan", title: "IPv6 LAN",
            fields: [
                .init("IPv6_LanEnable", "IPv6 on LAN", .bool),
                .init("IPv6_PrefixType", "Prefix", .choice([.init("DelegateFromWan", "Delegated from WAN"), .init("Static", "Static")]), when: ("IPv6_LanEnable", [true])),
                .init("IPv6_Prefix", "Static prefix", .text(placeholder: "2001:db8:1:2::/64"), when: ("IPv6_PrefixType", ["Static"]), required: true),
                .init("IPv6_LanAddrAssign", "Address assignment", .choice([.init("Stateless", "SLAAC (stateless)"), .init("Stateful", "DHCPv6 (stateful)")]), when: ("IPv6_LanEnable", [true])),
                .init("Ipv6_MinAddress", "DHCPv6 start", .text(placeholder: "0:0:0:2"), when: ("IPv6_LanAddrAssign", ["Stateful"])),
                .init("Ipv6_MaxAddress", "DHCPv6 end", .text(placeholder: "0:0:0:ffff"), when: ("IPv6_LanAddrAssign", ["Stateful"])),
                .init("IPv6_DNSAssign", "DNS via", .choice([.init("RA_DHCP", "RA + DHCPv6"), .init("DHCP", "DHCPv6"), .init("RA", "RA only")]), when: ("IPv6_LanEnable", [true])),
                .init("Ipv6_DNSServer1", "DNS server 1", .text(placeholder: "ISP, Proxy, None or an address"), help: "ISP, Proxy, None, or an IPv6 address", when: ("IPv6_LanEnable", [true])),
                .init("Ipv6_DNSServer2", "DNS server 2", .text(placeholder: "ISP"), when: ("IPv6_LanEnable", [true])),
                .init("Ipv6_DNSServer3", "DNS server 3", .text(placeholder: "None"), when: ("IPv6_LanEnable", [true])),
                .init("MLDSnoopingMode", "MLD snooping", .choice([.init("Disabled", "Off"), .init("Standard", "Standard"), .init("Blocking", "Blocking")]), when: ("IPv6_LanEnable", [true])),
                .init("DNSQueryScenario", "DNS query order", .choice([
                    .init("IPv4IPv6", "IPv4 + IPv6"), .init("IPv6First", "IPv6 first"), .init("IPv4First", "IPv4 first"),
                    .init("IPv6Only", "IPv6 only"), .init("IPv4Only", "IPv4 only"),
                ])),
            ],
            loadTransform: { $0.prefix(1).map { lanDefaults.merging($0) } },
            writeQuery: lanQuery, transform: lanTransform),

        ObjectSpec(
            oid: "dns", title: "Local DNS Names", summary: "Hostnames the router answers for itself (up to 253).",
            shape: .list,
            fields: [
                .init("HostName", "Hostname", .text(placeholder: "nas.home"), required: true, column: true),
                .init("IPv4Address", "Address", .ipv4, required: true, column: true),
            ],
            sendOnlyKnownFields: true),

        ObjectSpec(
            oid: "lanadv", title: "UPnP",
            fields: [
                .init("UPnPEnable", "UPnP", .bool, help: "Lets devices open ports themselves (shown under Port Forwarding)."),
                .init("NATTEnable", "UPnP NAT-T", .bool, when: ("UPnPEnable", [true])),
            ],
            loadTransform: { Array($0.prefix(1)) },
            transform: { _, e in
                var b = e
                if !b["UPnPEnable"].bool { b["NATTEnable"] = false }
                return b
            }),

        ObjectSpec(
            oid: "ddns", title: "Dynamic DNS",
            fields: [
                .init("Enable", "Enabled", .bool),
                .init("ServiceProvider", "Provider", .choice([
                    .init("dyndns", "DynDNS"), .init("zoneedit", "ZoneEdit"), .init("noip", "No-IP"),
                    .init("freedns", "FreeDNS (afraid.org)"), .init("dynu", "Dynu"), .init("userdefined", "Custom URL"),
                ]), when: ("Enable", [true])),
                .init("HostName", "Hostname", .text(placeholder: "home.example.net"), when: ("Enable", [true]), required: true),
                .init("UserName", "Username", .text(), when: ("ServiceProvider", ["dyndns", "zoneedit", "noip", "freedns", "dynu"])),
                .init("Password", "Password", .password, when: ("ServiceProvider", ["dyndns", "zoneedit", "noip", "freedns", "dynu"])),
                .init("ConnectionType", "Protocol", .choice([.init("HTTP", "HTTP"), .init("HTTPS", "HTTPS")]), when: ("ServiceProvider", ["userdefined"])),
                .init("UpdateURL", "Update URL", .text(placeholder: "https://…"), when: ("ServiceProvider", ["userdefined"])),
                .init("UseIPv6", "Update IPv6", .bool, when: ("Enable", [true])),
                .init("DynamicIP", "Current IP", .readOnly, when: ("Enable", [true])),
                .init("UpdatedTime", "Last update", .readOnly, when: ("Enable", [true])),
            ],
            loadTransform: { rows in
                rows.prefix(1).map { r in
                    // Unconfigured: start from the GUI's defaults.
                    r["ServiceProvider"].str.isEmpty ? r.merging(["ServiceProvider": "dyndns", "ConnectionType": "HTTP"]) : r
                }
            },
            transform: { _, e in
                var b = e
                if b["ConnectionType"].str.isEmpty { b["ConnectionType"] = "HTTP" }
                if !b["UseIPv6"].bool { b["UpdateURLv6"] = "" }
                return b
            }),

        ObjectSpec(
            oid: "ipalias", title: "Additional Subnets", shape: .fixedList,
            fields: [
                .init("GroupName", "LAN group", .readOnly, column: true),
                .init("ipAlias_Enable", "IP alias", .bool, column: true),
                .init("ipAlias_IPAddress", "Alias IP", .ipv4, when: ("ipAlias_Enable", [true]), required: true, column: true),
                .init("ipAlias_SubnetMask", "Alias mask", .ipv4, when: ("ipAlias_Enable", [true]), required: true),
                .init("PubLan_Enable", "Public LAN", .bool, column: true),
                .init("PubLan_IP", "Public IP", .ipv4, when: ("PubLan_Enable", [true]), required: true),
                .init("PubLan_SubnetMask", "Public mask", .ipv4, when: ("PubLan_Enable", [true]), required: true),
                .init("PubLan_DHCP", "Public DHCP", .bool, when: ("PubLan_Enable", [true])),
                .init("PubLan_ARP", "Proxy ARP", .bool, when: ("PubLan_Enable", [true])),
            ],
            transform: { _, e in
                var b = e
                if !b["ipAlias_Enable"].bool { b["ipAlias_IPAddress"] = ""; b["ipAlias_SubnetMask"] = "" }
                if !b["PubLan_Enable"].bool { b["PubLan_IP"] = ""; b["PubLan_SubnetMask"] = ""; b["PubLan_DHCP"] = false; b["PubLan_ARP"] = false }
                return b
            }),
    ]
}
