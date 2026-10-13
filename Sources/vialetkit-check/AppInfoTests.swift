import Foundation
import VialetKit

let appInfoTests: (String, [Test]) = ("AppInfo", [
    Test("versionFallsBackOutsideABundle") {
        // `swift run` n'a pas d'Info.plist : la version vaut 0.0.0.
        expectEqual(AppInfo.version, "0.0.0")
        expectEqual(AppInfo.semanticVersion, SemanticVersion(0))
    },
])
