import AppKit
import SwiftUI

/// Picks the screen: login, waiting for approval, or the app
struct RootView: View {
    @Environment(AccountService.self) private var account

    var body: some View {
        switch account.state {
        case .noServer, .approved: ContentView()
        case .loading: SpaceBackdrop { ProgressView().controlSize(.large).tint(.white) }
        case .signedOut: LoginView(mode: .login)
        case .needsUpgrade: LoginView(mode: .upgrade)
        case .pending: PendingView()
        }
    }
}

// MARK: - Space backdrop

/// Deep space with twinkling stars and soft nebulas (shared by the login and waiting screens)
struct SpaceBackdrop<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#0B0820"), Color(hex: "#120B2E"), Color(hex: "#05040F")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: "#7C3AED").opacity(0.35), .clear], center: .init(x: 0.18, y: 0.25), startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Color(hex: "#22D3EE").opacity(0.18), .clear], center: .init(x: 0.85, y: 0.85), startRadius: 10, endRadius: 480)
            TimelineView(.animation(minimumInterval: 1 / 20, paused: AppActivity.paused)) { t in
                Canvas { ctx, size in
                    var rng = SeededRandom(seed: "login-stars")
                    let time = t.date.timeIntervalSinceReferenceDate
                    for k in 0..<160 {
                        let x = rng.next() * size.width, y = rng.next() * size.height
                        let s = 0.6 + rng.next() * 1.8
                        let tw = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * (0.6 + rng.next() * 1.6) + Double(k)))
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)), with: .color(.white.opacity(tw * 0.85)))
                    }
                }
            }
            content
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

/// A bundled picture (Resources/art)
private struct Art: View {
    let name: String
    var body: some View {
        if let img = PlanetPainter.bundleImage(name) {
            Image(nsImage: img).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }
}

// MARK: - Login / sign up / upgrade

struct LoginView: View {
    enum Mode { case login, signup, upgrade }

    @Environment(AccountService.self) private var account
    @State var mode: Mode
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var start = Date()

    var body: some View {
        SpaceBackdrop {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1 / 30, paused: AppActivity.paused)) { t in
                    let time = t.date.timeIntervalSince(start)
                    ZStack {
                        // Satellite drifting through its nebula (top left)
                        Art(name: "login-satellite")
                            .frame(width: 230, height: 230)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                            .shadow(color: Color(hex: "#A78BFA").opacity(0.6), radius: 40)
                            .rotationEffect(.degrees(time * 6))
                            .position(x: geo.size.width * 0.12 + sin(time / 3) * 12, y: geo.size.height * 0.2 + cos(time / 4) * 10)
                            .opacity(0.9)

                        HStack(spacing: 56) {
                            hero(time)
                            form
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Astronaut cat floating past the form
                        Art(name: "login-cat")
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(sin(time / 2) * 12 - 8))
                            .position(x: geo.size.width * 0.86 + sin(time / 2.5) * 18, y: geo.size.height * 0.16 + cos(time / 1.8) * 14)
                    }
                }
            }
        }
        .onAppear(perform: prefill)
        .onChange(of: account.state) { _, _ in prefill() }
    }

    private func hero(_ time: Double) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Art(name: "login-abduction")
                    .frame(width: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                // The tractor beam glows
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(RadialGradient(colors: [Color(hex: "#FEF3C7").opacity(0.18 + 0.12 * sin(time * 2)), .clear],
                                         center: .init(x: 0.5, y: 0.55), startRadius: 10, endRadius: 220))
                    .frame(width: 330, height: 440)
                    .allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: Color(hex: "#22D3EE").opacity(0.35), radius: 30, y: 10)
            .offset(y: sin(time / 1.6) * 6)
            VStack(spacing: 4) {
                Text("Study. Level up. Get abducted by good habits.")
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Your planner, timer and galaxy — synced to your account")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 0) {
                    Text("ORBIT").font(.system(size: 30, weight: .black, design: .monospaced)).tracking(6)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }

            if mode == .upgrade {
                Text("Orbit now uses accounts. Add an email and a password to keep your friends, groups, galaxy and data — and to get it all back on any Mac.")
                    .font(.callout).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 0) {
                    tab("Log in", .login)
                    tab("Sign up", .signup)
                }
                .padding(3)
                .background(Capsule().fill(.white.opacity(0.08)))
            }

            VStack(spacing: 10) {
                field("envelope", "Email", text: $email)
                if mode != .login { field("at", "Username", text: $username) }
                field("lock", "Password", text: $password, secure: true)
                if mode != .login { field("lock.rotation", "Repeat password", text: $confirm, secure: true) }
            }

            if let m = account.message {
                Label(m, systemImage: "exclamationmark.circle.fill")
                    .font(.callout).foregroundStyle(Color(hex: "#FCA5A5"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: submit) {
                HStack {
                    if account.busy { ProgressView().controlSize(.small).tint(.white) }
                    Text(buttonTitle).font(.headline)
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(LinearGradient(colors: [Color(hex: "#8B5CF6"), Color(hex: "#22D3EE")],
                                                          startPoint: .leading, endPoint: .trailing)))
                .foregroundStyle(.white)
                .shadow(color: Color(hex: "#8B5CF6").opacity(0.5), radius: 14, y: 4)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(account.busy)

            Text(mode == .signup ? "New accounts are checked by the owner before they can use Orbit. You'll get in as soon as you're approved."
                 : mode == .upgrade ? "Your friends, groups and stats stay exactly as they are."
                 : "Forgot your password? Ask the Orbit owner to reset it.")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(width: 400)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
    }

    private var subtitle: String {
        switch mode {
        case .login: "Welcome back, explorer"
        case .signup: "Create your account"
        case .upgrade: "Welcome back, \(account.profile?.name ?? "explorer")"
        }
    }

    private var buttonTitle: String {
        switch mode {
        case .login: "Log in"
        case .signup: "Create account"
        case .upgrade: "Create my account"
        }
    }

    private func tab(_ title: String, _ m: Mode) -> some View {
        Button { withAnimation(.spring(duration: 0.3)) { mode = m; account.message = nil } } label: {
            Text(title).font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(Capsule().fill(mode == m ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.clear)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func field(_ icon: String, _ title: String, text: Binding<String>, secure: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.white.opacity(0.5)).frame(width: 18)
            Group {
                if secure { SecureField(title, text: text) } else { TextField(title, text: text) }
            }
            .textFieldStyle(.plain)
            .font(.body)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1)))
    }

    private func prefill() {
        if mode == .upgrade, username.isEmpty { username = account.profile?.username ?? account.profile?.name.replacingOccurrences(of: " ", with: "") ?? "" }
    }

    private func submit() {
        if mode != .login, password != confirm { account.message = "The two passwords don't match."; return }
        Task {
            switch mode {
            case .login: await account.signIn(email: email, password: password)
            case .signup: await account.signUp(email: email, username: username, password: password)
            case .upgrade: await account.upgrade(email: email, username: username, password: password)
            }
        }
    }
}

// MARK: - Waiting for approval

struct PendingView: View {
    @Environment(AccountService.self) private var account
    @State private var start = Date()

    var body: some View {
        SpaceBackdrop {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: AppActivity.paused)) { t in
                let time = t.date.timeIntervalSince(start)
                VStack(spacing: 22) {
                    Art(name: "login-cat")
                        .frame(width: 190, height: 190)
                        .rotationEffect(.degrees(sin(time / 2) * 10))
                        .offset(y: sin(time / 1.4) * 10)
                    Text("Waiting for approval").font(.system(size: 30, weight: .black, design: .monospaced))
                    Text("Hi @\(account.profile?.username ?? account.profile?.name ?? "explorer")! The Orbit owner checks every new account.\nThis screen opens the app by itself as soon as you're approved.")
                        .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
                    if let email = account.email { Label(email, systemImage: "envelope").font(.callout).foregroundStyle(.white.opacity(0.5)) }
                    HStack {
                        Button { Task { await account.refreshStatus() } } label: { Label("Check again", systemImage: "arrow.clockwise") }
                        Button("Log out") { Task { await account.signOut() } }
                    }
                    .controlSize(.large)
                }
                .foregroundStyle(.white)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Profile

struct ProfileSheet: View {
    @Environment(AccountService.self) private var account
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var newEmail = ""
    @State private var emailPassword = ""
    @State private var current = ""
    @State private var newPassword = ""
    @State private var repeatPassword = ""
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Avatar(name: account.profile?.name ?? "?", color: .accentColor, size: 56, planet: store.avatarPlanet)
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(account.profile?.username ?? account.profile?.name ?? "")").font(.title2.weight(.bold))
                    Text(account.email ?? "").foregroundStyle(.secondary)
                }
                Spacer()
                if account.isAdmin { Label("Owner", systemImage: "crown.fill").foregroundStyle(.orange).font(.callout.weight(.semibold)) }
            }

            GroupBox("Username") {
                HStack {
                    TextField("Username", text: $username).textFieldStyle(.roundedBorder)
                    Button("Save") { Task { if await account.changeUsername(username) { note = "Username updated." } } }
                        .disabled(username == account.profile?.username || username.count < 3)
                }
                .padding(6)
            }

            GroupBox("Email") {
                HStack {
                    TextField("New email", text: $newEmail).textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $emailPassword).textFieldStyle(.roundedBorder).frame(width: 150)
                    Button("Change") { Task { if await account.changeEmail(newEmail, password: emailPassword) { note = "Email updated."; newEmail = ""; emailPassword = "" } } }
                        .disabled(newEmail.isEmpty || emailPassword.isEmpty)
                }
                .padding(6)
            }

            GroupBox("Password") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Current password", text: $current).textFieldStyle(.roundedBorder)
                    HStack {
                        SecureField("New password", text: $newPassword).textFieldStyle(.roundedBorder)
                        SecureField("Repeat new password", text: $repeatPassword).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Spacer()
                        Button("Change Password") {
                            guard newPassword == repeatPassword else { account.message = "The new passwords don't match."; return }
                            Task { if await account.changePassword(current: current, new: newPassword) { note = "Password changed."; current = ""; newPassword = ""; repeatPassword = "" } }
                        }
                        .disabled(current.isEmpty || newPassword.isEmpty)
                    }
                }
                .padding(6)
            }

            GroupBox("Cloud backup") {
                HStack {
                    Image(systemName: account.syncError == nil ? "checkmark.icloud" : "icloud.slash")
                        .foregroundStyle(account.syncError == nil ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.syncError ?? (account.lastSync.map { "Synced \($0.formatted(.relative(presentation: .named)))" } ?? "Your data is backed up to your account"))
                        Text("Everything is also kept on this Mac, so Orbit works offline.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(account.syncing ? "Syncing…" : "Sync Now") { Task { await account.upload() } }.disabled(account.syncing)
                }
                .padding(6)
            }

            if let m = account.message { Label(m, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            if let note { Label(note, systemImage: "checkmark.circle").foregroundStyle(.green) }

            HStack {
                Button("Log Out", role: .destructive) { Task { await account.signOut(); dismiss() } }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { username = account.profile?.username ?? ""; account.message = nil }
    }
}

/// The signed-in user at the bottom of the sidebar
struct AccountChip: View {
    @Environment(AccountService.self) private var account
    @Environment(AppStore.self) private var store
    @State private var showing = false

    var body: some View {
        if account.state == .approved {
            Button { showing = true } label: {
                HStack(spacing: 8) {
                    Avatar(name: account.profile?.name ?? "?", color: .accentColor, size: 26, planet: store.avatarPlanet)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("@\(account.profile?.username ?? account.profile?.name ?? "")").font(.callout.weight(.semibold)).lineLimit(1)
                        Text(account.syncError == nil ? "Synced" : "Offline").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StreakChip()
                    Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.bottom, 10)
            .sheet(isPresented: $showing) { ProfileSheet() }
        }
    }
}

/// Streak days next to the account; hover to see the freezes left this month
private struct StreakChip: View {
    @Environment(AppStore.self) private var store
    @State private var hover = false

    var body: some View {
        let info = store.streakInfo
        HStack(spacing: 2) {
            StreakIcon(size: 16)
            Text("\(info.days)").font(.callout.weight(.bold).monospacedDigit())
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(Color.yellow.opacity(hover ? 0.25 : 0.12)))
        .onHover { hover = $0 }
        .popover(isPresented: $hover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    StreakIcon(size: 22)
                    Text("\(info.days)-day streak").font(.headline)
                }
                HStack(spacing: 4) {
                    ForEach(0..<StreakInfo.freezesPerMonth, id: \.self) { i in
                        Image(systemName: "snowflake").foregroundStyle(i < info.freezesLeft ? Color.cyan : Color.secondary.opacity(0.35))
                    }
                    Text("\(info.freezesLeft) of \(StreakInfo.freezesPerMonth) freezes left this month").font(.callout)
                }
                Text("Miss a day and a freeze is used automatically, so your streak survives. You get 3 new ones every month.")
                    .font(.caption).foregroundStyle(.secondary).frame(width: 240, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                if !info.frozen.isEmpty {
                    Text("Frozen: " + info.frozen.prefix(5).map { Fmt.date($0, "MMM d", .persian) }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.cyan)
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Admin panel (owner only)

struct AdminPanel: View {
    @Environment(AccountService.self) private var account
    @Environment(FightClubService.self) private var fightClub
    @State private var bossHours = 5
    @State private var tempPassword: (name: String, value: String)?
    @State private var confirmRemove: AccountService.AdminUser?
    @State private var giftTo: AccountService.AdminUser?
    @State private var giftAmount = 100
    @State private var giftDone: String?

    var body: some View {
        let pending = account.users.filter { !$0.approved }
        let members = account.users.filter(\.approved)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Admin", systemImage: "crown.fill").font(.title3.weight(.bold)).foregroundStyle(.orange)
                    Spacer()
                    Button { Task { await account.loadUsers() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                }
                Text("Only you see this panel. \(members.count) member\(members.count == 1 ? "" : "s") · \(pending.count) waiting")
                    .font(.caption).foregroundStyle(.secondary)

                // World Boss health for the next weeks
                VStack(alignment: .leading, spacing: 6) {
                    Text("WORLD BOSS").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    HStack {
                        Stepper("\(bossHours) hours per member", value: $bossHours, in: 1...100)
                        Spacer()
                        Button("Save") { Task { await fightClub.setHoursPerMember(bossHours) } }
                            .disabled(bossHours == fightClub.hoursPerMember)
                    }
                    Text("Next monster: \(members.count) members × \(bossHours)h = \(members.count * bossHours)h of health. Applies from next week; this week's stays as it is.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let e = fightClub.error { Text(e).font(.caption).foregroundStyle(.red) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))
                .onAppear { bossHours = fightClub.hoursPerMember }

                Text("WAITING FOR APPROVAL").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                if pending.isEmpty { Text("No one is waiting.").font(.callout).foregroundStyle(.secondary) }
                ForEach(pending) { u in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("@\(u.username ?? u.name)").font(.headline)
                        Text(u.email ?? "—").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        if let at = u.requested_at { Text("Signed up \(at.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.tertiary) }
                        HStack {
                            Button { Task { await account.approve(u.id) } } label: { Label("Approve", systemImage: "checkmark") }.buttonStyle(.borderedProminent).tint(.green)
                            Button(role: .destructive) { confirmRemove = u } label: { Label("Reject", systemImage: "xmark") }
                        }
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
                }

                Text("MEMBERS").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).padding(.top, 6)
                ForEach(members) { u in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("@\(u.username ?? u.name)").font(.callout.weight(.semibold))
                                if u.is_admin { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.orange) }
                            }
                            Text(u.email ?? "no email yet").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Text("Backup: \(u.last_backup.map { $0.formatted(.relative(presentation: .named)) } ?? "none") · Studied: \(u.last_studied ?? "—")")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Menu {
                            Button("Give Rockets…") { giftAmount = 100; giftTo = u }
                            if !u.is_admin {
                                Button("Reset Password…") {
                                    Task { if let p = await account.resetPassword(u.id) { tempPassword = (u.username ?? u.name, p) } }
                                }
                                Divider()
                                Button("Remove Account…", role: .destructive) { confirmRemove = u }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
                if let g = giftDone { Text(g).font(.caption).foregroundStyle(.green) }
                if let m = account.message { Text(m).font(.caption).foregroundStyle(.red) }
            }
            .padding(16)
        }
        .task { await account.loadUsers() }
        .sheet(item: $giftTo) { u in
            VStack(alignment: .leading, spacing: 14) {
                Label("Give rockets to @\(u.username ?? u.name)", systemImage: "paperplane.fill").font(.headline)
                HStack {
                    TextField("Amount", value: $giftAmount, format: .number).textFieldStyle(.roundedBorder).frame(width: 120)
                    Text("🚀")
                    ForEach([50, 100, 500, 1000], id: \.self) { n in Button("\(n)") { giftAmount = n }.controlSize(.small) }
                }
                Text("Use a negative number to take rockets back. They're added the next time their app checks (within a minute).")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { giftTo = nil }.keyboardShortcut(.cancelAction)
                    Button("Give") {
                        let amount = giftAmount, name = u.username ?? u.name
                        giftTo = nil
                        Task { if await account.giftRockets(u.id, amount: amount) { giftDone = "Sent \(amount) 🚀 to @\(name)." } }
                    }
                    .buttonStyle(.borderedProminent).disabled(giftAmount == 0).keyboardShortcut(.defaultAction)
                }
            }
            .padding(20).frame(width: 380)
        }
        .alert("New password for @\(tempPassword?.name ?? "")", isPresented: Binding(get: { tempPassword != nil }, set: { if !$0 { tempPassword = nil } })) {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tempPassword?.value ?? "", forType: .string)
            }
            Button("Done", role: .cancel) {}
        } message: {
            Text("\(tempPassword?.value ?? "")\n\nSend it to them privately. They can change it in their profile after logging in.")
        }
        .confirmationDialog("Remove @\(confirmRemove?.username ?? confirmRemove?.name ?? "")?", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button("Remove", role: .destructive) { if let u = confirmRemove { Task { await account.reject(u.id) } } }
        } message: {
            Text("Their profile, friendships and backup are removed from the server. They'll need to sign up again.")
        }
    }
}
