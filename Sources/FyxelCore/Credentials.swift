import Foundation
import LocalAuthentication
import Security

/// Router password in the login keychain, released only after Touch ID (or the Mac's
/// password as a fallback, e.g. lid closed / no sensor).
///
/// Note: Touch ID here is an app-level gate (LAContext) in front of a regular keychain item,
/// not a biometry-bound ACL. Hardware-bound items need the data-protection keychain, which
/// needs a provisioning profile; not worth it for a personal tool.
public enum CredentialStore {
    static let service = "eu.rossng.fyxel.router"

    static func account(user: String, host: String) -> String { "\(user)@\(host)" }

    public static func hasPassword(user: String, host: String) -> Bool {
        let q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account(user: user, host: host),
            kSecReturnAttributes: true,
        ]
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    public static func save(password: String, user: String, host: String) throws {
        let acct = account(user: user, host: host)
        let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: acct]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData] = Data(password.utf8)
        add[kSecAttrLabel] = "Fyxel router password (\(host))"
        add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        let st = SecItemAdd(add as CFDictionary, nil)
        guard st == errSecSuccess else { throw keychainError(st) }
    }

    public static func delete(user: String, host: String) {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                  kSecAttrAccount: account(user: user, host: host)]
        SecItemDelete(q as CFDictionary)
    }

    /// Prompts for Touch ID, then reads the password.
    public static func unlock(user: String, host: String, reason: String = "log in to your router") async throws -> String {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Password…"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            throw err ?? NSError(domain: "Fyxel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Authentication unavailable"])
        }
        try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        return try read(user: user, host: host)
    }

    /// Reads without a Touch ID prompt (used by the CLI when explicitly asked).
    public static func read(user: String, host: String) throws -> String {
        let q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account(user: user, host: host),
            kSecReturnData: true,
        ]
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        guard st == errSecSuccess, let d = out as? Data else { throw keychainError(st) }
        return String(decoding: d, as: UTF8.self)
    }

    static func keychainError(_ st: OSStatus) -> NSError {
        let msg = SecCopyErrorMessageString(st, nil) as String? ?? "Keychain error \(st)"
        return NSError(domain: NSOSStatusErrorDomain, code: Int(st), userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
