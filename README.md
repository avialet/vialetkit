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
- **Surfaces communes** (`Wordmark`, `SectionHeader`, `PanelCard`, `KeyHint`, `ShortcutFooter`,
  `SettingsScreen`) et **mode capture** (`SnapshotRunner`), voir plus bas.
- **Identité** (`AppIdentity`) : nom, dépôt, bundle, palette et glyphe déclarés une fois ;
  site, liens, clés UserDefaults et configuration de mise à jour en découlent.

Aucune dépendance externe. Swift 6, macOS 15 ou plus récent (les apps visent macOS 26).

## Utilisation

```swift
// Package.swift
.package(url: "https://github.com/avialet/vialetkit.git", .upToNextMinor(from: "0.2.1"))
// En 0.x, un changement cassant monte le mineur : epingler le mineur, pas `from:` (= < 1.0.0).
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
La 0.2.1 ajoute, sans rien casser, le relâchement du raccourci et le panneau qui ne prend pas
le focus (voir « Raccourci et panneau flottant »).

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

## Surfaces

Les motifs que chaque app recopiait, à l'identique :

- `Wordmark("Pince")` : nom en `Theme.display(26)`, encre, suivi d'un point à l'accent
  (`size:` pour une autre taille) ; `Wordmark.Mini("Pince")` : « pince. » en 15 heavy, `inkFaint`,
  pour l'en-tête d'un panneau. Pas de marge : chaque fenêtre pose la sienne.
- `SectionHeader("Aujourd'hui")` : titre de section en capitales, 11,5 gras, `inkFaint`.
- `PanelCard { … }` : carte du panneau flottant (fond `card`, coins `Radius.panel`, ombre
  `Shadow.panel`, contour `line`) ; le contenu est rogné aux coins, l'ombre déborde (laisser 16 pt).
- `KeyHint("esc", "fermer")` : touche sur fond d'encre à 7 % et son libellé.
- `ShortcutFooter(hotKey.shortcut)` : « Raccourci ⌃⇧Espace » en pied de barre latérale.
- `SettingsScreen` : l'écran Réglages complet, wordmark « Réglages. » puis les cartes Raccourci
  global (avec « Rétablir » vers `HotKeyController.defaultShortcut`), Toujours là, Mises à jour,
  Apparence, puis les cartes propres à l'app :

```swift
struct SettingsView: View {
    @AppStorage(Brand.identity.key("MenuBar")) private var menuBarVisible = true

    var body: some View {
        SettingsScreen(app: Brand.identity, hotKey: .shared, updater: .shared,
                       menuBarVisible: $menuBarVisible,
                       hotKeyHint: "Depuis n'importe quelle app : affiche ou masque Allège.",
                       width: 480) {
            SettingsCard(icon: "doc.on.clipboard", color: Theme.accent, title: "Historique") { … }
        }
    }
}
```

Sans carte propre à l'app, la fermeture `extra` s'omet.

## Raccourci et panneau flottant

- `HotKeyController.start(action:onRelease:)` : `onRelease` (facultatif) est appelé au
  relâchement du raccourci, pour un push-to-talk. `start { }` seul garde le comportement
  d'avant et efface un `onRelease` précédent.
- `FloatingPanelController(size:takesFocus:placement:content:)` : avec `takesFocus: false`, le
  panneau ne devient jamais clé, s'affiche par-dessus l'app active sans l'activer ni lui prendre
  la frappe et ne se ferme pas quand on clique ailleurs ; ses boutons restent cliquables.
  `placement: .bottom` le pose au-dessus du bas de l'écran (bas à 10 % de la hauteur visible),
  `.upperThird` (défaut) garde la position de palette.

```swift
let listening = FloatingPanelController(size: CGSize(width: 320, height: 72),
                                        takesFocus: false, placement: .bottom) { ListeningView() }
hotKey.start(action: { recorder.begin(); listening.show() },
             onRelease: { recorder.end(); listening.hide() })
```

## Capture

En DEBUG, l'app rend ses fenêtres en PNG elle-même, sans autorisation d'enregistrement d'écran :

```
Allege -AllegeSnapshot /tmp/captures [-AllegeSnapshotAppearance dark] [-AllegeSnapshotOnly settings,about] [-AllegeSnapshotSize 1000x720]
```

écrit `/tmp/captures/<scénario>.png` (`<scénario>-sombre.png` en sombre), imprime
`capture : <chemin>` par fichier puis quitte. La taille s'applique aux fenêtres
redimensionnables. Scénarios standard : `mainWindow` (après 2 s), `settings` (entrée « Réglages… »
du menu de l'app), `about` (panneau À propos) et `floatingPanel` (le `FloatingPanel` de l'app s'il
existe déjà). Un scénario de l'app portant le même nom remplace le standard. La graine des
données reste dans l'app, appelée avant :

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    HotKeyController.shared.start { WindowSummoner.toggle() }
    #if DEBUG
    if CommandLine.arguments.contains("-AllegeSnapshotSeed") { seed() }
    let captured = SnapshotRunner.runIfRequested(
        prefix: Brand.identity.name,
        scenarios: SnapshotRunner.standardScenarios(mainWindow: { WindowSummoner.mainWindow },
                                                    identity: Brand.identity)
            + [SnapshotScenario("detail") {
                AppState.shared.processAll()
                try await Task.sleep(for: .seconds(1))
                return WindowSummoner.mainWindow
            }])
    if captured { return }
    #endif
    // ... vérification des mises à jour, etc.
}
```

## Tests

Les Command Line Tools n'embarquent ni XCTest ni Swift Testing : les tests vivent dans
`Sources/vialetkit-check/` et tournent avec `swift run vialetkit-check [filtre]`.

## Licence

[MIT](LICENSE) © 2026 Aurélien Vialet
