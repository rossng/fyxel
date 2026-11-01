import CommonCrypto
import Foundation
import Security

/// Mirrors the stock GUI's scheme: AES-256-CBC/PKCS7 with a client-chosen key, key sent
/// once at login wrapped with the router's RSA public key (PKCS#1 v1.5).
enum ZyCrypto {
    static func randomBytes(_ n: Int) -> Data {
        var d = Data(count: n)
        _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) }
        return d
    }

    /// The GUI generates 32-byte IVs; CryptoJS only uses the first block (16 bytes).
    static func aes(_ op: CCOperation, key: Data, iv: Data, data: Data) throws -> Data {
        let iv16 = iv.prefix(kCCBlockSizeAES128)
        guard key.count == kCCKeySizeAES256, iv16.count == kCCBlockSizeAES128 else {
            throw RouterError.crypto("bad key/iv length")
        }
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var outLen = 0
        let outCap = out.count
        let status = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { d in
                key.withUnsafeBytes { k in
                    iv16.withUnsafeBytes { i in
                        CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress, key.count, i.baseAddress,
                                d.baseAddress, data.count, o.baseAddress, outCap, &outLen)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw RouterError.crypto("CCCrypt failed (\(status))") }
        return out.prefix(outLen)
    }

    static func encrypt(_ plain: Data, key: Data) throws -> (content: String, iv: String) {
        let iv = randomBytes(32)
        let ct = try aes(CCOperation(kCCEncrypt), key: key, iv: iv, data: plain)
        return (ct.base64EncodedString(), iv.base64EncodedString())
    }

    static func decrypt(content: String, iv: String, key: Data) throws -> Data {
        guard let ct = Data(base64Encoded: content), let ivd = Data(base64Encoded: iv) else {
            throw RouterError.crypto("bad base64 in encrypted response")
        }
        return try aes(CCOperation(kCCDecrypt), key: key, iv: ivd, data: ct)
    }

    /// RSA-encrypt with a PEM "PUBLIC KEY" (SubjectPublicKeyInfo); returns base64 like JSEncrypt.
    static func rsaEncrypt(_ plain: Data, pem: String) throws -> String {
        let b64 = pem.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let spki = Data(base64Encoded: b64) else { throw RouterError.crypto("bad PEM") }
        let pkcs1 = try stripSPKI(spki)
        let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &err) else {
            throw RouterError.crypto("RSA key import: \(err!.takeRetainedValue())")
        }
        guard let ct = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, plain as CFData, &err) else {
            throw RouterError.crypto("RSA encrypt: \(err!.takeRetainedValue())")
        }
        return (ct as Data).base64EncodedString()
    }

    /// SEQUENCE { SEQUENCE { algId }, BIT STRING { 0x00, RSAPublicKey } } -> RSAPublicKey
    static func stripSPKI(_ der: Data) throws -> Data {
        let b = [UInt8](der)
        var i = 0
        func readLen() throws -> Int {
            guard i < b.count else { throw RouterError.crypto("DER truncated") }
            let first = Int(b[i]); i += 1
            if first < 0x80 { return first }
            let n = first & 0x7f
            var len = 0
            for _ in 0..<n { len = (len << 8) | Int(b[i]); i += 1 }
            return len
        }
        guard b.first == 0x30 else { throw RouterError.crypto("not SPKI") }
        i = 1; _ = try readLen()
        guard b[i] == 0x30 else { return der } // already PKCS#1
        i += 1; let algLen = try readLen(); i += algLen
        guard b[i] == 0x03 else { throw RouterError.crypto("no BIT STRING") }
        i += 1; let bitLen = try readLen()
        i += 1 // unused-bits byte
        return Data(b[i..<(i + bitLen - 1)])
    }
}
