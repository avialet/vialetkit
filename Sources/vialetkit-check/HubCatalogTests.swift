import Foundation
@testable import VialetKit

let catalogJSON = """
{
  "apps": [
    { "name": "Pico", "brand": "Pico", "url": "https://pico.vialet.app", "tagline": "Le gestionnaire de t\u{00E2}ches.", "status": "available" },
    { "name": "All\u{00E8}ge", "brand": "Allege", "url": "https://allege.vialet.app", "tagline": "All\u{00E8}ge vos images.", "status": "available" },
    { "name": "Chuchote", "brand": "Chuchote", "url": "https://chuchote.vialet.app", "tagline": "Parlez.", "status": "available" },
    { "name": "Bient\u{00F4}t", "brand": "Bientot", "url": "https://bientot.vialet.app", "tagline": "Plus tard.", "status": "soon" }
  ]
}
"""

let catalogTests: (String, [Test]) = ("Catalog", [
    Test("parsesHubCatalog") {
        let entries = Catalog.parse(Data(catalogJSON.utf8))
        expectEqual(entries?.map(\.brand), ["Pico", "Allege", "Chuchote", "Bientot"])
        expectEqual(entries?[1].name, "All\u{00E8}ge")
        expectEqual(entries?[1].url, URL(string: "https://allege.vialet.app"))
        expectEqual(entries?[1].tagline, "All\u{00E8}ge vos images.")
        expect(entries?[0].isAvailable == true)
        expect(entries?[3].isAvailable == false)
    },
    Test("toleratesMissingOptionalFields") {
        let json = #"{"apps": [{"name": "Pico", "brand": "Pico", "url": "https://pico.vialet.app"}, {"name": "Sans marque"}]}"#
        let entries = Catalog.parse(Data(json.utf8))
        expectEqual(entries?.map(\.brand), ["Pico"])
        expectEqual(entries?.first?.tagline, "")
        expect(entries?.first?.isAvailable == true, "statut absent : disponible")
    },
    Test("rejectsInvalidJSON") {
        expectEqual(Catalog.parse(Data("[]".utf8)), nil)
        expectEqual(Catalog.parse(Data("nope".utf8)), nil)
        expectEqual(Catalog.parse(Data(#"{"apps": 3}"#.utf8)), nil)
    },
    Test("onlyHttpsLinks") {
        let json = #"{"apps": [{"name": "X", "brand": "X", "url": "javascript:alert(1)"}, {"name": "Y", "brand": "Y", "url": "http://y.vialet.app"}]}"#
        let entries = Catalog.parse(Data(json.utf8))
        expectEqual(entries?.map(\.brand), ["X", "Y"])
        expectEqual(entries?[0].url, nil)
        expectEqual(entries?[1].url, nil)
    },
    Test("refreshAtMostDaily") {
        let now = Date(timeIntervalSince1970: 2_000_000)
        expect(Catalog.shouldRefresh(now: now, lastFetch: nil))
        expect(!Catalog.shouldRefresh(now: now, lastFetch: now.addingTimeInterval(-3600)))
        expect(!Catalog.shouldRefresh(now: now, lastFetch: now.addingTimeInterval(-23 * 3600)))
        expect(Catalog.shouldRefresh(now: now, lastFetch: now.addingTimeInterval(-24 * 3600)))
        expect(Catalog.shouldRefresh(now: now, lastFetch: now.addingTimeInterval(3600)), "horloge reculee")
        expectEqual(Catalog.url, URL(string: "https://vialet.app/apps.json")!)
    },
])
