import SwiftUI
import Charts

/// Leitner boxes: words kept on this Mac only (one CSV per box). See Leitner/LeitnerStore.swift for the rules.
struct LeitnerView: View {
    @State private var leitner = LeitnerStore.shared
    @State private var selected: String?
    @State private var tab = Tab.review
    @State private var newBoxName = ""
    @State private var showNewBox = false
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var deleting: String?
    @State private var collapsed: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "leitner.collapsed") ?? [])
    @State private var subOf: String?
    @State private var subName = ""
    @State private var newInTopic: String?
    @State private var newInTopicName = ""
    @State private var renamingTopic: String?
    @State private var topicText = ""
    @State private var toNewTopic: String?
    @State private var newTopicName = ""
    @Namespace private var tabNS

    enum Tab: String, CaseIterable, Identifiable {
        case review = "Review", words = "Words", learned = "Learned"
        var id: String { rawValue }
        var icon: String { self == .review ? "rectangle.on.rectangle.angled" : self == .words ? "text.alignleft" : "graduationcap.fill" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                HStack(alignment: .top, spacing: 18) {
                    boxList.frame(width: 250)
                    Group {
                        if let name = selected, leitner.box(name) != nil { detail(name) } else { emptyState }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .navigationTitle("Leitner Box")
        .onAppear {
            // back on the box (and tab) that was open before leaving the page
            if selected == nil || leitner.box(selected) == nil {
                let saved = UserDefaults.standard.string(forKey: "leitner.box")
                selected = leitner.box(saved) != nil ? saved : leitner.boxes.first?.name
            }
            if let t = UserDefaults.standard.string(forKey: "leitner.tab"), let tt = Tab(rawValue: t) { tab = tt }
        }
        .onChange(of: selected) { if let n = selected { UserDefaults.standard.set(n, forKey: "leitner.box") } }
        .onChange(of: tab) { UserDefaults.standard.set(tab.rawValue, forKey: "leitner.tab") }
        .alert("New Leitner box", isPresented: $showNewBox) {
            TextField("Name, e.g. IELTS vocabulary", text: $newBoxName)
            Button("Create") { if let n = leitner.createBox(newBoxName) { withAnimation(.spring) { selected = n; tab = .words } }; newBoxName = "" }
            Button("Cancel", role: .cancel) { newBoxName = "" }
        } message: { Text("Each box keeps its words in its own CSV file.") }
        .alert("Rename box", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let old = renaming, leitner.renameBox(old, to: renameText) { selected = renameText.trimmingCharacters(in: .whitespaces) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("New box inside this one", isPresented: Binding(get: { subOf != nil }, set: { if !$0 { subOf = nil } })) {
            TextField("Name, e.g. Green Packaging", text: $subName)
            Button("Create") { if let b = subOf, let n = leitner.putWordsInSubBox(of: b, called: subName) { withAnimation(.spring) { selected = n } }; subOf = nil; subName = "" }
            Button("Cancel", role: .cancel) { subOf = nil; subName = "" }
        } message: { Text("“\(subOf ?? "")” becomes a topic, and all its words move into this small box inside it. You can add more small boxes to the topic later.") }
        .alert("New box in this topic", isPresented: Binding(get: { newInTopic != nil }, set: { if !$0 { newInTopic = nil } })) {
            TextField("Name", text: $newInTopicName)
            Button("Create") { if let t = newInTopic, let n = leitner.createBox(t + LeitnerStore.topicSeparator + newInTopicName.replacingOccurrences(of: "›", with: "-")) { withAnimation(.spring) { selected = n; tab = .words } }; newInTopic = nil; newInTopicName = "" }
            Button("Cancel", role: .cancel) { newInTopic = nil; newInTopicName = "" }
        }
        .alert("Rename topic", isPresented: Binding(get: { renamingTopic != nil }, set: { if !$0 { renamingTopic = nil } })) {
            TextField("Name", text: $topicText)
            Button("Rename") { if let t = renamingTopic { leitner.renameTopic(t, to: topicText); selected = leitner.boxes.first(where: { $0.name.hasPrefix(topicText.trimmingCharacters(in: .whitespaces) + LeitnerStore.topicSeparator) })?.name ?? selected }; renamingTopic = nil }
            Button("Cancel", role: .cancel) { renamingTopic = nil }
        }
        .alert("Move to a new topic", isPresented: Binding(get: { toNewTopic != nil }, set: { if !$0 { toNewTopic = nil } })) {
            TextField("Topic name, e.g. Reading", text: $newTopicName)
            Button("Move") { if let b = toNewTopic, let n = leitner.moveBox(b, toTopic: newTopicName) { selected = n }; toNewTopic = nil; newTopicName = "" }
            Button("Cancel", role: .cancel) { toNewTopic = nil; newTopicName = "" }
        }
        .confirmationDialog("Delete this box?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { if let d = deleting { leitner.deleteBox(d); selected = leitner.boxes.first?.name }; deleting = nil }
        } message: { Text("Its CSV file goes to the Trash.") }
    }

    // MARK: Hero: today's words

    private var hero: some View {
        let done = leitner.reviewedToday, goal = leitner.dailyGoal, due = leitner.totalDue
        let learnedTotal = leitner.boxes.reduce(0) { $0 + $1.cards.filter(\.isLearned).count }
        let wordsTotal = leitner.boxes.reduce(0) { $0 + $1.cards.count }
        return HStack(spacing: 26) {
            ZStack {
                Circle().stroke(.white.opacity(0.22), lineWidth: 11)
                Circle().trim(from: 0, to: min(1, Double(done) / Double(max(1, goal))))
                    .stroke(.white, style: StrokeStyle(lineWidth: 11, lineCap: .round)).rotationEffect(.degrees(-90))
                    .shadow(color: .white.opacity(0.6), radius: 6)
                    .animation(.spring(response: 0.8, dampingFraction: 0.8), value: done)
                VStack(spacing: -2) {
                    Text("\(done)").font(.system(size: 36, weight: .heavy, design: .rounded)).contentTransition(.numericText())
                    Text("of \(goal)").font(.caption.weight(.semibold)).opacity(0.8)
                }
            }
            .frame(width: 122, height: 122)

            VStack(alignment: .leading, spacing: 10) {
                Text("LEITNER BOX").font(.caption.weight(.heavy)).tracking(2.5).opacity(0.75)
                Text(done >= goal ? "Minimum reached — you're on fire 🔥" : "\(goal - done) more word\(goal - done == 1 ? "" : "s") to reach today's minimum")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                HStack(spacing: 10) {
                    chip("\(done)", "reviewed today", "checkmark.circle.fill")
                    chip("\(due)", "left to review", "hourglass")
                    chip("\(learnedTotal)", "learned", "graduationcap.fill")
                    chip("\(wordsTotal - learnedTotal)", "in the boxes", "square.stack.3d.up.fill")
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                Button { LeitnerQuickPanel.shared.show() } label: {
                    HStack(spacing: 8) { Image(systemName: "bolt.fill"); Text("Daily review").fontWeight(.bold) }
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Capsule().fill(.white)).foregroundStyle(Color(hex: "#6D28D9"))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .help("A small window with your due words, from any app")
                Text("⌃⌥L from anywhere").font(.caption2.weight(.semibold)).opacity(0.75)
                Stepper(value: $leitner.dailyGoal, in: 1...1000) { Text("Minimum \(goal)/day").font(.caption.weight(.semibold)).monospacedDigit() }
                    .controlSize(.small).fixedSize()
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: "#4F46E5"), Color(hex: "#7C3AED"), Color(hex: "#DB2777")], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.10)).frame(width: 260).offset(x: 240, y: -90)
                Circle().fill(.white.opacity(0.07)).frame(width: 180).offset(x: -300, y: 110)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color(hex: "#7C3AED").opacity(0.4), radius: 22, y: 10)
        )
    }

    private func chip(_ value: String, _ label: String, _ icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.callout)
            VStack(alignment: .leading, spacing: -1) {
                Text(value).font(.headline.monospacedDigit()).contentTransition(.numericText())
                Text(label).font(.caption2).opacity(0.8)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.17)))
    }

    // MARK: Boxes

    private enum Row: Identifiable {
        case box(LeitnerBox)
        case topic(String, [LeitnerBox])
        var id: String { switch self { case .box(let b): "b|" + b.name; case .topic(let t, _): "t|" + t } }
    }

    /// Loose boxes, and topics with the small boxes inside them (a topic sits where its first box would)
    private var rows: [Row] {
        var out: [Row] = [], seen = Set<String>()
        for b in leitner.boxes {
            if let t = LeitnerStore.parts(b.name).topic {
                guard seen.insert(t).inserted else { continue }
                out.append(.topic(t, leitner.boxes.filter { LeitnerStore.parts($0.name).topic == t }))
            } else {
                out.append(.box(b))
            }
        }
        return out
    }

    private var boxList: some View {
        VStack(spacing: 10) {
            ForEach(rows) { row in
                switch row {
                case .box(let b): boxTile(b)
                case .topic(let t, let kids): topicGroup(t, kids)
                }
            }
            Button { showNewBox = true } label: {
                HStack { Image(systemName: "plus.circle.fill"); Text("New box").fontWeight(.semibold) }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    /// A topic: a header you can fold, with its small boxes under it
    private func topicGroup(_ topic: String, _ kids: [LeitnerBox]) -> some View {
        let open = !collapsed.contains(topic)
        let due = kids.reduce(0) { $0 + leitner.due(in: $1.name).count }
        let words = kids.reduce(0) { $0 + $1.cards.count }
        return VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    if open { collapsed.insert(topic) } else { collapsed.remove(topic) }
                }
                UserDefaults.standard.set(Array(collapsed), forKey: "leitner.collapsed")
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: open ? "folder.fill" : "folder").font(.title3).foregroundStyle(LeitnerLook.gradient(topic))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(topic).font(.headline).lineLimit(1)
                        Text("\(kids.count) box\(kids.count == 1 ? "" : "es") · \(words) words").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if due > 0 { Text("\(due) due").font(.caption2.weight(.heavy)).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Color(hex: "#EA580C"))).foregroundStyle(.white) }
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary).rotationEffect(.degrees(open ? 0 : -90))
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("New box in this topic…") { newInTopic = topic }
                Button("Rename topic…") { topicText = topic; renamingTopic = topic }
                Divider()
                Button("Take all boxes out of the topic") { for b in kids { leitner.moveBox(b.name, toTopic: nil) } }
            }
            if open {
                VStack(spacing: 8) { ForEach(kids) { boxTile($0, inTopic: true) } }
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) { Capsule().fill(Color.primary.opacity(0.12)).frame(width: 2).padding(.vertical, 6) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func boxTile(_ b: LeitnerBox, inTopic: Bool = false) -> some View {
        let due = leitner.due(in: b.name).count, on = selected == b.name
        let counts = (1...5).map { s in b.cards.filter { $0.box == s }.count }
        let learned = b.cards.filter(\.isLearned).count
        return Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selected = b.name } } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(inTopic ? LeitnerStore.parts(b.name).title : b.name).font(inTopic ? .subheadline.weight(.semibold) : .headline).lineLimit(1)
                    Spacer()
                    if due > 0 { Text("\(due) due").font(.caption2.weight(.heavy)).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(.white.opacity(on ? 0.3 : 0.9))).foregroundStyle(on ? .white : Color(hex: "#EA580C")) }
                }
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { i in
                        Capsule().fill(LeitnerLook.color(i + 1).opacity(counts[i] > 0 ? 1 : 0.25)).frame(height: 6).frame(maxWidth: .infinity)
                            .scaleEffect(x: 1, y: counts[i] > 0 ? 1 : 0.6)
                    }
                }
                Text("\(counts.reduce(0, +)) in the box · \(learned) learned").font(.caption).opacity(0.75)
            }
            .foregroundStyle(on ? .white : .primary)
            .padding(inTopic ? 11 : 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(on ? AnyShapeStyle(LeitnerLook.gradient(b.name)) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
                    .shadow(color: .black.opacity(on ? 0.25 : 0.08), radius: on ? 14 : 6, y: on ? 8 : 3)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(on ? 0 : 0.07)))
            .scaleEffect(on ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") { renameText = LeitnerStore.parts(b.name).title == b.name ? b.name : b.name; renaming = b.name }
            if LeitnerStore.parts(b.name).topic == nil {
                Button("Put its words in a new box inside it…") { subName = ""; subOf = b.name }
            }
            Menu("Move to a topic") {
                ForEach(leitner.topics.filter { $0 != LeitnerStore.parts(b.name).topic }, id: \.self) { t in
                    Button(t) { if let n = leitner.moveBox(b.name, toTopic: t) { selected = n } }
                }
                Button("New topic…") { newTopicName = ""; toNewTopic = b.name }
                if LeitnerStore.parts(b.name).topic != nil {
                    Divider()
                    Button("Take out of the topic") { if let n = leitner.moveBox(b.name, toTopic: nil) { selected = n } }
                }
            }
            Button("Show CSV in Finder") { leitner.reveal(b.name) }
            Divider()
            Button("Delete…", role: .destructive) { deleting = b.name }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 54)).foregroundStyle(LinearGradient(colors: [.indigo, .pink], startPoint: .top, endPoint: .bottom))
            Text("Make your first Leitner box").font(.title2.weight(.bold))
            Text("A box is a list of words with its own CSV file. Words move through 5 sections: 1, 2, 4, 8 and 16 days.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            Button("New box") { showNewBox = true }.buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 70)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: A box

    private func detail(_ name: String) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    if let t = LeitnerStore.parts(name).topic { Label(t, systemImage: "folder.fill").font(.caption.weight(.bold)).foregroundStyle(.secondary).lineLimit(1) }
                    Text(LeitnerStore.parts(name).title).font(.system(size: 26, weight: .heavy, design: .rounded)).lineLimit(1)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(Tab.allCases) { t in
                        Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { tab = t } } label: {
                            Label(t.rawValue, systemImage: t.icon).font(.callout.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 7)
                                .foregroundStyle(tab == t ? .white : .secondary)
                                .background { if tab == t { Capsule().fill(LeitnerLook.gradient(name)).matchedGeometryEffect(id: "tab", in: tabNS) } }
                                .contentShape(Capsule())   // the whole pill is clickable, not just the letters
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3).background(Capsule().fill(Color.primary.opacity(0.07)))
                Button { leitner.reveal(name) } label: { Image(systemName: "doc.text.magnifyingglass").padding(8).background(Circle().fill(Color.primary.opacity(0.07))) }
                    .buttonStyle(.plain).help("Show this box's CSV file in Finder")
            }
            shelf(name)
            Group {
                switch tab {
                case .review: LeitnerReview(box: name).id(name)
                case .words: LeitnerWords(box: name)
                case .learned: LeitnerLearned(box: name)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .id(tab)
        }
    }

    /// The five sections of the box (and the learned ones) as little shelves
    private func shelf(_ name: String) -> some View {
        let cards = leitner.box(name)?.cards ?? []
        let late = cards.filter { !$0.isLearned && $0.due <= LeitnerStore.today }
        return HStack(spacing: 10) {
            ForEach(1...6, id: \.self) { s in
                let n = cards.filter { $0.box == s }.count
                let dueHere = late.filter { $0.box == s }.count
                VStack(spacing: 4) {
                    Text("\(n)").font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                    Text(s == 6 ? "Learned" : "Section \(s)").font(.caption.weight(.bold))
                    Text(LeitnerLook.intervalText(s)).font(.caption2).opacity(0.7)
                    if dueHere > 0 { Text("\(dueHere) due").font(.caption2.weight(.heavy)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(LeitnerLook.color(s))) }
                    else { Text(" ").font(.caption2) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LeitnerLook.color(s).opacity(0.14))
                        .overlay(alignment: .top) { Capsule().fill(LeitnerLook.color(s)).frame(width: 34, height: 4).offset(y: -2) }
                )
            }
        }
    }
}

// MARK: - Review

private struct LeitnerReview: View {
    let box: String
    @State private var leitner = LeitnerStore.shared
    @State private var session = LeitnerSession()
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 18) {
            if session.current != nil {
                HStack {
                    ProgressView(value: Double(session.answered), total: Double(max(1, session.initial))).tint(LeitnerLook.color(2))
                    Text("\(session.queue.count) left").font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                }
                LeitnerReviewDeck(session: session).frame(maxWidth: 520)
            } else {
                finished
            }
        }
        .frame(maxWidth: .infinity).padding(24)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .onAppear { session.start(boxes: [box]) }
    }

    @ViewBuilder private var finished: some View {
        let due = leitner.due(in: box).count, more = leitner.ahead(in: box).count
        VStack(spacing: 12) {
            if leitner.box(box)?.cards.isEmpty ?? true {
                Image(systemName: "text.badge.plus").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("No words yet").font(.title3.weight(.bold))
                Text("Open the Words tab and add some.").foregroundStyle(.secondary)
            } else {
                Text(session.answered > 0 ? "🎉" : "✅").font(.system(size: 64)).scaleEffect(celebrate ? 1 : 0.4)
                    .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) { celebrate = true } }
                Text(session.answered > 0 ? "Round finished — \(session.answered) word\(session.answered == 1 ? "" : "s") reviewed" : "Nothing due in this box").font(.title3.weight(.bold))
                if due > 0 { Button("Review \(due) due word\(due == 1 ? "" : "s")") { celebrate = false; session.start(boxes: [box]) }.buttonStyle(.borderedProminent).controlSize(.large) }
                if more > 0 {
                    // a round big enough to reach today's minimum (at least 10 words)
                    let n = min(more, max(10, leitner.dailyGoal - leitner.reviewedToday))
                    Button("Study more (next \(n) of \(more) not due yet)") { celebrate = false; session.start(boxes: [box], more: true, count: n) }.controlSize(.large)
                    Text("There is no limit: study as many as you like.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 30)
    }
}

// MARK: - Words

private struct LeitnerWords: View {
    let box: String
    @State private var leitner = LeitnerStore.shared
    @State private var text = ""
    @State private var info = ""
    @State private var search = ""
    /// Words that look misspelled, waiting for the member to pick the right spelling before they enter the box
    @State private var checking: [SpellItem] = []

    struct SpellItem: Identifiable {
        let id = UUID()
        let line: String
        let word: String
        var options: [String]
        var choice: String
    }

    private func addNow(_ t: String) {
        let r = leitner.addWords(t, to: box)
        withAnimation { checking = [] }
        withAnimation { info = r.added == 0 && r.skipped == 0 ? "" : "\(r.added) added" + (r.skipped > 0 ? " · \(r.skipped) already in the box" : "") }
        if r.added > 0 || r.skipped > 0 { text = "" }
    }

    /// Look for spelling mistakes first; if there are none the words go straight into the box
    private func tryAdd() {
        let items: [SpellItem] = text.split(whereSeparator: \.isNewline).compactMap { l in
            let line = String(l)
            let (word, _) = LeitnerStore.split(line)
            guard !word.isEmpty, let opts = LeitnerSpell.options(word) else { return nil }
            return SpellItem(line: line, word: word, options: opts, choice: opts.first ?? word)
        }
        if items.isEmpty { addNow(text) } else { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { checking = items } }
    }

    private func confirmChecked() {
        let fixes = Dictionary(checking.map { ($0.line, $0) }, uniquingKeysWith: { a, _ in a })
        let out = text.split(whereSeparator: \.isNewline).map { l -> String in
            let line = String(l)
            guard let f = fixes[line], f.choice != f.word, let r = line.range(of: f.word) else { return line }
            return line.replacingCharacters(in: r, with: f.choice)
        }.joined(separator: "\n")
        withAnimation { checking = [] }
        addNow(out)
    }

    var body: some View {
        let cards = (leitner.box(box)?.cards ?? []).filter { !$0.isLearned && (search.isEmpty || $0.word.localizedCaseInsensitiveContains(search) || $0.meaning.localizedCaseInsensitiveContains(search)) }
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Add words", systemImage: "plus.circle.fill").font(.headline)
                TextEditor(text: $text).font(.body.monospaced()).frame(height: 84).scrollContentBackground(.hidden).padding(6)
                    // Return adds the words, Shift + Return starts a new line
                    .onKeyPress(keys: [.return]) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        let filled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        // Command + Return adds the words as typed, without the spelling check (names, special words)
                        if press.modifiers.contains(.command) { if filled { addNow(text) }; return .handled }
                        if filled { tryAdd() }
                        return .handled
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty { Text("word - meaning   (meaning is optional)   ·   Return adds · ⇧ Return new line · ⌘ Return adds without the spelling check").foregroundStyle(.tertiary).padding(.leading, 11).padding(.top, 7).allowsHitTesting(false) }
                    }
                HStack {
                    Button { tryAdd() } label: { Label("Add to box", systemImage: "arrow.down.circle.fill") }
                        .buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button {
                        let r = leitner.fillMeanings(in: box)
                        withAnimation { info = r.filled == 0 && r.missing == 0 ? "Every word already has a meaning" : "\(r.filled) meaning\(r.filled == 1 ? "" : "s") filled" + (r.missing > 0 ? " · \(r.missing) not in the dictionary" : "") }
                    } label: { Label("Fill empty meanings", systemImage: "character.book.closed.fill") }
                        .help("Take the meaning from the dictionary built into your Mac")
                    Text(info).font(.callout).foregroundStyle(.green)
                    Spacer()
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Search", text: $search).textFieldStyle(.plain) }
                        .padding(.horizontal, 10).padding(.vertical, 6).frame(width: 200).background(Capsule().fill(Color.primary.opacity(0.07)))
                }
            }
            .padding(18).background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))

            if !checking.isEmpty { spellCard }

            if cards.isEmpty {
                Text(search.isEmpty ? "No words in this box yet" : "Nothing found").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                ForEach(1...5, id: \.self) { s in
                    let inSection = cards.filter { $0.box == s }.sorted { ($0.due, $0.word) < ($1.due, $1.word) }
                    if !inSection.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle().fill(LeitnerLook.color(s)).frame(width: 10, height: 10)
                                Text("Section \(s)").font(.headline)
                                Text("\(LeitnerLook.intervalText(s)) · \(inSection.count)").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(inSection) { c in row(c) }
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: cards.count)
        // typing again means the suggestions are out of date: the card goes away
        .onChange(of: text) { if !checking.isEmpty { withAnimation { checking = [] } } }
    }

    /// "Did you mean …?" before the words enter the box
    private var spellCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Check the spelling", systemImage: "text.badge.checkmark").font(.headline).foregroundStyle(.orange)
            Text("A word with a spelling mistake can't be added. Pick the right spelling below, or go back and fix it yourself. (For a special word, press ⌘ Return in the box to add it as typed.)").font(.callout).foregroundStyle(.secondary)
            ForEach($checking) { $item in
                HStack(spacing: 10) {
                    Text(item.word).strikethrough(item.choice != item.word).foregroundStyle(item.choice != item.word ? .red : .primary).fontWeight(.semibold)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    if item.options.isEmpty {
                        Text("No suggestion found — check the spelling").foregroundStyle(.orange)
                    } else {
                        Picker("", selection: $item.choice) { ForEach(item.options, id: \.self) { Text($0).tag($0) } }
                            .labelsHidden().frame(width: 220)
                    }
                    Spacer()
                }
            }
            HStack {
                Button("Add words") { confirmChecked() }.buttonStyle(.borderedProminent).disabled(checking.contains { $0.options.isEmpty })
                Button("Back to editing") { withAnimation { checking = [] } }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.orange.opacity(0.4)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func row(_ c: LeitnerCard) -> some View {
        let late = LeitnerStore.daysLate(c)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(LeitnerLook.color(c.box)).frame(width: 4, height: 30)
            Text(c.word).fontWeight(.bold)
            LeitnerPOSChip(pos: c.pos)
            Text(c.meaning).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text(late > 0 ? "\(late)d late" : late == 0 ? "due today" : "in \(-late)d")
                .font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(late >= 0 ? Color.orange.opacity(0.18) : Color.primary.opacity(0.07))).foregroundStyle(late >= 0 ? .orange : .secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .transition(.scale(scale: 0.95).combined(with: .opacity))
        .contextMenu {
            Menu("Move to section") { ForEach(1...5, id: \.self) { s in Button("Section \(s)") { leitner.move(c.id, in: box, toSection: s) } } }
            Button("Mark as learned") { leitner.move(c.id, in: box, toSection: LeitnerCard.learned) }
            Divider()
            Button("Delete", role: .destructive) { leitner.delete(c.id, in: box) }
        }
    }
}

// MARK: - Learned

private struct LeitnerLearned: View {
    let box: String
    @State private var leitner = LeitnerStore.shared

    var body: some View {
        let list = leitner.learned(in: box)
        VStack(alignment: .leading, spacing: 12) {
            if list.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "graduationcap.fill").font(.system(size: 40)).foregroundStyle(LeitnerLook.color(6))
                    Text("No learned words yet").font(.title3.weight(.bold))
                    Text("A word is learned when you know it in section 5.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 50)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            } else {
                Label("\(list.count) learned word\(list.count == 1 ? "" : "s")", systemImage: "graduationcap.fill").font(.headline).foregroundStyle(LeitnerLook.color(6))
                ForEach(list) { c in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(LeitnerLook.color(6))
                        Text(c.word).fontWeight(.bold)
                        LeitnerPOSChip(pos: c.pos)
                        Text(c.meaning).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(c.lastReview).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LeitnerLook.color(6).opacity(0.10)))
                    .contextMenu {
                        Button("Back to section 1") { leitner.move(c.id, in: box, toSection: 1) }
                        Divider()
                        Button("Delete", role: .destructive) { leitner.delete(c.id, in: box) }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: list.count)
    }
}

// MARK: - Reports

/// Words reviewed per day (used in Reports)
struct LeitnerReportChart: View {
    let days: [Date]
    @State private var leitner = LeitnerStore.shared

    var body: some View {
        let per = leitner.reviewedPerDay()
        let points = days.map { (day: $0, n: per[Cal.dayKey($0)] ?? 0) }
        let total = points.reduce(0) { $0 + $1.n }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(total)").font(.title.weight(.bold).monospacedDigit())
                Text("word reviews in this period · today \(leitner.reviewedToday) of \(leitner.dailyGoal)").font(.callout).foregroundStyle(.secondary)
            }
            if total == 0 {
                Text("No words reviewed in this period.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
            } else {
                Chart(points, id: \.day) { p in
                    BarMark(x: .value("Day", p.day, unit: .day), y: .value("Words", p.n)).foregroundStyle(p.n >= leitner.dailyGoal ? Color.green : Color.mint).cornerRadius(3)
                    RuleMark(y: .value("Minimum", leitner.dailyGoal)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .frame(height: 140)
            }
        }
    }
}
