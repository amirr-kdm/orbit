import SwiftUI

/// One notification in the bell
struct AppNotice: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case gift, challenge, group, boss, update, info

        var icon: String {
            switch self {
            case .gift: "gift.fill"
            case .challenge: "flag.checkered"
            case .group: "person.3.fill"
            case .boss: "burst.fill"
            case .update: "arrow.down.circle.fill"
            case .info: "bell.fill"
            }
        }
        var tint: Color {
            switch self {
            case .gift: .orange
            case .challenge: .pink
            case .group: .purple
            case .boss: .red
            case .update: .blue
            case .info: .gray
            }
        }
    }

    var id: String
    var title: String
    var body: String
    var date: Date
    var kind: Kind
    var read = false
    /// The page to open when it's clicked (a `SidebarItem` raw value), and an item inside it (e.g. a challenge id)
    var route: String?
    var target: String?
}

/// Everything the app wants to tell you: shown in the bell (top right) and as a small card that slides in.
/// Each notification also goes to macOS as a normal banner.
@MainActor @Observable
final class Inbox {
    static let shared = Inbox()

    private(set) var items: [AppNotice] = []
    /// The card sliding in at the top right right now
    var toast: AppNotice?
    var unread: Int { items.filter { !$0.read }.count }

    @ObservationIgnored private let key = "inbox.v1"
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([AppNotice].self, from: data) { items = saved }
    }

    /// Add a notification once (the same id is never added twice)
    func post(id: String, title: String, body: String, kind: AppNotice.Kind = .info, route: SidebarItem? = nil, target: String? = nil,
              system: Bool = true) {
        guard !items.contains(where: { $0.id == id }) else { return }
        let n = AppNotice(id: id, title: title, body: body, date: Date(), kind: kind, route: route?.rawValue, target: target)
        items.insert(n, at: 0)
        if items.count > 60 { items.removeLast(items.count - 60) }
        save()
        withAnimation(.spring(duration: 0.4)) { toast = n }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { if self?.toast?.id == id { self?.toast = nil } }
        }
        if system { Notifier.post(id: id, title: title, body: body) }
    }

    func markRead(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].read else { return }
        items[i].read = true
        save()
    }

    func markAllRead() {
        for i in items.indices { items[i].read = true }
        save()
    }

    func clear() {
        items = []
        toast = nil
        save()
    }

    func dismissToast() { withAnimation(.easeOut(duration: 0.25)) { toast = nil } }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - The bell

/// Bell in the top right: the number of unread notifications on its corner; opens a small list beside it
struct InboxBell: View {
    @Environment(Router.self) private var router
    @State private var open = false
    private var inbox: Inbox { .shared }

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: inbox.unread > 0 ? "bell.badge.fill" : "bell")
                .symbolRenderingMode(inbox.unread > 0 ? .multicolor : .monochrome)
                .overlay(alignment: .topTrailing) {
                    if inbox.unread > 0 {
                        Text(inbox.unread > 99 ? "99+" : "\(inbox.unread)")
                            .font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 9, y: -7)
                    }
                }
        }
        .help(inbox.unread > 0 ? "\(inbox.unread) unread notification\(inbox.unread == 1 ? "" : "s")" : "Notifications")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            InboxList { open = false }
                .environment(router)
        }
    }
}

/// The list inside the bell: unread ones are marked read as the mouse moves over them
struct InboxList: View {
    @Environment(Router.self) private var router
    var close: () -> Void
    private var inbox: Inbox { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notifications").font(.headline)
                if inbox.unread > 0 {
                    Text("\(inbox.unread) new").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Color.red))
                }
                Spacer()
                if inbox.unread > 0 {
                    Button("Mark all read") { inbox.markAllRead() }.buttonStyle(.link).font(.caption)
                }
                if !inbox.items.isEmpty {
                    Button { inbox.clear() } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("Clear all")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if inbox.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash").font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text("You're all caught up").font(.callout.weight(.semibold))
                    Text("New challenges, gifts and news show up here.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(inbox.items) { n in
                            NoticeRow(notice: n) { open(n) }
                            if n.id != inbox.items.last?.id { Divider().padding(.leading, 56) }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
        .frame(width: 340)
    }

    private func open(_ n: AppNotice) {
        inbox.markRead(n.id)
        if let r = n.route, let page = SidebarItem(rawValue: r) {
            if let t = n.target, let id = UUID(uuidString: t) { router.openChallenge = id }
            router.selection = page
        }
        close()
    }
}

struct NoticeRow: View {
    let notice: AppNotice
    var onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notice.kind.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(notice.kind.tint.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(notice.title).font(.callout.weight(notice.read ? .regular : .bold)).lineLimit(2)
                        Spacer(minLength: 4)
                        Text(notice.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(notice.body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !notice.read {
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(.top, 6)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(notice.read ? Color.clear : Color.accentColor.opacity(hovering ? 0.05 : 0.09))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            guard h, !notice.read else { return }
            // resting the mouse on a new one for a moment reads it
            let id = notice.id
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                if hovering { Inbox.shared.markRead(id) }
            }
        }
    }
}

// MARK: - The card that slides in

struct NoticeToast: View {
    let notice: AppNotice
    @Environment(Router.self) private var router
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.kind.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(notice.kind.tint.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title).font(.callout.weight(.bold)).lineLimit(2)
                Text(notice.body).font(.caption).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { Inbox.shared.dismissToast() } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                .buttonStyle(.borderless).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 330, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(notice.kind.tint.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .scaleEffect(hover ? 1.02 : 1)
        .animation(.spring(duration: 0.25), value: hover)
        .onHover { hover = $0 }
        .onTapGesture {
            Inbox.shared.markRead(notice.id)
            if let r = notice.route, let page = SidebarItem(rawValue: r) {
                if let t = notice.target, let id = UUID(uuidString: t) { router.openChallenge = id }
                router.selection = page
            }
            Inbox.shared.dismissToast()
        }
    }
}
