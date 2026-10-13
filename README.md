# VialetKit

Socle partagé des apps Mac de [vialet.app](https://app.vialet.app) : ce que chaque
app embarque à l'identique, écrit une seule fois.

- **Mises à jour intégrées** (`Updater`, `UpdateCard`, `UpdateBanner`) : lecture de la
  dernière Release GitHub, téléchargement du DMG, vérification SHA-256, contrôle du
  bundle, remplacement et relance. Une seule copie de ce code, pour toutes les apps.
- **Thème** (`Theme`) : papier chaud, encre profonde, polices, plus quelques composants
  (`Chip`, `CheckCircle`, `ProgressRing`, `AmbientBackground`, `SettingsCard`, `FlowLayout`).
- **Coquille d'app** : raccourci global sans autorisation d'accessibilité (`HotKeyController`,
  `ShortcutRecorder`), panneau flottant (`FloatingPanelController`), fenêtre principale
  (`WindowSummoner`), apparence (`AppearanceChoice`), ouverture à la connexion (`LaunchAtLogin`),
  version lue dans le bundle (`AppInfo`).

Aucune dépendance externe. Swift 6, macOS 15 ou plus récent (les apps visent macOS 26).

## Utilisation

```swift
// Package.swift
.package(url: "https://github.com/avialet/vialetkit.git", from: "0.1.0")
```

```swift
import VialetKit

enum Brand {
    static let updater = UpdaterConfiguration(repository: "avialet/allege", appName: "Allege",
                                              bundleIdentifier: "fr.vialet.allege", displayName: "Allège")
}
extension Updater { static let shared = Updater(configuration: Brand.updater) }
```

Le générateur `scripts/new-app.sh` du dépôt [vialetapps](https://github.com/avialet/vialetapps)
produit une app déjà branchée sur le kit.

En 0.x, un changement d'API incompatible monte le numéro mineur (`0.2.0`) ; chaque app
met à jour son `Package.swift` quand elle est prête.

## Tests

Les Command Line Tools n'embarquent ni XCTest ni Swift Testing : les tests vivent dans
`Sources/vialetkit-check/` et tournent avec `swift run vialetkit-check [filtre]`.

## Licence

[MIT](LICENSE) © 2026 Aurélien Vialet
