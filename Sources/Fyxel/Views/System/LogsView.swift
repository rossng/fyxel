import FyxelCore
import SwiftUI
import UniformTypeIdentifiers

struct LogsView: View {
    @Environment(AppModel.self) private var model
    @State private var kind: LogKind = .system
    @State private var lines: [LogLine] = []
    @State private var categories: [String] = []
    @State private var category = ""
    @State private var maxLevel = 7
    @State private var search = ""
    @State private var error: String?
    @State private var loading = false
    @State private var confirmClear = false
    @State private var showSettings = false
    @State private var follow = false

    var filtered: [LogLine] {
        lines.reversed().filter { l in
            l.severity <= maxLevel && (search.isEmpty || l.raw.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $kind) { ForEach(LogKind.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                Picker("Category", selection: $category) {
                    Text("All").tag("")
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()
                Picker("Level", selection: $maxLevel) {
                    ForEach(Array(LogLine.levels.enumerated()), id: \.offset) { i, l in Text("≤ \(l)").tag(i) }
                }
                .fixedSize()
                Toggle("Follow", isOn: $follow).toggleStyle(.checkbox).help("Reload every 5 seconds")
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.help("Reload")
                Button { export() } label: { Image(systemName: "square.and.arrow.down") }.help("Save as text…").disabled(lines.isEmpty)
                Button { showSettings = true } label: { Image(systemName: "gearshape") }.help("Log settings")
                Button(role: .destructive) { confirmClear = true } label: { Image(systemName: "trash") }.help("Clear this log")
            }
            .padding(10)
            Divider()
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).padding()
            }
            Table(filtered) {
                TableColumn("Time") { l in Text(l.time).mono().foregroundStyle(.secondary) }.width(min: 120, ideal: 130, max: 150)
                TableColumn("Level") { l in LevelBadge(level: l.level) }.width(min: 56, ideal: 64, max: 72)
                TableColumn("Category") { l in Text(l.category).foregroundStyle(.secondary) }.width(min: 60, ideal: 80, max: 110)
                TableColumn("Message") { l in Text(l.message).mono().lineLimit(1).help(l.raw) }.width(min: 300, ideal: 900)
            }
            .contextMenu(forSelectionType: LogLine.ID.self) { ids in
                Button("Copy") { copyToPasteboard(lines.filter { ids.contains($0.id) }.map(\.raw).joined(separator: "\n")) }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("\(filtered.count) of \(lines.count) lines").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter log")
        .task(id: "\(kind.rawValue)/\(category)") { await load() }
        .task(id: kind) {
            categories = (try? await model.client.logCategories(kind)) ?? []
            if !categories.contains(category) { category = "" }
        }
        .task(id: follow) {
            while follow, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await load()
            }
        }
        .confirmationDialog("Clear the \(kind.label.lowercased()) log on the router?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) {
                Task { if await model.write("Clear log", { try await model.client.clearLog(kind) }) { await load() } }
            }
        } message: { Text("This can't be undone.") }
        .sheet(isPresented: $showSettings) {
            VStack(alignment: .leading) {
                SpecSection(spec: Specs.logSettings)
                HStack { Spacer(); Button("Done") { showSettings = false }.keyboardShortcut(.defaultAction) }
            }
            .padding()
            .frame(width: 560)
        }
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            lines = try await model.client.logLines(kind, category: category)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "router-\(kind.rawValue)-\(Date().formatted(.iso8601.year().month().day())).log"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? lines.map(\.raw).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

struct LevelBadge: View {
    var level: String
    var body: some View {
        let sev = LogLine.levels.firstIndex(of: level) ?? 6
        Text(level.isEmpty ? "–" : level)
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background((sev <= 3 ? Color.red : sev == 4 ? .orange : sev == 5 ? .yellow : .gray).opacity(0.2), in: Capsule())
    }
}
