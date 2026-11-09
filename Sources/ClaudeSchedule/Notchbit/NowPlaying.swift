import AppKit
import Observation

/// What Apple Music or Spotify is playing, and the play / next / previous buttons for them.
/// Track changes arrive as system notifications (no permission needed). Controls and the cover use AppleScript,
/// which macOS asks about once ("Orbit wants to control Music").
@MainActor @Observable
final class NowPlaying {
    static let shared = NowPlaying()

    enum Source: String {
        case music = "Music", spotify = "Spotify", system = "System"
        var bundleID: String { self == .music ? "com.apple.Music" : self == .spotify ? "com.spotify.client" : "" }
        var title: String { self == .music ? "Apple Music" : self == .spotify ? "Spotify" : "Other app" }
        var defaultsKey: String { self == .music ? "notchbit.music.apple" : self == .spotify ? "notchbit.music.spotify" : "notchbit.music.system" }
        var allowed: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? (self != .system) }
    }

    private(set) var source: Source?
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var isPlaying = false {
        didSet {
            if isPlaying { holding = false; holdWork?.cancel() }
            else if oldValue { startHold() }
        }
    }
    /// Apple Music's favourite star for the current song
    private(set) var isFavorite = false
    /// Just paused: the music view stays for a while in case the song is started again
    private(set) var holding = false
    @ObservationIgnored private var holdWork: DispatchWorkItem?
    private(set) var artwork: NSImage?

    /// A track is known (playing or paused)
    var hasTrack: Bool { source != nil && !title.isEmpty }
    /// Music is playing right now
    var isActive: Bool { hasTrack && isPlaying }
    /// Playing, or paused only a moment ago: the cover takes the planet's place and the music view stays
    var showing: Bool { hasTrack && (isPlaying || holding) }

    private func startHold() {
        guard hasTrack else { return }
        holding = true
        holdWork?.cancel()
        let seconds = UserDefaults.standard.object(forKey: "notchbit.musicHold") as? Double ?? 30
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.holding = false } }
        holdWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    /// A report from the system-wide Now Playing (any app except Apple Music and Spotify, which have their own)
    func systemUpdate(app: String, title: String, artist: String, album: String, playing: Bool, artwork: Data?) {
        if app == "com.apple.Music" || app == "com.spotify.client" { return }
        if title.isEmpty && !playing { if source == .system { clear() }; return }
        // an app that plays something without a title (a voice message, a recording): show the app's name
        var title = title
        if title.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            title = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        if title.isEmpty { title = "Playing" }
        // a paused report must not take over from a player that is playing
        if !playing && source != .system && hasTrack && isPlaying { return }
        apply(.system, name: title, artist: artist, album: album, playing: playing)
        if let artwork, let img = NSImage(data: artwork) { setArtwork(img, key: trackKey) }
    }

    /// The notch closed: the paused song is let go
    func dropHold() { holdWork?.cancel(); holding = false }

    @ObservationIgnored private var trackKey = ""
    @ObservationIgnored private let queue = DispatchQueue(label: "orbit.notchbit.applescript")
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { n in
            let info = n.userInfo
            MainActor.assumeIsolated { NowPlaying.shared.received(.music, info) }
        }
        dc.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { n in
            let info = n.userInfo
            MainActor.assumeIsolated { NowPlaying.shared.received(.spotify, info) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { n in
            let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { NowPlaying.shared.appQuit(id) }
        }
        // what was already playing before Orbit started
        for s in [Source.music, .spotify] where s.allowed && isRunning(s) { probe(s) }
        NowPlayingBridge.shared.sync()
    }

    private func isRunning(_ s: Source) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: s.bundleID).isEmpty
    }

    private func appQuit(_ id: String?) {
        guard let s = source, s.bundleID == id else { return }
        clear()
    }

    private func clear() {
        source = nil; title = ""; artist = ""; album = ""; isPlaying = false; artwork = nil; trackKey = ""
    }

    private func received(_ s: Source, _ info: [AnyHashable: Any]?) {
        guard s.allowed, let info else { return }
        let state = (info["Player State"] as? String ?? "").lowercased()
        let name = info["Name"] as? String ?? ""
        let playing = state == "playing"
        if state == "stopped" && source == s { clear(); return }
        // the other player was paused / quiet while this one speaks: only follow a player that plays, or the current one
        if source != s && !playing && hasTrack && isPlaying { return }
        apply(s, name: name, artist: info["Artist"] as? String ?? "", album: info["Album"] as? String ?? "", playing: playing)
    }

    private func apply(_ s: Source, name: String, artist: String, album: String, playing: Bool) {
        let key = "\(s.rawValue)|\(name)|\(artist)"
        source = s
        self.isPlaying = playing
        if key != trackKey {
            let hadTrack = !trackKey.isEmpty && isPlaying
            trackKey = key
            if hadTrack, playing { NotchbitModel.shared.showSong(title: name, artist: artist) }
            title = name; self.artist = artist; self.album = album
            artwork = nil
            isFavorite = false
            fetchArtwork(s, key: key)
            if s == .music { fetchFavorite(key: key) }
        }
    }

    // MARK: Cover

    private func fetchArtwork(_ s: Source, key: String) {
        guard isRunning(s) else { return }
        let songTitle = title, songArtist = artist
        queue.async {
            switch s {
            case .music:
                let d = Self.run("tell application \"Music\" to get data of artwork 1 of current track")
                let image = d.flatMap { $0.data.isEmpty ? nil : NSImage(data: $0.data) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        NowPlaying.shared.setArtwork(image, key: key)
                        // streamed songs have no cover the script can reach: ask Apple's public iTunes search instead
                        if image == nil { NowPlaying.shared.fetchOnlineCover(title: songTitle, artist: songArtist, key: key) }
                    }
                }
            case .system:
                break   // the bridge hands over the cover itself
            case .spotify:
                let u = Self.run("tell application \"Spotify\" to get artwork url of current track")?.stringValue
                guard let u, let url = URL(string: u) else { return }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    let image = data.flatMap { NSImage(data: $0) }
                    DispatchQueue.main.async { MainActor.assumeIsolated { NowPlaying.shared.setArtwork(image, key: key) } }
                }.resume()
            }
        }
    }

    private func fetchFavorite(key: String) {
        guard isRunning(.music) else { return }
        queue.async {
            let on = Self.run("tell application \"Music\" to get favorited of current track")?.booleanValue ?? false
            DispatchQueue.main.async { MainActor.assumeIsolated { if key == NowPlaying.shared.trackKey { NowPlaying.shared.isFavorite = on } } }
        }
    }

    /// Star / un-star the song in Apple Music
    func toggleFavorite() {
        guard source == .music else { return }
        isFavorite.toggle()
        let value = isFavorite
        queue.async { _ = Self.run("tell application \"Music\" to set favorited of current track to \(value)") }
    }

    /// Finds a cover through Apple's public iTunes search (sends only the song title and artist). Can be turned off in Notchbit settings.
    private func fetchOnlineCover(title: String, artist: String, key: String) {
        guard UserDefaults.standard.object(forKey: "notchbit.onlineCovers") as? Bool ?? true, !title.isEmpty else { return }
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: "\(artist) \(title)"), URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "limit", value: "1")]
        guard let url = c.url else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (o["results"] as? [[String: Any]])?.first, let u = first["artworkUrl100"] as? String,
                  let big = URL(string: u.replacingOccurrences(of: "100x100", with: "300x300")) else { return }
            URLSession.shared.dataTask(with: big) { d, _, _ in
                let image = d.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async { MainActor.assumeIsolated { NowPlaying.shared.setArtwork(image, key: key) } }
            }.resume()
        }.resume()
    }

    fileprivate func setArtwork(_ image: NSImage?, key: String) {
        if key == trackKey { artwork = image }
    }

    /// Asks a running player what it is doing right now
    private func probe(_ s: Source) {
        let script = """
        tell application "\(s.rawValue)"
            try
                return (player state as text) & "||" & (name of current track) & "||" & (artist of current track) & "||" & (album of current track)
            on error
                return ""
            end try
        end tell
        """
        queue.async {
            guard let out = Self.run(script)?.stringValue, !out.isEmpty else { return }
            let p = out.components(separatedBy: "||")
            guard p.count >= 4 else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NowPlaying.shared.apply(s, name: p[1], artist: p[2], album: p[3], playing: p[0].lowercased().contains("play"))
                }
            }
        }
    }

    // MARK: Buttons

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    private func send(_ command: String) {
        guard let s = source else { return }
        if s == .system {
            if command == "playpause" { isPlaying.toggle() }
            NowPlayingBridge.shared.send(command == "playpause" ? "toggle" : command == "next track" ? "next" : "prev")
            return
        }
        if command == "playpause" { isPlaying.toggle() } // show it at once; the player's own notification confirms
        queue.async { _ = Self.run("tell application \"\(s.rawValue)\" to \(command)") }
    }

    /// Opens the player that is playing
    func openPlayer() {
        guard let s = source, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: s.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    nonisolated private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}


/// Asks macOS for what any app is playing (Telegram, a browser…). Since macOS 15.4 only Apple's own programs may ask, so a small
/// library (helpers/nowplaying_helper.m) runs inside Apple's /usr/bin/perl, which prints one line each time something changes.
/// It waits for system notifications (no polling) and only runs while "Other apps" is on in the Notchbit settings.
/// This leans on a loophole: a macOS update may close it, and then only this feature stops.
@MainActor
final class NowPlayingBridge {
    static let shared = NowPlayingBridge()
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var failures = 0

    private var wanted: Bool { UserDefaults.standard.object(forKey: "notchbit.music.system") as? Bool ?? false }

    /// Start or stop to match the setting
    func sync() {
        if wanted, process == nil { start() } else if !wanted, process != nil { stop() }
    }

    func send(_ command: String) {
        input?.write(Data((command + "\n").utf8))
    }

    private func start() {
        guard let lib = Bundle.main.url(forResource: "nowplaying", withExtension: "dylib")?.path else { return }
        let script = "use DynaLoader; my $l = DynaLoader::dl_load_file($ENV{NP_DYLIB}, 0) or exit 4; " +
                     "my $s = DynaLoader::dl_find_symbol($l, 'nowplaying_boot') or exit 5; " +
                     "my $x = DynaLoader::dl_install_xsub('main::nowplaying_boot', $s); &$x('main');"
        let p = Process()
        #if arch(arm64)
        p.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        p.arguments = ["-arm64", "/usr/bin/perl", "-e", script]
        #else
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", script]
        #endif
        p.environment = ["NP_DYLIB": lib]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async { MainActor.assumeIsolated { NowPlayingBridge.shared.received(data) } }
        }
        p.terminationHandler = { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { NowPlayingBridge.shared.ended() } }
        }
        do {
            try p.run()
            process = p; input = inp.fileHandleForWriting; buffer = Data()
        } catch { process = nil }
    }

    func stop() {
        input = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    private func ended() {
        process = nil; input = nil
        // try again a few times if it was not switched off (a macOS update may have closed the loophole)
        failures += 1
        if wanted, failures <= 3 { DispatchQueue.main.asyncAfter(deadline: .now() + 10) { MainActor.assumeIsolated { NowPlayingBridge.shared.sync() } } }
    }

    private func received(_ data: Data) {
        failures = 0
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 10) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            let art = (o["artwork"] as? String).flatMap { Data(base64Encoded: $0) }
            NowPlaying.shared.systemUpdate(app: o["app"] as? String ?? "", title: o["title"] as? String ?? "",
                                           artist: o["artist"] as? String ?? "", album: o["album"] as? String ?? "",
                                           playing: (o["playing"] as? Bool) ?? ((o["playing"] as? Int ?? 0) != 0), artwork: art)
        }
    }
}
