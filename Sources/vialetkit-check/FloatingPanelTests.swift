import AppKit
import Foundation
import SwiftUI
import VialetKit

let floatingPanelTests: (String, [Test]) = ("FloatingPanel", [
    Test("upperThirdOrigin") {
        let frame = CGRect(x: 0, y: 25, width: 1000, height: 800)
        let origin = FloatingPanelPlacement.upperThird.origin(in: frame, size: CGSize(width: 200, height: 100))
        // haut du panneau a 22 % de la hauteur visible sous le haut : 825 - 176 - 100
        expectEqual(origin, CGPoint(x: 400, y: 549))
    },
    Test("bottomOrigin") {
        let frame = CGRect(x: 0, y: 25, width: 1000, height: 800)
        let origin = FloatingPanelPlacement.bottom.origin(in: frame, size: CGSize(width: 200, height: 100))
        // bas du panneau a 10 % de la hauteur visible au-dessus du bas : 25 + 80
        expectEqual(origin, CGPoint(x: 400, y: 105))
    },
    Test("originFollowsSecondaryScreen") {
        let frame = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        let size = CGSize(width: 300, height: 60)
        expectEqual(FloatingPanelPlacement.bottom.origin(in: frame, size: size), CGPoint(x: -870, y: 190))
        expectEqual(FloatingPanelPlacement.upperThird.origin(in: frame, size: size), CGPoint(x: -870, y: 742))
    },
    Test("canBecomeKeyFollowsTakesFocus") {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let size = CGSize(width: 200, height: 100)
            let focused = FloatingPanel(size: size)
            expect(focused.takesFocus)
            expect(focused.canBecomeKey)
            let passive = FloatingPanel(size: size, takesFocus: false)
            expect(!passive.takesFocus)
            expect(!passive.canBecomeKey)
            expect(!passive.canBecomeMain)
            expect(!passive.ignoresMouseEvents)
        }
    },
    Test("resignKeyDismissesOnlyFocusedPanel") {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let size = CGSize(width: 200, height: 100)
            var dismissed: [String] = []
            let focused = FloatingPanel(size: size)
            focused.onDismiss = { dismissed.append("focused") }
            let passive = FloatingPanel(size: size, takesFocus: false)
            passive.onDismiss = { dismissed.append("passive") }
            focused.resignKey()
            passive.resignKey()
            expectEqual(dismissed, ["focused"])
        }
    },
    Test("controllerDefaultsAndOptions") {
        MainActor.assumeIsolated {
            let size = CGSize(width: 200, height: 100)
            let standard = FloatingPanelController(size: size) { EmptyView() }
            expect(standard.takesFocus)
            expectEqual(standard.placement, .upperThird)
            let listening = FloatingPanelController(size: size, takesFocus: false, placement: .bottom) { EmptyView() }
            expect(!listening.takesFocus)
            expectEqual(listening.placement, .bottom)
        }
    },
    Test("showDuringHideFadeKeepsPanelVisible") {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let controller = FloatingPanelController(size: CGSize(width: 200, height: 100),
                                                     takesFocus: false, placement: .bottom) { EmptyView() }
            controller.show()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            expect(controller.isVisible, "affiche apres show()")
            controller.hide()
            controller.show()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            expect(controller.isVisible, "le fondu de hide() ne doit pas masquer un show() posterieur")
            controller.hide()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            expect(!controller.isVisible, "masque apres hide()")
        }
    },
])
