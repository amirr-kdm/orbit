import SwiftUI

/// A dictation round: the Mac says a word, waits a few seconds while the member types it, then says the next one.
@MainActor @Observable
final class SpellingSession {
    enum Phase { case idle, running, finished }
    struct Result: Identifiable { let id = UUID(); let word: String; let typed: String; let ok: Bool }

    var phase = Phase.idle
    private(set) var queue: [LeitnerCard] = []
    private(set) var index = 0
    var typed = ""
    /// 0…1: how much of the waiting time has passed
    private(set) var progress = 0.0
    private(set) var speaking = false
    private(set) var results: [Result] = []
    private(set) var lastResult: Result?
    private(set) var box = ""

    private var task: Task<Void, Never>?
    private var skip = false
    private var rate: Float = 0.42
    private var gap = 3.0
    private var twice = false

    var current: LeitnerCard? { index < queue.count ? queue[index] : nil }

    static var savedGap: Double { UserDefaults.standard.object(forKey: "spell.gap") as? Double ?? 3 }
    static var savedRate: Double { UserDefaults.standard.object(forKey: "spell.rate") as? Double ?? 0.42 }
    static var savedTwice: Bool { UserDefaults.standard.bool(forKey: "spell.twice") }

    func start(box: String, cards: [LeitnerCard], shuffle: Bool) {
        task?.cancel()
        self.box = box
        queue = shuffle ? cards.shuffled() : cards
        index = 0; typed = ""; results = []; lastResult = nil; progress = 0
        gap = Self.savedGap; rate = Float(Self.savedRate); twice = Self.savedTwice
        guard !queue.isEmpty else { phase = .idle; return }
        phase = .running
        task = Task { await run() }
    }

    func submit() { skip = true }
    func replay() { if let c = current { LeitnerSpeech.say(c.word, rate: rate) } }

    func stop() {
        task?.cancel(); LeitnerSpeech.stop()
        phase = results.isEmpty ? .idle : .finished
    }

    private func speak(_ word: String) async {
        speaking = true
        LeitnerSpeech.say(word, rate: rate)
        try? await Task.sleep(for: .milliseconds(250))
        while LeitnerSpeech.isSpeaking && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(80)) }
        speaking = false
    }

    private func run() async {
        for (i, c) in queue.enumerated() {
            if Task.isCancelled { return }
            index = i; typed = ""; progress = 0; skip = false
            await speak(c.word)
            if twice && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(700)); await speak(c.word) }
            // the writing time
            var t = 0.0
            while t < gap && !skip && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                t += 0.05; progress = min(1, t / gap)
            }
            if Task.isCancelled { return }
            let ok = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == c.word.lowercased()
            let r = Result(word: c.word, typed: typed.trimmingCharacters(in: .whitespacesAndNewlines), ok: ok)
            results.append(r); lastResult = r
            LeitnerStore.shared.spellingReview(c.id, in: box, correct: ok)
        }
        phase = .finished
    }
}

/// The Spelling section of a Leitner box
struct LeitnerSpelling: View {
    let box: String
    @State private var leitner = LeitnerStore.shared
    @State private var session = SpellingSession()
    @State private var filter = LeitnerStore.SpellingFilter.spellingDue
    @AppStorage("spell.gap") private var gap = 3.0
    @AppStorage("spell.rate") private var rate = 0.42
    @AppStorage("spell.twice") private var twice = false
    @AppStorage("spell.shuffle") private var shuffle = true
    @FocusState private var focused: Bool

    private var cards: [LeitnerCard] { leitner.spellingCards(in: box, filter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "ear.and.waveform").font(.title2).foregroundStyle(LinearGradient(colors: [.cyan, .indigo], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Spelling").font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text("Listen, then type the word. Words you spell right move to the next spelling section.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(leitner.spelledToday) spelled today").font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.cyan.opacity(0.18)))
            }
            shelf
            switch session.phase {
            case .idle: setup
            case .running: running
            case .finished: finished
            }
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.cyan.opacity(0.25)))
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: session.phase)
        .onDisappear { if session.phase == .running { session.stop() } }
    }

    // MARK: Spelling sections (not the same as the vocabulary sections)

    private var shelf: some View {
        let all = leitner.box(box)?.cards ?? []
        return HStack(spacing: 8) {
            ForEach(1...6, id: \.self) { s in
                let n = all.filter { $0.spellBox == s }.count
                let due = all.filter { $0.spellBox == s && s < 6 && ($0.spellDue.isEmpty || $0.spellDue <= LeitnerStore.today) }.count
                VStack(spacing: 2) {
                    Text("\(n)").font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text(s == 6 ? "Spelled" : "Spelling \(s)").font(.caption2.weight(.bold))
                    Text(due > 0 ? "\(due) due" : " ").font(.caption2).foregroundStyle(due > 0 ? Color.cyan : .secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.cyan.opacity(0.07 + 0.03 * Double(s))))
            }
        }
    }

    // MARK: Before starting

    private func title(_ f: LeitnerStore.SpellingFilter) -> String {
        switch f {
        case .spellingDue: "Spelling words due today"
        case .reviewedToday: "Words I reviewed today (all)"
        case .learnedToday: "Words I learned today (moved up a section)"
        case .vocabSection(let s): s == 6 ? "Vocabulary: learned words" : "Vocabulary section \(s)"
        case .spellSection(let s): s == 6 ? "Spelling: already spelled" : "Spelling section \(s)"
        case .all: "All words in the box"
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Words", selection: $filter) {
                    Text(title(.spellingDue)).tag(LeitnerStore.SpellingFilter.spellingDue)
                    Text(title(.learnedToday)).tag(LeitnerStore.SpellingFilter.learnedToday)
                    Text(title(.reviewedToday)).tag(LeitnerStore.SpellingFilter.reviewedToday)
                    Divider()
                    ForEach(1...6, id: \.self) { s in Text(title(.vocabSection(s))).tag(LeitnerStore.SpellingFilter.vocabSection(s)) }
                    Divider()
                    ForEach(1...6, id: \.self) { s in Text(title(.spellSection(s))).tag(LeitnerStore.SpellingFilter.spellSection(s)) }
                    Divider()
                    Text(title(.all)).tag(LeitnerStore.SpellingFilter.all)
                }
                .frame(maxWidth: 330)
                Text("\(cards.count) word\(cards.count == 1 ? "" : "s")").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
            }
            LeitnerVoicePicker()
            HStack(spacing: 28) {
                Stepper(value: $gap, in: 1...30, step: 1) { Text("Wait between words: \(Int(gap)) s").monospacedDigit() }.fixedSize()
                HStack(spacing: 8) {
                    Text("Speed").foregroundStyle(.secondary)
                    Text("Slow").font(.caption)
                    Slider(value: $rate, in: 0.25...0.6).frame(width: 130)
                    Text("Fast").font(.caption)
                    Button { LeitnerSpeech.say("pronunciation", rate: Float(rate)) } label: { Image(systemName: "speaker.wave.2.fill") }.buttonStyle(.borderless).help("Hear this speed")
                }
            }
            HStack(spacing: 24) {
                Toggle("Say each word twice", isOn: $twice)
                Toggle("Mix the order", isOn: $shuffle)
            }
            .toggleStyle(.switch).controlSize(.small)
            HStack {
                Button { startRound(cards) } label: {
                    Label("Start spelling", systemImage: "play.fill").font(.headline).padding(.horizontal, 14).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).tint(.cyan).controlSize(.large).disabled(cards.isEmpty)
                if cards.isEmpty { Text(emptyHint).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    private var emptyHint: String {
        (leitner.box(box)?.cards.isEmpty ?? true) ? "Add words to this box first." : "No words in this group right now. Pick another group."
    }

    private func startRound(_ list: [LeitnerCard]) {
        session.start(box: box, cards: list, shuffle: shuffle)
        focused = true
    }

    // MARK: During a round

    private var running: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Word \(session.index + 1) of \(session.queue.count)").font(.headline).monospacedDigit()
                Spacer()
                Button(role: .destructive) { session.stop() } label: { Label("Stop", systemImage: "stop.fill") }.controlSize(.regular)
            }
            ProgressView(value: Double(session.index), total: Double(max(1, session.queue.count))).tint(.cyan)

            ZStack {
                Circle().fill(Color.cyan.opacity(session.speaking ? 0.28 : 0.12)).frame(width: 96, height: 96)
                    .scaleEffect(session.speaking ? 1.15 : 1)
                    .animation(session.speaking ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .spring, value: session.speaking)
                Image(systemName: session.speaking ? "speaker.wave.3.fill" : "ear.fill").font(.system(size: 36)).foregroundStyle(.cyan)
                    .contentTransition(.symbolEffect(.replace))
            }
            Text(session.speaking ? "Listen…" : "Type the word you heard").font(.title3.weight(.semibold))

            TextField("Write it here, then press Return", text: $session.typed)
                .textFieldStyle(.plain).font(.system(size: 30, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                .padding(.vertical, 12).padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cyan.opacity(0.5), lineWidth: 1.5))
                .focused($focused)
                .onSubmit { session.submit() }
                .autocorrectionDisabled()
                .frame(maxWidth: 520)
            // the time left to write
            Capsule().fill(Color.primary.opacity(0.1)).frame(height: 6).frame(maxWidth: 520)
                .overlay(alignment: .leading) {
                    GeometryReader { g in Capsule().fill(session.progress > 0.75 ? Color.orange : Color.cyan).frame(width: g.size.width * (1 - session.progress)) }
                }
            HStack(spacing: 12) {
                Button { session.replay() } label: { Label("Hear again", systemImage: "arrow.counterclockwise") }
                Button { session.submit() } label: { Label("Next word  ⏎", systemImage: "forward.end.fill") }
            }
            if let r = session.lastResult {
                HStack(spacing: 8) {
                    Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(r.ok ? .green : .red)
                    Text(r.ok ? r.word : "\(r.typed.isEmpty ? "(nothing)" : r.typed)  →  \(r.word)").font(.callout.weight(.semibold))
                    Text("previous word").font(.caption).foregroundStyle(.tertiary)
                }
                .id(r.id).transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
        .animation(.easeOut(duration: 0.25), value: session.lastResult?.id)
    }

    // MARK: After a round

    private var finished: some View {
        let right = session.results.filter(\.ok).count, total = session.results.count
        let wrong = session.results.filter { !$0.ok }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text(right == total && total > 0 ? "🎉" : "📝").font(.system(size: 40))
                VStack(alignment: .leading) {
                    Text("\(right) of \(total) spelled right").font(.title3.weight(.bold))
                    Text(wrong.isEmpty ? "Perfect round!" : "The words you missed go back to Spelling 1.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ForEach(session.results) { r in
                HStack(spacing: 10) {
                    Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(r.ok ? .green : .red)
                    Text(r.word).fontWeight(.bold)
                    if !r.ok { Text("you wrote: \(r.typed.isEmpty ? "nothing" : r.typed)").foregroundStyle(.red).strikethrough(!r.typed.isEmpty) }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill((r.ok ? Color.green : Color.red).opacity(0.10)))
            }
            HStack {
                if !wrong.isEmpty {
                    Button("Practise the \(wrong.count) missed again") {
                        let ids = Set(wrong.map { $0.word.lowercased() })
                        startRound((leitner.box(box)?.cards ?? []).filter { ids.contains($0.word.lowercased()) })
                    }.buttonStyle(.borderedProminent).tint(.cyan)
                }
                Button("Done") { session.stop(); session.phase = .idle }
            }
        }
    }
}


/// The Spelling page (sidebar, under Leitner Box): pick a box, then practise by ear
struct LeitnerSpellingPage: View {
    @State private var leitner = LeitnerStore.shared
    @AppStorage("spell.box") private var picked = ""

    private var current: String? { leitner.box(picked) != nil ? picked : leitner.boxes.first?.name }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if leitner.boxes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "ear.and.waveform").font(.system(size: 46)).foregroundStyle(.cyan)
                        Text("No Leitner box yet").font(.title2.weight(.bold))
                        Text("Make a box in Leitner Box and add words. Then come back to practise their spelling.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 80)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Practise the spelling of").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(leitner.boxes) { b in
                                    let on = current == b.name
                                    let due = leitner.spellingCards(in: b.name, .spellingDue).count
                                    Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { picked = b.name } } label: {
                                        HStack(spacing: 8) {
                                            Text(b.name).fontWeight(.semibold)
                                            if due > 0 { Text("\(due)").font(.caption2.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(.white.opacity(on ? 0.3 : 0.9))).foregroundStyle(on ? .white : Color(hex: "#0891B2")) }
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                        .foregroundStyle(on ? .white : .primary)
                                        .background(Capsule().fill(on ? AnyShapeStyle(LeitnerLook.gradient(b.name)) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))))
                                        .shadow(color: .black.opacity(on ? 0.25 : 0.06), radius: on ? 10 : 4, y: 3)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 6).padding(.horizontal, 2)
                        }
                    }
                    if let name = current { LeitnerSpelling(box: name).id(name) }
                }
            }
            .padding(24)
        }
        .navigationTitle("Spelling")
    }
}
