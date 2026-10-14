import Foundation

/// Place d'une app dans la barre des menus, face aux autres apps vialet.app.
public enum HubRole: Equatable, Hashable, Sendable {
    /// L'app Vialet est installee : elle rassemble les apps, chacune masque son icone.
    case vialet
    /// Seule app vialet.app du Mac : elle garde son icone.
    case alone
    /// Cette app tient le menu rassembleur (icone vialet.app) pour toutes les apps.
    case host
    /// Une autre app (`host`, son bundle id) tient le menu rassembleur.
    case member(host: String)

    /// En mode `auto`, l'icone propre de l'app est-elle affichee ?
    public var showsOwnIcon: Bool { self == .alone }
    /// Cette app affiche l'icone et le menu vialet.app ?
    public var hostsHub: Bool { self == .host }

    /// Forme rangee (`<App>HubRole`) : `vialet`, `alone`, `host`, `member:<bundle id>`.
    public var stored: String {
        switch self {
        case .vialet: "vialet"
        case .alone: "alone"
        case .host: "host"
        case .member(let host): "member:" + host
        }
    }

    public init?(stored: String?) {
        switch stored {
        case "vialet": self = .vialet
        case "alone": self = .alone
        case "host": self = .host
        case let s? where s.hasPrefix("member:") && s.count > 7: self = .member(host: String(s.dropFirst(7)))
        default: return nil
        }
    }
}

/// Election d'un hote unique pour le menu rassembleur, sans l'app Vialet : chaque app (kit 0.2.6 ou
/// plus) calcule le meme resultat a partir des memes faits (apps installees, apps en cours, fiches),
/// sans echange de messages. Regle :
/// - Vialet installee : elle est l'hote (`vialet`) ;
/// - sinon une seule app vialet.app installee : elle garde son icone (`alone`) ;
/// - sinon, parmi les apps en cours capables d'heberger (fiche avec `hub`) et l'app elle-meme, le plus
///   petit bundle id tient le menu (`host`), les autres masquent leur icone (`member`).
public enum HubElection {
    /// Version du protocole, ecrite dans la fiche (`HubManifest.hub`) par une app qui peut heberger.
    public static let protocolVersion = 1
    /// Notification distribuee par une app quand elle prend ou quitte le role d'hote, ou quitte :
    /// les autres refont l'election.
    public static let hostNotification = Notification.Name("fr.vialet.hub.host")

    /// `installed` : bundle ids des apps vialet.app installees (fiches validees et dossiers Applications) ;
    /// `runningHosts` : celles qui tournent et peuvent heberger. Vialet n'y compte jamais ; `me` toujours.
    public static func role(me: String, hubAppInstalled: Bool, installed: Set<String>, runningHosts: Set<String>) -> HubRole {
        if hubAppInstalled { return .vialet }
        guard counted(installed: installed.union([me])).count >= 2 else { return .alone }
        let host = counted(installed: runningHosts.union([me])).min() ?? me
        return host == me ? .host : .member(host: host)
    }

    /// Apps qui comptent : toutes sauf Vialet.
    public static func counted(installed: Set<String>) -> Set<String> {
        installed.subtracting([MenuBarPresence.hubBundleIdentifier])
    }

    /// Apps capables d'heberger : fiche portant `hub` (kit 0.2.6 ou plus) et app retenue comme installee.
    public static func capable(manifests: [HubManifest], installed: Set<String>) -> Set<String> {
        Set(manifests.filter { ($0.hub ?? 0) >= 1 && installed.contains($0.bundleIdentifier) }.map(\.bundleIdentifier))
            .subtracting([MenuBarPresence.hubBundleIdentifier])
    }
}
