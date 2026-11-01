import FyxelCore
import FyxelMock
import Testing

@Suite struct SpecTests {
    func api() async throws -> MockRouter {
        let m = MockRouter(latency: .zero)
        try await m.login(username: "admin", password: "x")
        return m
    }

    func spec(_ list: [ObjectSpec], _ title: String) throws -> ObjectSpec {
        try #require(list.first { $0.title == title })
    }

    @Test func mgmtModeRoundTrips() {
        for mode in ["LAN_ONLY", "LAN_WAN", "LAN_TstDm", "WL_WAN", "WL_Trust_Dm", "WL_ONLY", "LAN_withoutWL",
                     "LAN_withoutWL_WAN", "LAN_withoutWL_TstDm", "WAN_ONLY", "Trust_Dm"] {
            let f = MgmtMode.flags(mode)
            #expect(MgmtMode.mode(lan: f.lan, wlan: f.wlan, wan: f.wan, trust: f.trust) == mode)
        }
    }

    @Test func remoteManagementRefusesLockout() throws {
        let s = try spec(Specs.system, "Remote Management")
        let row: JSONValue = ["Name": "HTTPS", "LANEnable": false, "WLANEnable": false, "WANEnable": true, "TrustDmEnable": false]
        #expect(!s.validate(row).isEmpty)
    }

    @Test func remoteManagementSendsWholeArray() async throws {
        let m = try await api()
        let s = try spec(Specs.system, "Remote Management")
        let rows = try await m.load(s)
        var ssh = try #require(rows.first { $0["Name"] == "SSH" })
        let orig = ssh
        ssh["Enable"] = true
        try await m.save(s, original: orig, edited: ssh)
        let log = await m.writeLog
        let body = try #require(log.last?.body)
        #expect(body.array.count == rows.count)
        #expect(body.array.first { $0["Name"] == "SSH" }?["Mode"] == "LAN_ONLY")
    }

    @Test func firewallUsesWriteKeys() async throws {
        let m = try await api()
        let s = try spec(Specs.firewall, "Firewall")
        var o = try #require(try await m.load(s).first)
        let orig = o
        o["Level_GUI"] = "High"
        try await m.save(s, original: orig, edited: o)
        let body = try #require(await m.writeLog.last?.body)
        #expect(body["Firewall_Enable"] == true)
        #expect(body["Level_GUI"] == "High")
        #expect(body["Enable"].isNull)
    }

    @Test func portTriggerRenamesAndDeletesByIdx() async throws {
        let m = try await api()
        let s = try spec(Specs.nat, "Port Triggering")
        let r = try #require(try await m.load(s).first)
        #expect(r["TriggerPortStart"] == 6970)
        try await m.delete(s, row: r)
        let last = try #require(await m.writeLog.last)
        #expect(last.method == .DELETE)
        #expect(last.body?["idx"] == "1")
    }

    @Test func lanWritesFullObjectWithLogoutFlag() async throws {
        let m = try await api()
        let s = try spec(Specs.lan, "LAN & DHCP Server")
        var o = try #require(try await m.load(s).first)
        let orig = o
        o["DHCP_LeaseTime"] = 3600
        try await m.save(s, original: orig, edited: o)
        let last = try #require(await m.writeLog.last)
        #expect(last.path.contains("oid=lan"))
        #expect(last.body?["logout"] == 0)
        #expect(last.body?["IPv6_PrefixType"] == "DelegateFromWan")  // defaults merged in
    }

    @Test func wifiMacFilterWritesDashedList() async throws {
        let m = try await api()
        let s = try spec(Specs.wifi, "Wi-Fi MAC Filter")
        var r = try #require(try await m.load(s).first { $0["Index"] == 1 })
        let orig = r
        r["mode"] = 1
        r["list"] = "AA:BB:CC:DD:EE:01, aa:bb:cc:dd:ee:02"
        try await m.save(s, original: orig, edited: r)
        let body = try #require(await m.writeLog.last?.body)
        #expect(body["FilterMode"] == "1")
        #expect(body["FilterLists"] == "aa-bb-cc-dd-ee-01,aa-bb-cc-dd-ee-02")
    }

    @Test func securityModeChangeSetsWireFields() {
        let rec: JSONValue = ["Index": 1, "SecurityMode": "WPA3-Personal-Transition", "wlpmf": "capable", "PskDisplay": "password1",
                              "band": "2.4GHz", "channel": 6, "bandwidth": "20MHz"]
        var e = WiFiEdit(rec)
        e.security = "WPA3-Personal"
        let f = WiFiSecurity.fields(for: e.security, currentPMF: rec["wlpmf"], modeChanged: true)
        #expect(f["wpaMode"] == "wpa3sae")
        #expect(f["wlpmf"] == "required")
    }

    @Test func parsesLogLines() {
        let l = LogLine(id: 0, raw: "[dhcpd] Nov  1 10:00:01 user.info DHCPACK(br0) 192.168.1.5")
        #expect(l.category == "dhcpd")
        #expect(l.level == "info")
        #expect(l.message == "DHCPACK(br0) 192.168.1.5")
        #expect(l.time == "Nov 1 10:00:01")
    }

    @Test func parsesNATCounts() {
        let c = MockRouter.parseNATCounts("192.168.1.2 aa:bb:cc:dd:ee:ff 12 192.168.1.3 AA:BB:CC:DD:EE:00 3 ")
        #expect(c.count == 2)
        #expect(c[1].mac == "aa:bb:cc:dd:ee:00")
    }
}
