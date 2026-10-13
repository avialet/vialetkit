import AppKit
import ServiceManagement

/// Ouverture a la connexion via SMAppService.
@MainActor
public enum LaunchAtLogin {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    public static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Active ou desactive. Renvoie l'etat effectif (true si active ou en attente d'approbation).
    @discardableResult
    public static func set(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("\(AppInfo.displayName) login item: \(error)")
        }
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    public static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
