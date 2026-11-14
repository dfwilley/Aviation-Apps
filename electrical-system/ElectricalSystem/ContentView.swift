import SwiftUI

struct ContentView: View {
    @State private var inputs = ElectricalInputs()
    @State private var showSettings = false
    @State private var showArrange = false

    // Timer. It starts with the first failed alternator or battery and tracks charge drawn since then.
    @State private var timerStart: Date?
    @State private var lastTick: Date?
    @State private var now = Date()
    @State private var flashOn = false
    @State private var battery1UsedAh = 0.0
    @State private var battery2UsedAh = 0.0
    @State private var ebbsUsedAh = 0.0
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Layout of the data boxes: their order, and which are shown small.
    @AppStorage("boxOrder") private var boxOrderRaw = DataBox.defaultOrderRaw
    @AppStorage("boxesCompact") private var boxesCompactRaw = ""

    @AppStorage("usablePercent") private var usablePercent = 80.0
    @AppStorage("essentialLoadA") private var essentialLoadA = Ratings.essentialBreakerCeilingA
    @AppStorage("essentialLoadIsMeasured") private var essentialLoadIsMeasured = false
    @AppStorage("ebbsLoadA") private var ebbsLoadA = Ratings.ebbsPlannedLoadA

    private var config: ElectricalConfig {
        var c = ElectricalConfig()
        c.usableFraction = usablePercent / 100
        c.essentialLoadA = essentialLoadA
        c.essentialLoadIsMeasured = essentialLoadIsMeasured
        c.ebbsLoadA = ebbsLoadA
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

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    DiagramView(inputs: $inputs, result: result)
                        .padding(8)
                        .background(Theme.background)
                    Text("Touch an alternator, a battery or the EMER box to turn it off or on.")
                        .font(.caption)
                        .foregroundColor(Theme.dim)
                    legend
                    rpmControl
                    if timerStart != nil {
                        timerBanner(result)
                    }
                    ForEach(DataBox.order(from: boxOrderRaw)) { box in
                        boxView(box, result, config)
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
            .onChange(of: inputs) { _ in syncTimer() }
        }
    }

    // MARK: - Timer

    /// Starts the timer on the first failure and clears it when everything is back on.
    private func syncTimer() {
        if anyFailure {
            if timerStart == nil {
                let t = Date()
                timerStart = t
                lastTick = t
                now = t
            }
        } else {
            timerStart = nil
            lastTick = nil
            battery1UsedAh = 0
            battery2UsedAh = 0
            ebbsUsedAh = 0
        }
        UIApplication.shared.isIdleTimerDisabled = timerStart != nil
    }

    /// Runs once a second. Uses the real clock, so time spent with the phone locked still counts.
    private func tick(_ date: Date) {
        flashOn.toggle()
        guard timerStart != nil, let last = lastTick else { return }
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
    }

    /// The limits that are counting down, with minutes left.
    private func countdowns(_ r: ElectricalResult) -> [(name: String, minutes: Double)] {
        var list: [(name: String, minutes: Double)] = []
        if let t = r.mainBusLostAtMin, t > 0 { list.append(("Main bus", t)) }
        if let t = r.engineLostAtMin, t > 0 { list.append(("Engine power", t)) }
        if let t = r.essentialOverloadAtMin, t > 0 { list.append(("Battery help for the engine", t)) }
        if r.ebbsState == .supplying, r.ebbsLifeMin > 0 { list.append(("EBBS avionics", r.ebbsLifeMin)) }
        return list
    }

    private func expiring(_ minutes: Double?) -> Bool {
        guard let minutes else { return false }
        return minutes > 0 && minutes <= PowerModel.expiryWarningMin
    }

    private func timerBanner(_ r: ElectricalResult) -> some View {
        let soon = countdowns(r).filter { expiring($0.minutes) }
        let elapsed = max(0, Int(now.timeIntervalSince(timerStart ?? now)))
        let lit = !soon.isEmpty && flashOn
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Since first failure")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%d:%02d:%02d", elapsed / 3600, elapsed / 60 % 60, elapsed % 60))
                    .font(.title2.weight(.bold).monospacedDigit())
            }
            ForEach(soon, id: \.name) { item in
                Text("\(item.name): \(PowerModel.durationText(item.minutes)) left")
                    .font(.headline)
            }
            if soon.isEmpty {
                Text("Times below count down from full batteries at the moment of the first failure.")
                    .font(.caption)
                    .foregroundColor(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .foregroundColor(lit ? .black : .white)
        .background(lit ? Theme.fail : Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(soon.isEmpty ? Theme.battery : Theme.fail, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data boxes

    private func isCompact(_ box: DataBox) -> Bool {
        DataBox.compactSet(from: boxesCompactRaw).contains(box)
    }

    @ViewBuilder
    private func boxView(_ box: DataBox, _ result: ElectricalResult, _ config: ElectricalConfig) -> some View {
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
                    + (config.essentialLoadIsMeasured ? " measured" : " breaker total"),
                    source: essentialSource(result), time: essentialTime(result),
                    timeColor: result.essentialOverloadAtMin != nil ? Theme.battery
                        : timeColor(result.engineLostAtMin),
                    flash: expiring(result.engineLostAtMin) || expiring(result.essentialOverloadAtMin),
                    compact: compact)
        case .batteries:
            batteriesCard(result, config, compact: compact)
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

    private func batteriesCard(_ r: ElectricalResult, _ c: ElectricalConfig, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Text("BATTERIES").font(.caption.weight(.bold)).foregroundColor(Theme.dim)
            batteryRow(name: "Battery 1 (main)", model: "EarthX ETX-900", rated: Ratings.battery1RatedAh,
                       usable: c.battery1UsableAh, left: c.battery1LeftAh,
                       status: batteryStatus(r.battery1State, emptyAt: r.battery1EmptyAtMin),
                       color: batteryColor(r.battery1State), compact: compact)
            if !compact { Divider().background(Theme.cardEdge) }
            batteryRow(name: "Battery 2 (alternate)", model: "EarthX ETX-680C", rated: Ratings.battery2RatedAh,
                       usable: c.battery2UsableAh, left: c.battery2LeftAh,
                       status: batteryStatus(r.battery2State, emptyAt: r.battery2EmptyAtMin),
                       color: batteryColor(r.battery2State), compact: compact)
            if !compact { Divider().background(Theme.cardEdge) }
            batteryRow(name: "Backup battery", model: "EarthX EBBS", rated: Ratings.ebbsRatedAh,
                       usable: c.ebbsUsableAh, left: c.ebbsLeftAh,
                       status: ebbsStatus(r, c), color: ebbsColor(r), compact: compact)
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
                            status: String, color: Color, compact: Bool) -> some View {
        // Once the timer has drawn some charge, show what is left instead of the starting figure.
        let drawn = usable - left > 0.05
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
        }
    }

    private func batteryStatus(_ state: BatteryState, emptyAt: Double?) -> String {
        switch state {
        case .failed: return "Failed"
        case .charging: return "Charging"
        case .standby: return "Standing by, not being charged"
        case .empty: return "Empty"
        case .discharging(let amps):
            var text = "Supplying \(PowerModel.ampsText(amps))"
            if let emptyAt { text += " · empty in \(PowerModel.durationText(emptyAt))" }
            return text
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
        case .supplying: return "Running the left HXr, SL-30, audio panel and transponder · \(life)"
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
