import Foundation

public typealias CredentialProvider = @Sendable () async throws -> (username: String, password: String)?

/// The seam between the app and a router. `RouterClient` talks to real hardware;
/// `MockRouter` (FyxelMock) emulates one in memory. Everything else — typed operations,
/// models, the UI — is written against this protocol and works with either.
///
/// Implementations only provide transport and session handling. `request` takes and returns
/// plaintext JSON: encryption, CSRF tokens and re-login are the implementation's business.
public protocol RouterAPI: AnyObject, Sendable {
    var host: String { get }
    /// Human-readable account level ("high", "medium"…) once logged in.
    var accountLevel: String { get async }

    func login(username: String, password: String) async throws
    func logout() async
    /// Used to log back in transparently when the router expires the session.
    func setCredentialProvider(_ p: CredentialProvider?) async

    func request(_ method: HTTPMethod, _ path: String, query: [String: String], body: JSONValue?) async throws -> JSONValue
    /// multipart/form-data upload (firmware, config restore).
    func upload(_ path: String, field: String, fileName: String, data: Data) async throws -> JSONValue
    /// Raw GET of a non-JSON resource (config backup).
    func download(_ path: String) async throws -> Data

    /// True when the router's web server answers and isn't mid-upgrade (no login needed).
    func isReachable() async -> Bool

    var pinnedFingerprint: String? { get }
    func forgetPinnedCertificate()
}

// MARK: - Conveniences shared by every implementation

extension RouterAPI {
    /// GET an endpoint and return the decrypted JSON.
    public func get(_ path: String, query: [String: String] = [:]) async throws -> JSONValue {
        try await request(.GET, path, query: query, body: nil)
    }

    /// GET /cgi-bin/DAL?oid=… and return `Object` (after checking `result`).
    public func dal(_ oid: String, query: [String: String] = [:]) async throws -> [JSONValue] {
        let j = try await get("/cgi-bin/DAL?oid=\(oid)", query: query)
        try checkDAL(j)
        return j["Object"].array
    }

    /// POST/PUT/DELETE a DAL object. DELETE sends the object's fields as query parameters.
    @discardableResult
    public func dalWrite(_ method: HTTPMethod, oid: String, _ obj: JSONValue, query: [String: String] = [:]) async throws -> JSONValue {
        let path = "/cgi-bin/DAL?oid=\(oid)"
        let j: JSONValue
        if method == .DELETE {
            var q = query
            for (k, v) in obj.object ?? [:] { q[k] = v.string ?? v.compactString }
            j = try await request(.DELETE, path, query: q, body: nil)
        } else {
            j = try await request(method, path, query: query, body: obj)
        }
        try checkDAL(j)
        return j
    }

    @discardableResult
    public func post(_ path: String, _ obj: JSONValue? = nil) async throws -> JSONValue {
        try await request(.POST, path, query: [:], body: obj)
    }

    public func checkDAL(_ j: JSONValue) throws {
        let r = j["result"].str
        if r != "ZCFG_SUCCESS" {
            throw RouterError.dal(result: r.isEmpty ? "unknown error" : r, message: j["ReplyMsg"].str)
        }
    }
}

extension RouterError {
    /// The router refuses this object for the logged-in account level.
    public var isPermissionDenied: Bool {
        if case .dal(let r, _) = self { return r == "ZCFG_REQUEST_REJECT" }
        return false
    }
}
