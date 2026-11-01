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
    default:
        usage()
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
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
