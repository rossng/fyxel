import Foundation
import FyxelCore
import FyxelMock

// fyxelctl — raw access to the router API.
//
//   fyxelctl get /cgi-bin/DAL?oid=lanhosts
//   fyxelctl dal lanhosts
//
// Auth (first match wins):
//   FYXEL_MOCK=1                                  talk to the built-in mock router
//   FYXEL_SESSION + FYXEL_AESKEY (+ FYXEL_CSRF)   reuse a browser session
//                                                 (FYXEL_SESSION_FILE=path saves rotated tokens back)
//   FYXEL_PASSWORD                                log in with this password
//   otherwise                                     password from the Fyxel keychain item (Touch ID)

let env = ProcessInfo.processInfo.environment
let host = env["FYXEL_HOST"] ?? "192.168.1.1"
let user = env["FYXEL_USER"] ?? "admin"
var args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: fyxelctl get <path>          GET any endpoint, print decrypted JSON
           fyxelctl dal <oid>           GET /cgi-bin/DAL?oid=<oid>, print Object
           fyxelctl login               log in and print a session (for FYXEL_SESSION etc.)
           fyxelctl put|post <oid> <json>   write a DAL object (body encrypted)
           fyxelctl delete <oid> <Index>    DELETE /cgi-bin/DAL?oid=<oid>&Index=N
           fyxelctl req <METHOD> <path> [json]   raw request to any /cgi-bin path
           fyxelctl selftest            add + delete a throwaway port forward and DHCP reservation
           fyxelctl specs               load every settings page and report what the router allows
           fyxelctl ping <host>         ping from the router

    """.utf8))
    exit(2)
}

guard let cmd = args.first else { usage() }
args.removeFirst()

let real = RouterClient(host: host)
let client: any RouterAPI = env["FYXEL_MOCK"] != nil ? MockRouter(latency: .zero) : real

do {
    if client is MockRouter {
        try await client.login(username: user, password: "mock")
    } else if let cookie = env["FYXEL_SESSION"], let k = env["FYXEL_AESKEY"], let key = Data(base64Encoded: k) {
        await real.restore(RouterSession(cookie: cookie, aesKey: key, csrfToken: env["FYXEL_CSRF"] ?? ""))
    } else {
        let pw: String
        if let p = env["FYXEL_PASSWORD"] { pw = p } else {
            pw = try await CredentialStore.unlock(user: user, host: host, reason: "let fyxelctl log in to your router")
        }
        try await client.login(username: user, password: pw)
    }

    switch cmd {
    case "get":
        guard let p = args.first else { usage() }
        print(try await client.get(p).prettyString)
    case "dal":
        guard let oid = args.first else { usage() }
        print(JSONValue.array(try await client.dal(oid)).prettyString)
    case "login":
        guard let s = await real.session else { usage() }
        print("export FYXEL_SESSION='\(s.cookie)' FYXEL_AESKEY='\(s.aesKey.base64EncodedString())' FYXEL_CSRF='\(s.csrfToken)'")
    case "put", "post":
        guard args.count >= 2 else { usage() }
        let obj = try JSONValue.parse(Data(args[1].utf8))
        print(try await client.dalWrite(cmd == "put" ? .PUT : .POST, oid: args[0], obj).prettyString)
    case "delete":
        guard args.count >= 2 else { usage() }
        print(try await client.dalWrite(.DELETE, oid: args[0], ["Index": .string(args[1])]).prettyString)
    case "req":
        guard args.count >= 2, let m = HTTPMethod(rawValue: args[0].uppercased()) else { usage() }
        let body = args.count > 2 ? try JSONValue.parse(Data(args[2].utf8)) : nil
        print(try await client.request(m, args[1], query: [:], body: body).prettyString)
    case "selftest":
        try await selftest(client)
    case "selftest-specs":
        try await selftestSpecs(client)
    case "specs":
        try await checkSpecs(client)
    case "ping":
        guard let h = args.first else { usage() }
        for try await t in client.runDiagnostic(.ping, host: h) { print("\u{1B}[2J\u{1B}[H" + t) }
    default:
        usage()
    }
    await saveSession()
} catch {
    await saveSession()
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}

/// With FYXEL_SESSION_FILE set, write the (possibly rotated) session back as `export …` lines,
/// so `source $FYXEL_SESSION_FILE` before the next call keeps a borrowed session usable.
func saveSession() async {
    guard let path = env["FYXEL_SESSION_FILE"], let s = await real.session else { return }
    let line = "export FYXEL_SESSION='\(s.cookie)' FYXEL_AESKEY='\(s.aesKey.base64EncodedString())' FYXEL_CSRF='\(s.csrfToken)'\n"
    try? line.write(toFile: path, atomically: true, encoding: .utf8)
}

func selftest(_ c: any RouterAPI) async throws {
    func step(_ s: String) { print("• \(s)") }
    // Port forward on an unused high port to a nonexistent LAN IP, disabled.
    var r = PortForwardRule.new()
    r.enabled = false
    r.description = "fyxel-selftest"
    r.externalStart = 54321; r.externalEnd = 54321
    r.internalStart = 54321; r.internalEnd = 54321
    r.internalClient = "192.168.1.253"
    r.proto = "TCP"
    step("add port forward")
    try await c.savePortForward(r)
    guard var added = try await c.portForwards().first(where: { $0.description == "fyxel-selftest" }) else {
        throw RouterError.badResponse("added rule not found")
    }
    step("  added as Index \(added.index)")
    added.externalStart = 54322; added.externalEnd = 54322
    step("edit port forward")
    try await c.savePortForward(added)
    let edited = try await c.portForwards().first(where: { $0.index == added.index })
    step("  external port now \(edited?.externalStart ?? -1)")
    step("delete port forward")
    try await c.deletePortForward(index: added.index)
    let gone = try await c.portForwards().contains { $0.description == "fyxel-selftest" }
    step("  removed: \(!gone)")

    // DHCP reservation for a locally-administered MAC that no device uses.
    let mac = "02:00:00:fe:fe:01"
    step("add reservation")
    try await c.saveReservation(index: 0, mac: mac, ip: "192.168.1.252", enabled: false)
    guard let res = try await c.dal("static_dhcp").first(where: { $0["MACAddr"].str.lowercased() == mac }) else {
        throw RouterError.badResponse("added reservation not found")
    }
    let idx = res["Index"].int ?? 0
    step("  added as Index \(idx)")
    step("edit reservation")
    try await c.saveReservation(index: idx, mac: mac, ip: "192.168.1.251", enabled: false)
    let ed = try await c.dal("static_dhcp").first(where: { $0["Index"].int == idx })
    step("  IP now \(ed?["IPAddr"].str ?? "?")")
    step("delete reservation")
    try await c.deleteReservation(index: idx)
    let rgone = try await c.dal("static_dhcp").contains { $0["MACAddr"].str.lowercased() == mac }
    step("  removed: \(!rgone)")
}

func checkSpecs(_ c: any RouterAPI) async throws {
    let pages: [(String, [ObjectSpec])] = [
        ("Wi-Fi", Specs.wifi), ("LAN", Specs.lan), ("NAT", Specs.nat), ("Routing", Specs.routing),
        ("Firewall", Specs.firewall), ("Parental", Specs.parental), ("System", Specs.system + [Specs.logSettings]),
        ("Services", Specs.services),
    ]
    for (page, specs) in pages {
        for s in specs {
            let label = "\(page) / \(s.title) (\(s.oid))".padding(toLength: 52, withPad: " ", startingAt: 0)
            do {
                let rows = try await c.load(s)
                let missing = Set(s.fields.map(\.key)).subtracting(rows.flatMap { $0.object?.keys.map { $0 } ?? [] })
                print("ok    \(label) \(rows.count) rows" + (missing.isEmpty || rows.isEmpty ? "" : "  (absent: \(missing.sorted().joined(separator: ", ")))"))
            } catch let e as RouterError where e.isPermissionDenied {
                print("deny  \(label)")
            } catch {
                print("FAIL  \(label) \(error.localizedDescription)")
            }
        }
    }
}

/// Add → verify → delete a harmless row through the generic spec path, for a few list objects.
func selftestSpecs(_ c: any RouterAPI) async throws {
    func spec(_ l: [ObjectSpec], _ t: String) -> ObjectSpec { l.first { $0.title == t }! }
    let cases: [(ObjectSpec, JSONValue, (JSONValue) -> Bool)] = [
        (spec(Specs.lan, "Local DNS Names"), ["HostName": "fyxel-selftest.home", "IPv4Address": "192.168.1.252"],
         { $0["HostName"] == "fyxel-selftest.home" }),
        (spec(Specs.nat, "Port Triggering"), ["Enable": false, "Description": "fyxel-selftest", "TriggerProtocol": "UDP",
                                              "TriggerPortStart": 54321, "TriggerPortEnd": 54321, "OpenProtocol": "UDP",
                                              "OpenPortStart": 54322, "OpenPortEnd": 54322],
         { $0["Description"] == "fyxel-selftest" }),
        (spec(Specs.firewall, "Firewall Services"), ["Name": "fyxselftest", "Description": "", "Protocol": "TCP", "DestPort": 54321, "DestPortEnd": -1],
         { $0["Name"] == "fyxselftest" }),
    ]
    for (s, fields, match) in cases {
        print("• \(s.title)")
        do {
            let row = s.newRow().merging(fields)
            try await c.save(s, original: nil, edited: row)
            guard let added = try await c.load(s).first(where: match) else { print("  ✗ not found after add"); continue }
            print("  added: \(added.compactString.prefix(140))")
            try await c.delete(s, row: added)
            let still = try await c.load(s).contains(where: match)
            print(still ? "  ✗ still present after delete" : "  ✓ deleted")
        } catch {
            print("  ✗ \(error.localizedDescription)")
        }
    }
    print("• LEDs")
    let on = try await c.ledsOn()
    try await c.setLEDs(!on)
    let flipped = try await c.ledsOn()
    try await c.setLEDs(on)
    print("  was \(on), toggled to \(flipped), restored to \(try await c.ledsOn())")
}
