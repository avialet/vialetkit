# VialetKit

Socle partagé des apps Mac de [vialet.app](https://app.vialet.app) : ce que chaque
app embarque à l'identique, écrit une seule fois.

- **Mises à jour intégrées** (`Updater`, `UpdateNotice`, `UpdateCard`, `UpdateBanner`) : lecture
  de la dernière Release GitHub, annonce avec le journal des changements, téléchargement du DMG,
  vérification SHA-256, contrôle du bundle, remplacement et relance. Une seule copie de ce code,
  pour toutes les apps.
- **Thème** (`Theme`, voir plus bas) : papier chaud, encre profonde, palette d'accent par app,
  jetons, titres en Bricolage Grotesque, plus quelques composants
  (`Chip`, `CheckCircle`, `ProgressRing`, `AmbientBackground`, `SettingsCard`, `FlowLayout`).
- **Coquille d'app** : raccourci global sans autorisation d'accessibilité (`HotKeyController`,
  `ShortcutRecorder`), panneau flottant (`FloatingPanelController`), fenêtre principale
  (`WindowSummoner`), apparence (`AppearanceChoice`), ouverture à la connexion (`LaunchAtLogin`),
  version lue dans le bundle (`AppInfo`), panneau À propos (`AboutPanel`, `AboutCommands`),
  icône de barre des menus (`MenuBarIcon`, `MenuBarPresence`), actions rapides par URL et fiche
  pour l'app Vialet (`AppActions`, `HubManifest`).
- **Surfaces communes** (`Wordmark`, `SectionHeader`, `PanelCard`, `KeyHint`, `ShortcutFooter`,
  `SettingsScreen`) et **mode capture** (`SnapshotRunner`), voir plus bas.
- **Identité** (`AppIdentity`) : nom, dépôt, bundle, palette et glyphe déclarés une fois ;
  site, liens, clés UserDefaults et configuration de mise à jour en découlent.

Aucune dépendance externe. Swift 6, macOS 15 ou plus récent (les apps visent macOS 26).

## Utilisation

```swift
// Package.swift
.package(url: "https://github.com/avialet/vialetkit.git", .upToNextMinor(from: "0.2.5"))
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
La 0.2.2 ajoute, sans rien casser, le bandeau d'annonce des mises à jour et leur journal
(voir « Annoncer les mises à jour »).

## Annoncer les mises à jour

Dans le menu de l'app, sous « À propos », l'entrée « Rechercher les mises à jour… » (0.2.3) : une mise à jour
trouvée ramène la fenêtre principale et son bandeau ; sinon une alerte dit que l'app est à jour.

```swift
.commands {
    AboutCommands(identity: Brand.identity)
    UpdateCommands(updater: .shared)
}
```

Une ligne dans l'app, en haut de la fenêtre principale (ou d'un panneau), dans une pile sans
espacement :

```swift
VStack(spacing: 0) {
    UpdateNotice(updater: .shared)
    // ... contenu de la fenêtre
}
```

Le bandeau n'occupe aucune place tant qu'il n'a rien à dire. Sinon, sur une ligne aux teintes de
l'app (`accentPale` en clair, `accentNight` en sombre), avec la plaque de son glyphe :

- **Version disponible** : « Allège 0.3.0 est disponible », « Nouveautés » (déplie le journal),
  « Plus tard » et « Installer et relancer ». « Plus tard » écarte cette version seulement
  (clé `<App>DismissedUpdate`) : la suivante sera annoncée, et la carte des Réglages la propose
  toujours.
- **Installation** : avancement du téléchargement, vérification, relance ; en cas d'échec, le
  message et « Réessayer ».
- **Après une mise à jour** : au premier lancement d'une version plus récente que la dernière vue
  (clé `<App>LastSeenVersion`), « Allège a été mis à jour en 0.3.0 », ses nouveautés et « OK ».
  Les notes viennent de la dernière Release ou, au besoin, de `releases/tags/v<version>`, lues en
  silence (hors ligne, le bandeau s'en passe).

Le journal est le corps de la Release, c'est-à-dire `docs/notes/vX.Y.Z.md` : un titre
`## App X.Y.Z` éventuel (retiré, il redit le bandeau), un chapeau facultatif puis des puces `- `,
où le gras, le `code` et les liens sont rendus (`ReleaseNotes`). Les marges du bandeau visible se
règlent par `padding:` (12 pt en haut et sur les côtés par défaut). L'apparition est discrète et
se réduit à un fondu quand « Réduire les animations » est actif.

La vérification automatique a lieu à chaque lancement (`checkAutomatically()`, que l'app appelle
déjà quelques secondes après l'ouverture), puis toutes les 6 h tant que l'app tourne, jamais à
moins de 30 min de la précédente, et seulement si l'utilisateur l'a laissée active. Elle est
silencieuse : un échec réseau ne s'affiche pas. `UpdateBanner`, l'ancien bandeau de barre
latérale, reste disponible ; `UpdateNotice` le remplace.

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
    var body: some View {
        SettingsScreen(app: Brand.identity, hotKey: .shared, updater: .shared,
                       menuBar: MenuBarPresence.shared,
                       hotKeyHint: "Depuis n'importe quelle app : affiche ou masque Allège.",
                       width: 480) {
            SettingsCard(icon: "doc.on.clipboard", color: Theme.accent, title: "Historique") { … }
        }
    }
}
```

`menuBar:` donne la ligne « Icône dans la barre des menus : Automatique / Toujours / Jamais » et sa
légende (voir plus bas) ; `nil` la retire (app qui n'est qu'une icône de barre des menus).
`hotKeyEnabled:` (facultatif) ajoute l'interrupteur « Activer le raccourci » à la carte Raccourci
global ; `alwaysOnHint:` remplace la légende de la carte Toujours là. L'ancienne forme
`menuBarVisible: $booleen` (simple interrupteur) reste acceptée.

Sans carte propre à l'app, la fermeture `extra` s'omet.

## Vialet : barre des menus et actions rapides

L'app **Vialet** (`fr.vialet.vialet`) rassemble toutes les apps dans une seule icône de barre des
menus. Le kit fournit aux apps ce qu'il faut pour s'y ranger, sans retoucher Vialet à chaque
nouvelle app.

**Icône de barre des menus.** `MenuBarPresence` range le choix de l'utilisateur sous
`<App>MenuBarMode` : `auto` (défaut) masque l'icône quand Vialet est installée (LaunchServices,
hors corbeille), `shown` et `hidden` la forcent. L'ancien booléen `<App>MenuBar` est migré une fois
(false donne `hidden`, true ou absent `auto`). La présence est réévaluée à l'activation de l'app
et à la notification distribuée `fr.vialet.hub.changed` (envoyée par Vialet à son lancement et à
sa fermeture). Si l'utilisateur retire l'icône de la barre (⌘-glisser), le mode passe à `hidden`.

```swift
extension MenuBarPresence { static let shared = MenuBarPresence(app: Brand.identity) }

MenuBarExtra(isInserted: MenuBarPresence.shared.binding) { MenuBarContent() } label: { … }
```

**Actions rapides.** Une app répond aux URL `<nom>://<action>` (`pico://new`, `chuchote://dicter`).
`AppURLCommand.parse(_:scheme:)` les lit : `<nom>://` et `<nom>://open` montrent l'app,
`<nom>://update` vérifie les mises à jour (lien « Mise à jour disponible » de Vialet), le reste est
une action déclarée (identifiant en minuscules ASCII, chiffres et tirets, 40 caractères au plus ;
`open` et `update` sont réservés). `AppActions` tient le registre, aiguille les URL (une action
inconnue montre l'app) et publie la fiche de l'app pour Vialet :

```swift
extension AppActions {
    static let shared = AppActions(Brand.identity, open: { WindowSummoner.show() },
                                   checkForUpdates: { WindowSummoner.show(); Updater.shared.check() })
}

// applicationDidFinishLaunching (apres le mode capture)
AppActions.shared.register(AppAction("new", title: "Nouvelle tâche", symbol: "plus", shortcut: "⌘N")) {
    AppState.shared.newTask()
}
AppActions.shared.publish()

func application(_ application: NSApplication, open urls: [URL]) { AppActions.shared.handle(urls) }
```

Le schéma est celui de `CFBundleURLSchemes` (par défaut le nom en minuscules). `publish()` n'écrit
rien pour une app hors d'un dossier Applications (`build/`, image disque) ; `force: true` passe outre.

**Fiche pour Vialet (format 1).** `publish()` écrit
`~/Library/Application Support/Vialet/apps/<bundle id>.json` (`HubManifest`), puis envoie la
notification distribuée `fr.vialet.apps.changed` :

```json
{
  "actions" : [ { "id" : "new", "shortcut" : "⌘N", "symbol" : "plus", "title" : "Nouvelle tâche" } ],
  "appPath" : "/Applications/Pico.app",
  "bundleIdentifier" : "fr.vialet.pico",
  "displayName" : "Pico",
  "format" : 1,
  "glyph" : "M 28 52 L 44 68 L 74 34",
  "name" : "Pico",
  "palette" : { "accent" : "#2F6FEB", "background" : "#2F6FEB", "deep" : "#00001F",
                "night" : "#0F1A2F", "nightInk" : "#C4D8FD", "pale" : "#EBF2FF" },
  "repository" : "avialet/pico",
  "scheme" : "pico",
  "site" : "https://pico.vialet.app",
  "strokeDeep" : false,
  "version" : "0.2.0"
}
```

Tous les champs sont obligatoires sauf `shortcut` (raccourci de l'app, pour information). Les
teintes sont en `#RRGGBB`. Un lecteur ignore les champs inconnus et lit un format plus récent pour
les champs qu'il connaît : un ajout garde le format, un changement de sens le monte.
`HubManifest.decode` retire les actions à l'identifiant invalide ou réservé ;
`HubManifest.loadAll(from:)` lit un dossier entier.

## Raccourci et panneau flottant

- `HotKeyController.start(action:onRelease:)` : `onRelease` (facultatif) est appelé au
  relâchement du raccourci, pour un push-to-talk. `start { }` seul garde le comportement
  d'avant et efface un `onRelease` précédent.
- `FloatingPanelController(size:takesFocus:placement:content:)` : avec `takesFocus: false`, le
  panneau ne devient jamais clé, s'affiche par-dessus l'app active sans l'activer ni lui prendre
  la frappe et ne se ferme pas quand on clique ailleurs ; ses boutons restent cliquables. Jamais
  clé, il ne reçoit pas Échap : l'app le ferme elle-même par `hide()`.
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
du menu de l'app), `about` (panneau À propos), `floatingPanel` (le `FloatingPanel` de l'app s'il
existe déjà) et `update` (le bandeau de mise à jour replié, déplié et après une mise à jour, avec
une version fictive, sans réseau). Un scénario de l'app portant le même nom remplace le standard. La graine des
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
