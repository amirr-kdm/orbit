import SwiftUI

/// The colour swatches for schedule / planner cells. "+" creates a custom colour;
/// right-click a swatch to delete it. The list is saved in settings.
struct CellPaletteBar: View {
    @Environment(AppStore.self) private var store
    /// Currently chosen colour (nil = template colour)
    let selection: String?
    let onPick: (String?) -> Void

    @State private var adding = false
    @State private var newColor = Color(hex: "#22C55E")

    private var template: ScheduleTemplate { store.settings.template }

    var body: some View {
        HStack(spacing: 6) {
            swatch(nil)
            ForEach(store.settings.cellPalette, id: \.self) { hex in
                swatch(hex)
                    .contextMenu {
                        Button("Use This Colour") { onPick(hex) }
                        Divider()
                        Button("Delete Colour", role: .destructive) { remove(hex) }
                    }
            }
            Button { adding = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Circle().strokeBorder(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3])))
            }
            .buttonStyle(.plain)
            .help("Create a colour")
            .popover(isPresented: $adding, arrowEdge: .top) { addPopover }
        }
    }

    private var addPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New colour").font(.headline)
            HStack {
                ColorPicker("Pick a colour", selection: $newColor, supportsOpacity: false)
                Spacer()
                Circle().fill(newColor.gradient).frame(width: 28, height: 28)
            }
            Text(newColor.hexString).font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack {
                Button("Restore Default Colours") {
                    store.settings.cellPalette = AppSettings.defaultPalette
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Spacer()
                Button("Add") {
                    let hex = newColor.hexString
                    if !store.settings.cellPalette.contains(hex) { store.settings.cellPalette.append(hex) }
                    onPick(hex)
                    adding = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            Text("Right-click any swatch to delete it. Cells keep their colour.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 260)
    }

    private func remove(_ hex: String) {
        store.settings.cellPalette.removeAll { $0 == hex }
    }

    private func swatch(_ hex: String?) -> some View {
        let isOn = selection == hex
        let accent = template.style.accent
        return Button {
            onPick(hex)
        } label: {
            ZStack {
                Circle()
                    .fill(hex.map { AnyShapeStyle(Color(hex: $0).gradient) }
                          ?? AnyShapeStyle(Color(hex: template.defaultCellColor).opacity(0.25)))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                if hex == nil {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Circle()
                    .strokeBorder(isOn ? accent : Color.clear, lineWidth: 2)
                    .frame(width: 26, height: 26)
            }
            .scaleEffect(isOn ? 1.08 : 1)
            .animation(.spring(duration: 0.25), value: isOn)
        }
        .buttonStyle(.plain)
        .help(hex == nil ? "Template colour" : "\(hex!) · right-click to delete")
    }
}
