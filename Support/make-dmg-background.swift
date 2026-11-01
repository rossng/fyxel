// Renders the DMG window background: usage `swift Support/make-dmg-background.swift out-prefix`
// Writes out-prefix.png (1x), out-prefix@2x.png and out-prefix.tiff (both, for Retina).
// Geometry must match Support/dmg-settings.py (window 640x420, icons centred at y=190).
import AppKit

let prefix = CommandLine.arguments.dropFirst().first ?? "dmg-background"
let W: CGFloat = 640, H: CGFloat = 420
let navy = NSColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1)
let blue = NSColor(red: 0.16, green: 0.30, blue: 0.55, alpha: 1)
let cyan = NSColor(red: 0.35, green: 0.70, blue: 0.95, alpha: 1)
let iconY: CGFloat = 190            // from the top, as Finder measures
let appX: CGFloat = 170, appsX: CGFloat = 470

func render(scale: CGFloat) -> Data {
    let px = Int(W * scale), py = Int(H * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    func y(_ top: CGFloat) -> CGFloat { H - top }  // top-left coordinates -> AppKit

    // Pale wash in the icon's colours, with a soft glow behind the icon row.
    NSGradient(colors: [NSColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1), NSColor(red: 0.86, green: 0.91, blue: 0.98, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
    NSGradient(colors: [cyan.withAlphaComponent(0.18), cyan.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: W / 2, y: y(iconY)), radius: 0, toCenter: NSPoint(x: W / 2, y: y(iconY)), radius: 300, options: [])

    // Faint router watermark, bottom right.
    let mark = NSImage.SymbolConfiguration(pointSize: 150, weight: .regular).applying(.init(paletteColors: [blue.withAlphaComponent(0.06)]))
    if let s = NSImage(systemSymbolName: "wifi.router", accessibilityDescription: nil)?.withSymbolConfiguration(mark) {
        s.draw(in: NSRect(x: W - s.size.width + 30, y: -20, width: s.size.width, height: s.size.height))
    }

    // Title and instruction.
    func text(_ s: String, _ font: NSFont, _ color: NSColor, top: CGFloat) {
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (s as NSString).size(withAttributes: a)
        (s as NSString).draw(at: NSPoint(x: (W - size.width) / 2, y: y(top) - size.height), withAttributes: a)
    }
    text("Fyxel", .systemFont(ofSize: 30, weight: .bold), navy, top: 30)
    text("Drag Fyxel into Applications to install", .systemFont(ofSize: 14, weight: .medium), blue, top: 72)

    // Arrow from the app to Applications.
    let arrow = NSBezierPath()
    let x0 = appX + 78, x1 = appsX - 78, ay = y(iconY)
    arrow.move(to: NSPoint(x: x0, y: ay)); arrow.line(to: NSPoint(x: x1 - 6, y: ay))
    arrow.lineWidth = 5; arrow.lineCapStyle = .round
    arrow.setLineDash([2, 11], count: 2, phase: 0)
    blue.withAlphaComponent(0.85).setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: x1 - 16, y: ay + 13)); head.line(to: NSPoint(x: x1, y: ay)); head.line(to: NSPoint(x: x1 - 16, y: ay - 13))
    head.lineWidth = 5; head.lineCapStyle = .round; head.lineJoinStyle = .round
    head.stroke()

    // Gatekeeper hint: this build isn't notarized.
    text("Not notarized. If macOS won't open it: System Settings › Privacy & Security › Open Anyway.",
         .systemFont(ofSize: 11), navy.withAlphaComponent(0.55), top: 372)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(scale: 1).write(to: URL(fileURLWithPath: "\(prefix).png"))
try! render(scale: 2).write(to: URL(fileURLWithPath: "\(prefix)@2x.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
p.arguments = ["-cathidpicheck", "\(prefix).png", "\(prefix)@2x.png", "-out", "\(prefix).tiff"]
try! p.run(); p.waitUntilExit()
print("wrote \(prefix).tiff")
