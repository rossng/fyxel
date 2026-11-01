import Foundation

/// Loosely-typed JSON, used because the router's DAL objects are wide, inconsistent and
/// mostly round-tripped back to it unchanged on writes.
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue {
        get { if case .object(let o) = self { return o[key] ?? .null }; return .null }
        set {
            if case .object(var o) = self { o[key] = newValue; self = .object(o) }
        }
    }

    public subscript(index: Int) -> JSONValue {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    public var string: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        default: return nil
        }
    }
    public var str: String { string ?? "" }

    public var int: Int? {
        switch self {
        case .int(let i): return Int(i)
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    public var int64: Int64? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int64(d)
        case .string(let s): return Int64(s)
        default: return nil
        }
    }

    public var bool: Bool {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .string(let s): return s == "true" || s == "1"
        default: return false
        }
    }

    public var array: [JSONValue] { if case .array(let a) = self { return a }; return [] }
    public var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    public init(_ any: Any?) {
        switch any {
        case nil, is NSNull: self = .null
        case let v as JSONValue: self = v
        case let b as Bool: self = .bool(b)
        case let i as Int: self = .int(Int64(i))
        case let i as Int64: self = .int(i)
        case let d as Double: self = .double(d)
        case let s as String: self = .string(s)
        case let a as [Any?]: self = .array(a.map(JSONValue.init))
        case let o as [String: Any?]: self = .object(o.mapValues(JSONValue.init))
        default: self = .string(String(describing: any!))
        }
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func encoded(pretty: Bool = false) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        return (try? enc.encode(self)) ?? Data("null".utf8)
    }

    public var prettyString: String { String(decoding: encoded(pretty: true), as: UTF8.self) }
    public var compactString: String { String(decoding: encoded(), as: UTF8.self) }

    /// The router HTML-escapes strings in GET responses; the stock GUI undoes it.
    func htmlUnescaped() -> JSONValue {
        switch self {
        case .string(let s):
            guard s.contains("&") else { return self }
            return .string(s
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&"))
        case .array(let a): return .array(a.map { $0.htmlUnescaped() })
        case .object(let o): return .object(o.mapValues { $0.htmlUnescaped() })
        default: return self
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByNilLiteral
{
    public init(stringLiteral v: String) { self = .string(v) }
    public init(integerLiteral v: Int) { self = .int(Int64(v)) }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(nilLiteral: ()) { self = .null }
}
