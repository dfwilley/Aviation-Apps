import SwiftUI

struct ContentView: View {
    @State private var inputs = ElectricalInputs()
    @State private var showSettings = false
    @State private var showArrange = false

    // Battery drain. It starts with the first failed alternator or battery and tracks charge drawn since then.
    // `lastTick` is set while that tracking is running.
    @State private var lastTick: Date?
    @State private var now = Date()
    @State private var flashOn = false
    @State private var battery1UsedAh = 0.0
    @State private var battery2UsedAh = 0.0
    @State private var ebbsUsedAh = 0.0
    // The moment each countdown reaches zero, so the countdowns tick evenly with the clock.
    @State private var battery1Deadline: Date?
    @State private var battery2Deadline: Date?
    @State private var ebbsDeadline: Date?
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Layout of the data boxes: their order, and which are shown small.
    @AppStorage("boxOrder") private var boxOrderRaw = DataBox.defaultOrderRaw
    @AppStorage("boxesCompact") private var boxesCompactRaw = ""

    @AppStorage("usablePercent") private var usablePercent = 80.0
    @AppStorage("essentialLoadA") private var essentialLoadA = Ratings.essentialDefaultLoadA
    @AppStorage("essentialLoadIsMeasured") private var essentialLoadIsMeasured = false
    /// Amps typed in Settings for each item on the EBBS. Their total is the EBBS load.
    @AppStorage("ebbsItemAmps") private var ebbsItemAmpsRaw = ""

    private var config: ElectricalConfig {
        var c = ElectricalConfig()
        c.usableFraction = usablePercent / 100
        c.essentialLoadA = essentialLoadA
        c.essentialLoadIsMeasured = essentialLoadIsMeasured
        c.ebbsLoadA = EBBSLoad.itemAmps(from: ebbsItemAmpsRaw).reduce(0, +)
        c.battery1UsedAh = battery1UsedAh
        c.battery2UsedAh = battery2UsedAh
        c.ebbsUsedAh = ebbsUsedAh
        return c
    }

    private var anyFailure: Bool {
        !(inputs.mainAltOK && inputs.backupAltOK && inputs.battery1OK && inputs.battery2OK)
    }

    var body: some View {
        let config = self.config
        let result = PowerModel.evaluate(inputs, config)
        let left = countdowns(result)

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    DiagramView(inputs: $inputs, result: result,
                                battery1Timer: boxTimer(left.battery1),
                                battery2Timer: boxTimer(left.battery2),
                                ebbsTimer: boxTimer(left.ebbs)
                                    ?? DiagramView.BoxTimer(text: "Lasts " + PowerModel.durationText(result.ebbsLifeMin),
                                                            running: false),
                                flashOn: flashOn)
                        .padding(8)
                        .background(Theme.background)
                    Text("Touch an alternator, a battery or the EMER box to turn it off or on.")
                        .font(.caption)
                        .foregroundColor(Theme.dim)
                    legend
                    rpmControl
                    ForEach(DataBox.order(from: boxOrderRaw)) { box in
                        boxView(box, result, config, left)
                            .draggable(box.rawValue)
                            .dropDestination(for: String.self) { items, _ in
                                moveBox(items.first, before: box)
                            }
                    }
                    Text("Hold a box and drag it to move it. Use the arrange button at the top to resize boxes.")
                        .font(.caption)
                        .foregroundColor(Theme.dim)
                    Text("Reference aid only. The POH, the checklist and what the airplane is showing you come first. "
                         + "Times are estimates from rated capacity and the loads set here.")
                        .font(.footnote)
                        .foregroundColor(Theme.dim)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("N721NE Electrical")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") { inputs = ElectricalInputs() }
                        .disabled(inputs == ElectricalInputs())
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showArrange = true } label: {
                        Image(systemName: "rectangle.3.group")
                    }
                    .accessibilityLabel("Arrange boxes")
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showArrange) {
                ArrangeView()
                    .preferredColorScheme(.dark)
            }
            .onReceive(clock) { tick($0) }
            .onChange(of: inputs) { _ in syncTracking() }
        }
    }

    // MARK: - Countdowns

    /// Starts tracking battery drain on the first failure and clears it when everything is back on.
    private func syncTracking() {
        if anyFailure {
            if lastTick == nil {
                let t = Date()
                lastTick = t
                now = t
            }
        } else {
            lastTick = nil
            battery1UsedAh = 0
            battery2UsedAh = 0
            ebbsUsedAh = 0
        }
        UIApplication.shared.isIdleTimerDisabled = lastTick != nil
        syncDeadlines()
    }

    /// Runs once a second. Uses the real clock, so time spent with the phone locked still counts.
    private func tick(_ date: Date) {
        flashOn.toggle()
        guard let last = lastTick else {
            now = date
            return
        }
        var remaining = date.timeIntervalSince(last)
        // Work through a long gap in short steps so a battery that runs out part way is handled.
        while remaining > 0 {
            let step = min(remaining, 30)
            let c = config
            let r = PowerModel.evaluate(inputs, c)
            let hours = step / 3600
            battery1UsedAh = min(c.battery1UsableAh, battery1UsedAh + r.now.battery1Out * hours)
            battery2UsedAh = min(c.battery2UsableAh, battery2UsedAh + r.now.battery2Out * hours)
            if r.ebbsState == .supplying {
                ebbsUsedAh = min(c.ebbsUsableAh, ebbsUsedAh + c.ebbsLoadA * hours)
            }
            remaining -= step
        }
        lastTick = date
        now = date
        syncDeadlines()
    }

    /// Seconds left on each battery's countdown. nil means that battery is not running down.
    private struct Countdowns {
        var battery1: Double?
        var battery2: Double?
        var ebbs: Double?
    }

    private func countdowns(_ r: ElectricalResult) -> Countdowns {
        Countdowns(battery1: secondsLeft(r.battery1EmptyAtMin, battery1Deadline),
                   battery2: secondsLeft(r.battery2EmptyAtMin, battery2Deadline),
                   ebbs: r.ebbsState == .supplying ? secondsLeft(r.ebbsLifeMin, ebbsDeadline) : nil)
    }

    /// Turns the model's estimate (in minutes, at the loads set now) into seconds for a countdown.
    /// The estimate moves in small jumps, so between changes the countdown follows the clock to
    /// tick once a second. A real change, such as a new load, moves it straight to the new estimate.
    private func secondsLeft(_ minutes: Double?, _ deadline: Date?) -> Double? {
        guard let minutes, minutes > 0 else { return nil }
        let estimate = minutes * 60
        guard lastTick != nil, minutes < PowerModel.horizonMin, let deadline else { return estimate }
        let ticking = deadline.timeIntervalSince(now)
        return abs(ticking - estimate) <= 8 ? max(0, ticking) : estimate
    }

    private func syncDeadlines() {
        let left = countdowns(PowerModel.evaluate(inputs, config))
        battery1Deadline = left.battery1.map { now.addingTimeInterval($0) }
        battery2Deadline = left.battery2.map { now.addingTimeInterval($0) }
        ebbsDeadline = left.ebbs.map { now.addingTimeInterval($0) }
    }

    private func expiring(_ minutes: Double?) -> Bool {
        guard let minutes else { return false }
        return minutes > 0 && minutes <= PowerModel.expiryWarningMin
    }

    private func expiring(seconds: Double?) -> Bool {
        guard let seconds else { return false }
        return seconds <= PowerModel.expiryWarningMin * 60
    }

    private func boxTimer(_ seconds: Double?) -> DiagramView.BoxTimer? {
        guard let seconds else { return nil }
        return DiagramView.BoxTimer(text: PowerModel.countdownText(seconds), urgent: expiring(seconds: seconds))
    }

    // MARK: - Data boxes

    private func isCompact(_ box: DataBox) -> Bool {
        DataBox.compactSet(from: boxesCompactRaw).contains(box)
    }

    @ViewBuilder
    private func boxView(_ box: DataBox, _ result: ElectricalResult, _ config: ElectricalConfig,
                         _ left: Countdowns) -> some View {
        let compact = isCompact(box)
        switch box {
        case .load:
            loadControl(compact: compact)
        case .mainBus:
            busCard(title: "MAIN BUS", detail: "Avionics, lights, flaps, trim, autopilot",
                    source: mainBusSource(result), time: mainBusTime(result),
                    timeColor: timeColor(result.mainBusLostAtMin),
                    flash: expiring(result.mainBusLostAtMin), compact: compact)
        case .essentialBus:
            busCard(title: "ESSENTIAL BUS", detail: "Engine: both ECUs, ignition, one fuel pump · "
                    + PowerModel.ampsText(config.essentialLoadA)
                    + (config.essentialLoadIsMeasured ? " measured"
                        : (config.essentialLoadIsBreakerTotal ? " breaker total" : " set in Settings")),
                    source: essentialSource(result), time: essentialTime(result),
                    timeColor: result.essentialOverloadAtMin != nil ? Theme.battery
                        : timeColor(result.engineLostAtMin),
                    flash: expiring(result.engineLostAtMin) || expiring(result.essentialOverloadAtMin),
                    compact: compact)
        case .batteries:
            batteriesCard(result, config, left, compact: compact)
        case .notes:
            notesCard(result, compact: compact)
        }
    }

    /// Puts the dragged box in front of the box it was dropped on.
    private func moveBox(_ raw: String?, before target: DataBox) -> Bool {
        guard let raw, let moved = DataBox(rawValue: raw), moved != target else { return false }
        var order = DataBox.order(from: boxOrderRaw)
        order.removeAll { $0 == moved }
        let index = order.firstIndex(of: target) ?? order.count
        order.insert(moved, at: index)
        boxOrderRaw = DataBox.raw(order)
        return true
    }

    // MARK: - Controls

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Theme.alt, "Alternator")
            legendItem(Theme.battery, "Battery")
            legendItem(Theme.off, "No current")
            legendItem(Theme.fail, "Failed")
        }
        .font(.caption)
        .foregroundColor(Theme.dim)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 16, height: 5)
            Text(text)
        }
    }

    private var rpmControl: some View {
        Picker("Engine RPM", selection: $inputs.lowRPM) {
            Text("1,800 RPM and above").tag(false)
            Text("Near 1,000 RPM").tag(true)
        }
        .pickerStyle(.segmented)
    }

    private func loadControl(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Main bus load")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(PowerModel.ampsText(inputs.mainBusLoadA))
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            Slider(value: $inputs.mainBusLoadA, in: 0...Ratings.mainBusMaxA, step: 1)
            if !compact {
                Text("Set this to the total amps on the VP-X page.")
                    .font(.caption)
                    .foregroundColor(Theme.dim)
            }
        }
        .card()
    }

    // MARK: - Results

    private func busCard(title: String, detail: String, source: String, time: String, timeColor: Color,
                         flash: Bool, compact: Bool) -> some View {
        let lit = flash && flashOn
        return VStack(alignment: .leading, spacing: 6) {
            if compact {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.caption.weight(.bold)).foregroundColor(lit ? .black : Theme.dim)
                    Spacer()
                    Text(time)
                        .font(.headline.weight(.bold))
                        .foregroundColor(lit ? .black : timeColor)
                }
            } else {
                Text(title).font(.caption.weight(.bold)).foregroundColor(lit ? .black : Theme.dim)
                Text(time)
                    .font(.title2.weight(.bold))
                    .foregroundColor(lit ? .black : timeColor)
                Text(source).font(.subheadline).foregroundColor(lit ? .black : .white)
                Text(detail).font(.caption).foregroundColor(lit ? .black : Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(lit ? Theme.fail : Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(flash ? Theme.fail : Theme.cardEdge, lineWidth: flash ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func timeColor(_ lostAt: Double?) -> Color {
        guard let lostAt else { return Theme.alt }
        return lostAt <= 0 ? Theme.fail : Theme.battery
    }

    private func mainBusSource(_ r: ElectricalResult) -> String {
        if !r.now.mainBusPowered { return "No source. Main alternator and Battery 1 are both out." }
        if r.now.mainFromBattery1 > 0.01 || !inputs.mainAltOK {
            return "Fed by Battery 1 at \(PowerModel.ampsText(r.now.mainFromBattery1))"
        }
        return "Fed by the main alternator"
    }

    private func mainBusTime(_ r: ElectricalResult) -> String {
        guard let t = r.mainBusLostAtMin else { return "Sustained" }
        return t <= 0 ? "No power" : PowerModel.durationText(t) + " left"
    }

    private func essentialSource(_ r: ElectricalResult) -> String {
        let f = r.now
        if !f.essentialPowered { return "No source can carry it." }
        var parts: [String] = []
        if f.essentialFromMainAlt > 0.01 { parts.append("main alternator") }
        if f.essentialFromBackupAlt > 0.01 { parts.append("backup alternator") }
        if f.essentialFromBattery2 > 0.01 { parts.append("Battery 2 (\(PowerModel.ampsText(f.essentialFromBattery2)))") }
        if f.essentialFromBattery1 > 0.01 { parts.append("Battery 1 (\(PowerModel.ampsText(f.essentialFromBattery1)))") }
        var text = "Fed by " + parts.joined(separator: " and ")
        if f.essentialOverload > 0.01 { text += " alone, with no battery behind it" }
        if inputs.mainAltOK, inputs.backupAltOK, f.essentialFromMainAlt > 0.01 {
            text += ". Backup alternator is ready behind it."
        }
        return text
    }

    private func essentialTime(_ r: ElectricalResult) -> String {
        guard let t = r.engineLostAtMin else {
            if r.now.essentialOverload > 0.01 { return "Powered, over the limit" }
            if let at = r.essentialOverloadAtMin { return PowerModel.durationText(at) + " of battery help" }
            return "Sustained"
        }
        return t <= 0 ? "No power" : PowerModel.durationText(t) + " left"
    }

    private func batteriesCard(_ r: ElectricalResult, _ c: ElectricalConfig, _ left: Countdowns,
                               compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Text("BATTERIES").font(.caption.weight(.bold)).foregroundColor(Theme.dim)
            batteryRow(name: "Battery 1 (main)", model: "EarthX ETX-900", rated: Ratings.battery1RatedAh,
                       usable: c.battery1UsableAh, left: c.battery1LeftAh,
                       status: batteryStatus(r.battery1State), color: batteryColor(r.battery1State),
                       countdown: left.battery1, countdownID: "battery1Countdown", compact: compact)
            if !compact { Divider().background(Theme.cardEdge) }
            batteryRow(name: "Battery 2 (alternate)", model: "EarthX ETX-680C", rated: Ratings.battery2RatedAh,
                       usable: c.battery2UsableAh, left: c.battery2LeftAh,
                       status: batteryStatus(r.battery2State), color: batteryColor(r.battery2State),
                       countdown: left.battery2, countdownID: "battery2Countdown", compact: compact)
            if !compact { Divider().background(Theme.cardEdge) }
            batteryRow(name: "Backup battery", model: "EarthX EBBS", rated: Ratings.ebbsRatedAh,
                       usable: c.ebbsUsableAh, left: c.ebbsLeftAh,
                       status: ebbsStatus(r, c), color: ebbsColor(r),
                       countdown: left.ebbs, countdownID: "ebbsCountdown", compact: compact)
            if !compact {
                Text("Usable figures are \(Int(usablePercent))% of the rated capacity. Change the share in Settings as the batteries age.")
                    .font(.caption)
                    .foregroundColor(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func batteryRow(name: String, model: String, rated: Double, usable: Double, left: Double,
                            status: String, color: Color, countdown: Double?, countdownID: String,
                            compact: Bool) -> some View {
        // Once some charge has been drawn, show what is left instead of the starting figure.
        let drawn = usable - left > 0.05
        let urgent = expiring(seconds: countdown)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f Ah", rated))
                    .font((compact ? Font.subheadline : Font.title3).weight(.bold).monospacedDigit())
            }
            if !compact {
                HStack(alignment: .firstTextBaseline) {
                    Text(model).font(.caption).foregroundColor(Theme.dim)
                    Spacer()
                    Text(drawn ? String(format: "%.1f of %.1f Ah left", left, usable)
                               : String(format: "%.1f Ah usable", usable))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(drawn ? Theme.battery : Theme.dim)
                }
            }
            Text(status).font(.footnote.weight(.medium)).foregroundColor(color)
            if let countdown {
                // Time left on this battery at the loads set now.
                HStack(alignment: .firstTextBaseline) {
                    Text("Time remaining").font(.footnote).foregroundColor(Theme.dim)
                    Spacer()
                    Text(PowerModel.countdownText(countdown))
                        .font((compact ? Font.headline : Font.title2).weight(.bold).monospacedDigit())
                        .foregroundColor(urgent ? (flashOn ? Theme.fail : .white) : Theme.battery)
                        .accessibilityIdentifier(countdownID)
                }
            }
        }
    }

    private func batteryStatus(_ state: BatteryState) -> String {
        switch state {
        case .failed: return "Failed"
        case .charging: return "Charging"
        case .standby: return "Standing by, not being charged"
        case .empty: return "Empty"
        case .discharging(let amps): return "Supplying \(PowerModel.ampsText(amps))"
        }
    }

    private func batteryColor(_ state: BatteryState) -> Color {
        switch state {
        case .failed: return Theme.fail
        case .charging: return Theme.alt
        case .standby: return Theme.dim
        case .empty: return Theme.fail
        case .discharging: return Theme.battery
        }
    }

    private func ebbsStatus(_ r: ElectricalResult, _ c: ElectricalConfig) -> String {
        let life = "\(PowerModel.durationText(r.ebbsLifeMin)) at \(PowerModel.ampsText(c.ebbsLoadA))"
        switch r.ebbsState {
        case .notArmed: return "Not armed. Comes on with Emergency Power. Would last \(life)."
        case .armed: return "Armed. Takes over if the main bus is lost. Would last \(life)."
        case .supplying:
            return "Running the left HXr, SL-30, A210, audio panel and transponder at \(PowerModel.ampsText(c.ebbsLoadA))"
        }
    }

    private func ebbsColor(_ r: ElectricalResult) -> Color {
        switch r.ebbsState {
        case .notArmed: return Theme.dim
        case .armed: return Theme.emergency
        case .supplying: return Theme.battery
        }
    }

    private func notesCard(_ r: ElectricalResult, compact: Bool) -> some View {
        // Small size shows warnings and cautions only.
        let notes = compact ? r.advisories.filter { $0.level != .info } : r.advisories
        return VStack(alignment: .leading, spacing: 10) {
            Text("NOTES").font(.caption.weight(.bold)).foregroundColor(Theme.dim)
            if notes.isEmpty {
                Text(r.advisories.isEmpty ? "Normal. Both alternators are charging and nothing is draining."
                                          : "No warnings or cautions.")
                    .font(.subheadline)
            }
            ForEach(notes) { note in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(note.level))
                        .foregroundColor(noteColor(note.level))
                        .frame(width: 20)
                    Text(note.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func icon(_ level: Advisory.Level) -> String {
        switch level {
        case .info: return "info.circle"
        case .caution: return "exclamationmark.triangle"
        case .warning: return "exclamationmark.octagon.fill"
        }
    }

    private func noteColor(_ level: Advisory.Level) -> Color {
        switch level {
        case .info: return Theme.dim
        case .caution: return Theme.battery
        case .warning: return Theme.fail
        }
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardEdge, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}
