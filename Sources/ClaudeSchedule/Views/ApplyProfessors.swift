import SwiftUI
import AppKit

private let ap = Color(hex: "#8E6BD8")

/// Wraps its children onto new lines (for research-topic tags)
struct ChipFlow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

private func initials(_ name: String) -> String {
    let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
    return parts.isEmpty ? "?" : String(parts).uppercased()
}

// MARK: - Card

struct ProfessorCard: View {
    let program: ApplyProgram
    let prof: ApplyProfessor
    var showUniversity = false
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        let f = prof
        Button(action: open) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 12) {
                    Text(initials(f.name)).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 46, height: 46).background(Circle().fill(LinearGradient(colors: [f.priority.color, f.priority.color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.displayName).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1)
                        if !f.group.isEmpty { Text(f.group).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                        if showUniversity {
                            Text("\(ApplyWorld.flag(program.country)) \(program.displayName)").font(.caption.weight(.semibold)).foregroundStyle(ap).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 1) {
                            ForEach(0..<4, id: \.self) { i in Image(systemName: i < f.priority.stars ? "star.fill" : "star").font(.system(size: 9)).foregroundStyle(i < f.priority.stars ? f.priority.color : Color.secondary.opacity(0.3)) }
                        }
                        Text(f.priority.title).font(.caption2.weight(.bold)).foregroundStyle(f.priority.color)
                    }
                }
                if !f.topics.isEmpty {
                    ChipFlow(spacing: 5) {
                        ForEach(f.topics.prefix(6), id: \.self) { t in
                            Text(t).font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(ap.opacity(0.15))).foregroundStyle(ap)
                        }
                    }
                }
                ChipFlow(spacing: 6) {
                    ApplyChip(icon: f.accepting.icon, text: f.accepting.title, color: f.accepting.color)
                    ApplyChip(icon: f.funding.icon, text: f.funding.title, color: f.funding.color)
                    if !f.position.isEmpty { ApplyChip(icon: "briefcase.fill", text: f.position, color: Color(hex: "#3F7FE0")) }
                }
                Divider().opacity(0.5)
                ChipFlow(spacing: 8) {
                    Label(f.contact.title, systemImage: f.contact.icon).font(.caption.weight(.bold))
                        .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(f.contact.color.opacity(0.16))).foregroundStyle(f.contact.color)
                    if let d = f.lastContact { Text("last \(Fmt.date(d, "MMM d", .gregorian))").font(.caption).foregroundStyle(.secondary) }
                    if let days = f.daysToFollowUp, f.contact.needsFollowUp {
                        let c = ApplyWorld.urgencyColor(days)
                        Label("Follow up \(ApplyWorld.countdown(days))", systemImage: "bell.fill").font(.caption.weight(.bold)).foregroundStyle(c)
                    }
                }
                if !f.email.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope").font(.caption).foregroundStyle(.secondary)
                        Text(f.email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [f.priority.color.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center))))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(f.contact.color.opacity(hover ? 0.7 : 0.22), lineWidth: hover ? 2 : 1))
            .shadow(color: .black.opacity(hover ? 0.22 : 0.07), radius: hover ? 10 : 3, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Row (list mode)

struct ProfessorRow: View {
    let program: ApplyProgram
    let prof: ApplyProfessor
    var showUniversity = false
    var compact = false
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        let f = prof
        Button(action: open) {
            Group { if compact { compactBody } else { wideBody } }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(f.contact.color).frame(width: 4).padding(.vertical, 8) }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(f.contact.color.opacity(hover ? 0.6 : 0.15)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var compactBody: some View {
        let f = prof
        return HStack(alignment: .top, spacing: 10) {
            Text(initials(f.name)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(Circle().fill(f.priority.color.gradient))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(f.displayName).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1)
                    Spacer(minLength: 6)
                    HStack(spacing: 1) {
                        ForEach(0..<4, id: \.self) { i in Image(systemName: i < f.priority.stars ? "star.fill" : "star").font(.system(size: 8)).foregroundStyle(i < f.priority.stars ? f.priority.color : Color.secondary.opacity(0.3)) }
                    }
                }
                Text(showUniversity ? "\(ApplyWorld.flag(program.country)) \(program.displayName)" : (f.group.isEmpty ? "—" : f.group))
                    .font(.caption).foregroundStyle(showUniversity ? ap : Color.secondary).lineLimit(1)
                if !f.topics.isEmpty { Text(f.topics.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                ChipFlow(spacing: 6) {
                    ApplyChip(icon: f.accepting.icon, text: f.accepting.title, color: f.accepting.color)
                    ApplyChip(icon: f.funding.icon, text: f.funding.title, color: f.funding.color)
                    ApplyChip(icon: f.contact.icon, text: f.contact.title, color: f.contact.color)
                    if let days = f.daysToFollowUp, f.contact.needsFollowUp { ApplyChip(icon: "bell.fill", text: "Follow up \(ApplyWorld.countdown(days))", color: ApplyWorld.urgencyColor(days)) }
                }
            }
        }
    }

    private var wideBody: some View {
        let f = prof
        return HStack(spacing: 12) {
                Text(initials(f.name)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Circle().fill(f.priority.color.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.displayName).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1)
                    Text(showUniversity ? "\(ApplyWorld.flag(program.country)) \(program.displayName)" : (f.group.isEmpty ? "—" : f.group))
                        .font(.caption).foregroundStyle(showUniversity ? ap : Color.secondary).lineLimit(1)
                }
                .frame(width: 210, alignment: .leading)
                Text(f.topics.isEmpty ? "—" : f.topics.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                ApplyChip(icon: f.accepting.icon, text: f.accepting.title, color: f.accepting.color).frame(width: 140, alignment: .leading)
                ApplyChip(icon: f.funding.icon, text: f.funding.title, color: f.funding.color).frame(width: 140, alignment: .leading)
                Label(f.contact.title, systemImage: f.contact.icon).font(.caption.weight(.bold)).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(f.contact.color.opacity(0.16))).foregroundStyle(f.contact.color)
                    .frame(width: 140, alignment: .leading)
                Group {
                    if let days = f.daysToFollowUp, f.contact.needsFollowUp {
                        Text(ApplyWorld.countdown(days)).font(.caption.weight(.bold)).foregroundStyle(ApplyWorld.urgencyColor(days))
                    } else if let d = f.lastContact { Text(Fmt.date(d, "MMM d", .gregorian)).font(.caption).foregroundStyle(.secondary) }
                    else { Text("—").foregroundStyle(.tertiary) }
                }
                .frame(width: 100, alignment: .leading)
                HStack(spacing: 1) {
                    ForEach(0..<4, id: \.self) { i in Image(systemName: i < f.priority.stars ? "star.fill" : "star").font(.system(size: 8)).foregroundStyle(i < f.priority.stars ? f.priority.color : Color.secondary.opacity(0.3)) }
                }
                .frame(width: 60)
        }
    }
}

struct ProfessorRowHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 36, height: 1)
            Text("PROFESSOR").frame(width: 210, alignment: .leading)
            Text("RESEARCH").frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            Text("STUDENTS").frame(width: 140, alignment: .leading)
            Text("FUNDING").frame(width: 140, alignment: .leading)
            Text("CONTACT").frame(width: 140, alignment: .leading)
            Text("FOLLOW-UP / LAST").frame(width: 100, alignment: .leading)
            Text("PRIORITY").frame(width: 60)
        }
        .font(.system(size: 9, weight: .heavy)).foregroundStyle(.tertiary).padding(.horizontal, 14)
    }
}

// MARK: - List with filters (used inside a program and for all programs)

struct ProfessorList: View {
    let items: [(program: ApplyProgram, prof: ApplyProfessor)]
    var showUniversity = false
    let open: (UUID, UUID) -> Void

    @State private var search = ""
    @State private var country: String?
    @State private var city: String?
    @State private var university: String?
    @State private var contact: ProfContact?
    @State private var accepting: ProfAccepting?
    @State private var priority: ProfPriority?
    @State private var funding: ProfFunding?
    @AppStorage("apply.profSort") private var sortRaw = "priority"
    @AppStorage("apply.profView") private var viewMode = "grid"

    private static let sorts: [(String, String)] = [
        ("priority", "Priority (top first)"), ("followUp", "Follow-up date (soonest)"), ("lastOld", "Last contact (longest ago)"),
        ("lastNew", "Last contact (most recent)"), ("name", "Name A → Z"), ("accepting", "Taking students first"), ("qs", "University QS ranking (best first)"), ("university", "University")
    ]

    private var shown: [(program: ApplyProgram, prof: ApplyProfessor)] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = items.filter { it in
            let f = it.prof
            return (country == nil || it.program.country == country) && (city == nil || it.program.city == city) && (university == nil || it.program.university == university)
                && (contact == nil || f.contact == contact) && (accepting == nil || f.accepting == accepting) && (priority == nil || f.priority == priority)
                && (funding == nil || f.funding == funding)
                && (q.isEmpty || [f.name, f.group, f.research, f.position, f.notes, it.program.university].contains { $0.lowercased().contains(q) })
        }
        func opt(_ d: Date?, _ asc: Bool, _ a: (ApplyProgram, ApplyProfessor), _ b: (ApplyProgram, ApplyProfessor), _ key: ((ApplyProgram, ApplyProfessor)) -> Date?) -> Bool {
            switch (key(a), key(b)) { case let (x?, y?): return asc ? x < y : x > y; case (_?, nil): return true; default: return false }
        }
        switch sortRaw {
        case "followUp": return list.sorted { opt(nil, true, ($0.program, $0.prof), ($1.program, $1.prof)) { $0.1.followUp } }
        case "lastOld": return list.sorted { opt(nil, true, ($0.program, $0.prof), ($1.program, $1.prof)) { $0.1.lastContact } }
        case "lastNew": return list.sorted { opt(nil, false, ($0.program, $0.prof), ($1.program, $1.prof)) { $0.1.lastContact } }
        case "name": return list.sorted { $0.prof.name.localizedCaseInsensitiveCompare($1.prof.name) == .orderedAscending }
        case "accepting": return list.sorted { rank($0.prof.accepting) < rank($1.prof.accepting) }
        case "qs": return list.sorted { ($0.program.qsRank ?? Int.max) < ($1.program.qsRank ?? Int.max) }
        case "university": return list.sorted { $0.program.university.localizedCaseInsensitiveCompare($1.program.university) == .orderedAscending }
        default: return list.sorted { ($0.prof.priority.rank, $0.prof.name) < ($1.prof.priority.rank, $1.prof.name) }
        }
    }
    /// The programs of the professors listed (for the place filters)
    private var uniquePrograms: [ApplyProgram] {
        var seen = Set<UUID>()
        return items.compactMap { seen.insert($0.program.id).inserted ? $0.program : nil }
    }

    private func rank(_ a: ProfAccepting) -> Int { switch a { case .yes: 0; case .maybe: 1; case .unknown: 2; case .no: 3 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showUniversity {
                ApplyLocationFilters(pool: uniquePrograms, country: $country, city: $city, university: $university)
            }
            ChipFlow(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search name, topic, lab…", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 6).frame(width: 230)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.07)))
                menu("Contact", "envelope", contact?.title) {
                    Button("Any status") { contact = nil }
                    ForEach(ProfContact.allCases) { c in Button { contact = c } label: { Label(c.title, systemImage: c.icon) } }
                }
                menu("Students", "person.crop.circle.badge.checkmark", accepting?.title) {
                    Button("Any") { accepting = nil }
                    ForEach(ProfAccepting.allCases) { a in Button { accepting = a } label: { Label(a.title, systemImage: a.icon) } }
                }
                menu("Priority", "star", priority?.title) {
                    Button("Any priority") { priority = nil }
                    ForEach(ProfPriority.allCases) { p in Button(p.title) { priority = p } }
                }
                menu("Funding", "banknote", funding?.title) {
                    Button("Any") { funding = nil }
                    ForEach(ProfFunding.allCases) { f in Button { funding = f } label: { Label(f.title, systemImage: f.icon) } }
                }
                Text("\(shown.count) of \(items.count)").font(.caption).foregroundStyle(.secondary)
                ViewModeToggle(mode: $viewMode)
                Menu {
                    Picker("Sort by", selection: $sortRaw) { ForEach(Self.sorts, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.inline)
                } label: { Label("Sort: " + (Self.sorts.first { $0.0 == sortRaw }?.1 ?? ""), systemImage: "arrow.up.arrow.down").font(.callout.weight(.semibold)) }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            if shown.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 34)).foregroundStyle(.tertiary)
                    Text(items.isEmpty ? "No professors yet" : "No professor matches").font(.headline)
                    if !items.isEmpty { Button("Clear filters") { country = nil; city = nil; university = nil; contact = nil; accepting = nil; priority = nil; funding = nil; search = "" } }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if viewMode == "list" {
                ViewThatFits(in: .horizontal) {
                    VStack(spacing: 8) {
                        ProfessorRowHeader()
                        ForEach(shown, id: \.prof.id) { it in
                            ProfessorRow(program: it.program, prof: it.prof, showUniversity: showUniversity) { open(it.program.id, it.prof.id) }
                        }
                    }
                    VStack(spacing: 8) {
                        ForEach(shown, id: \.prof.id) { it in
                            ProfessorRow(program: it.program, prof: it.prof, showUniversity: showUniversity, compact: true) { open(it.program.id, it.prof.id) }
                        }
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 16, alignment: .top)], spacing: 16) {
                    ForEach(shown, id: \.prof.id) { it in
                        ProfessorCard(program: it.program, prof: it.prof, showUniversity: showUniversity) { open(it.program.id, it.prof.id) }
                    }
                }
            }
        }
    }

    private func menu<C: View>(_ title: String, _ icon: String, _ value: String?, @ViewBuilder _ content: () -> C) -> some View {
        Menu { content() } label: {
            Label(value ?? title, systemImage: icon).font(.callout.weight(.semibold)).foregroundStyle(value == nil ? Color.primary : ap)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }
}

// MARK: - Tab inside one program

struct ApplyProfessorsTab: View {
    let programID: UUID
    @Environment(AppStore.self) private var store
    @State private var openProf: UUID?

    var body: some View {
        let p = store.applyProgram(programID) ?? ApplyProgram()
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Professors at \(p.displayName)").font(.title3.weight(.bold))
                    Text(summary(p)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { add() } label: { Label("Add professor", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(ap)
            }
            ProfessorList(items: p.professors.map { (p, $0) }) { _, prof in openProf = prof }
        }
        .padding(24)
        .sheet(item: Binding(get: { openProf.map { Ref(id: $0) } }, set: { openProf = $0?.id })) { ProfessorSheet(programID: programID, profID: $0.id) }
    }

    private struct Ref: Identifiable { let id: UUID }

    private func summary(_ p: ApplyProgram) -> String {
        if p.professors.isEmpty { return "Keep the professors you might work with: their research, emails, and whether they take students." }
        let sent = p.professors.filter { $0.contact != .notYet }.count
        let good = p.professors.filter { $0.contact == .positive }.count
        return "\(p.professors.count) professor\(p.professors.count == 1 ? "" : "s") · \(sent) contacted · \(good) positive"
    }

    private func add() {
        var p = store.applyProgram(programID) ?? ApplyProgram()
        let f = ApplyProfessor()
        p.professors.append(f)
        store.upsertApply(p)
        openProf = f.id
    }
}

// MARK: - Tab for all programs

struct ApplyAllProfessorsTab: View {
    @Environment(AppStore.self) private var store
    @State private var openRef: Ref?
    @State private var addTo: UUID?

    private struct Ref: Identifiable { let program: UUID; let prof: UUID; var id: UUID { prof } }

    var body: some View {
        let items = store.applyPrograms.flatMap { p in p.professors.map { (program: p, prof: $0) } }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All professors").font(.title3.weight(.bold))
                        Text("\(items.count) in \(Set(items.map { $0.program.id }).count) universities. Add one from inside a program.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(store.applyPrograms) { p in Button("\(ApplyWorld.flag(p.country)) \(p.displayName)") { add(to: p) } }
                    } label: { Label("Add professor", systemImage: "plus") }
                        .menuStyle(.borderlessButton).fixedSize().disabled(store.applyPrograms.isEmpty)
                }
                ProfessorList(items: items, showUniversity: true) { prog, prof in openRef = Ref(program: prog, prof: prof) }
            }
            .padding(24)
        }
        .sheet(item: $openRef) { ProfessorSheet(programID: $0.program, profID: $0.prof) }
    }

    private func add(to p: ApplyProgram) {
        var q = p
        let f = ApplyProfessor()
        q.professors.append(f)
        store.upsertApply(q)
        openRef = Ref(program: p.id, prof: f.id)
    }
}

// MARK: - One professor (editor)

struct ProfessorSheet: View {
    let programID: UUID
    let profID: UUID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var newSent = true
    @State private var newDate = Date()
    @State private var newSubject = ""
    @State private var newNote = ""

    private var prof: Binding<ApplyProfessor> {
        Binding(
            get: { store.applyProgram(programID)?.professors.first { $0.id == profID } ?? ApplyProfessor() },
            set: { v in
                guard var p = store.applyProgram(programID), let i = p.professors.firstIndex(where: { $0.id == profID }) else { return }
                p.professors[i] = v; store.upsertApply(p)
            })
    }

    var body: some View {
        let f = prof.wrappedValue
        let program = store.applyProgram(programID) ?? ApplyProgram()
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(initials(f.name)).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 50, height: 50).background(Circle().fill(f.priority.color.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(["Prof.", "Dr.", "Assoc. Prof.", "Asst. Prof.", "PD Dr.", "Mr.", "Ms.", ""], id: \.self) { t in Button(t.isEmpty ? "(none)" : t) { prof.title.wrappedValue = t } }
                        } label: { Text(f.title.isEmpty ? "—" : f.title).font(.title3.weight(.semibold)) }.menuStyle(.borderlessButton).fixedSize()
                        TextField("Name", text: prof.name).textFieldStyle(.plain).font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                    Text("\(ApplyWorld.flag(program.country)) \(program.displayName)").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Delete this professor")
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(ap)
            }
            .padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // priority and status
                    VStack(alignment: .leading, spacing: 8) {
                        label("Priority")
                        HStack(spacing: 8) {
                            ForEach(ProfPriority.allCases) { p in
                                let on = f.priority == p
                                Button { prof.priority.wrappedValue = p } label: {
                                    HStack(spacing: 4) {
                                        ForEach(0..<p.stars, id: \.self) { _ in Image(systemName: "star.fill").font(.system(size: 9)) }
                                        Text(p.title).font(.callout.weight(.semibold)).lineLimit(1).fixedSize()
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity)
                                    .background(Capsule().fill(on ? p.color : p.color.opacity(0.12))).foregroundStyle(on ? Color.white : p.color)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        label("Contact status")
                        ChipFlow(spacing: 7) {
                            ForEach(ProfContact.allCases) { c in
                                let on = f.contact == c
                                Button { prof.contact.wrappedValue = c } label: {
                                    Label(c.title, systemImage: c.icon).font(.callout.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 6)
                                        .background(Capsule().fill(on ? c.color : c.color.opacity(0.12))).foregroundStyle(on ? Color.white : c.color)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .sheetCard()

                    // research and position
                    VStack(alignment: .leading, spacing: 10) {
                        label("Research")
                        field("Lab / group", "e.g. Machine Learning Lab", prof.group)
                        field("Research areas", "Comma separated: NLP, graph neural networks, robotics", prof.research)
                        if !f.topics.isEmpty {
                            ChipFlow(spacing: 5) { ForEach(f.topics, id: \.self) { t in Text(t).font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(ap.opacity(0.15))).foregroundStyle(ap) } }
                        }
                        field("Key papers", "Titles or links you liked", prof.papers)
                        field("Website / profile", "https://…", prof.website, link: true)
                    }
                    .sheetCard()

                    // students and funding
                    VStack(alignment: .leading, spacing: 10) {
                        label("Position")
                        HStack(spacing: 8) {
                            ForEach(ProfAccepting.allCases) { a in
                                let on = f.accepting == a
                                Button { prof.accepting.wrappedValue = a } label: {
                                    Label(a.title, systemImage: a.icon).font(.caption.weight(.semibold)).lineLimit(1).padding(.horizontal, 9).padding(.vertical, 7).frame(maxWidth: .infinity)
                                        .background(RoundedRectangle(cornerRadius: 9).fill(on ? a.color : a.color.opacity(0.12))).foregroundStyle(on ? Color.white : a.color)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        field("Position offered", "PhD, Master thesis, postdoc, research assistant…", prof.position)
                        label("Funding")
                        HStack(spacing: 8) {
                            ForEach(ProfFunding.allCases) { x in
                                let on = f.funding == x
                                Button { prof.funding.wrappedValue = x } label: {
                                    Label(x.title, systemImage: x.icon).font(.caption.weight(.semibold)).lineLimit(1).padding(.horizontal, 9).padding(.vertical, 7).frame(maxWidth: .infinity)
                                        .background(RoundedRectangle(cornerRadius: 9).fill(on ? x.color : x.color.opacity(0.12))).foregroundStyle(on ? Color.white : x.color)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        field("Funding note", "Grant, salary level, how long…", prof.fundingNote)
                    }
                    .sheetCard()

                    // email
                    VStack(alignment: .leading, spacing: 10) {
                        label("Email")
                        HStack(spacing: 8) {
                            TextField("name@university.edu", text: prof.email).textFieldStyle(.roundedBorder)
                            Button { compose(f, program) } label: { Label("Write", systemImage: "square.and.pencil") }.disabled(f.email.isEmpty).help("Open a new email to this professor")
                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(f.email, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                                .disabled(f.email.isEmpty).help("Copy the address")
                        }
                        HStack(spacing: 14) {
                            dateField("Last contact", prof.lastContact)
                            dateField("Follow up on", prof.followUp)
                        }
                        Divider().opacity(0.5)
                        HStack { label("Emails with this professor"); Spacer(); Text("\(f.emails.count)").font(.caption.weight(.bold)).foregroundStyle(.secondary) }
                        ForEach(f.emails) { e in emailRow(elem(prof.emails, e.id, ApplyEmail())) }
                        // log one
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Picker("", selection: $newSent) { Text("I sent").tag(true); Text("I received").tag(false) }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
                                DatePicker("", selection: $newDate, displayedComponents: .date).labelsHidden()
                            }
                            TextField("Subject", text: $newSubject).textFieldStyle(.roundedBorder)
                            TextField("What was said (short)", text: $newNote, axis: .vertical).textFieldStyle(.roundedBorder)
                            HStack {
                                Text("Logging an email updates the contact status and sets a follow-up in 2 weeks.").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Add to the log") { logEmail() }.disabled(newSubject.trimmingCharacters(in: .whitespaces).isEmpty && newNote.isEmpty)
                            }
                        }
                        .padding(12).background(RoundedRectangle(cornerRadius: 11).fill(Color.primary.opacity(0.05)))
                    }
                    .sheetCard()

                    VStack(alignment: .leading, spacing: 8) {
                        label("Notes")
                        TextEditor(text: prof.notes).frame(minHeight: 90).scrollContentBackground(.hidden).padding(8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                    }
                    .sheetCard()
                }
                .padding(18)
            }
        }
        .frame(minWidth: 560, idealWidth: 680, minHeight: 420, idealHeight: 580)
        .environment(\.calendar, Cal.gregorian)
        .confirmationDialog("Delete \(f.displayName)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if var p = store.applyProgram(programID) { p.professors.removeAll { $0.id == profID }; store.upsertApply(p) }
                dismiss()
            }
        } message: { Text("Their notes and email log are removed.") }
    }

    private func label(_ t: String) -> some View { Text(t.uppercased()).font(.system(size: 10, weight: .heavy)).foregroundStyle(.tertiary) }

    private func field(_ title: String, _ placeholder: String, _ text: Binding<String>, link: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.callout).foregroundStyle(.secondary).frame(width: 118, alignment: .leading)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
            if link, let u = URL(string: text.wrappedValue.contains("://") ? text.wrappedValue : "https://" + text.wrappedValue), !text.wrappedValue.isEmpty {
                Link(destination: u) { Image(systemName: "arrow.up.right.square") }
            }
        }
    }

    private func dateField(_ title: String, _ date: Binding<Date?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let d = date.wrappedValue {
                    DatePicker("", selection: Binding(get: { d }, set: { date.wrappedValue = $0 }), displayedComponents: .date).labelsHidden()
                    Button { date.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                } else {
                    Button("Set date") { date.wrappedValue = Date() }.controlSize(.small)
                    if title.hasPrefix("Follow") {
                        Button("in 1 week") { date.wrappedValue = Calendar.current.date(byAdding: .day, value: 7, to: Date()) }.controlSize(.small)
                        Button("in 2 weeks") { date.wrappedValue = Calendar.current.date(byAdding: .day, value: 14, to: Date()) }.controlSize(.small)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emailRow(_ e: Binding<ApplyEmail>) -> some View {
        let v = e.wrappedValue
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: v.sent ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill").foregroundStyle(v.sent ? Color(hex: "#3F7FE0") : Color(hex: "#34C77B")).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(v.subject.isEmpty ? (v.sent ? "Email sent" : "Email received") : v.subject).font(.callout.weight(.semibold))
                    Spacer()
                    Text(Fmt.date(v.date, "MMM d, yyyy", .gregorian)).font(.caption).foregroundStyle(.secondary)
                }
                if !v.note.isEmpty { Text(v.note).font(.caption).foregroundStyle(.secondary) }
            }
            Button { prof.emails.wrappedValue.removeAll { $0.id == v.id } } label: { Image(systemName: "trash").foregroundStyle(.tertiary) }.buttonStyle(.plain)
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 11).fill(Color.primary.opacity(0.05)))
    }

    private func logEmail() {
        var f = prof.wrappedValue
        f.emails.insert(ApplyEmail(date: newDate, sent: newSent, subject: newSubject, note: newNote), at: 0)
        f.emails.sort { $0.date > $1.date }
        f.lastContact = f.emails.first?.date
        if newSent {
            if f.contact == .notYet || f.contact == .noReply { f.contact = .emailed }
            f.followUp = Calendar.current.date(byAdding: .day, value: 14, to: newDate)
        } else if [.notYet, .emailed, .noReply].contains(f.contact) {
            f.contact = .replied
            f.followUp = nil
        }
        prof.wrappedValue = f
        newSubject = ""; newNote = ""; newDate = Date()
    }

    private func compose(_ f: ApplyProfessor, _ program: ApplyProgram) {
        let subject = "Prospective \(program.degree == .phd ? "PhD" : "graduate") student: \(program.program.isEmpty ? program.displayName : program.program)"
        let body = "Dear \(f.displayName),\n\nMy name is \n\nI am writing because of your work on \(f.topics.first ?? "…").\n\nBest regards,\n"
        var c = URLComponents(); c.scheme = "mailto"; c.path = f.email
        c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        if let u = c.url { NSWorkspace.shared.open(u) }
    }
}

private extension View {
    func sheetCard() -> some View {
        self.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
