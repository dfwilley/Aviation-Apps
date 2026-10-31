import SwiftUI

private enum Tile: String, CaseIterable, Identifiable {
    case airspeed, altitude, weight, oat, mixture, results
    var id: String { rawValue }
}

struct CruiseView: View {
    @State private var alt = 0.0
    @State private var weight = 1650.0
    @State private var oatF = 59.0
    @State private var ktas = 143.0
    @State private var mode: MixMode = .chart
    @State private var order: [Tile] = Tile.allCases
    @State private var best = 143.0
    @State private var wide = 184.0
    @State private var cruise: FinderResult?

    private let cal = true
    private var isaC: Double { 15 - 1.98 * alt / 1000 }
    private var isaF: Double { isaC * 9 / 5 + 32 }
    private var oatC: Double { (oatF - 32) * 5 / 9 }
    private var dT: Double { oatC - isaC }
    private var densityAlt: Double { alt + 120 * dT }
    private var inputs: CruiseInputs {
        CruiseInputs(alt: alt, dT: dT, W: weight, pct: 65, mode: mode, cal: cal)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                banner
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(group.enumerated()), id: \.element.id) { index, tile in
                            if index > 0 {
                                Rectangle()
                                    .fill(line)
                                    .frame(height: 1)
                                    .padding(.vertical, 16)
                            }
                            tileBody(tile)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let raw = items.first, let source = Tile(rawValue: raw) else { return false }
                                    move(source, before: tile)
                                    return true
                                }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(line))
                }
                Text("IO-390 chart and an RV-14 drag estimate. A planning aid — fly what the engine monitor shows.")
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            if let saved = UserDefaults.standard.stringArray(forKey: "n721ne.tiles") {
                let parsed = saved.compactMap(Tile.init(rawValue:))
                let missing = Tile.allCases.filter { !parsed.contains($0) }
                if !parsed.isEmpty { order = parsed + missing }
            }
            refresh()
        }
        .onChange(of: alt) { _, _ in refresh() }
        .onChange(of: weight) { _, _ in refresh() }
        .onChange(of: oatF) { _, _ in refresh() }
        .onChange(of: ktas) { _, _ in refreshCruise() }
        .onChange(of: mode) { _, _ in refresh() }
    }

    private var banner: some View {
        Text("Standard temp \(CruiseEngine.fmt(isaF))°F · density altitude \(CruiseEngine.fmt(densityAlt)) ft · max about \(CruiseEngine.fmt(wide)) KTAS wide open")
            .font(.subheadline)
            .foregroundStyle(muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(line))
    }

    private var blocks: [[Tile]] {
        let stack: Set<Tile> = [.altitude, .weight, .oat, .mixture]
        var grouped: [[Tile]] = []
        for tile in order {
            if stack.contains(tile), var last = grouped.last, last.allSatisfy({ stack.contains($0) }) {
                last.append(tile)
                grouped[grouped.count - 1] = last
            } else {
                grouped.append([tile])
            }
        }
        return grouped
    }

    @ViewBuilder private func tileBody(_ tile: Tile) -> some View {
        switch tile {
        case .airspeed: airspeedBody
        case .altitude: altitudeBody
        case .weight: weightBody
        case .oat: oatBody
        case .mixture: mixtureBody
        case .results: resultsBody
        }
    }

    private var airspeedBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("TRUE AIRSPEED", unit: "KTAS", tile: .airspeed)
            dial(CruiseEngine.fmt(ktas), minus: { ktas = clamp(ktas - 1, 100, 200) }, plus: { ktas = clamp(ktas + 1, 100, 200) })
            HStack(spacing: 8) {
                ForEach([150.0, 160, 170, 180], id: \.self) { preset in
                    chip(CruiseEngine.fmt(preset)) { ktas = preset }
                }
            }
            Button { ktas = best } label: {
                Text("Most efficient · \(CruiseEngine.fmt(best))")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(gold)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var altitudeBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("ALTITUDE", unit: "ft", tile: .altitude)
            dial(CruiseEngine.fmt(alt), minus: { alt = clamp(alt - 500, 0, 16000) }, plus: { alt = clamp(alt + 500, 0, 16000) })
            HStack(spacing: 8) {
                ForEach([4500.0, 8500, 12500], id: \.self) { preset in
                    chip(CruiseEngine.fmt(preset)) { alt = preset }
                }
            }
        }
    }

    private var weightBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("WEIGHT", unit: "lb", tile: .weight)
            dial(CruiseEngine.fmt(weight), minus: { weight = clamp(weight - 10, 1250, 2050) }, plus: { weight = clamp(weight + 10, 1250, 2050) })
            Text("Empty 1,247 lb. 1,650 lb is you at 250 lb plus about half fuel.")
                .font(.subheadline)
                .foregroundStyle(muted)
        }
    }

    private var oatBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("OAT")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(muted)
                Spacer()
                Button { oatF = isaF.rounded() } label: {
                    Text("ISA \(CruiseEngine.fmt(isaF))°")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(gold)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                grip(.oat)
            }
            ZStack {
                Text(CruiseEngine.fmt(oatF))
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(ink)
                HStack {
                    stepButton("-") { oatF = clamp(oatF - 1, -40, 120) }
                    Spacer()
                    Text("°F")
                        .font(.title3)
                        .foregroundStyle(muted)
                        .padding(.trailing, 8)
                    stepButton("+") { oatF = clamp(oatF + 1, -40, 120) }
                }
            }
        }
    }

    private var mixtureBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("MIXTURE", unit: " ", tile: .mixture)
            HStack(spacing: 8) {
                chip("Lean of peak", on: mode == .lop) { mode = .lop }
                chip("Rich of peak", on: mode == .chart) { mode = .chart }
            }
            Text(mode == .lop
                ? "Lean of peak is an estimate, and only at 70% power or less. Above that, fuel flow uses rich of peak."
                : "Rich of peak uses the Lycoming best-power chart.")
                .font(.subheadline)
                .foregroundStyle(muted)
        }
    }

    private var resultsBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("FUEL FLOW", unit: "gal/hr", tile: .results)
            if let cruise {
                switch cruise {
                case let .impossible(V, _, need, avail, top):
                    Text("\(CruiseEngine.fmt(V)) KTAS needs about \(CruiseEngine.fmt(need)) hp. Full throttle here makes \(CruiseEngine.fmt(avail)) hp, about \(CruiseEngine.fmt(top)) KTAS.")
                        .font(.subheadline)
                        .foregroundStyle(ink)
                    Button("Use \(CruiseEngine.fmt(top)) KTAS") { ktas = top.rounded() }
                        .buttonStyle(.plain)
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(gold)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                case let .ok(_, _, need, powerPct, lopOK, gChart, gLop, g, kias, options, betterAlt):
                    Text(CruiseEngine.fmt(g, 1))
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity)
                    let bestOption = options.first
                    fact("Power", "\(CruiseEngine.fmt(need)) hp · \(CruiseEngine.fmt(powerPct))%")
                    fact("RPM / MP", bestOption.map { "\(CruiseEngine.fmt($0.rpm)) / \(CruiseEngine.fmt($0.mp, 1)) in" } ?? "Not available")
                    fact("Mileage", "\(CruiseEngine.fmt(ktas / g, 1)) nm/gal")
                    fact("Indicated", "\(CruiseEngine.fmt(kias)) KIAS")
                    let usable = max(0, 50 - 0.75 * g)
                    fact("Range", "\(CruiseEngine.fmt(usable / g * ktas)) nm")
                    Text(mixtureSentence(lopOK: lopOK, pct: powerPct, gChart: gChart, gLop: gLop))
                        .font(.subheadline)
                        .foregroundStyle(muted)
                    if let betterAlt {
                        Text("\(CruiseEngine.fmt(betterAlt.alt)) ft holds this speed on about \(CruiseEngine.fmt(betterAlt.gph, 1)) gal/hr.")
                            .font(.subheadline)
                            .foregroundStyle(ink)
                    }
                    HStack(spacing: 8) {
                        chip("Lean of peak", on: mode == .lop) { mode = .lop }
                        chip("Rich of peak", on: mode == .chart) { mode = .chart }
                    }
                }
            }
        }
    }

    private func heading(_ title: String, unit: String, tile: Tile) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(muted)
            Spacer()
            Text(unit)
                .font(.caption)
                .foregroundStyle(muted)
            grip(tile)
        }
    }

    private func grip(_ tile: Tile) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(muted)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .draggable(tile.rawValue)
            .accessibilityLabel("Move tile")
    }

    private func dial(_ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        ZStack {
            Text(value)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(ink)
            HStack {
                stepButton("-", action: minus)
                Spacer()
                stepButton("+", action: plus)
            }
        }
    }

    private func stepButton(_ mark: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(mark)
                .font(.title2.weight(.medium))
                .foregroundStyle(ink)
                .frame(width: 52, height: 52)
                .background(chipBg)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundStyle(on ? Color.black : ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(on ? gold : chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func fact(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(muted)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(ink)
        }
    }

    private func mixtureSentence(lopOK: Bool, pct: Double, gChart: Double, gLop: Double) -> String {
        if lopOK {
            return "Lean of peak, about \(CruiseEngine.fmt(gLop, 1)) gal/hr. Rich of peak would be about \(CruiseEngine.fmt(gChart, 1))."
        }
        if pct > 70 {
            return "Above 70% power, so this is rich of peak. Lean of peak is not used here."
        }
        return "Rich of peak, about \(CruiseEngine.fmt(gChart, 1)) gal/hr. Lean of peak would be about \(CruiseEngine.fmt(gLop, 1))."
    }

    private func refresh() {
        let wideSolve = CruiseEngine.solve(CruiseInputs(alt: alt, dT: dT, W: weight, pct: 100, mode: mode, cal: cal))
        wide = wideSolve.ktas
        best = CruiseEngine.bestEconomyKTAS(inputs)
        refreshCruise()
    }

    private func refreshCruise() {
        cruise = CruiseEngine.findCruise(inputs, ktas, alt)
    }

    private func move(_ source: Tile, before target: Tile) {
        guard source != target, let from = order.firstIndex(of: source), let to = order.firstIndex(of: target) else { return }
        withAnimation(.spring(duration: 0.25)) {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        UserDefaults.standard.set(order.map(\.rawValue), forKey: "n721ne.tiles")
    }

    private func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, value)) }

    private var bg: Color { Color(red: 0.047, green: 0.047, blue: 0.055) }
    private var cardBg: Color { Color(red: 0.11, green: 0.11, blue: 0.12) }
    private var chipBg: Color { Color(red: 0.17, green: 0.17, blue: 0.18) }
    private var ink: Color { Color(red: 0.96, green: 0.94, blue: 0.90) }
    private var muted: Color { Color(red: 0.62, green: 0.60, blue: 0.56) }
    private var line: Color { Color.white.opacity(0.10) }
    private var gold: Color { Color(red: 0.89, green: 0.67, blue: 0.28) }
}
