import AppKit

/// The little animated pictures that can sit right of the notch while music plays.
/// Their frames are copied into the app (Resources/art-local/notch_logo_<id>_<n>.png, listed in notch_logos.json),
/// so they keep working if the original GIFs are deleted from the Desktop.
enum NotchLogos {
    struct Logo: Identifiable, Hashable {
        let id: String
        let name: String
        let frameCount: Int
        let duration: Double
    }

    static let all: [Logo] = {
        guard let url = Bundle.main.url(forResource: "notch_logos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return raw.compactMap { d in
            guard let id = d["id"] as? String, let name = d["name"] as? String,
                  let n = d["frames"] as? Int, let dur = d["duration"] as? Double else { return nil }
            return Logo(id: id, name: name, frameCount: n, duration: dur)
        }
    }()

    /// Sizes the user set, one for each picture, saved together as JSON in one setting
    static let scalesKey = "notchbit.logoScales"
    /// Wide or small pictures start bigger
    static func defaultScale(_ id: String) -> Double {
        switch id { case "band-trio": 2.6; case "boombox": 1.8; case "keyboard-cats": 1.3; case "guitarist": 1.2; default: 1 }
    }
    static func scales(_ json: String?) -> [String: Double] {
        guard let json, let d = json.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Double] else { return [:] }
        return o
    }
    static func scale(_ id: String, in json: String? = UserDefaults.standard.string(forKey: scalesKey)) -> Double {
        scales(json)[id] ?? defaultScale(id)
    }
    static func setScale(_ v: Double, for id: String, in json: String) -> String {
        var d = scales(json); d[id] = (v * 100).rounded() / 100
        return (try? JSONSerialization.data(withJSONObject: d)).flatMap { String(data: $0, encoding: .utf8) } ?? json
    }

    static func logo(_ id: String) -> Logo? { all.first { $0.id == id } ?? all.first }

    /// Only the logo in use is kept in memory
    private static var cache: (id: String, frames: [NSImage])?

    static func frames(of logo: Logo) -> [NSImage] {
        if let c = cache, c.id == logo.id { return c.frames }
        var out: [NSImage] = []
        for k in 0..<logo.frameCount {
            if let url = Bundle.main.url(forResource: "notch_logo_\(logo.id)_\(k)", withExtension: "png"), let img = NSImage(contentsOf: url) { out.append(img) }
        }
        cache = (logo.id, out)
        return out
    }

    /// The first picture, for the choice grid
    static func thumbnail(_ logo: Logo) -> NSImage? {
        Bundle.main.url(forResource: "notch_logo_\(logo.id)_0", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }
}
