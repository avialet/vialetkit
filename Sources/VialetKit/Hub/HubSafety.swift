import Foundation

/// Regles appliquees a ce que Vialet lit d'ailleurs : les fiches HubManifest (dossier modifiable par
/// tout processus local) et le catalogue ne sont pas dignes de confiance.
public enum HubSafety {
    /// `avialet/<nom>` : proprietaire fixe, nom ASCII `[A-Za-z0-9._-]` (100 au plus), ni `.` ni `..`.
    public static func isValidRepository(_ repository: String) -> Bool {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "avialet" else { return false }
        let name = parts[1]
        guard (1...100).contains(name.count), name != ".", name != ".." else { return false }
        return name.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || ".-_".unicodeScalars.contains($0)
        }
    }

    /// Schemas du systeme ou d'autres usages, jamais ouverts au nom d'une app.
    static let systemSchemes: Set<String> = [
        "file", "http", "https", "ftp", "ftps", "sftp", "mailto", "tel", "sms", "facetime", "facetime-audio",
        "ssh", "telnet", "smb", "afp", "nfs", "vnc", "rdar", "javascript", "data", "about", "blob", "shortcuts",
        "applescript", "help", "news", "nntp", "message", "webcal", "ical", "maps", "music", "spotlight",
        "x-help-action", "vialet",
    ]
    static let systemPrefixes = ["x-apple", "itms", "com.apple", "apple"]

    /// `^[a-z][a-z0-9+.-]{0,30}$`, hors schemas systeme.
    public static func isAcceptableScheme(_ scheme: String) -> Bool {
        guard (1...31).contains(scheme.count), let first = scheme.unicodeScalars.first, ("a"..."z").contains(first),
              scheme.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || "+.-".unicodeScalars.contains($0) })
        else { return false }
        return !systemSchemes.contains(scheme) && !systemPrefixes.contains { scheme.hasPrefix($0) }
    }

    /// Chemin d'app d'une fiche : absolu, sans `..`, extension `.app`, dans `/Applications`,
    /// `~/Applications` ou un de leurs sous-dossiers, liens symboliques resolus.
    public static func isAcceptableAppPath(_ path: String, home: URL) -> Bool {
        isAcceptableAppPath(path, roots: HubManifest.applicationRoots(home: home))
    }

    public static func isAcceptableAppPath(_ path: String, roots: [URL]) -> Bool {
        guard path.hasPrefix("/") else { return false }
        return isAcceptableAppURL(URL(fileURLWithPath: path), roots: roots)
    }

    /// Bundle `.app` sans `..`, dans une des racines une fois les liens symboliques resolus
    /// (`HubManifest.isInApplications`) : un `.app` ou un dossier en lien qui sort des racines est refuse.
    public static func isAcceptableAppURL(_ url: URL, roots: [URL]) -> Bool {
        guard url.isFileURL, url.pathExtension == "app", !url.pathComponents.contains("..") else { return false }
        return HubManifest.isInApplications(url, roots: roots)
    }

    /// Taille maximale d'une reponse reseau (Release GitHub, catalogue) : 2 Mo.
    public static let maxResponseSize = 2 * 1024 * 1024

    /// Reponse acceptee : taille annoncee (`expectedContentLength`, -1 si inconnue) et taille recue bornees.
    public static func isAcceptableResponse(byteCount: Int, expectedLength: Int64) -> Bool {
        byteCount <= maxResponseSize && expectedLength <= Int64(maxResponseSize)
    }
}
