import Foundation

// The electrical logic for N721NE, with no screen code in it so it can be tested.
//
// Sources for the wiring and numbers:
//   - EFII Bus Manager Installation Instructions (PN BM-1, rev 1-6-20), Drawing 5A
//     "Power Distribution Diagram Dual Alternator"
//   - N721NE POH Rev 1.10, sections 8.8 and 9.9
//   - EFII System32 Installation Instructions (rev 6/19), breaker table
//   - EarthX published ratings for the ETX-900, ETX-680C and EBBS
//
// How the airplane is wired, as modelled here:
//   - Main alternator and Battery 1 share the BAT1/ALT terminal. That terminal is the
//     only feed for the main bus.
//   - Backup alternator (MZ-30L) and Battery 2 share the BAT2 terminal. That side can
//     feed the essential bus but never the main bus.
//   - The essential bus takes power through diodes from whichever side is higher.
//   - Emergency Power adds a second, direct path from both sides to the essential bus.

/// Fixed ratings. Change these only if the airplane's equipment changes.
enum Ratings {
    static let mainAlternatorA = 60.0          // Plane Power AL12-EI60
    static let backupAlternatorA = 30.0        // Monkworkz MZ-30L at 1,800 RPM and above
    static let backupAlternatorLowRPMA = 15.0  // MZ-30L near 900 to 1,000 RPM
    static let continuousFraction = 0.8        // plan on 80% of an alternator's rating
    static let mainBusMaxA = 40.0              // Bus Manager MBUS output limit
    static let essentialBusMaxA = 30.0         // Bus Manager EBUS output limit
    static let ebbsMaxContinuousA = 8.0        // EarthX EBBS output limit
    static let miniXMinutes = 30.0             // GRT Mini-X internal battery

    static let battery1RatedAh = 15.6          // EarthX ETX-900
    static let battery2RatedAh = 12.4          // EarthX ETX-680C
    static let ebbsRatedAh = 8.0               // EarthX EBBS

    // Essential bus breakers from the System32 manual. Breakers are upper limits,
    // not the real draw, so their sum is a worst case.
    static let ecuBreakerA = 5.0               // two ECUs, both powered all the time
    static let ignitionBreakerA = 15.0         // coil packs and injector power
    static let fuelPumpBreakerA = 10.0         // two pumps, only one runs at a time
    static let essentialBreakerCeilingA = 2 * ecuBreakerA + ignitionBreakerA + fuelPumpBreakerA

    // Planned draws for the avionics on the EBBS, from the VP-X load plan.
    static let ebbsPlannedLoads: [(name: String, amps: Double)] = [
        ("Left HXr and AHRS", 3.6),
        ("PMA8000BT audio panel", 2.5),
        ("GTX-330 transponder", 1.5),
        ("SL-30 nav", 0.6),
        ("SL-30 com (receiving)", 0.3),
    ]
    static let ebbsPlannedLoadA = 8.5
}

/// Values the owner can adjust in Settings.
struct ElectricalConfig: Equatable {
    var usableFraction = 0.80
    var essentialLoadA = Ratings.essentialBreakerCeilingA
    var essentialLoadIsMeasured = false
    var ebbsLoadA = Ratings.ebbsPlannedLoadA

    var battery1UsableAh: Double { Ratings.battery1RatedAh * usableFraction }
    var battery2UsableAh: Double { Ratings.battery2RatedAh * usableFraction }
    var ebbsUsableAh: Double { Ratings.ebbsRatedAh * usableFraction }
}

/// What the pilot sets on the main screen.
struct ElectricalInputs: Equatable {
    var mainAltOK = true
    var backupAltOK = true
    var battery1OK = true
    var battery2OK = true
    var emergencyPower = false
    var lowRPM = false
    var mainBusLoadA = 15.0

    var backupAltLimitA: Double {
        guard backupAltOK else { return 0 }
        return lowRPM ? Ratings.backupAlternatorLowRPMA : Ratings.backupAlternatorA
    }
}

/// Who is supplying how many amps at one moment.
struct Flows: Equatable {
    var mainBusPowered = false
    var mainFromAlt = 0.0
    var mainFromBattery1 = 0.0
    var essentialFromMainAlt = 0.0
    var essentialFromBackupAlt = 0.0
    var essentialFromBattery1 = 0.0
    var essentialFromBattery2 = 0.0
    /// Amps nothing can supply while no source at all is connected. The engine has no power.
    var essentialShortfall = 0.0
    /// Amps the set load is above what a lone alternator can give, with no battery to help.
    /// The bus is still powered, but the alternator is at or past its limit.
    var essentialOverload = 0.0

    var battery1Out: Double { mainFromBattery1 + essentialFromBattery1 }
    var battery2Out: Double { essentialFromBattery2 }
    var mainAltOut: Double { mainFromAlt + essentialFromMainAlt }
    var essentialPowered: Bool { essentialShortfall < 0.01 }
    /// The BAT1/ALT side is feeding the essential bus (through D1).
    var sideAFeedsEssential: Bool { essentialFromMainAlt + essentialFromBattery1 > 0.01 }
    /// The BAT2 side is feeding the essential bus (through D2).
    var sideBFeedsEssential: Bool { essentialFromBackupAlt + essentialFromBattery2 > 0.01 }
}

enum BatteryState: Equatable {
    case failed
    case charging
    case standby           // connected, not charging, not supplying
    case discharging(amps: Double)
}

enum EBBSState: Equatable {
    case notArmed          // Emergency Power is off
    case armed             // Emergency Power is on, main bus still powered
    case supplying         // Emergency Power is on and the main bus is dead
}

struct Advisory: Equatable, Identifiable {
    enum Level { case info, caution, warning }
    var level: Level
    var text: String
    var id: String { text }
}

struct ElectricalResult: Equatable {
    var now = Flows()
    /// Minutes until the main bus loses power. nil means it is sustained. 0 means dead now.
    var mainBusLostAtMin: Double?
    /// Minutes until the essential bus (the engine) loses power. nil means sustained.
    var engineLostAtMin: Double?
    /// Minutes until the essential bus is left on an alternator that cannot meet the set load,
    /// with no battery left to help. nil means that never happens. 0 means it is the case now.
    var essentialOverloadAtMin: Double?
    /// Engine time if every main bus load were switched off. nil means sustained.
    var engineLostIfMainShedMin: Double?
    var battery1EmptyAtMin: Double?
    var battery2EmptyAtMin: Double?
    var battery1State = BatteryState.standby
    var battery2State = BatteryState.standby
    var ebbsState = EBBSState.notArmed
    /// How long the EBBS runs its avionics once it takes over.
    var ebbsLifeMin = 0.0
    var advisories: [Advisory] = []
}

enum PowerModel {
    /// Longest time the estimate looks ahead.
    static let horizonMin = 600.0
    private static let stepMin = 0.1

    /// Who supplies what, given which batteries still have charge.
    static func flows(_ inputs: ElectricalInputs, _ config: ElectricalConfig,
                      battery1HasCharge: Bool, battery2HasCharge: Bool) -> Flows {
        var f = Flows()
        let b1 = inputs.battery1OK && battery1HasCharge
        let b2 = inputs.battery2OK && battery2HasCharge
        var mainAlt = inputs.mainAltOK ? Ratings.mainAlternatorA : 0
        var backupAlt = inputs.backupAltLimitA

        // Main bus: fed only from the BAT1/ALT side.
        f.mainBusPowered = inputs.mainAltOK || b1
        if f.mainBusPowered {
            f.mainFromAlt = min(inputs.mainBusLoadA, mainAlt)
            mainAlt -= f.mainFromAlt
            f.mainFromBattery1 = inputs.mainBusLoadA - f.mainFromAlt
        }

        // Essential bus: alternators first, then Battery 2, then Battery 1.
        // Battery 1 is the one loaded by the main bus, so it sits at the lower voltage
        // and Battery 2 picks up the essential bus first.
        var need = config.essentialLoadA
        f.essentialFromMainAlt = min(need, mainAlt)
        need -= f.essentialFromMainAlt
        f.essentialFromBackupAlt = min(need, backupAlt)
        backupAlt -= f.essentialFromBackupAlt
        need -= f.essentialFromBackupAlt
        if need > 0, b2 {
            f.essentialFromBattery2 = need
            need = 0
        }
        if need > 0, b1 {
            f.essentialFromBattery1 = need
            need = 0
        }
        if need > 0, f.essentialFromMainAlt + f.essentialFromBackupAlt > 0.01 {
            // An alternator is still connected. It powers the bus but cannot meet the set load.
            f.essentialOverload = need
        } else {
            f.essentialShortfall = need
        }
        return f
    }

    static func evaluate(_ inputs: ElectricalInputs, _ config: ElectricalConfig) -> ElectricalResult {
        var r = simulate(inputs, config)

        if r.engineLostAtMin != nil, inputs.mainBusLoadA > 0 {
            var shed = inputs
            shed.mainBusLoadA = 0
            r.engineLostIfMainShedMin = simulate(shed, config).engineLostAtMin
        } else {
            r.engineLostIfMainShedMin = r.engineLostAtMin
        }

        r.battery1State = batteryState(ok: inputs.battery1OK, out: r.now.battery1Out,
                                       charging: inputs.mainAltOK)
        r.battery2State = batteryState(ok: inputs.battery2OK, out: r.now.battery2Out,
                                       charging: inputs.backupAltOK)

        if !inputs.emergencyPower {
            r.ebbsState = .notArmed
        } else {
            r.ebbsState = r.now.mainBusPowered ? .armed : .supplying
        }
        r.ebbsLifeMin = config.ebbsLoadA > 0 ? config.ebbsUsableAh / config.ebbsLoadA * 60 : horizonMin

        r.advisories = advisories(inputs, config, r)
        return r
    }

    private static func batteryState(ok: Bool, out: Double, charging: Bool) -> BatteryState {
        if !ok { return .failed }
        if out > 0.01 { return .discharging(amps: out) }
        return charging ? .charging : .standby
    }

    /// Steps forward in time, draining the batteries, until something runs out.
    private static func simulate(_ inputs: ElectricalInputs, _ config: ElectricalConfig) -> ElectricalResult {
        var r = ElectricalResult()
        var left1 = inputs.battery1OK ? config.battery1UsableAh : 0
        var left2 = inputs.battery2OK ? config.battery2UsableAh : 0
        let stepHours = stepMin / 60
        var t = 0.0
        var first = true

        while t < horizonMin {
            let f = flows(inputs, config, battery1HasCharge: left1 > 1e-9, battery2HasCharge: left2 > 1e-9)
            if first {
                r.now = f
                first = false
            }
            if !f.mainBusPowered, r.mainBusLostAtMin == nil {
                r.mainBusLostAtMin = t
            }
            if !f.essentialPowered {
                r.engineLostAtMin = t
                break
            }
            if f.essentialOverload > 0.01, r.essentialOverloadAtMin == nil {
                r.essentialOverloadAtMin = t
            }
            if f.battery1Out < 0.01, f.battery2Out < 0.01 {
                break   // nothing is draining, so this state holds
            }
            if f.battery1Out > 0 {
                left1 -= f.battery1Out * stepHours
                if left1 <= 1e-9, r.battery1EmptyAtMin == nil { r.battery1EmptyAtMin = t + stepMin }
            }
            if f.battery2Out > 0 {
                left2 -= f.battery2Out * stepHours
                if left2 <= 1e-9, r.battery2EmptyAtMin == nil { r.battery2EmptyAtMin = t + stepMin }
            }
            t += stepMin
        }
        return r
    }

    private static func advisories(_ inputs: ElectricalInputs, _ config: ElectricalConfig,
                                   _ r: ElectricalResult) -> [Advisory] {
        var a: [Advisory] = []
        let f = r.now
        let bothAltsOut = !inputs.mainAltOK && !inputs.backupAltOK

        if !f.essentialPowered {
            a.append(Advisory(level: .warning, text:
                "No source can carry the essential bus. The engine has no electrical power in this state."))
        }
        if let at = r.essentialOverloadAtMin, at > 0 {
            a.append(Advisory(level: .caution, text:
                "When the batteries are empty, in about \(Self.durationText(at)), the essential bus will be on the alternator alone "
                + "and the set load is above what it can give."))
        }
        if f.essentialOverload > 0.01 {
            let limit = f.essentialFromMainAlt + f.essentialFromBackupAlt
            a.append(Advisory(level: .warning, text:
                "The essential bus is on an alternator alone, with no battery behind it. "
                + "The set load of \(Self.ampsText(config.essentialLoadA)) is above the \(Self.ampsText(limit)) it can give"
                + (inputs.lowRPM && inputs.backupAltOK && !inputs.mainAltOK ? " at low RPM" : "")
                + ". If the real load is that high, expect low voltage and the engine may not keep running."
                + (inputs.lowRPM && inputs.backupAltOK ? " Keep RPM at 1,800 or above." : "")))
        }
        if !f.mainBusPowered {
            a.append(Advisory(level: .warning, text:
                "Main bus is dead: no avionics, lights, flaps, trim or autopilot from the VP-X. "
                + "The Mini-X runs about \(Int(Ratings.miniXMinutes)) minutes on its own battery."))
            if !inputs.emergencyPower {
                a.append(Advisory(level: .caution, text:
                    "EBBS is not on. Select EMERGENCY POWER to bring it on for the left HXr, SL-30, audio panel and transponder."))
            }
        }
        if bothAltsOut, f.essentialPowered {
            a.append(Advisory(level: .warning, text:
                "Both charging sources are out. The engine is running on battery power only. Land as soon as practical."))
            if let shed = r.engineLostIfMainShedMin, let nowTime = r.engineLostAtMin, shed > nowTime + 1 {
                a.append(Advisory(level: .info, text:
                    "With every main bus load off, engine power lasts about \(Self.durationText(shed))."))
            }
        }
        if !inputs.mainAltOK, inputs.backupAltOK, f.mainBusPowered {
            a.append(Advisory(level: .caution, text:
                "Battery 1 is the only source for the main bus. The backup alternator cannot reach the main bus. "
                + "Shed main bus loads on the VP-X page to stretch Battery 1."))
        }
        if !inputs.mainAltOK, inputs.backupAltOK, f.essentialFromBattery2 + f.essentialFromBattery1 > 0.01 {
            a.append(Advisory(level: .caution, text:
                "The essential bus needs more than the backup alternator's \(Int(inputs.backupAltLimitA)) A limit"
                + (inputs.lowRPM ? " at low RPM" : "")
                + ", so a battery is making up the difference."))
        }
        if inputs.backupAltOK, inputs.lowRPM {
            a.append(Advisory(level: .info, text:
                "Backup alternator is limited to about \(Int(Ratings.backupAlternatorLowRPMA)) A near 900 to 1,000 RPM. "
                + "It gives \(Int(Ratings.backupAlternatorA)) A at 1,800 RPM and above."))
        }
        if inputs.mainAltOK, !inputs.battery1OK {
            a.append(Advisory(level: .caution, text:
                "Main bus is on the main alternator with no battery behind it. "
                + "If the alternator trips, the main bus drops at once."))
        }
        if inputs.mainAltOK, !inputs.backupAltOK, inputs.battery2OK {
            a.append(Advisory(level: .info, text:
                "Battery 2 is not being charged. It stays connected as a reserve for the essential bus."))
        }
        if inputs.mainAltOK, f.battery1Out > 0.01 {
            a.append(Advisory(level: .caution, text:
                "Total load is more than the main alternator's \(Int(Ratings.mainAlternatorA)) A. Battery 1 is making up the difference."))
        } else if inputs.mainAltOK,
                  f.mainAltOut > Ratings.mainAlternatorA * Ratings.continuousFraction {
            a.append(Advisory(level: .info, text:
                "Main alternator load is above 80% of its rating (\(Int(Ratings.mainAlternatorA * Ratings.continuousFraction)) A)."))
        }
        if inputs.emergencyPower {
            a.append(Advisory(level: .info, text:
                "Emergency Power is drawn as built per the Bus Manager manual: a direct path from both batteries to the essential bus, "
                + "with the main bus left as it is. Not yet confirmed on N721NE."))
        }
        if !config.essentialLoadIsMeasured {
            a.append(Advisory(level: .info, text:
                "Essential bus load is set to \(Self.ampsText(config.essentialLoadA)), the sum of the breaker ratings. "
                + "The real draw is lower, so real times are longer. Enter a measured value in Settings."))
        }
        return a
    }

    // MARK: - Text helpers

    static func durationText(_ minutes: Double) -> String {
        if minutes >= horizonMin { return "more than \(Int(horizonMin / 60)) h" }
        let m = Int(minutes.rounded(.down))
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h \(String(format: "%02d", m % 60)) min"
    }

    static func ampsText(_ amps: Double) -> String {
        if abs(amps - amps.rounded()) < 0.05 { return "\(Int(amps.rounded())) A" }
        return String(format: "%.1f A", amps)
    }
}
