import Foundation

// Write operations, modelled on what the stock GUI sends (see README "API notes").

public struct PortForwardRule: Sendable, Identifiable, Hashable {
    public var id: Int { index }
    public var index: Int
    public var enabled: Bool
    public var description: String
    public var proto: String           // "TCP", "UDP", "ALL"
    public var externalStart: Int, externalEnd: Int
    public var internalStart: Int, internalEnd: Int
    public var internalClient: String
    public var remoteHost: String      // "" = any
    public var interface: String       // "" = default WAN
    public var raw: JSONValue

    public init(_ j: JSONValue) {
        index = j["Index"].int ?? 0
        enabled = j["Enable"].bool
        description = j["Description"].str
        proto = j["Protocol"].string ?? "TCP"
        externalStart = j["ExternalPortStart"].int ?? 0
        externalEnd = j["ExternalPortEnd"].int ?? externalStart
        internalStart = j["InternalPortStart"].int ?? 0
        internalEnd = j["InternalPortEnd"].int ?? internalStart
        internalClient = j["InternalClient"].str
        remoteHost = j["SetRemoteIP"].bool ? j["RemoteHost"].str : ""
        interface = j["Interface"].str
        raw = j
    }

    public static func new() -> PortForwardRule {
        PortForwardRule(["Index": 0, "Enable": true, "Protocol": "TCP"])
    }

    public var protoLabel: String { proto == "ALL" ? "TCP/UDP" : proto }

    /// Applies the editable fields onto the original record (or the GUI's defaults for a new rule).
    func payload() -> JSONValue {
        var o: JSONValue = raw.object == nil || index == 0 ? [
            "Index": 0, "referenceIndex": -1, "Enable": false, "Protocol": "TCP", "DefaultPort": "",
            "Description": "", "Interface": "", "ExternalPortStart": "", "ExternalPortEnd": "",
            "InternalPortStart": "", "InternalPortEnd": "", "InternalClient": "", "SetRemoteIP": false,
            "RemoteHost": "", "RemoteHostEndRange": "255.255.255.255", "WANIP": "", "X_ZYXEL_AutoDetectWanStatus": false,
        ] : raw
        o["Enable"] = .bool(enabled)
        o["Description"] = .string(description)
        o["Protocol"] = .string(proto)
        o["ExternalPortStart"] = .int(Int64(externalStart))
        o["ExternalPortEnd"] = .int(Int64(max(externalEnd, externalStart)))
        o["InternalPortStart"] = .int(Int64(internalStart))
        o["InternalPortEnd"] = .int(Int64(max(internalEnd, internalStart)))
        o["InternalClient"] = .string(internalClient)
        o["SetRemoteIP"] = .bool(!remoteHost.isEmpty)
        o["RemoteHost"] = .string(remoteHost)
        if o["Interface"].str == "defaultWAN" { o["Interface"] = "" }
        return o
    }
}

/// Editable Wi-Fi fields for one SSID (one `wlan` Index).
public struct WiFiEdit: Sendable, Equatable {
    public var enabled: Bool
    public var ssid: String
    public var password: String
    public var hidden: Bool
    public var channel: Int        // 0 = auto
    public var bandwidth: String   // "20", "40", "80", "160"
    public var security: String    // SecurityMode, e.g. "WPA3-Personal-Transition"

    public init(_ rec: JSONValue) {
        enabled = rec["wlEnable"].bool
        ssid = rec["SSID"].str
        password = rec["AutoGenPSK"].bool ? rec["AutoGenPSKValue"].str : rec["PskDisplay"].str
        hidden = rec["wlHide"].bool
        channel = rec["AutoChannelEnable"].bool ? 0 : (rec["channel"].int ?? 0)
        bandwidth = rec["bandwidth"].str.replacingOccurrences(of: "MHz", with: "")
        security = rec["SecurityMode"].string ?? "WPA3-Personal-Transition"
    }
}

extension RouterAPI {
    // MARK: Port forwarding

    public func portForwards() async throws -> [PortForwardRule] {
        try await dal("nat").map(PortForwardRule.init)
    }

    public func savePortForward(_ r: PortForwardRule) async throws {
        if r.index == 0 {
            try await dalWrite(.POST, oid: "nat", r.payload())
        } else {
            // Like the GUI: start from the router's current copy of this rule.
            let cur = try await dal("nat", query: ["DalGetOneObject": "y", "Index": String(r.index)]).first
            var base = r
            if let cur { base.raw = cur }
            try await dalWrite(.PUT, oid: "nat", base.payload())
        }
    }

    public func deletePortForward(index: Int) async throws {
        try await dalWrite(.DELETE, oid: "nat", ["Index": .int(Int64(index))])
    }

    // MARK: DHCP reservations

    public func saveReservation(index: Int, mac: String, ip: String, enabled: Bool, brWan: String = "Default") async throws {
        let o: JSONValue = ["Index": .int(Int64(index)), "BrWan": .string(brWan), "Enable": .bool(enabled),
                            "MACAddr": .string(mac.lowercased()), "IPAddr": .string(ip)]
        try await dalWrite(index == 0 ? .POST : .PUT, oid: "static_dhcp", o)
    }

    public func deleteReservation(index: Int) async throws {
        try await dalWrite(.DELETE, oid: "static_dhcp", ["Index": .int(Int64(index))])
    }

    // MARK: Devices

    /// Rename / set icon / block internet. Mirrors the connected-devices "edit" popup.
    public func updateHost(_ h: LanHost, name: String? = nil, blockInternet: Bool? = nil) async throws {
        let icon = h.raw["DeviceIcon"].string.flatMap { $0.isEmpty ? nil : $0.lowercased() } ?? (h.icon.isEmpty ? "iothers" : h.icon)
        let o: JSONValue = [
            "HostName": .string(name ?? (h.raw["curHostName"].str.isEmpty ? h.deviceName : h.raw["curHostName"].str)),
            "DeviceIcon": .string(icon),
            "MacAddress": .string(h.raw["PhysAddress"].str),
            "Internet_Blocking_Enable": .bool(blockInternet ?? h.blocked),
        ]
        try await dalWrite(.PUT, oid: "lanhosts", o)
    }

    public func wakeOnLAN(mac: String, ip: String) async throws {
        let r = try await request(.PUT, "/cgi-bin/Home_Networking?action=WOLCommand", query: [:],
                                  body: ["MAC": .string(mac.uppercased()), "IP": .string(ip)])
        let ret = r[0]["Ret"].string ?? r["Ret"].string ?? r["result"].str
        guard ret == "ZCFG_SUCCESS" else { throw RouterError.dal(result: ret.isEmpty ? "WOL failed" : ret, message: "") }
    }

    // MARK: Wi-Fi

    public func setWiFiEnabled(_ entries: [(index: Int, enabled: Bool)]) async throws {
        let objs = entries.map { JSONValue.object(["Index": .int(Int64($0.index)), "wlEnable": .bool($0.enabled)]) }
        try await dalWrite(.PUT, oid: "wlan", objs.count == 1 ? objs[0] : .array(objs))
        try await wlCheck()
    }

    /// Full per-SSID write, built the way the GUI's Wireless > General page builds it.
    /// `edits` maps wlan Index -> edits, and records are the current `wlan` GET objects.
    public func saveWiFi(_ edits: [(record: JSONValue, edit: WiFiEdit)]) async throws {
        let objs = edits.map { Self.wlanPayload(record: $0.record, edit: $0.edit) }
        try await dalWrite(.PUT, oid: "wlan", objs.count == 1 ? objs[0] : .array(objs))
        try await wlCheck()
    }

    /// The GUI polls this after Wi-Fi writes; it returns once the radios have been reconfigured.
    func wlCheck() async throws {
        _ = try? await get("/cgi-bin/Wireless?action=WlCheck")
    }

    static func wlanPayload(record r: JSONValue, edit e: WiFiEdit) -> JSONValue {
        let sec = WiFiSecurity.fields(for: e.security, currentPMF: r["wlpmf"], modeChanged: e.security != r["SecurityMode"].str)
        let isolated = r["X_ZYXEL_BssIdIsolation"].bool || r["IsolationEnable"].bool
        let is24 = r["band"].str.hasPrefix("2.4")
        var bw = e.bandwidth
        if is24, r["X_ZYXEL_OBSS_coex"].bool, bw == "40" { bw = "0" } // GUI's "20/40 MHz"
        let pskChanged = e.password != (r["AutoGenPSK"].bool ? r["AutoGenPSKValue"].str : r["PskDisplay"].str)
        let origChannel = r["AutoChannelEnable"].bool ? 0 : (r["channel"].int ?? 0)

        let o: JSONValue = [
            "Index": r["Index"],
            "wlEnable": .bool(e.enabled),
            "X_ZYXEL_Multicast_Fwd": r["X_ZYXEL_Multicast_Fwd"],
            "oneSsidEnable": r["oneSsidEnable"],
            "oneSsidEnable_ori": r["oneSsidEnable_ori"],
            "SSID": .string(e.ssid),
            "upRate": r["upRate"],
            "downRate": r["downRate"],
            "MaxAssociatedDevices": r["MaxAssociatedDevices"],
            "wlHide": .bool(e.hidden),
            "secMode": sec["secMode"] ?? 255,
            "wpaMode": sec["wpaMode"] ?? .null,
            "owe": sec["owe"] ?? .null,
            "wlpmf": sec["wlpmf"] ?? r["wlpmf"],
            "AutoGenPSK": .bool(pskChanged ? false : r["AutoGenPSK"].bool),
            "psk_value": .string(e.password),
            "encryp": sec["encryp"] ?? r["encryp"],
            "RekeyingInterval": r["RekeyingInterval"],
            "X_ZYXEL_Preauth": r["X_ZYXEL_Preauth"],
            "X_ZYXEL_ReauthInterval": r["X_ZYXEL_ReauthInterval"],
            "RadiusServerIPAddr": r["RadiusServerIPAddr"],
            "RadiusServerPort": r["RadiusServerPort"],
            "RadiusSecret": r["RadiusSecret"],
            "RadiusAccountingPort": r["RadiusAccountingPort"],
            "div_wifiAdvance": true,
            "channel": .int(Int64(e.channel)),
            "channel_changed": .int(e.channel == origChannel ? 0 : 1),
            "bandwidth": .string(bw),
            "extcha": r["extcha"],
            "subnetObjAction": "",
            "div_wifiSubnet": false,
            "IsolationEnable": .bool(isolated),
            "X_ZYXEL_BssIdIsolation": .bool(isolated),
            "wlEnableGuest": .bool(isolated),
            "wlGwMode": .string(isolated ? "0" : "1"),
        ]
        return o.droppingNulls()
    }
}
