import AppKit
import SwiftUI

/// Sends formatting commands from the SwiftUI toolbar to the text view
@MainActor
final class RichTextController {
    weak var textView: NoteTextView?

    static let bodyFont = NSFont.systemFont(ofSize: 14)
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.labelColor]
    }

    func toggleTrait(_ trait: NSFontTraitMask) {
        guard let tv = textView else { return }
        let fm = NSFontManager.shared
        let range = tv.selectedRange()
        if range.length == 0 {
            let f = (tv.typingAttributes[.font] as? NSFont) ?? Self.bodyFont
            let has = fm.traits(of: f).contains(trait)
            tv.typingAttributes[.font] = has ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait)
            return
        }
        guard let storage = tv.textStorage else { return }
        var allHave = true
        storage.enumerateAttribute(.font, in: range) { v, _, _ in
            if !fm.traits(of: (v as? NSFont) ?? Self.bodyFont).contains(trait) { allHave = false }
        }
        edit(range) { storage in
            storage.enumerateAttribute(.font, in: range) { v, r, _ in
                let f = (v as? NSFont) ?? Self.bodyFont
                storage.addAttribute(.font, value: allHave ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait), range: r)
            }
        }
    }

    func toggle(_ key: NSAttributedString.Key) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if range.length == 0 {
            let on = (tv.typingAttributes[key] as? Int ?? 0) != 0
            tv.typingAttributes[key] = on ? 0 : NSUnderlineStyle.single.rawValue
            return
        }
        let on = (tv.textStorage?.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0) != 0
        edit(range) { s in
            if on { s.removeAttribute(key, range: range) } else { s.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: range) }
        }
    }

    func setColor(_ color: NSColor?, background: Bool = false) {
        guard let tv = textView else { return }
        let key: NSAttributedString.Key = background ? .backgroundColor : .foregroundColor
        let value = color ?? (background ? nil : NSColor.labelColor)
        let range = tv.selectedRange()
        if range.length == 0 {
            tv.typingAttributes[key] = value
            return
        }
        edit(range) { s in
            if let value { s.addAttribute(key, value: value, range: range) } else { s.removeAttribute(key, range: range) }
        }
    }

    /// Heading level 1 / 2, or 0 for body text, applied to the selected paragraphs
    func setHeading(_ level: Int) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = (storage.string as NSString).paragraphRange(for: tv.selectedRange())
        let font: NSFont = switch level {
        case 1: .systemFont(ofSize: 24, weight: .bold)
        case 2: .systemFont(ofSize: 18, weight: .semibold)
        default: Self.bodyFont
        }
        if range.length == 0 { tv.typingAttributes[.font] = font; return }
        edit(range) { $0.addAttribute(.font, value: font, range: range) }
        tv.typingAttributes[.font] = font
    }

    enum ListKind { case bullet, number, check }

    /// Adds or removes a list marker at the start of every selected line
    func toggleList(_ kind: ListKind) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ns = storage.string as NSString
        let range = ns.paragraphRange(for: tv.selectedRange())
        var lines: [NSRange] = []
        ns.enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, r, _, _ in lines.append(r) }
        if lines.isEmpty { lines = [NSRange(location: range.location, length: 0)] }
        let allHave = lines.allSatisfy { NoteTextView.marker(in: ns.substring(with: $0)).map { NoteTextView.kind(of: $0) == kind } ?? false }

        tv.undoManager?.beginUndoGrouping()
        for (n, line) in lines.enumerated().reversed() {
            let text = ns.substring(with: line)
            let existing = NoteTextView.marker(in: text)
            let replaceLen = existing?.count ?? 0
            let marker: String = switch kind {
            case .bullet: "• "
            case .number: "\(n + 1). "
            case .check: "☐ "
            }
            let newMarker = allHave ? "" : marker
            let r = NSRange(location: line.location, length: (replaceLen as Int))
            if tv.shouldChangeText(in: r, replacementString: newMarker) {
                storage.replaceCharacters(in: r, with: NSAttributedString(string: newMarker, attributes: tv.typingAttributes))
                tv.didChangeText()
            }
        }
        tv.undoManager?.endUndoGrouping()
    }

    func insertTable(rows: Int = 3, columns: Int = 3) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        var at = tv.selectedRange()
        at.length = 0
        let out = NSMutableAttributedString()
        // A table has to start on its own line
        if at.location > 0, (storage.string as NSString).character(at: at.location - 1) != 10 {
            out.append(NSAttributedString(string: "\n", attributes: Self.baseAttributes))
        }
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.setContentWidth(100, type: .percentageValueType)
        table.hidesEmptyCells = false
        for r in 0..<rows {
            for c in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setBorderColor(NSColor.separatorColor)
                block.setWidth(6, type: .absoluteValueType, for: .padding)
                if r == 0 { block.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12) }
                let ps = NSMutableParagraphStyle()
                ps.textBlocks = [block]
                var attrs = Self.baseAttributes
                attrs[.paragraphStyle] = ps
                if r == 0 { attrs[.font] = NSFont.systemFont(ofSize: 14, weight: .semibold) }
                out.append(NSAttributedString(string: (r == 0 ? "Column \(c + 1)" : "") + "\n", attributes: attrs))
            }
        }
        out.append(NSAttributedString(string: "\n", attributes: Self.baseAttributes))
        if tv.shouldChangeText(in: at, replacementString: out.string) {
            storage.replaceCharacters(in: at, with: out)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: at.location + (out.string.hasPrefix("\n") ? 1 : 0), length: 0))
        }
        tv.window?.makeFirstResponder(tv)
    }

    /// The system table panel: add / remove rows and columns, merge cells, borders…
    func tableOptions() {
        textView?.orderFrontTablePanel(nil)
    }

    /// Alignment for the selected paragraphs (keeps table cells and other paragraph settings)
    func setAlignment(_ alignment: NSTextAlignment) {
        changeParagraphs { $0.alignment = alignment }
    }

    /// Right-to-left (Persian, Arabic…) or left-to-right writing for the selected paragraphs
    func setDirection(rightToLeft: Bool) {
        changeParagraphs {
            $0.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
            $0.alignment = rightToLeft ? .right : .left
        }
    }

    private func changeParagraphs(_ change: (NSMutableParagraphStyle) -> Void) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = (storage.string as NSString).paragraphRange(for: tv.selectedRange())
        // Typing on an empty line uses the typing attributes
        let typing = ((tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle) ?? .default).mutableCopy() as! NSMutableParagraphStyle
        change(typing)
        tv.typingAttributes[.paragraphStyle] = typing
        guard range.length > 0 else { return }
        edit(range) { s in
            s.enumerateAttribute(.paragraphStyle, in: range) { v, r, _ in
                let ps = ((v as? NSParagraphStyle) ?? .default).mutableCopy() as! NSMutableParagraphStyle
                change(ps)
                s.addAttribute(.paragraphStyle, value: ps, range: r)
            }
        }
    }

    func insertDivider() {
        guard let tv = textView else { return }
        tv.insertText("\n──────────────────────────\n", replacementRange: tv.selectedRange())
    }

    private func edit(_ range: NSRange, _ change: (NSTextStorage) -> Void) {
        guard let tv = textView, let storage = tv.textStorage, tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        change(storage)
        storage.endEditing()
        tv.didChangeText()
        tv.window?.makeFirstResponder(tv)
    }
}

/// Text view with checklists (click ☐ to tick it) and lists that continue when you press Return
final class NoteTextView: NSTextView {
    static let markers = ["☐ ", "☑ ", "• "]

    static func marker(in line: String) -> String? {
        if let m = markers.first(where: { line.hasPrefix($0) }) { return m }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") { return String(digits) + ". " }
        return nil
    }

    static func kind(of marker: String) -> RichTextController.ListKind {
        switch marker {
        case "☐ ", "☑ ": .check
        case "• ": .bullet
        default: .number
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let lm = layoutManager, let tc = textContainer, let storage = textStorage, storage.length > 0 {
            let local = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
            let glyph = lm.glyphIndex(for: local, in: tc)
            let idx = lm.characterIndexForGlyph(at: glyph)
            if idx < storage.length {
                let ch = (storage.string as NSString).substring(with: NSRange(location: idx, length: 1))
                let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
                if (ch == "☐" || ch == "☑") && rect.insetBy(dx: -3, dy: -3).contains(local) {
                    let r = NSRange(location: idx, length: 1)
                    let new = ch == "☐" ? "☑" : "☐"
                    if shouldChangeText(in: r, replacementString: new) {
                        let attrs = storage.attributes(at: idx, effectiveRange: nil)
                        storage.replaceCharacters(in: r, with: NSAttributedString(string: new, attributes: attrs))
                        // Strike through a ticked item
                        let line = (storage.string as NSString).paragraphRange(for: r)
                        let body = NSRange(location: idx + 2, length: max(0, NSMaxRange(line) - idx - 2))
                        if body.length > 0 {
                            if new == "☑" {
                                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: body)
                                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: body)
                            } else {
                                storage.removeAttribute(.strikethroughStyle, range: body)
                                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: body)
                            }
                        }
                        didChangeText()
                    }
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage else { return super.insertNewline(sender) }
        let ns = storage.string as NSString
        let sel = selectedRange()
        let lineRange = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        let line = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard let marker = Self.marker(in: line) else { return super.insertNewline(sender) }

        if line == marker || line == marker.trimmingCharacters(in: .whitespaces) {
            // Empty list item: end the list
            let r = NSRange(location: lineRange.location, length: (line as NSString).length)
            insertText("", replacementRange: r)
            return
        }
        var next = marker
        if marker == "☑ " { next = "☐ " }
        if let n = Int(marker.dropLast(2)) { next = "\(n + 1). " }
        super.insertNewline(sender)
        typingAttributes[.strikethroughStyle] = nil
        typingAttributes[.foregroundColor] = NSColor.labelColor
        insertText(next, replacementRange: selectedRange())
    }
}

/// An editable rich-text note. Content is loaded from / saved to RTF.
struct RichTextEditor: NSViewRepresentable {
    let noteID: UUID
    let rtf: Data
    let controller: RichTextController
    let onSave: (UUID, Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSave: onSave) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let tv = NoteTextView(frame: .zero)
        tv.isRichText = true
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 14, height: 14)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.typingAttributes = RichTextController.baseAttributes
        tv.delegate = context.coordinator
        scroll.documentView = tv

        controller.textView = tv
        context.coordinator.load(noteID: noteID, rtf: rtf, into: tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NoteTextView else { return }
        controller.textView = tv
        context.coordinator.onSave = onSave
        if context.coordinator.noteID != noteID {
            context.coordinator.flush(tv)
            context.coordinator.load(noteID: noteID, rtf: rtf, into: tv)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let tv = scroll.documentView as? NSTextView { coordinator.flush(tv) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSave: (UUID, Data) -> Void
        var noteID: UUID?
        private var pending: DispatchWorkItem?
        private var dirty = false

        init(onSave: @escaping (UUID, Data) -> Void) { self.onSave = onSave }

        func load(noteID: UUID, rtf: Data, into tv: NSTextView) {
            self.noteID = noteID
            dirty = false
            let content = NSMutableAttributedString(attributedString:
                (rtf.isEmpty ? nil : NSAttributedString(rtf: rtf, documentAttributes: nil)) ?? NSAttributedString())
            let full = NSRange(location: 0, length: content.length)
            // Text without an explicit colour follows light / dark mode
            content.enumerateAttribute(.foregroundColor, in: full) { v, r, _ in
                if v == nil { content.addAttribute(.foregroundColor, value: NSColor.labelColor, range: r) }
            }
            content.enumerateAttribute(.font, in: full) { v, r, _ in
                if v == nil { content.addAttribute(.font, value: RichTextController.bodyFont, range: r) }
            }
            tv.textStorage?.setAttributedString(content)
            tv.typingAttributes = RichTextController.baseAttributes
            tv.undoManager?.removeAllActions()
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            dirty = true
            pending?.cancel()
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv else { return }
                MainActor.assumeIsolated { self.flush(tv) }
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }

        func flush(_ tv: NSTextView) {
            pending?.cancel()
            guard dirty, let noteID, let storage = tv.textStorage else { return }
            dirty = false
            let copy = NSMutableAttributedString(attributedString: storage)
            let full = NSRange(location: 0, length: copy.length)
            copy.enumerateAttribute(.foregroundColor, in: full) { v, r, _ in
                if let c = v as? NSColor, c == NSColor.labelColor { copy.removeAttribute(.foregroundColor, range: r) }
            }
            let data = copy.rtf(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) ?? Data()
            onSave(noteID, data)
        }
    }
}
