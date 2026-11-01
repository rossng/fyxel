import FyxelCore
import FyxelMock
import Testing

@Suite struct OperationsTests {
    func api() async throws -> MockRouter {
        let m = MockRouter(latency: .zero)
        try await m.login(username: "admin", password: "x")
        return m
    }

    @Test func portForwardLifecycle() async throws {
        let m = try await api()
        let before = try await m.portForwards().count
        var r = PortForwardRule.new()
        r.description = "test"; r.externalStart = 8443; r.externalEnd = 8443
        r.internalStart = 443; r.internalEnd = 443; r.internalClient = "192.168.1.9"
        try await m.savePortForward(r)
        var added = try #require(try await m.portForwards().first { $0.description == "test" })
        added.externalStart = 9443
        try await m.savePortForward(added)
        #expect(try await m.portForwards().first { $0.index == added.index }?.externalStart == 9443)
        try await m.deletePortForward(index: added.index)
        #expect(try await m.portForwards().count == before)
    }

    @Test func reservationLifecycle() async throws {
        let m = try await api()
        try await m.saveReservation(index: 0, mac: "02:00:00:00:00:01", ip: "192.168.1.200", enabled: true)
        let r = try #require(try await m.dal("static_dhcp").first { $0["MACAddr"].str == "02:00:00:00:00:01" })
        try await m.deleteReservation(index: r["Index"].int ?? 0)
        #expect(try await m.dal("static_dhcp").contains { $0["MACAddr"].str == "02:00:00:00:00:01" } == false)
    }

    @Test func mediumLevelRejects() async throws {
        let m = MockRouter(level: "medium", latency: .zero)
        try await m.login(username: "admin", password: "x")
        await #expect(throws: RouterError.self) { try await m.dal("static_route") }
        do { _ = try await m.dal("qos") } catch let e as RouterError { #expect(e.isPermissionDenied) }
    }

    @Test func wifiEditRoundTrips() async throws {
        let m = try await api()
        let rec = try #require(try await m.dal("wlan").first { $0["Index"].int == 5 })
        var e = WiFiEdit(rec)
        e.ssid = "Renamed"; e.channel = 36
        try await m.saveWiFi([(rec, e)])
        let after = try #require(try await m.dal("wlan").first { $0["Index"].int == 5 })
        #expect(WiFiEdit(after).ssid == "Renamed")
        #expect(WiFiEdit(after).channel == 36)
    }
}
