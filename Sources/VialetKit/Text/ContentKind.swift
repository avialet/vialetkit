import Foundation

/// Ce qu'on a copie, devine par heuristiques : pilote l'apercu et les actions.
public enum ContentKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case text, url, email, color, json, code, path, number, image, files

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .text: "Texte"
        case .url: "Lien"
        case .email: "Adresse"
        case .color: "Couleur"
        case .json: "JSON"
        case .code: "Code"
        case .path: "Chemin"
        case .number: "Nombre"
        case .image: "Image"
        case .files: "Fichiers"
        }
    }

    /// Symbole SF.
    public var icon: String {
        switch self {
        case .text: "text.alignleft"
        case .url: "link"
        case .email: "at"
        case .color: "paintpalette"
        case .json: "curlybraces"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .path: "folder"
        case .number: "number"
        case .image: "photo"
        case .files: "doc.on.doc"
        }
    }
}

public enum ContentDetector {
    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    public static func detect(_ raw: String) -> ContentKind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .text }
        let singleLine = !text.contains(where: \.isNewline)

        if singleLine, matches(#"^(https?://|ftp://|www\.)\S+$"#, text) { return .url }
        if singleLine, matches(#"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, text) { return .email }
        if hexColor(text) != nil { return .color }
        if let first = text.first, first == "{" || first == "[" {
            if JSONTools.isValid(text) { return .json }
            return .code
        }
        if singleLine, matches(#"^(/|~/)"#, text) { return .path }
        if singleLine, matches(#"^[-+]?\d{1,3}([ \u{202F}\u{00A0}]\d{3})*([.,]\d+)?$"#, text) || matches(#"^[-+]?\d+([.,]\d+)?$"#, text) {
            return .number
        }
        if looksLikeCode(text, singleLine: singleLine) { return .code }
        return .text
    }

    private static func looksLikeCode(_ text: String, singleLine: Bool) -> Bool {
        let keywords = #"^(func|fn|let|var|const|def|class|struct|enum|import|package|public|private|static|if|for|while|return|select|insert|update|delete|create|alter|drop|#include|#!/|<\?php|<!doctype|<html|<div|<svg|\$ |git |npm |brew |curl |ssh |docker )"#
        if matches(keywords, text) { return true }
        if text.contains("=>") || text.contains("->") || text.contains("::") || text.contains("();") { return true }
        if !singleLine {
            let lines = text.split(whereSeparator: \.isNewline)
            if text.contains("{") && text.contains("}") { return true }
            if lines.filter({ $0.hasSuffix(";") }).count >= 2 { return true }
            if lines.filter({ $0.hasPrefix("    ") || $0.hasPrefix("\t") }).count >= 2, text.contains("(") { return true }
        }
        return false
    }

    /// `#RGB`, `#RRGGBB`, `#RRGGBBAA` (alpha ignoree), `rgb(r, g, b)`, `rgba(r, g, b, a)`.
    public static func hexColor(_ raw: String) -> UInt32? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            let hex = String(text.dropFirst())
            guard hex.allSatisfy(\.isHexDigit), hex.allSatisfy(\.isASCII) else { return nil }
            switch hex.count {
            case 3:
                let digits = hex.map { String($0) + String($0) }.joined()
                return UInt32(digits, radix: 16)
            case 6: return UInt32(hex, radix: 16)
            case 8: return UInt32(String(hex.prefix(6)), radix: 16)
            default: return nil
            }
        }
        guard let regex = try? NSRegularExpression(pattern: #"^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*[\d.]+\s*)?\)$"#, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var parts: [UInt32] = []
        for i in 1...3 {
            guard let r = Range(m.range(at: i), in: text), let v = UInt32(text[r]), v <= 255 else { return nil }
            parts.append(v)
        }
        return parts[0] << 16 | parts[1] << 8 | parts[2]
    }
}

public enum JSONTools {
    public static func isValid(_ text: String) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
    }

    /// Reindente (2 espaces, cles triees). nil si ce n'est pas du JSON.
    public static func pretty(_ text: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func minified(_ text: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

public enum SearchNormalizer {
    /// Minuscules sans accents : « Élève » et « eleve » se trouvent.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}

/// Regroupement d'une liste par anciennete.
public enum TimeBucket: Equatable, Sendable {
    case now, minutes(Int), today, yesterday, week, older

    public var label: String {
        switch self {
        case .now: "À l'instant"
        case .minutes(let m): "Il y a \(m) min"
        case .today: "Aujourd'hui"
        case .yesterday: "Hier"
        case .week: "Cette semaine"
        case .older: "Plus ancien"
        }
    }

    /// Etiquette de section : les minutes sont regroupees sous « À l'instant » au-dela de 1 min.
    public var sectionLabel: String {
        switch self {
        case .now, .minutes: "À l'instant"
        default: label
        }
    }

    public static func bucket(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> TimeBucket {
        let age = now.timeIntervalSince(date)
        if age < 60 { return .now }
        if age < 3600 { return .minutes(Int(age / 60)) }
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        if age < 7 * 86400 { return .week }
        return .older
    }
}
