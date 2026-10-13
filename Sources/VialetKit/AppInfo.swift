import Foundation

/// Identite de l'app en cours, lue dans son Info.plist. La version n'existe
/// qu'a un endroit : le fichier VERSION, ecrit dans le bundle par bundle.sh.
public enum AppInfo {
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Numero de build (CFBundleVersion), sinon la version.
    public static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? version
    }

    /// Mention de copyright (NSHumanReadableCopyright), sinon vide.
    public static var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    public static var semanticVersion: SemanticVersion {
        SemanticVersion(string: version) ?? SemanticVersion(0)
    }

    /// Nom affiche (CFBundleDisplayName), sinon CFBundleName, sinon le nom du processus.
    public static var displayName: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? ProcessInfo.processInfo.processName
    }
}
