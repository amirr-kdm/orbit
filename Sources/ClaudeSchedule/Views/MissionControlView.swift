import SwiftUI
import Charts

/// Mission Control: the home of notes, English exam preparation and (soon) university applications.
/// Three big doors; each opens a page of its own, with a way back at the top.
struct MissionControlView: View {
    enum Route { case home, notes, exams, ielts }
    @State private var route = Route.home
    @Environment(Router.self) private var router
    /// The exam you chose ("ielts"); its door on the first page then shows its name and picture
    @AppStorage("mission.exam") private var exam = ""

    var body: some View {
        Group {
            switch route {
            case .home: home
            case .notes: page("Notes", back: .home) { PlannerView() }
            case .exams: page("English Exam", back: .home) { ExamPicker(open: { exam = "ielts"; route = .ielts }) }
            case .ielts: page("IELTS", back: .home, trailing: AnyView(
                Button { exam = ""; route = .exams } label: { Label("Change exam", systemImage: "arrow.triangle.2.circlepath").font(.caption) }
                    .buttonStyle(.borderless))) { IELTSView() }
            }
        }
        .navigationTitle("Mission Control")
        .onChange(of: router.missionHome) { _, _ in route = .home }
    }

    private func page<C: View>(_ title: String, back: Route, trailing: AnyView? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { route = back } label: { Label("Mission Control", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(title).font(.headline)
                Spacer()
                Group { if let trailing { trailing } else { Color.clear.frame(height: 1) } }.frame(width: 130, alignment: .trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var home: some View {
        VStack(spacing: 34) {
            VStack(spacing: 6) {
                Text("Mission Control").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Where do you want to go?").foregroundStyle(.secondary)
            }
            HStack(spacing: 26) {
                BigDoor(title: "Notes", subtitle: "Planners, brainstorm and notes", icon: "note.text", tint: Color(hex: "#E8A33D")) { route = .notes }
                if exam == "ielts" {
                    BigDoor(title: "IELTS", subtitle: "Your tests, bands and progress", icon: "text.book.closed.fill", tint: Color(hex: "#E8384F")) { route = .ielts }
                } else {
                    BigDoor(title: "English Exam", subtitle: "IELTS and TOEFL: scores and progress", icon: "graduationcap.fill", tint: Color(hex: "#3F7FE0")) { route = .exams }
                }
                BigDoor(title: "Apply", subtitle: "University applications", icon: "paperplane.fill", tint: Color(hex: "#8E6BD8"), soon: true) {}
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A big card-button (with a "Coming soon" state)
struct BigDoor: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    var soon = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 46, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(Circle().fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .shadow(color: tint.opacity(0.5), radius: hover && !soon ? 18 : 8)
                Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if soon { Text("COMING SOON").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(tint) }
            }
            .padding(24)
            .frame(maxWidth: 300, minHeight: 280)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(tint.opacity(hover && !soon ? 0.9 : 0.3), lineWidth: 2))
            .scaleEffect(hover && !soon ? 1.03 : 1)
            .opacity(soon ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(soon)
        .onHover { hover = $0 }
        .animation(.spring(duration: 0.25), value: hover)
    }
}

/// "Which exam are you preparing for?"
struct ExamPicker: View {
    let open: () -> Void
    var body: some View {
        VStack(spacing: 34) {
            VStack(spacing: 6) {
                Text("Which English exam are you preparing for?").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Pick one to open its page").foregroundStyle(.secondary)
            }
            HStack(spacing: 26) {
                BigDoor(title: "IELTS", subtitle: "Log your practice tests and follow your bands", icon: "text.book.closed.fill", tint: Color(hex: "#E8384F"), action: open)
                BigDoor(title: "TOEFL", subtitle: "Scores and progress", icon: "globe.americas.fill", tint: Color(hex: "#3F7FE0"), soon: true) {}
            }
            .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - IELTS

struct IELTSView: View {
    @Environment(AppStore.self) private var store
    // the band you want in each skill; the overall target is worked out from them
    @AppStorage("ielts.target.listening") private var tL = 7.0
    @AppStorage("ielts.target.reading") private var tR = 7.0
    @AppStorage("ielts.target.writing") private var tW = 7.0
    @AppStorage("ielts.target.speaking") private var tS = 7.0
    private var target: Double { IELTSTest.roundBand((tL + tR + tW + tS) / 4) }
    private func targetBinding(_ s: IELTSSkill) -> Binding<Double> {
        switch s { case .listening: $tL; case .reading: $tR; case .writing: $tW; case .speaking: $tS }
    }
    @State private var tab = 0
    @State private var editing: IELTSTest?
    @State private var hidden: Set<IELTSSkill> = []
    @State private var confirmClear = false
    @State private var filter: UUID?          // nil = all tests
    @State private var showCategories = false

    private var shownTests: [IELTSTest] { store.ieltsByDate.filter { filter == nil || $0.categoryID == filter } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                HStack {
                    Picker("", selection: $tab) { Text("Tests").tag(0); Text("Exam report").tag(1) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                    Spacer()
                    if !store.ieltsTests.isEmpty {
                        Button(role: .destructive) { confirmClear = true } label: { Label("Delete all", systemImage: "trash") }
                    }
                    Button { editing = IELTSTest(name: "Test \(store.ieltsTests.count + 1)") } label: { Label("Add test", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
                categoryBar
                if store.ieltsTests.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.book.closed").font(.system(size: 38)).foregroundStyle(.tertiary)
                        Text("No tests yet").font(.headline)
                        Text("Add a practice test with the band of each skill. Your overall band and the charts appear here.").font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 50)
                } else if tab == 0 { testList } else { report }
            }
            .padding(24)
        }
        .sheet(item: $editing) { IELTSTestSheet(test: $0) }
        .sheet(isPresented: $showCategories) { IELTSCategoriesSheet() }
        .confirmationDialog("Delete all \(store.ieltsTests.count) IELTS tests?", isPresented: $confirmClear) {
            Button("Delete all my tests", role: .destructive) { store.ieltsTests = [] }
        } message: { Text("Your scores and charts are removed. This can't be undone.") }
    }

    // top cards
    private var summary: some View {
        let latest = store.ieltsByDate.first(where: { $0.overall != nil })?.overall
        let best = store.ieltsTests.compactMap(\.overall).max()
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                tile("Your overall", IELTSTest.format(store.ieltsOverall), "average of all your tests", Color(hex: "#E8384F"), big: true)
                tile("Latest test", IELTSTest.format(latest), "overall of the newest test", .accentColor)
                tile("Best test", IELTSTest.format(best), "highest overall", .green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("TARGET OVERALL").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    Text(IELTSTest.format(target)).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.green)
                    Text(store.ieltsOverall.map { $0 >= target ? "You are there 🎉" : "\(IELTSTest.format(target - $0)) to go" } ?? "from your skill targets below")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.08)))
            }
            HStack(spacing: 12) {
                ForEach(IELTSSkill.allCases) { s in
                    let avg = store.ieltsAverage(s)
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: s.icon).foregroundStyle(s.color).frame(width: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.title).font(.callout)
                                Text(avg.map { "average " + String(format: "%.2f", $0) } ?? "no score yet").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(IELTSTest.format(avg.map(IELTSTest.roundBand))).font(.title2.weight(.bold).monospacedDigit())
                        }
                        Divider().opacity(0.4)
                        HStack(spacing: 6) {
                            Text("🎯 Target").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text(IELTSTest.format(targetBinding(s).wrappedValue)).font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(.green)
                            Stepper("", value: targetBinding(s), in: 4...9, step: 0.5).labelsHidden()
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(s.color.opacity(0.12)))
                }
            }
            if store.ieltsOverall == nil && !store.ieltsTests.isEmpty {
                Text("Your overall needs at least one score for each of the four skills.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ sub: String, _ tint: Color, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(tint)
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(big ? 0.16 : 0.08)))
    }

    /// All / Cambridge / Mocks / … with a button to manage the list
    private var categoryBar: some View {
        HStack(spacing: 8) {
            chip("All", nil)
            ForEach(store.ieltsCategories) { chip($0.name, $0.id) }
            Button { showCategories = true } label: { Label("Categories", systemImage: "slider.horizontal.3").font(.caption.weight(.semibold)) }
                .buttonStyle(.borderless)
            Spacer()
        }
    }

    private func chip(_ title: String, _ id: UUID?) -> some View {
        let on = filter == id
        return Button { filter = id } label: {
            Text(title).font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // the tests
    private var testList: some View {
        VStack(spacing: 8) {
            if shownTests.isEmpty { Text("No tests in this category yet.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 30) }
            ForEach(shownTests) { t in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(t.name.isEmpty ? "Test" : t.name).font(.headline)
                            if let c = store.ieltsCategory(t.categoryID) {
                                Text(c.name).font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            }
                        }
                        Text(t.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        if !t.note.isEmpty { Text(t.note).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                    }
                    Spacer()
                    ForEach(IELTSSkill.allCases) { s in
                        VStack(spacing: 1) {
                            Image(systemName: s.icon).font(.caption2).foregroundStyle(s.color)
                            Text(IELTSTest.format(t.band(s))).font(.callout.weight(.semibold).monospacedDigit())
                        }
                        .frame(width: 46)
                    }
                    VStack(spacing: 1) {
                        Text("OVERALL").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                        Text(IELTSTest.format(t.overall)).font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(t.overall.map { $0 >= target ? Color.green : Color.primary } ?? .secondary)
                    }
                    .frame(width: 70)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .contentShape(Rectangle())
                .onTapGesture { editing = t }
                .contextMenu {
                    Button("Edit") { editing = t }
                    Button("Delete", role: .destructive) { store.deleteIELTS(t.id) }
                }
                .overlay(alignment: .topTrailing) {
                    Button { store.deleteIELTS(t.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).padding(6).help("Delete this test")
                }
            }
            Text("Click a test to edit it. The ✕ deletes it.").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var report: some View { IELTSReport(tests: shownTests.sorted { $0.date < $1.date }, target: target, tL: tL, tR: tR, tW: tW, tS: tS) }
}

/// Add or edit a test
struct IELTSTestSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var test: IELTSTest

    init(test: IELTSTest) { _test = State(initialValue: test) }

    private let bands: [Double] = stride(from: 0.0, through: 9.0, by: 0.5).map { $0 }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $test.name, prompt: Text("e.g. Cambridge 18, Test 2"))
                DatePicker("Date", selection: $test.date, displayedComponents: .date)
                Picker("Category", selection: $test.categoryID) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.ieltsCategories) { Text($0.name).tag(Optional($0.id)) }
                }
                ForEach(IELTSSkill.allCases) { s in
                    Picker(selection: Binding(get: { test.band(s) }, set: { test.set(s, $0) })) {
                        Text("—").tag(Double?.none)
                        ForEach(bands, id: \.self) { Text(IELTSTest.format($0)).tag(Double?.some($0)) }
                    } label: { Label(s.title, systemImage: s.icon) }
                }
                LabeledContent("Overall") {
                    Text(IELTSTest.format(test.overall)).font(.title3.weight(.bold).monospacedDigit())
                }
                TextField("Note (optional)", text: $test.note)
            }
            .formStyle(.grouped)
            Text("The overall is worked out for you from the four skills, rounded the IELTS way.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { store.upsertIELTS(test); dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(IELTSSkill.allCases.allSatisfy { test.band($0) == nil })
            }
            .padding()
        }
        .frame(width: 440)
    }
}


/// Add, rename or delete the categories of tests (Cambridge and Mocks are only the first two; they can be changed too)
struct IELTSCategoriesSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test categories").font(.title3.weight(.bold))
            Text("Group your tests: a Cambridge book, mocks, a website you practise on. Deleting a category keeps its tests.").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(store.ieltsCategories.enumerated()), id: \.element.id) { i, c in
                HStack {
                    TextField("Name", text: Binding(get: { store.ieltsCategories.indices.contains(i) ? store.ieltsCategories[i].name : "" },
                                                    set: { if store.ieltsCategories.indices.contains(i) { store.ieltsCategories[i].name = $0 } }))
                    Text("\(store.ieltsTests.filter { $0.categoryID == c.id }.count) tests").font(.caption).foregroundStyle(.secondary)
                    Button(role: .destructive) { store.deleteIELTSCategory(c.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("New category", text: $newName).onSubmit(add)
                Button("Add", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 400)
    }

    private func add() { store.addIELTSCategory(newName); newName = "" }
}
