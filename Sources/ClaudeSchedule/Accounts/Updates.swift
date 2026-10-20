import AppKit
import UserNotifications

/// Shows a macOS notification (asks for permission the first time)
enum Notifier {
    static func post(id: String, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
        }
    }
}

/// Checks GitHub for a newer Orbit release and tells the user once per version
@Observable @MainActor
final class UpdateChecker {
    static let releasesPage = URL(string: "https://github.com/amirr-kdm/orbit/releases/latest")!
    private static let api = URL(string: "https://api.github.com/repos/amirr-kdm/orbit/releases/latest")!

    /// The newer version available, e.g. "1.4.0" (nil = up to date)
    private(set) var available: String?
    var dismissed = false

    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        Task {
            while true {
                await check()
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func check() async {
        struct Release: Decodable { let tag_name: String }
        guard let (data, _) = try? await URLSession.shared.data(from: Self.api),
              let tag = try? JSONDecoder().decode(Release.self, from: data).tag_name else { return }
        let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard Self.isNewer(latest, than: current) else { return }
        available = latest
        let key = "notifiedVersion"
        if UserDefaults.standard.string(forKey: key) != latest {
            UserDefaults.standard.set(latest, forKey: key)
            Notifier.post(id: "update-\(latest)", title: "Orbit \(latest) is out ✨",
                          body: "Download the new version from GitHub. Your data stays as it is.")
        }
    }

    func openDownload() { NSWorkspace.shared.open(Self.releasesPage) }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
