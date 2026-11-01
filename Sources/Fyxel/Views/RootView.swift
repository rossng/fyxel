import FyxelCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .loggedIn: MainView()
        default: LoginView()
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReboot = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            // A plain stack, not `.safeAreaInset` on the List: when the list doesn't fit, insets
            // let rows scroll under the (transparent) footer, and SwiftUI can loop re-insetting.
            VStack(spacing: 0) {
                PaletteButton().padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 6)
                List(selection: $model.section) {
                    ForEach(Section.Group.allCases, id: \.self) { g in
                        SwiftUI.Section(g.rawValue) {
                            ForEach(Section.allCases.filter { $0.group == g }) { s in
                                Label(s.rawValue, systemImage: s.icon).tag(s)
                            }
                        }
                    }
                }
                Divider()
                SidebarFooter()
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            SectionContent(section: model.section)
            .navigationTitle(model.section.rawValue)
            .safeAreaInset(edge: .top) {
                if let m = model.maintenanceStatus {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(m)
                        Spacer()
                    }
                    .padding(8)
                    .background(.yellow.opacity(0.15))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let e = model.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text(e).lineLimit(2).textSelection(.enabled)
                        Spacer()
                        Button { model.lastError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(.bar)
                }
            }
        }
        .toolbar {
            rateToolbarItem
            ToolbarItem {
                Button { Task { await model.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Refresh everything (⌘R)")
            }
            ToolbarItem {
                Menu {
                    Button("Reboot Router…", role: .destructive) { confirmReboot = true }
                    Divider()
                    Button("Log Out") { Task { await model.logout() } }
                } label: { Label("Router", systemImage: "power") }
            }
        }
        .confirmationDialog("Reboot the router?", isPresented: $confirmReboot) {
            Button("Reboot", role: .destructive) {
                Task { await model.rebootAndWait() }
            }
        } message: {
            Text("Everything on the network loses connectivity for a few minutes.")
        }
        .overlay(alignment: .top) {
            if model.paletteOpen {
                ZStack(alignment: .top) {
                    // Click outside to dismiss.
                    Color.black.opacity(0.08).ignoresSafeArea().onTapGesture { model.paletteOpen = false }
                    CommandPalette().padding(.top, 36)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.paletteOpen)
        .background {
            // ⇧⌘P as well as ⌘K, for VS Code / Sublime muscle memory.
            Button("") { model.paletteOpen.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        .onChange(of: model.request) { _, r in
            if r?.intent == .reboot { model.request = nil; confirmReboot = true }
        }
    }
}

/// Sidebar button that looks like a search field and opens the command palette.
struct PaletteButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { model.paletteOpen.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                Text("Go to…")
                Spacer(minLength: 4)
                Text("⌘K").font(.system(size: 11, weight: .medium, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Search pages, settings, actions, networks and devices (⌘K)")
    }
}

struct SidebarFooter: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 2) {
                if model.isDemo {
                    Label("Demo router", systemImage: "theatermasks").font(.caption)
                } else {
                    Text("\(model.username)@\(model.host)").font(.caption).mono()
                }
                Text("updated \(Fmt.ago(model.lastUpdated))").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }
}

/// WAN rate readout for the toolbar: plain text, fixed widths so it doesn't jiggle as the
/// numbers change, and a tiny sparkline of the last minute.
extension MainView {
    /// On macOS 26 toolbar items get a glass bubble; the readout looks better without it.
    @ToolbarContentBuilder var rateToolbarItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .status) { LiveRateChip() }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .status) { LiveRateChip() }
        }
    }
}

struct LiveRateChip: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let r = model.rates.last
        HStack(spacing: 12) {
            rate("arrow.down", r?.down, .blue)
            rate("arrow.up", r?.up, .orange)
            Sparkline(values: model.rates.suffix(30).map(\.down)).frame(width: 54, height: 16)
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .padding(.horizontal, 6)
        .fixedSize()
        .help("WAN throughput (last minute)")
    }

    func rate(_ icon: String, _ v: Double?, _ c: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(v.map(Fmt.bits) ?? "–").frame(width: 78, alignment: .leading)
        }
        .foregroundStyle(c)
    }
}

struct Sparkline: View {
    var values: [Double]
    var body: some View {
        GeometryReader { g in
            let peak = max(values.max() ?? 0, 1)
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = g.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                    let y = g.size.height * (1 - CGFloat(v / peak))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.blue.opacity(0.7), lineWidth: 1.2)
        }
    }
}

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var remember = true
    @FocusState private var focused: Bool
    @State private var triedAuto = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 18) {
            Image(systemName: "wifi.router").font(.system(size: 44)).foregroundStyle(.tint)
            Text("Fyxel").font(.largeTitle.bold())

            Form {
                TextField("Router", text: $model.host).mono()
                TextField("Username", text: $model.username).mono()
                SecureField("Password", text: $password).focused($focused).onSubmit(submit)
                Toggle("Save in Keychain, unlock with Touch ID", isOn: $remember)
            }
            .formStyle(.grouped)
            .frame(width: 380)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                if model.hasSavedPassword {
                    Button { Task { await model.unlockWithKeychain() } } label: {
                        Label("Unlock with Touch ID", systemImage: "touchid")
                    }
                    .controlSize(.large)
                }
                Button("Log In", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(password.isEmpty || model.phase == .loggingIn)
            }

            Button("Explore with demo data") { model.startDemo() }
                .buttonStyle(.link).font(.callout)
                .help("Runs against a simulated router with made-up devices. Nothing leaves this Mac.")

            if model.phase == .loggingIn { ProgressView().controlSize(.small) }
            if let e = model.loginError {
                VStack(spacing: 8) {
                    Text(e).foregroundStyle(.red).multilineTextAlignment(.center).textSelection(.enabled).frame(maxWidth: 460)
                    if e.contains("certificate") {
                        Button("Trust New Certificate") { model.trustNewCertificate() }
                    }
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !triedAuto else { return }
            triedAuto = true
            if model.hasSavedPassword, model.loginError == nil, !model.isDemo { await model.unlockWithKeychain() }
            else { focused = true }
        }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        let pw = password
        Task {
            await model.login(password: pw, remember: remember)
            if model.phase == .loggedIn { password = "" }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var refresh = false

    var body: some View {
        Form {
            LabeledContent("Router", value: "\(model.username)@\(model.host)")
            LabeledContent("Keychain") {
                HStack {
                    Text(model.hasSavedPassword ? "Password saved" : "No saved password")
                    if model.hasSavedPassword {
                        Button("Forget") { model.forgetSavedPassword(); refresh.toggle() }
                    }
                }
            }
            LabeledContent("Pinned certificate") {
                VStack(alignment: .trailing) {
                    Text(model.client.pinnedFingerprint ?? "none yet")
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: 300, alignment: .trailing)
                    Button("Forget Certificate") { model.trustNewCertificate(); refresh.toggle() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .id(refresh)
    }
}

struct SectionContent: View {
    var section: Section
    var body: some View {
        switch section {
        case .overview: OverviewView()
        case .devices: DevicesView()
        case .wifi: WiFiView()
        // One case per page (not a combined case) so each page gets its own view identity.
        case .wifiAdvanced: SpecPage(specs: section.specs)
        case .lan: SpecPage(specs: section.specs)
        case .dhcp: DHCPView()
        case .ports: PortForwardingView()
        case .nat: SpecPage(specs: section.specs)
        case .routing: SpecPage(specs: section.specs)
        case .firewall: SpecPage(specs: section.specs)
        case .parental: SpecPage(specs: section.specs)
        case .diagnostics: DiagnosticsView()
        case .logs: LogsView()
        case .maintenance: MaintenanceView()
        case .services: SpecPage(specs: section.specs)
        case .explorer: ExplorerView()
        }
    }
}
