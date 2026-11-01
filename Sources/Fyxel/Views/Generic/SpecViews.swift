import FyxelCore
import SwiftUI

// Generic editors driven by `ObjectSpec`. A page is a vertical stack of `SpecSection`s;
// single objects render as an inline form with Apply/Revert, lists as a compact table with
// add / edit / delete. Fields the spec doesn't describe are still reachable via "Raw".

/// A scrolling page of spec sections plus optional custom content on top.
struct SpecPage<Header: View>: View {
    var specs: [ObjectSpec]
    @ViewBuilder var header: Header

    var body: some View {
        RevealScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(specs) { SpecSection(spec: $0) }
            }
            .padding(16)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension SpecPage where Header == EmptyView {
    init(specs: [ObjectSpec]) { self.init(specs: specs) { EmptyView() } }
}

/// Loads one spec and shows the right editor, plus loading / permission / error states.
struct SpecSection: View {
    @Environment(AppModel.self) private var model
    var spec: ObjectSpec
    @State private var rows: [JSONValue]?
    @State private var error: Error?
    @State private var reloadToken = 0

    var body: some View {
        Panel(title: spec.title, systemImage: icon) {
            if let s = spec.summary { Text(s).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            content
        }
        .revealAnchor(Anchor.spec(spec))
        .environment(\.revealedField, model.request?.intent.revealedField(in: Anchor.spec(spec)))
        .task(id: "\(spec.id)#\(reloadToken)") { await load() }
    }

    var icon: String {
        switch spec.shape { case .single: "slider.horizontal.3"; case .list: "list.bullet"; case .fixedList: "square.grid.3x1.below.line.grid.1x2" }
    }

    @ViewBuilder var content: some View {
        if let e = error as? RouterError, e.isPermissionDenied {
            Label("The router refuses this page for your account level (\(model.accountLevel.isEmpty ? "?" : model.accountLevel)). It's only available to the ISP/supervisor account.",
                  systemImage: "lock")
                .foregroundStyle(.secondary)
        } else if let e = error {
            HStack {
                Label(e.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Retry") { reloadToken += 1 }
            }
        } else if let rows {
            switch spec.shape {
            case .single:
                SingleObjectEditor(spec: spec, original: rows.first ?? [:]) { reloadToken += 1 }
                    .id(rows.first)
            case .list, .fixedList:
                RowTable(spec: spec, rows: rows) { reloadToken += 1 }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    func load() async {
        do {
            let loaded = try await model.client.load(spec)
            rows = loaded
            model.specRows[spec.id] = loaded
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }
}

// MARK: - Single object

struct SingleObjectEditor: View {
    @Environment(AppModel.self) private var model
    var spec: ObjectSpec
    var original: JSONValue
    var reload: () -> Void
    @State private var edited: JSONValue
    @State private var saving = false
    @State private var confirming = false
    @State private var showRaw = false

    init(spec: ObjectSpec, original: JSONValue, reload: @escaping () -> Void) {
        self.spec = spec
        self.original = original
        self.reload = reload
        _edited = State(initialValue: original)
    }

    var dirty: Bool { edited != original }
    var problems: [String] { spec.validate(edited) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldGrid(spec: spec, obj: $edited, original: original)
            if !problems.isEmpty, dirty {
                ForEach(problems, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
            }
            HStack {
                Button("Raw…") { showRaw = true }.buttonStyle(.link).font(.caption)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                if dirty {
                    Text("\(ObjectSpec.changedKeys(original, edited).count) changed").font(.caption).foregroundStyle(.secondary)
                    Button("Revert") { edited = original }
                }
                Button("Apply") { if spec.confirm != nil { confirming = true } else { apply() } }
                    .disabled(!dirty || !problems.isEmpty || saving)
                    .keyboardShortcut(dirty ? .defaultAction : nil)
            }
        }
        .sheet(isPresented: $showRaw) { JSONInspector(title: spec.oid, value: original) }
        .confirmationDialog("Apply \(spec.title) changes?", isPresented: $confirming) {
            Button("Apply", role: .destructive) { apply() }
        } message: { Text(spec.confirm ?? "") }
    }

    func apply() {
        saving = true
        Task {
            let ok = await model.write(spec.title) { try await model.client.save(spec, original: original, edited: edited) }
            saving = false
            if ok { reload() }
        }
    }
}

/// Two-column grid of labelled controls for every visible field.
struct FieldGrid: View {
    var spec: ObjectSpec
    @Binding var obj: JSONValue
    var original: JSONValue?
    @Environment(\.revealedField) private var revealed

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            ForEach(spec.fields.filter { $0.isVisible(in: obj) }) { f in
                GridRow {
                    HStack(spacing: 4) {
                        Text(f.label)
                        if let o = original, o[f.key] != obj[f.key] { Circle().fill(.orange).frame(width: 5, height: 5) }
                    }
                    .foregroundStyle(revealed == f.key ? .primary : .secondary)
                    .background {
                        RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.3)).padding(-3)
                            .opacity(revealed == f.key ? 1 : 0)
                            .animation(.easeInOut(duration: revealed == f.key ? 0.2 : 0.6), value: revealed)
                    }
                    .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        FieldControl(field: f, value: Binding(get: { obj[f.key] }, set: { obj[f.key] = $0 }))
                        if let h = f.help { Text(h).font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true) }
                    }
                    .frame(maxWidth: 460, alignment: .leading)
                }
            }
        }
    }
}

struct FieldControl: View {
    var field: FieldSpec
    @Binding var value: JSONValue
    @State private var reveal = false

    var body: some View {
        switch field.kind {
        case .bool:
            Toggle("", isOn: Binding(get: { value.bool }, set: { value = .bool($0) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
        case .int(_, _, let unit):
            HStack {
                TextField("", value: intBinding, format: .number.grouping(.never)).mono().frame(width: 110)
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        case .seconds:
            HStack {
                TextField("", value: intBinding, format: .number.grouping(.never)).mono().frame(width: 110)
                Text("s · \(Fmt.duration(TimeInterval(value.int ?? 0)))").foregroundStyle(.secondary)
            }
        case .text(let p):
            TextField(p, text: stringBinding)
        case .ipv4:
            TextField("0.0.0.0", text: stringBinding).mono().frame(maxWidth: 200)
        case .mac:
            TextField("aa:bb:cc:dd:ee:ff", text: stringBinding).mono().frame(maxWidth: 220)
        case .password:
            HStack {
                if reveal { TextField("", text: stringBinding).mono() } else { SecureField("", text: stringBinding) }
                Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }.buttonStyle(.borderless)
            }
        case .choice(let choices):
            let all = choices.contains { $0.value == value } || value.isNull ? choices : choices + [Choice(value, "\(value.str) (current)")]
            Picker("", selection: $value) {
                ForEach(all, id: \.value) { Text($0.label).tag($0.value) }
            }
            .labelsHidden().fixedSize()
        case .readOnly:
            if case .bool(let b) = value {
                Label(b ? "On" : "Off", systemImage: b ? "checkmark.circle.fill" : "circle").foregroundStyle(b ? .green : .secondary)
            } else {
                Text(value.string ?? value.compactString).mono().textSelection(.enabled).foregroundStyle(.secondary)
            }
        }
    }

    /// Keeps the router's original JSON type (some numbers arrive as strings).
    var intBinding: Binding<Int> {
        Binding(get: { value.int ?? 0 }, set: { n in
            if case .string = value { value = .string(String(n)) } else { value = .int(Int64(n)) }
        })
    }

    var stringBinding: Binding<String> {
        Binding(get: { value.string ?? "" }, set: { value = .string($0) })
    }
}

// MARK: - Lists

struct RowTable: View {
    @Environment(AppModel.self) private var model
    var spec: ObjectSpec
    var rows: [JSONValue]
    var reload: () -> Void
    @State private var editing: EditTarget?
    @State private var deleting: JSONValue?
    @State private var raw: JSONValue?

    struct EditTarget: Identifiable { let id = UUID(); var row: JSONValue; var isNew: Bool }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Text("No entries.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        ForEach(spec.columns) { Text($0.label) }
                        Text("")
                    }
                    .font(.caption.bold()).foregroundStyle(.secondary)
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        GridRow {
                            ForEach(spec.columns) { c in CellText(field: c, value: r[c.key]) }
                            HStack(spacing: 6) {
                                Button { editing = EditTarget(row: r, isNew: false) } label: { Image(systemName: "pencil") }
                                if spec.shape == .list {
                                    Button { deleting = r } label: { Image(systemName: "trash") }
                                }
                            }
                            .buttonStyle(.borderless)
                            .gridColumnAlignment(.trailing)
                        }
                        .contextMenu {
                            Button("Edit…") { editing = EditTarget(row: r, isNew: false) }
                            Button("Show Raw…") { raw = r }
                            if spec.shape == .list { Divider(); Button("Delete…", role: .destructive) { deleting = r } }
                        }
                    }
                }
            }
            if spec.shape == .list {
                Button { editing = EditTarget(row: spec.newRow(), isNew: true) } label: { Label("Add", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { t in RowEditor(spec: spec, original: t.isNew ? nil : t.row, initial: t.row, reload: reload) }
        .sheet(item: Binding(get: { raw.map { IdentifiedJSON(value: $0) } }, set: { raw = $0?.value })) { JSONInspector(title: spec.oid, value: $0.value) }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                guard let d = deleting else { return }
                Task { if await model.write("Delete", { try await model.client.delete(spec, row: d) }) { reload() } }
            }
        }
    }
}

struct IdentifiedJSON: Identifiable { let id = UUID(); var value: JSONValue }

struct CellText: View {
    var field: FieldSpec
    var value: JSONValue
    var body: some View {
        switch field.kind {
        case .bool: StatusDot(on: value.bool)
        case .choice(let c): Text(c.first { $0.value == value }?.label ?? value.str).lineLimit(1)
        case .password: Text(value.str.isEmpty ? "" : "••••••").foregroundStyle(.secondary)
        case .seconds: Text(Fmt.duration(TimeInterval(value.int ?? 0)))
        case .ipv4, .mac, .int: Text(verbatim: value.string ?? "").mono()
        default: Text(verbatim: value.string ?? value.compactString).lineLimit(1)
        }
    }
}

struct RowEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var spec: ObjectSpec
    var original: JSONValue?
    var reload: () -> Void
    @State private var obj: JSONValue
    @State private var saving = false
    @State private var confirming = false

    init(spec: ObjectSpec, original: JSONValue?, initial: JSONValue, reload: @escaping () -> Void) {
        self.spec = spec
        self.original = original
        self.reload = reload
        _obj = State(initialValue: initial)
    }

    var problems: [String] { spec.validate(obj) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? "Add \(spec.title)" : "Edit \(spec.title)").font(.headline)
            FieldGrid(spec: spec, obj: $obj, original: original)
            ForEach(problems, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add" : "Save") { if spec.confirm != nil { confirming = true } else { save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!problems.isEmpty || saving || (original != nil && obj == original))
            }
        }
        .padding(20)
        .frame(minWidth: 480)
        .confirmationDialog("Apply?", isPresented: $confirming) {
            Button("Apply", role: .destructive) { save() }
        } message: { Text(spec.confirm ?? "") }
    }

    func save() {
        saving = true
        Task {
            let ok = await model.write(spec.title) { try await model.client.save(spec, original: original, edited: obj) }
            saving = false
            if ok { reload(); dismiss() }
        }
    }
}
