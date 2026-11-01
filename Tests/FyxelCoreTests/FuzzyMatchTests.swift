import FyxelCore
import Testing

@Suite struct FuzzyMatchTests {
    func score(_ q: String, _ t: String) -> Int? { FuzzyMatch.match(q, t)?.score }

    @Test func requiresAllCharactersInOrder() {
        #expect(FuzzyMatch.match("lan", "LAN") != nil)
        #expect(FuzzyMatch.match("nal", "LAN") == nil)
        #expect(FuzzyMatch.match("lans", "LAN") == nil)
        #expect(FuzzyMatch.match("", "anything")?.positions == [])
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(FuzzyMatch.match("WIFI", "wi-fi") != nil)
        #expect(FuzzyMatch.match("cafe", "Café Guest") != nil)
    }

    @Test func prefersWordStartsAndRuns() throws {
        // "pf" should hit the initials of Port Forwarding, not letters inside words.
        let r = try #require(FuzzyMatch.match("pf", "Port Forwarding"))
        #expect(r.positions == [0, 5])
        // Contiguous beats scattered.
        #expect(score("dns", "Local DNS Names")! > score("dns", "Dynamic Names Server")!)
        // Word-start initials beat a mid-word run.
        #expect(score("ap", "Admin Password")! > score("ap", "Snapshot")!)
    }

    @Test func prefersShorterTextOnEqualMatch() {
        #expect(score("lan", "LAN")! > score("lan", "LAN & DHCP Server")!)
    }

    @Test func picksBestAlignmentNotFirst() throws {
        // A greedy matcher would take the "s" in "Guest"; the best alignment starts "SSID".
        let r = try #require(FuzzyMatch.match("ssid", "Guest SSID"))
        #expect(r.positions == [6, 7, 8, 9])
    }

    @Test func scatteredMatchesScoreLow() {
        #expect(score("lan", "Login Attempts allowed then")! <= 0)
    }
}
