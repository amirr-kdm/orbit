import SwiftUI
import Carbon.HIToolbox

/// A small floating window for the daily words: press Control + Option + L anywhere (or use the menu bar) to open it,
/// press Space to see the answer, then ← (don't know) or → (know it). Esc closes it.
@MainActor
final class LeitnerQuickPanel {
    static let shared = LeitnerQuickPanel()
    private var panel: NSPanel?

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    func toggle() { if let p = panel, p.isVisible { close() } else { show() } }

    func show() {
        if panel == nil {
            let p = Panel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                          styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.backgroundColor = .clear
            p.isOpaque = false
            p.contentView = NSHostingView(rootView: LeitnerQuickView(onClose: { [weak self] in self?.close() }))
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { p.standardWindowButton(b)?.isHidden = true }
            p.center()
            panel = p
        }
        guard let p = panel else { return }
        // a fresh round every time it opens
        NotificationCenter.default.post(name: .leitnerQuickOpened, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
    }

    func close() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.14; p.animator().alphaValue = 0 }) { p.orderOut(nil) }
    }
}

extension Notification.Name { static let leitnerQuickOpened = Notification.Name("leitnerQuickOpened") }

/// Control + Option + L, from any app
enum LeitnerHotKey {
    nonisolated(unsafe) private static var ref: EventHotKeyRef?

    @MainActor static func register() {
        guard ref == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { LeitnerQuickPanel.shared.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x4F524254), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}

struct LeitnerQuickView: View {
    var onClose: () -> Void
    @State private var leitner = LeitnerStore.shared
    @State private var session = LeitnerSession()
    @State private var celebrate = false
    /// "" = the words of every box; otherwise one box
    @AppStorage("leitner.quickBox") private var quickBox = ""

    private var chosen: [String]? { leitner.box(quickBox) != nil ? [quickBox] : nil }

    var body: some View {
        let done = leitner.reviewedToday, goal = leitner.dailyGoal
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
                    Circle().trim(from: 0, to: min(1, Double(done) / Double(max(1, goal))))
                        .stroke(done >= goal ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: done)
                    Text("\(done)").font(.callout.weight(.bold).monospacedDigit()).contentTransition(.numericText())
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today's words").font(.headline)
                    Text("\(done) reviewed · \(leitner.totalDue) left · minimum \(goal)").font(.caption).foregroundStyle(.secondary).contentTransition(.numericText())
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.top, 14)

            if leitner.boxes.count > 1 {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox.fill").foregroundStyle(.secondary)
                    Picker("Box", selection: $quickBox) {
                        Text("All boxes").tag("")
                        ForEach(leitner.boxes) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity)
                }
            }
            ProgressView(value: Double(session.answered), total: Double(max(1, session.initial)))
                .tint(.orange).animation(.easeOut, value: session.answered)

            if session.current != nil {
                LeitnerReviewDeck(session: session, compact: true)
                if let c = session.current { Text("from \(c.box) · \(session.queue.count) to go in this round").font(.caption).foregroundStyle(.tertiary) }
            } else {
                finished
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.bottom, 18)
        .frame(width: 420, height: 520)
        .background(
            ZStack {
                VisualEffect()
                LinearGradient(colors: [Color(hex: "#6366F1").opacity(0.18), Color(hex: "#EC4899").opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .onAppear { session.start(boxes: chosen) }
        .onReceive(NotificationCenter.default.publisher(for: .leitnerQuickOpened)) { _ in session.start(boxes: chosen); celebrate = false }
        .onChange(of: quickBox) { celebrate = false; session.start(boxes: chosen) }
    }

    @ViewBuilder private var finished: some View {
        let more = leitner.boxes.filter { chosen == nil || chosen!.contains($0.name) }.reduce(0) { $0 + leitner.ahead(in: $1.name).count }
        VStack(spacing: 12) {
            if leitner.boxes.isEmpty {
                Image(systemName: "square.stack.3d.up").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("No boxes yet").font(.title3.weight(.semibold))
                Text("Make a Leitner box in the app and add your words.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                Text(session.answered > 0 ? "🎉" : "✅").font(.system(size: 60)).scaleEffect(celebrate ? 1 : 0.4)
                    .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) { celebrate = true } }
                Text(session.answered > 0 ? "Round finished!" : "Nothing due right now").font(.title3.weight(.bold))
                Text("\(leitner.reviewedToday) words today" + (leitner.reviewedToday >= leitner.dailyGoal ? " — minimum reached ✓" : " · \(leitner.dailyGoal - leitner.reviewedToday) to your minimum"))
                    .font(.callout).foregroundStyle(.secondary)
                if more > 0 {
                    Button("Study 10 more") { celebrate = false; session.start(boxes: chosen, more: true) }.buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// The frosted glass behind the quick window
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active; return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
