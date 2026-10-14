import Foundation

/// Mises a jour des apps vues par Vialet : la derniere Release GitHub de chaque app, au lancement
/// puis toutes les 6 h, avec un plancher de 30 min (comme le kit). Vialet n'installe rien : il
/// signale, et l'app s'en charge (`<nom>://update`).
public enum HubUpdates {
    public static let interval: TimeInterval = 6 * 3600
    public static let floor: TimeInterval = 30 * 60

    public static func shouldCheck(now: Date, lastCheck: Date?) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed < 0 || elapsed >= floor
    }

    /// nil si le depot n'est pas `avialet/<nom>` valide (voir `HubSafety`).
    public static func releaseURL(repository: String) -> URL? {
        guard HubSafety.isValidRepository(repository) else { return nil }
        return URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
    }

    /// Ce que vaut une reponse de GitHub pour une app.
    public enum Outcome: Equatable, Sendable {
        /// 200 (Release lue) ou 404 (aucune Release) : l'app est interrogee.
        case result
        /// 304 (ETag inchange) : interrogee, resultat precedent garde.
        case unchanged
        /// 403 ou 429 (quota) : arreter la verification, les apps restantes ne sont pas interrogees.
        case stop
        /// Autre : app non interrogee cette fois.
        case skip
    }

    public static func outcome(status: Int) -> Outcome {
        switch status {
        case 200, 404: .result
        case 304: .unchanged
        case 403, 429: .stop
        default: .skip
        }
    }

    /// Resultat d'une verification interrompue ou complete : les apps interrogees (`checked`) prennent
    /// leur nouveau resultat (`found`, absent = a jour), les autres gardent le precedent.
    public static func merge(previous: [String: SemanticVersion], found: [String: SemanticVersion],
                             checked: Set<String>) -> [String: SemanticVersion] {
        var result = previous.filter { !checked.contains($0.key) }
        for (id, version) in found where checked.contains(id) { result[id] = version }
        return result
    }

    /// Version a annoncer : la Release est complete pour cette app (DMG `<appName>-X.Y.Z.dmg` et son
    /// empreinte, ce que l'app pourra installer) et plus recente que la version installee.
    public static func available(installed: String, releaseJSON: Data, appName: String) -> SemanticVersion? {
        guard let current = SemanticVersion(string: installed),
              let release = ReleaseInfo.parse(json: releaseJSON, appName: appName),
              release.version > current else { return nil }
        return release.version
    }
}
