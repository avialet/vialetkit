import AppKit
import SwiftUI

/// Panneau A propos standard de macOS, rempli depuis l'identite de l'app :
/// nom affiche, version, credit, licence, liens vers le site et le code source.
/// L'icone reste celle du bundle (icns).
@MainActor
public enum AboutPanel {
    public static func show(_ identity: AppIdentity) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options(identity))
    }

    /// Options passees au panneau. `.version` (build) est vide quand il vaut la version :
    /// AppKit affiche alors << Version X.Y.Z >> sans parenthese.
    public static func options(_ identity: AppIdentity) -> [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: identity.displayName,
            .applicationVersion: AppInfo.version,
            .version: AppInfo.build == AppInfo.version ? "" : AppInfo.build,
            .credits: credits(identity),
        ]
    }

    /// Credit centre en police systeme 11 : auteur, licence, puis deux liens (site, depot).
    public static func credits(_ identity: AppIdentity) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let text = NSMutableAttributedString()
        func append(_ s: String, link: URL? = nil) {
            var attrs = base
            if let link { attrs[.link] = link }
            text.append(NSAttributedString(string: s, attributes: attrs))
        }
        append("Un projet d'\(identity.author)\nLicence \(identity.license)\n")
        append("\(identity.name.lowercased()).vialet.app", link: identity.siteURL)
        append("\n")
        append("Code source sur GitHub", link: identity.repositoryURL)
        return text
    }
}

/// Remplace l'entree << A propos >> du menu de l'app par le panneau de l'identite :
/// `.commands { AboutCommands(identity: Brand.identity) }`.
public struct AboutCommands: Commands {
    let identity: AppIdentity

    public init(identity: AppIdentity) {
        self.identity = identity
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("\u{00C0} propos de \(identity.displayName)") { AboutPanel.show(identity) }
        }
    }
}
