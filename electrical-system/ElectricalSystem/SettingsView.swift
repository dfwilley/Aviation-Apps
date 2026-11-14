import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("usablePercent") private var usablePercent = 80.0
    @AppStorage("essentialLoadA") private var essentialLoadA = Ratings.essentialBreakerCeilingA
    @AppStorage("essentialLoadIsMeasured") private var essentialLoadIsMeasured = false
    /// Amps typed in for each item on the EBBS, in the same order as the planned list.
    @AppStorage("ebbsItemAmps") private var ebbsItemAmpsRaw = ""
    @State private var ebbsFields: [String] = []
    @FocusState private var focusedField: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $usablePercent, in: 50...100, step: 5) {
                        row("Usable share", "\(Int(usablePercent))%")
                    }
                    row("Battery 1 · ETX-900", ahText(Ratings.battery1RatedAh))
                    row("Battery 2 · ETX-680C", ahText(Ratings.battery2RatedAh))
                    row("Backup · EBBS", ahText(Ratings.ebbsRatedAh))
                } header: {
                    Text("Battery capacity")
                } footer: {
                    Text("Rated capacities are EarthX's published figures. The usable share is how much of that the time estimates count on. Lower it as the batteries age or for cold weather.")
                }

                Section {
                    Stepper(value: $essentialLoadA, in: 1...40, step: 0.5) {
                        row("Essential bus load", PowerModel.ampsText(essentialLoadA))
                    }
                    Toggle("This is a measured value", isOn: $essentialLoadIsMeasured)
                    Button("Use the breaker total (\(PowerModel.ampsText(Ratings.essentialBreakerCeilingA)))") {
                        essentialLoadA = Ratings.essentialBreakerCeilingA
                        essentialLoadIsMeasured = false
                    }
                } header: {
                    Text("Essential bus (engine)")
                } footer: {
                    Text("The breaker total is ECU 1 (5 A) + ECU 2 (5 A) + ignition (15 A) + one fuel pump (10 A), from the System32 manual. Breakers are upper limits, so the real draw is lower and real battery times are longer. Measure the essential bus current with the engine running and enter it here. The Bus Manager's essential bus output is rated for \(Int(Ratings.essentialBusMaxA)) A.")
                }

                Section {
                    ForEach(Array(Ratings.ebbsPlannedLoads.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            TextField(PowerModel.ampsText(item.amps), text: fieldBinding(index))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(width: 70)
                                .focused($focusedField, equals: index)
                                .accessibilityLabel("\(item.name) amps")
                            Text("A").foregroundColor(.secondary)
                        }
                    }
                    row("Total EBBS load", PowerModel.ampsText(ebbsLoadA))
                        .font(.headline)
                        .foregroundColor(ebbsLoadA > Ratings.ebbsMaxContinuousA ? .orange : .primary)
                    Button("Use the wiring map values (\(PowerModel.ampsText(Ratings.ebbsPlannedLoadA)) total)") {
                        focusedField = nil
                        ebbsFields = Ratings.ebbsPlannedLoads.map { Self.fieldText($0.amps) }
                        saveEbbsFields()
                    }
                } header: {
                    Text("Backup battery (EBBS)")
                } footer: {
                    Text("Type the amps each item draws. The total is what the EBBS time estimate uses. The starting values are the expected loads from the airplane's wiring map. The EBBS is rated for \(Int(Ratings.ebbsMaxContinuousA)) A continuous, and the total turns orange above that. Transmitting on either radio draws more than these figures.")
                }

                Section {
                    Text("Wiring follows the Bus Manager manual, Drawing 5A (two alternators). The main bus is fed only from the Battery 1 and main alternator side. The backup alternator and Battery 2 feed the essential bus only.")
                    Text("With both alternators working, the app shows the main alternator carrying the essential bus. Whichever alternator regulates higher actually carries it.")
                    Text("Emergency Power is drawn as a direct path from both batteries to the essential bus that also brings the EBBS on. Whether it changes the main bus on N721NE is not yet confirmed.")
                    Text("A failed battery is treated as disconnected. A shorted battery behaves differently and can trip a breaker.")
                } header: {
                    Text("What the app assumes")
                }
            }
            .onAppear { loadEbbsFields() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    // MARK: - EBBS item amps

    private static func fieldText(_ amps: Double) -> String {
        if abs(amps - amps.rounded()) < 0.005 { return String(Int(amps.rounded())) }
        if abs(amps * 10 - (amps * 10).rounded()) < 0.005 { return String(format: "%.1f", amps) }
        return String(format: "%.2f", amps)
    }

    /// Fills the text boxes from what was saved, or from the planned values the first time.
    private func loadEbbsFields() {
        ebbsFields = EBBSLoad.itemAmps(from: ebbsItemAmpsRaw).map { Self.fieldText($0) }
    }

    private func fieldBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < ebbsFields.count ? ebbsFields[index] : "" },
            set: { text in
                guard index < ebbsFields.count else { return }
                ebbsFields[index] = text
                saveEbbsFields()
            }
        )
    }

    private func saveEbbsFields() {
        let amps = ebbsFields.map { EBBSLoad.parseAmps($0) }
        ebbsItemAmpsRaw = amps.map { String($0) }.joined(separator: ",")
    }

    /// The total of the item amps, which is the EBBS load the time estimate uses.
    private var ebbsLoadA: Double {
        EBBSLoad.itemAmps(from: ebbsItemAmpsRaw).reduce(0, +)
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private func ahText(_ ah: Double) -> String {
        String(format: "%.1f Ah", ah)
    }
}
