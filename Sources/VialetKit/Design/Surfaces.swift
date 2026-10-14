import SwiftUI

// Surfaces communes des apps : wordmark, en-tetes, carte de panneau, touches d'aide,
// pied de raccourci et ecran Reglages. Remplacements 1:1 des motifs recopies dans les apps.

// MARK: - Wordmark

/// Nom de l'app en `Theme.display`, encre, suivi d'un point a l'accent (<< Pince. >>).
/// Pas de marge : chaque fenetre pose la sienne.
public struct Wordmark: View {
    let text: String
    let size: CGFloat

    public init(_ text: String, size: CGFloat = 26) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(text).font(Theme.display(size)).foregroundStyle(Theme.ink)
            Text(".").font(Theme.display(size)).foregroundStyle(Theme.accent)
        }
    }

    /// Petit wordmark discret des panneaux (<< pince. >>) : nom en minuscules et point,
    /// 15 heavy, `Theme.inkFaint`.
    public struct Mini: View {
        let text: String

        public init(_ text: String) { self.text = text }

        public var body: some View {
            Text(text.lowercased() + ".")
                .font(Theme.display(15, weight: .heavy))
                .foregroundStyle(Theme.inkFaint)
        }
    }
}

// MARK: - En-tete de section

/// Titre de section en capitales : 11,5 gras, `Theme.inkFaint`, sans marge.
public struct SectionHeader: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(Theme.ui(11.5, weight: .bold))
            .foregroundStyle(Theme.inkFaint)
            .textCase(.uppercase)
    }
}

// MARK: - Carte de panneau

/// Carte du panneau flottant : fond `Theme.card`, coins `Theme.Radius.panel`, ombre
/// `Theme.Shadow.panel`, contour `Theme.line` de 1 pt. Le contenu est rogne aux coins ;
/// l'ombre deborde : prevoir une marge autour (16 pt) dans la fenetre.
public struct PanelCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        let shadow = Theme.Shadow.panel
        content
            .clipShape(shape)
            .background(shape.fill(Theme.card).shadow(color: shadow.color, radius: shadow.radius, y: shadow.y))
            .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
    }
}

// MARK: - Touche d'aide

/// Touche sur fond d'encre a 7 % suivie de son libelle (<< esc fermer >>), en `Theme.inkSoft`.
public struct KeyHint: View {
    let key: String
    let label: String

    public init(_ key: String, _ label: String) {
        self.key = key
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(key).font(Theme.ui(11, weight: .bold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.key).fill(Theme.ink.opacity(0.07)))
            Text(label).font(Theme.ui(11.5))
        }
        .foregroundStyle(Theme.inkSoft)
    }
}

// MARK: - Pied de raccourci

/// Pied de barre laterale : << Raccourci >> suivi de `shortcut.display`, 11 `Theme.inkFaint`, marges 18 / 14
/// comme dans les apps.
public struct ShortcutFooter: View {
    let shortcut: HotKeyShortcut

    public init(_ shortcut: HotKeyShortcut) { self.shortcut = shortcut }

    public var body: some View {
        Text(verbatim: "Raccourci \(shortcut.display)")
            .font(Theme.ui(11)).foregroundStyle(Theme.inkFaint)
            .padding(.horizontal, 18).padding(.bottom, 14)
    }
}

// MARK: - Reglages

/// Ecran Reglages standard : wordmark << Reglages. >>, puis les cartes Raccourci global,
/// Toujours la, Mises a jour et Apparence, puis les cartes propres a l'app (`extra`).
/// `hotKeyHint` decrit ce que fait le raccourci ; l'apparence est rangee sous `app.key("Appearance")`.
/// Icone de barre des menus : `menuBar` (MenuBarPresence : Automatique, Toujours, Jamais), nil pour
/// ne pas proposer la ligne ; l'ancien `menuBarVisible` (interrupteur sur `app.key("MenuBar")`) reste accepte.
public struct SettingsScreen<Extra: View>: View {
    enum MenuBarRow {
        case toggle(Binding<Bool>)
        case presence(MenuBarPresence)
        case none
    }

    let app: AppIdentity
    let hotKey: HotKeyController
    let updater: Updater
    let menuBar: MenuBarRow
    let dock: DockPresence?
    let hotKeyEnabled: Binding<Bool>?
    let hotKeyHint: String
    let alwaysOnHint: String?
    let updateNote: String?
    let width: CGFloat
    let extra: Extra
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginNeedsApproval = LaunchAtLogin.needsApproval
    @State private var appearance: AppearanceChoice

    /// `menuBar` : presence de l'icone de barre des menus (nil : pas de ligne, pour une app qui n'est
    /// qu'une icone de barre des menus). `hotKeyEnabled` : raccourci facultatif, avec son interrupteur
    /// (l'app enregistre ou suspend le raccourci). `alwaysOnHint` remplace la legende de la carte
    /// Toujours la (fermer la fenetre ne quitte pas l'app) ; `updateNote` la phrase sur les echanges reseau
    /// de la carte Mises a jour. `dock` : ligne « Icone dans le Dock » (voir `DockPresence`).
    public init(app: AppIdentity, hotKey: HotKeyController, updater: Updater, menuBar: MenuBarPresence?,
                dock: DockPresence? = nil,
                hotKeyEnabled: Binding<Bool>? = nil, hotKeyHint: String, alwaysOnHint: String? = nil,
                updateNote: String? = nil, width: CGFloat = 460, @ViewBuilder extra: () -> Extra) {
        self.init(app: app, hotKey: hotKey, updater: updater, row: menuBar.map(MenuBarRow.presence) ?? .none,
                  dock: dock, hotKeyEnabled: hotKeyEnabled, hotKeyHint: hotKeyHint, alwaysOnHint: alwaysOnHint,
                  updateNote: updateNote, width: width, extra: extra())
    }

    /// Ancienne forme : interrupteur << Icone dans la barre des menus >> sur `menuBarVisible`.
    public init(app: AppIdentity, hotKey: HotKeyController, updater: Updater, menuBarVisible: Binding<Bool>,
                hotKeyHint: String, width: CGFloat = 460, @ViewBuilder extra: () -> Extra) {
        self.init(app: app, hotKey: hotKey, updater: updater, row: .toggle(menuBarVisible), dock: nil, hotKeyEnabled: nil,
                  hotKeyHint: hotKeyHint, alwaysOnHint: nil, updateNote: nil, width: width, extra: extra())
    }

    private init(app: AppIdentity, hotKey: HotKeyController, updater: Updater, row: MenuBarRow, dock: DockPresence?,
                 hotKeyEnabled: Binding<Bool>?, hotKeyHint: String, alwaysOnHint: String?, updateNote: String?,
                 width: CGFloat, extra: Extra) {
        self.app = app
        self.hotKey = hotKey
        self.updater = updater
        self.menuBar = row
        self.dock = dock
        self.hotKeyEnabled = hotKeyEnabled
        self.hotKeyHint = hotKeyHint
        self.alwaysOnHint = alwaysOnHint
        self.updateNote = updateNote
        self.width = width
        self.extra = extra
        self._appearance = State(initialValue: AppearanceChoice.current(defaultsKey: app.key("Appearance")))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Wordmark("R\u{00E9}glages")

            SettingsCard(icon: "keyboard", color: Theme.sea, title: "Raccourci global") {
                if let hotKeyEnabled {
                    Toggle("Activer le raccourci", isOn: hotKeyEnabled)
                }
                HStack(spacing: 12) {
                    ShortcutRecorder(controller: hotKey)
                    Button("R\u{00E9}tablir") { hotKey.shortcut = hotKey.defaultShortcut }
                        .buttonStyle(.plain)
                        .font(Theme.ui(12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .opacity(hotKey.shortcut == hotKey.defaultShortcut ? 0 : 1)
                }
                .disabled(hotKeyEnabled?.wrappedValue == false)
                .opacity(hotKeyEnabled?.wrappedValue == false ? 0.45 : 1)
                Text(verbatim: hotKey.isTaken
                     ? "Cette combinaison est d\u{00E9}j\u{00E0} utilis\u{00E9}e par une autre app. Choisissez-en une autre."
                     : hotKeyHint)
                    .font(Theme.ui(12))
                    .foregroundStyle(hotKey.isTaken ? Theme.danger : Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(icon: "power", color: Theme.pine, title: "Toujours l\u{00E0}") {
                Toggle("Ouvrir \(app.displayName) \u{00E0} la connexion", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        launchAtLogin = LaunchAtLogin.set(on)
                        loginNeedsApproval = LaunchAtLogin.needsApproval
                    }
                if loginNeedsApproval {
                    HStack(spacing: 6) {
                        Text("\u{00C0} autoriser dans R\u{00E9}glages Syst\u{00E8}me \u{203A} Ouverture.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.coral)
                        Button("Ouvrir") { LaunchAtLogin.openSystemSettings() }
                            .buttonStyle(.link).font(Theme.ui(12, weight: .semibold))
                    }
                }
                menuBarRow
                dockRow
                Text(verbatim: alwaysOnHint
                     ?? "Fermer la fen\u{00EA}tre ne quitte pas \(app.displayName) : le raccourci reste actif. \u{2318}Q pour quitter.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(icon: "arrow.down.circle", color: Theme.coral, title: "Mises \u{00E0} jour") {
                UpdateCard(updater: updater, note: updateNote)
            }

            SettingsCard(icon: "circle.lefthalf.filled", color: Theme.lavender, title: "Apparence") {
                Picker("", selection: $appearance) {
                    ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: appearance) { _, choice in choice.apply(defaultsKey: app.key("Appearance")) }
            }

            extra
        }
        .toggleStyle(.switch)
        .font(Theme.ui(13))
        .padding(26)
        .frame(width: width)
        .background(Theme.paper)
        .fontDesign(.rounded)
    }
}

extension SettingsScreen {
    @ViewBuilder
    private var menuBarRow: some View {
        switch menuBar {
        case .toggle(let visible):
            Toggle("Ic\u{00F4}ne dans la barre des menus", isOn: visible)
        case .presence(let presence):
            HStack {
                Text("Ic\u{00F4}ne dans la barre des menus")
                Spacer(minLength: 12)
                Picker("Ic\u{00F4}ne dans la barre des menus",
                       selection: Binding(get: { presence.mode }, set: { presence.mode = $0 })) {
                    ForEach(MenuBarMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            let status = presence.mode.status(hubInstalled: presence.hubInstalled, hubName: "Vialet")
            if !status.isEmpty {
                Text(verbatim: status)
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var dockRow: some View {
        if let dock {
            HStack {
                Text("Ic\u{00F4}ne dans le Dock")
                Spacer(minLength: 12)
                Picker("Ic\u{00F4}ne dans le Dock", selection: Binding(get: { dock.mode }, set: { dock.mode = $0 })) {
                    ForEach(DockMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

extension SettingsScreen where Extra == EmptyView {
    /// Les quatre cartes standard, sans carte propre a l'app.
    public init(app: AppIdentity, hotKey: HotKeyController, updater: Updater, menuBar: MenuBarPresence?,
                dock: DockPresence? = nil,
                hotKeyEnabled: Binding<Bool>? = nil, hotKeyHint: String, alwaysOnHint: String? = nil,
                updateNote: String? = nil, width: CGFloat = 460) {
        self.init(app: app, hotKey: hotKey, updater: updater, menuBar: menuBar, dock: dock, hotKeyEnabled: hotKeyEnabled,
                  hotKeyHint: hotKeyHint, alwaysOnHint: alwaysOnHint, updateNote: updateNote,
                  width: width) { EmptyView() }
    }

    /// Ancienne forme, sans carte propre a l'app.
    public init(app: AppIdentity, hotKey: HotKeyController, updater: Updater, menuBarVisible: Binding<Bool>,
                hotKeyHint: String, width: CGFloat = 460) {
        self.init(app: app, hotKey: hotKey, updater: updater, menuBarVisible: menuBarVisible,
                  hotKeyHint: hotKeyHint, width: width) { EmptyView() }
    }
}
