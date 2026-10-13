import AppKit
import Carbon.HIToolbox
import Foundation
import VialetKit

let hotKeyTests: (String, [Test]) = ("HotKey", [
    Test("defaultIsShiftCommandSpace") {
        let d = HotKeyShortcut.default
        expectEqual(d.keyCode, UInt16(kVK_Space))
        expectEqual(d.display, "⇧⌘Espace")
    },
    Test("displayOrdersModifiersLikeMacOS") {
        let all = NSEvent.ModifierFlags([.command, .option, .control, .shift]).rawValue
        expectEqual(HotKeyShortcut(keyCode: 0, modifiers: all, keyName: "A").display, "⌃⌥⇧⌘A")
    },
    Test("carbonModifiersMapFlags") {
        let s = HotKeyShortcut(keyCode: 0, modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue, keyName: "A")
        expectEqual(s.carbonModifiers, UInt32(cmdKey) | UInt32(optionKey))
    },
    Test("controllerKeepsItsDefault") {
        MainActor.assumeIsolated {
            let key = "VialetKitCheck\(UInt32.random(in: 0...UInt32.max))HotKey"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let initial = HotKeyShortcut.space([.control, .shift])
            let controller = HotKeyController(defaultsKey: key, logName: "check", initial: initial)
            expectEqual(controller.defaultShortcut, initial)
            expectEqual(HotKeyController(defaultsKey: key, logName: "check").defaultShortcut, .default)
        }
    },
    Test("codableRoundTrip") {
        let s = HotKeyShortcut(keyCode: 12, modifiers: NSEvent.ModifierFlags([.control]).rawValue, keyName: "Q")
        let data = try JSONEncoder().encode(s)
        expectEqual(try JSONDecoder().decode(HotKeyShortcut.self, from: data), s)
    },
    Test("eventKindFromCarbon") {
        expectEqual(HotKeyEventKind(carbonKind: UInt32(kEventHotKeyPressed)), .pressed)
        expectEqual(HotKeyEventKind(carbonKind: UInt32(kEventHotKeyReleased)), .released)
        expectEqual(HotKeyEventKind(carbonKind: 0), nil)
    },
    Test("pressCallsActionReleaseCallsOnRelease") {
        MainActor.assumeIsolated {
            let hotKey = GlobalHotKey.shared
            let saved = (hotKey.action, hotKey.onRelease)
            defer { hotKey.action = saved.0; hotKey.onRelease = saved.1 }
            var log: [String] = []
            hotKey.action = { log.append("down") }
            hotKey.onRelease = { log.append("up") }
            hotKey.handle(.pressed)
            hotKey.handle(.released)
            expectEqual(log, ["down", "up"])
            hotKey.onRelease = nil
            hotKey.handle(.released)
            expectEqual(log, ["down", "up"])
        }
    },
    Test("startWithoutOnReleaseKeepsPressOnly") {
        MainActor.assumeIsolated {
            let key = "VialetKitCheck\(UInt32.random(in: 0...UInt32.max))HotKey"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let hotKey = GlobalHotKey.shared
            let saved = (hotKey.action, hotKey.onRelease)
            defer { hotKey.action = saved.0; hotKey.onRelease = saved.1 }
            let controller = HotKeyController(defaultsKey: key, logName: "check", initial: unusedShortcut)
            var presses = 0
            var staleRelease = false
            hotKey.onRelease = { staleRelease = true }
            controller.start { presses += 1 }
            defer { controller.suspend() }
            expect(hotKey.onRelease == nil, "start(action:) doit effacer un onRelease precedent")
            hotKey.handle(.pressed)
            hotKey.handle(.released)
            expectEqual(presses, 1)
            expect(!staleRelease)
        }
    },
    Test("startWithOnReleaseWiresBoth") {
        MainActor.assumeIsolated {
            let key = "VialetKitCheck\(UInt32.random(in: 0...UInt32.max))HotKey"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let hotKey = GlobalHotKey.shared
            let saved = (hotKey.action, hotKey.onRelease)
            defer { hotKey.action = saved.0; hotKey.onRelease = saved.1 }
            let controller = HotKeyController(defaultsKey: key, logName: "check", initial: unusedShortcut)
            var log: [String] = []
            controller.start(action: { log.append("down") }, onRelease: { log.append("up") })
            defer { controller.suspend() }
            hotKey.handle(.pressed)
            hotKey.handle(.released)
            expectEqual(log, ["down", "up"])
        }
    },
    Test("unregisterWhileDownReleasesOnce") {
        MainActor.assumeIsolated {
            let hotKey = GlobalHotKey.shared
            let saved = (hotKey.action, hotKey.onRelease)
            defer { hotKey.action = saved.0; hotKey.onRelease = saved.1 }
            var releases = 0
            hotKey.action = {}
            hotKey.onRelease = { releases += 1 }
            hotKey.unregister()
            expectEqual(releases, 0, "pas de relachement sans appui")
            hotKey.handle(.pressed)
            expect(hotKey.isDown)
            hotKey.unregister()
            expectEqual(releases, 1, "suspendre pendant l'appui doit relacher")
            expect(!hotKey.isDown)
            hotKey.unregister()
            hotKey.handle(.released)
            expectEqual(releases, 1, "un seul relachement par appui")
        }
    },
    Test("suspendWhileDownReleases") {
        MainActor.assumeIsolated {
            let key = "VialetKitCheck\(UInt32.random(in: 0...UInt32.max))HotKey"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let hotKey = GlobalHotKey.shared
            let saved = (hotKey.action, hotKey.onRelease)
            defer { hotKey.action = saved.0; hotKey.onRelease = saved.1 }
            let controller = HotKeyController(defaultsKey: key, logName: "check", initial: unusedShortcut)
            var log: [String] = []
            controller.start(action: { log.append("down") }, onRelease: { log.append("up") })
            hotKey.handle(.pressed)
            controller.suspend()
            hotKey.handle(.released)
            expectEqual(log, ["down", "up"])
        }
    },
])

/// Ctrl-Option-Maj-Cmd-F19 : combinaison que personne n'utilise, pour enregistrer un vrai raccourci pendant les tests.
private let unusedShortcut = HotKeyShortcut(
    keyCode: UInt16(kVK_F19),
    modifiers: NSEvent.ModifierFlags([.command, .option, .control, .shift]).rawValue,
    keyName: "F19")
