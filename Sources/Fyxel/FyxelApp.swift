import FyxelCore
import SwiftUI

@main
struct FyxelApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup("Fyxel") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear { delegate.model = model; DevSnapshots.startIfRequested(model) }
        }
        .defaultSize(width: 1320, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Router") {
                Button("Refresh") { Task { await model.refreshAll() } }
                    .keyboardShortcut("r")
                    .disabled(model.phase != .loggedIn)
                Divider()
                ForEach(Section.allCases) { s in
                    if let k = s.shortcut {
                        Button(s.rawValue) { model.section = s }.keyboardShortcut(k)
                    } else {
                        Button(s.rawValue) { model.section = s }
                    }
                }
                Divider()
                Button("Log Out") { Task { await model.logout() } }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(model.phase != .loggedIn)
            }
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}

/// Log out on quit so the router doesn't keep a dangling session.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.phase == .loggedIn else { return .terminateNow }
        Task { @MainActor in
            await model.logout()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Captures one of our own windows via the window server (no screen-recording permission is
/// needed for a process's own windows). Looked up dynamically because the SDK marks it obsolete.
@MainActor
func windowImage(_ w: NSWindow) -> CGImage? {
    typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    guard let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "CGWindowListCreateImage") else { return nil }
    let f = unsafeBitCast(sym, to: Fn.self)
    // kCGWindowListOptionIncludingWindow = 1<<3; boundsIgnoreFraming = 1<<0, bestResolution = 1<<3
    return f(.null, 1 << 3, UInt32(w.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue()
}

/// Dev hook: FYXEL_SNAPSHOT_DIR=/path makes the app walk every section and save a PNG of
/// its own window (no screen-recording permission needed), then quit.
@MainActor
enum DevSnapshots {
    static func startIfRequested(_ model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["FYXEL_SNAPSHOT_DIR"] else { return }
        let only = ProcessInfo.processInfo.environment["FYXEL_SNAPSHOT_ONLY"]?.split(separator: ",").map(String.init)
        Task { @MainActor in
            NSApp.appearance = NSAppearance(named: .aqua)
            NSApp.activate(ignoringOtherApps: true)
            if let w = NSApp.windows.first(where: \.isVisible) {
                w.setContentSize(NSSize(width: 1320, height: 820))
                w.center()
                w.makeKeyAndOrderFront(nil)
            }
            // Let the throughput graph collect some history first.
            try? await Task.sleep(for: .seconds(model.isDemo ? 40 : 8))
            for s in Section.allCases where only == nil || only!.contains(s.rawValue) {
                model.section = s
                try? await Task.sleep(for: .seconds(3))
                print("[snapshot] \(s.rawValue): status=\(model.status != nil) hosts=\(model.hosts.count) wlan=\(model.wlan.count) rates=\(model.rates.count) err=\(model.lastError ?? "-")")
                let slug = s.rawValue.lowercased().replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-")
                if s == .overview, ProcessInfo.processInfo.environment["FYXEL_SNAPSHOT_RENDER"] != nil {
                    let content = OverviewContent()
                    .environment(model)
                    .frame(width: 1100)
                    .background(Color(nsColor: .windowBackgroundColor))
                    let r = ImageRenderer(content: content)
                    r.scale = 2
                    if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(slug)-full.png")
                        try? rep.representation(using: .png, properties: [:])?.write(to: url)
                    }
                }
                guard let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { continue }
                let url = URL(fileURLWithPath: dir).appendingPathComponent("\(slug).png")
                if let img = windowImage(w) {
                    let rep = NSBitmapImageRep(cgImage: img)
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                } else if let v = w.contentView?.superview ?? w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
            exit(0)
        }
    }
}
