import Foundation

// Weight and balance math for N721NE. Mirrors the N721NE Weight & Balance web app exactly.

enum WBCategory: String, Codable {
    case utility = "U"
    case aerobatic = "A"

    var name: String { self == .utility ? "utility" : "aerobatic" }
}

enum Limits {
    static let seatArm = 99.83
    static let baggageArm = 129.48
    static let fuelArm = 81.97
    static let forwardCG = 82.08
    static let aftCGUtility = 88.24
    static let aftCGAerobatic = 86.0
    static let grossUtility = 2050.0
    static let grossAerobatic = 1900.0
    static let baggageMax = 100.0
    static let fuelMax = 50.0
    static let lbPerGal = 6.0
    /// February 4, 2024 weighing.
    static let weighingWeight = 1247.0
    static let weighingMoment = 99447.30

    /// Percent of the 56 in wing chord; leading edge is 72 in aft of the datum.
    static func mac(_ cg: Double) -> Double { (cg - 72) / 56 * 100 }
}

/// Everything the user types, kept as text (like the web app's input boxes) and saved between launches.
struct WBInputs: Codable, Equatable {
    var pil = "240"
    var pax = "0"
    var bag = "20"
    var fuel = "50"
    var burn = "30"
    var wL = "599"
    var aL = "71.325"
    var wR = "583"
    var aR = "71.625"
    var wT = "65"
    var aT = "230.25"
    var dW = "0"
    var dA = "0"
    var cat: WBCategory = .utility

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WBInputs()
        func s(_ k: CodingKeys, _ fallback: String) -> String {
            (try? c.decodeIfPresent(String.self, forKey: k)) ?? fallback
        }
        pil = s(.pil, d.pil); pax = s(.pax, d.pax); bag = s(.bag, d.bag)
        fuel = s(.fuel, d.fuel); burn = s(.burn, d.burn)
        wL = s(.wL, d.wL); aL = s(.aL, d.aL); wR = s(.wR, d.wR); aR = s(.aR, d.aR)
        wT = s(.wT, d.wT); aT = s(.aT, d.aT); dW = s(.dW, d.dW); dA = s(.dA, d.dA)
        cat = (try? c.decodeIfPresent(WBCategory.self, forKey: .cat)) ?? .utility
    }

    /// "Restore February 4, 2024 weighing": scale readings, arms and the add/remove item go back to the weighing.
    mutating func restoreWeighing() {
        let d = WBInputs()
        wL = d.wL; aL = d.aL; wR = d.wR; aR = d.aR; wT = d.wT; aT = d.aT; dW = d.dW; dA = d.dA
    }
}

struct WBResult {
    enum Level { case ok, warn, bad }

    let category: WBCategory
    let emptyWeight: Double
    let emptyMoment: Double
    let pilot: Double
    let passenger: Double
    let baggage: Double
    let fuelGal: Double
    let burnGal: Double
    let gross: Double
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
    var burnW: Double { burnGal * Limits.lbPerGal }

    func inCG(_ c: Double) -> Bool { c >= Limits.forwardCG - 1e-9 && c <= aftCG + 1e-9 }
}

enum WB {
    // MARK: Reading numbers

    /// Any number, including negative (scale readings, arms, add/remove item).
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

    static func emptyWeight(_ i: WBInputs) -> (weight: Double, moment: Double) {
        let w0 = value(i.wL) + value(i.wR) + value(i.wT)
        let m0 = value(i.wL) * value(i.aL) + value(i.wR) * value(i.aR) + value(i.wT) * value(i.aT)
        return (w0 + value(i.dW), m0 + value(i.dW) * value(i.dA))
    }

    /// True when the empty weight no longer matches the February 4, 2024 weighing.
    static func emptyWeightChanged(_ i: WBInputs) -> Bool {
        let e = emptyWeight(i)
        return abs(e.weight - Limits.weighingWeight) > 0.05 || abs(e.moment - Limits.weighingMoment) > 1
    }

    // MARK: Loading

    /// Nil when the scale weights add up to zero or less.
    static func compute(_ i: WBInputs) -> WBResult? {
        let (ew, em) = emptyWeight(i)
        guard ew > 0 else { return nil }

        let pil = positive(i.pil), pax = positive(i.pax), bag = positive(i.bag)
        let fuelEntered = positive(i.fuel)
        let fuelG = min(fuelEntered, Limits.fuelMax)
        let burnG = min(positive(i.burn), fuelG)
        let gw = i.cat == .utility ? Limits.grossUtility : Limits.grossAerobatic
        let aft = i.cat == .utility ? Limits.aftCGUtility : Limits.aftCGAerobatic

        let zfW = ew + pil + pax + bag
        let zfM = em + (pil + pax) * Limits.seatArm + bag * Limits.baggageArm
        let fW = fuelG * Limits.lbPerGal
        let lfW = (fuelG - burnG) * Limits.lbPerGal
        let toW = zfW + fW, toM = zfM + fW * Limits.fuelArm, toCG = toM / toW
        let lW = zfW + lfW, lM = zfM + lfW * Limits.fuelArm, lCG = lM / lW
        let zfCG = zfM / zfW
        let maxFuel = max(0, min(Limits.fuelMax, (gw - zfW) / Limits.lbPerGal))

        let fwd = Limits.forwardCG
        func inCG(_ c: Double) -> Bool { c >= fwd - 1e-9 && c <= aft + 1e-9 }
        func side(_ c: Double) -> String { c < fwd ? "forward of \(plain(fwd))" : "aft of \(plain(aft))" }

        var issues: [String] = []
        if toW > gw {
            issues.append("takeoff weight is \(fmt(toW - gw)) lb over the \(fmt(gw)) lb \(i.cat == .utility ? "gross" : "aerobatic") limit")
        }
        if !inCG(toCG) { issues.append("takeoff CG \(fmt(toCG, 2)) in is \(side(toCG)) in") }
        if !inCG(lCG) { issues.append("landing CG \(fmt(lCG, 2)) in is \(side(lCG)) in") }
        if !inCG(zfCG) { issues.append("zero-fuel CG \(fmt(zfCG, 2)) in is \(side(zfCG)) in") }
        if bag > Limits.baggageMax {
            issues.append("baggage is \(fmt(bag - Limits.baggageMax)) lb over the \(plain(Limits.baggageMax)) lb limit")
        }
        if fuelEntered > Limits.fuelMax {
            issues.append("fuel is more than the \(plain(Limits.fuelMax)) gal capacity")
        }

        let near = issues.isEmpty &&
            (gw - toW < 25 || aft - max(toCG, lCG, zfCG) < 0.3 || min(toCG, lCG) - fwd < 0.3)
        let level: WBResult.Level = !issues.isEmpty ? .bad : (near ? .warn : .ok)
        let status: String
        switch level {
        case .bad: status = "Out of limits: \(issues.joined(separator: "; "))."
        case .warn: status = "Within \(i.cat.name) limits, but close to an edge."
        case .ok: status = "Within \(i.cat.name) limits for takeoff and landing."
        }

        return WBResult(category: i.cat, emptyWeight: ew, emptyMoment: em,
                        pilot: pil, passenger: pax, baggage: bag, fuelGal: fuelG, burnGal: burnG,
                        gross: gw, aftCG: aft,
                        zfW: zfW, zfM: zfM, zfCG: zfCG, fuelW: fW,
                        toW: toW, toM: toM, toCG: toCG, lW: lW, lM: lM, lCG: lCG,
                        maxFuel: maxFuel, issues: issues, level: level, statusText: status)
    }
}

enum Store {
    /// Same key name as the web app.
    static let key = "n721ne-wb3"

    static func load() -> WBInputs {
        guard let data = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode(WBInputs.self, from: data) else { return WBInputs() }
        return v
    }

    static func save(_ i: WBInputs) {
        if let data = try? JSONEncoder().encode(i) { UserDefaults.standard.set(data, forKey: key) }
    }
}
