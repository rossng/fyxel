import Foundation
import FyxelCore
import SwiftUI

enum Fmt {
    static func bits(_ bps: Double) -> String {
        let u = ["b/s", "kb/s", "Mb/s", "Gb/s"]
        var v = bps, i = 0
        while v >= 1000, i < u.count - 1 { v /= 1000; i += 1 }
        return i == 0 ? "\(Int(v)) \(u[i])" : String(format: v < 10 ? "%.2f %@" : v < 100 ? "%.1f %@" : "%.0f %@", v, u[i])
    }

    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .binary)
    }

    static func duration(_ s: TimeInterval) -> String {
        guard s > 0 else { return "—" }
        let t = Int(s), d = t / 86400, h = (t % 86400) / 3600, m = (t % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m \(t % 60)s"
    }

    static func ago(_ d: Date?) -> String {
        guard let d else { return "never" }
        let s = Int(-d.timeIntervalSinceNow)
        return s < 2 ? "just now" : "\(s)s ago"
    }
}

extension View {
    func mono() -> some View { font(.system(.body, design: .monospaced)) }
}

func copyToPasteboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

struct StatusDot: View {
    var on: Bool
    var body: some View {
        Circle().fill(on ? Color.green : Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
    }
}

/// Label/value rows for dense info panels.
struct KV: View {
    var k: String
    var v: String
    var mono = false
    var body: some View {
        GridRow {
            Text(k).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(v.isEmpty ? "—" : v)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .gridColumnAlignment(.leading)
        }
    }
}

struct Panel<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A sheet showing any JSON value, searchable and copyable.
struct JSONInspector: View {
    var title: String
    var value: JSONValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Copy") { copyToPasteboard(value.prettyString) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Text(value.prettyString)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }
}
