import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("usablePercent") private var usablePercent = 80.0
    @AppStorage("essentialLoadA") private var essentialLoadA = Ratings.essentialBreakerCeilingA
    @AppStorage("essentialLoadIsMeasured") private var essentialLoadIsMeasured = false
    @AppStorage("ebbsLoadA") private var ebbsLoadA = Ratings.ebbsPlannedLoadA

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
                    Stepper(value: $ebbsLoadA, in: 0.5...12, step: 0.5) {
                        row("EBBS load", PowerModel.ampsText(ebbsLoadA))
                    }
                    ForEach(Ratings.ebbsPlannedLoads, id: \.name) { item in
                        row(item.name, PowerModel.ampsText(item.amps))
                            .foregroundColor(.secondary)
                    }
                    Button("Use the planned total (\(PowerModel.ampsText(Ratings.ebbsPlannedLoadA)))") {
                        ebbsLoadA = Ratings.ebbsPlannedLoadA
                    }
                } header: {
                    Text("Backup battery (EBBS)")
                } footer: {
                    Text("Planned draws are from the VP-X load plan. The EBBS is rated for \(Int(Ratings.ebbsMaxContinuousA)) A continuous, and transmitting on the SL-30 draws more than receiving.")
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
