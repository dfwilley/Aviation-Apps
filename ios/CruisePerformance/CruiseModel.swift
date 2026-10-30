import Foundation

enum MixMode: String {
    case lop
    case chart
}

struct CruiseInputs {
    var alt: Double
    var dT: Double
    var W: Double
    var pct: Double
    var mode: MixMode
    var cal: Bool
}

struct CruiseComponent: Identifiable {
    let name: String
    let value: Double
    var id: String { name }
}

struct SolveResult {
    var bhp: Double
    var avail: Double
    var limited: Bool
    var ktas: Double
    var gph: Double
    var nmpg: Double
    var eta: Double
    var f: Double
    var D0: Double
    var Di: Double
    var comps: [CruiseComponent]
    var lopBlocked: Bool
    var kias: Double
}

struct CruiseOption: Identifiable {
    var rpm: Double
    var mp: Double
    var oversquare: Double
    var id: Double { rpm }
}

enum FinderResult {
    case impossible(V: Double, h: Double, need: Double, avail: Double, top: Double)
    case ok(
        V: Double,
        h: Double,
        need: Double,
        pct: Double,
        lopOK: Bool,
        gChart: Double,
        gLop: Double,
        g: Double,
        kias: Double,
        options: [CruiseOption],
        betterAlt: (alt: Double, gph: Double)?
    )
}

struct PlanningNumbers {
    var hp200: Double
    var avail: Double
    var p9c: Double
    var p9l: Double
    var v9c: Double
    var v9l: Double
}

struct CruiseRow: Identifiable {
    var h: Double
    var cells: [(na: Bool, ktas: Double, gph: Double)]
    var wideBhp: Double
    var wideKtas: Double
    var pref: Bool
    var id: Double { h }
}

enum CruiseEngine {
    static let KT = 1.68781
    private static let S_REF = 126.1
    private static let SPAN = 27.0
    private static let AR = SPAN * SPAN / S_REF
    private static let E_OSW = 0.78
    private static let WING_C = 58.0 / 12
    private static let WING_TC = 0.1575
    private static let WING_XM = 0.33
    private static let WING_SEXP = S_REF - (46.0 / 12) * WING_C
    private static let HT_SEXP = ((124.0 - 10) * 33.7) / 144
    private static let HT_C = 33.7 / 12
    private static let HT_TC = 0.10
    private static let VT_SEXP = 11.5
    private static let VT_C = (52.0 + 27) / 2 / 12
    private static let VT_TC = 0.10
    private static let FUS_L = 228.0 / 12
    private static let FUS_D = 46.9 / 12
    private static let K_ROUGH = 2.08e-5
    private static let COOL_RAW = 0.35
    private static let K_CAL = 0.7943
    private static let PROP_D = 74.0
    private static let PROP_K = 0.86
    private static let FT: [(Double, Double)] = [(0, 210), (5.6, 180), (10.9, 155), (19.3, 105)]
    private static let FF: [(Double, Double)] = [(110, 47), (150, 66), (160, 73), (170, 81.5), (180, 90), (210, 105)]
    private static let SLL: [(Double, Double, Double, Double)] = [
        (2000, 69.3, 7.47, 151.5),
        (2150, 79.6, 7.93, 165.6),
        (2350, 91.3, 8.36, 180.8),
        (2450, 95.1, 8.94, 189.9),
        (2700, 111.3, 9.56, 210),
    ]

    private struct Atm {
        var rho: Double
        var mu: Double
        var a: Double
        var sigma: Double
    }

    private static func atm(_ hft: Double, _ dT: Double) -> Atm {
        let T0 = 288.15
        let p0 = 101325.0
        let h = hft * 0.3048
        let Ti = T0 - 0.0065 * h
        let p = p0 * pow(Ti / T0, 5.25588)
        let T = Ti + dT
        let rho = p / (287.053 * T)
        let mu = (1.458e-6 * pow(T, 1.5)) / (T + 110.4)
        return Atm(
            rho: rho * 0.00194032,
            mu: mu * 0.0208854,
            a: sqrt(1.4 * 287.053 * T) * 3.28084,
            sigma: rho / 1.225
        )
    }

    private static func cf(_ L: Double, _ V: Double, _ A: Atm) -> Double {
        var Re = A.rho * V * L / A.mu
        let M = V / A.a
        Re = min(Re, 38.21 * pow(L / K_ROUGH, 1.053))
        return 0.455 / (pow(log10(Re), 2.58) * pow(1 + 0.144 * M * M, 0.65))
    }

    private static func ffLift(_ tc: Double, _ xm: Double, _ M: Double) -> Double {
        (1 + (0.6 / xm) * tc + 100 * pow(tc, 4)) * (1.34 * pow(M, 0.18))
    }

    private static func ffBody(_ f: Double) -> Double {
        1 + 60 / pow(f, 3) + f / 400
    }

    private static func fusSwet() -> Double {
        let l = FUS_L / FUS_D
        return Double.pi * FUS_D * FUS_L * pow(1 - 2 / l, 2.0 / 3) * (1 + 1 / l / l) - 5
    }

    private static func components(_ V: Double, _ h: Double, _ dT: Double, _ K: Double) -> [CruiseComponent] {
        let A = atm(h, dT)
        let M = V / A.a
        var c: [(String, Double)] = []
        c.append(("Wing", cf(WING_C, V, A) * ffLift(WING_TC, WING_XM, M) * WING_SEXP * (1.977 + 0.52 * WING_TC)))
        c.append(("Fuselage & canopy", cf(FUS_L, V, A) * ffBody(FUS_L / FUS_D) * fusSwet()))
        c.append(("Horizontal tail", cf(HT_C, V, A) * ffLift(HT_TC, 0.3, M) * 1.05 * HT_SEXP * (1.977 + 0.52 * HT_TC)))
        c.append(("Vertical tail", cf(VT_C, V, A) * ffLift(VT_TC, 0.3, M) * 1.05 * VT_SEXP * (1.977 + 0.52 * VT_TC)))
        c.append(("Wheel pants (2)", 0.40))
        c.append(("Main gear legs (2)", 0.12))
        c.append(("Tailwheel", 0.06))
        c.append(("Antennas, lights, exhaust", 0.15))
        let sub = c.reduce(0) { $0 + $1.1 }
        c.append(("Gaps, leaks, rivets", 0.08 * sub))
        c.append(("Cooling airflow", COOL_RAW))
        return c.map { CruiseComponent(name: $0.0, value: $0.1 * K) }
    }

    static func bisect(_ f: (Double) -> Double, _ a0: Double, _ b0: Double, _ n: Int = 60) -> Double {
        var a = a0
        var b = b0
        var fa = f(a)
        for _ in 0..<n {
            let m = (a + b) / 2
            let fm = f(m)
            if (fm > 0) == (fa > 0) {
                a = m
                fa = fm
            } else {
                b = m
            }
        }
        return (a + b) / 2
    }

    private static func propEff(_ bhp: Double, _ V: Double, _ rho: Double) -> Double {
        let A = Double.pi * pow(PROP_D / 24, 2)
        let P = bhp * 550
        let a = bisect({ x in 2 * rho * A * V * V * x * (1 + x) * V - (PROP_K * P) / (1 + x) }, 1e-6, 2)
        return PROP_K / (1 + a)
    }

    private struct PowerReq {
        var D0: Double
        var Di: Double
        var f: Double
        var comps: [CruiseComponent]
        var q: Double
        var thp: Double
        var rho: Double
    }

    private static func powerReq(_ V: Double, _ h: Double, _ W: Double, _ dT: Double, _ K: Double) -> PowerReq {
        let A = atm(h, dT)
        let q = 0.5 * A.rho * V * V
        let comps = components(V, h, dT, K)
        let f = comps.reduce(0) { $0 + $1.value }
        let CL = W / (q * S_REF)
        let Di = q * S_REF * CL * CL / (Double.pi * AR * E_OSW)
        return PowerReq(D0: q * f, Di: Di, f: f, comps: comps, q: q, thp: (q * f + Di) * V / 550, rho: A.rho)
    }

    private static func bhpForSpeed(_ V: Double, _ h: Double, _ W: Double, _ dT: Double, _ K: Double) -> (bhp: Double, eta: Double, req: PowerReq) {
        let r = powerReq(V, h, W, dT, K)
        var bhp = r.thp / 0.8
        var eta = 0.8
        for _ in 0..<30 {
            eta = propEff(bhp, V, r.rho)
            bhp = r.thp / eta
        }
        return (bhp, eta, r)
    }

    static func speedForBhp(_ bhp: Double, _ h: Double, _ W: Double, _ dT: Double, _ K: Double) -> Double {
        bisect({ v in bhpForSpeed(v * KT, h, W, dT, K).bhp - bhp }, 80, 260)
    }

    private static func interp(_ x: Double, _ pts: [(Double, Double)]) -> Double {
        if x <= pts[0].0 {
            let a = pts[0]
            let b = pts[1]
            return a.1 + (x - a.0) * (b.1 - a.1) / (b.0 - a.0)
        }
        for i in 1..<pts.count where x <= pts[i].0 {
            let a = pts[i - 1]
            let b = pts[i]
            return a.1 + (x - a.0) * (b.1 - a.1) / (b.0 - a.0)
        }
        let a = pts[pts.count - 2]
        let b = pts[pts.count - 1]
        return a.1 + (x - a.0) * (b.1 - a.1) / (b.0 - a.0)
    }

    static func maxBhp(_ h: Double, _ dT: Double) -> Double {
        let p = interp(h / 1000, FT)
        let Ts = 59 - 3.566 * h / 1000
        let Ta = Ts + dT * 1.8
        return p * sqrt((460 + Ts) / (460 + Ta))
    }

    static func fuelLbHr(_ bhp: Double, _ mode: MixMode) -> Double {
        if mode == .lop { return 0.40 * bhp }
        if bhp < 110 { return 47 / 110 * bhp }
        return interp(bhp, FF)
    }

    static func solve(_ o: CruiseInputs) -> SolveResult {
        let K = o.cal ? K_CAL : 1.0
        let avail = maxBhp(o.alt, o.dT)
        var bhp = 2.10 * o.pct
        var limited = false
        if bhp > avail {
            bhp = avail
            limited = true
        }
        let ktas = speedForBhp(bhp, o.alt, o.W, o.dT, K)
        let d = bhpForSpeed(ktas * KT, o.alt, o.W, o.dT, K)
        let lop = o.mode == .lop && bhp > 0.70 * 210
        let gph = fuelLbHr(bhp, lop ? .chart : o.mode) / 6.0
        return SolveResult(
            bhp: bhp,
            avail: avail,
            limited: limited,
            ktas: ktas,
            gph: gph,
            nmpg: ktas / gph,
            eta: d.eta,
            f: d.req.f,
            D0: d.req.D0,
            Di: d.req.Di,
            comps: d.req.comps,
            lopBlocked: lop,
            kias: ktas * sqrt(atm(o.alt, o.dT).sigma)
        )
    }

    private static func slPar(_ r: Double) -> (Double, Double, Double) {
        for i in 1..<SLL.count where r <= SLL[i].0 {
            let a = SLL[i - 1]
            let b = SLL[i]
            let t = (r - a.0) / (b.0 - a.0)
            return (a.1 + t * (b.1 - a.1), a.2 + t * (b.2 - a.2), a.3 + t * (b.3 - a.3))
        }
        let last = SLL[SLL.count - 1]
        return (last.1, last.2, last.3)
    }

    private static func ambHg(_ h: Double) -> Double {
        29.92 * pow(1 - 6.8756e-6 * h, 5.2559)
    }

    private static func mpFT(_ h: Double) -> Double {
        ambHg(h) - 0.2
    }

    private static func hpAt(_ r: Double, _ m: Double, _ h: Double, _ dT: Double) -> Double {
        let par = slPar(r)
        let hpSL = par.0 + par.1 * (m - 18)
        let hA = bisect({ x in mpFT(x) - m }, -3000, 30000)
        let hp: Double
        if hA <= 0 {
            hp = hpSL
        } else {
            let hpA = par.2 * interp(hA / 1000, FT) / 210
            hp = hpSL + (hpA - hpSL) * h / hA
        }
        let Ts = 59 - 3.566 * h / 1000
        let Ta = Ts + dT * 1.8
        return hp * sqrt((460 + Ts) / (460 + Ta))
    }

    static func findCruise(_ o: CruiseInputs, _ targetKtas: Double, _ targetAlt: Double) -> FinderResult {
        let K = o.cal ? K_CAL : 1
        let V = max(100, min(200, targetKtas))
        let h = max(0, min(16000, targetAlt))
        let d = bhpForSpeed(V * KT, h, o.W, o.dT, K)
        let need = d.bhp
        let avail = maxBhp(h, o.dT)
        if need > avail {
            let top = speedForBhp(avail, h, o.W, o.dT, K)
            return .impossible(V: V, h: h, need: need, avail: avail, top: top)
        }
        let mpMax = mpFT(h) - 0.3
        var options: [CruiseOption] = []
        var r = 2150.0
        while r <= 2700 {
            let hpMax = hpAt(r, mpMax, h, o.dT)
            if hpMax >= need {
                let m = bisect({ x in hpAt(r, x, h, o.dT) - need }, 10, mpMax)
                options.append(CruiseOption(rpm: r, mp: m, oversquare: m - r / 100))
            }
            r += 50
        }
        let pct = need / 2.1
        let lopOK = pct <= 70 && o.mode == .lop
        let gChart = fuelLbHr(need, .chart) / 6
        let gLop = fuelLbHr(need, .lop) / 6
        let g = lopOK ? gLop : gChart
        var cands: [(Double, Double)] = []
        var hh = 2500.0
        while hh <= 12500 {
            let n = bhpForSpeed(V * KT, hh, o.W, o.dT, K).bhp
            if n <= maxBhp(hh, o.dT) - 3 {
                cands.append((hh, fuelLbHr(n, lopOK ? .lop : .chart) / 6))
            }
            hh += 1000
        }
        var better: (alt: Double, gph: Double)? = nil
        if let b = cands.min(by: { $0.1 < $1.1 }), b.1 < g - 0.15 {
            better = (b.0, b.1)
        }
        return .ok(
            V: V, h: h, need: need, pct: pct, lopOK: lopOK,
            gChart: gChart, gLop: gLop, g: g,
            kias: V * sqrt(atm(h, o.dT).sigma),
            options: options, betterAlt: better
        )
    }

    static func planningNumbers(_ W: Double, _ cal: Bool) -> PlanningNumbers {
        let K = cal ? K_CAL : 1
        let hp200 = bhpForSpeed(200 * KT, 8500, W, 0, K).bhp
        let avail = maxBhp(8500, 0)
        let p9c = bisect({ p in fuelLbHr(p, .chart) / 6 - 9 }, 60, 210)
        let p9l = bisect({ p in fuelLbHr(p, .lop) / 6 - 9 }, 60, 210)
        return PlanningNumbers(
            hp200: hp200,
            avail: avail,
            p9c: p9c,
            p9l: p9l,
            v9c: speedForBhp(p9c, 8500, W, 0, K),
            v9l: speedForBhp(p9l, 8500, W, 0, K)
        )
    }

    static func cruiseTable(_ o: CruiseInputs) -> [CruiseRow] {
        var rows: [CruiseRow] = []
        var h = 2500.0
        while h <= 14500 {
            var cells: [(na: Bool, ktas: Double, gph: Double)] = []
            for p in [55.0, 65.0, 75.0] {
                if 2.1 * p > maxBhp(h, 0) {
                    cells.append((true, 0.0, 0.0))
                } else {
                    var rowIn = o
                    rowIn.alt = h
                    rowIn.dT = 0
                    rowIn.pct = p
                    let s = solve(rowIn)
                    cells.append((false, s.ktas, s.gph))
                }
            }
            var wideIn = o
            wideIn.alt = h
            wideIn.dT = 0
            wideIn.pct = 100
            let wide = solve(wideIn)
            rows.append(CruiseRow(h: h, cells: cells, wideBhp: wide.bhp, wideKtas: wide.ktas, pref: h >= 6500 && h <= 9500))
            h += 1000
        }
        return rows
    }

    static func bestEconomyKTAS(_ o: CruiseInputs) -> Double {
        let K = o.cal ? K_CAL : 1
        let hp = min(105, maxBhp(o.alt, o.dT))
        return speedForBhp(hp, o.alt, o.W, o.dT, K).rounded()
    }

    static func fmt(_ x: Double, _ d: Int = 0) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.minimumFractionDigits = d
        f.maximumFractionDigits = d
        return f.string(from: NSNumber(value: x)) ?? String(format: "%.\(d)f", x)
    }
}
