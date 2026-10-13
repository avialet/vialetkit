# VialetKit

Socle partagé des apps Mac de [vialet.app](https://app.vialet.app) : ce que chaque
app embarque à l'identique, écrit une seule fois.

- **Mises à jour intégrées** (`Updater`, `UpdateCard`, `UpdateBanner`) : lecture de la
  dernière Release GitHub, téléchargement du DMG, vérification SHA-256, contrôle du
  bundle, remplacement et relance. Une seule copie de ce code, pour toutes les apps.
- **Thème** (`Theme`, voir plus bas) : papier chaud, encre profonde, palette d'accent par app,
  jetons, titres en Bricolage Grotesque, plus quelques composants
  (`Chip`, `CheckCircle`, `ProgressRing`, `AmbientBackground`, `SettingsCard`, `FlowLayout`).
- **Coquille d'app** : raccourci global sans autorisation d'accessibilité (`HotKeyController`,
  `ShortcutRecorder`), panneau flottant (`FloatingPanelController`), fenêtre principale
  (`WindowSummoner`), apparence (`AppearanceChoice`), ouverture à la connexion (`LaunchAtLogin`),
  version lue dans le bundle (`AppInfo`), panneau À propos (`AboutPanel`, `AboutCommands`),
  icône de barre des menus (`MenuBarIcon`).
- **Identité** (`AppIdentity`) : nom, dépôt, bundle, palette et glyphe déclarés une fois ;
  site, liens, clés UserDefaults et configuration de mise à jour en découlent.

Aucune dépendance externe. Swift 6, macOS 15 ou plus récent (les apps visent macOS 26).

## Utilisation

```swift
// Package.swift
.package(url: "https://github.com/avialet/vialetkit.git", from: "0.2.0")
```

```swift
import VialetKit

enum Brand {
    static let identity = AppIdentity(
        name: "Allege", displayName: "Allège", repository: "avialet/allege",
        bundleIdentifier: "fr.vialet.allege",
        palette: AccentPalette(accent: 0x2E9D6E, background: 0x2E9D6E, deep: 0x012B1A,
                               pale: 0xE1F8EB, night: 0x032114, nightInk: 0xB6E4CB),
        glyph: "M 50 16 L 50 60 M 32 42 L 50 60 L 68 42 M 24 82 L 76 82")
    static let updater = UpdaterConfiguration(identity)
}
extension Updater { static let shared = Updater(configuration: Brand.updater) }
```

## Thème

Chaque app pose sa palette au lancement, avant le premier rendu (les teintes sont celles de
l'affiche et du site, calculées par `scripts/teintes.py` du dépôt vialetapps) :

```swift
@main struct AllegeApp: App {
    init() {
        Theme.configure(AccentPalette(accent: 0x2E9D6E, background: 0x2E9D6E, deep: 0x012B1A,
                                      pale: 0xE1F8EB, night: 0x032114, nightInk: 0xB6E4CB))
    }
}
```

- **Palette** : `Theme.accent` (contrôles, halos), `accentSelection` (accent à 14 %),
  `accentBackground`, `accentDeep`, `accentPale`, `accentNight`, `accentNightInk`, et le bouton
  principal des sites : `accentPrimaryButtonBackground` / `accentPrimaryButtonForeground`
  (fond deep et texte blanc en clair, fond background et texte deep en sombre). Sans
  `configure`, la palette est `AccentPalette.sea`. `AccentPalette.contrast(_:_:)` donne le
  contraste WCAG ; pas de `.tint` global, les apps restent natives.
- **Jetons** : `Theme.Radius` (`key` 4, `icon` 7, `chip` 8, `row` 10, `item` 12, `card` 16,
  `editor` 18, `panel` 22), `Theme.Space` (`xs` 4 à `xxl` 26), `Theme.Shadow.panel`.
- **Typographie** : `Theme.display` sert les titres en Bricolage Grotesque (ExtraBold pour
  `.bold` et plus gras, SemiBold sinon), avec repli SF Rounded tant que la police n'est pas
  enregistrée ; le texte courant reste en police système (`Theme.ui`). `Theme.serif` garde
  l'ancien titre (New York) pour la transition de Pico.
- **Police embarquée** : `Sources/VialetKit/Design/Fonts.swift` est généré par
  `scripts/kit-fonts.sh` du dépôt vialetapps (base64, aucune ressource SwiftPM, donc aucun
  `.bundle` à signer). `Theme.configure` l'écrit dans `~/Library/Caches/<bundle>/VialetKit/Fonts` et
  l'enregistre pour le processus. Bricolage Grotesque est sous licence
  [SIL Open Font License 1.1](OFL-Bricolage.txt).

Le générateur `scripts/new-app.sh` du dépôt [vialetapps](https://github.com/avialet/vialetapps)
produit une app déjà branchée sur le kit.

En 0.x, un changement d'API incompatible monte le numéro mineur ; chaque app met à jour son
`Package.swift` quand elle est prête. La 0.2.0 rend `Theme.display` isolé au `MainActor`
(à appeler depuis une vue) et le fait passer du serif à Bricolage Grotesque.

## Glyphe

Le glyphe d'une app (`Brand.glyph`) est un tracé SVG absolu réduit (`M L H V C Q Z`) dans une
boîte 0-100, y vers le bas : le même que celui de la plaque d'icône, de l'affiche et des sites
(`scripts/plaque.swift` du dépôt vialetapps, dont le parseur est une copie à garder identique).

- `GlyphPath.cgPath(_:in:)` : le tracé dans un rectangle AppKit (y vers le haut) ; lève
  `GlyphError.empty`, `.command("A")` ou `.arguments("M")`.
- `GlyphImage.template(_:pointSize:stroke:)` : trait noir arrondi dans 60 % du carré, image
  template (la barre des menus la teinte en clair comme en sombre).
- `GlyphImage.plate(_:glyph:pixels:inverse:strokeDeep:)` : plaque plate (carré arrondi à
  22,45 %, fond accent ou blanc, trait blanc, accent ou deep), pour une vue ou un aperçu.
- `MenuBarIcon(glyph:)` : label prêt pour `MenuBarExtra`.

## Identité et À propos

`AppIdentity` regroupe ce qui nomme l'app : `siteURL` (`https://allege.vialet.app`),
`repositoryURL`, `author`, `license`, `key("HotKey")` (`AllegeHotKey`) et
`UpdaterConfiguration(identity)`. `AppInfo.build` (CFBundleVersion) et `AppInfo.copyright`
complètent `AppInfo.version`.

`AboutPanel.show(identity)` ouvre le panneau À propos standard : nom affiché, version, puis
« Un projet d'Aurélien Vialet », « Licence MIT » et deux liens (le site, le code source sur
GitHub). L'icône reste celle du bundle. Adoption dans une app :

```swift
@main struct AllegeApp: App {
    init() { Theme.configure(Brand.identity.palette) }

    var body: some Scene {
        WindowGroup { ContentView() }
            .commands { AboutCommands(identity: Brand.identity) }
        MenuBarExtra {
            MenuContent()
        } label: {
            MenuBarIcon(glyph: Brand.identity.glyph)
        }
    }
}
```

## Tests

Les Command Line Tools n'embarquent ni XCTest ni Swift Testing : les tests vivent dans
`Sources/vialetkit-check/` et tournent avec `swift run vialetkit-check [filtre]`.

## Licence

[MIT](LICENSE) © 2026 Aurélien Vialet
