import Foundation

// Weight and balance math and RV model defaults.
// Mirrors web/wb-core.js line for line so the iPhone app and the web app give the same numbers.

enum WBGear: String, Codable {
    case nose, tail

    var thirdWheel: String { self == .nose ? "Nosewheel" : "Tailwheel" }
}

/// A place weight is loaded: a seat or a baggage area.
struct WBStation: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var arm: String
    /// Limit in pounds; blank for none.
    var max: String
    var load: String
}

/// One loading envelope: a weight limit and a CG range.
struct WBCat: Codable, Equatable {
    var name: String
    var gross: String
    var fwd: String
    var aft: String

    var ready: Bool { WB.value(gross) > 0 && WB.value(aft) > WB.value(fwd) }
}

struct WBPreset: Identifiable {
    let id: String
    let name: String
    /// Name of the nosewheel version, or blank when there is none.
    let aName: String
    let gear: WBGear
    let le: String
    let chord: String
    let fuelArm: String
    let fuelCap: String
    let cats: [WBCat]
    let twoCats: Bool
    let stations: [WBStation]
    let note: String

    var menuName: String {
        if id == "custom" { return "Other / custom values" }
        return aName.isEmpty ? name : "\(name) / \(aName)"
    }
}

enum WBData {
    private static func st(_ id: String, _ name: String, _ arm: String, _ max: String = "") -> WBStation {
        WBStation(id: id, name: name, arm: arm, max: max, load: "0")
    }

    private static func cat(_ name: String, _ gross: String, _ fwd: String, _ aft: String) -> WBCat {
        WBCat(name: name, gross: gross, fwd: fwd, aft: aft)
    }

    // Limits and arms come from Van's Aircraft "Weight and Balance Data Quick Reference" sheets
    // (RV-12: Pilot's Operating Handbook Section IV). Fuel capacity and baggage figures come from
    // Van's specification tables unless the note says otherwise. Wheel arms are not published by
    // Van's; they come from each airplane's own weighing.
    static let presets: [WBPreset] = [
        WBPreset(id: "rv4", name: "RV-4", aName: "", gear: .tail, le: "60", chord: "58",
                 fuelArm: "70", fuelCap: "32",
                 cats: [cat("Utility", "1500", "68.7", "77.4"), cat("Aerobatic", "1375", "68.7", "75.9")],
                 twoCats: true,
                 stations: [st("pilot", "Pilot", "82.5"), st("pax", "Passenger", "107"),
                            st("bagF", "Forward baggage", "56.5"), st("bag", "Rear baggage", "130", "30")],
                 note: "Van's RV-4 Weight and Balance Data Quick Reference. Fuel 32 gal and baggage about 30 lb: Van's specifications table. The forward baggage area is an option; leave it at 0 if you do not have one."),
        WBPreset(id: "rv6", name: "RV-6", aName: "RV-6A", gear: .tail, le: "60", chord: "58",
                 fuelArm: "70", fuelCap: "38",
                 cats: [cat("Utility", "1650", "68.7", "76.8"), cat("Aerobatic", "1375", "68.7", "75.3")],
                 twoCats: true,
                 stations: [st("pilot", "Pilot", "87.4"), st("pax", "Passenger", "87.4"), st("bag", "Baggage", "117")],
                 note: "Van's RV-6 Weight and Balance Data Quick Reference. Fuel capacity 38 gal is the commonly published figure, not from a Van's sheet; check yours. No baggage limit is pre-filled; enter the limit from your own records."),
        WBPreset(id: "rv7", name: "RV-7", aName: "RV-7A", gear: .tail, le: "70", chord: "58",
                 fuelArm: "80", fuelCap: "42",
                 cats: [cat("Utility", "1800", "78.7", "86.82"), cat("Aerobatic", "1600", "78.7", "84.5")],
                 twoCats: true,
                 stations: [st("pilot", "Pilot", "97.48"), st("pax", "Passenger", "97.48"), st("bag", "Baggage", "126.78", "100")],
                 note: "Van's RV-7 Weight and Balance Data Quick Reference. Fuel 42 gal and baggage 100 lb: Van's specifications table."),
        WBPreset(id: "rv8", name: "RV-8", aName: "RV-8A", gear: .tail, le: "70", chord: "58",
                 fuelArm: "80", fuelCap: "42",
                 cats: [cat("Utility", "1800", "78.7", "86.82"), cat("Aerobatic", "1600", "78.7", "85.3")],
                 twoCats: true,
                 stations: [st("pilot", "Pilot", "91.78"), st("pax", "Passenger", "119.12"),
                            st("bagF", "Forward baggage", "58.51"), st("bag", "Aft baggage floor", "138"),
                            st("bagS", "Aft baggage shelf", "152.91")],
                 note: "Van's RV-8 Weight and Balance Data Quick Reference. Aerobatic gross weight is 1,600 lb with the Dash-One wing and 1,550 lb without it; change it if yours is the earlier wing. Fuel 42 gal: Van's specifications table, which lists about 125 lb of baggage in total. No limit is pre-filled for each baggage area; enter your own."),
        WBPreset(id: "rv9", name: "RV-9", aName: "RV-9A", gear: .tail, le: "70", chord: "53",
                 fuelArm: "76.75", fuelCap: "36",
                 cats: [cat("Normal", "1750", "77.95", "84.84"), cat("Utility", "1600", "77.95", "82.72")],
                 twoCats: true,
                 stations: [st("pilot", "Pilot", "92.7"), st("pax", "Passenger", "92.7"), st("bag", "Baggage", "122", "100")],
                 note: "Van's RV-9 Weight and Balance Data Quick Reference. The RV-9 is not aerobatic; its second envelope is the utility category (1,600 lb, aft limit 82.72 in). Fuel 36 gal and baggage 100 lb: Van's specifications table."),
        WBPreset(id: "rv10", name: "RV-10", aName: "", gear: .nose, le: "99.44", chord: "56",
                 fuelArm: "108.9", fuelCap: "60",
                 cats: [cat("Normal", "2700", "107.84", "116.24"), cat("Category 2", "", "", "")],
                 twoCats: false,
                 stations: [st("pilot", "Pilot", "114.58"), st("pax", "Front passenger", "114.58"),
                            st("rear", "Rear passengers", "151.26"), st("bag", "Baggage", "173.5", "100")],
                 note: "Van's RV-10 Weight and Balance Data Quick Reference. Fuel capacity 60 gal and baggage 100 lb are the commonly published figures, not from a Van's sheet; check yours."),
        WBPreset(id: "rv12", name: "RV-12", aName: "", gear: .nose, le: "", chord: "",
                 fuelArm: "110.28", fuelCap: "20",
                 cats: [cat("Light-sport", "1320", "80.49", "85.39"), cat("Category 2", "", "", "")],
                 twoCats: false,
                 stations: [st("pilot", "Pilot", "78.85"), st("pax", "Passenger", "78.85"), st("bag", "Baggage", "110.81", "50")],
                 note: "Van's RV-12 Pilot's Operating Handbook, Section IV (CG limits and arms). Gross weight 1,320 lb, fuel 20 gal and baggage 50 lb are the commonly published figures; check your handbook. These are for the original RV-12. The RV-12iS has a different fuel tank arm, so use Custom values from your own handbook for an RV-12iS."),
        WBPreset(id: "rv14", name: "RV-14", aName: "RV-14A", gear: .tail, le: "72", chord: "56",
                 fuelArm: "81.97", fuelCap: "50",
                 cats: [cat("Utility", "2050", "82.08", "88.24"), cat("Aerobatic", "1900", "82.08", "86")],
                 twoCats: true,
                 stations: [st("pilot", "Pilot", "99.83"), st("pax", "Passenger", "99.83"), st("bag", "Baggage", "129.48", "100")],
                 note: "Van's RV-14 Weight and Balance Data Quick Reference. Fuel 50 gal and baggage 100 lb: Van's RV-14 specification sheet."),
    ]

    static let custom = WBPreset(
        id: "custom", name: "Custom", aName: "", gear: .tail, le: "", chord: "", fuelArm: "", fuelCap: "",
        cats: [cat("Utility", "", "", ""), cat("Aerobatic", "", "", "")], twoCats: false,
        stations: [st("pilot", "Pilot", ""), st("pax", "Passenger", ""), st("bag", "Baggage", "")],
        note: "Custom aircraft: every limit and arm is entered by you from your aircraft's own records.")

    static func preset(_ id: String) -> WBPreset {
        presets.first { $0.id == id } ?? custom
    }

    /// Name shown for the model: the "A" name when it has a nosewheel. Blank for custom.
    static func modelName(_ id: String, _ gear: WBGear) -> String {
        let p = preset(id)
        if p.id == "custom" { return "" }
        return gear == .nose && !p.aName.isEmpty ? p.aName : p.name
    }
}

/// Everything about one aircraft and its current load, kept as typed text and saved between launches.
struct WBProfile: Codable, Equatable {
    var v = 1
    var reg = ""
    var model = "custom"
    var gear: WBGear = .tail
    var wL = "", aL = "", wR = "", aR = "", w3 = "", a3 = ""
    var dW = "0", dA = "0"
    var stations: [WBStation] = []
    var fuelArm = "", fuelCap = "", lbGal = "6"
    var fuel = "0", burn = "0"
    var cats: [WBCat] = []
    var twoCats = false
    var cat = 0
    var le = "", chord = ""

    static func cleanReg(_ s: String) -> String {
        String(s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(12))
    }

    static func new(reg: String, model: String, gear: WBGear? = nil) -> WBProfile {
        let d = WBData.preset(model)
        var p = WBProfile()
        p.reg = cleanReg(reg)
        p.gear = gear ?? d.gear
        p.applyPreset(d.id)
        return p
    }

    /// Copies a model's limits and arms in. Loads typed for stations with the same id are kept.
    mutating func applyPreset(_ id: String) {
        let d = WBData.preset(id)
        var old: [String: String] = [:]
        for s in stations { old[s.id] = s.load }
        model = d.id
        le = d.le
        chord = d.chord
        fuelArm = d.fuelArm
        fuelCap = d.fuelCap
        cats = d.cats
        twoCats = d.twoCats
        if !twoCats { cat = 0 }
        stations = d.stations.map { s in
            var n = s
            n.load = old[s.id] ?? "0"
            return n
        }
    }

    var modelName: String { WBData.modelName(model, gear) }

    /// The envelope in use.
    var activeCat: WBCat {
        if cats.isEmpty { return WBCat(name: "", gross: "", fwd: "", aft: "") }
        return cats[twoCats && cat == 1 && cats.count > 1 ? 1 : 0]
    }
}

struct WBRow: Equatable {
    let name: String
    let weight: Double
    let arm: Double
    var moment: Double { weight * arm }
}

struct WBResult {
    enum Level { case ok, warn, bad }

    let catName: String
    let emptyWeight: Double
    let emptyMoment: Double
    let rows: [WBRow]
    let fuelGal: Double
    let burnGal: Double
    let fuelArm: Double
    let lbGal: Double
    let gross: Double
    let fwdCG: Double
    let aftCG: Double
    let zfW: Double, zfM: Double, zfCG: Double
    let fuelW: Double
    let toW: Double, toM: Double, toCG: Double
    let lW: Double, lM: Double, lCG: Double
    let maxFuel: Double
    let issues: [String]
    let level: Level
    let statusText: String

    var emptyCG: Double { emptyMoment / emptyWeight }
    var margin: Double { gross - toW }
    var overWeight: Bool { toW > gross }
    var burnW: Double { burnGal * lbGal }

    func inCG(_ c: Double) -> Bool { c >= fwdCG - 1e-9 && c <= aftCG + 1e-9 }
}

struct WBChartRange: Equatable {
    let x0: Double, x1: Double, xStep: Double
    let y0: Double, y1: Double, yStep: Double
}

enum WB {
    // MARK: Reading numbers

    /// Any number, including negative (scale readings, arms, add/remove item). Blank or unreadable is 0.
    static func value(_ s: String) -> Double {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        guard let v = Double(t), v.isFinite else { return 0 }
        return v
    }

    /// Load entries: anything not positive counts as zero.
    static func positive(_ s: String) -> Double {
        let v = value(s)
        return v > 0 ? v : 0
    }

    /// Up/down buttons: add the step and keep it inside the field's range.
    static func stepped(_ s: String, by step: Double, min lo: Double, max hi: Double) -> String {
        plain(Swift.max(lo, Swift.min(hi, value(s) + step)))
    }

    /// Writes a number the way a text box would show it: 245, 12.5.
    static func plain(_ v: Double) -> String {
        let r = (v * 1_000_000).rounded() / 1_000_000
        if r == r.rounded(), abs(r) < 1e15 { return String(Int(r)) }
        return String(r)
    }

    // MARK: Formatting

    private static var formatters: [Int: NumberFormatter] = [:]

    /// US grouping with a fixed number of decimals: 1,807 or 83.34.
    static func fmt(_ x: Double, _ digits: Int = 0) -> String {
        let f: NumberFormatter
        if let cached = formatters[digits] {
            f = cached
        } else {
            f = NumberFormatter()
            f.locale = Locale(identifier: "en_US")
            f.numberStyle = .decimal
            f.minimumFractionDigits = digits
            f.maximumFractionDigits = digits
            f.roundingMode = .halfUp
            formatters[digits] = f
        }
        let tiny = 0.5 * pow(10, -Double(digits))
        let v = abs(x) < tiny ? 0 : x
        return f.string(from: NSNumber(value: v)) ?? ""
    }

    // MARK: Empty weight

    static func emptyWeight(_ p: WBProfile) -> (weight: Double, moment: Double) {
        let w0 = value(p.wL) + value(p.wR) + value(p.w3)
        let m0 = value(p.wL) * value(p.aL) + value(p.wR) * value(p.aR) + value(p.w3) * value(p.a3)
        return (w0 + value(p.dW), m0 + value(p.dW) * value(p.dA))
    }

    /// Percent of wing chord, or nil when the chord is not entered.
    static func mac(_ p: WBProfile, _ cg: Double) -> Double? {
        let c = value(p.chord)
        guard c > 0, !p.le.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return (cg - value(p.le)) / c * 100
    }

    /// What still has to be entered before a result can be shown; empty when ready.
    static func missing(_ p: WBProfile) -> [String] {
        var out: [String] = []
        if !(emptyWeight(p).weight > 0) { out.append("the empty weight (scale readings)") }
        if !p.activeCat.ready { out.append("the weight limit and CG range") }
        return out
    }

    // MARK: Loading

    /// Nil until the empty weight and the active envelope are entered.
    static func compute(_ p: WBProfile) -> WBResult? {
        guard missing(p).isEmpty else { return nil }
        let (ew, em) = emptyWeight(p)
        let cat = p.activeCat
        let trimmedName = cat.name.trimmingCharacters(in: .whitespaces)
        let catName = (trimmedName.isEmpty ? "category" : trimmedName).lowercased()
        let gw = value(cat.gross), fwd = value(cat.fwd), aft = value(cat.aft)
        let lb = value(p.lbGal) > 0 ? value(p.lbGal) : 6
        let cap = positive(p.fuelCap)
        let fuelArm = value(p.fuelArm)

        var rows: [WBRow] = []
        var sumW = 0.0, sumM = 0.0
        for s in p.stations {
            let row = WBRow(name: s.name, weight: positive(s.load), arm: value(s.arm))
            rows.append(row)
            sumW += row.weight
            sumM += row.moment
        }

        let fuelEntered = positive(p.fuel)
        let fuelG = cap > 0 ? min(fuelEntered, cap) : fuelEntered
        let burnG = min(positive(p.burn), fuelG)
        let zfW = ew + sumW, zfM = em + sumM
        let fW = fuelG * lb
        let lfW = (fuelG - burnG) * lb
        let toW = zfW + fW, toM = zfM + fW * fuelArm, toCG = toM / toW
        let lW = zfW + lfW, lM = zfM + lfW * fuelArm, lCG = lM / lW
        let zfCG = zfM / zfW
        let room = (gw - zfW) / lb
        let maxFuel = max(0, cap > 0 ? min(cap, room) : room)

        func inCG(_ c: Double) -> Bool { c >= fwd - 1e-9 && c <= aft + 1e-9 }
        func side(_ c: Double) -> String { c < fwd ? "forward of \(plain(fwd))" : "aft of \(plain(aft))" }

        var issues: [String] = []
        if toW > gw {
            issues.append("takeoff weight is \(fmt(toW - gw)) lb over the \(fmt(gw)) lb \(catName) limit")
        }
        if !inCG(toCG) { issues.append("takeoff CG \(fmt(toCG, 2)) in is \(side(toCG)) in") }
        if !inCG(lCG) { issues.append("landing CG \(fmt(lCG, 2)) in is \(side(lCG)) in") }
        if !inCG(zfCG) { issues.append("zero-fuel CG \(fmt(zfCG, 2)) in is \(side(zfCG)) in") }
        for s in p.stations {
            let mx = positive(s.max), w = positive(s.load)
            if mx > 0 && w > mx {
                issues.append("\(s.name.lowercased()) is \(fmt(w - mx)) lb over the \(plain(mx)) lb limit")
            }
        }
        if cap > 0 && fuelEntered > cap {
            issues.append("fuel is more than the \(plain(cap)) gal capacity")
        }

        let near = issues.isEmpty &&
            (gw - toW < 25 || aft - max(toCG, lCG, zfCG) < 0.3 || min(toCG, lCG) - fwd < 0.3)
        let level: WBResult.Level = !issues.isEmpty ? .bad : (near ? .warn : .ok)
        let status: String
        switch level {
        case .bad: status = "Out of limits: \(issues.joined(separator: "; "))."
        case .warn: status = "Within \(catName) limits, but close to an edge."
        case .ok: status = "Within \(catName) limits for takeoff and landing."
        }

        return WBResult(catName: catName, emptyWeight: ew, emptyMoment: em, rows: rows,
                        fuelGal: fuelG, burnGal: burnG, fuelArm: fuelArm, lbGal: lb,
                        gross: gw, fwdCG: fwd, aftCG: aft,
                        zfW: zfW, zfM: zfM, zfCG: zfCG, fuelW: fW,
                        toW: toW, toM: toM, toCG: toCG, lW: lW, lM: lM, lCG: lCG,
                        maxFuel: maxFuel, issues: issues, level: level, statusText: status)
    }

    /// Axis ranges for the envelope chart, sized to the limits.
    static func chartRange(_ p: WBProfile, _ r: WBResult) -> WBChartRange {
        var xs: [Double] = []
        var top = 0.0
        for (i, c) in p.cats.enumerated() where (i == 0 || p.twoCats) && c.ready {
            xs.append(value(c.fwd))
            xs.append(value(c.aft))
            top = max(top, value(c.gross))
        }
        let lo = xs.min() ?? r.fwdCG, hi = xs.max() ?? r.aftCG
        let x0 = lo.rounded(.down) - 2, x1 = hi.rounded(.up) + 2
        let xStep: Double = (x1 - x0) > 14 ? 2 : 1
        let y1 = ((top + 100) / 100).rounded(.up) * 100
        var y0 = ((min(r.emptyWeight, r.zfW) - 50) / 100).rounded(.down) * 100
        if y0 >= y1 - 200 { y0 = y1 - 400 }
        if y0 < 0 { y0 = 0 }
        let yStep: Double = (y1 - y0) > 1400 ? 200 : 100
        return WBChartRange(x0: x0, x1: x1, xStep: xStep, y0: y0, y1: y1, yStep: yStep)
    }
}

enum Store {
    static let key = "homebuilt-wb-v1"
    /// Key used by the earlier single-aircraft version of this app.
    static let legacyKey = "n721ne-wb3"

    private struct Legacy: Decodable {
        var pil, pax, bag, fuel, burn, wL, aL, wR, aR, wT, aT, dW, dA, cat: String?
    }

    /// Turns data saved by the earlier N721NE-only version into a profile, so nothing typed is lost.
    static func migrate(_ data: Data) -> WBProfile? {
        guard let o = try? JSONDecoder().decode(Legacy.self, from: data) else { return nil }
        var p = WBProfile.new(reg: "N721NE", model: "rv14", gear: .tail)
        p.wL = o.wL ?? "599"; p.aL = o.aL ?? "71.325"
        p.wR = o.wR ?? "583"; p.aR = o.aR ?? "71.625"
        p.w3 = o.wT ?? "65"; p.a3 = o.aT ?? "230.25"
        p.dW = o.dW ?? "0"; p.dA = o.dA ?? "0"
        p.fuel = o.fuel ?? "50"; p.burn = o.burn ?? "30"
        let loads = ["pilot": o.pil ?? "240", "pax": o.pax ?? "0", "bag": o.bag ?? "20"]
        for i in p.stations.indices { p.stations[i].load = loads[p.stations[i].id] ?? "0" }
        p.cat = o.cat == "A" ? 1 : 0
        return p
    }

    /// Nil on a first launch, which is when the aircraft setup screen is shown.
    static func load() -> WBProfile? {
        if DemoMode.isOn { return DemoMode.profile }
        let d = UserDefaults.standard
        if let data = d.data(forKey: key), let p = try? JSONDecoder().decode(WBProfile.self, from: data) {
            return p
        }
        if let data = d.data(forKey: legacyKey), let p = migrate(data) {
            save(p)
            return p
        }
        return nil
    }

    static func save(_ p: WBProfile) {
        if DemoMode.isOn { return }
        if let data = try? JSONEncoder().encode(p) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Sample aircraft shown when the app is launched with "-demo" (used only for App Store screenshots).
enum DemoMode {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    /// "-demoScreen limits" opens the limits editor; "-demoScreen setup" opens the aircraft setup.
    static var screen: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-demoScreen"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static var profile: WBProfile {
        var p = WBProfile.new(reg: "N512PT", model: "rv7", gear: .nose)
        p.wL = "420"; p.aL = "90.5"; p.wR = "418"; p.aR = "90.5"; p.w3 = "262"; p.a3 = "37.2"
        p.fuel = "42"; p.burn = "20"
        let loads = ["pilot": "180", "pax": "170", "bag": "60"]
        for i in p.stations.indices { p.stations[i].load = loads[p.stations[i].id] ?? "0" }
        return p
    }
}
