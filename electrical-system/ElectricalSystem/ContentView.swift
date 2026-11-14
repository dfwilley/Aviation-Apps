import SwiftUI

struct ContentView: View {
    @State private var inputs = ElectricalInputs()
    @State private var showSettings = false

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
        return c
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
                    loadControl
                    busCard(title: "MAIN BUS", detail: "Avionics, lights, flaps, trim, autopilot",
                            source: mainBusSource(result), time: mainBusTime(result),
                            timeColor: timeColor(result.mainBusLostAtMin))
                    busCard(title: "ESSENTIAL BUS", detail: "Engine: both ECUs, ignition, one fuel pump · "
                            + PowerModel.ampsText(config.essentialLoadA)
                            + (config.essentialLoadIsMeasured ? " measured" : " breaker total"),
                            source: essentialSource(result), time: essentialTime(result),
                            timeColor: result.essentialOverloadAtMin != nil ? Theme.battery
                                : timeColor(result.engineLostAtMin))
                    batteriesCard(result, config)
                    notesCard(result)
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
                ToolbarItem(placement: .navigationBarTrailing) {
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
        }
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

    private var loadControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Main bus load")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(PowerModel.ampsText(inputs.mainBusLoadA))
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            Slider(value: $inputs.mainBusLoadA, in: 0...Ratings.mainBusMaxA, step: 1)
            Text("Set this to the total amps on the VP-X page.")
                .font(.caption)
                .foregroundColor(Theme.dim)
        }
        .card()
    }

    // MARK: - Results

    private func busCard(title: String, detail: String, source: String, time: String, timeColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundColor(Theme.dim)
            Text(time)
                .font(.title2.weight(.bold))
                .foregroundColor(timeColor)
            Text(source).font(.subheadline)
            Text(detail).font(.caption).foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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

    private func batteriesCard(_ r: ElectricalResult, _ c: ElectricalConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BATTERIES").font(.caption.weight(.bold)).foregroundColor(Theme.dim)
            batteryRow(name: "Battery 1 (main)", model: "EarthX ETX-900", rated: Ratings.battery1RatedAh,
                       usable: c.battery1UsableAh, status: batteryStatus(r.battery1State, emptyAt: r.battery1EmptyAtMin),
                       color: batteryColor(r.battery1State))
            Divider().background(Theme.cardEdge)
            batteryRow(name: "Battery 2 (alternate)", model: "EarthX ETX-680C", rated: Ratings.battery2RatedAh,
                       usable: c.battery2UsableAh, status: batteryStatus(r.battery2State, emptyAt: r.battery2EmptyAtMin),
                       color: batteryColor(r.battery2State))
            Divider().background(Theme.cardEdge)
            batteryRow(name: "Backup battery", model: "EarthX EBBS", rated: Ratings.ebbsRatedAh,
                       usable: c.ebbsUsableAh, status: ebbsStatus(r, c), color: ebbsColor(r))
            Text("Usable figures are \(Int(usablePercent))% of the rated capacity. Change the share in Settings as the batteries age.")
                .font(.caption)
                .foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func batteryRow(name: String, model: String, rated: Double, usable: Double,
                            status: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f Ah", rated))
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            HStack(alignment: .firstTextBaseline) {
                Text(model).font(.caption).foregroundColor(Theme.dim)
                Spacer()
                Text(String(format: "%.1f Ah usable", usable))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Theme.dim)
            }
            Text(status).font(.footnote.weight(.medium)).foregroundColor(color)
        }
    }

    private func batteryStatus(_ state: BatteryState, emptyAt: Double?) -> String {
        switch state {
        case .failed: return "Failed"
        case .charging: return "Charging"
        case .standby: return "Standing by, not being charged"
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

    private func notesCard(_ r: ElectricalResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTES").font(.caption.weight(.bold)).foregroundColor(Theme.dim)
            if r.advisories.isEmpty {
                Text("Normal. Both alternators are charging and nothing is draining.")
                    .font(.subheadline)
            }
            ForEach(r.advisories) { note in
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
