import AppKit
import Foundation
import UserNotifications

/// Signing in (email + username + password), owner approval, cloud backup of the data file,
/// and the owner's admin tools. The app keeps working offline on the local data.json.
@MainActor @Observable
final class AccountService {
    enum State: Equatable {
        /// This build has no server: the app works fully offline without accounts
        case noServer
        case loading
        case signedOut
        /// An old anonymous profile (from before accounts): turn it into a real account
        case needsUpgrade
        /// Signed up, waiting for the owner to approve
        case pending
        case approved
    }

    struct Profile: Decodable, Equatable {
        let id: UUID
        var name: String
        var username: String?
        var approved: Bool?
        var is_admin: Bool?
    }

    /// One account, as the admin panel sees it
    struct AdminUser: Decodable, Identifiable, Equatable {
        let id: UUID
        let name: String
        let username: String?
        let email: String?
        let approved: Bool
        let is_admin: Bool
        let requested_at: Date?
        let last_backup: Date?
        let last_studied: String?
    }

    private(set) var state: State = .loading
    private(set) var profile: Profile?
    private(set) var email: String?
    var message: String?
    private(set) var busy = false

    // Cloud backup status
    private(set) var lastSync: Date?
    private(set) var syncing = false
    private(set) var syncError: String?

    // Admin
    private(set) var users: [AdminUser] = []
    var pendingCount: Int { users.filter { !$0.approved }.count }
    var isAdmin: Bool { profile?.is_admin == true }

    @ObservationIgnored private let client = SupabaseClient.shared
    @ObservationIgnored private let store: AppStore
    @ObservationIgnored private let friends: FriendsService
    @ObservationIgnored private var uploadTask: Task<Void, Never>?
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var loops: [Task<Void, Never>] = []
    @ObservationIgnored private var notifiedPending: Set<UUID> = []

    init(store: AppStore, friends: FriendsService) {
        self.store = store
        self.friends = friends
        store.onSaved = { [weak self] in self?.localChanged() }
        Task { await bootstrap() }
    }

    // MARK: Start-up

    private func bootstrap() async {
        guard SupabaseConfig.isConfigured else { state = .noServer; return }
        guard let session = await client.currentSession else { state = .signedOut; return }
        email = session.email
        // Approved before on this Mac: open straight away (works offline too)
        if !session.isAnonymous, Self.cachedApproval(session.userID) { state = .approved }
        store.accountReady = syncedAccount == session.userID.uuidString
        await loadProfile()
    }

    /// Reads my profile and decides which screen to show
    private func loadProfile() async {
        guard let session = await client.currentSession else { state = .signedOut; return }
        email = session.email
        do {
            let rows = try await client.select("profiles?id=eq.\(session.userID.uuidString)&select=id,name,username,approved,is_admin",
                                               as: [Profile].self)
            guard let p = rows.first else {
                // The profile is gone (turned down by the owner, or deleted)
                await signOutLocally()
                message = "This account no longer exists. Sign up again, or ask the owner."
                return
            }
            profile = p
            if session.isAnonymous { state = .needsUpgrade; return }
            if p.approved == true {
                Self.setCachedApproval(session.userID, true)
                let wasApproved = state == .approved
                state = .approved
                if !wasApproved || loops.isEmpty { startLoops() }
                // Bring this account's data down first, so nothing from another account is sent under its name
                await syncOnStart()
                store.accountReady = syncedAccount == session.userID.uuidString
                await friends.reload()
                await claimGifts()
            } else {
                Self.setCachedApproval(session.userID, false)
                state = .pending
                startPendingPoll()
            }
        } catch {
            // Offline: keep whatever we had; a pending user stays on the waiting screen
            if state == .loading { state = Self.cachedApproval(session.userID) ? .approved : .pending }
            store.accountReady = syncedAccount == session.userID.uuidString
            if state == .approved && loops.isEmpty { startLoops() }
        }
    }

    // MARK: Sign up / in / out

    func signUp(email: String, username: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        let username = username.trimmingCharacters(in: .whitespaces)
        guard let problem = Self.validate(email: email, username: username, password: password) else {
            await perform {
                guard try await self.usernameFree(username) else { throw Self.fail("That username is taken.") }
                try await self.client.signUp(email: email, password: password)
                guard let uid = await self.client.userID else { return }
                struct NewProfile: Encodable { let id: UUID; let name: String; let username: String }
                _ = try await self.client.insert("profiles", NewProfile(id: uid, name: username, username: username),
                                                 returning: [Profile].self)
                await self.loadProfile()
            }
            return
        }
        message = problem
    }

    func signIn(email: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !email.isEmpty, !password.isEmpty else { message = "Enter your email and password."; return }
        await perform {
            try await self.client.signIn(email: email, password: password)
            await self.loadProfile()
        }
    }

    /// Turn the old anonymous profile on this Mac into a real account (same id: friends and stats stay)
    func upgrade(email: String, username: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        let username = username.trimmingCharacters(in: .whitespaces)
        if let problem = Self.validate(email: email, username: username, password: password) { message = problem; return }
        await perform {
            if username.lowercased() != self.profile?.username?.lowercased() {
                guard try await self.usernameFree(username) else { throw Self.fail("That username is taken.") }
            }
            try await self.client.updateUser(email: email, password: password)
            guard let uid = await self.client.userID else { return }
            try await self.client.update("profiles?id=eq.\(uid.uuidString)", ["username": username, "name": username])
            await self.loadProfile()
        }
    }

    func signOut() async {
        await flushUpload()
        await signOutLocally()
    }

    private func signOutLocally() async {
        stopLoops()
        store.accountReady = false
        await friends.signOut()
        profile = nil
        email = nil
        users = []
        state = .signedOut
    }

    // MARK: Profile changes

    func changeUsername(_ new: String) async -> Bool {
        let new = new.trimmingCharacters(in: .whitespaces)
        guard (3...24).contains(new.count) else { message = "Usernames are 3–24 characters."; return false }
        var ok = false
        await perform {
            guard try await self.usernameFree(new) else { throw Self.fail("That username is taken.") }
            guard let uid = await self.client.userID else { return }
            try await self.client.update("profiles?id=eq.\(uid.uuidString)", ["username": new, "name": new])
            self.profile?.username = new
            self.profile?.name = new
            await self.friends.reload()
            ok = true
        }
        return ok
    }

    /// Changing the password or email needs the current password
    func changePassword(current: String, new: String) async -> Bool {
        guard new.count >= 6 else { message = "Passwords are at least 6 characters."; return false }
        guard let email else { return false }
        var ok = false
        await perform {
            do { try await self.client.signIn(email: email, password: current) } catch { throw Self.fail("Your current password isn't right.") }
            try await self.client.updateUser(password: new)
            ok = true
        }
        return ok
    }

    func changeEmail(_ new: String, password: String) async -> Bool {
        let new = new.trimmingCharacters(in: .whitespaces).lowercased()
        guard new.contains("@"), new.contains(".") else { message = "That doesn't look like an email."; return false }
        guard let email else { return false }
        var ok = false
        await perform {
            do { try await self.client.signIn(email: email, password: password) } catch { throw Self.fail("Your password isn't right.") }
            try await self.client.updateUser(email: new)
            self.email = await self.client.currentSession?.email ?? new
            ok = true
        }
        return ok
    }

    // MARK: Cloud backup

    private var syncKey: String { "sync|" + store.dataFolder.path }
    private var syncedAccount: String? {
        get { UserDefaults.standard.string(forKey: syncKey + "|account") }
        set { UserDefaults.standard.set(newValue, forKey: syncKey + "|account") }
    }
    private var syncedAt: Date? {
        get { UserDefaults.standard.object(forKey: syncKey + "|at") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: syncKey + "|at") }
    }
    private var dirty: Bool {
        get { UserDefaults.standard.bool(forKey: syncKey + "|dirty") }
        set { UserDefaults.standard.set(newValue, forKey: syncKey + "|dirty") }
    }

    private func localChanged() {
        guard !restoring else { return }
        dirty = true
        guard state == .approved else { return }
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await self?.upload()
        }
    }

    /// First sync after signing in: bring the server copy down, or send ours up
    private func syncOnStart() async {
        guard let uid = await client.userID else { return }
        struct Row: Decodable { let updated_at: Date }
        do {
            syncing = true
            defer { syncing = false }
            let rows = try await client.select("user_data?user_id=eq.\(uid.uuidString)&select=updated_at", as: [Row].self)
            let account = uid.uuidString
            guard let server = rows.first?.updated_at else {
                // Nothing on the server yet: this Mac's data becomes the backup —
                // unless it belongs to another account; then this one starts empty (theirs is kept aside)
                if let other = syncedAccount, other != account {
                    restoring = true
                    store.restore(from: Data("{}".utf8), keepingBackupNamed: "data-other-account-\(Int(Date().timeIntervalSince1970)).json")
                    restoring = false
                }
                syncedAccount = account
                await upload()
                return
            }
            let local = (try? FileManager.default.attributesOfItem(atPath: store.dataFolder.appendingPathComponent("data.json").path)[.modificationDate] as? Date) ?? .distantPast
            if syncedAccount != account {
                // New install or a different account on this Mac: use the server copy, keep ours aside
                try await download(uid, backup: "data-before-login-\(Int(Date().timeIntervalSince1970)).json")
            } else if Self.differs(server, syncedAt) {
                if dirty && local > server { await upload() } else { try await download(uid, backup: dirty ? "data-replaced-\(Int(Date().timeIntervalSince1970)).json" : nil) }
            } else if dirty {
                await upload()
            }
            syncedAccount = account
            syncError = nil
        } catch {
            syncError = (error as? SupabaseClient.APIError)?.message ?? "Offline — your changes are saved on this Mac and will sync later."
        }
    }

    private func download(_ uid: UUID, backup: String?) async throws {
        let raw = try await client.raw("GET", "user_data?user_id=eq.\(uid.uuidString)&select=data,updated_at", json: nil)
        guard let arr = try JSONSerialization.jsonObject(with: raw) as? [[String: Any]], let row = arr.first,
              let obj = row["data"] else { return }
        let data = try JSONSerialization.data(withJSONObject: obj)
        restoring = true
        defer { restoring = false }
        guard store.restore(from: data, keepingBackupNamed: backup) else { throw Self.fail("Couldn't read the backup from the server.") }
        if let s = row["updated_at"] as? String, let d = Self.parseDate(s) { syncedAt = d } else { syncedAt = Date() }
        dirty = false
        lastSync = Date()
    }

    /// Send the whole data file up (last change wins)
    func upload() async {
        guard state == .approved, let uid = await client.userID, syncedAccount == uid.uuidString,
              let data = store.exportData() else { return }
        syncing = true
        defer { syncing = false }
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now)
        var body = Data(#"{"user_id":""#.utf8) + Data(uid.uuidString.lowercased().utf8) + Data(#"","updated_at":""#.utf8)
            + Data(stamp.utf8) + Data(#"","device":""#.utf8) + Data((Host.current().localizedName ?? "Mac").replacingOccurrences(of: "\"", with: "").utf8)
            + Data(#"","data":"#.utf8)
        body += data
        body += Data("}".utf8)
        do {
            _ = try await client.raw("POST", "user_data", json: body, prefer: "resolution=merge-duplicates,return=minimal")
            dirty = false
            syncedAt = now
            syncedAccount = uid.uuidString
            lastSync = now
            syncError = nil
        } catch {
            syncError = (error as? SupabaseClient.APIError)?.message ?? "Offline — your changes are saved on this Mac and will sync later."
        }
    }

    /// Another device (the Windows app, another Mac) saved a newer copy: bring it down
    private func pullIfChanged() async {
        guard let uid = await client.userID, syncedAccount == uid.uuidString else { return }
        struct Row: Decodable { let updated_at: Date }
        guard let server = try? await client.select("user_data?user_id=eq.\(uid.uuidString)&select=updated_at", as: [Row].self).first?.updated_at,
              Self.differs(server, syncedAt), !dirty else { return }
        do { try await download(uid, backup: nil); syncError = nil } catch {}
    }

    /// Times saved by different devices: more than a second apart counts as a change
    private static func differs(_ a: Date, _ b: Date?) -> Bool { b.map { abs(a.timeIntervalSince($0)) > 1 } ?? true }

    private func flushUpload() async {
        uploadTask?.cancel()
        if dirty { await upload() }
    }

    // MARK: Admin (owner only — the server refuses everyone else)

    func loadUsers() async {
        guard isAdmin else { return }
        do {
            let data = try await client.rpc("admin_users", [String: String]())
            let list = try SupabaseClient.decoder.decode([AdminUser].self, from: data)
            notifyNewSignUps(list)
            users = list
        } catch {
            message = (error as? SupabaseClient.APIError)?.message ?? error.localizedDescription
        }
    }

    func approve(_ id: UUID) async {
        await perform { _ = try await self.client.rpc("approve_user", ["uid": id.uuidString]) }
        await loadUsers()
    }

    func reject(_ id: UUID) async {
        await perform { _ = try await self.client.rpc("reject_user", ["uid": id.uuidString]) }
        await loadUsers()
    }

    /// Give (or take back, if negative) rockets. The person's app adds them on its next check.
    func giftRockets(_ id: UUID, amount: Int) async -> Bool {
        var ok = false
        await perform {
            struct Body: Encodable { let uid: String; let amount: Int }
            _ = try await self.client.rpc("admin_gift_rockets", Body(uid: id.uuidString, amount: amount))
            ok = true
        }
        if ok, id == (await client.userID) { await claimGifts() }
        return ok
    }

    /// Add rocket gifts from the owner that this account hasn't counted yet
    func claimGifts() async {
        guard state == .approved, !restoring, store.accountReady else { return }
        struct Gift: Decodable { let id: UUID; let amount: Int; let reason: String? }
        guard let gifts = try? await client.select("rocket_gifts?select=id,amount,reason", as: [Gift].self) else { return }
        let new = gifts.filter { !store.claimedGifts.contains($0.id.uuidString) }
        guard !new.isEmpty else { return }
        store.claimedGifts += new.map(\.id.uuidString)
        store.rocketGrant += new.reduce(0) { $0 + $1.amount }
        // Tell about rockets received (paying a fee is your own action, so it stays quiet)
        for g in new where g.amount > 0 {
            let text = g.reason.map { "\($0) (+\(g.amount) 🚀)" } ?? "You got \(g.amount) rockets from the Orbit admin! 🚀"
            giftNotice = text
            Notifier.post(id: "gift-\(g.id)", title: g.reason == nil ? "You got \(g.amount) 🚀 rockets!" : "+\(g.amount) 🚀 rockets",
                          body: g.reason ?? "A gift from the Orbit admin. Spend them in the Store.")
        }
    }

    /// Rockets just received as a gift (shown as a banner until dismissed)
    var giftNotice: String?

    /// Sets a new temporary password and returns it, so the owner can pass it on
    func resetPassword(_ id: UUID) async -> String? {
        let temp = "Orbit-" + String(Int.random(in: 100_000...999_999))
        var ok = false
        await perform {
            struct Body: Encodable { let uid: String; let new_password: String }
            _ = try await self.client.rpc("admin_reset_password", Body(uid: id.uuidString, new_password: temp))
            ok = true
        }
        return ok ? temp : nil
    }

    private func notifyNewSignUps(_ list: [AdminUser]) {
        let pending = list.filter { !$0.approved }
        let fresh = pending.filter { !notifiedPending.contains($0.id) }
        let firstLoad = notifiedPending.isEmpty && users.isEmpty
        notifiedPending.formUnion(pending.map(\.id))
        NSApp.dockTile.badgeLabel = pending.isEmpty ? nil : "\(pending.count)"
        guard !fresh.isEmpty, !(firstLoad && UserDefaults.standard.bool(forKey: "notifiedOnce")) else {
            UserDefaults.standard.set(true, forKey: "notifiedOnce")
            return
        }
        UserDefaults.standard.set(true, forKey: "notifiedOnce")
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            for u in fresh {
                let c = UNMutableNotificationContent()
                c.title = "New Orbit sign-up"
                c.body = "\(u.username ?? u.name) (\(u.email ?? "no email")) is waiting for your approval."
                c.sound = .default
                center.add(UNNotificationRequest(identifier: "signup-\(u.id)", content: c, trigger: nil))
            }
        }
    }

    // MARK: Background loops

    private func startLoops() {
        stopLoops()
        // Keep the backup fresh and retry after being offline
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, self.state == .approved else { continue }
                if !self.store.accountReady { await self.syncOnStart(); self.store.accountReady = self.syncedAccount == (await self.client.userID)?.uuidString }
                else if self.dirty { await self.upload() } else { await self.pullIfChanged() }
                await self.claimGifts()
            }
        })
        // Owner: watch for new sign-ups
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isAdmin { await self.loadUsers() }
                try? await Task.sleep(for: .seconds(45))
            }
        })
    }

    /// Waiting for approval: check every 30 seconds so the app opens as soon as the owner says yes
    private func startPendingPoll() {
        stopLoops()
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.state == .pending else { return }
                await self.loadProfile()
            }
        })
    }

    private func stopLoops() {
        loops.forEach { $0.cancel() }
        loops = []
    }

    func refreshStatus() async { await loadProfile() }

    // MARK: Helpers

    private func usernameFree(_ name: String) async throws -> Bool {
        let data = try await client.rpcAnon("username_available", ["wanted": name])
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? true
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await work()
        } catch let e as SupabaseClient.APIError {
            message = Self.friendly(e.message)
        } catch let e as Failure {
            message = e.text
        } catch {
            message = (error as? URLError) != nil ? "Can't reach the server. Check your internet or VPN." : error.localizedDescription
        }
    }

    private struct Failure: Error { let text: String }
    private static func fail(_ text: String) -> Failure { Failure(text: text) }

    private static func friendly(_ m: String) -> String {
        let l = m.lowercased()
        if l.contains("invalid login") { return "Wrong email or password." }
        if l.contains("already registered") || l.contains("already been registered") { return "There's already an account with this email. Log in instead." }
        if l.contains("profiles_username_key") || l.contains("duplicate key") { return "That username is taken." }
        if l.contains("password should be") { return "Passwords are at least 6 characters." }
        return m
    }

    static func validate(email: String, username: String, password: String) -> String? {
        if !email.contains("@") || !email.contains(".") { return "Enter a valid email." }
        if !(3...24).contains(username.count) { return "Usernames are 3–24 characters." }
        if username.contains(where: { $0.isWhitespace }) { return "Usernames can't have spaces." }
        if password.count < 6 { return "Passwords are at least 6 characters." }
        return nil
    }

    private static func cachedApproval(_ id: UUID) -> Bool { UserDefaults.standard.bool(forKey: "approved|\(id.uuidString)") }
    private static func setCachedApproval(_ id: UUID, _ v: Bool) { UserDefaults.standard.set(v, forKey: "approved|\(id.uuidString)") }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
