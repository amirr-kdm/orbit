import SwiftUI

/// One word card of a Leitner box
struct LeitnerCard: Identifiable, Hashable {
    var id = UUID()
    var word: String
    var meaning: String
    /// 1…5 = the box section, `learned` = finished all five
    var box: Int = 1
    var added: String
    /// "yyyy-MM-dd" of the last review ("" = never)
    var lastReview = ""
    /// "yyyy-MM-dd" it is due again ("" once learned)
    var due: String
    var reviews = 0
    var mistakes = 0
    /// Spelling practice has its own sections (1…5, 6 = learned) that move independently of the vocabulary ones
    var spellBox = 1
    var spellDue = ""
    var spellLast = ""
    var spellReviews = 0
    var spellMistakes = 0
    /// noun, verb, adjective, adverb … (from the Mac's dictionary)
    var pos = ""

    static let learned = 6
    var spellLearned: Bool { spellBox == Self.learned }
    var isLearned: Bool { box == Self.learned }
}

/// A Leitner box: its own list of words, saved in its own CSV file
struct LeitnerBox: Identifiable, Hashable {
    var name: String
    var cards: [LeitnerCard] = []
    var id: String { name }
}

/// Leitner boxes kept on this Mac only: one CSV per box in ~/Library/Application Support/Orbit/Leitner/
/// Section 1 is reviewed after 1 day, then 2, 4, 8 and 16 days. A right answer moves a word up a section, a wrong one sends it back to
/// section 1; after section 5 it is "learned". Being late changes nothing by itself: the word is only overdue.
@MainActor @Observable
final class LeitnerStore {
    static let shared = LeitnerStore()
    nonisolated static let intervals = [1, 2, 4, 8, 16]

    private(set) var boxes: [LeitnerBox] = []
    private(set) var log: [(date: String, box: String, word: String, knew: Bool)] = []
    /// The least number of words to review each day (there is no upper limit)
    var dailyGoal: Int { didSet { UserDefaults.standard.set(dailyGoal, forKey: "leitner.dailyGoal") } }
    let folder: URL

    private var logURL: URL { folder.appendingPathComponent("review-log.csv") }

    init(folder: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.folder = folder ?? support.appendingPathComponent("Orbit/Leitner", isDirectory: true)
        let goal = UserDefaults.standard.integer(forKey: "leitner.dailyGoal")
        dailyGoal = goal > 0 ? goal : 10
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        load()
    }

    // MARK: Dates (days are "yyyy-MM-dd" so they sort and compare as text)

    static var today: String { Cal.dayKey(Date()) }

    static func date(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Cal.gregorian.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    static func addDays(_ key: String, _ n: Int) -> String {
        guard let d = date(key), let r = Cal.gregorian.date(byAdding: .day, value: n, to: d) else { return key }
        return Cal.dayKey(r)
    }

    /// How many days a word is late (0 = due today, negative = not due yet)
    static func daysLate(_ card: LeitnerCard) -> Int {
        guard let due = date(card.due), let now = date(today) else { return 0 }
        return Cal.gregorian.dateComponents([.day], from: due, to: now).day ?? 0
    }

    // MARK: Queries

    func box(_ name: String?) -> LeitnerBox? { boxes.first { $0.name == name } }

    /// Words to review now: the latest ones first (the most overdue), then by section
    func due(in name: String) -> [LeitnerCard] {
        (box(name)?.cards ?? []).filter { !$0.isLearned && $0.due <= Self.today }
            .sorted { ($0.due, $0.box, $0.word) < ($1.due, $1.box, $1.word) }
    }

    /// Words that are not due yet, soonest first (for studying more than the day asks)
    func ahead(in name: String) -> [LeitnerCard] {
        (box(name)?.cards ?? []).filter { !$0.isLearned && $0.due > Self.today }
            .sorted { ($0.due, $0.box, $0.word) < ($1.due, $1.box, $1.word) }
    }

    func learned(in name: String) -> [LeitnerCard] {
        (box(name)?.cards ?? []).filter(\.isLearned).sorted { ($1.lastReview, $0.word) < ($0.lastReview, $1.word) }
    }

    // MARK: Spelling practice (its own little Leitner box inside each box)

    enum SpellingFilter: Hashable {
        case spellingDue, reviewedToday, learnedToday, vocabSection(Int), spellSection(Int), all
    }

    private(set) var spellLog: [(date: String, box: String, word: String, ok: Bool)] = []
    private var spellLogURL: URL { folder.appendingPathComponent("spelling-log.csv") }
    var spelledToday: Int { spellLog.filter { $0.date == Self.today }.count }

    /// A word spelled right today has had its spelling turn for today: it moves up once a day, not every round
    func spelledRightToday(_ box: String, _ word: String) -> Bool {
        spellLog.contains { $0.date == Self.today && $0.box == box && $0.word.lowercased() == word.lowercased() && $0.ok }
    }

    /// Words to practise by ear, for a chosen group
    func spellingCards(in name: String, _ f: SpellingFilter) -> [LeitnerCard] {
        let cards = box(name)?.cards ?? []
        switch f {
        case .spellingDue: return cards.filter { !$0.spellLearned && ($0.spellDue.isEmpty || $0.spellDue <= Self.today) }
        case .reviewedToday:
            let words = Set(log.filter { $0.date == Self.today && $0.box == name }.map { $0.word.lowercased() })
            return cards.filter { words.contains($0.word.lowercased()) && !spelledRightToday(name, $0.word) }
        case .learnedToday:
            // answered right today, so they moved up a section
            let words = Set(log.filter { $0.date == Self.today && $0.box == name && $0.knew }.map { $0.word.lowercased() })
            return cards.filter { words.contains($0.word.lowercased()) && !spelledRightToday(name, $0.word) }
        case .vocabSection(let s): return cards.filter { $0.box == s }
        case .spellSection(let s): return cards.filter { $0.spellBox == s }
        case .all: return cards
        }
    }

    /// One spelled word: right → up a spelling section (after 5: learned), wrong → back to spelling section 1
    func spellingReview(_ cardID: UUID, in name: String, correct: Bool) {
        let today = Self.today
        var word = ""
        // already spelled right earlier today: writing it right again is practice, it doesn't move up a second time
        let again = correct && (box(name)?.cards.first { $0.id == cardID }).map { spelledRightToday(name, $0.word) } == true
        update(cardID, in: name) { c in
            word = c.word
            if again { return }
            c.spellReviews += 1
            c.spellLast = today
            if correct {
                c.spellBox += 1
                if c.spellBox > Self.intervals.count { c.spellBox = LeitnerCard.learned; c.spellDue = "" }
                else { c.spellDue = Self.addDays(today, Self.intervals[c.spellBox - 1]) }
            } else {
                c.spellMistakes += 1
                c.spellBox = 1
                c.spellDue = Self.addDays(today, Self.intervals[0])
            }
        }
        spellLog.append((today, name, word, correct))
        let line = [today, name, word, correct ? "right" : "wrong"].map(Self.esc).joined(separator: ",") + "\n"
        if !FileManager.default.fileExists(atPath: spellLogURL.path) { try? "date,box,word,result\n".write(to: spellLogURL, atomically: true, encoding: .utf8) }
        if let h = try? FileHandle(forWritingTo: spellLogURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    }

    var totalDue: Int { boxes.reduce(0) { $0 + due(in: $1.name).count } }
    var reviewedToday: Int { log.filter { $0.date == Self.today }.count }
    func reviewedPerDay() -> [String: Int] { Dictionary(log.map { ($0.date, 1) }, uniquingKeysWith: +) }

    // MARK: Boxes

    @discardableResult
    func createBox(_ rawName: String) -> String? {
        let name = Self.safeName(rawName)
        guard !name.isEmpty, !boxes.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return nil }
        boxes.append(LeitnerBox(name: name))
        boxes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save(name)
        return name
    }

    func renameBox(_ old: String, to rawName: String) -> Bool {
        let name = Self.safeName(rawName)
        guard let i = boxes.firstIndex(where: { $0.name == old }), !name.isEmpty,
              !boxes.contains(where: { $0.name.lowercased() == name.lowercased() && $0.name != old }) else { return false }
        try? FileManager.default.moveItem(at: url(old), to: url(name))
        boxes[i].name = name
        boxes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return true
    }

    // MARK: Topics
    //
    // A topic is a general subject with small boxes inside it. It needs no file of its own: a box named "Topic › Box"
    // sits in the topic "Topic", so every box keeps working exactly as before (own CSV, own sections, own review).

    static let topicSeparator = " › "

    static func parts(_ name: String) -> (topic: String?, title: String) {
        if let r = name.range(of: topicSeparator) { return (String(name[..<r.lowerBound]), String(name[r.upperBound...])) }
        return (nil, name)
    }

    var topics: [String] {
        Array(Set(boxes.compactMap { Self.parts($0.name).topic })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Puts a box inside a topic (or takes it out with nil). Returns the box's new name
    @discardableResult
    func moveBox(_ name: String, toTopic topic: String?) -> String? {
        let title = Self.parts(name).title
        let t = topic.map { $0.replacingOccurrences(of: "›", with: "-").trimmingCharacters(in: .whitespaces) } ?? ""
        let newName = t.isEmpty ? title : t + Self.topicSeparator + title
        guard newName != name, renameBox(name, to: newName) else { return nil }
        NotificationCenter.default.post(name: .orbitDataSaved, object: nil)
        return Self.safeName(newName)
    }

    /// Makes a box a topic of its own: the box (with all its words) becomes the first small box inside it, named `sub`
    @discardableResult
    func putWordsInSubBox(of name: String, called sub: String) -> String? {
        let s = sub.replacingOccurrences(of: "›", with: "-").trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, Self.parts(name).topic == nil else { return nil }
        guard renameBox(name, to: name + Self.topicSeparator + s) else { return nil }
        NotificationCenter.default.post(name: .orbitDataSaved, object: nil)
        return Self.safeName(name + Self.topicSeparator + s)
    }

    @discardableResult
    func renameTopic(_ old: String, to new: String) -> Bool {
        var any = false
        for b in boxes where Self.parts(b.name).topic == old { if moveBox(b.name, toTopic: new) != nil { any = true } }
        return any
    }

    func deleteBox(_ name: String) {
        try? FileManager.default.trashItem(at: url(name), resultingItemURL: nil)
        boxes.removeAll { $0.name == name }
        NotificationCenter.default.post(name: .orbitDataSaved, object: nil)
    }

    func url(_ name: String) -> URL { folder.appendingPathComponent("\(name).csv") }

    private static func safeName(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    // MARK: Words

    /// Add words from lines like "word - meaning", "word, meaning" or "word<tab>meaning". Returns (added, already there)
    @discardableResult
    func addWords(_ text: String, to name: String) -> (added: Int, skipped: Int) {
        guard let i = boxes.firstIndex(where: { $0.name == name }) else { return (0, 0) }
        var have = Set(boxes[i].cards.map { $0.word.lowercased() })
        var added = 0, skipped = 0
        for line in text.split(whereSeparator: \.isNewline) {
            var (word, meaning) = Self.split(String(line))
            guard !word.isEmpty else { continue }
            word = word.prefix(1).uppercased() + word.dropFirst()   // the first letter is always a capital
            if have.contains(word.lowercased()) { skipped += 1; continue }
            have.insert(word.lowercased())
            // no meaning typed: take it from the dictionary built into the Mac
            boxes[i].cards.append(LeitnerCard(word: word, meaning: meaning.isEmpty ? (LeitnerDictionary.define(word) ?? "") : meaning, added: Self.today, due: Self.today, pos: LeitnerDictionary.partOfSpeech(word) ?? ""))
            added += 1
        }
        if added > 0 { save(name) }
        return (added, skipped)
    }

    static func split(_ line: String) -> (String, String) {
        for sep in ["\t", " - ", " – ", " — ", ",", "،", ":"] {
            if let r = line.range(of: sep) {
                return (String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces), String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
        }
        return (line.trimmingCharacters(in: .whitespaces), "")
    }

    /// Fill every empty meaning of a box from the Mac's dictionary. Returns (filled, not found)
    @discardableResult
    func fillMeanings(in name: String) -> (filled: Int, missing: Int) {
        guard let i = boxes.firstIndex(where: { $0.name == name }) else { return (0, 0) }
        var filled = 0, missing = 0
        var changed = false
        for j in boxes[i].cards.indices {
            if boxes[i].cards[j].pos.isEmpty, let p = LeitnerDictionary.partOfSpeech(boxes[i].cards[j].word) { boxes[i].cards[j].pos = p; changed = true }
            if boxes[i].cards[j].meaning.isEmpty {
                if let m = LeitnerDictionary.define(boxes[i].cards[j].word) { boxes[i].cards[j].meaning = m; filled += 1; changed = true } else { missing += 1 }
            }
        }
        if changed { save(name) }
        return (filled, missing)
    }

    func update(_ cardID: UUID, in name: String, _ change: (inout LeitnerCard) -> Void) {
        guard let i = boxes.firstIndex(where: { $0.name == name }), let j = boxes[i].cards.firstIndex(where: { $0.id == cardID }) else { return }
        change(&boxes[i].cards[j])
        save(name)
    }

    func delete(_ cardID: UUID, in name: String) {
        guard let i = boxes.firstIndex(where: { $0.name == name }) else { return }
        boxes[i].cards.removeAll { $0.id == cardID }
        save(name)
    }

    /// Put a word in a section (1…5) by hand, or mark it learned (6)
    func move(_ cardID: UUID, in name: String, toSection s: Int) {
        update(cardID, in: name) { c in
            c.box = s
            c.due = s == LeitnerCard.learned ? "" : Self.addDays(Self.today, s == 1 ? 0 : Self.intervals[s - 1])
            if s == LeitnerCard.learned && c.lastReview.isEmpty { c.lastReview = Self.today }
        }
    }

    /// One review: right → up a section (after 5: learned), wrong → back to section 1
    func review(_ cardID: UUID, in name: String, knew: Bool) {
        let today = Self.today
        var word = ""
        update(cardID, in: name) { c in
            word = c.word
            c.reviews += 1
            c.lastReview = today
            if knew {
                c.box += 1
                if c.box > Self.intervals.count { c.box = LeitnerCard.learned; c.due = "" }
                else { c.due = Self.addDays(today, Self.intervals[c.box - 1]) }
            } else {
                c.mistakes += 1
                c.box = 1
                c.due = Self.addDays(today, Self.intervals[0])
            }
        }
        log.append((today, name, word, knew))
        appendLog(today, name, word, knew)
    }

    // MARK: CSV

    private static let header = "box,word,meaning,added,last_review,due,reviews,mistakes,spelling_box,spelling_due,spelling_last,spelling_reviews,spelling_mistakes,type"

    private static func esc(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// Rows sorted by section (1 … 5, then learned), so the file reads like the box
    private func save(_ name: String) {
        guard let b = box(name) else { return }
        var out = Self.header + "\n"
        for c in b.cards.sorted(by: { ($0.box, $0.due, $0.word.lowercased()) < ($1.box, $1.due, $1.word.lowercased()) }) {
            let cols = [c.isLearned ? "learned" : String(c.box), c.word, c.meaning, c.added, c.lastReview, c.due, String(c.reviews), String(c.mistakes),
                        c.spellLearned ? "learned" : String(c.spellBox), c.spellDue, c.spellLast, String(c.spellReviews), String(c.spellMistakes), c.pos]
            out += cols.map(Self.esc).joined(separator: ",") + "\n"
        }
        try? out.write(to: url(name), atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .orbitDataSaved, object: nil)
    }

    private func appendLog(_ date: String, _ box: String, _ word: String, _ knew: Bool) {
        let line = [date, box, word, knew ? "knew" : "missed"].map(Self.esc).joined(separator: ",") + "\n"
        if !FileManager.default.fileExists(atPath: logURL.path) { try? "date,box,word,result\n".write(to: logURL, atomically: true, encoding: .utf8) }
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        NotificationCenter.default.post(name: .orbitDataSaved, object: nil)
    }

    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// One-time fix: before one-move-a-day, a word spelled right in several rounds on the same day moved up each time.
    /// Words that were right 2+ times today and never wrong go back to the section they should have reached (Spelling 2).
    private func repairDoublePromotions() {
        let flag = "spell.repair.\(Self.today)"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        for i in boxes.indices {
            var changed = false
            for j in boxes[i].cards.indices {
                let c = boxes[i].cards[j]
                let mine = spellLog.filter { $0.date == Self.today && $0.box == boxes[i].name && $0.word.lowercased() == c.word.lowercased() }
                let rights = mine.filter(\.ok).count
                if rights >= 2, !mine.contains(where: { !$0.ok }), c.spellBox == 1 + rights, c.spellBox > 2 {
                    boxes[i].cards[j].spellBox = 2
                    boxes[i].cards[j].spellDue = Self.addDays(Self.today, Self.intervals[1])
                    changed = true
                }
            }
            if changed { save(boxes[i].name) }
        }
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        boxes = files.filter { $0.pathExtension.lowercased() == "csv" && !["review-log", "spelling-log"].contains($0.deletingPathExtension().lastPathComponent) }.map { f in
            var b = LeitnerBox(name: f.deletingPathExtension().lastPathComponent)
            let rows = Self.parseCSV((try? String(contentsOf: f, encoding: .utf8)) ?? "")
            for r in rows.dropFirst() where r.count >= 2 {
                func col(_ i: Int) -> String { i < r.count ? r[i] : "" }
                let section = col(0).lowercased() == "learned" ? LeitnerCard.learned : min(5, max(1, Int(col(0)) ?? 1))
                let added = col(3).isEmpty ? Self.today : col(3)
                b.cards.append(LeitnerCard(word: col(1), meaning: col(2), box: section, added: added, lastReview: col(4),
                                           due: section == LeitnerCard.learned ? "" : (col(5).isEmpty ? Self.today : col(5)),
                                           reviews: Int(col(6)) ?? 0, mistakes: Int(col(7)) ?? 0,
                                           spellBox: col(8).lowercased() == "learned" ? LeitnerCard.learned : min(5, max(1, Int(col(8)) ?? 1)),
                                           spellDue: col(9), spellLast: col(10), spellReviews: Int(col(11)) ?? 0, spellMistakes: Int(col(12)) ?? 0, pos: col(13)))
            }
            return b
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let rows = Self.parseCSV((try? String(contentsOf: logURL, encoding: .utf8)) ?? "")
        log = rows.dropFirst().compactMap { r in r.count >= 4 ? (r[0], r[1], r[2], r[3] == "knew") : nil }
        // words saved before the kind of word existed get it from the dictionary (once)
        for i in boxes.indices {
            var changed = false
            for j in boxes[i].cards.indices where boxes[i].cards[j].pos.isEmpty {
                if let p = LeitnerDictionary.partOfSpeech(boxes[i].cards[j].word) { boxes[i].cards[j].pos = p; changed = true }
            }
            if changed { save(boxes[i].name) }
        }
        let srows = Self.parseCSV((try? String(contentsOf: spellLogURL, encoding: .utf8)) ?? "")
        spellLog = srows.dropFirst().compactMap { r in r.count >= 4 ? (r[0], r[1], r[2], r[3] == "right") : nil }
        repairDoublePromotions()
    }

    // MARK: Phone sync

    private static func cardKey(_ box: String, _ word: String) -> String { "\(box)|\(word.lowercased())" }

    /// The words and review log as plain data for the phone sync
    func exportSync() -> (boxes: [[String: Any]], cards: [[String: Any]], log: [[String: Any]]) {
        let boxList = boxes.map { ["id": $0.name] as [String: Any] }
        var cards: [[String: Any]] = []
        for b in boxes {
            for c in b.cards {
                cards.append(["id": Self.cardKey(b.name, c.word), "box": b.name, "word": c.word, "meaning": c.meaning, "section": c.box,
                              "added": c.added, "lastReview": c.lastReview, "due": c.due, "reviews": c.reviews, "mistakes": c.mistakes,
                              "spellBox": c.spellBox, "spellDue": c.spellDue, "spellLast": c.spellLast, "spellReviews": c.spellReviews,
                              "spellMistakes": c.spellMistakes, "pos": c.pos])
            }
        }
        var seen: [String: Int] = [:]
        let rows: [[String: Any]] = log.map { e in
            let base = "\(e.date)|\(e.box)|\(e.word.lowercased())|\(e.knew ? 1 : 0)"
            let k = seen[base, default: 0]; seen[base] = k + 1
            return ["id": "\(base)|\(k)", "date": e.date, "box": e.box, "word": e.word, "knew": e.knew]
        }
        return (boxList, cards, rows)
    }

    /// Takes the merged words from the phone: rewrites the boxes that changed, the log, and removes boxes deleted elsewhere
    func applySync(boxes names: [[String: Any]], cards: [[String: Any]], log rows: [[String: Any]]) {
        let wanted = names.compactMap { $0["id"] as? String }
        var byBox: [String: [LeitnerCard]] = [:]
        for name in wanted { byBox[name] = [] }
        let old = Dictionary(uniqueKeysWithValues: boxes.flatMap { b in b.cards.map { (Self.cardKey(b.name, $0.word), $0) } })
        for d in cards {
            guard let box = d["box"] as? String, let word = d["word"] as? String, byBox[box] != nil else { continue }
            var c = old[Self.cardKey(box, word)] ?? LeitnerCard(word: word, meaning: "", added: Self.today, due: Self.today)
            c.word = word
            c.meaning = d["meaning"] as? String ?? ""
            c.box = d["section"] as? Int ?? 1
            c.added = d["added"] as? String ?? c.added
            c.lastReview = d["lastReview"] as? String ?? ""
            c.due = d["due"] as? String ?? ""
            c.reviews = d["reviews"] as? Int ?? 0
            c.mistakes = d["mistakes"] as? Int ?? 0
            c.spellBox = d["spellBox"] as? Int ?? 1
            c.spellDue = d["spellDue"] as? String ?? ""
            c.spellLast = d["spellLast"] as? String ?? ""
            c.spellReviews = d["spellReviews"] as? Int ?? 0
            c.spellMistakes = d["spellMistakes"] as? Int ?? 0
            c.pos = d["pos"] as? String ?? ""
            byBox[box, default: []].append(c)
        }
        let before = self.boxes
        var result: [LeitnerBox] = []
        for name in wanted {
            let cardsHere = (byBox[name] ?? []).sorted { ($0.box, $0.due, $0.word.lowercased()) < ($1.box, $1.due, $1.word.lowercased()) }
            result.append(LeitnerBox(name: name, cards: cardsHere))
        }
        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for b in before where !wanted.contains(b.name) { try? FileManager.default.trashItem(at: url(b.name), resultingItemURL: nil) }
        func sameCards(_ a: [LeitnerCard], _ b: [LeitnerCard]) -> Bool {
            a.count == b.count && zip(a.sorted { $0.word < $1.word }, b.sorted { $0.word < $1.word }).allSatisfy { $0.word == $1.word && $0.meaning == $1.meaning && $0.box == $1.box && $0.due == $1.due && $0.lastReview == $1.lastReview && $0.reviews == $1.reviews && $0.mistakes == $1.mistakes && $0.spellBox == $1.spellBox && $0.spellDue == $1.spellDue && $0.pos == $1.pos }
        }
        boxes = result
        for b in result where !(before.first { $0.name == b.name }.map { sameCards($0.cards, b.cards) } ?? false) { save(b.name) }
        let newLog = rows.compactMap { d -> (date: String, box: String, word: String, knew: Bool)? in
            guard let date = d["date"] as? String, let box = d["box"] as? String, let word = d["word"] as? String else { return nil }
            return (date, box, word, (d["knew"] as? Bool) ?? ((d["knew"] as? Int ?? 0) != 0))
        }.sorted { ($0.date, $0.box, $0.word) < ($1.date, $1.box, $1.word) }
        if newLog.count != self.log.count {
            self.log = newLog
            var out = "date,box,word,result\n"
            for e in newLog { out += [e.date, e.box, e.word, e.knew ? "knew" : "missed"].map(Self.esc).joined(separator: ",") + "\n" }
            try? out.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    /// Show a box's CSV in Finder
    func reveal(_ name: String) { NSWorkspace.shared.activateFileViewerSelecting([url(name)]) }
}

/// Spelling help while adding words: uses the spell checker built into macOS (offline)
@MainActor
enum LeitnerSpell {
    /// Suggestions for a misspelled word or phrase (best first, maybe none), or nil when it looks right
    static func options(_ word: String) -> [String]? {
        let sc = NSSpellChecker.shared
        let tokens = word.split(separator: " ").map(String.init)
        var fixed: [String] = [], alts: [String] = [], bad = false
        for t in tokens {
            // only plain English words: numbers, symbols and other alphabets are left alone
            guard t.range(of: #"^[A-Za-z'’-]+$"#, options: .regularExpression) != nil else { fixed.append(t); continue }
            let r = sc.checkSpelling(of: t, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            if r.location != NSNotFound {
                bad = true
                let g = sc.guesses(forWordRange: NSRange(location: 0, length: (t as NSString).length), in: t, language: "en", inSpellDocumentWithTag: 0) ?? []
                fixed.append(g.first ?? t)
                if tokens.count == 1 { alts = Array(g.prefix(4)) }
            } else { fixed.append(t) }
        }
        guard bad else { return nil }
        let opts = tokens.count == 1 ? alts : [fixed.joined(separator: " ")]
        return opts.filter { $0.lowercased() != word.lowercased() }
    }
}
