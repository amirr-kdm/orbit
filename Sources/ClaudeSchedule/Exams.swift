import SwiftUI

/// One IELTS practice test: the band (0–9, steps of 0.5) of each skill. A skill can be left empty.
struct IELTSTest: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var date = Date()
    var listening: Double?
    var reading: Double?
    var writing: Double?
    var speaking: Double?
    var note = ""
    /// Which kind of test it is (Cambridge, Mocks, …); see IELTSCategory
    var categoryID: UUID?

    func band(_ s: IELTSSkill) -> Double? {
        switch s { case .listening: listening; case .reading: reading; case .writing: writing; case .speaking: speaking }
    }
    mutating func set(_ s: IELTSSkill, _ v: Double?) {
        switch s { case .listening: listening = v; case .reading: reading = v; case .writing: writing = v; case .speaking: speaking = v }
    }

    /// The overall band of this test: the average of the four skills, rounded the IELTS way (.25 → .5, .75 → next whole). Needs all four.
    var overall: Double? {
        guard let l = listening, let r = reading, let w = writing, let s = speaking else { return nil }
        return IELTSTest.roundBand((l + r + w + s) / 4)
    }

    static func roundBand(_ x: Double) -> Double {
        let f = floor(x), d = x - f
        return d < 0.25 ? f : (d < 0.75 ? f + 0.5 : f + 1)
    }
    static func format(_ b: Double?) -> String { b.map { String(format: "%.1f", $0) } ?? "—" }
}

/// A group of practice tests (Cambridge books, mock exams, a site you practise on…). You make your own; Cambridge and Mocks come first.
struct IELTSCategory: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    static let cambridgeID = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
    static let mocksID = UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!
    static let defaults = [IELTSCategory(id: cambridgeID, name: "Cambridge"), IELTSCategory(id: mocksID, name: "Mocks")]
}

enum IELTSSkill: String, CaseIterable, Identifiable {
    case listening, reading, writing, speaking
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// UserDefaults key of the band you want in this skill
    var targetKey: String { "ielts.target.\(rawValue)" }
    /// The band you want in this skill (7.0 until you set it)
    var target: Double { UserDefaults.standard.object(forKey: targetKey) as? Double ?? 7.0 }
    /// The overall band you get when every skill reaches its target (the four targets averaged, rounded the IELTS way)
    static var overallTarget: Double { IELTSTest.roundBand(allCases.map(\.target).reduce(0, +) / 4) }
    var icon: String {
        switch self { case .listening: "headphones"; case .reading: "book.fill"; case .writing: "pencil.line"; case .speaking: "mic.fill" }
    }
    var color: Color {
        switch self { case .listening: Color(hex: "#3FB6C8"); case .reading: Color(hex: "#6E8BD8"); case .writing: Color(hex: "#E8A33D"); case .speaking: Color(hex: "#E8384F") }
    }
}

extension AppStore {
    func upsertIELTS(_ t: IELTSTest) {
        if let i = ieltsTests.firstIndex(where: { $0.id == t.id }) { ieltsTests[i] = t } else { ieltsTests.append(t) }
    }
    func ieltsCategory(_ id: UUID?) -> IELTSCategory? { id.flatMap { i in ieltsCategories.first { $0.id == i } } }
    func addIELTSCategory(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !ieltsCategories.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { return }
        ieltsCategories.append(IELTSCategory(name: n))
    }
    func deleteIELTSCategory(_ id: UUID) {
        ieltsCategories.removeAll { $0.id == id }
        for i in ieltsTests.indices where ieltsTests[i].categoryID == id { ieltsTests[i].categoryID = nil }
    }
    func deleteIELTS(_ id: UUID) { ieltsTests.removeAll { $0.id == id } }

    /// Newest first
    var ieltsByDate: [IELTSTest] { ieltsTests.sorted { $0.date > $1.date } }

    /// Average band of one skill over all tests that have it
    func ieltsAverage(_ s: IELTSSkill) -> Double? {
        let v = ieltsTests.compactMap { $0.band(s) }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    /// Your overall band now: the average of each skill over all tests, then the four averaged and rounded like IELTS does.
    /// Needs at least one score for every skill.
    var ieltsOverall: Double? {
        let a = IELTSSkill.allCases.compactMap { ieltsAverage($0) }
        guard a.count == 4 else { return nil }
        return IELTSTest.roundBand(a.reduce(0, +) / 4)
    }
}
