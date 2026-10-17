import Foundation
@testable import VialetKit

/// Fichiers Swift du kit (Sources/VialetKit), lus depuis les sources du harnais.
private func kitSources() -> [URL] {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("VialetKit")
    let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
    return (walker?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
}

private final class Counter: @unchecked Sendable { var value = 0 }

let mainThreadTests: (String, [Test]) = ("MainThread", [
    Test("runsOnTheMainThreadAndReturnsItsValue") {
        var ran = false
        let value = MainActor.runOnMainThread { () -> Int in
            ran = Thread.isMainThread
            return 42
        }
        expect(ran, "corps execute sur le fil principal")
        expectEqual(value, 42)
    },
    Test("runsInsideANotificationObserver") {
        // Forme des observateurs du kit : file .main, rappel non isole.
        let center = NotificationCenter()
        let name = Notification.Name("VialetKitCheck.MainThread")
        let count = Counter()
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.runOnMainThread { count.value += 1 }
        }
        center.post(name: name, object: nil)
        center.removeObserver(token)
        expectEqual(count.value, 1)
    },
    Test("kitNeverAssumesIsolationThroughTheRuntime") {
        // MainActor.assumeIsolated lit l'executeur courant du runtime de concurrence, qu'une exception
        // Objective-C avalee par AppKit laisse pendant (plantage de Chuchote 0.2.2 dans DockPresence).
        let files = kitSources()
        expect(!files.isEmpty, "sources du kit introuvables")
        for file in files {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let uses = text.components(separatedBy: "\n").filter {
                $0.contains("MainActor.assumeIsolated") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///")
                    && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
            }
            expect(uses.isEmpty, "\(file.lastPathComponent) : \(uses.count) MainActor.assumeIsolated")
        }
    },
])
