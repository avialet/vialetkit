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
    Test("codableRoundTrip") {
        let s = HotKeyShortcut(keyCode: 12, modifiers: NSEvent.ModifierFlags([.control]).rawValue, keyName: "Q")
        let data = try JSONEncoder().encode(s)
        expectEqual(try JSONDecoder().decode(HotKeyShortcut.self, from: data), s)
    },
])
