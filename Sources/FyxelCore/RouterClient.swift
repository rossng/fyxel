import CryptoKit
import Foundation

public enum RouterError: LocalizedError, Equatable {
    case notLoggedIn
    case sessionExpired
    case loginFailed(String)
    case http(Int, String)
    case dal(result: String, message: String)
    case crypto(String)
    case badResponse(String)
    case certificateChanged(host: String, pinned: String, presented: String)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "Not logged in"
        case .sessionExpired: return "Session expired"
        case .loginFailed(let m): return "Login failed: \(m)"
        case .http(let c, let b): return "HTTP \(c): \(b.prefix(200))"
        case .dal(let r, let m): return m.isEmpty ? r : "\(r) (\(m))"
        case .crypto(let m): return "Crypto error: \(m)"
        case .badResponse(let m): return "Bad response: \(m.prefix(200))"
        case .certificateChanged(let h, let p, let n):
            return "The TLS certificate for \(h) changed.\nPinned:    \(p)\nPresented: \(n)"
        }
    }
}

public struct RouterSession: Sendable, Codable, Equatable {
    public var cookie: String     // value of the `Session` cookie
    public var aesKey: Data       // raw 32-byte AES key
    public var csrfToken: String  // `sessionkey`, sent as the CSRFToken header on writes
    public var account: String
    public var level: String

    public init(cookie: String, aesKey: Data, csrfToken: String, account: String = "", level: String = "") {
        self.cookie = cookie; self.aesKey = aesKey; self.csrfToken = csrfToken
        self.account = account; self.level = level
    }
}

public enum HTTPMethod: String, Sendable { case GET, POST, PUT, DELETE }

/// Talks to a Zyxel "OPAL" web backend (EX5601 and friends): /cgi-bin/DAL?oid=… etc.
/// The real router. Implements `RouterAPI`; operations live in protocol extensions.
public actor RouterClient: RouterAPI {

    public nonisolated let host: String
    public private(set) var session: RouterSession?
    private let urlSession: URLSession
    private let trust: TrustDelegate
    private var credentialProvider: CredentialProvider?
    private var loginTask: Task<RouterSession, Error>?

    public init(host: String) {
        self.host = host
        self.trust = TrustDelegate(host: host)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.timeoutIntervalForRequest = 20
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: cfg, delegate: trust, delegateQueue: nil)
    }

    /// Used to transparently log back in when the router expires the session.
    public func setCredentialProvider(_ p: CredentialProvider?) { credentialProvider = p }

    public func restore(_ s: RouterSession) { session = s }

    public var isLoggedIn: Bool { session != nil }
    public var accountLevel: String { session?.level ?? "" }

    // MARK: Login / logout

    public func login(username: String, password: String) async throws {
        if let t = loginTask { _ = try await t.value; return }
        let t = Task { try await performLogin(username: username, password: password) }
        loginTask = t
        defer { loginTask = nil }
        session = try await t.value
    }

    private func performLogin(username: String, password: String) async throws -> RouterSession {
        let keyJSON = try await raw(.GET, "/getRSAPublickKey", body: nil, auth: nil).json
        guard let pem = keyJSON["RSAPublicKey"].string, !pem.isEmpty else {
            throw RouterError.badResponse("no RSA public key")
        }
        let aesKey = ZyCrypto.randomBytes(32)
        let aesKeyB64 = aesKey.base64EncodedString()
        let payload: JSONValue = [
            "Input_Account": .string(username),
            "Input_Passwd": .string(Data(password.utf8).base64EncodedString()),
            "currLang": "en",
            "RememberPassword": 0,
            "SHA512_password": false,
        ]
        let (content, iv) = try ZyCrypto.encrypt(payload.encoded(), key: aesKey)
        let wrapped = try ZyCrypto.rsaEncrypt(Data(aesKeyB64.utf8), pem: pem)
        let body: JSONValue = ["content": .string(content), "key": .string(wrapped), "iv": .string(iv)]

        let resp = try await raw(.POST, "/UserLogin", body: body.encoded(), auth: nil, allowErrorStatus: true)
        let json = (try? decryptIfNeeded(resp.json, key: aesKey)) ?? resp.json
        guard resp.status == 200, json["result"].string == "ZCFG_SUCCESS" else {
            let msg = json["result"].string ?? "HTTP \(resp.status)"
            throw RouterError.loginFailed(msg)
        }
        guard let cookie = resp.cookies["Session"] else {
            throw RouterError.loginFailed("router did not set a session cookie")
        }
        return RouterSession(cookie: cookie, aesKey: aesKey, csrfToken: json["sessionkey"].str,
                             account: json["loginAccount"].string ?? username,
                             level: json["loginLevel"].str)
    }

    public func logout() async {
        if session != nil { _ = try? await raw(.POST, "/cgi-bin/UserLogout", body: nil, auth: session) }
        session = nil
    }

    // MARK: Requests

    public func request(_ method: HTTPMethod, _ path: String, query: [String: String], body: JSONValue?) async throws -> JSONValue {
        try await send(method, path, query: query, body: body, retried: false)
    }

    private func send(_ method: HTTPMethod, _ path: String, query: [String: String], body: JSONValue?,
                      retried: Bool) async throws -> JSONValue {
        guard let s = session else {
            if try await reauthenticate() { return try await send(method, path, query: query, body: body, retried: true) }
            throw RouterError.notLoggedIn
        }
        var fullPath = path
        if !query.isEmpty {
            let qs = query.sorted { $0.key < $1.key }
                .map { "\(Self.formEncode($0.key))=\(Self.formEncode($0.value))" }
                .joined(separator: "&")
            fullPath += (path.contains("?") ? "&" : "?") + qs
        }
        var bodyData: Data?
        if let body {
            let (content, iv) = try ZyCrypto.encrypt(body.encoded(), key: s.aesKey)
            bodyData = JSONValue.object(["content": .string(content), "key": "", "iv": .string(iv)]).encoded()
        }
        let resp = try await raw(method, fullPath, body: bodyData, auth: s, allowErrorStatus: true)

        if Self.isAuthFailure(resp) {
            session = nil
            if !retried, try await reauthenticate() {
                return try await send(method, path, query: query, body: body, retried: true)
            }
            throw RouterError.sessionExpired
        }
        // A write with a stale CSRF token gets an empty 403. The token can't be recovered,
        // so log in again (if we can) and retry once.
        if resp.status == 403, method != .GET, !retried, credentialProvider != nil {
            session = nil
            if try await reauthenticate() { return try await send(method, path, query: query, body: body, retried: true) }
        }
        guard (200..<300).contains(resp.status) else {
            if resp.status == 403, method != .GET, resp.data.isEmpty {
                throw RouterError.badResponse("The router refused the write (stale CSRF token). Log in again.")
            }
            throw RouterError.http(resp.status, String(decoding: resp.data, as: UTF8.self))
        }
        var json = try decryptIfNeeded(resp.json, key: s.aesKey)
        if method == .GET { json = json.htmlUnescaped() }
        if let k = json["sessionkey"].string, !k.isEmpty { session?.csrfToken = k }
        return json
    }

    private func reauthenticate() async throws -> Bool {
        guard let p = credentialProvider, let c = try await p() else { return false }
        try await login(username: c.username, password: c.password)
        return true
    }

    private static func isAuthFailure(_ r: RawResponse) -> Bool {
        if r.status == 401 { return true }
        let res = r.json["result"].string ?? ""
        // An idle-expired session answers HTTP 504 {"result":"Timeout"}.
        return res == "Invalid Username or Password" || res == "NotLogin" || res == "Timeout"
    }

    private func decryptIfNeeded(_ j: JSONValue, key: Data) throws -> JSONValue {
        guard let content = j["content"].string, let iv = j["iv"].string else { return j }
        let plain = try ZyCrypto.decrypt(content: content, iv: iv, key: key)
        return try JSONValue.parse(plain)
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    public func upload(_ path: String, field: String, fileName: String, data: Data) async throws -> JSONValue {
        guard let s = session else { throw RouterError.notLoggedIn }
        let boundary = "----fyxel\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"\(fileName)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let r = try await raw(.POST, path, body: body, auth: s, contentType: "multipart/form-data; boundary=\(boundary)",
                              timeout: 600)
        if Self.isAuthFailure(r) { session = nil; throw RouterError.sessionExpired }
        return (try? decryptIfNeeded(r.json, key: s.aesKey)) ?? r.json
    }

    public func isReachable() async -> Bool {
        guard let r = try? await raw(.GET, "/GetInfoNoLogin", body: nil, auth: nil, timeout: 5), r.status == 200 else { return false }
        return !r.json["FWUpgradeAgentDownloading"].bool
    }

    public func download(_ path: String) async throws -> Data {
        guard let s = session else { throw RouterError.notLoggedIn }
        let r = try await raw(.GET, path, body: nil, auth: s, timeout: 120)
        if Self.isAuthFailure(r) { session = nil; throw RouterError.sessionExpired }
        return r.data
    }

    // MARK: Transport

    struct RawResponse {
        var status: Int
        var data: Data
        var cookies: [String: String]
        var json: JSONValue { (try? JSONValue.parse(data)) ?? .null }
    }

    private func raw(_ method: HTTPMethod, _ path: String, body: Data?, auth: RouterSession?,
                     allowErrorStatus: Bool = false, contentType: String? = nil,
                     timeout: TimeInterval? = nil) async throws -> RawResponse {
        guard let url = URL(string: "https://\(host)\(path)") else { throw RouterError.badResponse("bad URL \(path)") }
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("Thu, 01 Jun 1970 00:00:00 GMT", forHTTPHeaderField: "If-Modified-Since")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        if let auth {
            req.setValue("Session=\(auth.cookie)", forHTTPHeaderField: "Cookie")
            if method != .GET, path.hasPrefix("/cgi-bin") { req.setValue(auth.csrfToken, forHTTPHeaderField: "CSRFToken") }
        }
        if let body {
            req.httpBody = body
            req.setValue(contentType ?? "application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        if let timeout { req.timeoutInterval = timeout }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: req)
        } catch {
            if let pinErr = trust.lastPinError { trust.lastPinError = nil; throw pinErr }
            throw error
        }
        let http = response as! HTTPURLResponse
        var cookies: [String: String] = [:]
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
        for c in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) { cookies[c.name] = c.value }
        let r = RawResponse(status: http.statusCode, data: data, cookies: cookies)
        if !allowErrorStatus, !(200..<300).contains(r.status) {
            throw RouterError.http(r.status, String(decoding: data, as: UTF8.self))
        }
        return r
    }

    // MARK: Certificate pinning (trust on first use)

    public nonisolated var pinnedFingerprint: String? { TrustDelegate.pin(for: host) }
    public nonisolated func forgetPinnedCertificate() { TrustDelegate.setPin(nil, for: host) }
}

/// The router uses a self-signed cert. Trust whatever it presents first, then pin it.
final class TrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let host: String
    var lastPinError: RouterError?

    init(host: String) { self.host = host }

    static func key(_ host: String) -> String { "certPin.\(host)" }
    static func pin(for host: String) -> String? { UserDefaults.standard.string(forKey: key(host)) }
    static func setPin(_ fp: String?, for host: String) { UserDefaults.standard.set(fp, forKey: key(host)) }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first
        else { return completionHandler(.performDefaultHandling, nil) }

        let der = SecCertificateCopyData(leaf) as Data
        let fp = SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
        if let pinned = Self.pin(for: host) {
            guard pinned == fp else {
                lastPinError = .certificateChanged(host: host, pinned: pinned, presented: fp)
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            Self.setPin(fp, for: host)
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
