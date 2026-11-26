import SwiftUI

private let applyPurple = Color(hex: "#8E6BD8")

/// "Jan 15, 2027" (always the Gregorian calendar: that is how universities write their dates)
func applyDate(_ d: Date?) -> String { d.map { Fmt.date($0, "MMM d, yyyy", .gregorian) } ?? "—" }

// MARK: - Card

struct ApplyStatusPill: View {
    let status: ApplyStatus
    var body: some View {
        Label(status.title, systemImage: status.icon).font(.caption.weight(.bold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(status.color.opacity(0.18)))
            .foregroundStyle(status.color)
    }
}

struct ApplyChip: View {
    let icon: String
    let text: String
    var color: Color = .secondary
    var body: some View {
        Label(text, systemImage: icon).font(.caption.weight(.semibold)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.13)))
            .foregroundStyle(color)
    }
}

struct ApplyCard: View {
    let program: ApplyProgram
    let open: () -> Void
    @Environment(AppStore.self) private var store
    @State private var hover = false

    var body: some View {
        let p = program
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text(ApplyWorld.flag(p.country)).font(.system(size: 26))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(p.country.isEmpty ? "No country yet" : p.country).font(.caption.weight(.bold))
                        if !p.city.isEmpty { Text(p.city).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button { var q = p; q.starred.toggle(); store.upsertApply(q) } label: {
                        Image(systemName: p.starred ? "star.fill" : "star").foregroundStyle(p.starred ? Color.yellow : Color.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain).help(p.starred ? "Remove the star" : "Star this program")
                    ApplyStatusPill(status: p.status)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.displayName).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(p.program.isEmpty ? "No program name yet" : p.program).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        Text(p.degree.title).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(applyPurple.opacity(0.2))).foregroundStyle(applyPurple)
                    }
                }
                deadlineLine
                ChipFlow(spacing: 6) {
                    ApplyChip(icon: p.funding.icon, text: p.funding.short, color: p.funding.color)
                    if let f = p.fee { ApplyChip(icon: p.feePaid ? "checkmark.circle.fill" : "creditcard", text: f == 0 ? "No fee" : ApplyWorld.money(f, p.currency), color: p.feePaid ? Color(hex: "#34C77B") : .secondary) }
                    if let m = p.durationMonths { ApplyChip(icon: "clock", text: m % 12 == 0 ? "\(m / 12) yr" : "\(m) mo") }
                    if p.tier != .none { ApplyChip(icon: "scope", text: p.tier.title, color: p.tier.color) }
                }
                if !p.professors.isEmpty {
                    ChipFlow(spacing: 6) {
                        ApplyChip(icon: "person.2.fill", text: "\(p.professors.count) professor\(p.professors.count == 1 ? "" : "s")")
                        let replied = p.professors.filter { [.replied, .meeting, .positive].contains($0.contact) }.count
                        if replied > 0 { ApplyChip(icon: "arrowshape.turn.up.left.fill", text: "\(replied) replied", color: Color(hex: "#3FB6C8")) }
                        let yes = p.professors.filter { $0.accepting == .yes }.count
                        if yes > 0 { ApplyChip(icon: "checkmark.circle.fill", text: "\(yes) taking students", color: Color(hex: "#34C77B")) }
                    }
                }
                if !p.intakes.isEmpty {
                    ChipFlow(spacing: 6) {
                        ForEach(p.intakes) { i in
                            ApplyChip(icon: i.season.icon, text: i.label, color: i.season.color)
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(i.season.color.opacity(p.focusIntake?.id == i.id && p.intakes.count > 1 ? 0.9 : 0), lineWidth: 1.5))
                        }
                        if let st = p.termStart { ApplyChip(icon: "graduationcap", text: "Starts " + Fmt.date(st, "MMM yyyy", .gregorian)) }
                    }
                }
                progress
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [p.status.color.opacity(0.14), .clear], startPoint: .topLeading, endPoint: .center)))
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.status.color.opacity(hover ? 0.7 : 0.25), lineWidth: hover ? 2 : 1))
            .shadow(color: .black.opacity(hover ? 0.25 : 0.08), radius: hover ? 12 : 4, y: 3)
            .scaleEffect(hover ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .contextMenu {
            Button("Open") { open() }
            Menu("Set status") { ForEach(ApplyStatus.allCases) { s in Button(s.title) { var q = p; q.status = s; store.upsertApply(q) } } }
            Divider()
            Button("Delete", role: .destructive) { store.deleteApply(p.id) }
        }
    }

    @ViewBuilder private var deadlineLine: some View {
        let p = program
        if p.status.isClosed || p.status == .submitted || p.status == .interview || p.status == .waitlisted, p.nextDeadline == nil {
            HStack(spacing: 6) {
                Image(systemName: p.status.icon).foregroundStyle(p.status.color)
                Text(p.decision.map { "Decision expected \(applyDate($0))" } ?? p.status.title).font(.callout.weight(.semibold))
            }
        } else if let n = p.nextDeadline {
            let days = ApplyProgram.daysUntil(n.date), c = ApplyWorld.urgencyColor(days)
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(c)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(n.label) · \(applyDate(n.date))").font(.callout.weight(.semibold))
                    Text(ApplyWorld.countdown(days)).font(.caption.weight(.bold)).foregroundStyle(c)
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.plus").foregroundStyle(.tertiary)
                Text("No deadline yet").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var progress: some View {
        let p = program
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Documents", systemImage: "checklist").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(p.docs.isEmpty ? "no checklist" : "\(p.docsDone)/\(p.docs.count)").font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(p.progress >= 1 ? Color(hex: "#34C77B") : .secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    if p.progress > 0 {
                        Capsule().fill(LinearGradient(colors: [p.progress >= 1 ? Color(hex: "#34C77B") : applyPurple, p.progress >= 1 ? Color(hex: "#7BE0A8") : Color(hex: "#C08CFF")],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, g.size.width * p.progress))
                    }
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Row (list mode)

struct ApplyRow: View {
    let program: ApplyProgram
    var compact = false
    let open: () -> Void
    @Environment(AppStore.self) private var store
    @State private var hover = false

    var body: some View {
        let p = program
        Button(action: open) {
            Group { if compact { compactBody } else { wideBody } }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(p.status.color).frame(width: 4).padding(.vertical, 8) }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.status.color.opacity(hover ? 0.6 : 0.15)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Open") { open() }
            Menu("Set status") { ForEach(ApplyStatus.allCases) { s in Button(s.title) { var q = p; q.status = s; store.upsertApply(q) } } }
            Divider()
            Button("Delete", role: .destructive) { store.deleteApply(p.id) }
        }
    }

    /// Narrow window: two lines instead of columns
    private var compactBody: some View {
        let p = program
        return HStack(alignment: .top, spacing: 10) {
            Button { var q = p; q.starred.toggle(); store.upsertApply(q) } label: {
                Image(systemName: p.starred ? "star.fill" : "star").foregroundStyle(p.starred ? Color.yellow : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain).frame(width: 18)
            Text(ApplyWorld.flag(p.country)).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(p.displayName).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1)
                    Spacer(minLength: 6)
                    ApplyStatusPill(status: p.status)
                }
                Text([p.program, p.city, p.country].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                ChipFlow(spacing: 6) {
                    if let n = p.nextDeadline {
                        let days = ApplyProgram.daysUntil(n.date)
                        ApplyChip(icon: "calendar.badge.clock", text: "\(applyDate(n.date)) · \(ApplyWorld.countdown(days))", color: ApplyWorld.urgencyColor(days))
                    }
                    ApplyChip(icon: p.funding.icon, text: p.funding.short, color: p.funding.color)
                    if let f = p.fee { ApplyChip(icon: "creditcard", text: f == 0 ? "No fee" : ApplyWorld.money(f, p.currency)) }
                    ApplyChip(icon: "checklist", text: p.docs.isEmpty ? "no checklist" : "\(p.docsDone)/\(p.docs.count)", color: p.progress >= 1 ? Color(hex: "#34C77B") : applyPurple)
                }
            }
        }
    }

    private var wideBody: some View {
        let p = program
        return HStack(spacing: 12) {
                Button { var q = p; q.starred.toggle(); store.upsertApply(q) } label: {
                    Image(systemName: p.starred ? "star.fill" : "star").foregroundStyle(p.starred ? Color.yellow : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain).frame(width: 18)
                Text(ApplyWorld.flag(p.country)).font(.system(size: 22)).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.displayName).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(p.program.isEmpty ? "—" : p.program).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(p.degree.title).font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(applyPurple.opacity(0.2))).foregroundStyle(applyPurple)
                    }
                }
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.city.isEmpty ? "—" : p.city).font(.callout).lineLimit(1)
                    Text(p.country).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 120, alignment: .leading)
                ApplyStatusPill(status: p.status).frame(width: 120, alignment: .leading)
                deadline.frame(width: 190, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    ApplyChip(icon: p.funding.icon, text: p.funding.short, color: p.funding.color)
                    if let f = p.fee { Text(f == 0 ? "No fee" : ApplyWorld.money(f, p.currency)).font(.caption).foregroundStyle(p.feePaid ? Color(hex: "#34C77B") : .secondary) }
                }
                .frame(width: 120, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.docs.isEmpty ? "—" : "\(p.docsDone)/\(p.docs.count)").font(.caption.weight(.bold).monospacedDigit())
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.10))
                            if p.progress > 0 { Capsule().fill(p.progress >= 1 ? Color(hex: "#34C77B") : applyPurple).frame(width: max(5, g.size.width * p.progress)) }
                        }
                    }
                    .frame(height: 5)
                }
                .frame(width: 80)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var deadline: some View {
        let p = program
        if let n = p.nextDeadline {
            let days = ApplyProgram.daysUntil(n.date), c = ApplyWorld.urgencyColor(days)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(n.label)").font(.caption).lineLimit(1)
                Text("\(applyDate(n.date)) · \(ApplyWorld.countdown(days))").font(.caption.weight(.bold)).foregroundStyle(c).lineLimit(1)
            }
        } else if let d = p.decision, !p.status.isOpen {
            Text("Decision \(applyDate(d))").font(.caption).lineLimit(1)
        } else {
            Text("No deadline").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// Column titles above the list rows
struct ApplyRowHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 18 + 30 + 24, height: 1)
            Text("UNIVERSITY").frame(minWidth: 200 - 54, maxWidth: .infinity, alignment: .leading)
            Text("LOCATION").frame(width: 120, alignment: .leading)
            Text("STATUS").frame(width: 120, alignment: .leading)
            Text("NEXT DEADLINE").frame(width: 190, alignment: .leading)
            Text("FUNDING / FEE").frame(width: 120, alignment: .leading)
            Text("DOCS").frame(width: 80, alignment: .leading)
            Color.clear.frame(width: 10)
        }
        .font(.system(size: 9, weight: .heavy)).foregroundStyle(.tertiary).padding(.horizontal, 14)
    }
}

/// Cards or list
struct ViewModeToggle: View {
    @Binding var mode: String
    var body: some View {
        Picker("", selection: $mode) {
            Image(systemName: "square.grid.2x2").tag("grid")
            Image(systemName: "list.bullet").tag("list")
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 84).help("Cards or list")
    }
}

// MARK: - Deadlines tab

struct ApplyDeadlinesTab: View {
    let open: (UUID) -> Void
    @Environment(AppStore.self) private var store

    private struct Item: Identifiable {
        var id: String { "\(program.id)|\(label)|\(date.timeIntervalSince1970)|\(extraID?.uuidString ?? "")" }
        let program: ApplyProgram
        let label: String
        let date: Date
        let icon: String
        var extraID: UUID?
        var done = false
    }

    private var items: [Item] {
        var out: [Item] = []
        for p in store.applyPrograms where p.status != .withdrawn && p.status != .rejected {
            let pool = p.appliedIntake.flatMap { a in p.intakes.first { $0.id == a } }.map { [$0] } ?? p.intakes
            for i in pool {
                if let o = i.opens, p.status.isOpen, ApplyProgram.daysUntil(o) >= 0 { out.append(Item(program: p, label: "\(i.label): applications open", date: o, icon: "door.left.hand.open")) }
                if let c = i.closes { out.append(Item(program: p, label: "\(i.label): applications close", date: c, icon: "alarm.fill", done: !p.status.isOpen)) }
                if let d = i.decision, p.status != .accepted { out.append(Item(program: p, label: "\(i.label): decision expected", date: d, icon: "envelope.open.fill")) }
                if let st = i.start, p.status == .accepted, ApplyProgram.daysUntil(st) >= 0 { out.append(Item(program: p, label: "\(i.label): course starts", date: st, icon: "graduationcap.fill")) }
            }
            for f in p.professors where f.contact.needsFollowUp {
                if let d = f.followUp { out.append(Item(program: p, label: "Follow up: \(f.displayName)", date: d, icon: "envelope.badge.fill")) }
            }
            for e in p.extraDeadlines { out.append(Item(program: p, label: e.label.isEmpty ? "Deadline" : e.label, date: e.date, icon: "flag.fill", extraID: e.id, done: e.done)) }
        }
        return out.sorted { $0.date < $1.date }
    }

    var body: some View {
        let all = items
        let todo = all.filter { !$0.done }
        let groups: [(String, Color, [Item])] = [
            ("Overdue", Color(hex: "#E8384F"), todo.filter { ApplyProgram.daysUntil($0.date) < 0 }),
            ("This week", Color(hex: "#E8384F"), todo.filter { (0...7).contains(ApplyProgram.daysUntil($0.date)) }),
            ("This month", Color(hex: "#E8A33D"), todo.filter { (8...30).contains(ApplyProgram.daysUntil($0.date)) }),
            ("Later", Color(hex: "#34C77B"), todo.filter { ApplyProgram.daysUntil($0.date) > 30 }),
            ("Done", Color.secondary, all.filter { $0.done }),
        ]
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if all.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 36)).foregroundStyle(.tertiary)
                        Text("No dates yet").font(.headline)
                        Text("Add the open and close dates of your programs and they appear here, all in one list.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 60)
                }
                ForEach(groups, id: \.0) { g in
                    if !g.2.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle().fill(g.1).frame(width: 9, height: 9)
                                Text(g.0).font(.headline)
                                Text("\(g.2.count)").font(.caption.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(g.1.opacity(0.2)))
                            }
                            ForEach(g.2) { row($0, tint: g.1) }
                        }
                    }
                }
                let undated = store.applyPrograms.filter { $0.closes == nil && $0.status.isOpen }
                if !undated.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Programs without a close date", systemImage: "calendar.badge.plus").font(.headline)
                        ForEach(undated) { p in
                            Button { open(p.id) } label: {
                                HStack { Text(ApplyWorld.flag(p.country)); Text(p.displayName).font(.callout.weight(.semibold)); Text(p.program).foregroundStyle(.secondary); Spacer()
                                    Text("Add date").font(.caption.weight(.bold)).foregroundStyle(applyPurple) }
                                    .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func row(_ it: Item, tint: Color) -> some View {
        let days = ApplyProgram.daysUntil(it.date)
        return HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(Fmt.date(it.date, "MMM", .gregorian).uppercased()).font(.system(size: 10, weight: .heavy)).foregroundStyle(tint)
                Text(Fmt.date(it.date, "d", .gregorian)).font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .frame(width: 52, height: 52).background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Label(it.label, systemImage: it.icon).font(.callout.weight(.bold)).strikethrough(it.done)
                HStack(spacing: 6) {
                    Text(ApplyWorld.flag(it.program.country))
                    Text(it.program.displayName).font(.callout)
                    if !it.program.program.isEmpty { Text("· " + it.program.program).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            Spacer()
            if !it.done {
                Text(ApplyWorld.countdown(days)).font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(tint.opacity(0.16))).foregroundStyle(tint)
            }
            if let eid = it.extraID {
                Button {
                    var q = it.program
                    if let i = q.extraDeadlines.firstIndex(where: { $0.id == eid }) { q.extraDeadlines[i].done.toggle(); store.upsertApply(q) }
                } label: { Image(systemName: it.done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(it.done ? Color(hex: "#34C77B") : .secondary) }
                    .buttonStyle(.plain).help("Mark as done")
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.2)))
        .opacity(it.done ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { open(it.program.id) }
    }
}

// MARK: - Overview tab

struct ApplyOverviewTab: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let all = store.applyPrograms
        let active = all.filter { !$0.status.isClosed }
        let sent = all.filter { [.submitted, .interview, .waitlisted].contains($0.status) }
        let accepted = all.filter { $0.status == .accepted }
        let withFee = all.filter { $0.fee != nil }
        let feeTotal = withFee.reduce(0.0) { $0 + ApplyWorld.usd($1.fee ?? 0, $1.currency) }
        let feePaid = withFee.filter(\.feePaid).reduce(0.0) { $0 + ApplyWorld.usd($1.fee ?? 0, $1.currency) }
        let docsAll = all.flatMap(\.docs)
        let next = all.compactMap { p in p.nextDeadline.map { (p, $0) } }.min { $0.1.date < $1.1.date }
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    tile("Programs", "\(all.count)", "\(active.count) still open", "square.stack.3d.up.fill", applyPurple)
                    tile("Sent", "\(sent.count)", "awaiting answer", "paperplane.fill", Color(hex: "#3F7FE0"))
                    tile("Accepted", "\(accepted.count)", accepted.isEmpty ? "keep going" : "congrats 🎉", "checkmark.seal.fill", Color(hex: "#34C77B"))
                    tile("Documents", docsAll.isEmpty ? "—" : "\(Int(Double(docsAll.filter(\.done).count) / Double(docsAll.count) * 100))%",
                         "\(docsAll.filter(\.done).count) of \(docsAll.count) ready", "checklist", Color(hex: "#E8A33D"))
                }
                if let n = next {
                    let days = ApplyProgram.daysUntil(n.1.date), c = ApplyWorld.urgencyColor(days)
                    HStack(spacing: 14) {
                        Image(systemName: "alarm.fill").font(.title2).foregroundStyle(c)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NEXT DEADLINE").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                            Text("\(n.0.displayName): \(n.1.label)").font(.headline)
                            Text("\(applyDate(n.1.date)) · \(ApplyWorld.countdown(days))").font(.callout.weight(.semibold)).foregroundStyle(c)
                        }
                        Spacer()
                    }
                    .padding(16).background(RoundedRectangle(cornerRadius: 16).fill(c.opacity(0.12)))
                }
                HStack(alignment: .top, spacing: 16) {
                    card("By status", "flag.fill") { statusBars(all) }
                    card("By country", "globe.europe.africa.fill") { countryBars(all) }
                }
                HStack(alignment: .top, spacing: 16) {
                    card("Money", "banknote.fill") { money(all, feeTotal: feeTotal, feePaid: feePaid, count: withFee.count) }
                    card("Funding", "creditcard.fill") { fundingBars(all) }
                }
                card("Professors", "person.2.fill") { professors(all) }
            }
            .padding(24)
        }
    }

    private func tile(_ title: String, _ value: String, _ sub: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(.white).frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 13).fill(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 88)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.25)))
    }

    private func card<C: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func bar(_ label: String, _ count: Int, _ total: Int, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.callout).frame(width: 120, alignment: .leading).lineLimit(1)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color.gradient).frame(width: count == 0 ? 0 : max(8, g.size.width * Double(count) / Double(max(1, total))))
                }
            }
            .frame(height: 10)
            Text("\(count)").font(.callout.weight(.bold).monospacedDigit()).frame(width: 28, alignment: .trailing)
        }
    }

    private func statusBars(_ all: [ApplyProgram]) -> some View {
        VStack(spacing: 8) {
            ForEach(ApplyStatus.allCases) { s in bar(s.title, all.filter { $0.status == s }.count, all.count, s.color) }
        }
    }

    private func countryBars(_ all: [ApplyProgram]) -> some View {
        let names = Array(Set(all.map(\.country))).sorted { c1, c2 in all.filter { $0.country == c1 }.count > all.filter { $0.country == c2 }.count }
        return VStack(spacing: 8) {
            ForEach(names, id: \.self) { n in bar((n.isEmpty ? "🌍 No country" : ApplyWorld.flag(n) + " " + n), all.filter { $0.country == n }.count, all.count, applyPurple) }
        }
    }

    private func professors(_ all: [ApplyProgram]) -> some View {
        let list = all.flatMap(\.professors)
        let due = list.filter { $0.contact.needsFollowUp && ($0.daysToFollowUp ?? 1) <= 0 }.count
        return VStack(alignment: .leading, spacing: 8) {
            if list.isEmpty { Text("No professors yet. Add them inside a program or in the Professors tab.").foregroundStyle(.secondary) }
            else {
                ForEach(ProfContact.allCases) { c in bar(c.title, list.filter { $0.contact == c }.count, list.count, c.color) }
                ChipFlow(spacing: 14) {
                    Label("\(list.filter { $0.accepting == .yes }.count) taking students", systemImage: "checkmark.circle.fill").foregroundStyle(Color(hex: "#34C77B"))
                    Label("\(list.filter { $0.funding == .yes }.count) with funding", systemImage: "banknote.fill").foregroundStyle(Color(hex: "#34C77B"))
                    if due > 0 { Label("\(due) follow-up\(due == 1 ? "" : "s") due", systemImage: "bell.fill").foregroundStyle(Color(hex: "#E8A33D")) }
                }
                .font(.callout.weight(.semibold))
            }
        }
    }

    private func fundingBars(_ all: [ApplyProgram]) -> some View {
        VStack(spacing: 8) {
            ForEach(ApplyFunding.allCases) { f in bar(f.title, all.filter { $0.funding == f }.count, all.count, f.color) }
            Text("Funded and partly funded programs cost you less. Check the cost of the self-funded ones in each program.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func money(_ all: [ApplyProgram], feeTotal: Double, feePaid: Double, count: Int) -> some View {
        let selfFunded = all.filter { $0.funding != .funded && !$0.status.isClosed && $0.costTotal != nil }
        let cheapest = selfFunded.min { ApplyWorld.usd($0.costTotal ?? 0, $0.currency) < ApplyWorld.usd($1.costTotal ?? 0, $1.currency) }
        return VStack(alignment: .leading, spacing: 10) {
            row("Application fees (\(count) programs)", ApplyWorld.moneyUSD(feeTotal))
            row("Already paid", ApplyWorld.moneyUSD(feePaid))
            row("Still to pay", ApplyWorld.moneyUSD(max(0, feeTotal - feePaid)), bold: true)
            Divider()
            if let c = cheapest {
                row("Cheapest program to study", "\(c.displayName) · \(ApplyWorld.money(c.costTotal, c.currency))")
            }
            Text("Amounts in other currencies are added with rough exchange rates, so they are estimates.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ l: String, _ v: String, bold: Bool = false) -> some View {
        HStack { Text(l).foregroundStyle(.secondary); Spacer(); Text(v).font(bold ? .callout.weight(.bold) : .callout) }.font(.callout)
    }
}

// MARK: - Add sheet

struct AddApplySheet: View {
    var country: String?
    var city: String?
    let onAdd: (UUID) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var p = ApplyProgram()
    @State private var hasIntake = false
    @State private var intake = ApplyIntake()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "plus").foregroundStyle(.white).frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(applyPurple))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Add a program").font(.title3.weight(.bold))
                    Text("Only the university is needed. Everything else can be filled in later.").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                labeled("University") { TextField("e.g. Technical University of Munich", text: $p.university).textFieldStyle(.roundedBorder) }
                labeled("Program") { TextField("e.g. MSc Computer Science", text: $p.program).textFieldStyle(.roundedBorder) }
                labeled("Degree") {
                    Picker("", selection: $p.degree) { ForEach(ApplyDegree.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                }
                HStack(spacing: 10) {
                    labeled("Country") { ApplySuggestField(text: $p.country, placeholder: "Germany", suggestions: countrySuggestions, flagged: true) }
                    labeled("City") { ApplySuggestField(text: $p.city, placeholder: "Munich", suggestions: citySuggestions, flagged: false) }
                }
                Toggle("I know the intake and when applications close", isOn: $hasIntake).toggleStyle(.switch)
                if hasIntake {
                    HStack(spacing: 10) {
                        Picker("", selection: $intake.season) { ForEach(ApplySeason.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 330)
                        Stepper("\(String(intake.year))", value: $intake.year, in: 2024...2040).monospacedDigit()
                    }
                    DatePicker("Applications close", selection: Binding(get: { intake.closes ?? Date() }, set: { intake.closes = $0 }), displayedComponents: .date)
                        .environment(\.calendar, Cal.gregorian)
                    Text("You can add more intakes (for example both spring and fall) inside the program.").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("A checklist of documents for \(p.degree.title.lowercased()) programs is added for you.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    p.docs = ApplyProgram.defaultDocs(for: p.degree)
                    p.durationMonths = p.degree.usualMonths
                    if hasIntake { var i = intake; if i.closes == nil { i.closes = Date() }; p.intakes = [i] }
                    store.upsertApply(p); onAdd(p.id); dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(applyPurple)
                .disabled(p.university.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22).frame(width: 560)
        .onAppear { if let country { p.country = country }; if let city { p.city = city } }
    }

    private var countrySuggestions: [String] {
        Array(Set(store.applyPrograms.map(\.country).filter { !$0.isEmpty } + ApplyWorld.countryNames)).sorted()
    }
    private var citySuggestions: [String] {
        Array(Set(store.applyPrograms.filter { p.country.isEmpty || $0.country == p.country }.map(\.city).filter { !$0.isEmpty })).sorted()
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary); content() }
    }
}

/// A text field with a menu of suggestions (you can still type anything)
struct ApplySuggestField: View {
    @Binding var text: String
    var placeholder = ""
    let suggestions: [String]
    var flagged = false

    var body: some View {
        HStack(spacing: 4) {
            if flagged { Text(ApplyWorld.flag(text)).font(.title3) }
            TextField(placeholder, text: $text).textFieldStyle(.roundedBorder)
            Menu {
                ForEach(suggestions, id: \.self) { s in Button((flagged ? ApplyWorld.flag(s) + " " : "") + s) { text = s } }
            } label: { Image(systemName: "chevron.down.circle") }
                .menuStyle(.borderlessButton).fixedSize().disabled(suggestions.isEmpty)
        }
    }
}


// MARK: - Country / city / university filters

/// One quiet button that opens a searchable list (so it stays tidy with many countries, cities and universities)
struct LocationPicker: View {
    let title: String
    let icon: String
    let options: [(key: String, label: String, count: Int)]
    let total: Int
    @Binding var selection: String?
    @State private var open = false
    @State private var query = ""

    var body: some View {
        let on = selection != nil
        HStack(spacing: 0) {
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                    Text(selectionLabel).font(.callout.weight(.semibold)).lineLimit(1)
                    if !on { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6) }
                }
                .padding(.leading, 11).padding(.trailing, on ? 6 : 11).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if on {
                Button { selection = nil } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 13)).opacity(0.75) }
                    .buttonStyle(.plain).padding(.trailing, 8).help("Show all")
            }
        }
        .foregroundStyle(on ? Color.white : Color.primary)
        .background(Capsule().fill(on ? applyPurple : Color.primary.opacity(0.08)))
        .popover(isPresented: $open, arrowEdge: .bottom) { list }
    }

    private var selectionLabel: String {
        guard let s = selection else { return title }
        return options.first { $0.key == s }?.label ?? s
    }

    private var shown: [(key: String, label: String, count: Int)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? options : options.filter { $0.label.lowercased().contains(q) }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if options.count > 6 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(title.lowercased())…", text: $query).textFieldStyle(.plain)
                }
                .padding(10)
                Divider()
            }
            ScrollView {
                VStack(spacing: 2) {
                    row("All", nil, total)
                    ForEach(shown, id: \.key) { o in row(o.label, o.key, o.count) }
                    if shown.isEmpty { Text("Nothing found").foregroundStyle(.secondary).padding(14) }
                }
                .padding(6)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 270)
    }

    private func row(_ label: String, _ key: String?, _ count: Int) -> some View {
        LocationRow(label: label, count: count, selected: selection == key) { selection = key; open = false; query = "" }
    }
}

/// One line of the list; it lights up under the mouse so you can see which one you are about to pick
private struct LocationRow: View {
    let label: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).font(.callout).lineLimit(1)
                Spacer()
                Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(applyPurple).opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(hover ? applyPurple.opacity(0.28) : (selected ? applyPurple.opacity(0.14) : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Country → City → University as three small pickers. Each one only lists what fits the choices before it.
struct ApplyLocationFilters: View {
    let pool: [ApplyProgram]
    @Binding var country: String?
    @Binding var city: String?
    @Binding var university: String?

    var body: some View {
        let inCountry = pool.filter { country == nil || $0.country == country }
        let inCity = inCountry.filter { city == nil || $0.city == city }
        ChipFlow(spacing: 8) {
            LocationPicker(title: "Country", icon: "globe.europe.africa.fill",
                           options: options(pool, \.country, flag: true), total: pool.count, selection: $country)
            LocationPicker(title: "City", icon: "building.2.fill",
                           options: options(inCountry, \.city, flag: false), total: inCountry.count, selection: $city)
            LocationPicker(title: "University", icon: "graduationcap.fill",
                           options: options(inCity, \.university, flag: false), total: inCity.count, selection: $university)
            if country != nil || city != nil || university != nil {
                Button("Clear places") { country = nil; city = nil; university = nil }.buttonStyle(.borderless).font(.caption.weight(.semibold))
            }
        }
        .onChange(of: country) { _, _ in city = nil; university = nil }
        .onChange(of: city) { _, _ in university = nil }
    }

    private func options(_ list: [ApplyProgram], _ key: KeyPath<ApplyProgram, String>, flag: Bool) -> [(key: String, label: String, count: Int)] {
        let names = Array(Set(list.map { $0[keyPath: key] }.filter { !$0.isEmpty })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return names.map { n in (key: n, label: (flag ? ApplyWorld.flag(n) + " " : "") + n, count: list.filter { $0[keyPath: key] == n }.count) }
    }
}
