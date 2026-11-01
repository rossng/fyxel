import FyxelCore
import SwiftUI
import UniformTypeIdentifiers

struct MaintenanceView: View {
    var body: some View {
        SpecPage(specs: Specs.system) {
            HStack(alignment: .top, spacing: 14) {
                DevicePanel()
                ConfigPanel()
            }
            HStack(alignment: .top, spacing: 14) {
                FirmwarePanel()
                PasswordPanel()
            }
        }
    }
}

/// Reboot and LEDs.
struct DevicePanel: View {
    @Environment(AppModel.self) private var model
    @State private var leds: Bool?
    @State private var confirmReboot = false

    var body: some View {
        Panel(title: "Device", systemImage: "wifi.router") {
            Grid(alignment: .leading, verticalSpacing: 8) {
                KV(k: "Model", v: model.status?.model ?? "")
                KV(k: "Firmware", v: model.status?.firmware ?? "", mono: true)
                KV(k: "Uptime", v: Fmt.duration(model.status?.uptime ?? 0))
                GridRow {
                    Text("LEDs").foregroundStyle(.secondary)
                    if let on = leds {
                        Toggle("", isOn: Binding(get: { on }, set: { v in
                            leds = v
                            Task { if !(await model.write("LEDs", { try await model.client.setLEDs(v) })) { leds = !v } }
                        }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Reboot…") { confirmReboot = true }
            }
        }
        .task { leds = try? await model.client.ledsOn() }
        .confirmationDialog("Reboot the router?", isPresented: $confirmReboot) {
            Button("Reboot", role: .destructive) { Task { await model.rebootAndWait() } }
        } message: { Text("Everything loses internet for a couple of minutes. Fyxel reconnects when it's back.") }
    }
}

/// Backup / restore.
struct ConfigPanel: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var restoreFile: URL?
    @State private var message: String?

    var body: some View {
        Panel(title: "Configuration", systemImage: "externaldrive") {
            Text("Back up all router settings to a file, or restore one. Restoring reboots the router and may change its address or password.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Restore…") { pickRestore() }.disabled(busy)
                Button("Back Up…") { backup() }.disabled(busy)
            }
        }
        .confirmationDialog("Restore \(restoreFile?.lastPathComponent ?? "")?", isPresented: Binding(get: { restoreFile != nil }, set: { if !$0 { restoreFile = nil } })) {
            Button("Restore and Reboot", role: .destructive) { if let u = restoreFile { restore(u) } }
        } message: { Text("All current settings are replaced. The router reboots.") }
    }

    func backup() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let data = try await model.client.backupConfig()
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "router-config-\(Date().formatted(.iso8601.year().month().day())).bin"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try data.write(to: url)
                message = "Saved \(Fmt.bytes(Int64(data.count))) to \(url.lastPathComponent)"
            } catch {
                model.lastError = "Backup: \(error.localizedDescription)"
            }
        }
    }

    func pickRestore() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return }
        restoreFile = panel.url
    }

    func restore(_ url: URL) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let data = try Data(contentsOf: url)
                let max = (try? await model.client.maxUploadSize("config")) ?? 0
                if max > 0, data.count > max { throw RouterError.badResponse("File is larger than the router accepts (\(Fmt.bytes(Int64(max)))).") }
                try await model.client.restoreConfig(data, fileName: url.lastPathComponent)
                message = "Restored. The router is rebooting…"
                await model.waitForRouterAndRelogin()
            } catch {
                model.lastError = "Restore: \(error.localizedDescription)"
            }
        }
    }
}

struct FirmwarePanel: View {
    @Environment(AppModel.self) private var model
    @State private var file: URL?
    @State private var confirm = false
    @State private var phase: String?

    var body: some View {
        Panel(title: "Firmware", systemImage: "cpu") {
            Grid(alignment: .leading) { KV(k: "Installed", v: model.status?.firmware ?? "", mono: true) }
            Text("Upload a firmware image for this model. The router flashes it and reboots; don't power it off.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let phase { Label(phase, systemImage: "hourglass").font(.callout) }
            HStack {
                Spacer()
                if phase != nil { ProgressView().controlSize(.small) }
                Button("Upgrade…") {
                    let panel = NSOpenPanel()
                    guard panel.runModal() == .OK, let u = panel.url else { return }
                    file = u; confirm = true
                }
                .disabled(phase != nil)
            }
        }
        .confirmationDialog("Install \(file?.lastPathComponent ?? "")?", isPresented: $confirm) {
            Button("Upload and Install", role: .destructive) { if let f = file { upgrade(f) } }
        } message: { Text("The router will be offline for several minutes.") }
    }

    func upgrade(_ url: URL) {
        Task {
            do {
                phase = "Checking image…"
                let data = try Data(contentsOf: url)
                let max = (try? await model.client.maxUploadSize("firmware")) ?? 0
                if max > 0, data.count > max { throw RouterError.badResponse("Image is larger than the router accepts (\(Fmt.bytes(Int64(max)))).") }
                phase = "Uploading \(Fmt.bytes(Int64(data.count)))…"
                try await model.client.upgradeFirmware(data, fileName: url.lastPathComponent)
                phase = "Flashing and rebooting…"
                await model.waitForRouterAndRelogin()
            } catch {
                model.lastError = "Firmware: \(error.localizedDescription)"
            }
            phase = nil
        }
    }
}

struct PasswordPanel: View {
    @Environment(AppModel.self) private var model
    @State private var old = ""
    @State private var new = ""
    @State private var again = ""
    @State private var busy = false

    var problems: [String] {
        var p = RouterClient.passwordProblems(new).map { "Needs \($0)" }
        if !again.isEmpty, again != new { p.append("Passwords don't match") }
        return p
    }

    var body: some View {
        Panel(title: "Admin Password", systemImage: "key") {
            Grid(alignment: .leading, verticalSpacing: 6) {
                GridRow { Text("Current").foregroundStyle(.secondary); SecureField("", text: $old) }
                GridRow { Text("New").foregroundStyle(.secondary); SecureField("", text: $new) }
                GridRow { Text("Again").foregroundStyle(.secondary); SecureField("", text: $again) }
            }
            if !new.isEmpty { ForEach(problems, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) } }
            HStack {
                Text("Updates the Keychain item too.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Change") {
                    busy = true
                    Task {
                        if await model.changePassword(old: old, new: new) { old = ""; new = ""; again = "" }
                        busy = false
                    }
                }
                .disabled(old.isEmpty || new.isEmpty || again != new || !problems.isEmpty || busy)
            }
        }
    }
}
