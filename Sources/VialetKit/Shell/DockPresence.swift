import AppKit
import Observation

/// Choix de l'utilisateur pour l'icone de l'app dans le Dock (`<App>DockMode`).
public enum DockMode: String, CaseIterable, Sendable {
    /// L'icone n'apparait que tant qu'une fenetre de l'app est ouverte (defaut).
    case whileWindowOpen
    /// L'icone reste dans le Dock.
    case always

    public var label: String {
        switch self {
        case .whileWindowOpen: "Pendant que la fen\u{00EA}tre est ouverte"
        case .always: "Toujours"
        }
    }

    /// Mode range ; une valeur absente ou inconnue donne `whileWindowOpen`.
    public static func resolve(stored: String?) -> DockMode {
        stored.flatMap(DockMode.init(rawValue:)) ?? .whileWindowOpen
    }

    /// L'icone est-elle dans le Dock, pour ces fenetres ?
    public func showsIcon(windows: [DockWindow]) -> Bool {
        switch self {
        case .always: true
        case .whileWindowOpen: windows.contains(where: \.counts)
        }
    }

    public func activationPolicy(windows: [DockWindow]) -> NSApplication.ActivationPolicy {
        showsIcon(windows: windows) ? .regular : .accessory
    }
}

/// Ce que `DockPresence` retient d'une fenetre.
public struct DockWindow: Equatable, Sendable {
    /// A l'ecran.
    public var isVisible: Bool
    /// Reduite dans le Dock.
    public var isMiniaturized: Bool
    /// Barre de titre : fenetre principale, Reglages, A propos.
    public var isTitled: Bool
    /// Niveau normal (ni flottant, ni menu, ni barre d'etat).
    public var isNormalLevel: Bool
    /// Panneau flottant du kit, fenetre de `MenuBarExtra` ou de la barre d'etat : ne compte jamais.
    public var isAuxiliary: Bool

    public init(isVisible: Bool, isMiniaturized: Bool, isTitled: Bool, isNormalLevel: Bool, isAuxiliary: Bool) {
        self.isVisible = isVisible
        self.isMiniaturized = isMiniaturized
        self.isTitled = isTitled
        self.isNormalLevel = isNormalLevel
        self.isAuxiliary = isAuxiliary
    }

    @MainActor
    public init(_ window: NSWindow) {
        let name = NSStringFromClass(type(of: window))
        self.init(isVisible: window.isVisible, isMiniaturized: window.isMiniaturized,
                  isTitled: window.styleMask.contains(.titled), isNormalLevel: window.level == .normal,
                  isAuxiliary: window is FloatingPanel || name.contains("MenuBarExtra") || name.contains("StatusBar"))
    }

    /// Fenetre « principale » ouverte (ou reduite) : elle garde l'icone dans le Dock.
    public var counts: Bool {
        (isVisible || isMiniaturized) && isTitled && isNormalLevel && !isAuxiliary
    }
}

/// Icone de l'app dans le Dock : en mode `whileWindowOpen` (defaut), l'app est un accessoire
/// (`.accessory`, ni Dock ni Cmd-Tab) tant qu'aucune fenetre titree n'est ouverte, et passe en
/// `.regular` (avec activation, la fenetre devant) des que la fenetre principale, les Reglages ou
/// A propos s'ouvrent ; elle redevient accessoire a la fermeture de la derniere. Les panneaux
/// flottants et les `MenuBarExtra` ne comptent pas. `always` garde l'icone.
///
/// Pour demarrer sans icone (sans clignotement), l'Info.plist porte `LSUIElement` = true ; l'app reste
/// joignable par sa barre des menus, Vialet, son raccourci et le Finder (`applicationShouldHandleReopen`
/// ouvre la fenetre). Lancee a l'ouverture de session (LaunchAtLogin), l'app ne prend pas le focus tant
/// que l'utilisateur n'y est pas venu.
///
/// ```swift
/// extension DockPresence { static let shared = DockPresence(app: Brand.identity) }
/// // applicationDidFinishLaunching
/// _ = DockPresence.shared
/// ```
@MainActor
@Observable
public final class DockPresence {
    public var mode: DockMode {
        didSet {
            defaults.set(mode.rawValue, forKey: modeKey)
            update()
        }
    }
    /// L'icone est dans le Dock (politique `.regular`).
    public private(set) var showsIcon = false

    private let defaults: UserDefaults
    private let modeKey: String
    private let windows: @MainActor () -> [DockWindow]
    private let isHidden: @MainActor () -> Bool
    private let apply: @MainActor (Bool) -> Void
    private let activate: @MainActor () -> Void
    /// Lancee a l'ouverture de session : pas de vol du focus tant que l'utilisateur n'est pas venu a l'app.
    private let launchedAsLoginItem: Bool
    @ObservationIgnored private var hasBeenActive = false
    @ObservationIgnored private var applied = false
    @ObservationIgnored private var scheduled = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    public convenience init(app: AppIdentity) {
        self.init(app: app, defaults: .standard,
                  windows: { NSApp.windows.map(DockWindow.init) },
                  isHidden: { NSApp.isHidden },
                  apply: { shows in
                      NSApp.setActivationPolicy(shows ? .regular : .accessory)
                      // Plus rien a montrer : l'app rend la main a la precedente.
                      let keyable = NSApp.windows.filter { $0.isVisible && $0.canBecomeKey }.count
                      if DockPresence.deactivates(showsIcon: shows, visibleKeyableWindows: keyable) { NSApp.deactivate() }
                  },
                  // Un tour plus tard : la politique `.regular` doit etre prise avant l'activation.
                  activate: { DispatchQueue.main.async { MainActor.assumeIsolated { DockPresence.bringWindowForward() } } },
                  launchedAsLoginItem: DockPresence.isLaunchedAsLoginItem(),
                  observe: true)
    }

    init(app: AppIdentity, defaults: UserDefaults, windows: @escaping @MainActor () -> [DockWindow],
         isHidden: @escaping @MainActor () -> Bool, apply: @escaping @MainActor (Bool) -> Void,
         activate: @escaping @MainActor () -> Void, launchedAsLoginItem: Bool = false, observe: Bool) {
        self.defaults = defaults
        self.modeKey = app.key("DockMode")
        self.windows = windows
        self.isHidden = isHidden
        self.apply = apply
        self.activate = activate
        self.launchedAsLoginItem = launchedAsLoginItem
        self.mode = DockMode.resolve(stored: defaults.string(forKey: modeKey))
        defaults.set(mode.rawValue, forKey: modeKey)
        update()
        if observe { startObserving() }
    }

    /// Relit les fenetres et pose la politique si elle change. Sans effet tant que l'app est masquee
    /// (Cmd-H) : l'icone reste, comme pour une app ordinaire.
    public func update() {
        guard !isHidden() else { return }
        let shows = mode.showsIcon(windows: windows())
        guard shows != showsIcon || !applied else { return }
        let appeared = shows && !showsIcon && mode == .whileWindowOpen
        showsIcon = shows
        applied = true
        apply(shows)
        if appeared, Self.mayActivate(launchedAsLoginItem: launchedAsLoginItem, hasBeenActive: hasBeenActive) {
            activate()
        }
    }

    /// L'app est passee au premier plan (l'utilisateur y est venu).
    func noteBecameActive() { hasBeenActive = true }

    /// Activer l'app a l'apparition d'une fenetre, sauf apres un lancement a l'ouverture de session tant
    /// que l'utilisateur n'est pas venu a l'app : une fenetre restauree ne vole pas le focus.
    nonisolated static func mayActivate(launchedAsLoginItem: Bool, hasBeenActive: Bool) -> Bool {
        !launchedAsLoginItem || hasBeenActive
    }

    /// Repasser la main a l'app precedente apres le passage en accessoire, s'il ne reste aucune fenetre
    /// (panneau, MenuBarExtra ouverts : on les laisse).
    nonisolated static func deactivates(showsIcon: Bool, visibleKeyableWindows: Int) -> Bool {
        !showsIcon && visibleKeyableWindows == 0
    }

    /// La fenetre a mettre devant : la principale (`WindowSummoner.mainWindow`), sinon la fenetre cle,
    /// sinon la premiere qui compte ; jamais une fenetre reduite.
    nonisolated static func windowToFront(main: Int?, key: Int?, windows: [DockWindow]) -> Int? {
        func usable(_ i: Int?) -> Int? {
            guard let i, windows.indices.contains(i), windows[i].counts, !windows[i].isMiniaturized else { return nil }
            return i
        }
        return usable(main) ?? usable(key) ?? windows.indices.first { windows[$0].counts && !windows[$0].isMiniaturized }
    }

    /// Lancement par l'ouverture de session (evenement d'ouverture « login item »), lu au lancement.
    static func isLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Une fenetre vient d'apparaitre alors que l'app etait accessoire : l'app passe devant, et la
    /// fenetre avec elle.
    static func bringWindowForward() {
        NSApp.activate()
        let all = NSApp.windows
        let main = WindowSummoner.mainWindow.flatMap { m in all.firstIndex { $0 === m } }
        let key = NSApp.keyWindow.flatMap { k in all.firstIndex { $0 === k } }
        if let i = windowToFront(main: main, key: key, windows: all.map(DockWindow.init)) {
            all[i].makeKeyAndOrderFront(nil)
        }
    }

    /// Une mise a jour au prochain tour de boucle (apres la fermeture effective d'une fenetre).
    private func schedule() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduled = false
                self?.update()
            }
        }
    }

    private func startObserving() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification, NSApplication.didUnhideNotification,
            NSApplication.didBecomeActiveNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            }
        }
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteBecameActive() }
        })
        // Une fenetre montree par une app accessoire non active (openWindow de SwiftUI, makeKeyAndOrderFront)
        // ne devient ni cle ni visible au sens des notifications ci-dessus : la mise a jour des fenetres
        // apres chaque evenement la voit. Seulement tant que l'icone est absente (apparition d'une fenetre) ;
        // les fermetures passent par willClose.
        observers.append(center.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.showsIcon == false { self?.update() } }
        })
    }
}
