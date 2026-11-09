import Foundation

// Shared by the Mac app and the iPhone app (this file is compiled into both).
// Syncs tasks, categories, study sessions, countdowns and the Pomodoro settings through a private code.
// Each side keeps what it had at the last sync, so the two can be merged safely (a change on one side wins over no change on the other).

enum SyncDoc {
    static let collections = ["tasks", "categories", "sessions", "countdowns", "schedule", "timeSlots", "scheduleDone", "scheduleMoved", "scheduleSkipped",
                              "leitnerBoxes", "leitnerCards", "leitnerLog"]
    static let scalars = ["pomodoroMinutes", "breakMinutes", "dailyGoalMinutes", "evenWeekAnchor", "leitnerDailyGoal"]

    private static func canonical(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(["v": o]),
              let d = try? JSONSerialization.data(withJSONObject: ["v": o], options: [.sortedKeys]) else { return "\(o)" }
        return String(decoding: d, as: UTF8.self)
    }

    private static func byID(_ list: Any?) -> (order: [String], items: [String: [String: Any]]) {
        var order: [String] = [], items: [String: [String: Any]] = [:]
        for case let o as [String: Any] in (list as? [Any]) ?? [] {
            guard let id = o["id"] as? String else { continue }
            if items[id] == nil { order.append(id) }
            items[id] = o
        }
        return (order, items)
    }

    /// Three-way merge of two copies of the shared data
    static func merge(base: [String: Any], local: [String: Any], remote: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for name in collections {
            let b = byID(base[name]).items, l = byID(local[name]), r = byID(remote[name])
            var result: [[String: Any]] = []
            var seen = Set<String>()
            for id in l.order + r.order where seen.insert(id).inserted {
                let li = l.items[id], ri = r.items[id], bi = b[id]
                let ls = li.map(canonical), rs = ri.map(canonical), bs = bi.map(canonical)
                let chosen: [String: Any]?
                if ls == rs { chosen = li }
                else if ls == bs { chosen = ri }          // only the other side changed (or deleted) it
                else if rs == bs { chosen = li }          // only this side changed (or deleted) it
                else { chosen = li ?? ri }                // both changed: this side wins
                if let chosen { result.append(chosen) }
            }
            out[name] = result
        }
        for k in scalars {
            let lv = local[k], rv = remote[k], bv = base[k]
            let ls = lv.map(canonical), rs = rv.map(canonical), bs = bv.map(canonical)
            if ls == rs { out[k] = lv ?? rv }
            else if bv == nil, let rv { out[k] = rv }   // the first sync: a setting that already exists elsewhere wins over a fresh device's default
            else if ls == bs { out[k] = rv }
            else { out[k] = lv ?? rv }
        }
        return out
    }

    static func same(_ a: [String: Any], _ b: [String: Any]) -> Bool { canonical(a) == canonical(b) }
}

struct SyncError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Talks to the two Supabase functions (see ios/sync.sql)
struct SyncClient {
    func get(code: String) async throws -> [String: Any]? {
        let data = try await call("sync_get", ["p_code": code])
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = rows.first else { return nil }
        return first["data"] as? [String: Any]
    }

    func put(code: String, doc: [String: Any]) async throws {
        _ = try await call("sync_put", ["p_code": code, "p_data": doc])
    }

    private func call(_ fn: String, _ body: [String: Any]) async throws -> Data {
        guard SupabaseConfig.isConfigured, let url = URL(string: SupabaseConfig.url.absoluteString + "/rest/v1/rpc/\(fn)") else {
            throw SyncError(message: "Supabase is not set up in this app")
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch let e as URLError { throw SyncError(message: e.code == .notConnectedToInternet ? "No internet" : "Network problem (\(e.code.rawValue))") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let text = String(decoding: data, as: UTF8.self)
            if text.contains("PGRST202") || text.contains("Could not find the function") {
                throw SyncError(message: "The sync table is not set up yet (run ios/sync.sql in Supabase)")
            }
            throw SyncError(message: "Server error \(status)")
        }
        return data
    }
}

/// One sync round: pull, merge, apply, push. The two sides give it their data through closures.
@MainActor
final class SyncEngine {
    var export: () -> [String: Any] = { [:] }
    var apply: ([String: Any]) -> Void = { _ in }
    var onStatus: (String, Bool) -> Void = { _, _ in }

    private var running = false
    private var again = false
    private var pending: DispatchWorkItem?
    private let baseKey = "sync.base"

    var code: String { UserDefaults.standard.string(forKey: "sync.code") ?? "" }
    var enabled: Bool { UserDefaults.standard.bool(forKey: "sync.enabled") && code.count >= 16 }

    /// Something changed here: sync in a few seconds
    func changed() {
        guard enabled else { return }
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in Task { @MainActor in await self?.syncNow() } }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    func syncNow() async {
        guard enabled else { return }
        if running { again = true; return }
        running = true
        defer { running = false }
        repeat {
            again = false
            do {
                let local = export()
                let remote = try await SyncClient().get(code: code) ?? [:]
                let base = (UserDefaults.standard.string(forKey: baseKey)?.data(using: .utf8))
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                let merged = SyncDoc.merge(base: base, local: local, remote: remote)
                if !SyncDoc.same(merged, local) { apply(merged) }
                if !SyncDoc.same(merged, remote) { try await SyncClient().put(code: code, doc: merged) }
                if let d = try? JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys]) {
                    UserDefaults.standard.set(String(decoding: d, as: UTF8.self), forKey: baseKey)
                }
                onStatus("Synced " + Date.now.formatted(date: .omitted, time: .shortened), true)
            } catch {
                onStatus((error as? SyncError)?.message ?? error.localizedDescription, false)
            }
        } while again
    }

    /// A readable code with no confusing letters
    static func newCode() -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return (0..<5).map { _ in String((0..<5).map { _ in letters.randomElement()! }) }.joined(separator: "-")
    }
}
