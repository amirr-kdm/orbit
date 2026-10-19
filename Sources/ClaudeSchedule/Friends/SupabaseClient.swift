import Foundation
import Security

/// Minimal Supabase client (Auth + PostgREST) over URLSession — no SDK needed.
/// The signed-in session is kept in the Keychain.
actor SupabaseClient {
    /// One client for the whole app (accounts, friends and cloud backup share the sign-in)
    static let shared = SupabaseClient()

    struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: UUID
        /// nil for the old anonymous profiles (no email / password yet)
        var email: String?
        var isAnonymous: Bool { email == nil }
    }

    struct APIError: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    private(set) var session: Session?
    private let base = SupabaseConfig.url
    private let key = SupabaseConfig.publishableKey

    init() {
        session = Keychain.load()
    }

    var userID: UUID? { session?.userID }
    var currentSession: Session? { session }

    // MARK: Auth

    /// Creates an anonymous account (no email or password)
    func signInAnonymously() async throws {
        let data = try await send("POST", "/auth/v1/signup", body: [String: String](), auth: false)
        try storeSession(from: data)
    }

    /// Create an account with email + password ("Confirm email" must be off on the server)
    func signUp(email: String, password: String) async throws {
        let data = try await send("POST", "/auth/v1/signup", body: ["email": email, "password": password], auth: false)
        guard (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["access_token"] != nil else {
            throw APIError(status: 400, message: "The server asks new accounts to confirm their email. Turn off “Confirm email” in Supabase → Authentication → Email.")
        }
        try storeSession(from: data)
    }

    func signIn(email: String, password: String) async throws {
        let data = try await send("POST", "/auth/v1/token?grant_type=password",
                                  body: ["email": email, "password": password], auth: false)
        try storeSession(from: data)
    }

    /// Change the signed-in user's email and/or password. For an old anonymous profile this turns it into a
    /// real account and keeps the same id, so friends, groups and stats stay.
    func updateUser(email: String? = nil, password: String? = nil) async throws {
        try await refreshIfNeeded()
        var body: [String: String] = [:]
        if let email { body["email"] = email }
        if let password { body["password"] = password }
        _ = try await send("PUT", "/auth/v1/user", body: body)
        // Fetch a fresh token so the session carries the new email
        guard let s = session else { return }
        let data = try await send("POST", "/auth/v1/token?grant_type=refresh_token",
                                  body: ["refresh_token": s.refreshToken], auth: false)
        try storeSession(from: data)
        if let email, session?.email == nil { session?.email = email; if let s = session { Keychain.save(s) } }
    }

    func signOut() {
        session = nil
        Keychain.delete()
    }

    private func refreshIfNeeded() async throws {
        guard let s = session else { throw APIError(status: 401, message: "Not signed in") }
        guard s.expiresAt.timeIntervalSinceNow < 60 else { return }
        let data = try await send("POST", "/auth/v1/token?grant_type=refresh_token",
                                  body: ["refresh_token": s.refreshToken], auth: false)
        try storeSession(from: data)
    }

    private func storeSession(from data: Data) throws {
        struct AuthResponse: Decodable {
            struct User: Decodable { let id: UUID; let email: String? }
            let access_token: String
            let refresh_token: String
            let expires_in: Double
            let user: User
        }
        let r = try JSONDecoder().decode(AuthResponse.self, from: data)
        let s = Session(accessToken: r.access_token, refreshToken: r.refresh_token,
                        expiresAt: Date().addingTimeInterval(r.expires_in), userID: r.user.id,
                        email: (r.user.email?.isEmpty ?? true) ? nil : r.user.email)
        session = s
        Keychain.save(s)
    }

    // MARK: Database (PostgREST)

    func select<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        try await refreshIfNeeded()
        let data = try await send("GET", "/rest/v1/\(path)", body: Optional<String>.none)
        return try Self.decoder.decode(T.self, from: data)
    }

    func insert<B: Encodable, T: Decodable>(_ table: String, _ body: B, returning: T.Type) async throws -> T {
        try await refreshIfNeeded()
        let data = try await send("POST", "/rest/v1/\(table)", body: body, prefer: "return=representation")
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Insert or update on the primary key
    func upsert<B: Encodable>(_ table: String, _ body: B) async throws {
        try await refreshIfNeeded()
        _ = try await send("POST", "/rest/v1/\(table)", body: body, prefer: "resolution=merge-duplicates,return=minimal")
    }

    func update<B: Encodable>(_ path: String, _ body: B) async throws {
        try await refreshIfNeeded()
        _ = try await send("PATCH", "/rest/v1/\(path)", body: body, prefer: "return=minimal")
    }

    func delete(_ path: String) async throws {
        try await refreshIfNeeded()
        _ = try await send("DELETE", "/rest/v1/\(path)", body: Optional<String>.none, prefer: "return=minimal")
    }

    /// Raw request with a prebuilt JSON body (used for the cloud backup, which embeds the data file as-is)
    func raw(_ method: String, _ path: String, json: Data?, prefer: String? = nil) async throws -> Data {
        try await refreshIfNeeded()
        return try await send(method, "/rest/v1/\(path)", body: Optional<String>.none, prefer: prefer, rawBody: json)
    }

    /// An RPC that works signed out too (e.g. checking if a username is free)
    func rpcAnon<B: Encodable>(_ name: String, _ body: B) async throws -> Data {
        if session != nil { try? await refreshIfNeeded() }
        return try await send("POST", "/rest/v1/rpc/\(name)", body: body, auth: session != nil)
    }

    func rpc<B: Encodable>(_ name: String, _ body: B) async throws -> Data {
        try await refreshIfNeeded()
        return try await send("POST", "/rest/v1/rpc/\(name)", body: body)
    }

    // MARK: HTTP

    private func send<B: Encodable>(_ method: String, _ path: String, body: B?, auth: Bool = true,
                                    prefer: String? = nil, rawBody: Data? = nil) async throws -> Data {
        guard let url = URL(string: base.absoluteString + path) else { throw APIError(status: 0, message: "Bad URL") }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let token = session?.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { req.httpBody = try Self.encoder.encode(body) }
        if let rawBody { req.httpBody = rawBody }

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, message: Self.errorMessage(data) ?? "Server error (\(status))")
        }
        return data
    }

    private static func errorMessage(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        return (obj["message"] ?? obj["msg"] ?? obj["error_description"] ?? obj["error"]) as? String
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: s) ?? ISO8601DateFormatter().date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()
}

/// Stores the Supabase session in the macOS Keychain
private enum Keychain {
    static let service = "com.amir.claudeschedule.supabase"
    /// A separate test data folder (CS_DATA_DIR) gets its own sign-in
    static let account = ProcessInfo.processInfo.environment["CS_DATA_DIR"].map { "session:\($0)" } ?? "session"

    static func save(_ session: SupabaseClient.Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> SupabaseClient.Session? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SupabaseClient.Session.self, from: data)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
