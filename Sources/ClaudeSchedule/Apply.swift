import SwiftUI

// MARK: - Apply: universities and programs you apply to

enum ApplyStatus: String, Codable, CaseIterable, Identifiable {
    case considering, preparing, submitted, interview, waitlisted, accepted, rejected, withdrawn
    var id: String { rawValue }
    var title: String {
        switch self {
        case .considering: "Considering"
        case .preparing: "Preparing"
        case .submitted: "Submitted"
        case .interview: "Interview"
        case .waitlisted: "Waitlisted"
        case .accepted: "Accepted"
        case .rejected: "Rejected"
        case .withdrawn: "Withdrawn"
        }
    }
    var icon: String {
        switch self {
        case .considering: "lightbulb.fill"
        case .preparing: "hammer.fill"
        case .submitted: "paperplane.fill"
        case .interview: "person.2.wave.2.fill"
        case .waitlisted: "hourglass"
        case .accepted: "checkmark.seal.fill"
        case .rejected: "xmark.octagon.fill"
        case .withdrawn: "arrow.uturn.backward.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .considering: Color(hex: "#8E9BB5")
        case .preparing: Color(hex: "#E8A33D")
        case .submitted: Color(hex: "#3F7FE0")
        case .interview: Color(hex: "#8E6BD8")
        case .waitlisted: Color(hex: "#3FB6C8")
        case .accepted: Color(hex: "#34C77B")
        case .rejected: Color(hex: "#E8384F")
        case .withdrawn: Color(hex: "#7A7F8C")
        }
    }
    /// Still moving: you can still do something about it
    var isOpen: Bool { [.considering, .preparing].contains(self) }
    /// Finished one way or the other
    var isClosed: Bool { [.accepted, .rejected, .withdrawn].contains(self) }
}

enum ApplyDegree: String, Codable, CaseIterable, Identifiable {
    case bachelor, master, phd, other
    var id: String { rawValue }
    var title: String { switch self { case .bachelor: "Bachelor"; case .master: "Master"; case .phd: "PhD"; case .other: "Other" } }
    /// Usual length in months, as a starting point
    var usualMonths: Int { switch self { case .bachelor: 36; case .master: 24; case .phd: 48; case .other: 12 } }
}

enum ApplyTier: String, Codable, CaseIterable, Identifiable {
    case none, reach, match, safety
    var id: String { rawValue }
    var title: String { switch self { case .none: "No tier"; case .reach: "Reach"; case .match: "Match"; case .safety: "Safety" } }
    var color: Color { switch self { case .none: .gray; case .reach: Color(hex: "#E8384F"); case .match: Color(hex: "#E8A33D"); case .safety: Color(hex: "#34C77B") } }
    var hint: String {
        switch self {
        case .none: "Not decided"
        case .reach: "A dream: harder to get in"
        case .match: "A good fit for your level"
        case .safety: "Very likely to get in"
        }
    }
}

enum ApplyFunding: String, Codable, CaseIterable, Identifiable {
    case unknown, funded, partial, selfFunded
    var id: String { rawValue }
    var title: String { switch self { case .unknown: "Unknown"; case .funded: "Fully funded"; case .partial: "Partly funded"; case .selfFunded: "Self-funded" } }
    var short: String { switch self { case .unknown: "Funding ?"; case .funded: "Funded"; case .partial: "Partial"; case .selfFunded: "Self-funded" } }
    var icon: String { switch self { case .unknown: "questionmark.circle"; case .funded: "banknote.fill"; case .partial: "banknote"; case .selfFunded: "creditcard.fill" } }
    var color: Color { switch self { case .unknown: .gray; case .funded: Color(hex: "#34C77B"); case .partial: Color(hex: "#E8A33D"); case .selfFunded: Color(hex: "#E8384F") } }
}

/// An extra date for one program: a scholarship deadline, the date letters are due, …
struct ApplyDeadline: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var date: Date
    var done = false
}

/// One thing to prepare for a program (a document, a form, a payment)
struct ApplyDoc: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var done = false
    var note = ""
    var due: Date?
}

enum ApplySeason: String, Codable, CaseIterable, Identifiable {
    case fall, spring, winter, summer, other
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String { switch self { case .fall: "leaf.fill"; case .spring: "camera.macro"; case .winter: "snowflake"; case .summer: "sun.max.fill"; case .other: "calendar" } }
    var color: Color { switch self { case .fall: Color(hex: "#E8793D"); case .spring: Color(hex: "#34C77B"); case .winter: Color(hex: "#3FB6C8"); case .summer: Color(hex: "#E8C33D"); case .other: .gray } }
}

/// One intake (entry term) of a program, with its own dates: many universities take students twice a year (spring and fall)
struct ApplyIntake: Identifiable, Codable, Hashable {
    var id = UUID()
    var season: ApplySeason = .fall
    var year = Cal.gregorian.component(.year, from: Date()) + 1
    var opens: Date?
    var closes: Date?
    var decision: Date?
    /// The day the course starts
    var start: Date?
    var note = ""

    var label: String { "\(season.title) \(year)" }

    init() {}
    init(season: ApplySeason, year: Int) { self.season = season; self.year = year }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.d(.id, UUID()); season = c.d(.season, .fall); year = c.d(.year, Cal.gregorian.component(.year, from: Date()) + 1)
        opens = c.d(.opens, nil as Date?); closes = c.d(.closes, nil as Date?); decision = c.d(.decision, nil as Date?); start = c.d(.start, nil as Date?)
        note = c.d(.note, "")
    }
}


// MARK: Requirements and professors

enum ApplyReqState: String, Codable, CaseIterable, Identifiable {
    case unknown, met, notMet
    var id: String { rawValue }
    var title: String { switch self { case .unknown: "Not checked"; case .met: "I meet it"; case .notMet: "I don't meet it yet" } }
    var icon: String { switch self { case .unknown: "questionmark.circle"; case .met: "checkmark.circle.fill"; case .notMet: "exclamationmark.triangle.fill" } }
    var color: Color { switch self { case .unknown: .gray; case .met: Color(hex: "#34C77B"); case .notMet: Color(hex: "#E8A33D") } }
    var next: ApplyReqState { switch self { case .unknown: .met; case .met: .notMet; case .notMet: .unknown } }
}

/// Anything a program asks for that is not a document: a minimum GPA, letters, GRE, work experience…
struct ApplyRequirement: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var value = ""
    var state: ApplyReqState = .unknown
    var note = ""

    /// Common ones, with a hint for the value
    static let presets: [(title: String, hint: String)] = [
        ("Minimum GPA", "e.g. 3.0 / 4.0 or 15 / 20"), ("Recommendation letters", "e.g. 2 (academic)"), ("GRE", "Required / optional / not needed"),
        ("GMAT", "Required / not needed"), ("TOEFL", "e.g. 90 iBT"), ("Work experience", "e.g. 2 years"), ("Research experience", "e.g. a thesis or a paper"),
        ("Publications", "Required / a plus"), ("Interview", "Required / maybe"), ("Portfolio", "What to include"), ("Writing sample", "Pages / topic"),
        ("Subject test", "Math, physics…"), ("Other language", "e.g. German B2"), ("Supervisor found before applying", "Yes / no"),
        ("Bachelor in a related field", "Which field"), ("Minimum credits (ECTS)", "e.g. 30 in math"), ("Age or time since graduation", "e.g. within 3 years")
    ]
}

enum ProfAccepting: String, Codable, CaseIterable, Identifiable {
    case unknown, yes, maybe, no
    var id: String { rawValue }
    var title: String { switch self { case .unknown: "Unknown"; case .yes: "Taking students"; case .maybe: "Maybe"; case .no: "Not taking" } }
    var icon: String { switch self { case .unknown: "questionmark.circle"; case .yes: "person.crop.circle.badge.checkmark"; case .maybe: "person.crop.circle.badge.questionmark"; case .no: "person.crop.circle.badge.xmark" } }
    var color: Color { switch self { case .unknown: .gray; case .yes: Color(hex: "#34C77B"); case .maybe: Color(hex: "#E8A33D"); case .no: Color(hex: "#E8384F") } }
}

enum ProfPriority: String, Codable, CaseIterable, Identifiable {
    case top, high, medium, low
    var id: String { rawValue }
    var title: String { switch self { case .top: "Top choice"; case .high: "High"; case .medium: "Medium"; case .low: "Low" } }
    var color: Color { switch self { case .top: Color(hex: "#E8384F"); case .high: Color(hex: "#E8A33D"); case .medium: Color(hex: "#3F7FE0"); case .low: .gray } }
    var rank: Int { switch self { case .top: 0; case .high: 1; case .medium: 2; case .low: 3 } }
    var stars: Int { 4 - rank }
}

enum ProfFunding: String, Codable, CaseIterable, Identifiable {
    case unknown, yes, maybe, no
    var id: String { rawValue }
    var title: String { switch self { case .unknown: "Funding unknown"; case .yes: "Has funding"; case .maybe: "Maybe funding"; case .no: "No funding" } }
    var icon: String { switch self { case .unknown: "questionmark.circle"; case .yes: "banknote.fill"; case .maybe: "banknote"; case .no: "nosign" } }
    var color: Color { switch self { case .unknown: .gray; case .yes: Color(hex: "#34C77B"); case .maybe: Color(hex: "#E8A33D"); case .no: Color(hex: "#E8384F") } }
}

enum ProfContact: String, Codable, CaseIterable, Identifiable {
    case notYet, emailed, replied, meeting, inProcess, positive, negative, noReply
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notYet: "Not contacted"; case .emailed: "Emailed"; case .replied: "Replied"; case .meeting: "Call / meeting"; case .inProcess: "In process"
        case .positive: "Positive answer"; case .negative: "Declined"; case .noReply: "No reply"
        }
    }
    var icon: String {
        switch self {
        case .notYet: "envelope"; case .emailed: "paperplane.fill"; case .replied: "arrowshape.turn.up.left.fill"; case .meeting: "video.fill"; case .inProcess: "gearshape.2.fill"
        case .positive: "hand.thumbsup.fill"; case .negative: "hand.thumbsdown.fill"; case .noReply: "clock.badge.questionmark"
        }
    }
    var color: Color {
        switch self {
        case .notYet: .gray; case .emailed: Color(hex: "#3F7FE0"); case .replied: Color(hex: "#3FB6C8"); case .meeting: Color(hex: "#8E6BD8"); case .inProcess: Color(hex: "#5B7CFA")
        case .positive: Color(hex: "#34C77B"); case .negative: Color(hex: "#E8384F"); case .noReply: Color(hex: "#E8A33D")
        }
    }
    /// Still waiting on something from you or them
    var needsFollowUp: Bool { [.notYet, .emailed, .noReply].contains(self) }
}

/// One email to or from a professor
struct ApplyEmail: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var sent = true
    var subject = ""
    var note = ""
}

struct ApplyProfessor: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var title = "Prof."
    var email = ""
    var website = ""
    var group = ""
    /// Research areas, separated by commas
    var research = ""
    /// What they offer: PhD, Master thesis, postdoc…
    var position = ""
    var accepting: ProfAccepting = .unknown
    var priority: ProfPriority = .medium
    var funding: ProfFunding = .unknown
    var fundingNote = ""
    var contact: ProfContact = .notYet
    var lastContact: Date?
    var followUp: Date?
    var emails: [ApplyEmail] = []
    var papers = ""
    var notes = ""
    var created = Date()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.d(.id, UUID()); name = c.d(.name, ""); title = c.d(.title, "Prof."); email = c.d(.email, ""); website = c.d(.website, "")
        group = c.d(.group, ""); research = c.d(.research, ""); position = c.d(.position, ""); accepting = c.d(.accepting, .unknown)
        priority = c.d(.priority, .medium); funding = c.d(.funding, .unknown); fundingNote = c.d(.fundingNote, ""); contact = c.d(.contact, .notYet)
        lastContact = c.d(.lastContact, nil as Date?); followUp = c.d(.followUp, nil as Date?); emails = c.d(.emails, [])
        papers = c.d(.papers, ""); notes = c.d(.notes, ""); created = c.d(.created, Date())
    }

    var displayName: String { name.isEmpty ? "Unnamed professor" : "\(title) \(name)".trimmingCharacters(in: .whitespaces) }
    var topics: [String] { research.split(whereSeparator: { ",;\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    var daysToFollowUp: Int? { followUp.map(ApplyProgram.daysUntil) }
}

struct ApplyProgram: Identifiable, Codable, Hashable {
    var id = UUID()
    var university = ""
    var program = ""
    var degree: ApplyDegree = .master
    var country = ""
    var city = ""
    var website = ""
    var portal = ""
    /// The university's place in the QS World University Rankings (1 = best)
    var qsRank: Int?
    var contactName = ""
    var contactEmail = ""

    var status: ApplyStatus = .considering
    var tier: ApplyTier = .none
    var starred = false

    // dates
    var intakes: [ApplyIntake] = []
    /// The intake you are applying for (nil: the program decides by the dates)
    var appliedIntake: UUID?
    var durationMonths: Int?
    var extraDeadlines: [ApplyDeadline] = []

    // money (all in `currency`)
    var currency = "USD"
    var fee: Double?
    var feePaid = false
    var funding: ApplyFunding = .unknown
    var fundingNote = ""
    var stipendPerMonth: Double?
    var tuitionPerYear: Double?
    var livingPerYear: Double?
    var otherPerYear: Double?

    // requirements
    var ieltsOverall: Double?
    var ieltsEachSkill: Double?
    var otherRequirements = ""
    var requirements: [ApplyRequirement] = []
    var professors: [ApplyProfessor] = []

    var docs: [ApplyDoc] = []
    var notes = ""
    var created = Date()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.d(.id, UUID()); university = c.d(.university, ""); program = c.d(.program, ""); degree = c.d(.degree, .master)
        country = c.d(.country, ""); city = c.d(.city, ""); website = c.d(.website, ""); portal = c.d(.portal, ""); qsRank = c.d(.qsRank, nil as Int?)
        contactName = c.d(.contactName, ""); contactEmail = c.d(.contactEmail, "")
        status = c.d(.status, .considering); tier = c.d(.tier, .none); starred = c.d(.starred, false)
        intakes = c.d(.intakes, []); appliedIntake = c.d(.appliedIntake, nil as UUID?)
        // older data kept one set of dates on the program itself: it becomes the first intake
        if intakes.isEmpty {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let o = c2(legacy, .opens), cl = c2(legacy, .closes), de = c2(legacy, .decision), ts = c2(legacy, .termStart)
            if o != nil || cl != nil || de != nil || ts != nil {
                var i = ApplyIntake(); i.opens = o; i.closes = cl; i.decision = de; i.start = ts
                let ref = ts ?? cl ?? o ?? Date(), m = Cal.gregorian.component(.month, from: ref)
                i.season = ts != nil ? (m >= 8 ? .fall : (m >= 5 ? .summer : .spring)) : .fall
                i.year = Cal.gregorian.component(.year, from: ref) + (ts == nil && m >= 6 ? 1 : 0)
                intakes = [i]
            }
        }
        durationMonths = c.d(.durationMonths, nil as Int?); extraDeadlines = c.d(.extraDeadlines, [])
        currency = c.d(.currency, "USD"); fee = c.d(.fee, nil as Double?); feePaid = c.d(.feePaid, false)
        funding = c.d(.funding, .unknown); fundingNote = c.d(.fundingNote, ""); stipendPerMonth = c.d(.stipendPerMonth, nil as Double?)
        tuitionPerYear = c.d(.tuitionPerYear, nil as Double?); livingPerYear = c.d(.livingPerYear, nil as Double?); otherPerYear = c.d(.otherPerYear, nil as Double?)
        ieltsOverall = c.d(.ieltsOverall, nil as Double?); ieltsEachSkill = c.d(.ieltsEachSkill, nil as Double?); otherRequirements = c.d(.otherRequirements, "")
        requirements = c.d(.requirements, []); professors = c.d(.professors, [])
        docs = c.d(.docs, []); notes = c.d(.notes, ""); created = c.d(.created, Date())
    }

    private enum LegacyKeys: String, CodingKey { case opens, closes, decision, termStart }
    private func c2(_ c: KeyedDecodingContainer<LegacyKeys>, _ k: LegacyKeys) -> Date? { try? c.decodeIfPresent(Date.self, forKey: k) }

    // MARK: derived

    /// The intake that counts now: the one you chose, else the next one to close, else the latest
    var focusIntake: ApplyIntake? {
        if let a = appliedIntake, let i = intakes.first(where: { $0.id == a }) { return i }
        let upcoming = intakes.filter { ($0.closes.map(Self.daysUntil) ?? -1) >= 0 }.sorted { $0.closes! < $1.closes! }
        if let u = upcoming.first { return u }
        return intakes.sorted { ($0.closes ?? .distantPast) > ($1.closes ?? .distantPast) }.first
    }
    var opens: Date? { focusIntake?.opens }
    var closes: Date? { focusIntake?.closes }
    var decision: Date? { focusIntake?.decision }
    var termStart: Date? { focusIntake?.start }

    var displayName: String { university.isEmpty ? "Untitled university" : university }
    var docsDone: Int { docs.filter(\.done).count }
    var progress: Double { docs.isEmpty ? 0 : Double(docsDone) / Double(docs.count) }

    var years: Double { Double(durationMonths ?? degree.usualMonths) / 12 }
    /// Cost of one year (tuition + living + other); nil when nothing is filled in
    var costPerYear: Double? {
        let parts = [tuitionPerYear, livingPerYear, otherPerYear].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }
    var costTotal: Double? { costPerYear.map { $0 * years } }

    /// Days from today to a date (negative: it passed)
    static func daysUntil(_ d: Date) -> Int {
        Cal.gregorian.dateComponents([.day], from: Cal.gregorian.startOfDay(for: Date()), to: Cal.gregorian.startOfDay(for: d)).day ?? 0
    }
    var daysToClose: Int? { closes.map(Self.daysUntil) }

    /// The next date that needs you: the next close (of the intake you chose, or of all intakes) or an extra deadline.
    /// Dates still ahead come first; if all have passed, the latest one.
    var nextDeadline: (label: String, date: Date)? {
        var list: [(String, Date)] = extraDeadlines.filter { !$0.done }.map { ($0.label.isEmpty ? "Deadline" : $0.label, $0.date) }
        if status.isOpen {
            let pool = appliedIntake.flatMap { a in intakes.first { $0.id == a } }.map { [$0] } ?? intakes
            for i in pool { if let c = i.closes { list.append(("\(i.label) closes", c)) } }
        }
        let ahead = list.filter { Self.daysUntil($0.1) >= 0 }
        if let n = ahead.min(by: { $0.1 < $1.1 }) { return (label: n.0, date: n.1) }
        return list.max { $0.1 < $1.1 }.map { (label: $0.0, date: $0.1) }
    }

    func matches(_ q: String) -> Bool {
        let q = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return ([university, program, country, city, notes, otherRequirements] + professors.map(\.name)).contains { $0.lowercased().contains(q) }
    }

    static func defaultDocs(for degree: ApplyDegree) -> [ApplyDoc] {
        var t = ["Passport", "CV / Résumé", "Statement of purpose", "Academic transcripts", "Degree certificate", "English test score (IELTS/TOEFL)",
                 "Recommendation letter 1", "Recommendation letter 2", "Application form", "Application fee paid"]
        switch degree {
        case .phd: t.insert(contentsOf: ["Research proposal", "Publications list"], at: 3)
        case .master: t.insert("Recommendation letter 3", at: 8)
        case .bachelor: t = ["Passport", "High school diploma", "Academic transcripts", "Motivation letter", "English test score (IELTS/TOEFL)", "Recommendation letter", "Application form", "Application fee paid"]
        case .other: break
        }
        return t.map { ApplyDoc(title: $0) }
    }

    /// Documents people often need, for the "Add" menu of the checklist
    static let commonDocs = ["Passport", "CV / Résumé", "Statement of purpose", "Motivation letter", "Research proposal", "Academic transcripts",
                             "Degree certificate", "English test score (IELTS/TOEFL)", "GRE score", "Recommendation letter 1", "Recommendation letter 2",
                             "Recommendation letter 3", "Portfolio", "Writing sample", "Publications list", "Bank statement (proof of funds)",
                             "Certified translations", "Photo", "Application form", "Application fee paid", "Visa application", "Housing"]
}

private extension KeyedDecodingContainer {
    func d<T: Decodable>(_ k: Key, _ def: T) -> T { (try? decodeIfPresent(T.self, forKey: k)) ?? def }
}

extension AppStore {
    func applyProgram(_ id: UUID?) -> ApplyProgram? { id.flatMap { i in applyPrograms.first { $0.id == i } } }
    func upsertApply(_ p: ApplyProgram) {
        if let i = applyPrograms.firstIndex(where: { $0.id == p.id }) { if applyPrograms[i] != p { applyPrograms[i] = p } } else { applyPrograms.append(p) }
    }
    func deleteApply(_ id: UUID) { applyPrograms.removeAll { $0.id == id } }
}

// MARK: - Countries, flags, money

enum ApplyWorld {
    /// Country name → ISO code (for the flag)
    static let countries: [String: String] = [
        "Germany": "DE", "Netherlands": "NL", "Canada": "CA", "United States": "US", "United Kingdom": "GB", "Australia": "AU", "Sweden": "SE",
        "Italy": "IT", "France": "FR", "Switzerland": "CH", "Austria": "AT", "Denmark": "DK", "Norway": "NO", "Finland": "FI", "Ireland": "IE",
        "Japan": "JP", "South Korea": "KR", "China": "CN", "Turkey": "TR", "Hungary": "HU", "Poland": "PL", "Spain": "ES", "Czech Republic": "CZ",
        "Belgium": "BE", "Malaysia": "MY", "United Arab Emirates": "AE", "Singapore": "SG", "New Zealand": "NZ", "Portugal": "PT", "Estonia": "EE",
        "Lithuania": "LT", "Latvia": "LV", "Luxembourg": "LU", "Greece": "GR", "Iceland": "IS", "Slovenia": "SI", "Slovakia": "SK", "Romania": "RO",
        "Qatar": "QA", "Saudi Arabia": "SA", "Hong Kong": "HK", "Taiwan": "TW", "India": "IN", "Russia": "RU", "Brazil": "BR", "Mexico": "MX",
        "South Africa": "ZA", "Georgia": "GE", "Armenia": "AM", "Cyprus": "CY", "Malta": "MT", "Croatia": "HR", "Serbia": "RS", "Iran": "IR"
    ]
    static var countryNames: [String] { countries.keys.sorted() }

    static func flag(_ country: String) -> String {
        let key = countries.first { $0.key.caseInsensitiveCompare(country.trimmingCharacters(in: .whitespaces)) == .orderedSame }?.value
            ?? (country.count == 2 ? country.uppercased() : nil)
        guard let code = key else { return "🌍" }
        return code.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map { String($0) }.joined()
    }

    /// Currencies with a rough value in US dollars. Only used to compare and add up amounts, so the numbers are approximate.
    static let currencies: [(code: String, symbol: String, usd: Double)] = [
        ("USD", "$", 1), ("EUR", "€", 1.08), ("GBP", "£", 1.27), ("CAD", "C$", 0.73), ("AUD", "A$", 0.65), ("CHF", "CHF", 1.12),
        ("SEK", "kr", 0.095), ("NOK", "kr", 0.093), ("DKK", "kr", 0.145), ("JPY", "¥", 0.0066), ("KRW", "₩", 0.00073), ("CNY", "¥", 0.138),
        ("TRY", "₺", 0.03), ("HUF", "Ft", 0.0027), ("PLN", "zł", 0.25), ("CZK", "Kč", 0.043), ("SGD", "S$", 0.74), ("NZD", "NZ$", 0.6),
        ("AED", "AED", 0.272), ("MYR", "RM", 0.22), ("IRR", "﷼", 0.0000024)
    ]
    static func usd(_ amount: Double, _ code: String) -> Double { amount * (currencies.first { $0.code == code }?.usd ?? 1) }
    static func symbol(_ code: String) -> String { currencies.first { $0.code == code }?.symbol ?? code }

    static func money(_ amount: Double?, _ code: String) -> String {
        guard let a = amount else { return "—" }
        let n = NumberFormatter(); n.numberStyle = .decimal; n.maximumFractionDigits = a < 100 && a != a.rounded() ? 2 : 0
        return "\(symbol(code))\(n.string(from: NSNumber(value: a)) ?? "\(a)")"
    }
    static func moneyUSD(_ amount: Double) -> String { money(amount, "USD").replacingOccurrences(of: "$", with: "≈ $") }

    static func countdown(_ days: Int) -> String {
        switch days {
        case ..<(-1): "\(-days) days overdue"
        case -1: "1 day overdue"
        case 0: "today"
        case 1: "tomorrow"
        default: "in \(days) days"
        }
    }
    static func urgencyColor(_ days: Int) -> Color { days < 0 ? Color(hex: "#E8384F") : (days <= 7 ? Color(hex: "#E8384F") : (days <= 30 ? Color(hex: "#E8A33D") : Color(hex: "#34C77B"))) }
}
