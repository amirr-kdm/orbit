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
            ("apply-professors", AnyView(ApplyView())),
            ("apply-deadlines", AnyView(ApplyView())),
            ("apply-overview", AnyView(ApplyView())),
            ("apply-detail", AnyView(first.map { AnyView(ApplyDetailView(id: $0) {}) } ?? AnyView(EmptyView()))),
            ("apply-detail-profs", AnyView(first.map { AnyView(ApplyDetailView(id: $0) {}) } ?? AnyView(EmptyView()))),
            ("ielts", AnyView(IELTSView())),
            ("ielts-report", AnyView(IELTSView())),
        ]
        // (this tool runs in its own defaults domain: the app's saved choices are not touched)
        let listPages: [(String, AnyView)] = [("apply-programs-list", AnyView(ApplyView())), ("apply-professors-list", AnyView(ApplyView()))]
        for width in [800, 1400, 1800] {
            for (name, view) in pages + listPages {
                router.applyTab = name.contains("professors") ? 1 : (name.contains("deadlines") ? 2 : (name.contains("overview") ? 3 : 0))
                router.applySection = name == "apply-detail-profs" ? 1 : 0
                router.ieltsTab = name == "ielts-report" ? 1 : 0
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
