import Foundation
@testable import VialetKit

let updateScheduleTests: (String, [Test]) = ("UpdateSchedule", [
    Test("checksAtFirstLaunch") {
        let now = Date(timeIntervalSince1970: 1_000_000)
        expect(Updater.shouldCheckAutomatically(now: now, lastCheck: nil, autoCheck: true))
    },
    Test("respectsAutoCheckSetting") {
        let now = Date(timeIntervalSince1970: 1_000_000)
        expect(!Updater.shouldCheckAutomatically(now: now, lastCheck: nil, autoCheck: false))
        expect(!Updater.shouldCheckAutomatically(now: now, lastCheck: now.addingTimeInterval(-86_400), autoCheck: false))
    },
    Test("keepsThirtyMinuteFloor") {
        let now = Date(timeIntervalSince1970: 1_000_000)
        expect(!Updater.shouldCheckAutomatically(now: now, lastCheck: now.addingTimeInterval(-60), autoCheck: true))
        expect(!Updater.shouldCheckAutomatically(now: now, lastCheck: now.addingTimeInterval(-29 * 60), autoCheck: true))
        expect(Updater.shouldCheckAutomatically(now: now, lastCheck: now.addingTimeInterval(-30 * 60), autoCheck: true))
        expect(Updater.shouldCheckAutomatically(now: now, lastCheck: now.addingTimeInterval(-7 * 3600), autoCheck: true))
    },
    Test("lastCheckInFutureDoesNotBlock") {
        // Horloge reculee : une derniere verification "dans le futur" ne bloque pas.
        let now = Date(timeIntervalSince1970: 1_000_000)
        expect(Updater.shouldCheckAutomatically(now: now, lastCheck: now.addingTimeInterval(3600), autoCheck: true))
    },
    Test("periodicIntervalIsSixHours") {
        expectEqual(Updater.automaticInterval, 6 * 3600)
        expectEqual(Updater.automaticFloor, 30 * 60)
    },
])
