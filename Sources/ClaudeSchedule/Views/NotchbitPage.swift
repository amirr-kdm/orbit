import SwiftUI
import ServiceManagement

/// Notchbit: a tiny Orbit that lives in the notch. Everything about it is switched here.
struct NotchbitPage: View {
    @Environment(AppStore.self) private var store
    @AppStorage("notchbit.enabled") private var enabled = true
    @AppStorage("notchbit.planet") private var planetChoice = ""
    @AppStorage("notchbit.leitner") private var leitner = false
    @AppStorage("notchbit.hover") private var hover = true
    @AppStorage("notchbit.scroll") private var scroll = true
    @AppStorage("notchbit.music.apple") private var appleMusic = true
    @AppStorage("notchbit.music.spotify") private var spotify = true
    @AppStorage("notchbit.haptic") private var haptic = true
    @AppStorage("notchbit.hapticStyle") private var hapticStyle = 1
    @AppStorage("notchbit.planetSize") private var planetSize = 30.0
    @AppStorage("notchbit.speed") private var speed = 1.0
    @AppStorage("notchbit.openDelay") private var openDelay = 0.12
    @AppStorage("notchbit.logo") private var logoID = "headphones"
    @AppStorage("notchbit.logoScales") private var logoScales = "{}"
    @AppStorage("notchbit.music.system") private var otherApps = false
    @AppStorage("notchbit.planetMotion") private var planetMotion = true
    @AppStorage("notchbit.onlineCovers") private var onlineCovers = true
    @AppStorage("notchbit.musicHold") private var musicHold = 30.0
    @AppStorage("notchbit.closeDelay") private var closeDelay = 0.35
    @AppStorage("notchbit.hud") private var hudOn = true
    @AppStorage("notchbit.hudStyle") private var hudStyle = "drop"
    @AppStorage("notchbit.hideOSD") private var hideOSD = true
    @AppStorage("notchbit.hudKeyboard") private var hudKeyboard = true
    @AppStorage("notchbit.hudBattery") private var hudBattery = true
    @AppStorage("notchbit.hudSong") private var hudSong = true
    @AppStorage("notchbit.hudLock") private var hudLock = true
    @AppStorage("notchbit.lockScreen") private var lockScreen = true
    @AppStorage("notchbit.keepRunning") private var keepRunning = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("notchbit.nextUp") private var nextUpOn = true
    @AppStorage("notchbit.nextUpLead") private var nextUpLead = 10
    @AppStorage("notchbit.hudVolumeHex") private var volumeHex = ""
    @AppStorage("notchbit.hudBrightnessHex") private var brightnessHex = ""
    @State private var keysAllowed = SystemHUD.trusted
    private let recheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    @State private var music = NowPlaying.shared
    @State private var planets: [PlanetDef] = []

    private var chosen: String { planetChoice.isEmpty ? (store.avatarPlanet ?? "terra") : planetChoice }

    /// Worked out once when the page opens (in a fixed order), not on every redraw
    private func loadPlanets() {
        let level = store.galaxyProgress().level
        let all = PlanetCatalog.unlocked(at: level) + store.purchases.compactMap { PlanetCatalog.planet($0.planetID) } + PlanetCatalog.notchOnly
        var seen = Set<String>()
        planets = all.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                if enabled {
                    card("Planet", "capsule.tophalf.filled") { EquatableView(content: PlanetGrid(planets: planets, chosen: chosen) { planetChoice = $0 }) }
                    card("What it shows", "slider.horizontal.3") {
                        toggle("Planet moves", "A gentle float and turning moons. Turn off for a still planet if you want to save a little battery.", $planetMotion)
                        toggle("Words to review", "An orange number beside the planet with today's Leitner words.", $leitner)
                    }
                    card("Volume & brightness", "speaker.wave.2.fill") {
                        toggle("Show them in the notch", "When you change the volume or the screen brightness, a level meter appears in the notch for a moment. Turn this off and the notch stays as it was.", $hudOn)
                        if hudOn {
                            Picker("Style", selection: $hudStyle) {
                                Text("Under the notch").tag("drop"); Text("Beside the notch").tag("inline")
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
                            hudColorRow("Volume bar", $volumeHex, defaultHex: "#22C55E")
                            hudColorRow("Brightness bar", $brightnessHex, defaultHex: "#FACC15")
                            toggle("Battery", "A tiny icon and percentage on the right of the notch when you plug the charger in or out, when the battery gets to 20% on battery power, to 80% while charging, and when it is full.", $hudBattery)
                            toggle("Lock sign", "A small lock on the right of the notch when you lock the Mac, and an open lock for a moment when you unlock it. macOS doesn't let apps draw on the lock screen itself.", $hudLock)
                            toggle("Keyboard language", "Shows the layout (EN, FA…) in the notch when you switch the keyboard. For no delay and no macOS box, switch with the shortcut from System Settings → Keyboard → Keyboard Shortcuts → Input Sources (e.g. Option + Space): Orbit takes it over. The 🌐 key is handled deep inside macOS and can't be taken over, so set “Press 🌐 key to” to Do Nothing.", $hudKeyboard)
                            toggle("Replace the macOS panel", "macOS shows its own panel when you press the volume or brightness keys, and it can't be hidden. With this on, Orbit takes those keys over (it needs Accessibility permission) so only the notch shows. Turn it off and the keys work as normal again.", $hideOSD)
                            if hideOSD && !keysAllowed {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                    Text("Allow Orbit under Privacy & Security → Accessibility. Until then macOS shows its panel too.").font(.caption)
                                    Spacer()
                                    Button("Open") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }.controlSize(.small)
                                }
                            }
                        }
                    }
                    card("Always on", "power") {
                        toggle("Keep the notch when I quit", "⌘Q (or Quit in the Dock) closes the windows and the Dock icon, but the notch stays. To really quit, use the button below. Logging out and shutting down are never blocked.", $keepRunning)
                        toggle("Open Orbit when I log in", "So the notch is there as soon as the Mac starts.", Binding(get: { launchAtLogin }, set: { on in
                            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }))
                        Button("Quit Orbit completely") { AppDelegate.reallyQuit = true; NSApp.terminate(nil) }.controlSize(.small)
                    }
                    card("Next up", "clock.badge") {
                        toggle("Remind me before a weekly to-do starts", "A few minutes before an item of your weekly schedule starts, the notch opens with its name and a Start button. It closes by itself.", $nextUpOn)
                        if nextUpOn {
                            Picker("Remind me", selection: $nextUpLead) {
                                ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min before").tag($0) }
                            }
                            .frame(maxWidth: 260)
                        }
                    }
                    card("Lock screen", "lock.fill") {
                        toggle("Show the notch on the lock screen (experimental)", "Uses a private macOS feature, so it may stop working after a macOS update. If anything looks wrong, turn it off. Takes effect the next time Orbit opens.", $lockScreen)
                    }
                    card("Opening", "hand.draw") {
                        Picker("", selection: Binding(get: { hover ? "hover" : "swipe" },
                                                      set: { hover = $0 == "hover"; if $0 == "swipe" { scroll = true } })) {
                            Text("Pointer or swipe").tag("hover")
                            Text("Two-finger swipe only").tag("swipe")
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                        Text(hover ? "The notch opens when the pointer rests on it, or when you swipe down on it with two fingers."
                                   : "The pointer can rest on the notch without opening it. Swipe down on it with two fingers to open it, up to close it.")
                            .font(.caption).foregroundStyle(.secondary)
                        if hover {
                            toggle("Two-finger swipe on the trackpad", "Swipe down on the notch to open it, up to close it.", $scroll)
                        }
                    }
                    card("Feel", "waveform.path") {
                        toggle("Haptic tap when it opens", "A small tap on the trackpad as the notch opens.", $haptic)
                        if haptic {
                            Picker("Strength", selection: $hapticStyle) {
                                Text("Light").tag(0); Text("Medium").tag(1); Text("Strong").tag(2)
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
                            .onChange(of: hapticStyle) { NotchbitController.shared.haptic() }
                        }
                        slider("Animation speed", $speed, 0.5...2, format: { String(format: "%.1f×", $0) }, hint: "Slower or faster opening and closing.")
                        slider("Opens after", $openDelay, 0...0.6, format: { String(format: "%.2f s", $0) }, hint: "How long the pointer rests on the notch before it opens.")
                        slider("Closes after", $closeDelay, 0.1...1.5, format: { String(format: "%.2f s", $0) }, hint: "How long it waits once the pointer has left.")
                        slider("Planet size", $planetSize, 20...36, format: { "\(Int($0)) pt" }, hint: "The planet (or the cover) beside the notch.")
                        Button("Reset to defaults") {
                            haptic = true; hapticStyle = 1; speed = 1; openDelay = 0.12; closeDelay = 0.35; planetSize = 30
                        }.controlSize(.small)
                    }
                    if !NotchLogos.all.isEmpty {
                        card("Music picture", "figure.dance") {
                            Text("Shown right of the notch while music plays. Each picture keeps its own size.").font(.caption).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                let size = Binding<Double>(get: { NotchLogos.scale(logoID, in: logoScales) },
                                                           set: { logoScales = NotchLogos.setScale($0, for: logoID, in: logoScales) })
                                HStack {
                                    Text("Size of \(NotchLogos.logo(logoID)?.name ?? "this picture")")
                                    Spacer()
                                    Text(String(format: "%.1f×", size.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
                                    Button("Reset") { logoScales = NotchLogos.setScale(NotchLogos.defaultScale(logoID), for: logoID, in: logoScales) }.controlSize(.small)
                                }
                                Slider(value: size, in: 0.5...5)
                                Text("It can grow past the notch; set it once and it is remembered.").font(.caption).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                                ForEach(NotchLogos.all) { logo in
                                    Button { logoID = logo.id } label: {
                                        VStack(spacing: 4) {
                                            Group {
                                                if let img = NotchLogos.thumbnail(logo) { Image(nsImage: img).resizable().interpolation(.high) } else { Color.gray }
                                            }
                                            .frame(width: 44, height: 44)
                                            .background(Color.black)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            Text(logo.name).font(.system(size: 9)).lineLimit(1).foregroundStyle(.secondary)
                                        }
                                        .padding(6).frame(maxWidth: .infinity)
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(logoID == logo.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04)))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(logoID == logo.id ? Color.accentColor : .clear, lineWidth: 2))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    card("Music", "music.note") {
                        toggle("Apple Music", "Cover and controls while it plays.", $appleMusic)
                        toggle("Spotify", "Cover and controls while it plays.", $spotify)
                        toggle("Show the next song", "When the song changes, its name appears under the notch for a moment.", $hudSong)
                        toggle("Other apps (experimental)", "Telegram, a browser, YouTube… through macOS Now Playing. It relies on a loophole in macOS, so a macOS update may stop it; Apple Music and Spotify keep working either way. It only waits for changes and does nothing while off.", $otherApps)
                        toggle("Find missing covers online", "Songs streamed in Apple Music have no cover the notch can read. This asks Apple's iTunes search for one and sends only the song title and artist.", $onlineCovers)
                        slider("Keep the song after pausing", $musicHold, 5...120, format: { "\(Int($0)) s" }, hint: "After you pause, the music view stays this long in case you play again. Closing the notch ends it sooner.")
                        Text("The first time, macOS asks if Orbit may control Music or Spotify. Allow it so the buttons work.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Notchbit")
        .onAppear { if planets.isEmpty { loadPlanets() }; keysAllowed = SystemHUD.trusted }
        .onChange(of: hideOSD) { _, on in if on { SystemHUD.shared.syncKeys(prompt: true) } }
        .onReceive(recheck) { _ in keysAllowed = SystemHUD.trusted; SystemHUD.shared.syncKeys() }
    }

    // MARK: Pieces

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black)
                    .overlay(LinearGradient(colors: [Color(hex: "#6366F1").opacity(0.35), Color(hex: "#EC4899").opacity(0.18), .clear],
                                            startPoint: .bottomLeading, endPoint: .topTrailing).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
                // a drawing of the notch
                HStack(spacing: 0) {
                    HStack {
                        if let p = PlanetCatalog.planet(chosen) { PlanetView(planet: p, size: 30) }
                    }.frame(width: 48)
                    Color.clear.frame(width: 130)
                    Text("24:10").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white).frame(width: 66)
                }
                .frame(height: 32)
                .background(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous).fill(Color(white: 0.04)))
                .overlay(alignment: .center) { Capsule().fill(.black).frame(width: 130, height: 32).offset(y: -8) }
                .padding(.top, 0)
            }
            .frame(height: 78)
            .opacity(enabled ? 1 : 0.4)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notchbit").font(.title2.weight(.bold))
                    Text("Your planet, the timer, your tasks and your music — right at the notch.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $enabled).toggleStyle(.switch).labelsHidden()
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.background.secondary))
    }

    /// Auto (the colour follows the level) or a colour you choose
    private func hudColorRow(_ title: String, _ hex: Binding<String>, defaultHex: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if !hex.wrappedValue.isEmpty { ColorChoice(hex: hex) }
            Picker("", selection: Binding(get: { !hex.wrappedValue.isEmpty }, set: { hex.wrappedValue = $0 ? defaultHex : "" })) {
                Text("Changes with level").tag(false); Text("My colour").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        format: @escaping (Double) -> String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toggle(_ title: String, _ detail: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private func card<C: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.background.secondary))
    }
}

/// The planet choices. Only redraws when the choice changes (drawing ~45 planets on every settings change made the page lag).
private struct PlanetGrid: View, Equatable {
    let planets: [PlanetDef]
    let chosen: String
    let pick: (String) -> Void

    static func == (a: PlanetGrid, b: PlanetGrid) -> Bool { a.planets.map(\.id) == b.planets.map(\.id) && a.chosen == b.chosen }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
            ForEach(planets) { p in
                Button { pick(p.id) } label: {
                    VStack(spacing: 4) {
                        PlanetView(planet: p, size: 40).drawingGroup()
                        Text(p.name).font(.system(size: 9)).lineLimit(1).foregroundStyle(.secondary)
                    }
                    .padding(6).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(chosen == p.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(chosen == p.id ? Color.accentColor : .clear, lineWidth: 2))
                }.buttonStyle(.plain)
            }
        }
    }
}
