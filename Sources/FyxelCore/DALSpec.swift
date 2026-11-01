import Foundation

// Declarative descriptions of router config objects. One `ObjectSpec` drives a generic
// editor (form for single objects, table + sheet for lists) and the generic read/write
// operations below, so adding a settings page is mostly data.

public struct Choice: Sendable, Hashable {
    public var value: JSONValue
    public var label: String
    public init(_ value: JSONValue, _ label: String) { self.value = value; self.label = label }
}

public struct FieldSpec: Sendable, Identifiable {
    public enum Kind: Sendable {
        case bool
        case int(min: Int? = nil, max: Int? = nil, unit: String? = nil)
        case text(placeholder: String = "")
        case ipv4
        case mac
        case password
        case choice([Choice])
        /// Shown, never edited.
        case readOnly
        /// Seconds, displayed as a duration.
        case seconds
    }

    public var id: String { key }
    public var key: String
    public var label: String
    public var kind: Kind
    public var help: String?
    /// Value for new list rows.
    public var defaultValue: JSONValue
    /// Only show (and validate) when another field has one of these values.
    public var visibleWhen: (key: String, values: [JSONValue])?
    public var required: Bool
    /// Show this field as a table column (list objects).
    public var column: Bool

    public init(_ key: String, _ label: String, _ kind: Kind, help: String? = nil, default def: JSONValue? = nil,
                when: (String, [JSONValue])? = nil, required: Bool = false, column: Bool = false) {
        self.key = key
        self.label = label
        self.kind = kind
        self.help = help
        self.visibleWhen = when.map { (key: $0.0, values: $0.1) }
        self.required = required
        self.column = column
        self.defaultValue = def ?? {
            switch kind {
            case .bool: return false
            case .int, .seconds: return 0
            case .choice(let c): return c.first?.value ?? ""
            default: return ""
            }
        }()
    }

    public func isVisible(in obj: JSONValue) -> Bool {
        guard let w = visibleWhen else { return true }
        return w.values.contains(obj[w.key])
    }

    /// nil if valid, else a message.
    public func validate(_ v: JSONValue) -> String? {
        switch kind {
        case .ipv4:
            if v.str.isEmpty { return required ? "\(label) is required" : nil }
            return Validate.ipv4(v.str) ? nil : "\(label) must be an IPv4 address"
        case .mac:
            if v.str.isEmpty { return required ? "\(label) is required" : nil }
            return Validate.mac(v.str) ? nil : "\(label) must look like aa:bb:cc:dd:ee:ff"
        case .int(let lo, let hi, _):
            guard let i = v.int else { return required ? "\(label) is required" : nil }
            if let lo, i < lo { return "\(label) must be ≥ \(lo)" }
            if let hi, i > hi { return "\(label) must be ≤ \(hi)" }
            return nil
        case .text, .password:
            return required && v.str.isEmpty ? "\(label) is required" : nil
        default:
            return nil
        }
    }
}

public struct ObjectSpec: Sendable, Identifiable {
    public enum Shape: Sendable {
        /// `Object[0]` is a settings object; edits PUT it back.
        case single
        /// `Object` is a list of rows keyed by `Index`: POST adds, PUT edits, DELETE removes.
        case list
        /// `Object` is a fixed list (e.g. one per band/service): rows are edited, never added or removed.
        case fixedList
    }

    public typealias Transform = @Sendable (_ original: JSONValue, _ edited: JSONValue) -> JSONValue
    /// Like `Transform`, but may read from the router first.
    public typealias Prepare = @Sendable (_ api: any RouterAPI, _ original: JSONValue, _ edited: JSONValue) async throws -> JSONValue
    public typealias LoadTransform = @Sendable (_ rows: [JSONValue]) -> [JSONValue]
    public typealias WriteQuery = @Sendable (_ original: JSONValue, _ edited: JSONValue) -> [String: String]

    public var id: String { oid + (title) }
    public var oid: String
    public var title: String
    public var summary: String?
    public var shape: Shape
    public var fields: [FieldSpec]
    /// Query parameter name DELETE uses for the row ("Index" for most, "idx" for some).
    public var deleteKey: String
    /// Extra fields every new row needs (beyond field defaults).
    public var addTemplate: JSONValue
    /// Builds the request body from the original and edited object. Default: the edited object.
    public var transform: Transform?
    /// Warn before applying (e.g. "may disconnect you").
    public var confirm: String?
    /// Title for a row in lists (falls back to the first column).
    public var rowTitleKey: String?
    /// Only send keys that the spec knows about (plus Index) instead of the whole object.
    public var sendOnlyKnownFields: Bool
    /// Load each of these Index values with `DalGetOneObject=y` instead of one plain GET.
    public var loadIndexes: [Int]?
    /// Reshape rows after loading (rename keys, derive fields, hide internal rows).
    public var loadTransform: LoadTransform?
    /// Extra query parameters for writes (e.g. `Logout=0&timedelay=1` on `lan`).
    public var writeQuery: WriteQuery?
    /// GET this after a successful write (e.g. `/cgi-bin/Wireless?action=WlCheck`).
    public var followUp: String?
    /// Extra cross-field checks; return messages for problems.
    public var validator: (@Sendable (JSONValue) -> [String])?
    /// Method used to add rows (a few oids add via PUT).
    public var addMethod: HTTPMethod
    public var prepare: Prepare?

    public init(oid: String, title: String, summary: String? = nil, shape: Shape = .single, fields: [FieldSpec],
                deleteKey: String = "Index", addTemplate: JSONValue = [:], confirm: String? = nil,
                rowTitleKey: String? = nil, sendOnlyKnownFields: Bool = false, loadIndexes: [Int]? = nil,
                followUp: String? = nil, addMethod: HTTPMethod = .POST, validator: (@Sendable (JSONValue) -> [String])? = nil,
                loadTransform: LoadTransform? = nil, writeQuery: WriteQuery? = nil, transform: Transform? = nil,
                prepare: Prepare? = nil) {
        self.oid = oid
        self.title = title
        self.summary = summary
        self.shape = shape
        self.fields = fields
        self.deleteKey = deleteKey
        self.addTemplate = addTemplate
        self.confirm = confirm
        self.rowTitleKey = rowTitleKey
        self.sendOnlyKnownFields = sendOnlyKnownFields
        self.transform = transform
        self.loadIndexes = loadIndexes
        self.loadTransform = loadTransform
        self.writeQuery = writeQuery
        self.followUp = followUp
        self.addMethod = addMethod
        self.validator = validator
        self.prepare = prepare
    }

    public var columns: [FieldSpec] {
        let c = fields.filter(\.column)
        return c.isEmpty ? Array(fields.prefix(4)) : c
    }

    public func newRow() -> JSONValue {
        var o = addTemplate.object == nil ? JSONValue.object([:]) : addTemplate
        for f in fields where o[f.key].isNull { o[f.key] = f.defaultValue }
        o["Index"] = 0
        return o
    }

    public func validate(_ obj: JSONValue) -> [String] {
        fields.filter { $0.isVisible(in: obj) }.compactMap { $0.validate(obj[$0.key]) } + (validator?(obj) ?? [])
    }

    /// Keys whose value differs between two objects (for "what will change" summaries).
    public static func changedKeys(_ a: JSONValue, _ b: JSONValue) -> [String] {
        let ka = Set(a.object?.keys ?? [:].keys), kb = Set(b.object?.keys ?? [:].keys)
        return ka.union(kb).filter { a[$0] != b[$0] }.sorted()
    }
}

extension JSONValue {
    /// Shallow merge: keys in `other` overwrite ours.
    public func merging(_ other: JSONValue) -> JSONValue {
        guard var a = object, let b = other.object else { return other.isNull ? self : other }
        for (k, v) in b { a[k] = v }
        return .object(a)
    }

    public func droppingNulls() -> JSONValue {
        guard let o = object else { return self }
        return .object(o.filter { !$0.value.isNull })
    }

    /// Only these keys.
    public func picking(_ keys: [String]) -> JSONValue {
        var o: [String: JSONValue] = [:]
        for k in keys where !self[k].isNull { o[k] = self[k] }
        return .object(o)
    }
}

public enum Validate {
    public static func ipv4(_ s: String) -> Bool {
        let p = s.split(separator: ".", omittingEmptySubsequences: false)
        return p.count == 4 && p.allSatisfy { !$0.isEmpty && $0.count <= 3 && UInt8($0) != nil }
    }
    public static func mac(_ s: String) -> Bool {
        s.range(of: #"^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$"#, options: .regularExpression) != nil
    }
}

// MARK: - Generic operations

extension RouterAPI {
    public func load(_ spec: ObjectSpec) async throws -> [JSONValue] {
        var rows: [JSONValue]
        if let idx = spec.loadIndexes {
            rows = []
            for i in idx {
                for var r in try await dal(spec.oid, query: ["DalGetOneObject": "y", "Index": String(i)]) {
                    if r["Index"].isNull { r["Index"] = .int(Int64(i)) }
                    rows.append(r)
                }
            }
        } else {
            rows = try await dal(spec.oid)
        }
        return spec.loadTransform?(rows) ?? rows
    }

    /// Writes one object (settings object or list row). Rows with Index 0 are added.
    public func save(_ spec: ObjectSpec, original: JSONValue?, edited: JSONValue) async throws {
        var body = edited
        if spec.sendOnlyKnownFields {
            var o: [String: JSONValue] = [:]
            for f in spec.fields { o[f.key] = edited[f.key] }
            if !edited["Index"].isNull { o["Index"] = edited["Index"] }
            body = .object(o)
        }
        if let t = spec.transform { body = t(original ?? .null, body) }
        if let p = spec.prepare { body = try await p(self, original ?? .null, body) }
        let isNew = spec.shape == .list && (edited["Index"].int ?? 0) == 0
        if isNew, body.object != nil { body["Index"] = .null; body = body.droppingNulls() }
        let q = spec.writeQuery?(original ?? .null, edited) ?? [:]
        try await dalWrite(isNew ? spec.addMethod : .PUT, oid: spec.oid, body, query: q)
        if let f = spec.followUp { _ = try? await get(f) }
    }

    public func delete(_ spec: ObjectSpec, row: JSONValue) async throws {
        let key = row[spec.deleteKey].isNull ? row["Index"] : row[spec.deleteKey]
        try await dalWrite(.DELETE, oid: spec.oid, [spec.deleteKey: key])
        if let f = spec.followUp { _ = try? await get(f) }
    }
}
