import XCTest
@testable import ElectricalSystem

// Each expected time below is worked out by hand from amp-hours divided by amps.
// With the default 80% usable share: Battery 1 = 12.48 Ah, Battery 2 = 9.92 Ah, EBBS = 6.4 Ah.
final class PowerModelTests: XCTestCase {

    private func config(essential: Double = 12, usable: Double = 0.8) -> ElectricalConfig {
        var c = ElectricalConfig()
        c.essentialLoadA = essential
        c.usableFraction = usable
        return c
    }

    private func assertMinutes(_ value: Double?, _ expected: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard let value else { return XCTFail("expected about \(expected) min, got no limit", file: file, line: line) }
        XCTAssertEqual(value, expected, accuracy: 0.5, file: file, line: line)
    }

    func testDefaultsMatchPublishedRatings() {
        XCTAssertEqual(Ratings.battery1RatedAh, 15.6)
        XCTAssertEqual(Ratings.battery2RatedAh, 12.4)
        XCTAssertEqual(Ratings.ebbsRatedAh, 8.0)
        XCTAssertEqual(Ratings.essentialBreakerCeilingA, 35)   // 5 + 5 + 15 + 10
        XCTAssertEqual(Ratings.ebbsPlannedLoads.reduce(0) { $0 + $1.amps }, Ratings.ebbsPlannedLoadA, accuracy: 0.001)
        let c = ElectricalConfig()
        XCTAssertEqual(c.battery1UsableAh, 12.48, accuracy: 0.001)
        XCTAssertEqual(c.battery2UsableAh, 9.92, accuracy: 0.001)
        XCTAssertEqual(c.ebbsUsableAh, 6.4, accuracy: 0.001)
    }

    func testNormalNothingDrains() {
        let r = PowerModel.evaluate(ElectricalInputs(), config())
        XCTAssertNil(r.mainBusLostAtMin)
        XCTAssertNil(r.engineLostAtMin)
        XCTAssertEqual(r.battery1State, .charging)
        XCTAssertEqual(r.battery2State, .charging)
        XCTAssertEqual(r.now.mainFromAlt, 15)
        XCTAssertEqual(r.now.essentialFromMainAlt, 12)
        XCTAssertTrue(r.now.sideAFeedsEssential)
        XCTAssertFalse(r.now.sideBFeedsEssential)
    }

    func testMainAlternatorFailed() {
        var i = ElectricalInputs()
        i.mainAltOK = false
        i.mainBusLoadA = 10
        let r = PowerModel.evaluate(i, config())
        // Main bus on Battery 1: 12.48 Ah / 10 A = 74.9 min.
        assertMinutes(r.mainBusLostAtMin, 74.9)
        assertMinutes(r.battery1EmptyAtMin, 74.9)
        // Essential bus on the backup alternator (12 A is under its 30 A), so the engine is sustained.
        XCTAssertNil(r.engineLostAtMin)
        XCTAssertEqual(r.now.essentialFromBackupAlt, 12)
        XCTAssertEqual(r.battery1State, .discharging(amps: 10))
        XCTAssertEqual(r.battery2State, .charging)
        XCTAssertFalse(r.now.sideAFeedsEssential)
        XCTAssertTrue(r.now.sideBFeedsEssential)
    }

    func testMainAlternatorFailedLowRPMEssentialOverBackupLimit() {
        var i = ElectricalInputs()
        i.mainAltOK = false
        i.lowRPM = true
        i.mainBusLoadA = 0
        let r = PowerModel.evaluate(i, config(essential: 20))
        // Backup alternator gives 15 A, Battery 2 gives the other 5 A: 9.92 / 5 = 119 min.
        XCTAssertEqual(r.now.essentialFromBackupAlt, 15)
        XCTAssertEqual(r.battery2State, .discharging(amps: 5))
        assertMinutes(r.battery2EmptyAtMin, 119.0)
        // Then Battery 1 gives the 5 A: 12.48 / 5 = 149.8 min more.
        // After that the alternator is still connected but 5 A short, so the bus is over its limit, not dead.
        assertMinutes(r.essentialOverloadAtMin, 268.8)
        XCTAssertNil(r.engineLostAtMin)
    }

    func testBothAlternatorsFailed() {
        var i = ElectricalInputs()
        i.mainAltOK = false
        i.backupAltOK = false
        i.mainBusLoadA = 10
        let r = PowerModel.evaluate(i, config(essential: 35))
        // Battery 2 carries the engine first: 9.92 / 35 = 17.0 min.
        assertMinutes(r.battery2EmptyAtMin, 17.0)
        // Battery 1 has used 10 A for 17 min (2.83 Ah), leaving 9.65 Ah for 45 A = 12.9 min more.
        assertMinutes(r.engineLostAtMin, 29.9)
        assertMinutes(r.mainBusLostAtMin, 29.9)
        // With the main bus shed: (12.48 + 9.92) / 35 = 38.4 min.
        assertMinutes(r.engineLostIfMainShedMin, 38.4)
    }

    func testBothAlternatorsAndBattery1Failed() {
        var i = ElectricalInputs()
        i.mainAltOK = false
        i.backupAltOK = false
        i.battery1OK = false
        let r = PowerModel.evaluate(i, config(essential: 12))
        XCTAssertEqual(r.mainBusLostAtMin, 0)
        XCTAssertFalse(r.now.mainBusPowered)
        // Engine on Battery 2 alone: 9.92 / 12 = 49.6 min.
        assertMinutes(r.engineLostAtMin, 49.6)
        XCTAssertEqual(r.battery1State, .failed)
    }

    func testBothAlternatorsAndBattery2Failed() {
        var i = ElectricalInputs()
        i.mainAltOK = false
        i.backupAltOK = false
        i.battery2OK = false
        i.mainBusLoadA = 8
        let r = PowerModel.evaluate(i, config(essential: 12))
        // Everything on Battery 1: 12.48 / 20 = 37.4 min.
        assertMinutes(r.engineLostAtMin, 37.4)
        assertMinutes(r.mainBusLostAtMin, 37.4)
        XCTAssertEqual(r.battery1State, .discharging(amps: 20))
    }

    func testBackupAlternatorFailedOnly() {
        var i = ElectricalInputs()
        i.backupAltOK = false
        let r = PowerModel.evaluate(i, config())
        XCTAssertNil(r.engineLostAtMin)
        XCTAssertNil(r.mainBusLostAtMin)
        XCTAssertEqual(r.battery1State, .charging)
        XCTAssertEqual(r.battery2State, .standby)
    }

    func testBattery1FailedMainBusStaysOnAlternator() {
        var i = ElectricalInputs()
        i.battery1OK = false
        let r = PowerModel.evaluate(i, config())
        XCTAssertTrue(r.now.mainBusPowered)
        XCTAssertNil(r.mainBusLostAtMin)
        XCTAssertNil(r.engineLostAtMin)
    }

    func testBackupAlternatorAloneStillPowersTheEngine() {
        var i = ElectricalInputs()
        i.mainAltOK = false
        i.battery1OK = false
        i.battery2OK = false
        // Set load (35 A) is above the backup alternator's 30 A, and there is no battery to help.
        // The bus is still powered by the alternator. It is over its limit, not dead.
        var r = PowerModel.evaluate(i, config(essential: 35))
        XCTAssertTrue(r.now.essentialPowered)
        XCTAssertNil(r.engineLostAtMin)
        XCTAssertEqual(r.now.essentialFromBackupAlt, 30)
        XCTAssertEqual(r.now.essentialOverload, 5)
        XCTAssertEqual(r.essentialOverloadAtMin, 0)
        XCTAssertEqual(r.mainBusLostAtMin, 0)
        // With a load the alternator can carry, there is no overload at all.
        r = PowerModel.evaluate(i, config(essential: 12))
        XCTAssertTrue(r.now.essentialPowered)
        XCTAssertEqual(r.now.essentialOverload, 0)
        XCTAssertNil(r.essentialOverloadAtMin)
        XCTAssertNil(r.engineLostAtMin)
    }

    func testEverythingFailed() {
        var i = ElectricalInputs()
        i.mainAltOK = false
        i.backupAltOK = false
        i.battery1OK = false
        i.battery2OK = false
        let r = PowerModel.evaluate(i, config())
        XCTAssertEqual(r.engineLostAtMin, 0)
        XCTAssertEqual(r.mainBusLostAtMin, 0)
        XCTAssertFalse(r.now.essentialPowered)
    }

    func testEBBS() {
        var i = ElectricalInputs()
        var r = PowerModel.evaluate(i, config())
        XCTAssertEqual(r.ebbsState, .notArmed)
        // 6.4 Ah usable / 8.5 A = 45.2 min.
        XCTAssertEqual(r.ebbsLifeMin, 45.2, accuracy: 0.1)

        i.emergencyPower = true
        r = PowerModel.evaluate(i, config())
        XCTAssertEqual(r.ebbsState, .armed)

        i.mainAltOK = false
        i.battery1OK = false
        r = PowerModel.evaluate(i, config())
        XCTAssertEqual(r.ebbsState, .supplying)
    }

    func testUsableShareScalesTimes() {
        var i = ElectricalInputs()
        i.mainAltOK = false
        i.mainBusLoadA = 10
        let r = PowerModel.evaluate(i, config(usable: 1.0))
        // 15.6 Ah / 10 A = 93.6 min.
        assertMinutes(r.mainBusLostAtMin, 93.6)
    }

    func testDurationText() {
        XCTAssertEqual(PowerModel.durationText(17.9), "17 min")
        XCTAssertEqual(PowerModel.durationText(74.9), "1 h 14 min")
        XCTAssertEqual(PowerModel.durationText(600), "more than 10 h")
    }
}
