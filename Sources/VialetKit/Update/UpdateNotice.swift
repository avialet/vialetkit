import SwiftUI

/// Bandeau d'annonce, pleine largeur, a poser en haut de la fenetre principale (ou d'un panneau),
/// dans une pile sans espacement : `VStack(spacing: 0) { UpdateNotice(updater: .shared); ... }`.
/// Il n'occupe aucune place tant qu'il n'a rien a dire.
///
/// - Mise a jour disponible et non ecartee : << <App> X.Y.Z est disponible >>, << Nouveautes >> (deplie
///   le journal), << Plus tard >> (ecarte cette version, la suivante reapparait) et << Installer et relancer >>.
/// - Installation : avancement (telechargement, verification, relance), puis l'erreur eventuelle avec
///   << Reessayer >>.
/// - Premier lancement apres une mise a jour : << <App> a ete mis a jour en X.Y.Z >>, ses nouveautes
///   et << OK >>.
public struct UpdateNotice: View {
    let updater: Updater
    let padding: EdgeInsets
    @State private var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Marges autour du bandeau quand il est visible : 12 pt en haut et sur les cotes.
    public static let defaultPadding = EdgeInsets(top: 12, leading: 12, bottom: 0, trailing: 12)

    public init(updater: Updater, padding: EdgeInsets = UpdateNotice.defaultPadding) {
        self.init(updater: updater, padding: padding, expanded: false)
    }

    init(updater: Updater, padding: EdgeInsets, expanded: Bool) {
        self.updater = updater
        self.padding = padding
        self._expanded = State(initialValue: expanded)
    }

    // MARK: Etat

    enum Mode: Equatable {
        case progress(UpdateState)
        case failure(String)
        case available(ReleaseInfo)
        case updated(SemanticVersion, ReleaseNotes?)

        /// Nature du bandeau : l'animation joue a chaque changement de nature, pas a chaque pas
        /// du telechargement.
        var kind: Int {
            switch self {
            case .progress: 1
            case .failure: 2
            case .available: 3
            case .updated: 4
            }
        }
    }

    /// Ce que montre le bandeau : l'installation en cours ou son echec, sinon la version disponible
    /// non ecartee, sinon les nouveautes de la version installee ; nil : rien.
    @MainActor static func mode(for updater: Updater) -> Mode? {
        switch updater.state {
        case .downloading, .verifying, .installing:
            return .progress(updater.state)
        case .failed(let message) where updater.failedRelease != nil:
            return .failure(message)
        default:
            break
        }
        if let release = updater.announced { return .available(release) }
        if let version = updater.updatedVersion { return .updated(version, updater.updatedNotes) }
        return nil
    }

    // MARK: Vue

    public var body: some View {
        let mode = Self.mode(for: updater)
        VStack(spacing: 0) {
            if let mode {
                card(mode)
                    .padding(padding)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: mode?.kind)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: expanded)
    }

    private func card(_ mode: Mode) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        let notes = Self.notes(mode)
        return VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    icon(mode)
                    title(mode)
                    Spacer(minLength: 8)
                    actions(mode, notes: notes)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        icon(mode)
                        title(mode)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        actions(mode, notes: notes)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if expanded, let notes {
                journal(notes)
                    .transition(.opacity)
            }
        }
        .background(shape.fill(Self.background))
        .overlay(shape.strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1))
        .clipShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: Self.label(mode, appName: updater.configuration.displayName)))
    }

    /// Fond : `accentPale` en clair, `accentNight` en sombre.
    @MainActor static var background: Color { Color(light: Theme.palette.pale, dark: Theme.palette.night) }
    /// Titre : `deep` en clair, `nightInk` en sombre, comme l'affiche.
    @MainActor static var titleColor: Color { Color(light: Theme.palette.deep, dark: Theme.palette.nightInk) }

    /// Journal a deplier ; nil s'il n'y a rien a montrer.
    static func notes(_ mode: Mode) -> ReleaseNotes? {
        let notes: ReleaseNotes?
        switch mode {
        case .available(let release): notes = release.releaseNotes
        case .updated(_, let n): notes = n
        default: notes = nil
        }
        return notes?.isEmpty == false ? notes : nil
    }

    @ViewBuilder
    private func icon(_ mode: Mode) -> some View {
        let configuration = updater.configuration
        switch mode {
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
        case .progress where configuration.glyph.isEmpty:
            ProgressView().controlSize(.small).frame(width: 26, height: 26)
        default:
            if configuration.glyph.isEmpty {
                Image(systemName: mode.kind == 4 ? "sparkles" : "arrow.down.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
            } else {
                Image(nsImage: GlyphImage.plate(Theme.palette, glyph: configuration.glyph, pixels: 78,
                                                strokeDeep: configuration.strokeDeep))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Titre du bandeau.
    nonisolated static func headline(_ mode: Mode, appName name: String) -> String {
        switch mode {
        case .available(let release): "\(name) \(release.version) est disponible"
        case .updated(let version, _): "\(name) a \u{00E9}t\u{00E9} mis \u{00E0} jour en \(version)"
        case .progress(let state): UpdateText.status(state, appName: name)
        case .failure(let message): message
        }
    }

    /// Libelle d'accessibilite du bandeau (VoiceOver), avant ses boutons.
    nonisolated static func label(_ mode: Mode, appName: String) -> String {
        if case .failure(let message) = mode { return "\u{00C9}chec de la mise \u{00E0} jour : \(message)" }
        return "Mise \u{00E0} jour : " + headline(mode, appName: appName)
    }

    @ViewBuilder
    private func title(_ mode: Mode) -> some View {
        let name = updater.configuration.displayName
        switch mode {
        case .available, .updated:
            Text(verbatim: Self.headline(mode, appName: name))
                .font(Theme.display(15, weight: .bold)).foregroundStyle(Self.titleColor).lineLimit(1)
        case .progress:
            Text(verbatim: Self.headline(mode, appName: name))
                .font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                .monospacedDigit()
        case .failure(let message):
            Text(verbatim: message)
                .font(Theme.ui(12.5, weight: .medium)).foregroundStyle(Theme.ink)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func actions(_ mode: Mode, notes: ReleaseNotes?) -> some View {
        HStack(spacing: 14) {
            if notes != nil { notesToggle }
            switch mode {
            case .available:
                secondary("Plus tard") { updater.dismissAvailable() }
                primary("Installer et relancer") { updater.install() }
            case .updated:
                primary("OK") { updater.acknowledgeUpdate() }
            case .failure:
                secondary("Plus tard") { updater.dismissAvailable() }
                primary("R\u{00E9}essayer") { updater.retryInstall() }
            case .progress(let state):
                if case .downloading(let p) = state {
                    ProgressView(value: p).tint(Theme.accent).frame(width: 120)
                } else if !updater.configuration.glyph.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .fixedSize()
    }

    private var notesToggle: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: "Nouveaut\u{00E9}s")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .font(Theme.ui(12.5, weight: .semibold))
            .foregroundStyle(Theme.inkSoft)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(verbatim: expanded ? "d\u{00E9}pli\u{00E9}es" : "repli\u{00E9}es"))
    }

    private func secondary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(Theme.ui(12.5, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func primary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(Theme.ui(12.5, weight: .bold))
                .foregroundStyle(Theme.accentPrimaryButtonForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.accentPrimaryButtonBackground))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func journal(_ notes: ReleaseNotes) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            if !notes.summary.isEmpty {
                Text(ReleaseNotes.inline(notes.summary))
                    .font(Theme.ui(12.5, weight: .semibold)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
            }
            ForEach(Array(notes.bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 4.5, height: 4.5).offset(y: -2)
                    Text(ReleaseNotes.inline(bullet))
                        .font(Theme.ui(12.5)).foregroundStyle(Theme.ink.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 52)
        .padding(.trailing, 14)
        .padding(.vertical, 12)

        return VStack(spacing: 0) {
            Rectangle().fill(Theme.accent.opacity(0.18)).frame(height: 1)
            if notes.bullets.count > 7 {
                ScrollView { content }.frame(maxHeight: 190)
            } else {
                content
            }
        }
    }
}
