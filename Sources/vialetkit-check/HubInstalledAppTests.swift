import Foundation
@testable import VialetKit

/// Faux bundle `<dossier>/<nom>.app/Contents/Info.plist`.
@discardableResult
func makeBundle(in dir: URL, name: String, bundleId: String, version: String = "0.2.0",
                displayName: String? = nil, scheme: String? = nil) throws -> URL {
    let app = dir.appendingPathComponent("\(name).app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": bundleId, "CFBundleName": name,
                               "CFBundleShortVersionString": version]
    if let displayName { info["CFBundleDisplayName"] = displayName }
    if let scheme { info["CFBundleURLTypes"] = [["CFBundleURLName": bundleId, "CFBundleURLSchemes": [scheme]]] }
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return app
}

func withTemporaryDirectory(_ body: (URL) throws -> Void) rethrows {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vialetcore-check-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

let installedAppTests: (String, [Test]) = ("InstalledApp", [
    Test("readsInfoPlist") {
        try withTemporaryDirectory { dir in
            let url = try makeBundle(in: dir, name: "Allege", bundleId: "fr.vialet.allege", version: "0.2.1",
                                     displayName: "All\u{00E8}ge", scheme: "allege")
            let app = InstalledApp.read(bundleURL: url)
            expectEqual(app?.bundleIdentifier, "fr.vialet.allege")
            expectEqual(app?.name, "Allege")
            expectEqual(app?.displayName, "All\u{00E8}ge")
            expectEqual(app?.version, "0.2.1")
            expectEqual(app?.scheme, "allege")
            expectEqual(app?.url.lastPathComponent, "Allege.app")
        }
    },
    Test("fallsBackOnBundleName") {
        try withTemporaryDirectory { dir in
            let url = try makeBundle(in: dir, name: "Pico", bundleId: "fr.vialet.pico")
            let app = InstalledApp.read(bundleURL: url)
            expectEqual(app?.displayName, "Pico")
            expectEqual(app?.scheme, nil)
        }
    },
    Test("ignoresOtherBundles") {
        try withTemporaryDirectory { dir in
            let url = try makeBundle(in: dir, name: "Safari", bundleId: "com.apple.Safari")
            expectEqual(InstalledApp.read(bundleURL: url), nil)
            expectEqual(InstalledApp.read(bundleURL: dir.appendingPathComponent("Absent.app")), nil)
        }
    },
    Test("scansFoldersOneLevelDeep") {
        try withTemporaryDirectory { dir in
            try makeBundle(in: dir, name: "Pico", bundleId: "fr.vialet.pico")
            try makeBundle(in: dir, name: "Vialet", bundleId: "fr.vialet.vialet")
            try makeBundle(in: dir, name: "Safari", bundleId: "com.apple.Safari")
            let sub = dir.appendingPathComponent("Outils")
            try makeBundle(in: sub, name: "Pince", bundleId: "fr.vialet.pince")
            let deep = sub.appendingPathComponent("Profond")
            try makeBundle(in: deep, name: "Brouillon", bundleId: "fr.vialet.brouillon")
            let found = InstalledApp.scan(directories: [dir, dir.appendingPathComponent("absent")])
            expectEqual(found.map(\.bundleIdentifier).sorted(), ["fr.vialet.pico", "fr.vialet.pince", "fr.vialet.vialet"])
        }
    },
    Test("firstFolderWinsForDuplicates") {
        try withTemporaryDirectory { dir in
            let a = dir.appendingPathComponent("a"), b = dir.appendingPathComponent("b")
            try makeBundle(in: a, name: "Pico", bundleId: "fr.vialet.pico", version: "0.2.0")
            try makeBundle(in: b, name: "Pico", bundleId: "fr.vialet.pico", version: "0.1.0")
            let found = InstalledApp.scan(directories: [a, b])
            expectEqual(found.count, 1)
            expectEqual(found.first?.version, "0.2.0")
        }
    },
])
