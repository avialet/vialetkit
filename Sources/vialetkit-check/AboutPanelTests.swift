import AppKit
import Foundation
import VialetKit

let aboutPanelTests: (String, [Test]) = ("AboutPanel", [
    Test("creditsText") {
        MainActor.assumeIsolated {
            let s = AboutPanel.credits(allegeIdentity).string
            for part in ["Un projet d'Aur\u{00E9}lien Vialet", "Licence MIT", "allege.vialet.app", "Code source sur GitHub"] {
                expect(s.contains(part), "manque \(part) dans \(s)")
            }
        }
    },
    Test("creditsShowOverriddenSite") {
        MainActor.assumeIsolated {
            let hub = AppIdentity(name: "Vialet", displayName: "Vialet", repository: "avialet/vialet",
                                  bundleIdentifier: "fr.vialet.vialet", palette: .sea, glyph: "",
                                  site: URL(string: "https://vialet.app")!)
            let s = AboutPanel.credits(hub).string
            expect(s.contains("\nvialet.app\n"), s)
            expect(!s.contains("vialet.vialet.app"), s)
        }
    },
    Test("creditsCarryTwoLinks") {
        MainActor.assumeIsolated {
            let credits = AboutPanel.credits(allegeIdentity)
            var links: [(String, URL)] = []
            credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, range, _ in
                guard let value else { return }
                let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
                if let url { links.append(((credits.string as NSString).substring(with: range), url)) }
            }
            expectEqual(links.map(\.0), ["allege.vialet.app", "Code source sur GitHub"])
            expectEqual(links.map(\.1), [allegeIdentity.siteURL, allegeIdentity.repositoryURL])
        }
    },
    Test("creditsAreCenteredSystem11") {
        MainActor.assumeIsolated {
            let credits = AboutPanel.credits(allegeIdentity)
            var ok = true
            credits.enumerateAttributes(in: NSRange(location: 0, length: credits.length)) { attrs, _, _ in
                let font = attrs[.font] as? NSFont
                let style = attrs[.paragraphStyle] as? NSParagraphStyle
                if font?.pointSize != 11 || style?.alignment != .center { ok = false }
            }
            expect(ok, "police 11 et paragraphe centre partout")
        }
    },
    Test("linksKeepSystemLinkColor") {
        MainActor.assumeIsolated {
            let credits = AboutPanel.credits(allegeIdentity)
            credits.enumerateAttributes(in: NSRange(location: 0, length: credits.length)) { attrs, range, _ in
                let part = (credits.string as NSString).substring(with: range)
                if attrs[.link] != nil {
                    expect(attrs[.foregroundColor] == nil, "lien colore : \(part)")
                } else {
                    expect(attrs[.foregroundColor] as? NSColor == NSColor.labelColor, "texte sans labelColor : \(part)")
                }
            }
        }
    },
    Test("options") {
        MainActor.assumeIsolated {
            let o = AboutPanel.options(allegeIdentity)
            expectEqual(o[.applicationName] as? String, "All\u{00E8}ge")
            expectEqual(o[.applicationVersion] as? String, AppInfo.version)
            // Hors bundle, build == version : la parenthese de build est masquee.
            expectEqual(o[.version] as? String, "")
            expect(o[.credits] is NSAttributedString, "credits")
            expect(o[.applicationIcon] == nil, "pas d'icone : celle du bundle")
        }
    },
])
