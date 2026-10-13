import Foundation
@testable import VialetKit

let releaseNotesTests: (String, [Test]) = ("ReleaseNotes", [
    Test("dropsRedundantTitle") {
        let notes = ReleaseNotes(markdown: "## Pico 0.1.2\n\n- Version de maintenance.\n- Pastille du README.\n")
        expectEqual(notes.summary, "")
        expectEqual(notes.bullets, ["Version de maintenance.", "Pastille du README."])
        expect(!notes.isEmpty)
    },
    Test("keepsIntroAsSummary") {
        let notes = ReleaseNotes(markdown: "Nouvelle identit\u{00E9}.\n\n- Nouvelle ic\u{00F4}ne.\n- Titres en Bricolage.")
        expectEqual(notes.summary, "Nouvelle identit\u{00E9}.")
        expectEqual(notes.bullets, ["Nouvelle ic\u{00F4}ne.", "Titres en Bricolage."])
    },
    Test("acceptsStarsCrlfAndContinuations") {
        let notes = ReleaseNotes(markdown: "# Titre\r\n\r\n* Un\r\n  suite du un\r\n+ Deux\r\n  - Sous-point\r\n")
        expectEqual(notes.bullets, ["Un suite du un", "Deux", "Sous-point"])
    },
    Test("generatedNotesDropFullChangelog") {
        let md = "## What's Changed\n* Correctif by @avialet in https://github.com/a/b/pull/1\n\n**Full Changelog**: https://github.com/a/b/compare/v1...v2"
        let notes = ReleaseNotes(markdown: md)
        expectEqual(notes.summary, "")
        expectEqual(notes.bullets, ["Correctif by @avialet in https://github.com/a/b/pull/1"])
    },
    Test("emptyNotes") {
        expect(ReleaseNotes(markdown: "").isEmpty)
        expect(ReleaseNotes(markdown: "## Pico 0.2.0\n\n").isEmpty)
        expect(ReleaseNotes(markdown: "---\n* * *\n").isEmpty, "filets")
    },
    Test("summaryJoinsLines") {
        let notes = ReleaseNotes(markdown: "Premi\u{00E8}re ligne\nseconde ligne.\n\nAutre paragraphe.\n\n- Point")
        expectEqual(notes.summary, "Premi\u{00E8}re ligne seconde ligne. Autre paragraphe.")
    },
    Test("inlineMarkdown") {
        let text = ReleaseNotes.inline("**Nouveau** : `code` et [site](https://vialet.app)")
        expectEqual(String(text.characters), "Nouveau : code et site")
        expectEqual(String(ReleaseNotes.inline("[lien casse(").characters), "[lien casse(")
    },
    Test("releaseInfoExposesNotes") {
        let json = Data("""
        {"tag_name":"v0.2.0","body":"## Pico 0.2.0\\n\\n- A\\n- B","html_url":"https://github.com/avialet/pico/releases/tag/v0.2.0",
         "assets":[{"name":"Pico-0.2.0.dmg","browser_download_url":"https://github.com/a/Pico-0.2.0.dmg"},
                   {"name":"Pico-0.2.0.dmg.sha256","browser_download_url":"https://github.com/a/s"}]}
        """.utf8)
        expectEqual(ReleaseInfo.parse(json: json, appName: "Pico")?.releaseNotes.bullets, ["A", "B"])
        expectEqual(ReleaseInfo.notesBody(json: json), "## Pico 0.2.0\n\n- A\n- B")
        expect(ReleaseInfo.notesBody(json: Data("[]".utf8)) == nil)
    },
    Test("onlyMarkdownHeadingsAreDropped") {
        let notes = ReleaseNotes(markdown: "#\n####### pas un titre\n#42 corrige le bandeau\n\n- Point")
        expectEqual(notes.summary, "####### pas un titre #42 corrige le bandeau")
        expectEqual(ReleaseNotes(markdown: "- Un\n#42 suite").bullets, ["Un #42 suite"])
    },
    Test("inlineKeepsOnlyWebLinks") {
        let web = ReleaseNotes.inline("[site](https://vialet.app)")
        expectEqual(web.runs.first?.link?.absoluteString, "https://vialet.app")
        for bad in ["[x](file:///etc/passwd)", "[x](javascript:alert(1))", "[x](pico://ouvrir)"] {
            let text = ReleaseNotes.inline(bad)
            expect(text.runs.allSatisfy { $0.link == nil }, "lien garde : \(bad)")
            expectEqual(String(text.characters), "x")
        }
    },
])
