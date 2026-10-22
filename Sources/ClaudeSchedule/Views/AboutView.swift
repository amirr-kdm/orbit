import SwiftUI

/// Who made Orbit and where to reach them
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    /// Fill in to show a LinkedIn link
    static let linkedIn: String? = "https://www.linkedin.com/in/amirreza-khadempir/"

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // app
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                        .shadow(color: .purple.opacity(0.4), radius: 14, y: 5)
                    Text("Orbit").font(.system(size: 28, weight: .heavy, design: .rounded))
                    Text("Plan your week, study with focus, and watch your galaxy grow.")
                        .foregroundStyle(.secondary)
                    Text("Version \(version)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
                .padding(.top, 8)

                // designer
                card {
                    Text("DESIGNED & BUILT BY").font(.caption.weight(.heavy)).tracking(1.5).foregroundStyle(.secondary)
                    Text("Amirreza Khadempir").font(.title2.weight(.bold))
                    Text("Ideas, feedback or a bug? Message me — I read everything.")
                        .font(.callout).foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        link("paperplane.fill", "Telegram", "@amirr_kdm", "https://t.me/amirr_kdm", Color(hex: "#2AABEE"), image: "telegram")
                        link("chevron.left.forwardslash.chevron.right", "GitHub", "amirr-kdm", "https://github.com/amirr-kdm", .primary, image: "github")
                        if let li = Self.linkedIn {
                            link("person.crop.square.filled.and.at.rectangle", "LinkedIn", li.replacingOccurrences(of: "https://", with: ""), li, Color(hex: "#0A66C2"), image: "linkedin")
                        }
                    }
                    .padding(.top, 4)
                }

                // channel
                card {
                    Text("NEWS & UPDATES").font(.caption.weight(.heavy)).tracking(1.5).foregroundStyle(.secondary)
                    Text("Join the Orbit channel on Telegram for new features, updates and tips. (The app also tells you when a new version is out.)")
                        .font(.callout).foregroundStyle(.secondary)
                    link("megaphone.fill", "Orbit channel", "@orbitstudyplanner", "https://t.me/orbitstudyplanner", .orange, image: "channel")
                        .padding(.top, 4)
                }

                // challenges group
                card {
                    Text("ORBIT CHALLENGES 🚩").font(.caption.weight(.heavy)).tracking(1.5).foregroundStyle(.secondary)
                    Text("The Orbiters' Telegram group: make friends with other Orbiters and plan challenges together.")
                        .font(.callout).foregroundStyle(.secondary)
                    link("flag.checkered", "Orbit Challenges", "Join the group on Telegram", "https://t.me/+mgr1bVSj1xwxMmFk", .red, image: "flag")
                        .padding(.top, 4)
                }

                // project
                card {
                    Text("OPEN SOURCE").font(.caption.weight(.heavy)).tracking(1.5).foregroundStyle(.secondary)
                    Text("Orbit is free and open source (MIT). Downloads for Mac and Windows, the code and release notes are on GitHub.")
                        .font(.callout).foregroundStyle(.secondary)
                    link("arrow.down.circle.fill", "Orbit on GitHub", "github.com/amirr-kdm/orbit", "https://github.com/amirr-kdm/orbit", .purple)
                        .padding(.top, 4)
                }

                HStack {
                    Text("Made with ☕️ and a lot of study hours.").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
        }
        .frame(width: 460, height: 720)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    private func link(_ icon: String, _ title: String, _ handle: String, _ url: String, _ tint: Color, image: String? = nil) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Group {
                    if let image, let img = PlanetPainter.bundleImage(image) {
                        Image(nsImage: img).resizable().scaledToFill().frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else {
                        Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint == .primary ? Color.gray : tint))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(handle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
