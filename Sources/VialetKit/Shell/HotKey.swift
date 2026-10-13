import AppKit
import Carbon.HIToolbox
import Observation

/// Raccourci clavier global (code de touche independant de la disposition).
public struct HotKeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    /// `NSEvent.ModifierFlags.rawValue`, limite a ⌘ ⌥ ⌃ ⇧.
    public var modifiers: UInt
    /// Nom de la touche tel qu'affiche ("Espace", "P"...).
    public var keyName: String

    /// ⇧⌘Espace : libre par defaut sur macOS (⌃Espace change de source de saisie,
    /// ⌘Espace ouvre Spotlight, ⌥Espace tape une espace insecable).
    public static let `default` = HotKeyShortcut(
        keyCode: UInt16(kVK_Space),
        modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue,
        keyName: "Espace")

    /// Espace avec d'autres modificateurs : la touche est la meme sur toutes les dispositions de clavier,
    /// contrairement aux lettres (kVK_ANSI_A est la touche Q d'un clavier AZERTY). Chaque app choisit
    /// une combinaison libre ; eviter ⌘Espace (Spotlight), ⌥⌘Espace (Finder), ⌃⌘Espace (emoji)
    /// et ⌃⌥Espace (source de saisie suivante).
    public static func space(_ modifiers: NSEvent.ModifierFlags) -> HotKeyShortcut {
        HotKeyShortcut(keyCode: UInt16(kVK_Space),
                       modifiers: modifiers.intersection([.command, .option, .control, .shift]).rawValue,
                       keyName: "Espace")
    }

    public var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    public var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// "⇧⌘Espace", dans l'ordre standard macOS ⌃⌥⇧⌘.
    public var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + keyName
    }

    /// Construit un raccourci depuis une frappe ; nil sans ⌘, ⌥ ou ⌃.
    public init?(event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.intersection([.command, .option, .control]).isEmpty else { return nil }
        self.init(keyCode: event.keyCode, modifiers: mods.rawValue, keyName: Self.name(for: event))
    }

    public init(keyCode: UInt16, modifiers: UInt, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    private static func name(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Espace"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: break
        }
        let chars = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespaces) ?? ""
        return chars.isEmpty ? "#\(event.keyCode)" : chars.uppercased()
    }
}

/// Appui ou relachement du raccourci global, d'apres le genre d'evenement Carbon.
public enum HotKeyEventKind: Equatable, Sendable {
    case pressed
    case released

    /// `kEventHotKeyPressed` ou `kEventHotKeyReleased` ; nil pour tout autre genre.
    public init?(carbonKind: UInt32) {
        switch carbonKind {
        case UInt32(kEventHotKeyPressed): self = .pressed
        case UInt32(kEventHotKeyReleased): self = .released
        default: return nil
        }
    }
}

/// Enregistrement Carbon : seul moyen d'avoir un raccourci global sans
/// demander l'autorisation d'accessibilite. Un seul raccourci par app.
@MainActor
public final class GlobalHotKey {
    public static let shared = GlobalHotKey()
    /// Appele a l'appui sur le raccourci.
    public var action: (() -> Void)?
    /// Appele au relachement (push-to-talk) ; nil : le relachement est ignore.
    public var onRelease: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    private init() {}

    /// Renvoie false si la combinaison est deja prise par une autre app.
    @discardableResult
    public func register(_ shortcut: HotKeyShortcut) -> Bool {
        unregister()
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x564C_4554), id: 1) // 'VLET'
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    public func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    /// Point d'entree du gestionnaire Carbon : l'appui declenche `action`, le relachement `onRelease`.
    /// Public pour les tests (et pour simuler le raccourci).
    public func handle(_ kind: HotKeyEventKind) {
        switch kind {
        case .pressed: action?()
        case .released: onRelease?()
        }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event, let kind = HotKeyEventKind(carbonKind: GetEventKind(event)) else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalHotKey.shared.handle(kind) }
            }
            return noErr
        }, specs.count, &specs, nil, nil)
        handlerInstalled = true
    }
}

/// Raccourci choisi par l'utilisateur, persiste (UserDefaults) et enregistre.
@MainActor
@Observable
public final class HotKeyController {
    private let defaultsKey: String
    private let logName: String

    public var shortcut: HotKeyShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: defaultsKey)
            }
            apply()
        }
    }
    public private(set) var isTaken = false
    /// Raccourci propre a l'app (`initial`), celui que retablit le bouton des reglages.
    public let defaultShortcut: HotKeyShortcut

    /// `defaultsKey` : cle UserDefaults (ex. "AllegeHotKey"). `logName` : nom de l'app dans les journaux.
    public init(defaultsKey: String, logName: String = AppInfo.displayName, initial: HotKeyShortcut = .default) {
        self.defaultsKey = defaultsKey
        self.logName = logName
        self.defaultShortcut = initial
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = initial
        }
    }

    /// Enregistre le raccourci, l'action a declencher a l'appui et, si fournie, celle du relachement
    /// (push-to-talk). Remplace les deux : `start { }` seul efface un `onRelease` precedent.
    public func start(action: @escaping () -> Void, onRelease: (@MainActor () -> Void)? = nil) {
        GlobalHotKey.shared.action = action
        GlobalHotKey.shared.onRelease = onRelease
        apply()
    }

    /// Suspend le raccourci (pendant qu'on en enregistre un nouveau).
    public func suspend() { GlobalHotKey.shared.unregister() }

    public func apply() {
        isTaken = !GlobalHotKey.shared.register(shortcut)
        NSLog("\(logName) raccourci global \(shortcut.display) : \(isTaken ? "deja pris" : "actif")")
    }
}
