import AppKit
import SwiftUI

/// Entree « Rechercher les mises a jour... » du menu de l'app, sous « A propos » :
/// `.commands { AboutCommands(identity: ...); UpdateCommands(updater: .shared) }`.
/// Une mise a jour trouvee s'annonce dans le bandeau de la fenetre principale (UpdateNotice), ramenee
/// au premier plan ; une alerte dit si l'app est deja a jour ou si la recherche a echoue.
public struct UpdateCommands: Commands {
    let updater: Updater

    public init(updater: Updater) {
        self.updater = updater
    }

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Rechercher les mises \u{00E0} jour\u{2026}") { Self.checkFromMenu(updater) }
                .disabled(updater.isBusy)
        }
    }

    @MainActor static func checkFromMenu(_ updater: Updater) {
        updater.check()
        Task { @MainActor in
            // La recherche est courte ; au-dela de 30 s, l'etat d'echec du bandeau prend le relais.
            for _ in 0..<300 where updater.state == .checking {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let name = updater.configuration.displayName
            switch updater.state {
            case .available:
                WindowSummoner.show()
            case .upToDate:
                alert("\(name) est \u{00E0} jour",
                      "La version \(updater.currentVersion.description) est la derni\u{00E8}re publi\u{00E9}e.")
            case .failed(let message):
                alert("Recherche impossible", message)
            default:
                break
            }
        }
    }

    @MainActor private static func alert(_ title: String, _ text: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
