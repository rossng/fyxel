import AppKit
import FyxelCore
import SwiftUI

/// ⌘K "Go to Anything": fuzzy search over pages, panels, settings, actions and the
/// router's configured objects, shown as a floating panel over the window.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @AppStorage("palette.recent") private var recentRaw = ""
    @State private var query = ""
    @State private var selected = 0
    /// Snapshot taken on open, so results don't shuffle as polling updates the model.
    @State private var items: [PaletteItem] = []

    static let rowHeight: CGFloat = 46
    static let maxRows = 9

    var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }

    /// Ranked fresh on each call: key handlers must not use results from an earlier render,
    /// or ↩ typed straight after a letter opens what matched before that letter.
    var results: [PaletteRanker.Ranked] { PaletteRanker(recent: recent).rank(items, query: query) }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(.secondary)
                PaletteField(text: Binding(get: { query }, set: { query = $0; selected = 0 }),
                             placeholder: "Search pages, settings, actions, networks, devices…",
                             onMove: { move($0, count: self.results.count) },
                             onSubmit: { let r = self.results; if r.indices.contains(selected) { run(r[selected].item) } },
                             onCancel: close)
            }
            .padding(.horizontal, 14).frame(height: 50)
            Divider()
            if results.isEmpty {
                Text(items.isEmpty ? "" : "No matches for “\(query)”")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 60)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results.indices, id: \.self) { i in
                                PaletteRow(ranked: results[i], selected: i == selected,
                                           isRecent: query.isEmpty && recent.contains(results[i].item.id))
                                    .frame(height: Self.rowHeight)
                                    .contentShape(Rectangle())
                                    .onTapGesture { run(results[i].item) }
                                    .id(i)
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: CGFloat(min(results.count, Self.maxRows)) * Self.rowHeight + 12)
                    .onChange(of: selected) { _, s in proxy.scrollTo(s) }
                }
            }
            Divider()
            HStack(spacing: 14) {
                key("↑↓", "select"); key("↩", "open"); key("esc", "close")
                Spacer()
                Text(query.isEmpty ? "Recent, pages and actions" : "\(results.count)\(results.count == 60 ? "+" : "") matches")
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 14).frame(height: 28)
        }
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 28, y: 12)
        .onAppear { items = PaletteIndex.build(model) }
        .onExitCommand(perform: close)
    }

    func key(_ k: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(k).font(.caption.monospaced()).padding(.horizontal, 4).background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            Text(label)
        }
    }

    func move(_ d: Int, count: Int) {
        guard count > 0 else { return }
        selected = (selected + d + count) % count
    }

    func close() { model.paletteOpen = false }

    func run(_ item: PaletteItem) {
        recentRaw = ([item.id] + recent.filter { $0 != item.id }).prefix(8).joined(separator: "\n")
        close()
        item.run(model)
    }
}

struct PaletteRow: View {
    var ranked: PaletteRanker.Ranked
    var selected: Bool
    var isRecent: Bool

    var body: some View {
        let item = ranked.item
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(selected ? Color.white.opacity(0.2) : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(highlighted(item.title, ranked.titleHits)).lineLimit(1)
                Text(item.subtitle).font(.caption).lineLimit(1)
                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 8)
            if let h = item.hint { Text(h).font(.caption.monospaced()).opacity(0.7) }
            HStack(spacing: 3) {
                if isRecent { Image(systemName: "clock") }
                Text(item.kind.label)
            }
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(selected ? Color.white.opacity(0.2) : Color.primary.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
    }

    /// The title with the characters the query matched in bold.
    func highlighted(_ s: String, _ hits: [Int]) -> AttributedString {
        guard !hits.isEmpty else { return AttributedString(s) }
        let set = Set(hits)
        var out = AttributedString()
        for (i, c) in s.enumerated() {
            var part = AttributedString(String(c))
            if set.contains(i) {
                part.font = .body.bold()
                part.underlineStyle = .single
            }
            out += part
        }
        return out
    }
}

/// A borderless text field that takes focus when shown and reports ↑/↓ (and ⌃P/⌃N), ↩ and esc.
/// AppKit-backed because SwiftUI's TextField lets the field editor swallow the arrow keys.
struct PaletteField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let f = AutoFocusTextField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 18)
        f.placeholderString = placeholder
        f.cell?.usesSingleLineMode = true
        f.lineBreakMode = .byTruncatingTail
        f.delegate = context.coordinator
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text { f.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteField
        init(_ parent: PaletteField) { self.parent = parent }

        func controlTextDidChange(_ n: Notification) {
            if let f = n.object as? NSTextField { parent.text = f.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            default: return false
            }
            return true
        }
    }

    final class AutoFocusTextField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let w = self.window else { return }
                w.makeFirstResponder(self)
            }
        }
    }
}
