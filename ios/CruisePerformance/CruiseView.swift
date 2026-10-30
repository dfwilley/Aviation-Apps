import SwiftUI

struct CruiseView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var alt = 8500.0
    @State private var dT = 0.0
    @State private var weight = 1900.0
    @State private var pct = 65.0
    @State private var mode: MixMode = .lop
    @State private var cal = true
    @State private var targetKtas = 165.0
    @State private var targetAlt = 8500.0
    @State private var finder: FinderResult?
    @State private var table: [CruiseRow] = []
    @State private var jumpToReadout = false

    private var inputs: CruiseInputs {
        CruiseInputs(alt: alt, dT: dT, W: weight, pct: pct, mode: mode, cal: cal)
    }

    private var result: SolveResult { CruiseEngine.solve(inputs) }
    private var oat: Double { 15 - 1.98 * alt / 1000 + dT }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    finderSection
                    controls
                    readouts
                    dragSection
                    tableSection
                    planSection
                    notes
                }
                .padding(16)
            }
            .onChange(of: jumpToReadout) { _, jump in
                if jump {
                    withAnimation { proxy.scrollTo("ktas", anchor: .center) }
                    jumpToReadout = false
                }
            }
        }
        .background(bg.ignoresSafeArea())
        .onAppear { refreshHeavy() }
        .onChange(of: weight) { _, _ in refreshHeavy() }
        .onChange(of: mode) { _, _ in refreshHeavy() }
        .onChange(of: cal) { _, _ in refreshHeavy() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("N721NE · VAN'S RV-14 · LYCOMING YIO-390 · HARTZELL 74 IN CONSTANT-SPEED")
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(accent)
            Text("N721NE Cruise Fuel Burn")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(ink)
            Text("Expected true airspeed and fuel burn from a drag estimate built off the Van's 3-view, combined with the Lycoming power and fuel-flow charts. The drag estimate is tuned to Van's published RV-14 flight test numbers. Standard day unless you change the temperature.")
                .font(.body)
                .foregroundStyle(muted)
        }
    }

    private var finderSection: some View {
        panel {
            Text("Efficient cruise finder").font(.title3.weight(.semibold)).foregroundStyle(ink)
            HStack {
                labeledNumber("Target KTAS", value: $targetKtas, range: 120...190)
                labeledNumber("Altitude, ft", value: $targetAlt, range: 0...16000)
            }
            Button("Find efficient settings") { finder = CruiseEngine.findCruise(inputs, targetKtas, targetAlt) }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            Text("Uses the weight, temperature, mixture and drag settings from the calculator below.")
                .font(.footnote)
                .foregroundStyle(muted)
            finderBody
        }
    }

    @ViewBuilder private var finderBody: some View {
        if let finder {
            switch finder {
            case let .impossible(V, h, need, avail, top):
                flag("\(CruiseEngine.fmt(V)) KTAS at \(CruiseEngine.fmt(h)) ft needs about \(CruiseEngine.fmt(need)) hp, but full throttle there gives only \(CruiseEngine.fmt(avail)) hp. The fastest you can go at this altitude and weight is about \(CruiseEngine.fmt(top)) KTAS.")
            case let .ok(V, h, need, powerPct, lopOK, gChart, gLop, g, kias, options, betterAlt):
                let best = options.first
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        bigStat("Power", "\(CruiseEngine.fmt(need)) hp · \(CruiseEngine.fmt(powerPct))%")
                        bigStat("RPM / MP", best.map { "\(CruiseEngine.fmt($0.rpm)) / \(CruiseEngine.fmt($0.mp, 1))\"" } ?? "n/a")
                    }
                    HStack(alignment: .firstTextBaseline) {
                        bigStat("Fuel flow", "\(CruiseEngine.fmt(g, 1)) gal/hr")
                        bigStat("Mileage", "\(CruiseEngine.fmt(V / g, 1)) nm/gal")
                    }
                    Text(mixtureLine(lopOK: lopOK, pct: powerPct, gChart: gChart, gLop: gLop) + " Indicated airspeed will read about \(CruiseEngine.fmt(kias)) KIAS.")
                        .foregroundStyle(ink)
                    if let betterAlt {
                        Text("Climbing to \(CruiseEngine.fmt(betterAlt.alt)) ft would hold the same \(CruiseEngine.fmt(V)) KTAS on about \(CruiseEngine.fmt(betterAlt.gph, 1)) gal/hr, saving \(CruiseEngine.fmt(g - betterAlt.gph, 1)) gal/hr in cruise. Searched 2,500 to 12,500 ft so no oxygen is needed; the extra climb fuel is not counted.")
                            .foregroundStyle(ink)
                    }
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, row in
                        HStack {
                            Text(CruiseEngine.fmt(row.rpm))
                            Spacer()
                            Text(CruiseEngine.fmt(row.mp, 1))
                            Spacer()
                            Text(CruiseEngine.fmt(row.oversquare, 1))
                        }
                        .font(.system(.footnote, design: .monospaced))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(index == 0 ? accentSoft : Color.clear)
                    }
                    Text("Every row makes the same \(CruiseEngine.fmt(need)) hp. The first row is the lowest RPM that can do it. \"MP minus RPM/100\" shows how far oversquare each setting is.")
                        .font(.footnote)
                        .foregroundStyle(muted)
                    Button("Show this in the calculator") {
                        alt = (h / 500).rounded() * 500
                        pct = min(100, max(45, powerPct.rounded()))
                        jumpToReadout = true
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                }
            }
        } else {
            Text("Enter the speed and altitude you want, then tap Find efficient settings. You'll get the power needed, the lowest RPM and matching manifold pressure that make it, the mixture to use and the fuel burn.")
                .foregroundStyle(muted)
        }
    }

    private var controls: some View {
        panel {
            sliderRow("Pressure altitude", value: CruiseEngine.fmt(alt) + " ft", binding: $alt, range: 0...16000, step: 500)
            sliderRow(
                "Temperature vs. standard",
                value: "\(dT >= 0 ? "+" : "")\(CruiseEngine.fmt(dT)) °C (OAT \(CruiseEngine.fmt(oat)) °C)",
                binding: $dT, range: -20...30, step: 1
            )
            sliderRow("Weight", value: CruiseEngine.fmt(weight) + " lb", binding: $weight, range: 1450...2050, step: 10)
            sliderRow("Power (% of 210 hp)", value: "\(CruiseEngine.fmt(pct))% · \(CruiseEngine.fmt(2.1 * pct)) hp", binding: $pct, range: 45...100, step: 1)
            Text("Mixture").font(.subheadline.weight(.semibold))
            Picker("Mixture", selection: $mode) {
                Text("Lycoming chart").tag(MixMode.chart)
                Text("Lean of peak (est.)").tag(MixMode.lop)
            }
            .pickerStyle(.segmented)
            Text(mode == .chart ? "Fuel flow from Lycoming Figure 3-3." : "Estimated lean-of-peak burn. Above 70% power the chart value is used.")
                .font(.footnote).foregroundStyle(muted)
            Text("Drag estimate").font(.subheadline.weight(.semibold))
            Picker("Drag estimate", selection: $cal) {
                Text("Tuned to Van's").tag(true)
                Text("Drawing only").tag(false)
            }
            .pickerStyle(.segmented)
            Text(cal ? "Drag scaled to match Van's flight test cruise speeds." : "Raw estimate from the drawing, before tuning.")
                .font(.footnote).foregroundStyle(muted)
        }
    }

    private var readouts: some View {
        let r = result
        let usable = max(0, 50 - 0.75 * r.gph)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
                readout("True airspeed", CruiseEngine.fmt(r.ktas), "kt", main: true).id("ktas")
                readout("Fuel flow", CruiseEngine.fmt(r.gph, 1), "gal/hr", main: true)
                readout("Fuel mileage", CruiseEngine.fmt(r.nmpg, 1), "nm/gal", main: false)
                readout("Engine power", CruiseEngine.fmt(r.bhp), "hp", main: false)
                readout("Indicated airspeed", CruiseEngine.fmt(r.kias), "kt", main: false)
                readout("Range, 50 gal, 45 min reserve", CruiseEngine.fmt(usable / r.gph * r.ktas), "nm", main: false)
            }
            .background(rule)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if r.limited {
                flag("Full throttle at this altitude gives only \(CruiseEngine.fmt(r.avail)) hp, so \(CruiseEngine.fmt(pct))% is not available. Results shown are at full throttle.")
            }
            if r.lopBlocked {
                flag("Lean of peak is not used above 70% power. Fuel flow shown is the Lycoming chart value.")
            }
        }
    }

    private var dragSection: some View {
        let r = result
        let sorted = r.comps.sorted { $0.value > $1.value }
        let q = r.D0 / r.f
        let bars = sorted.map { (name: $0.name, lb: $0.value * q, induced: false) } + [(name: "Induced (lift)", lb: r.Di, induced: true)]
        let tot = bars.reduce(0) { $0 + $1.lb }
        let mx = bars.map(\.lb).max() ?? 1
        return panel {
            Text("Where the drag goes").font(.title3.weight(.semibold))
            ForEach(bars, id: \.name) { bar in
                HStack(spacing: 8) {
                    Text(bar.name).font(.caption).frame(width: 118, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(accentSoft)
                            Capsule().fill(bar.induced ? bar2 : accent).frame(width: geo.size.width * bar.lb / mx)
                        }
                    }
                    .frame(height: 12)
                    Text("\(CruiseEngine.fmt(bar.lb)) lb · \(CruiseEngine.fmt(bar.lb / tot * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 86, alignment: .trailing)
                }
            }
            Text("Total drag \(CruiseEngine.fmt(tot)) lb at \(CruiseEngine.fmt(r.ktas)) KTAS. Equivalent flat-plate area \(CruiseEngine.fmt(r.f, 2)) sq ft (zero-lift drag coefficient \(CruiseEngine.fmt(r.f / 126.1, 4))). Propeller efficiency \(CruiseEngine.fmt(r.eta * 100))%.")
                .font(.footnote).foregroundStyle(muted)
        }
    }

    private var tableSection: some View {
        panel {
            Text("Cruise table at \(CruiseEngine.fmt(weight)) lb").font(.title3.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    tableHeader
                    ForEach(table) { row in
                        HStack(spacing: 0) {
                            cell(CruiseEngine.fmt(row.h) + " ft", leading: true)
                            ForEach(0..<row.cells.count, id: \.self) { i in
                                let c = row.cells[i]
                                if c.na {
                                    cell("n/a", dim: true)
                                    cell("n/a", dim: true)
                                } else {
                                    cell(CruiseEngine.fmt(c.ktas))
                                    cell(CruiseEngine.fmt(c.gph, 1))
                                }
                            }
                            cell("\(CruiseEngine.fmt(row.wideBhp)) hp · \(CruiseEngine.fmt(row.wideKtas)) kt")
                        }
                        .background(row.pref ? accentSoft : Color.clear)
                    }
                }
            }
            Text("Standard day, mixture and drag settings from the controls above. Highlighted rows are your usual 6,500 to 9,500 ft VFR cruise band. \"Full throttle\" is 2,700 RPM wide open. Cells marked \"n/a\" need more power than the engine makes at that altitude.")
                .font(.footnote).foregroundStyle(muted)
        }
    }

    private var planSection: some View {
        panel {
            Text("Your 200 KTAS at 9 gal/hr planning number").font(.title3.weight(.semibold))
            Text("At 8,500 ft and \(CruiseEngine.fmt(weight)) lb, holding 200 KTAS would take about \(CruiseEngine.fmt(plan.hp200)) hp, but the engine makes only about \(CruiseEngine.fmt(plan.avail)) hp at full throttle there. Burning 9 gal/hr gives about \(CruiseEngine.fmt(plan.v9c)) KTAS on the Lycoming chart mixture (\(CruiseEngine.fmt(plan.p9c)) hp) or about \(CruiseEngine.fmt(plan.v9l)) KTAS lean of peak (\(CruiseEngine.fmt(plan.p9l)) hp). For flight planning, about \(CruiseEngine.fmt((plan.v9c / 5).rounded(.down) * 5)) KTAS at 9 gal/hr, or 170 KTAS at about 10 gal/hr, fits these numbers better. Your 200 may be miles per hour (174 KTAS), which matches roughly 70% power.")
                .foregroundStyle(ink)
        }
    }

    private var notes: some View {
        panel {
            Text("Method").font(.title3.weight(.semibold))
            Text("Skin-friction drag uses the Van's RV-14 3-view and Raymer's component buildup. Induced drag comes from span and weight. Fuel flow is Lycoming Figure 3-3, or 0.40 lb/hp/hr lean of peak at 70% power or less. Tuned parasite drag (factor 0.79) matches Van's 176 KTAS at 75% power, 8,000 ft, 2,050 lb. N721NE's paint, fairings, and baffles can move the result 5 to 10%.")
                .foregroundStyle(ink)
            Link("Van's RV-14 specification sheet", destination: URL(string: "https://www.vansaircraft.com/wp-content/uploads/2019/01/14FLY-e-02012019.pdf")!)
                .foregroundStyle(accent)
        }
    }

    private func refreshHeavy() {
        table = CruiseEngine.cruiseTable(inputs)
        plan = CruiseEngine.planningNumbers(weight, cal)
    }

    private func mixtureLine(lopOK: Bool, pct: Double, gChart: Double, gLop: Double) -> String {
        if lopOK {
            return "Mixture: lean of peak, about \(CruiseEngine.fmt(gLop, 1)) gal/hr (estimate). On the Lycoming chart mixture it would be about \(CruiseEngine.fmt(gChart, 1)) gal/hr."
        }
        if pct > 70 {
            return "Mixture: \(CruiseEngine.fmt(pct))% power is above 70%, so stay at the Lycoming chart mixture (best power, rich of peak): about \(CruiseEngine.fmt(gChart, 1)) gal/hr."
        }
        return "Mixture: Lycoming chart mixture: about \(CruiseEngine.fmt(gChart, 1)) gal/hr. Lean of peak would be about \(CruiseEngine.fmt(gLop, 1)) gal/hr (estimate)."
    }

    private func sliderRow(_ title: String, value: String, binding: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(accent)
            }
            Slider(value: binding, in: range, step: step).tint(accent)
        }
    }

    private func labeledNumber(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(title, value: value, format: .number)
                .keyboardType(.decimalPad)
                .font(.title3.monospacedDigit())
                .padding(8)
                .background(bg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(rule))
                .onChange(of: value.wrappedValue) { _, new in
                    value.wrappedValue = min(range.upperBound, max(range.lowerBound, new))
                }
        }
    }

    private func readout(_ k: String, _ v: String, _ u: String, main: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(v).font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(main ? accent : ink)
                Text(u).font(.caption).foregroundStyle(muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(panelBg)
    }

    private func bigStat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(muted)
            Text(v).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func flag(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(ink)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(warnSoft)
            .overlay(alignment: .leading) { Rectangle().fill(warn).frame(width: 3) }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panelBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(rule))
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            ForEach(["Altitude", "55% KTAS", "55% GPH", "65% KTAS", "65% GPH", "75% KTAS", "75% GPH", "Full throttle"], id: \.self) { title in
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(muted)
                    .frame(width: title == "Full throttle" ? 130 : 78, alignment: title == "Altitude" ? .leading : .trailing)
                    .padding(.vertical, 6)
            }
        }
    }

    private func cell(_ text: String, leading: Bool = false, dim: Bool = false) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(dim ? muted : ink)
            .frame(width: text.contains("hp") ? 130 : 78, alignment: leading ? .leading : .trailing)
            .padding(.vertical, 6)
    }

    private var bg: Color { scheme == .dark ? Color(red: 0.067, green: 0.086, blue: 0.110) : Color(red: 0.953, green: 0.961, blue: 0.969) }
    private var panelBg: Color { scheme == .dark ? Color(red: 0.094, green: 0.125, blue: 0.165) : .white }
    private var ink: Color { scheme == .dark ? Color(red: 0.894, green: 0.918, blue: 0.941) : Color(red: 0.094, green: 0.129, blue: 0.169) }
    private var muted: Color { scheme == .dark ? Color(red: 0.604, green: 0.659, blue: 0.710) : Color(red: 0.353, green: 0.404, blue: 0.451) }
    private var rule: Color { scheme == .dark ? Color(red: 0.173, green: 0.224, blue: 0.275) : Color(red: 0.839, green: 0.867, blue: 0.890) }
    private var accent: Color { scheme == .dark ? Color(red: 0.498, green: 0.714, blue: 0.863) : Color(red: 0.122, green: 0.373, blue: 0.545) }
    private var accentSoft: Color { scheme == .dark ? Color(red: 0.114, green: 0.192, blue: 0.259) : Color(red: 0.886, green: 0.929, blue: 0.961) }
    private var bar2: Color { scheme == .dark ? Color(red: 0.290, green: 0.388, blue: 0.471) : Color(red: 0.541, green: 0.655, blue: 0.741) }
    private var warn: Color { scheme == .dark ? Color(red: 0.941, green: 0.702, blue: 0.353) : Color(red: 0.631, green: 0.361, blue: 0) }
    private var warnSoft: Color { scheme == .dark ? Color(red: 0.227, green: 0.165, blue: 0.071) : Color(red: 0.984, green: 0.937, blue: 0.863) }
}
