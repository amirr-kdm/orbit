import SwiftUI

private let ap = Color(hex: "#8E6BD8")

/// A binding to one element of a list, found by its id every time it is read or written.
/// (Row bindings made by index can crash when a row is deleted while it is still on screen.)
func elem<T: Identifiable>(_ list: Binding<[T]>, _ id: T.ID, _ fallback: T) -> Binding<T> where T.ID: Equatable {
    Binding(get: { list.wrappedValue.first { $0.id == id } ?? fallback },
            set: { v in if let i = list.wrappedValue.firstIndex(where: { $0.id == id }) { list.wrappedValue[i] = v } })
}

/// One program: status, dates, money, requirements and the checklist. Everything is edited right here and saved as you type.
struct ApplyDetailView: View {
    let id: UUID
    let back: () -> Void
    @Environment(AppStore.self) private var store
    @State private var confirmDelete = false
    @Environment(Router.self) private var router
    private var section: Int { router.applySection }
    private var sectionBinding: Binding<Int> { Binding(get: { router.applySection }, set: { router.applySection = $0 }) }

    private var prog: Binding<ApplyProgram> {
        Binding(get: { store.applyProgram(id) ?? ApplyProgram() },
                set: { v in if store.applyProgram(id) != nil { store.upsertApply(v) } })   // (never brings back a deleted program)
    }

    var body: some View {
        let p = prog.wrappedValue
        return VStack(spacing: 0) {
            HStack {
                Button(action: back) { Label("Apply", systemImage: "chevron.left") }.buttonStyle(.borderless)
                Spacer()
                Text("\(ApplyWorld.flag(p.country)) \(p.displayName)").font(.headline).lineLimit(1)
                Spacer()
                Button { prog.starred.wrappedValue.toggle() } label: {
                    Image(systemName: p.starred ? "star.fill" : "star").foregroundStyle(p.starred ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.borderless).help("Star")
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Delete this program")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            Picker("", selection: sectionBinding) {
                Text("Program").tag(0)
                Text("Professors (\(p.professors.count))").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 300).padding(.vertical, 8)
            Divider()
            if section == 1 {
                ScrollView { ApplyProfessorsTab(programID: id) }
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    ApplyIntakesCard(prog: prog)
                    FlowGrid(minWidth: 430, spacing: 18, maxColumns: 2) {
                        ApplyWhereCard(prog: prog)
                        ApplyDatesCard(prog: prog)
                        ApplyMoneyCard(prog: prog)
                        ApplyRequirementsCard(prog: prog)
                    }
                    ApplyChecklistCard(prog: prog)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notes", systemImage: "note.text").font(.headline)
                        TextEditor(text: prog.notes).font(.body).frame(minHeight: 110)
                            .scrollContentBackground(.hidden).padding(8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                    }
                    .applyCard()
                }
                .padding(24)
            }
            }
        }
        .environment(\.calendar, Cal.gregorian)
        .confirmationDialog("Delete \(p.displayName)?", isPresented: $confirmDelete) {
            Button("Delete this program", role: .destructive) { store.deleteApply(id); back() }
        } message: { Text("Its dates, costs and checklist are removed. This can't be undone.") }
    }

    // MARK: hero

    private var hero: some View {
        let p = prog.wrappedValue
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Text(ApplyWorld.flag(p.country)).font(.system(size: 52))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("University", text: prog.university).textFieldStyle(.plain).font(.system(size: 28, weight: .bold, design: .rounded))
                    TextField("Program (e.g. MSc Computer Science)", text: prog.program).textFieldStyle(.plain).font(.title3).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Picker("", selection: prog.degree) { ForEach(ApplyDegree.allCases) { Text($0.title).tag($0) } }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 270)
                        if let q = p.qsRank { ApplyChip(icon: "rosette", text: "QS #\(q)", color: Color(hex: "#E8A33D")) }
                        Menu {
                            ForEach(ApplyTier.allCases) { t in Button { prog.tier.wrappedValue = t } label: { Text("\(t.title) · \(t.hint)") } }
                        } label: {
                            Label(p.tier.title, systemImage: "scope").font(.callout.weight(.semibold)).foregroundStyle(p.tier == .none ? Color.secondary : p.tier.color)
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }
                Spacer()
            }
            // the status, one click
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ApplyStatus.allCases) { s in
                        let on = p.status == s
                        Button { withAnimation { prog.status.wrappedValue = s } } label: {
                            Label(s.title, systemImage: s.icon).font(.callout.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(on ? s.color : s.color.opacity(0.12)))
                                .foregroundStyle(on ? Color.white : s.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            // the key numbers (they wrap onto a second line in a narrow window)
            FlowGrid(minWidth: 175) {
                fact("Next deadline", p.nextDeadline.map { ApplyWorld.countdown(ApplyProgram.daysUntil($0.date)) } ?? "none set",
                     p.nextDeadline.map { "\($0.label) · \(applyDate($0.date))" } ?? "add a date below",
                     "alarm.fill", p.nextDeadline.map { ApplyWorld.urgencyColor(ApplyProgram.daysUntil($0.date)) } ?? .gray)
                fact("Application fee", p.fee == 0 ? "No fee" : ApplyWorld.money(p.fee, p.currency), p.fee == nil ? "not set" : (p.fee == 0 ? "free to apply" : (p.feePaid ? "paid ✓" : "not paid yet")), "creditcard.fill",
                     p.feePaid ? Color(hex: "#34C77B") : Color(hex: "#3F7FE0"))
                fact("Funding", p.funding.title, p.funding == .selfFunded ? (p.costTotal.map { "≈ \(ApplyWorld.money($0, p.currency)) in total" } ?? "add the costs") : p.fundingNote.isEmpty ? " " : p.fundingNote,
                     p.funding.icon, p.funding.color)
                fact("Course starts", p.termStart.map { Fmt.date($0, "MMM d, yyyy", .gregorian) } ?? "not set", p.focusIntake?.label ?? "add an intake below", "graduationcap.fill", Color(hex: "#3FB6C8"))
                fact("Documents", p.docs.isEmpty ? "—" : "\(p.docsDone)/\(p.docs.count)", p.progress >= 1 && !p.docs.isEmpty ? "all ready 🎉" : "\(Int(p.progress * 100))% ready", "checklist", ap)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [p.status.color.opacity(0.22), .clear], startPoint: .topLeading, endPoint: .center)))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(p.status.color.opacity(0.35)))
    }

    private func fact(_ title: String, _ value: String, _ sub: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.title3).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased()).font(.system(size: 9, weight: .heavy)).foregroundStyle(.tertiary)
                Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1)
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13).fill(tint.opacity(0.10)))
    }
}

// MARK: - card helpers

extension View {
    func applyCard() -> some View {
        self.padding(18).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private func cardTitle(_ title: String, _ icon: String, _ tint: Color = ap) -> some View {
    HStack(spacing: 9) {
        Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint.gradient))
        Text(title).font(.headline)
    }
}

private struct LabeledRow<C: View>: View {
    let title: String
    var width: CGFloat = 140
    @ViewBuilder let content: C
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title).font(.callout).foregroundStyle(.secondary).frame(width: width, alignment: .leading)
            content
        }
    }
}

private func plainField(_ placeholder: String, _ text: Binding<String>) -> some View {
    TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
}

/// A number you can leave empty
private struct AmountField: View {
    @Binding var value: Double?
    var prefix = ""
    var placeholder = "—"
    var body: some View {
        HStack(spacing: 4) {
            if !prefix.isEmpty { Text(prefix).foregroundStyle(.secondary).font(.callout) }
            TextField(placeholder, value: $value, format: .number.precision(.fractionLength(0...2))).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
        }
    }
}

/// A date you can leave empty
private struct OptionalDate: View {
    @Binding var date: Date?
    var body: some View {
        HStack(spacing: 6) {
            if let d = date {
                DatePicker("", selection: Binding(get: { d }, set: { date = $0 }), displayedComponents: .date).labelsHidden()
                Button { date = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).help("Clear the date")
            } else {
                Button { date = Cal.gregorian.date(byAdding: .month, value: 1, to: Date()) } label: { Label("Set date", systemImage: "calendar.badge.plus").font(.callout) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Intakes

/// Each intake (Fall 2027, Spring 2028…) with its own dates. Many universities take students twice a year.
private struct ApplyIntakesCard: View {
    @Binding var prog: ApplyProgram

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                cardTitle("Intakes & dates", "calendar", Color(hex: "#E8A33D"))
                Spacer()
                Menu {
                    ForEach(ApplySeason.allCases) { s in Button { add(s) } label: { Label("Add \(s.title) intake", systemImage: s.icon) } }
                } label: { Label("Add intake", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            if prog.intakes.isEmpty {
                VStack(spacing: 6) {
                    Text("No intake yet").font(.callout.weight(.semibold))
                    Text("Add the term you apply for, with its dates. If the university takes students in spring and in fall, add both: each has its own deadline and start date.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                FlowGrid(minWidth: 380, spacing: 14, maxColumns: 3) {
                    ForEach(prog.intakes) { item in intake(elem($prog.intakes, item.id, ApplyIntake())) }
                }
            }
        }
        .applyCard()
    }

    private func add(_ s: ApplySeason) {
        let year = (prog.intakes.map(\.year).max() ?? Cal.gregorian.component(.year, from: Date())) + (prog.intakes.isEmpty ? 1 : 0)
        var i = ApplyIntake(season: s, year: year)
        if prog.intakes.contains(where: { $0.season == s && $0.year == year }) { i.year += 1 }
        withAnimation { prog.intakes.append(i) }
    }

    private func intake(_ i: Binding<ApplyIntake>) -> some View {
        let v = i.wrappedValue
        let applying = prog.appliedIntake == v.id
        let counting = prog.focusIntake?.id == v.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: v.season.icon).foregroundStyle(.white).frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 9).fill(v.season.color.gradient))
                Picker("", selection: i.season) { ForEach(ApplySeason.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 92)
                Stepper("\(String(v.year))", value: i.year, in: 2024...2040).monospacedDigit()
                Spacer()
                Button { withAnimation { if prog.appliedIntake == v.id { prog.appliedIntake = nil }; prog.intakes.removeAll { $0.id == v.id } } } label: { Image(systemName: "trash").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).help("Delete this intake")
            }
            Button { prog.appliedIntake = applying ? nil : v.id } label: {
                Label(applying ? "Applying for this intake" : "Apply for this intake", systemImage: applying ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 5).frame(maxWidth: .infinity)
                    .background(Capsule().fill(applying ? ap : Color.primary.opacity(0.08)))
                    .foregroundStyle(applying ? Color.white : Color.secondary)
            }
            .buttonStyle(.plain).help("Count the deadlines of this intake. With none chosen, the next one to close counts.")
            LabeledRow(title: "Applications open", width: 128) { OptionalDate(date: i.opens) }
            LabeledRow(title: "Applications close", width: 128) {
                OptionalDate(date: i.closes)
                if let d = v.closes, prog.status.isOpen {
                    let days = ApplyProgram.daysUntil(d)
                    Text(ApplyWorld.countdown(days)).font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(ApplyWorld.urgencyColor(days).opacity(0.18))).foregroundStyle(ApplyWorld.urgencyColor(days))
                }
            }
            LabeledRow(title: "Decision expected", width: 128) { OptionalDate(date: i.decision) }
            LabeledRow(title: "Course starts", width: 128) { OptionalDate(date: i.start) }
            TextField("Note (early round, rolling admission…)", text: i.note).textFieldStyle(.roundedBorder)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(v.season.color.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(v.season.color.opacity(counting ? 0.7 : 0.2), lineWidth: counting ? 2 : 1))
        .overlay(alignment: .topTrailing) {
            if counting && prog.intakes.count > 1 {
                Text("COUNTING NOW").font(.system(size: 8, weight: .heavy)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(v.season.color)).foregroundStyle(.white).offset(x: -8, y: -7)
            }
        }
    }
}

// MARK: - Where

private struct ApplyWhereCard: View {
    @Binding var prog: ApplyProgram
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Where", "mappin.and.ellipse", Color(hex: "#3F7FE0"))
            LabeledRow(title: "Country") { ApplySuggestField(text: $prog.country, placeholder: "Germany", suggestions: countries, flagged: true) }
            LabeledRow(title: "City") { ApplySuggestField(text: $prog.city, placeholder: "Munich", suggestions: cities) }
            LabeledRow(title: "QS ranking") {
                HStack(spacing: 4) {
                    Text("#").foregroundStyle(.secondary)
                    TextField("e.g. 37", value: Binding(get: { prog.qsRank.map { Double($0) } }, set: { prog.qsRank = $0.map { max(1, Int($0)) } }), format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                    Text("QS World University Rankings").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            LabeledRow(title: "Website") {
                plainField("https://…", $prog.website)
                if let u = url(prog.website) { Link(destination: u) { Image(systemName: "arrow.up.right.square") }.help("Open the website") }
            }
            LabeledRow(title: "Application portal") {
                plainField("Where you submit it", $prog.portal)
                if let u = url(prog.portal) { Link(destination: u) { Image(systemName: "arrow.up.right.square") }.help("Open the portal") }
            }
            LabeledRow(title: "Contact") { plainField("Name (admissions, professor…)", $prog.contactName) }
            LabeledRow(title: "Email") {
                plainField("name@university.edu", $prog.contactEmail)
                if !prog.contactEmail.isEmpty, let u = URL(string: "mailto:\(prog.contactEmail)") { Link(destination: u) { Image(systemName: "envelope") }.help("Write an email") }
            }
        }
        .applyCard()
    }

    private func url(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return URL(string: t.contains("://") ? t : "https://" + t)
    }
    private var countries: [String] { Array(Set(store.applyPrograms.map(\.country).filter { !$0.isEmpty } + ApplyWorld.countryNames)).sorted() }
    private var cities: [String] { Array(Set(store.applyPrograms.filter { prog.country.isEmpty || $0.country == prog.country }.map(\.city).filter { !$0.isEmpty })).sorted() }
}

// MARK: - Dates

private struct ApplyDatesCard: View {
    @Binding var prog: ApplyProgram

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Length & other deadlines", "clock.badge.checkmark", Color(hex: "#E8A33D"))
            LabeledRow(title: "Length of program") {
                Stepper(value: Binding(get: { prog.durationMonths ?? prog.degree.usualMonths }, set: { prog.durationMonths = $0 }), in: 1...120, step: 3) {
                    let m = prog.durationMonths ?? prog.degree.usualMonths
                    Text(m % 12 == 0 ? "\(m / 12) year\(m == 12 ? "" : "s")" : "\(m) months").font(.callout.weight(.semibold))
                }
                Menu {
                    ForEach([12, 18, 24, 30, 36, 48, 60], id: \.self) { m in Button(m % 12 == 0 ? "\(m / 12) year\(m == 12 ? "" : "s")" : "\(m) months") { prog.durationMonths = m } }
                } label: { Image(systemName: "list.bullet") }.menuStyle(.borderlessButton).fixedSize().help("Usual lengths")
            }
            Divider().opacity(0.5)
            HStack {
                Text("Other deadlines").font(.callout.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(["Scholarship deadline", "Recommendation letters due", "Documents deadline", "Funding application", "Interview", "Enrollment deposit", "Visa application"], id: \.self) { l in
                        Button(l) { add(l) }
                    }
                    Divider()
                    Button("Other…") { add("") }
                } label: { Label("Add", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
            }
            if prog.extraDeadlines.isEmpty {
                Text("A scholarship deadline, the date letters are due… add as many as you need.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(prog.extraDeadlines) { item in
                let d = elem($prog.extraDeadlines, item.id, ApplyDeadline(label: "", date: Date()))
                HStack(spacing: 8) {
                    Button { d.done.wrappedValue.toggle() } label: { Image(systemName: d.done.wrappedValue ? "checkmark.circle.fill" : "circle").foregroundStyle(d.done.wrappedValue ? Color(hex: "#34C77B") : .secondary) }.buttonStyle(.plain)
                    TextField("Deadline", text: d.label).textFieldStyle(.roundedBorder)
                    DatePicker("", selection: d.date, displayedComponents: .date).labelsHidden()
                    Button { prog.extraDeadlines.removeAll { $0.id == item.id } } label: { Image(systemName: "trash").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                }
                .opacity(item.done ? 0.55 : 1)
            }
        }
        .applyCard()
    }

    private func add(_ label: String) {
        let base = prog.closes ?? Date()
        prog.extraDeadlines.append(ApplyDeadline(label: label, date: base))
    }
}

// MARK: - Money

private struct ApplyMoneyCard: View {
    @Binding var prog: ApplyProgram

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Money", "banknote.fill", Color(hex: "#34C77B"))
            LabeledRow(title: "Currency") {
                Menu {
                    ForEach(ApplyWorld.currencies, id: \.code) { c in Button("\(c.code)  \(c.symbol)") { prog.currency = c.code } }
                } label: { Text("\(prog.currency)  \(ApplyWorld.symbol(prog.currency))").font(.callout.weight(.semibold)) }
                    .menuStyle(.borderlessButton).fixedSize()
                Spacer(minLength: 0)
            }
            LabeledRow(title: "Application fee") {
                AmountField(value: $prog.fee, prefix: ApplyWorld.symbol(prog.currency))
                Toggle("Paid", isOn: $prog.feePaid).toggleStyle(.checkbox)
            }
            Divider().opacity(0.5)
            Text("Funding").font(.callout.weight(.semibold))
            HStack(spacing: 6) {
                ForEach(ApplyFunding.allCases) { f in
                    let on = prog.funding == f
                    Button { prog.funding = f } label: {
                        Label(f.short, systemImage: f.icon).font(.caption.weight(.semibold)).lineLimit(1)
                            .padding(.horizontal, 9).padding(.vertical, 6).frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 9).fill(on ? f.color : f.color.opacity(0.12)))
                            .foregroundStyle(on ? Color.white : f.color)
                    }
                    .buttonStyle(.plain)
                }
            }
            if prog.funding == .funded || prog.funding == .partial {
                LabeledRow(title: "Stipend / month") { AmountField(value: $prog.stipendPerMonth, prefix: ApplyWorld.symbol(prog.currency)) }
            }
            LabeledRow(title: "Funding note") { plainField(prog.funding == .selfFunded ? "Scholarships you could try…" : "Scholarship name, what it covers…", $prog.fundingNote) }
            Divider().opacity(0.5)
            Text(prog.funding == .funded ? "Costs you still pay (optional)" : "What it costs you").font(.callout.weight(.semibold))
            LabeledRow(title: "Tuition / year") { AmountField(value: $prog.tuitionPerYear, prefix: ApplyWorld.symbol(prog.currency)) }
            LabeledRow(title: "Living / year") { AmountField(value: $prog.livingPerYear, prefix: ApplyWorld.symbol(prog.currency)) }
            LabeledRow(title: "Other / year") { AmountField(value: $prog.otherPerYear, prefix: ApplyWorld.symbol(prog.currency)) }
            summary
        }
        .applyCard()
    }

    @ViewBuilder private var summary: some View {
        if let perYear = prog.costPerYear, let total = prog.costTotal {
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Per year").foregroundStyle(.secondary); Spacer(); Text(ApplyWorld.money(perYear, prog.currency)).font(.callout.weight(.semibold)) }
                HStack {
                    Text("Whole program (\(String(format: "%.1f", prog.years)) years)").foregroundStyle(.secondary); Spacer()
                    Text(ApplyWorld.money(total, prog.currency)).font(.title3.weight(.bold))
                }
                if prog.currency != "USD" { HStack { Spacer(); Text(ApplyWorld.moneyUSD(ApplyWorld.usd(total, prog.currency))).font(.caption).foregroundStyle(.secondary) } }
                if let s = prog.stipendPerMonth, s > 0 {
                    Divider().opacity(0.4)
                    HStack { Text("Stipend per year").foregroundStyle(.secondary); Spacer(); Text(ApplyWorld.money(s * 12, prog.currency)).font(.callout.weight(.semibold)).foregroundStyle(Color(hex: "#34C77B")) }
                }
            }
            .font(.callout).padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#34C77B").opacity(0.10)))
        }
    }
}

// MARK: - Requirements

private struct ApplyRequirementsCard: View {
    @Binding var prog: ApplyProgram
    @Environment(AppStore.self) private var store
    private let bands: [Double] = stride(from: 4.0, through: 9.0, by: 0.5).map { $0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Requirements", "graduationcap.fill", Color(hex: "#E8384F"))
            LabeledRow(title: "IELTS overall") { bandPicker($prog.ieltsOverall) }
            LabeledRow(title: "IELTS each skill") { bandPicker($prog.ieltsEachSkill) }
            comparison
            Divider().opacity(0.5)
            HStack {
                Text("More requirements").font(.callout.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(missing, id: \.title) { r in Button(r.title) { add(r.title) } }
                    Divider()
                    Button("Something else…") { add("") }
                } label: { Label("Add", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
            }
            if prog.requirements.isEmpty {
                Text("GPA, recommendation letters, GRE, work experience… add what this program asks for. Tap the circle to say whether you meet it.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(prog.requirements) { item in row(elem($prog.requirements, item.id, ApplyRequirement(title: ""))) }
            // quick add
            let quick = Array(missing.prefix(7))
            if !quick.isEmpty {
                ChipFlow(spacing: 6) {
                    ForEach(quick, id: \.title) { r in
                        Button { add(r.title) } label: {
                            Label(r.title, systemImage: "plus").font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.07))).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            LabeledRow(title: "Other notes") { plainField("Anything else they ask for…", $prog.otherRequirements) }
        }
        .applyCard()
    }

    private var missing: [(title: String, hint: String)] { ApplyRequirement.presets.filter { r in !prog.requirements.contains { $0.title == r.title } } }

    private func add(_ title: String) { withAnimation { prog.requirements.append(ApplyRequirement(title: title)) } }

    private func row(_ r: Binding<ApplyRequirement>) -> some View {
        let v = r.wrappedValue
        let hint = ApplyRequirement.presets.first { $0.title == v.title }?.hint ?? "What they ask"
        return HStack(spacing: 8) {
            Button { r.state.wrappedValue = v.state.next } label: { Image(systemName: v.state.icon).font(.title3).foregroundStyle(v.state.color) }
                .buttonStyle(.plain).help(v.state.title + " (click to change)")
            TextField("Requirement", text: r.title).textFieldStyle(.plain).font(.callout.weight(.semibold)).frame(width: 165)
            TextField(hint, text: r.value).textFieldStyle(.roundedBorder)
            Button { prog.requirements.removeAll { $0.id == v.id } } label: { Image(systemName: "trash").foregroundStyle(.tertiary) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(v.state.color.opacity(0.08)))
    }

    private func bandPicker(_ v: Binding<Double?>) -> some View {
        HStack {
            Picker("", selection: v) {
                Text("Not required / unknown").tag(Double?.none)
                ForEach(bands, id: \.self) { Text(IELTSTest.format($0)).tag(Double?.some($0)) }
            }
            .labelsHidden().frame(width: 190)
            Spacer(minLength: 0)
        }
    }

    /// Your own IELTS scores (from the IELTS page) against what this program asks
    @ViewBuilder private var comparison: some View {
        let mine = store.ieltsOverall
        let weakest = IELTSSkill.allCases.compactMap { store.ieltsAverage($0).map(IELTSTest.roundBand) }.min()
        if prog.ieltsOverall != nil || prog.ieltsEachSkill != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let need = prog.ieltsOverall { line("Overall", mine, need) }
                if let need = prog.ieltsEachSkill { line("Weakest skill", weakest, need) }
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        }
    }

    private func line(_ title: String, _ mine: Double?, _ need: Double) -> some View {
        let ok = mine.map { $0 >= need }
        return HStack(spacing: 8) {
            Image(systemName: ok == nil ? "questionmark.circle" : (ok! ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                .foregroundStyle(ok == nil ? Color.secondary : (ok! ? Color(hex: "#34C77B") : Color(hex: "#E8A33D")))
            Text("\(title): needs \(IELTSTest.format(need))").font(.callout)
            Spacer()
            Text(mine == nil ? "add IELTS tests to compare" : (ok! ? "you have \(IELTSTest.format(mine)) ✓" : "you have \(IELTSTest.format(mine)), \(IELTSTest.format(need - mine!)) to go"))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Checklist

private struct ApplyChecklistCard: View {
    @Binding var prog: ApplyProgram
    @State private var newTitle = ""
    @State private var filter = 0     // 0 all, 1 to do, 2 done
    @State private var openNote: UUID?
    @State private var dueFor: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.10), lineWidth: 7)
                    Circle().trim(from: 0, to: prog.progress).stroke(prog.progress >= 1 ? Color(hex: "#34C77B") : ap, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text(prog.docs.isEmpty ? "—" : "\(Int(prog.progress * 100))%").font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(width: 54, height: 54).animation(.easeOut, value: prog.progress)
                VStack(alignment: .leading, spacing: 2) {
                    cardTitle("Checklist", "checklist", ap)
                    Text(prog.docs.isEmpty ? "Add what you need to prepare" : (prog.progress >= 1 ? "Everything is ready 🎉" : "\(prog.docsDone) of \(prog.docs.count) done · \(prog.docs.count - prog.docsDone) to go"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $filter) { Text("All").tag(0); Text("To do").tag(1); Text("Done").tag(2) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                Menu {
                    let missing = ApplyProgram.commonDocs.filter { c in !prog.docs.contains { $0.title == c } }
                    ForEach(missing, id: \.self) { c in Button(c) { prog.docs.append(ApplyDoc(title: c)) } }
                    Divider()
                    Button("Mark all as done") { for i in prog.docs.indices { prog.docs[i].done = true } }
                    Button("Mark all as to do") { for i in prog.docs.indices { prog.docs[i].done = false } }
                    Button("Start again with the usual list") { prog.docs = ApplyProgram.defaultDocs(for: prog.degree) }
                } label: { Label("More", systemImage: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
            }
            ForEach(prog.docs) { item in
                if filter == 0 || (filter == 1 && !item.done) || (filter == 2 && item.done) { row(elem($prog.docs, item.id, ApplyDoc(title: ""))) }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(ap)
                TextField("Add a document or step and press Enter…", text: $newTitle).textFieldStyle(.plain)
                    .onSubmit {
                        let t = newTitle.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        withAnimation { prog.docs.append(ApplyDoc(title: t)) }; newTitle = ""
                    }
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
        }
        .applyCard()
    }

    private func row(_ d: Binding<ApplyDoc>) -> some View {
        let doc = d.wrappedValue
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { withAnimation(.easeOut(duration: 0.15)) { d.done.wrappedValue.toggle() } } label: {
                    Image(systemName: doc.done ? "checkmark.circle.fill" : "circle").font(.title3)
                        .foregroundStyle(doc.done ? Color(hex: "#34C77B") : Color.secondary)
                }
                .buttonStyle(.plain)
                TextField("What to prepare", text: d.title).textFieldStyle(.plain).font(.body.weight(.medium))
                    .strikethrough(doc.done).foregroundStyle(doc.done ? Color.secondary : Color.primary)
                if let due = doc.due {
                    let days = ApplyProgram.daysUntil(due)
                    Button { dueFor = (dueFor == doc.id ? nil : doc.id) } label: {
                        Label(applyDate(due), systemImage: "clock").font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill((doc.done ? Color.secondary : ApplyWorld.urgencyColor(days)).opacity(0.16)))
                            .foregroundStyle(doc.done ? Color.secondary : ApplyWorld.urgencyColor(days))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { d.due.wrappedValue = Cal.gregorian.date(byAdding: .day, value: 7, to: Date()); dueFor = doc.id } label: { Image(systemName: "calendar.badge.plus").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).help("Set a due date")
                }
                Button { openNote = (openNote == doc.id ? nil : doc.id) } label: {
                    Image(systemName: doc.note.isEmpty ? "note.text" : "note.text.badge.plus").foregroundStyle(doc.note.isEmpty ? Color.secondary.opacity(0.5) : ap)
                }
                .buttonStyle(.plain).help("Note")
                Button { withAnimation { prog.docs.removeAll { $0.id == doc.id } } } label: { Image(systemName: "trash").foregroundStyle(.tertiary) }.buttonStyle(.plain)
            }
            if dueFor == doc.id, doc.due != nil {
                HStack {
                    DatePicker("Due", selection: Binding(get: { d.due.wrappedValue ?? Date() }, set: { d.due.wrappedValue = $0 }), displayedComponents: .date).labelsHidden()
                    Button("Remove date") { d.due.wrappedValue = nil; dueFor = nil }.controlSize(.small)
                    Button("Done") { dueFor = nil }.controlSize(.small)
                }
                .padding(.leading, 32)
            }
            if openNote == doc.id || (!doc.note.isEmpty && openNote == nil && false) {
                TextField("Note (who writes it, where to get it…)", text: d.note, axis: .vertical).textFieldStyle(.roundedBorder).padding(.leading, 32)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(doc.done ? Color(hex: "#34C77B").opacity(0.07) : Color.primary.opacity(0.05))
        )
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(doc.done ? Color(hex: "#34C77B") : ap.opacity(0.5)).frame(width: 3).padding(.vertical, 7) }
    }
}
