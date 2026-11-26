import SwiftUI
import Charts

/// Mission Control → Apply: every university and program you apply to. Browse by country → city → university, sort, filter,
/// follow deadlines and see money and progress at a glance. A click opens one program (ApplyDetailView).
struct ApplyView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    /// The open program and the tab live in the router, so back / forward can return to them
    private var openID: UUID? { get { router.applyOpen } nonmutating set { router.applyOpen = newValue } }
    private var tab: Int { router.applyTab }
    private var tabBinding: Binding<Int> { Binding(get: { router.applyTab }, set: { router.applyTab = $0 }) }
    @State private var country: String?
    @State private var city: String?
    @State private var university: String?
    @State private var status: ApplyStatus?
    @State private var funding: ApplyFunding?
    @State private var tier: ApplyTier?
    @State private var starredOnly = false
    @State private var search = ""
    @AppStorage("apply.sort") private var sortRaw = "deadline"
    @State private var showAdd = false
    @AppStorage("apply.view") private var viewMode = "grid"

    private var all: [ApplyProgram] { store.applyPrograms }


    var body: some View {
        Group {
            if let id = openID, store.applyProgram(id) != nil {
                ApplyDetailView(id: id) { openID = nil }
            } else {
                main
            }
        }
        .sheet(isPresented: $showAdd) { AddApplySheet(country: country, city: city) { router.applyOpen = $0; router.applyTab = 0 } }
    }

    // MARK: main page

    private var main: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("", selection: tabBinding) {
                    Text("Programs").tag(0); Text("Professors").tag(1); Text("Deadlines").tag(2); Text("Overview").tag(3)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 430)
                Spacer()
                Button { showAdd = true } label: { Label("Add program", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(Color(hex: "#8E6BD8"))
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            if all.isEmpty { emptyState }
            else {
                switch tab {
                case 1: ApplyAllProfessorsTab()
                case 2: ApplyDeadlinesTab(open: { openID = $0 })
                case 3: ApplyOverviewTab()
                default: programsTab
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "paperplane.circle.fill").font(.system(size: 64)).foregroundStyle(Color(hex: "#8E6BD8"))
            Text("Your applications start here").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Add each university or program you want. For every one you keep its status, deadlines, fees, funding, costs and a checklist of documents.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
            VStack(alignment: .leading, spacing: 8) {
                tip("globe.europe.africa.fill", "Browse by country, then city, then university")
                tip("calendar.badge.clock", "See what is due this week across all programs")
                tip("checklist", "A checklist of documents for each program")
                tip("banknote.fill", "Funding, fees and the real cost of each program")
            }
            Button { showAdd = true } label: { Label("Add your first program", systemImage: "plus").font(.headline).padding(.horizontal, 12).padding(.vertical, 4) }
                .buttonStyle(.borderedProminent).tint(Color(hex: "#8E6BD8")).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        Label { Text(text).font(.callout) } icon: { Image(systemName: icon).foregroundStyle(Color(hex: "#8E6BD8")).frame(width: 22) }
    }

    // MARK: programs tab

    private var programsTab: some View {
        let shown = sorted(filtered)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filterRows
                toolbar(shown.count)
                if shown.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 32)).foregroundStyle(.tertiary)
                        Text("No program matches").font(.headline)
                        Button("Clear filters") { clearFilters() }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 50)
                } else {
                    if viewMode == "list" {
                        // columns when there is room, two lines per row when the window is narrow
                        ViewThatFits(in: .horizontal) {
                            VStack(spacing: 8) {
                                ApplyRowHeader()
                                ForEach(shown) { p in ApplyRow(program: p, open: { openID = p.id }) }
                            }
                            VStack(spacing: 8) {
                                ForEach(shown) { p in ApplyRow(program: p, compact: true, open: { openID = p.id }) }
                            }
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 16, alignment: .top)], spacing: 16) {
                            ForEach(shown) { p in
                                ApplyCard(program: p, open: { openID = p.id })
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var filterRows: some View {
        ApplyLocationFilters(pool: all, country: $country, city: $city, university: $university)
    }

    private func toolbar(_ count: Int) -> some View {
        ChipFlow(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search university, program, city…", text: $search).textFieldStyle(.plain)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6).frame(width: 250)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.07)))

            filterMenu("Status", "flag.fill", status?.title) {
                Button("Any status") { status = nil }
                ForEach(ApplyStatus.allCases) { s in Button { status = s } label: { Label(s.title, systemImage: s.icon) } }
            }
            filterMenu("Funding", "banknote", funding?.title) {
                Button("Any funding") { funding = nil }
                ForEach(ApplyFunding.allCases) { f in Button { funding = f } label: { Label(f.title, systemImage: f.icon) } }
            }
            filterMenu("Tier", "scope", tier?.title) {
                Button("Any tier") { tier = nil }
                ForEach(ApplyTier.allCases) { t in Button(t.title) { tier = t } }
            }
            Toggle(isOn: $starredOnly) { Label("Starred", systemImage: "star.fill") }
                .toggleStyle(.button).controlSize(.small).tint(.yellow)
            Text("\(count) program\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            ViewModeToggle(mode: $viewMode)
            Menu {
                Picker("Sort by", selection: $sortRaw) {
                    ForEach(Self.sorts, id: \.0) { Text($0.1).tag($0.0) }
                }.pickerStyle(.inline)
            } label: { Label("Sort: " + (Self.sorts.first { $0.0 == sortRaw }?.1 ?? ""), systemImage: "arrow.up.arrow.down").font(.callout.weight(.semibold)) }
                .menuStyle(.borderlessButton).fixedSize()
        }
    }

    private func filterMenu<C: View>(_ title: String, _ icon: String, _ value: String?, @ViewBuilder _ content: () -> C) -> some View {
        Menu { content() } label: {
            Label(value ?? title, systemImage: icon).font(.callout.weight(.semibold))
                .foregroundStyle(value == nil ? Color.primary : Color(hex: "#8E6BD8"))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func clearFilters() { country = nil; city = nil; university = nil; status = nil; funding = nil; tier = nil; starredOnly = false; search = "" }

    // MARK: filtering and sorting

    private var filtered: [ApplyProgram] {
        all.filter { p in
            (country == nil || p.country == country) && (city == nil || p.city == city) && (university == nil || p.university == university)
                && (status == nil || p.status == status) && (funding == nil || p.funding == funding) && (tier == nil || p.tier == tier)
                && (!starredOnly || p.starred) && p.matches(search)
        }
    }

    static let sorts: [(String, String)] = [
        ("deadline", "Next deadline (soonest)"), ("feeLow", "Application fee (low → high)"), ("feeHigh", "Application fee (high → low)"),
        ("costLow", "Total cost (low → high)"), ("costHigh", "Total cost (high → low)"), ("tuitionLow", "Tuition per year (low → high)"),
        ("progressHigh", "Checklist (most done)"), ("progressLow", "Checklist (least done)"), ("status", "Status"),
        ("qsBest", "QS ranking (best first)"), ("qsWorst", "QS ranking (lowest first)"), ("term", "Term start"), ("name", "University A → Z"), ("country", "Country, city, university"), ("newest", "Recently added"), ("starred", "Starred first")
    ]

    /// Sorts by a key; programs without that value go last
    private func by<T: Comparable>(_ list: [ApplyProgram], desc: Bool = false, _ key: (ApplyProgram) -> T?) -> [ApplyProgram] {
        let have = list.filter { key($0) != nil }, none = list.filter { key($0) == nil }
        return have.sorted { desc ? key($0)! > key($1)! : key($0)! < key($1)! } + none
    }

    private func sorted(_ list: [ApplyProgram]) -> [ApplyProgram] {
        func feeUSD(_ p: ApplyProgram) -> Double? { p.fee.map { ApplyWorld.usd($0, p.currency) } }
        func costUSD(_ p: ApplyProgram) -> Double? { p.costTotal.map { ApplyWorld.usd($0, p.currency) } }
        switch sortRaw {
        case "feeLow": return by(list) { feeUSD($0) }
        case "feeHigh": return by(list, desc: true) { feeUSD($0) }
        case "costLow": return by(list) { costUSD($0) }
        case "costHigh": return by(list, desc: true) { costUSD($0) }
        case "tuitionLow": return by(list) { p in p.tuitionPerYear.map { ApplyWorld.usd($0, p.currency) } }
        case "progressHigh": return by(list, desc: true) { $0.docs.isEmpty ? nil : $0.progress }
        case "progressLow": return by(list) { $0.docs.isEmpty ? nil : $0.progress }
        case "status": return list.sorted { (ApplyStatus.allCases.firstIndex(of: $0.status) ?? 0) < (ApplyStatus.allCases.firstIndex(of: $1.status) ?? 0) }
        case "qsBest": return by(list) { $0.qsRank }
        case "qsWorst": return by(list, desc: true) { $0.qsRank }
        case "term": return by(list) { $0.termStart }
        case "name": return list.sorted { $0.university.localizedCaseInsensitiveCompare($1.university) == .orderedAscending }
        case "country":
            return list.sorted { a, b in
                [a.country, a.city, a.university].map { $0.lowercased() }.lexicographicallyPrecedes([b.country, b.city, b.university].map { $0.lowercased() })
            }
        case "newest": return list.sorted { $0.created > $1.created }
        case "starred": return list.sorted { ($0.starred ? 0 : 1, $0.university.lowercased()) < ($1.starred ? 0 : 1, $1.university.lowercased()) }
        default: return by(list) { $0.nextDeadline?.date }
        }
    }
}
