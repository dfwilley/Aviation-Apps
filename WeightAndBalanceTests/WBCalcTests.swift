import XCTest
@testable import WeightAndBalance

/// Expected numbers come from running the web app's own formulas on the same inputs.
final class WBCalcTests: XCTestCase {

    func testDefaultLoadMatchesWebApp() throws {
        let r = try XCTUnwrap(WB.compute(WBInputs()))
        XCTAssertEqual(r.emptyWeight, 1247, accuracy: 1e-9)
        XCTAssertEqual(r.emptyMoment, 99447.30, accuracy: 1e-6)
        XCTAssertEqual(r.emptyCG, 79.75, accuracy: 0.005)
        XCTAssertEqual(r.zfW, 1507, accuracy: 1e-9)
        XCTAssertEqual(r.zfM, 125996.1, accuracy: 1e-6)
        XCTAssertEqual(r.toW, 1807, accuracy: 1e-9)
        XCTAssertEqual(r.toM, 150587.1, accuracy: 1e-6)
        XCTAssertEqual(r.toCG, 83.33541781959049, accuracy: 1e-9)
        XCTAssertEqual(r.lW, 1627, accuracy: 1e-9)
        XCTAssertEqual(r.lCG, 83.48647818070067, accuracy: 1e-9)
        XCTAssertEqual(r.zfCG, 83.60723291307234, accuracy: 1e-9)
        XCTAssertEqual(r.maxFuel, 50, accuracy: 1e-9)
        XCTAssertEqual(Limits.mac(r.toCG), 20.241817534983017, accuracy: 1e-9)
        XCTAssertEqual(r.level, .ok)
        XCTAssertEqual(r.statusText, "Within utility limits for takeoff and landing.")
        XCTAssertEqual(WB.fmt(r.toCG, 2), "83.34")
        XCTAssertEqual(WB.fmt(r.toW), "1,807")
    }

    func testAerobaticHeavyLoadIsOutOfLimits() throws {
        var i = WBInputs()
        i.pax = "220"; i.bag = "100"; i.cat = .aerobatic
        let r = try XCTUnwrap(WB.compute(i))
        XCTAssertEqual(r.toW, 2107, accuracy: 1e-9)
        XCTAssertEqual(r.toCG, 86.80972947318463, accuracy: 1e-9)
        XCTAssertEqual(r.lCG, 87.2618059159315, accuracy: 1e-9)
        XCTAssertEqual(r.zfCG, 87.61322634200333, accuracy: 1e-9)
        XCTAssertEqual((r.maxFuel * 10).rounded(.down) / 10, 15.5, accuracy: 1e-9)
        XCTAssertEqual(r.level, .bad)
        XCTAssertEqual(r.statusText,
            "Out of limits: takeoff weight is 207 lb over the 1,900 lb aerobatic limit; takeoff CG 86.81 in is aft of 86 in; landing CG 87.26 in is aft of 86 in; zero-fuel CG 87.61 in is aft of 86 in.")
    }

    func testAddRemoveItemChangesEmptyWeight() throws {
        var i = WBInputs()
        i.dW = "-2.5"; i.dA = "60"
        let r = try XCTUnwrap(WB.compute(i))
        XCTAssertEqual(r.emptyWeight, 1244.5, accuracy: 1e-9)
        XCTAssertEqual(r.emptyMoment, 99297.3, accuracy: 1e-6)
        XCTAssertEqual(r.toCG, 83.36774729842062, accuracy: 1e-9)
        XCTAssertTrue(WB.emptyWeightChanged(i))
        i.restoreWeighing()
        XCTAssertFalse(WB.emptyWeightChanged(i))
        XCTAssertEqual(i, WBInputs())
    }

    func testEditedScaleReadingsAndArms() throws {
        var i = WBInputs()
        i.wL = "601"; i.aT = "231"
        let r = try XCTUnwrap(WB.compute(i))
        XCTAssertEqual(r.emptyWeight, 1249, accuracy: 1e-9)
        let left: Double = 601 * 71.325
        let right: Double = 583 * 71.625
        let tail: Double = 65 * 231
        XCTAssertEqual(r.emptyMoment, left + right + tail, accuracy: 1e-6)
    }

    func testFuelBurnAndLimits() throws {
        var i = WBInputs()
        i.fuel = "60"; i.burn = "70"; i.bag = "110"
        let r = try XCTUnwrap(WB.compute(i))
        XCTAssertEqual(r.fuelGal, 50, accuracy: 1e-9)
        XCTAssertEqual(r.burnGal, 50, accuracy: 1e-9)
        XCTAssertTrue(r.issues.contains("baggage is 10 lb over the 100 lb limit"))
        XCTAssertTrue(r.issues.contains("fuel is more than the 50 gal capacity"))
    }

    func testNoScaleWeightsGivesNoResult() {
        var i = WBInputs()
        i.wL = "0"; i.wR = ""; i.wT = "0"
        XCTAssertNil(WB.compute(i))
    }

    func testStepButtons() {
        XCTAssertEqual(WB.stepped("240", by: 5, min: 0, max: 300), "245")
        XCTAssertEqual(WB.stepped("298", by: 5, min: 0, max: 300), "300")
        XCTAssertEqual(WB.stepped("2", by: -5, min: 0, max: 300), "0")
        XCTAssertEqual(WB.stepped("", by: 1, min: 0, max: 50), "1")
        XCTAssertEqual(WB.stepped("12.5", by: 1, min: 0, max: 50), "13.5")
    }

    func testSavedInputsRoundTrip() throws {
        var i = WBInputs()
        i.pil = "185"; i.aL = "71.4"; i.cat = .aerobatic
        let data = try JSONEncoder().encode(i)
        XCTAssertEqual(try JSONDecoder().decode(WBInputs.self, from: data), i)
        let partial = try JSONDecoder().decode(WBInputs.self, from: Data(#"{"pil":"200"}"#.utf8))
        XCTAssertEqual(partial.pil, "200")
        XCTAssertEqual(partial.wL, "599")
    }
}
