import Foundation

/// How the GUI turns a `SecurityMode` (as the wlan GET reports it) into write fields.
public enum WiFiSecurity {
    public static let labels: [String: String] = [
        "None": "Open (no security)", "WPA2-Personal": "WPA2", "WPA3-Personal-Transition": "WPA3 + WPA2",
        "WPA3-Personal": "WPA3", "OWE": "Enhanced Open (OWE)", "WPA-WPA2-Personal": "WPA + WPA2",
    ]

    /// Modes this SSID offers, from `ModesSupported` ("None,WPA2-Personal,…").
    public static func supported(_ rec: JSONValue) -> [String] {
        let m = rec["ModesSupported"].str.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        return m.isEmpty ? ["WPA2-Personal", "WPA3-Personal-Transition", "WPA3-Personal"] : m
    }

    /// `secMode`, `wpaMode`/`owe`, `encryp` and `wlpmf` for a mode. `currentPMF` is kept when
    /// the mode is unchanged and allows a choice (WPA2).
    public static func fields(for mode: String, currentPMF: JSONValue, modeChanged: Bool) -> [String: JSONValue] {
        switch mode {
        case "None": return ["secMode": 43, "wpaMode": "wpa2psk", "encryp": "aes", "wlpmf": "disabled"]
        case "WPA2-Personal": return ["secMode": 255, "wpaMode": "wpa2psk", "encryp": "aes", "wlpmf": modeChanged ? "capable" : currentPMF]
        case "WPA3-Personal": return ["secMode": 255, "wpaMode": "wpa3sae", "encryp": "aes", "wlpmf": "required"]
        case "OWE": return ["secMode": 255, "owe": true, "encryp": "aes", "wlpmf": "required"]
        case "WPA-WPA2-Personal": return ["secMode": 255, "wpaMode": "wpawpa2psk", "encryp": "tkipaes", "wlpmf": "disabled"]
        default: return ["secMode": 255, "wpaMode": "wpa2pskwpa3sae", "encryp": "aes", "wlpmf": "capable"]
        }
    }

    public static func needsPassword(_ mode: String) -> Bool { mode != "None" && mode != "OWE" }
}

extension Specs {
    static let wlCheck = "/cgi-bin/Wireless?action=WlCheck"
    static let radioWarning = "The radio restarts: Wi-Fi devices drop off for a few seconds."

    public static let wifi: [ObjectSpec] = [guestNetworks, wps, macFilter, easyMesh, radioAdvanced, schedules]

    /// wlan Index 2 (2.4 GHz) and 6 (5 GHz); 3/4/7/8 are hidden by the firmware, 9/10 are mesh backhaul.
    static let guestNetworks = ObjectSpec(
        oid: "wlan", title: "Guest Networks",
        summary: "External guests reach only the internet. Home guests can also reach devices on your LAN.",
        shape: .fixedList,
        fields: [
            .init("band", "Band", .readOnly, column: true),
            .init("wlEnable", "Enabled", .bool, column: true),
            .init("SSID", "Name", .text(), required: true, column: true),
            .init("SecurityMode", "Security", .choice(WiFiSecurity.labels.sorted { $0.key < $1.key }.map { Choice(.string($0.key), $0.value) }), column: true),
            .init("psk_value", "Password", .password, help: "8–63 printable characters",
                  when: ("SecurityMode", ["WPA2-Personal", "WPA3-Personal-Transition", "WPA3-Personal", "WPA-WPA2-Personal"]), required: true),
            .init("wlHide", "Hidden", .bool),
            .init("wlEnableGuest", "Guest isolation", .bool, column: true),
            .init("wlGwMode", "Access", .choice([.init(0, "External guest (internet only)"), .init(1, "Home guest (LAN too)")]), when: ("wlEnableGuest", [true])),
            .init("upRate", "Upload limit", .int(min: 0, max: 1_000_000, unit: "kbit/s, 0 = none")),
            .init("downRate", "Download limit", .int(min: 0, max: 1_000_000, unit: "kbit/s, 0 = none")),
            .init("wlSubnetState", "Own subnet", .bool, help: "Give this SSID its own IP range."),
            .init("LANIP", "Gateway IP", .ipv4, when: ("wlSubnetState", [true]), required: true),
            .init("SubnetMask", "Mask", .ipv4, when: ("wlSubnetState", [true]), required: true),
            .init("MinAddress", "Pool start", .ipv4, when: ("wlSubnetState", [true]), required: true),
            .init("MaxAddress", "Pool end", .ipv4, when: ("wlSubnetState", [true]), required: true),
        ],
        confirm: radioWarning, followUp: wlCheck,
        loadTransform: { rows in
            rows.filter { [2, 6].contains($0["Index"].int ?? 0) }.map { r in
                var o = r
                let iso = r["IsolationEnable"].bool, bss = r["X_ZYXEL_BssIdIsolation"].bool
                o["wlEnableGuest"] = .bool(iso || bss)
                o["wlGwMode"] = .int(iso && bss ? 0 : 1)
                o["psk_value"] = .string(r["AutoGenPSK"].bool ? r["AutoGenPSKValue"].str : r["PskDisplay"].str)
                if o["wlSubnetState"].isNull { o["wlSubnetState"] = .bool(!r["MinAddress"].str.isEmpty) }
                return o
            }
        },
        transform: { o, e in
            let mode = e["SecurityMode"].str
            var b: JSONValue = e.picking(["Index", "wlEnable", "SSID", "upRate", "downRate", "wlHide", "wlEnableGuest", "wlGwMode",
                                          "AutoGenPSK", "psk_value", "RekeyingInterval", "X_ZYXEL_Preauth", "X_ZYXEL_ReauthInterval",
                                          "RadiusServerIPAddr", "RadiusServerPort", "RadiusSecret", "RadiusAccountingPort"])
            for (k, v) in WiFiSecurity.fields(for: mode, currentPMF: o["wlpmf"], modeChanged: mode != o["SecurityMode"].str) { b[k] = v }
            if e["psk_value"] != o["psk_value"] { b["AutoGenPSK"] = false }
            b["upRate"] = .int(Int64(e["upRate"].int ?? 0)); b["downRate"] = .int(Int64(e["downRate"].int ?? 0))
            b["wlGwMode"] = .int(Int64(e["wlGwMode"].int ?? 0))
            b["div_wifiSubnet"] = true
            let had = !o["MinAddress"].str.isEmpty, on = e["wlSubnetState"].bool
            b["wlSubnetState"] = .bool(on)
            b["subnetObjAction"] = on ? (had ? "PUT" : "POST") : (had ? "DELETE" : .null)
            if on {
                for k in ["MinAddress", "MaxAddress", "SubnetMask", "LANIP"] { b[k] = e[k] }
                b["Interface"] = .string("WiFi.SSID.\(e["Index"].int ?? 0)")
            }
            return b
        })

    static let wps = ObjectSpec(
        oid: "wps", title: "WPS", summary: "Methods per band. Disabled by the router while EasyMesh is on.",
        shape: .fixedList,
        fields: [
            .init("Band", "Band", .readOnly, column: true),
            .init("Enable", "Enabled", .bool, column: true),
            .init("EnablePBC", "Push button", .bool, when: ("Enable", [true]), column: true),
            .init("EnableStaPin", "Client PIN", .bool, when: ("Enable", [true]), column: true),
            .init("EnableAPPin", "Router PIN", .bool, when: ("Enable", [true]), column: true),
        ],
        followUp: wlCheck,
        loadTransform: { rows in
            rows.map { r in
                r.merging(["EnablePBC": r["X_ZYXEL_WPS_EnablePBC"], "EnableStaPin": r["X_ZYXEL_WPS_EnableStaPin"],
                           "EnableAPPin": r["X_ZYXEL_WPS_EnableAPPin"]])
            }
        },
        transform: { _, e in e.picking(["Band", "Enable", "EnablePBC", "EnableStaPin", "EnableAPPin"]) })

    static let macFilter = ObjectSpec(
        oid: "wifi_macfilter", title: "Wi-Fi MAC Filter",
        summary: "Per SSID: deny the listed devices, or allow only them. Up to 25 MACs each.",
        shape: .fixedList,
        fields: [
            .init("ssid", "SSID", .readOnly, column: true),
            .init("band", "Band", .readOnly, column: true),
            .init("mode", "Mode", .choice([.init(0, "Off"), .init(1, "Deny listed"), .init(2, "Allow only listed")]), column: true),
            .init("list", "MACs", .text(placeholder: "aa:bb:cc:dd:ee:ff, …"), help: "Comma-separated", column: true),
        ],
        loadTransform: { rows in
            // One row per wlan Index, in order; 9 and 10 are internal mesh SSIDs.
            rows.enumerated().compactMap { i, r in
                guard i < 8 else { return nil }
                return r.merging(["Index": .int(Int64(i + 1)), "band": i < 4 ? "2.4 GHz" : "5 GHz",
                                  "list": .string(r["list"].str.replacingOccurrences(of: "-", with: ":"))])
            }
        },
        transform: { _, e in
            let macs = e["list"].str.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
                .map { $0.lowercased().replacingOccurrences(of: ":", with: "-") }
            return ["Index": e["Index"], "FilterMode": .string(String(e["mode"].int ?? 0)), "FilterLists": .string(macs.joined(separator: ","))]
        })

    static let easyMesh = ObjectSpec(
        oid: "wifi_easy_mesh", title: "EasyMesh",
        summary: "Turning EasyMesh on copies the 2.4 GHz name and password to 5 GHz and sets 5 GHz to 80 MHz.",
        fields: [
            .init("EasyMeshEnable", "EasyMesh", .bool),
            .init("BandSteeringEnable", "Band steering", .readOnly),
            .init("CurRole", "Role", .choice([.init(1, "Controller"), .init(0, "Agent")])),
        ],
        confirm: radioWarning, followUp: wlCheck,
        transform: { o, e in
            var b: JSONValue = ["EasyMeshEnable": e["EasyMeshEnable"], "Controller_mode": o["Controller_mode"]]
            if e["EasyMeshEnable"].bool, !o["EasyMeshEnable"].bool { b["bandstreeringEnable"] = true }
            return b
        })

    static let radioAdvanced = ObjectSpec(
        oid: "wifi_others", title: "Radio (Advanced)", shape: .fixedList,
        fields: [
            .init("Band", "Band", .readOnly, column: true),
            .init("wlMode", "Standards", .choice([
                .init("b,g,n,ax", "b/g/n/ax"), .init("b,g,n", "b/g/n"), .init("a,n,ac,ax", "a/n/ac/ax"), .init("a,n,ac", "a/n/ac"), .init("n,ac", "n/ac"),
            ]), column: true),
            .init("wlTxPwrPcnt", "Transmit power", .choice([20, 40, 60, 80, 100].map { Choice(.int(Int64($0)), "\($0)%") }), column: true),
            .init("wlBcnIntvl", "Beacon interval", .int(min: 50, max: 1000, unit: "ms"), column: true),
            .init("wlDtmIntvl", "DTIM interval", .int(min: 1, max: 255)),
            .init("wlRtsThrshld", "RTS threshold", .int(min: 1, max: 2347)),
            .init("wlFrgThrshld", "Fragmentation threshold", .int(min: 256, max: 2346)),
            .init("wlProtect", "802.11g protection", .choice([.init("auto", "Auto"), .init("off", "Off")])),
            .init("wlPreamble", "Preamble", .choice([.init("long", "Long"), .init("short", "Short")])),
        ],
        loadIndexes: [1, 5], followUp: wlCheck,
        loadTransform: { rows in rows.map { r in r["wlPreamble"] == "auto" ? r.merging(["wlPreamble": "long"]) : r } },
        transform: { _, e in
            var b = e.picking(["Index", "wlRtsThrshld", "wlFrgThrshld", "wlTxPwrPcnt", "wlBcnIntvl", "wlDtmIntvl", "AutoChannelTimer",
                               "wlMode", "wlProtect", "wlPreamble", "InActiveChan", "atf", "acs_fcs_mode",
                               "X_ZYXEL_BF_Enable", "X_ZYXEL_IEEE80211R_Enable"])
            for k in ["wlRtsThrshld", "wlFrgThrshld", "wlTxPwrPcnt", "wlBcnIntvl", "wlDtmIntvl"] { b[k] = .int(Int64(e[k].int ?? 0)) }
            return b
        })

    static let dayChoices = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static let schedules = ObjectSpec(
        oid: "wlan_scheduler", title: "Wi-Fi Schedules",
        summary: "Turn Wi-Fi off on a timetable. Not provisioned on every firmware.",
        shape: .list,
        fields: [
            .init("Enable", "Enabled", .bool, default: true, column: true),
            .init("Name", "Name", .text(), required: true, column: true),
            .init("SSID", "SSID", .text(placeholder: "All WLAN"), default: "All WLAN", column: true),
            .init("Days", "Days", .text(placeholder: "Mon,Tue,Wed,Thu,Fri"), default: "Mon,Tue,Wed,Thu,Fri,Sat,Sun", column: true),
            .init("TimeStartHour", "Off from (h)", .int(min: 0, max: 23), default: 23, column: true),
            .init("TimeStartMin", "(min)", .int(min: 0, max: 59)),
            .init("TimeStopHour", "Until (h)", .int(min: 0, max: 24), default: 7, column: true),
            .init("TimeStopMin", "(min)", .int(min: 0, max: 59)),
            .init("Description", "Note", .text()),
        ],
        transform: { _, e in
            var b = e
            b["Enable"] = .int(e["Enable"].bool ? 1 : 0)
            b["Days"] = .array(e["Days"].str.split(separator: ",").map { .string($0.trimmingCharacters(in: .whitespaces)) })
            b["Interface"] = .int(e["SSID"].str == "All WLAN" ? 0 : 99)
            return b
        })
}
