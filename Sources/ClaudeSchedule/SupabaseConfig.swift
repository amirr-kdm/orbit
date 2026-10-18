import Foundation

/// Supabase project used for the Friends feature.
///
/// The values are read from `Supabase.plist` inside the app bundle (copied there by `build.sh`
/// from `Resources/Supabase.plist`, which is git-ignored). Copy `Resources/Supabase.example.plist`
/// to `Resources/Supabase.plist` and fill in your own project URL and publishable key.
///
/// The publishable key is public by design; access is protected by Row Level Security.
/// Never put the secret (service_role) key in the app.
enum SupabaseConfig {
    private static let values: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return [:] }
        return dict
    }()

    /// False when no Supabase project is configured — the Friends page then explains how to set one up
    static var isConfigured: Bool {
        guard let u = values["URL"], let k = values["PublishableKey"] else { return false }
        return !u.isEmpty && !k.isEmpty && !u.contains("YOUR-PROJECT")
    }

    static var url: URL { URL(string: values["URL"] ?? "") ?? URL(string: "https://invalid.supabase.co")! }
    static var publishableKey: String { values["PublishableKey"] ?? "" }
}
