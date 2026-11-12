import XCTest
@testable import WeightAndBalance

/// Expected numbers come from running the web app's formulas (web/wb-core.js) on the same inputs.
final class WBCalcTests: XCTestCase {

    /// An RV-14 tailwheel with the loads used by the first version of this app.
    private func rv14() -> WBProfile {
        var p = WBProfile.new(reg: " n721ne ", model: "rv14", gear: .tail)
        p.wL = "599"; p.aL = "71.325"; p.wR = "583"; p.aR = "71.625"; p.w3 = "65"; p.a3 = "230.25"
        p.fuel = "50"; p.burn = "30"
        p.stations[0].load = "240"; p.stations[2].load = "20"
        return p
    }

    func testRV14MatchesEarlierVersion() throws {
        let p = rv14()
        XCTAssertEqual(p.reg, "N721NE")
        XCTAssertEqual(p.modelName, "RV-14")
        let r = try XCTUnwrap(WB.compute(p))
        XCTAssertEqual(r.emptyWeight, 1247, accuracy: 1e-9)
        XCTAssertEqual(r.emptyMoment, 99447.30, accuracy: 1e-6)
        XCTAssertEqual(r.zfW, 1507, accuracy: 1e-9)
        XCTAssertEqual(r.toW, 1807, accuracy: 1e-9)
        XCTAssertEqual(r.toM, 150587.1, accuracy: 1e-6)
        XCTAssertEqual(r.toCG, 83.33541781959049, accuracy: 1e-9)
        XCTAssertEqual(r.lW, 1627, accuracy: 1e-9)
        XCTAssertEqual(r.lCG, 83.48647818070067, accuracy: 1e-9)
        XCTAssertEqual(r.zfCG, 83.60723291307234, accuracy: 1e-9)
        XCTAssertEqual(r.maxFuel, 50, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(WB.mac(p, r.toCG)), 20.241817534983017, accuracy: 1e-9)
        XCTAssertEqual(r.level, .ok)
        XCTAssertEqual(r.statusText, "Within utility limits for takeoff and landing.")
        XCTAssertEqual(WB.fmt(r.toCG, 2), "83.34")
        XCTAssertEqual(WB.fmt(r.toW), "1,807")
    }

    func testAerobaticHeavyLoadIsOutOfLimits() throws {
        var p = rv14()
        p.stations[1].load = "220"; p.stations[2].load = "100"; p.cat = 1
        let r = try XCTUnwrap(WB.compute(p))
        XCTAssertEqual(r.toW, 2107, accuracy: 1e-9)
        XCTAssertEqual(r.toCG, 86.80972947318463, accuracy: 1e-9)
        XCTAssertEqual((r.maxFuel * 10).rounded(.down) / 10, 15.5, accuracy: 1e-9)
        XCTAssertEqual(r.level, .bad)
        XCTAssertEqual(r.statusText,
            "Out of limits: takeoff weight is 207 lb over the 1,900 lb aerobatic limit; takeoff CG 86.81 in is aft of 86 in; landing CG 87.26 in is aft of 86 in; zero-fuel CG 87.61 in is aft of 86 in.")
    }

    func testNosewheelRV7A() throws {
        let p = DemoMode.profile
        XCTAssertEqual(p.modelName, "RV-7A")
        XCTAssertEqual(p.gear.thirdWheel, "Nosewheel")
        let r = try XCTUnwrap(WB.compute(p))
        XCTAssertEqual(r.emptyWeight, 1100, accuracy: 1e-9)
        XCTAssertEqual(r.emptyMoment, 85585.4, accuracy: 1e-6)
        XCTAssertEqual(r.emptyCG, 77.80490909090909, accuracy: 1e-9)
        XCTAssertEqual(r.toW, 1762, accuracy: 1e-9)
        XCTAssertEqual(r.toCG, 83.69477866061294, accuracy: 1e-9)
        XCTAssertEqual(r.lCG, 83.96479902557857, accuracy: 1e-9)
        XCTAssertEqual(r.zfCG, 84.31139072847682, accuracy: 1e-9)
        XCTAssertEqual(r.maxFuel, 42, accuracy: 1e-9)
        XCTAssertEqual(r.statusText, "Within utility limits for takeoff and landing.")
        XCTAssertEqual(WB.chartRange(p, r), WBChartRange(x0: 76, x1: 89, xStep: 1, y0: 1000, y1: 1900, yStep: 100))
    }

    func testEditedEnvelopeAndArms() throws {
        var p = DemoMode.profile
        p.cats[0].aft = "83"
        var r = try XCTUnwrap(WB.compute(p))
        XCTAssertEqual(r.statusText,
            "Out of limits: takeoff CG 83.69 in is aft of 83 in; landing CG 83.96 in is aft of 83 in; zero-fuel CG 84.31 in is aft of 83 in.")
        p.cats[0].aft = "86.82"
        p.stations[2].arm = "130"; p.fuelArm = "81"
        r = try XCTUnwrap(WB.compute(p))
        let zfM: Double = 85585.4 + 350 * 97.48 + 60 * 130
        XCTAssertEqual(r.zfM, zfM, accuracy: 1e-6)
        XCTAssertEqual(r.toM, zfM + 252 * 81, accuracy: 1e-6)
        // Restoring the model defaults puts the arms back and keeps loads and scale readings
        p.applyPreset(p.model)
        XCTAssertEqual(p.stations[2].arm, "126.78")
        XCTAssertEqual(p.fuelArm, "80")
        XCTAssertEqual(p.stations[0].load, "180")
        XCTAssertEqual(p.wL, "420")
    }

    func testFourSeatSingleCategory() throws {
        var p = WBProfile.new(reg: "N10XX", model: "rv10")
        XCTAssertEqual(p.gear, .nose)
        XCTAssertFalse(p.twoCats)
        XCTAssertEqual(WB.missing(p), ["the empty weight (scale readings)"])
        XCTAssertNil(WB.compute(p))
        p.wL = "610"; p.aL = "124.4"; p.wR = "612"; p.aR = "124.4"; p.w3 = "398"; p.a3 = "50.4"
        p.fuel = "60"; p.burn = "40"
        p.stations[0].load = "200"; p.stations[1].load = "180"; p.stations[2].load = "300"; p.stations[3].load = "120"
        p.cat = 1 // ignored while the second category is off
        let r = try XCTUnwrap(WB.compute(p))
        XCTAssertEqual(r.toW, 2780, accuracy: 1e-9)
        XCTAssertEqual(r.toCG, 115.47424460431655, accuracy: 1e-9)
        XCTAssertEqual(r.statusText,
            "Out of limits: takeoff weight is 80 lb over the 2,700 lb normal limit; zero-fuel CG 116.45 in is aft of 116.24 in; baggage is 20 lb over the 100 lb limit.")
    }

    func testCustomAircraftNeedsLimits() {
        let p = WBProfile.new(reg: "C-GABC", model: "custom", gear: .nose)
        XCTAssertEqual(p.modelName, "")
        XCTAssertEqual(WB.missing(p), ["the empty weight (scale readings)", "the weight limit and CG range"])
        XCTAssertNil(WB.mac(p, 80))
    }

    func testChangingModelKeepsMatchingLoads() {
        var p = rv14()
        p.applyPreset("rv8")
        XCTAssertEqual(p.stations.map { "\($0.id):\($0.load)" }, ["pilot:240", "pax:0", "bagF:0", "bag:20", "bagS:0"])
        XCTAssertEqual(p.fuelArm, "80")
        XCTAssertEqual(p.wL, "599")
    }

    func testFuelCapacityAndBurn() throws {
        var p = rv14()
        p.fuel = "60"; p.burn = "70"; p.stations[2].load = "110"
        let r = try XCTUnwrap(WB.compute(p))
        XCTAssertEqual(r.fuelGal, 50, accuracy: 1e-9)
        XCTAssertEqual(r.burnGal, 50, accuracy: 1e-9)
        XCTAssertTrue(r.issues.contains("baggage is 10 lb over the 100 lb limit"))
        XCTAssertTrue(r.issues.contains("fuel is more than the 50 gal capacity"))
    }

    func testPresetPercentChordMatchesVansSheets() {
        // Van's sheets give each limit both in inches and as a percent of chord; the two must agree.
        let expected: [String: [Double]] = [
            "rv4": [15, 30, 27.5], "rv6": [15, 29, 26.5], "rv7": [15, 29, 25], "rv8": [15, 29, 26.5],
            "rv9": [15, 28, 24], "rv10": [15, 30], "rv14": [18, 29, 25],
        ]
        for (id, pct) in expected {
            let p = WBProfile.new(reg: "", model: id)
            XCTAssertEqual(try XCTUnwrap(WB.mac(p, WB.value(p.cats[0].fwd))), pct[0], accuracy: 0.15, id)
            XCTAssertEqual(try XCTUnwrap(WB.mac(p, WB.value(p.cats[0].aft))), pct[1], accuracy: 0.15, id)
            if pct.count > 2 {
                XCTAssertEqual(try XCTUnwrap(WB.mac(p, WB.value(p.cats[1].aft))), pct[2], accuracy: 0.15, id)
            }
        }
    }

    func testStepButtons() {
        XCTAssertEqual(WB.stepped("240", by: 5, min: 0, max: 300), "245")
        XCTAssertEqual(WB.stepped("298", by: 5, min: 0, max: 300), "300")
        XCTAssertEqual(WB.stepped("2", by: -5, min: 0, max: 300), "0")
        XCTAssertEqual(WB.stepped("", by: 1, min: 0, max: 50), "1")
        XCTAssertEqual(WB.stepped("12.5", by: 1, min: 0, max: 50), "13.5")
    }

    func testSavedProfileRoundTrip() throws {
        var p = rv14()
        p.cats[1].gross = "1950"; p.cat = 1
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(WBProfile.self, from: data), p)
    }

    func testEarlierVersionDataIsCarriedOver() throws {
        let old = Data(#"{"pil":"200","pax":"150","bag":"35","fuel":"40","burn":"25","wL":"601","aL":"71.325","wR":"583","aR":"71.625","wT":"65","aT":"230.25","dW":"-2.5","dA":"60","cat":"A"}"#.utf8)
        let p = try XCTUnwrap(Store.migrate(old))
        XCTAssertEqual(p.reg, "N721NE")
        XCTAssertEqual(p.modelName, "RV-14")
        XCTAssertEqual(p.gear, .tail)
        XCTAssertEqual(p.wL, "601"); XCTAssertEqual(p.w3, "65"); XCTAssertEqual(p.a3, "230.25")
        XCTAssertEqual(p.dW, "-2.5")
        XCTAssertEqual(p.stations.map { $0.load }, ["200", "150", "35"])
        XCTAssertEqual(p.fuel, "40"); XCTAssertEqual(p.cat, 1)
        XCTAssertEqual(p.activeCat.gross, "1900")
        let partial = try XCTUnwrap(Store.migrate(Data(#"{"pil":"200"}"#.utf8)))
        XCTAssertEqual(partial.stations[0].load, "200")
        XCTAssertEqual(partial.wL, "599")
    }
}
