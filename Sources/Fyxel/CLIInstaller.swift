import AppKit

/// "Install Command Line Tool…": links the fyxelctl bundled in Fyxel.app into ~/.local/bin, so it
/// updates along with the app. No admin rights needed, unlike /usr/local/bin.
@MainActor
enum CLIInstaller {
    static var bundled: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/fyxelctl") }
    static var link: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/fyxelctl") }

    static func run() {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: bundled.path) else {
            return alert("fyxelctl isn't in this build", "Build the app with `make` to include it.")
        }
        // Launched straight from the DMG or Downloads, macOS runs the app from a random
        // read-only copy, and a link to it would break.
        if Bundle.main.bundlePath.contains("/AppTranslocation/") || Bundle.main.bundlePath.hasPrefix("/Volumes/") {
            return alert("Move Fyxel to Applications first",
                         "Fyxel is running from a temporary location. Drag it into Applications, open it from there and try again.")
        }

        let existing = (try? fm.destinationOfSymbolicLink(atPath: link.path)).map { URL(fileURLWithPath: $0) }
        let replacing = fm.fileExists(atPath: link.path) || existing != nil
        if existing?.standardizedFileURL != bundled.standardizedFileURL {
            let a = NSAlert()
            a.messageText = "Install the fyxelctl command?"
            a.informativeText = "This creates \(tilde(link)), linked to the copy inside \(Bundle.main.bundleURL.lastPathComponent)."
                + (replacing ? "\n\nIt replaces the \(tilde(link)) that's already there." : "")
            a.addButton(withTitle: replacing ? "Replace" : "Install")
            a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
            do {
                try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
                if replacing { try fm.removeItem(at: link) }
                try fm.createSymbolicLink(at: link, withDestinationURL: bundled)
            } catch {
                return alert("Couldn't install fyxelctl", error.localizedDescription)
            }
        }
        // Files copied off a downloaded DMG keep the quarantine flag, and opening the app
        // doesn't clear it on the tool, so Gatekeeper would block it in Terminal.
        removexattr(bundled.path, "com.apple.quarantine", 0)

        if onShellPath() {
            alert("fyxelctl is installed", "Try `fyxelctl dal lanhosts` in Terminal.")
        } else {
            alert("fyxelctl is installed, but ~/.local/bin isn't on your PATH",
                  "Add this line to your shell profile (for zsh, ~/.zprofile), then open a new terminal:\n\nexport PATH=\"$HOME/.local/bin:$PATH\"")
        }
    }

    /// Asks the user's login shell where `fyxelctl` resolves, since the app's own PATH
    /// doesn't include anything from their shell profile.
    private static func onShellPath() -> Bool {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-l", "-i", "-c", "command -v fyxelctl"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        // A profile that waits for input shouldn't hang the app.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let found = String(decoding: data, as: UTF8.self).split(separator: "\n").last.map(String.init) ?? ""
        return URL(fileURLWithPath: found).resolvingSymlinksInPath() == bundled.resolvingSymlinksInPath()
    }

    private static func tilde(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
