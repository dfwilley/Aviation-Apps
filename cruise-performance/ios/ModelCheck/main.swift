// Prints the native model's numbers for the same cases the web app was run on.
// The build compares them with expected.json (made from the web app's own code).
import Foundation

func mix(_ s: String) -> MixMode { s == "lop" ? .lop : .chart }
func num(_ any: Any?) -> Double { (any as? NSNumber)?.doubleValue ?? 0 }

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let exp = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
var out: [String: Any] = [:]

out["solve"] = (exp["solve"] as! [[String: Any]]).map { c -> [String: Any] in
    let r = CruiseEngine.solve(CruiseInputs(alt: num(c["alt"]), dT: num(c["dT"]), W: num(c["W"]), pct: num(c["pct"]), mode: mix(c["mode"] as! String), cal: c["cal"] as! Bool))
    return ["ktas": r.ktas, "gph": r.gph, "bhp": r.bhp, "kias": r.kias, "eta": r.eta, "f": r.f, "D0": r.D0, "Di": r.Di, "limited": r.limited ? 1 : 0, "lopBlocked": r.lopBlocked ? 1 : 0]
}

out["finder"] = (exp["finder"] as! [[String: Any]]).map { c -> [String: Any] in
    let o = CruiseInputs(alt: 0, dT: num(c["dT"]), W: num(c["W"]), pct: 65, mode: mix(c["mode"] as! String), cal: c["cal"] as! Bool)
    switch CruiseEngine.findCruise(o, num(c["fK"]), num(c["fA"])) {
    case let .impossible(_, _, need, avail, top):
        return ["impossible": 1, "need": need, "avail": avail, "top": top]
    case let .ok(_, _, need, pct, lopOK, gChart, gLop, g, kias, options, betterAlt):
        let mt = CruiseEngine.mixTarget(pct: pct, lopOK: lopOK)
        let own = num(c["own"])
        let t = CruiseEngine.efiiTrim(rpm: options.first?.rpm, ownAfr0: own > 0 ? own : nil, target: mt.n)
        return ["impossible": 0, "need": need, "pct": pct, "g": g, "gChart": gChart, "gLop": gLop, "kias": kias,
                "nOpts": options.count, "rpm": options.first?.rpm ?? -1, "mp": options.first?.mp ?? -1,
                "betterAlt": betterAlt?.alt ?? -1, "betterGph": betterAlt?.gph ?? -1,
                "trim": t.map { $0.trim } ?? NSNull(), "base": t.map { $0.base } ?? NSNull()]
    }
}

var rows: [[String: Any]] = []
let table = CruiseEngine.cruiseTable(CruiseInputs(alt: 0, dT: 0, W: 1900, pct: 65, mode: .lop, cal: true))
for h in [2500.0, 8500, 14500] {
    let row = table.first { $0.h == h }!
    for cell in row.cells {
        rows.append(cell.na ? ["na": 1] : ["na": 0, "ktas": cell.ktas, "gph": cell.gph])
    }
}
out["table"] = rows

let p = CruiseEngine.planningNumbers(1900, true)
out["planning"] = ["hp200": p.hp200, "avail": p.avail, "p9c": p.p9c, "p9l": p.p9l, "v9c": p.v9c, "v9l": p.v9l]

let data = try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)
