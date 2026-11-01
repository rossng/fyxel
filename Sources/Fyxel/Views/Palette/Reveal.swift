import FyxelCore
import SwiftUI

/// Scroll targets for `NavIntent.reveal`. Spec panels use `spec(_:)`; hand-written panels
/// use the constants, which the palette index (`PaletteIndex.panels`) also lists.
enum Anchor {
    static func spec(_ s: ObjectSpec) -> String { "spec:\(s.id)" }

    static let throughput = "overview.throughput", internet = "overview.internet", system = "overview.system"
    static let ethernet = "overview.ethernet", wifiSummary = "overview.wifi", lanSummary = "overview.lan"
    static let routes = "overview.routes"
    static let device = "maintenance.device", config = "maintenance.config", firmware = "maintenance.firmware"
    static let password = "maintenance.password"
    static let netTools = "diagnostics.tools", natSessions = "diagnostics.nat", arp = "diagnostics.arp"
    static let multicast = "diagnostics.multicast"
}

/// A vertical ScrollView that scrolls to the anchor of a pending `.reveal` request, then
/// clears the request once the highlight has had time to show.
struct RevealScrollView<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content }
                .task(id: model.request?.id) {
                    guard let r = model.request, case .reveal(let anchor, _) = r.intent else { return }
                    withAnimation { proxy.scrollTo(anchor, anchor: .top) }
                    // Panels above may still be loading and change height; scroll again once they settle.
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation { proxy.scrollTo(anchor, anchor: .top) }
                    try? await Task.sleep(for: .seconds(1.5))
                    if model.request?.id == r.id { model.request = nil }
                }
        }
    }
}

extension View {
    /// Makes this panel a scroll target for `NavIntent.reveal(id)` and outlines it while revealed.
    func revealAnchor(_ id: String) -> some View { modifier(RevealAnchor(id: id)) }
}

struct RevealAnchor: ViewModifier {
    @Environment(AppModel.self) private var model
    var id: String

    func body(content: Content) -> some View {
        let on = model.request?.intent.revealedAnchor == id
        content
            .id(id)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .opacity(on ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: on ? 0.2 : 0.6), value: on)
    }
}

extension NavIntent {
    var revealedAnchor: String? {
        if case .reveal(let a, _) = self { return a }
        return nil
    }

    func revealedField(in anchor: String) -> String? {
        if case .reveal(let a, let f) = self, a == anchor { return f }
        return nil
    }
}

private struct RevealedFieldKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// Key of the spec field the palette jumped to, if it's in this section.
    var revealedField: String? {
        get { self[RevealedFieldKey.self] }
        set { self[RevealedFieldKey.self] = newValue }
    }
}
