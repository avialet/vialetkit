import Foundation
import VialetKit

private let t0 = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21

let textTests: (String, [Test]) = ("Detector", [
    Test("urlsAndEmails") {
        expectEqual(ContentDetector.detect("https://vialet.app/x?y=1"), .url)
        expectEqual(ContentDetector.detect("http://localhost:8080"), .url)
        expectEqual(ContentDetector.detect("  www.example.com/page  "), .url)
        expectEqual(ContentDetector.detect("a.vialet@plan-net.com"), .email)
        expectEqual(ContentDetector.detect("pas un mail @ ici"), .text)
    },
    Test("colors") {
        expectEqual(ContentDetector.detect("#2F6FEB"), .color)
        expectEqual(ContentDetector.detect("#fff"), .color)
        expectEqual(ContentDetector.detect("rgb(47, 111, 235)"), .color)
        expectEqual(ContentDetector.hexColor("#2F6FEB"), 0x2F6FEB)
        expectEqual(ContentDetector.hexColor("#fff"), 0xFFFFFF)
        expectEqual(ContentDetector.hexColor("rgb(47, 111, 235)"), 0x2F6FEB)
        expect(ContentDetector.hexColor("#12345") == nil)
        expectEqual(ContentDetector.detect("#hashtag"), .text)
    },
    Test("jsonCodePathNumber") {
        expectEqual(ContentDetector.detect("{\"a\": 1, \"b\": [1, 2]}"), .json)
        expectEqual(ContentDetector.detect("[1, 2, 3]"), .json)
        expectEqual(ContentDetector.detect("{pas du json}"), .code)
        expectEqual(ContentDetector.detect("func go() {\n    return 1\n}"), .code)
        expectEqual(ContentDetector.detect("SELECT * FROM todo WHERE id = 1;"), .code)
        expectEqual(ContentDetector.detect("/Users/aurelien/Documents/rapport.pdf"), .path)
        expectEqual(ContentDetector.detect("~/Downloads"), .path)
        expectEqual(ContentDetector.detect("42"), .number)
        expectEqual(ContentDetector.detect("1 200,50"), .number)
        expectEqual(ContentDetector.detect("-3.14"), .number)
        expectEqual(ContentDetector.detect("Bonjour, on se voit demain ?"), .text)
        expectEqual(ContentDetector.detect("12 rue des Lilas"), .text)
        expectEqual(ContentDetector.detect(""), .text)
    },
    Test("jsonPretty") {
        expectEqual(JSONTools.pretty("{\"b\":1,\"a\":[true,null]}"), "{\n  \"a\" : [\n    true,\n    null\n  ],\n  \"b\" : 1\n}")
        expect(JSONTools.pretty("nope") == nil)
    },
    Test("searchNormalizationDropsAccentsAndCase") {
        expectEqual(SearchNormalizer.normalize("Élève à l'École"), "eleve a l'ecole")
    },
    Test("timeBuckets") {
        let now = t0
        expectEqual(TimeBucket.bucket(for: now.addingTimeInterval(-30), now: now).label, "À l'instant")
        expectEqual(TimeBucket.bucket(for: now.addingTimeInterval(-5 * 60), now: now).label, "Il y a 5 min")
        expectEqual(TimeBucket.bucket(for: now.addingTimeInterval(-3 * 3600), now: now).label, "Aujourd'hui")
        expectEqual(TimeBucket.bucket(for: now.addingTimeInterval(-26 * 3600), now: now).label, "Hier")
        expectEqual(TimeBucket.bucket(for: now.addingTimeInterval(-4 * 86400), now: now).label, "Cette semaine")
        expectEqual(TimeBucket.bucket(for: now.addingTimeInterval(-40 * 86400), now: now).label, "Plus ancien")
    },
])

