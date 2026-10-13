import Foundation

/// Journal d'une version, tire du corps markdown de sa Release GitHub (le fichier
/// `docs/notes/vX.Y.Z.md` des apps) : un chapeau facultatif et une liste de puces.
/// Les titres (`## Pico 0.2.0`, redondant avec le bandeau) sont retires ; le texte qui
/// suit les puces (`**Full Changelog**` des notes generees) est ignore.
public struct ReleaseNotes: Equatable, Sendable {
    /// Paragraphes avant la premiere puce, joints par une espace ; vide s'il n'y en a pas.
    public let summary: String
    /// Puces `- `, `* ` ou `+ `, lignes de suite jointes, sous-puces a plat.
    public let bullets: [String]

    public var isEmpty: Bool { summary.isEmpty && bullets.isEmpty }

    public init(markdown: String) {
        var summary: [String] = []
        var bullets: [String] = []
        var inBullet = false
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { inBullet = false; continue }
            // Titres et filets (`---`) : retires.
            if Self.isHeading(line) || (line.count >= 3 && line.allSatisfy({ "-*_ ".contains($0) })) {
                inBullet = false; continue
            }
            if let marker = line.first, "-*+".contains(marker), line.dropFirst().first == " " {
                let text = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { bullets.append(text); inBullet = true }
                continue
            }
            if inBullet, let last = bullets.indices.last {
                bullets[last] += " " + line
            } else if bullets.isEmpty {
                summary.append(line)
            }
        }
        self.summary = summary.joined(separator: " ")
        self.bullets = bullets
    }

    /// Titre markdown : 1 a 6 `#` suivis d'une espace ou de la fin de ligne (`#42` n'en est pas un).
    static func isHeading(_ line: String) -> Bool {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return false }
        let rest = line.dropFirst(hashes)
        return rest.isEmpty || rest.first == " " || rest.first == "\t"
    }

    /// Une puce (ou le chapeau) en texte riche : gras, italique, `code` et liens http(s) (les autres
    /// liens restent du texte) ; texte brut si le markdown est illisible.
    public static func inline(_ markdown: String) -> AttributedString {
        guard var text = try? AttributedString(markdown: markdown,
                                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else { return AttributedString(markdown) }
        for run in text.runs {
            guard let link = run.link else { continue }
            let scheme = link.scheme?.lowercased()
            if scheme != "http" && scheme != "https" { text[run.range].link = nil }
        }
        return text
    }
}

extension ReleaseInfo {
    /// `notes` decoupees en chapeau et puces.
    public var releaseNotes: ReleaseNotes { ReleaseNotes(markdown: notes) }

    /// Corps markdown d'une reponse `releases/tags/<tag>` (sans exiger ses fichiers) ; nil si illisible.
    static func notesBody(json: Data) -> String? {
        struct Payload: Decodable { let body: String? }
        return (try? JSONDecoder().decode(Payload.self, from: json))?.body
    }
}
