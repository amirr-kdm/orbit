import CoreServices
import Foundation

/// Meanings from the dictionary built into macOS (offline): used when a word is saved without one
enum LeitnerDictionary {
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    nonisolated(unsafe) private static var posCache: [String: String] = [:]

    private static let kinds = ["phrasal verb", "exclamation", "interjection", "conjunction", "preposition", "pronoun", "adjective", "adverb", "determiner", "noun", "verb", "abbreviation"]

    /// noun, verb, adjective, adverb … from the dictionary entry (nil when the dictionary doesn't know the word)
    static func partOfSpeech(_ word: String) -> String? {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return nil }
        if let c = posCache[w.lowercased()] { return c.isEmpty ? nil : c }
        var found = ""
        let ns = w as NSString
        if let raw = DCSCopyTextDefinition(nil, w as CFString, CFRange(location: 0, length: ns.length))?.takeRetainedValue() as String? {
            var s = raw.replacingOccurrences(of: "\n", with: " ")
            let bars = s.components(separatedBy: "|")
            if bars.count >= 3 { s = bars.dropFirst(2).joined(separator: "|") }
            s = s.trimmingCharacters(in: .whitespaces).lowercased()
            // a phrase ("give up") is listed under its main word: a verb phrase stays a verb
            found = kinds.first { s.hasPrefix($0) } ?? ""
            // some entries put it before the pronunciation, glued to the headword ("abuse a·buseverb [with object] | …")
            if found.isEmpty, let head = bars.first?.lowercased() {
                found = kinds.compactMap { k in head.range(of: k).map { (head.distance(from: head.startIndex, to: $0.lowerBound), k) } }
                    .min { ($0.0, -$0.1.count) < ($1.0, -$1.1.count) }?.1 ?? ""
            }
            if found == "phrasal verb" || found == "interjection" { found = found == "interjection" ? "exclamation" : "verb" }
        }
        posCache[w.lowercased()] = found
        return found.isEmpty ? nil : found
    }

    /// A short definition of the word, or nil when the dictionary doesn't know it
    static func define(_ word: String) -> String? {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return nil }
        if let c = cache[w.lowercased()] { return c.isEmpty ? nil : c }
        var found = ""
        let ns = w as NSString
        if let raw = DCSCopyTextDefinition(nil, w as CFString, CFRange(location: 0, length: ns.length))?.takeRetainedValue() as String? {
            // a phrase such as "give up" is listed under its main word: read from where the phrase appears
            if w.contains(" "), let r = raw.range(of: w, options: .caseInsensitive, range: raw.index(raw.startIndex, offsetBy: min(20, raw.count))..<raw.endIndex) {
                found = shorten("x | x | " + String(raw[r.upperBound...]), word: w)
            } else {
                found = shorten(raw, word: w)
            }
        }
        cache[w.lowercased()] = found
        return found.isEmpty ? nil : found
    }

    /// "ubiquitous | juːˈbɪkwɪtəs | adjective present, appearing, or found everywhere: …" → "present, appearing, or found everywhere"
    private static func shorten(_ raw: String, word: String) -> String {
        var s = raw.replacingOccurrences(of: "\n", with: " ")
        // drop the headword and the pronunciation between the bars
        let bars = s.components(separatedBy: "|")
        if bars.count >= 3 { s = bars.dropFirst(2).joined(separator: "|") }
        s = s.trimmingCharacters(in: .whitespaces)
        // a part of speech, with an optional sense number, comes first
        var parts = ["exclamation", "interjection", "conjunction", "preposition", "pronoun", "adjective", "adverb", "determiner", "noun", "verb", "phrasal verb", "abbreviation", "prefix", "suffix"]
        parts.sort { $0.count > $1.count }
        var changed = true
        while changed {
            changed = false
            for p in parts where s.lowercased().hasPrefix(p) { s = String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespaces); changed = true }
            if let r = s.range(of: #"^\d+\s*"#, options: .regularExpression) { s.removeSubrange(r); changed = true }
            // grammar notes such as [no object] or (informal)
            if let r = s.range(of: #"^(\[[^\]]*\]|\([^)]*\))\s*"#, options: .regularExpression) { s.removeSubrange(r); changed = true }
        }
        // stop at the examples, the other senses and the word's history
        for stop in [":", " • ", " ▸ ", " ORIGIN", " PHRASES", " DERIVATIVES"] {
            if let r = s.range(of: stop) { s = String(s[..<r.lowerBound]) }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " .;,"))
        if s.count > 140, let r = s.range(of: ";") { s = String(s[..<r.lowerBound]) }
        return s.count > 160 ? String(s.prefix(157)) + "…" : s
    }
}
