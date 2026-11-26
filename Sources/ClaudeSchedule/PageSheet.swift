import SwiftUI

/// Developer tool (CS_RENDER_APPLY): draws pages offscreen at different widths, so layouts can be checked without a window.
@MainActor
enum PageSheet {
    static func render(to dir: String) {
        _ = NSApplication.shared
        let store = AppStore()
        let router = Router()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let first = store.applyPrograms.first?.id
        let pages: [(String, AnyView)] = [
            ("home", AnyView(MissionControlView())),
            ("apply-programs", AnyView(ApplyView())),
            ("apply-professors", AnyView(ApplyView(tab: 1))),
            ("apply-deadlines", AnyView(ApplyView(tab: 2))),
            ("apply-overview", AnyView(ApplyView(tab: 3))),
            ("apply-detail", AnyView(first.map { AnyView(ApplyDetailView(id: $0) {}) } ?? AnyView(EmptyView()))),
            ("apply-detail-profs", AnyView(first.map { AnyView(ApplyDetailView(id: $0, section: 1) {}) } ?? AnyView(EmptyView()))),
            ("ielts", AnyView(IELTSView())),
            ("ielts-report", AnyView(IELTSView(tab: 1))),
        ]
        // (this tool runs in its own defaults domain: the app's saved choices are not touched)
        let listPages: [(String, AnyView)] = [("apply-programs-list", AnyView(ApplyView())), ("apply-professors-list", AnyView(ApplyView(tab: 1)))]
        for width in [800, 1000, 1400] {
            for (name, view) in pages + listPages {
                UserDefaults.standard.set(name.hasSuffix("-list") ? "list" : "grid", forKey: "apply.view")
                UserDefaults.standard.set(name.hasSuffix("-list") ? "list" : "grid", forKey: "apply.profView")
                let content = view.environment(store).environment(router)
                    .frame(width: CGFloat(width), height: 1500, alignment: .top)
                    .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: content)
                let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: CGFloat(width), height: 1500), styleMask: [.borderless], backing: .buffered, defer: false)
                win.appearance = NSAppearance(named: .darkAqua)
                win.contentView = host
                host.frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: 1500)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(width).png")) }
                }
            }
        }
    }
}
