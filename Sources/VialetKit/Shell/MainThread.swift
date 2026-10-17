import Foundation

extension MainActor {
    /// Execute `body` sur le MainActor depuis un rappel synchrone deja sur le fil principal (observateur
    /// de NotificationCenter en file `.main`, moniteur d'evenements, bloc de `DispatchQueue.main`).
    ///
    /// Remplace `MainActor.assumeIsolated` dans le kit et les apps. Celui-ci interroge le runtime de concurrence
    /// (`swift_task_isCurrentExecutor`), qui lit l'executeur courant enregistre par le fil. Une exception
    /// Objective-C levee dans une tache du MainActor puis avalee par AppKit (ex. `installTap` d'AVAudioEngine
    /// au mauvais format) laisse cet enregistrement pointer dans une pile morte : la verification suivante
    /// saute dans le tas et plante (Chuchote 0.2.2, dans l'observateur `didUpdate` de DockPresence).
    /// Ici la verification porte sur le fil (pthread), sans le runtime ; le fil principal est l'executeur
    /// du MainActor, la garantie est la meme. Meme conversion que la bibliotheque standard apres sa
    /// verification.
    public nonisolated static func runOnMainThread<T>(_ body: @MainActor () -> T) -> T {
        precondition(Thread.isMainThread, "MainActor.runOnMainThread hors du fil principal")
        return withoutActuallyEscaping(body) { isolated in
            unsafeBitCast(isolated, to: (() -> T).self)()
        }
    }
}
