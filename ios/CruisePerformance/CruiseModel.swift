import Foundation

enum MixMode: String {
    case lop
    case chart
}

static func bestEconomyKTAS(_ o: CruiseInputs) -> Double {
    let K = o.cal ? K_CAL : 1
    let hp = min(105, maxBhp(o.alt, o.dT))
    return speedForBhp(hp, o.alt, o.W, o.dT, K).rounded()
}
