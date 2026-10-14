import SwiftUI

/// Ce que le pied et la tete du menu rassembleur proposent, selon l'app qui le tient.
public struct HubMenuOptions {
    /// Bandeau de mise a jour de l'app qui tient le menu (Vialet, qui ne se liste pas) ; nil sinon.
    public var updater: Updater?
    /// « Reglages... » (Cmd-virgule) ; nil : pas de ligne.
    public var openSettings: (@MainActor () -> Void)?
    /// « Quitter Vialet » (Cmd-Q) ; nil : pas de ligne (une app hote se quitte depuis son interface).
    public var quitTitle: String?

    public init(updater: Updater? = nil, openSettings: (@MainActor () -> Void)? = nil, quitTitle: String? = nil) {
        self.updater = updater
        self.openSettings = openSettings
        self.quitTitle = quitTitle
    }
}

/// Le menu rassembleur : la plaque du hub et « vialet.app » en tete, une ligne par app installee
/// (sa plaque, son nom en Bricolage, son statut, ses actions rapides, sa mise a jour), les apps a
/// decouvrir, puis le site et, selon `options`, les reglages et Quitter. Au papier et a l'encre de
/// vialet.app. `run` ferme le menu puis lance l'action (voir `HubStatusItem.run`).
public struct HubMenu: View {
    public static let width: CGFloat = 330
    /// Au-dela, la liste defile (hauteur fixe).
    static let maxRowsWithoutScroll = 8
    /// Le site du hub.
    public static let siteURL = URL(string: "https://vialet.app")!

    let model: HubModel
    let options: HubMenuOptions
    let run: (@escaping @MainActor () -> Void) -> Void
    var onSizeChange: () -> Void
    @AppStorage private var showDiscover: Bool

    /// `showDiscover` est range sous `<App>ShowDiscover` (app du modele).
    public init(model: HubModel, options: HubMenuOptions = HubMenuOptions(),
                run: @escaping (@escaping @MainActor () -> Void) -> Void = { $0() },
                onSizeChange: @escaping () -> Void = {}) {
        self.model = model
        self.options = options
        self.run = run
        self.onSizeChange = onSizeChange
        _showDiscover = AppStorage(wrappedValue: true, model.identity.key("ShowDiscover"))
    }

    private var discover: [CatalogEntry] { showDiscover ? model.listing.discover : [] }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let updater = options.updater {
                UpdateBanner(updater: updater).padding(.horizontal, -6)
            }
            list
            Divider().overlay(Theme.line).padding(.vertical, 6)
            footer
        }
        .padding(6)
        .frame(width: Self.width)
        .background(Theme.paper, in: shape)
        .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
        .clipShape(shape)
        .onChange(of: model.listing) { onSizeChange() }
        .onChange(of: model.updates) { onSizeChange() }
        .onChange(of: showDiscover) { onSizeChange() }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    // MARK: Tete

    private var header: some View {
        HStack(spacing: 9) {
            Image(nsImage: hubPlate).resizable().interpolation(.high).frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(verbatim: "vialet.app")
                .font(Theme.display(17))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            let count = model.pendingUpdates.count
            if count > 0 {
                Text(count == 1 ? "1 mise \u{00E0} jour" : "\(count) mises \u{00E0} jour")
                    .font(Theme.ui(11.5, weight: .semibold))
                    .foregroundStyle(Theme.coral)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// Un secteur par app listee (comme le logo du hub) ; sans fiche connue, l'icone de Vialet.
    private var hubPlate: NSImage {
        let palettes = model.palettes
        return palettes.isEmpty ? HubPlate.cropped(NSApp.applicationIconImage, pixels: 44)
                                : HubPlate.image(palettes, pixels: 44)
    }

    // MARK: Liste

    @ViewBuilder
    private var list: some View {
        let rows = model.listing.apps.count + discover.count
        if rows > Self.maxRowsWithoutScroll {
            ScrollView { rowsStack }.frame(height: 470).scrollIndicators(.automatic)
        } else {
            rowsStack
        }
    }

    private var rowsStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.listing.apps.isEmpty {
                Text("Aucune app vialet.app sur ce Mac pour l'instant.")
                    .font(Theme.ui(12.5)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 10).padding(.vertical, 8)
            }
            ForEach(model.listing.apps) { entry in
                AppRow(entry: entry, plate: model.plate(for: entry),
                       update: model.pendingUpdates.contains(entry) ? model.updates[entry.bundleIdentifier] : nil,
                       model: model, run: run)
            }
            if !discover.isEmpty {
                SectionHeader("\u{00C0} d\u{00E9}couvrir")
                    .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
                ForEach(discover, id: \.brand) { DiscoverRow(entry: $0, model: model, run: run) }
            }
        }
    }

    // MARK: Pied

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuLine("Toutes les apps sur vialet.app", trailingSymbol: "arrow.up.right") {
                run { [model] in model.openSite(HubMenu.siteURL) }
            }
            if let openSettings = options.openSettings {
                MenuLine("R\u{00E9}glages\u{2026}", shortcut: "\u{2318},") { run(openSettings) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            if let quitTitle = options.quitTitle {
                MenuLine(quitTitle, shortcut: "\u{2318}Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

// MARK: - Ligne d'app

private struct AppRow: View {
    let entry: HubEntry
    let plate: NSImage
    let update: SemanticVersion?
    let model: HubModel
    let run: (@escaping @MainActor () -> Void) -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(nsImage: plate).resizable().interpolation(.high)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.displayName)
                        .font(Theme.display(15.5))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 6)
                    Text(entry.version)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.inkFaint)
                }
                if let status = entry.status {
                    StatusLine(text: status, active: entry.active, palette: entry.palette)
                }
                if !entry.visibleActions.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(entry.visibleActions, id: \.id) { action in
                            ActionChip(action: action, palette: entry.palette) {
                                run { [model] in model.perform(action, of: entry) }
                            }
                        }
                    }
                } else if entry.status == nil, let tagline = entry.tagline {
                    Text(tagline).font(Theme.ui(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                if let update {
                    UpdateLink(version: update) {
                        run { [model] in model.update(entry) }
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
            .fill(hover ? rowTint : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { run { [model] in model.open(entry) } }
        .help("Ouvrir \(entry.displayName)")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.displayName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Ouvrir \(entry.displayName)") { model.open(entry) }
    }

    /// Survol : le fond pale de l'app en clair, sa nuit en sombre (comme ses sites).
    private var rowTint: Color {
        guard let p = entry.palette else { return Theme.ink.opacity(0.06) }
        return Color(light: p.pale, dark: p.night)
    }
}

/// Statut publie par l'app, sous son nom ; pastille a l'accent de l'app pendant une activite.
private struct StatusLine: View {
    let text: String
    let active: Bool
    let palette: AccentPalette?

    var body: some View {
        HStack(spacing: 6) {
            if active {
                Circle().fill(palette.map { Color(hex: $0.accent) } ?? Theme.accent).frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(text).font(Theme.ui(12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.ink : Theme.inkSoft).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Action rapide : pastille discrete, aux couleurs de l'affiche de l'app au survol.
private struct ActionChip: View {
    let action: AppAction
    let palette: AccentPalette?
    let perform: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 4) {
                Image(systemName: action.symbol).font(.system(size: 10, weight: .bold))
                Text(action.title).font(Theme.ui(11.5, weight: .semibold))
            }
            .foregroundStyle(hover ? deep : Theme.inkSoft)
            .padding(.horizontal, 8).padding(.vertical, 3.5)
            .background(Capsule().fill(hover ? background : Theme.ink.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(action.shortcut.map { "\(action.title) (\($0) dans l'app)" } ?? action.title)
    }

    /// La paire de l'affiche de l'app : texte `deep` sur `background` (contraste >= 4,5).
    private var background: Color { palette.map { Color(hex: $0.background) } ?? Theme.ink.opacity(0.12) }
    private var deep: Color { palette.map { Color(hex: $0.deep) } ?? Theme.ink }
}

/// « Mise a jour X.Y.Z disponible » : l'app la verifie et la propose (`<nom>://update`).
private struct UpdateLink: View {
    let version: SemanticVersion
    let perform: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                Circle().fill(Theme.coral).frame(width: 6, height: 6)
                Text("Mise \u{00E0} jour \(version.description) disponible")
                    .font(Theme.ui(11.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .underline(hover)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Ouvrir l'app et installer la mise \u{00E0} jour")
    }
}

// MARK: - A decouvrir

private struct DiscoverRow: View {
    let entry: CatalogEntry
    let model: HubModel
    let run: (@escaping @MainActor () -> Void) -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            GhostPlate(initial: String(entry.name.prefix(1))).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(Theme.display(14.5, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                if !entry.tagline.isEmpty {
                    Text(entry.tagline).font(Theme.ui(11.5)).foregroundStyle(Theme.inkFaint).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
            .fill(hover ? Theme.ink.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { run { [model] in model.openSite(entry.url) } }
        .help(entry.url.map { "Ouvrir \($0.host() ?? $0.absoluteString)" } ?? entry.name)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}

/// Plaque en pointilles d'une app pas encore installee, son initiale au centre.
private struct GhostPlate: View {
    let initial: String

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: side * 185 / 824, style: .circular)
                    .strokeBorder(Theme.inkFaint, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.4]))
                Text(initial).font(Theme.display(side * 0.46)).foregroundStyle(Theme.inkFaint)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Ligne de menu

private struct MenuLine: View {
    let title: String
    let shortcut: String?
    let trailingSymbol: String?
    let action: () -> Void
    @State private var hover = false

    init(_ title: String, shortcut: String? = nil, trailingSymbol: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.trailingSymbol = trailingSymbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.ui(13)).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut).font(Theme.ui(12)).foregroundStyle(Theme.inkFaint)
                }
                if let trailingSymbol {
                    Image(systemName: trailingSymbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? Theme.ink.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Plaque recadree

extension HubPlate {
    /// Icone d'app (plaque a 824/1024 avec ombre) recadree a sa plaque, en `pixels` de cote.
    public static func cropped(_ icon: NSImage, pixels: Int) -> NSImage {
        let side = CGFloat(pixels)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let radius = side * 185 / 824
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            let scale = 1024.0 / 824.0
            let drawn = rect.insetBy(dx: -side * (scale - 1) / 2, dy: -side * (scale - 1) / 2)
            icon.draw(in: drawn, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        return image
    }
}
