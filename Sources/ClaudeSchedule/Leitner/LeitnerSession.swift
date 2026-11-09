import SwiftUI
import AVFoundation

/// Colours and little helpers shared by the Leitner screens
enum LeitnerLook {
    /// Section 1 … 5 and "learned": warm when a word is new, cool and calm as it settles
    static func color(_ section: Int) -> Color {
        switch section {
        case 1: Color(hex: "#F43F5E")
        case 2: Color(hex: "#F97316")
        case 3: Color(hex: "#EAB308")
        case 4: Color(hex: "#14B8A6")
        case 5: Color(hex: "#3B82F6")
        default: Color(hex: "#22C55E")
        }
    }

    static let boxGradients: [[Color]] = [
        [Color(hex: "#6366F1"), Color(hex: "#A855F7")], [Color(hex: "#EC4899"), Color(hex: "#F97316")],
        [Color(hex: "#06B6D4"), Color(hex: "#3B82F6")], [Color(hex: "#10B981"), Color(hex: "#14B8A6")],
        [Color(hex: "#F59E0B"), Color(hex: "#EF4444")], [Color(hex: "#8B5CF6"), Color(hex: "#EC4899")],
    ]

    /// Every box keeps the same colours (picked from its name)
    static func gradient(_ name: String) -> LinearGradient {
        let h = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return LinearGradient(colors: boxGradients[h % boxGradients.count], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// "verb · فعل": colour and Persian name of a part of speech
    static func posInfo(_ pos: String) -> (label: String, color: Color)? {
        switch pos.lowercased() {
        case "noun": ("noun", Color(hex: "#3B82F6"))
        case "verb": ("verb", Color(hex: "#F43F5E"))
        case "adjective": ("adjective", Color(hex: "#F59E0B"))
        case "adverb": ("adverb", Color(hex: "#14B8A6"))
        case "preposition": ("preposition", Color(hex: "#8B5CF6"))
        case "conjunction": ("conjunction", Color(hex: "#EC4899"))
        case "pronoun": ("pronoun", Color(hex: "#06B6D4"))
        case "determiner": ("determiner", Color(hex: "#84CC16"))
        case "exclamation": ("exclamation", Color(hex: "#F97316"))
        case "": nil
        default: (pos, Color.gray)
        }
    }

    static func intervalText(_ section: Int) -> String {
        guard section >= 1, section <= LeitnerStore.intervals.count else { return "learned" }
        let d = LeitnerStore.intervals[section - 1]
        return d == 1 ? "every day" : "every \(d) days"
    }
}

/// One round of reviewing: a queue of due words, from one box or from all of them
@MainActor @Observable
final class LeitnerSession {
    struct Item: Hashable { let box: String; let id: UUID }

    private(set) var queue: [Item] = []
    private(set) var initial = 0
    private(set) var answered = 0
    var revealed = false
    private let store = LeitnerStore.shared

    var current: (box: String, card: LeitnerCard)? {
        guard let it = queue.first, let c = store.box(it.box)?.cards.first(where: { $0.id == it.id }) else { return nil }
        return (it.box, c)
    }

    /// Words due now (the most overdue first); `more` = the next 10 words that are not due yet
    func start(boxes: [String]? = nil, more: Bool = false, count: Int = 10) {
        var found: [(LeitnerCard, String)] = []
        for n in boxes ?? store.boxes.map(\.name) {
            let list = more ? store.ahead(in: n) : store.due(in: n)
            found += list.map { ($0, n) }
        }
        found.sort { ($0.0.due, $0.0.box, $0.0.word) < ($1.0.due, $1.0.box, $1.0.word) }
        if more { found = Array(found.prefix(count)) }
        queue = found.map { Item(box: $0.1, id: $0.0.id) }
        initial = queue.count
        answered = 0
        revealed = false
    }

    func answer(_ knew: Bool) {
        guard let cur = current else { if !queue.isEmpty { queue.removeFirst() }; return }
        store.review(cur.card.id, in: cur.box, knew: knew)
        answered += 1
        revealed = false
        queue.removeFirst()
    }
}

/// Reads a word aloud with the Mac's own English voice (offline)
@MainActor
enum LeitnerSpeech {
    private static let synth = AVSpeechSynthesizer()

    /// The best English voice installed: Premium, then Enhanced, then the normal ones (so a downloaded voice is used automatically)
    /// English voices installed on this Mac, best quality first
    private static var voiceCache: [AVSpeechSynthesisVoice]?
    static func englishVoices() -> [AVSpeechSynthesisVoice] {
        if let c = voiceCache { return c }
        let list = loadEnglishVoices()
        voiceCache = list
        return list
    }

    private static func loadEnglishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") && !$0.identifier.contains("eloquence") }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    static func label(_ v: AVSpeechSynthesisVoice) -> String {
        let q = v.quality == .premium ? " · Premium" : v.quality == .enhanced ? " · Enhanced" : ""
        return "\(v.name) (\(v.language))\(q)"
    }

    /// The voice picked in Settings, or the best English one installed
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: "leitner.voice"), !id.isEmpty, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return autoVoice()
    }

    private static func autoVoice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" && !$0.identifier.contains("eloquence") }
        return all.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    static var isSpeaking: Bool { synth.isSpeaking }
    static func stop() { synth.stopSpeaking(at: .immediate) }

    static func say(_ text: String, rate: Float = 0.42) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = bestVoice()
        u.rate = rate
        synth.speak(u)
    }
}

/// A small tag with the kind of word
struct LeitnerPOSChip: View {
    let pos: String
    var body: some View {
        if let i = LeitnerLook.posInfo(pos) {
            Text(i.label).font(.caption2.weight(.bold)).foregroundStyle(i.color)
                .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(i.color.opacity(0.16)))
        }
    }
}

/// The flip card: the word on the front, the meaning on the back
struct LeitnerFlashCard: View {
    var pos = ""
    let word: String
    let meaning: String
    let section: Int
    let late: Int
    let revealed: Bool
    var compact = false

    var body: some View {
        LeitnerFlip(angle: revealed ? 180 : 0, pos: pos.isEmpty ? (LeitnerDictionary.partOfSpeech(word) ?? "") : pos, word: word, meaning: meaning, section: section, late: late, compact: compact)
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: revealed)
    }
}

/// The card at a given angle: each side shows only when it faces us, so the text is never seen mirrored mid-flip
private struct LeitnerFlip: View, Animatable {
    var angle: Double
    let pos: String
    let word: String
    let meaning: String
    let section: Int
    let late: Int
    let compact: Bool

    var animatableData: Double { get { angle } set { angle = newValue } }

    var body: some View {
        ZStack {
            face(back: false).opacity(angle < 90 ? 1 : 0)
            face(back: true).opacity(angle >= 90 ? 1 : 0).rotation3DEffect(.degrees(180), axis: (0, 1, 0))
        }
        .rotation3DEffect(.degrees(angle), axis: (0, 1, 0), perspective: 0.5)
    }

    /// 🔊 reads the word aloud (also the S key)
    private func speaker(small: Bool) -> some View {
        Button { LeitnerSpeech.say(word) } label: {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: small ? 12 : (compact ? 15 : 18), weight: .semibold))
                .padding(small ? 6 : 9).background(Circle().fill(LeitnerLook.color(section).opacity(0.2)))
        }
        .buttonStyle(.plain).keyboardShortcut("s", modifiers: []).help("Hear the pronunciation (S)")
    }

    private func face(back: Bool) -> some View {
        let tint = LeitnerLook.color(section)
        return VStack(spacing: compact ? 8 : 14) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text("Section \(section) · \(LeitnerLook.intervalText(section))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if late > 0 { Text("· \(late)d late").font(.caption.weight(.bold)).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
            if back {
                HStack(spacing: 8) {
                    Text(word).font(.system(size: compact ? 17 : 20, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    speaker(small: true)
                    LeitnerPOSChip(pos: pos)
                }
                // (a word saved without a meaning shows the one from the Mac's dictionary)
                Text(meaning.isEmpty ? (LeitnerDictionary.define(word) ?? "(no meaning saved)") : meaning)
                    .font(.system(size: compact ? 26 : 34, weight: .bold, design: .rounded)).multilineTextAlignment(.center).minimumScaleFactor(0.5)
            } else {
                HStack(spacing: 12) {
                    Text(word).font(.system(size: compact ? 34 : 48, weight: .heavy, design: .rounded)).multilineTextAlignment(.center).minimumScaleFactor(0.4)
                    speaker(small: false)
                }
                LeitnerPOSChip(pos: pos)
                Text("tap or press Space to see the meaning").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 18 : 26)
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 190 : 270)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(LinearGradient(colors: [tint.opacity(back ? 0.22 : 0.12), .clear], startPoint: .top, endPoint: .bottom)))
                .shadow(color: tint.opacity(0.28), radius: 22, y: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
    }
}

/// Show answer → "Don't know / Know it", with the card flying away to the side of the answer
struct LeitnerReviewDeck: View {
    @Bindable var session: LeitnerSession
    var compact = false
    @State private var fly: CGFloat = 0
    @State private var appear = true
    @State private var busy = false

    var body: some View {
        VStack(spacing: compact ? 14 : 22) {
            if let cur = session.current {
                LeitnerFlashCard(pos: cur.card.pos, word: cur.card.word, meaning: cur.card.meaning, section: cur.card.box, late: LeitnerStore.daysLate(cur.card),
                                 revealed: session.revealed, compact: compact)
                    .id(cur.card.id)
                    .offset(x: fly * 380).rotationEffect(.degrees(Double(fly) * 14)).opacity(1 - abs(Double(fly)) * 0.9)
                    .scaleEffect(appear ? 1 : 0.92).opacity(appear ? 1 : 0)
                    .onTapGesture { if !session.revealed { session.revealed = true } }
                    .shadow(color: fly > 0 ? .green.opacity(0.4) : fly < 0 ? .red.opacity(0.4) : .clear, radius: 24)
                if session.revealed {
                    HStack(spacing: 14) {
                        answerButton("Don't know", icon: "xmark", tint: .red, key: .leftArrow, hint: "←", knew: false)
                        answerButton("Know it", icon: "checkmark", tint: .green, key: .rightArrow, hint: "→", knew: true)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Button { withAnimation { session.revealed = true } } label: {
                        Text("Show answer   ⎵").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .keyboardShortcut(.space, modifiers: []).buttonStyle(.borderedProminent).controlSize(.large)
                    .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: session.revealed)
    }

    private func answerButton(_ title: String, icon: String, tint: Color, key: KeyEquivalent, hint: String, knew: Bool) -> some View {
        Button { send(knew) } label: {
            HStack(spacing: 8) { Image(systemName: icon).font(.headline); Text(title).font(.headline); Text(hint).font(.caption).opacity(0.6) }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .keyboardShortcut(key, modifiers: []).buttonStyle(.borderedProminent).tint(tint).controlSize(.large)
    }

    /// The card flies off, the next one grows in
    private func send(_ knew: Bool) {
        guard !busy else { return }
        busy = true
        withAnimation(.easeIn(duration: 0.22)) { fly = knew ? 1 : -1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            session.answer(knew)
            fly = 0; appear = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { appear = true }
            busy = false
        }
    }
}


/// Which voice reads the words (the app can't use the macOS "System voice" Siri voices, so it has its own list)
struct LeitnerVoicePicker: View {
    @AppStorage("leitner.voice") private var voice = ""

    var body: some View {
        HStack(spacing: 8) {
            Picker("Voice", selection: $voice) {
                Text("Automatic (best installed)").tag("")
                ForEach(LeitnerSpeech.englishVoices(), id: \.identifier) { Text(LeitnerSpeech.label($0)).tag($0.identifier) }
            }
            .frame(maxWidth: 360)
            Button { LeitnerSpeech.say("Accommodation") } label: { Image(systemName: "speaker.wave.2.fill") }
                .buttonStyle(.borderless).help("Hear this voice")
        }
    }
}
