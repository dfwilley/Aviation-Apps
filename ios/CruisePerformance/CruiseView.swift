import SwiftUI

enum Theme {
    static let bg = Color(red: 0.047, green: 0.047, blue: 0.055)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let chip = Color(red: 0.17, green: 0.17, blue: 0.18)
    static let ink = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let muted = Color(red: 0.62, green: 0.60, blue: 0.56)
    static let line = Color.white.opacity(0.10)
    static let gold = Color(red: 0.89, green: 0.67, blue: 0.28)
    static let goldSoft = Color(red: 0.89, green: 0.67, blue: 0.28).opacity(0.16)
    static let warn = Color(red: 0.94, green: 0.70, blue: 0.35)
    static let warnSoft = Color(red: 0.23, green: 0.16, blue: 0.07)
}

private func f(_ x: Double, _ d: Int = 0) -> String { CruiseEngine.fmt(x, d) }
private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

private struct FinderKey: Hashable {
    var fK: Double, fA: Double, W: Double, dT: Double, mode: String, cal: Bool, own: String
}
private struct CalcKey: Hashable {
    var alt: Double, dT: Double, W: Double, pct: Double, mode: String, cal: Bool
}
private struct TableKey: Hashable {
    var W: Double, mode: String, cal: Bool
}

struct CruiseView: View {
    @StateObject private var layout = LayoutStore()

    // Flight conditions (shared by the finder and the calculator), remembered between launches.
    @AppStorage("n721ne.alt") private var alt = 8500.0
    @AppStorage("n721ne.dT") private var dT = 0.0
    @AppStorage("n721ne.W") private var weight = 1900.0
    @AppStorage("n721ne.pct") private var pct = 65.0
    @AppStorage("n721ne.mode") private var modeRaw = MixMode.lop.rawValue
    @AppStorage("n721ne.cal") private var cal = true
    // Cruise finder targets.
    @AppStorage("n721ne.fK") private var fK = 165.0
    @AppStorage("n721ne.fA") private var fA = 8500.0
    @AppStorage("n721ne.afr0") private var afr0Text = ""

    @State private var finder: FinderResult?
    @State private var best = 0.0
    @State private var calc: SolveResult?
    @State private var table: [CruiseRow] = []
    @State private var plan: PlanningNumbers?
    @State private var showArrange = false

    private var mode: MixMode { MixMode(rawValue: modeRaw) ?? .lop }
    private var ownAfr0: Double? {
        guard let v = Double(afr0Text.replacingOccurrences(of: ",", with: ".")), v > 9, v < 22 else { return nil }
        return v
    }
    private var shared: CruiseInputs { CruiseInputs(alt: alt, dT: dT, W: weight, pct: pct, mode: mode, cal: cal) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        ForEach(layout.sections) { section in
                            card(section, proxy: proxy)
                                .id(section.rawValue)
                        }
                        Text("IO-390 chart and an RV-14 drag estimate. A planning aid — fly what the engine monitor shows.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Cruise Perf").font(.headline).foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showArrange = true } label: {
                        Label("Arrange", systemImage: "rectangle.3.group")
                    }
                    .tint(Theme.gold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .tint(Theme.gold)
                }
            }
            .sheet(isPresented: $showArrange) { ArrangeView(layout: layout) }
        }
        .preferredColorScheme(.dark)
        .task(id: FinderKey(fK: fK, fA: fA, W: weight, dT: dT, mode: modeRaw, cal: cal, own: afr0Text)) {
            try? await Task.sleep(for: .milliseconds(40))
            if Task.isCancelled { return }
            let o = shared, k = fK, a = fA
            var bo = o
            bo.alt = a
            let out = await Task.detached(priority: .userInitiated) {
                (CruiseEngine.findCruise(o, k, a), CruiseEngine.bestEconomyKTAS(bo))
            }.value
            if Task.isCancelled { return }
            finder = out.0
            best = out.1
        }
        .task(id: CalcKey(alt: alt, dT: dT, W: weight, pct: pct, mode: modeRaw, cal: cal)) {
            let o = shared
            let r = await Task.detached(priority: .userInitiated) { CruiseEngine.solve(o) }.value
            if Task.isCancelled { return }
            calc = r
        }
        .task(id: TableKey(W: weight, mode: modeRaw, cal: cal)) {
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            let o = shared, w = weight, c = cal
            let out = await Task.detached(priority: .utility) {
                (CruiseEngine.cruiseTable(o), CruiseEngine.planningNumbers(w, c))
            }.value
            if Task.isCancelled { return }
            table = out.0
            plan = out.1
        }
    }

    // MARK: - Header and cards

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("N721NE · VAN'S RV-14 · LYCOMING YIO-390 · HARTZELL 74 IN CONSTANT-SPEED")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.gold)
            Text("Expected true airspeed and fuel burn from a drag estimate built off the Van's 3-view, combined with the Lycoming power and fuel-flow charts, tuned to Van's flight test numbers. Standard day unless you change the temperature.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ section: PageSection, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(cardTitle(section))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Grip(key: "s:\(section.rawValue)", name: section.title,
                     onStep: { d in LayoutStore.step(&layout.sections, section, d) })
            }
            sectionBody(section, proxy: proxy)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
        .dropDestination(for: String.self) { items, _ in drop(items.first, onto: "s:\(section.rawValue)") }
    }

    private func cardTitle(_ s: PageSection) -> String {
        s == .table ? "Cruise table at \(f(weight)) lb" : s.title
    }

    @ViewBuilder private func sectionBody(_ s: PageSection, proxy: ScrollViewProxy) -> some View {
        switch s {
        case .finder: finderBody(proxy)
        case .conditions: conditionsBody
        case .readouts: readoutsBody
        case .drag: dragBody
        case .table: tableBody
        case .planning: planningBody
        case .sources: notesList(InfoText.sources)
        case .method: notesList(InfoText.method)
        }
    }

    // MARK: - Efficient cruise finder

    @ViewBuilder private func finderBody(_ proxy: ScrollViewProxy) -> some View {
        finderTiles

        StepField(label: "Target KTAS", hint: "±5 kt", value: $fK, step: 5, range: 100...200)
        HStack(spacing: 8) {
            ForEach([150.0, 160, 170, 180], id: \.self) { p in
                Chip(title: f(p), on: fK == p) { fK = p }
            }
        }
        Button { fK = best } label: {
            Text("Most efficient · \(f(best)) KTAS")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.gold)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)

        StepField(label: "Altitude, ft", hint: "±500 ft", value: $fA, step: 500, range: 0...16000)
        HStack(spacing: 8) {
            ForEach([4500.0, 6500, 8500, 10500, 12500], id: \.self) { p in
                Chip(title: f(p / 1000, 1) + "k", on: fA == p) { fA = p }
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Your A/F at 0% trim").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("(optional)").font(.footnote).foregroundStyle(Theme.muted)
            }
            TextField("from EFII tuning chart", text: $afr0Text)
                .keyboardType(.decimalPad)
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .padding(10)
                .background(Theme.chip)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        Text("Uses the weight, temperature, mixture and drag settings from Flight conditions.")
            .font(.footnote)
            .foregroundStyle(Theme.muted)

        finderDetails(proxy)

        HStack {
            Text("Hold ≡ and drag to rearrange tiles, or tap Arrange.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button("Reset tile layout") { layout.resetTiles() }
                .font(.footnote.weight(.semibold))
                .tint(Theme.gold)
        }
    }

    @ViewBuilder private var finderTiles: some View {
        switch finder {
        case nil:
            ProgressView().frame(maxWidth: .infinity)
        case let .impossible(V, h, need, avail, top)?:
            Flag(text: "\(f(V)) KTAS at \(f(h)) ft needs about \(f(need)) hp, but full throttle there gives only \(f(avail)) hp. The fastest you can go at this altitude and weight is about \(f(top)) KTAS.")
            Button("Use \(f(top.rounded(.down))) KTAS") { fK = max(100, top.rounded(.down)) }
                .font(.subheadline.weight(.semibold))
                .tint(Theme.gold)
        case let .ok(V, h, need, p, lopOK, _, _, g, kias, options, _)?:
            let mt = CruiseEngine.mixTarget(pct: p, lopOK: lopOK)
            let trim = CruiseEngine.efiiTrim(rpm: options.first?.rpm, ownAfr0: ownAfr0, target: mt.n)
            TileGrid {
                ForEach(layout.finderTiles) { t in
                    let v = finderValue(t, V: V, h: h, need: need, pct: p, g: g, kias: kias, options: options, mt: mt, trim: trim?.trim)
                    Tile(key: "f:\(t.rawValue)", title: t.title, value: v.0, unit: v.1, main: t == .gph,
                         onStep: { d in LayoutStore.step(&layout.finderTiles, t, d) },
                         onDrop: { raw in drop(raw, onto: "f:\(t.rawValue)") })
                }
            }
        }
    }

    private func finderValue(_ t: FinderTile, V: Double, h: Double, need: Double, pct: Double, g: Double, kias: Double,
                             options: [CruiseOption], mt: MixTarget, trim: Int?) -> (String, String) {
        switch t {
        case .pwr: return ("\(f(need)) hp", "\(f(pct))%")
        case .rpm:
            guard let b = options.first else { return ("n/a", "") }
            return (f(b.rpm), "/ \(f(b.mp, 1)) in.")
        case .gph: return (f(g, 1), "gal/hr")
        case .mpg: return (f(V / g, 1), "nm/gal")
        case .fa: return (mt.fa, "\(mt.afr):1 A/F")
        case .trim:
            guard let trim else { return ("n/a", "") }
            return ((trim > 0 ? "+" : "") + "\(trim)%", "")
        case .kias: return (f(kias), "KIAS")
        case .mode: return (mt.label, "")
        }
    }

    @ViewBuilder private func finderDetails(_ proxy: ScrollViewProxy) -> some View {
        if case let .ok(V, h, need, p, lopOK, gChart, gLop, g, kias, options, betterAlt)? = finder {
            let mt = CruiseEngine.mixTarget(pct: p, lopOK: lopOK)
            let bestRpm = options.first?.rpm
            VStack(alignment: .leading, spacing: 12) {
                if let t = CruiseEngine.efiiTrim(rpm: bestRpm, ownAfr0: ownAfr0, target: mt.n) {
                    let txt = (t.trim > 0 ? "+" : "") + "\(t.trim)%"
                    let dir = t.trim < 0 ? "counterclockwise, less fuel" : (t.trim > 0 ? "clockwise, more fuel" : "no change")
                    let at = bestRpm.map { " at \(f($0)) RPM" } ?? ""
                    let src = t.own ? ", the value you entered" : ", the target in EFII's initial tuning chart for that RPM"
                    Para(bold: "Fuel trim:", text: "set the System32 trim knob to about \(txt) (\(dir)). This assumes the controller shows about \(f(t.base, 1)):1 air/fuel at 0% trim\(at)\(src). Fine-tune the knob until the controller reads \(mt.afr):1 and the EGTs agree.")
                }
                Para(bold: "Target mixture:", text: "fuel/air ratio about \(mt.fa), which reads as an air/fuel ratio of about \(mt.afr):1 (good range \(mt.band)) on the System32 controller. That is \(mt.egt).")
                Para(bold: "Mixture:", text: mixtureText(p: p, lopOK: lopOK, gChart: gChart, gLop: gLop) + " Indicated airspeed will read about \(f(kias)) KIAS.")
                if let b = betterAlt {
                    Para(bold: nil, text: "Climbing to \(f(b.alt)) ft would hold the same \(f(V)) KTAS on about \(f(b.gph, 1)) gal/hr, saving \(f(g - b.gph, 1)) gal/hr in cruise. Searched 2,500 to 12,500 ft so no oxygen is needed; the extra climb fuel is not counted.")
                }
                if !options.isEmpty {
                    OptionsTable(options: options)
                    Text("Every row makes the same \(f(need)) hp. The highlighted row is the lowest RPM that can do it at this altitude; higher RPM rows are listed for comparison. \"MP minus RPM/100\" shows how far oversquare each setting is.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                Button {
                    alt = (h / 500).rounded() * 500
                    pct = clamp(min(100, p).rounded(), 45, 100)
                    withAnimation { proxy.scrollTo(PageSection.readouts.rawValue, anchor: .top) }
                } label: {
                    Text("Show this in the calculator")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.gold))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func mixtureText(p: Double, lopOK: Bool, gChart: Double, gLop: Double) -> String {
        if lopOK {
            return "lean of peak, about \(f(gLop, 1)) gal/hr (estimate). On the Lycoming chart mixture it would be about \(f(gChart, 1)) gal/hr."
        }
        let lead = p > 70 ? "\(f(p))% power is above 70%, so stay at the Lycoming chart mixture (best power, rich of peak)" : "Lycoming chart mixture"
        let tail = p <= 70 ? " Lean of peak would be about \(f(gLop, 1)) gal/hr (estimate)." : ""
        return lead + ": about \(f(gChart, 1)) gal/hr." + tail
    }

    // MARK: - Flight conditions (calculator inputs)

    @ViewBuilder private var conditionsBody: some View {
        let oat = 15 - 1.98 * alt / 1000 + dT
        SliderRow(label: "Pressure altitude", out: "\(f(alt)) ft", value: $alt, range: 0...16000, step: 500)
        SliderRow(label: "Temperature vs. standard",
                  out: "\(dT >= 0 ? "+" : "")\(f(dT)) °C (OAT \(f(oat)) °C / \(f(oat * 9 / 5 + 32)) °F)",
                  value: $dT, range: -20...30, step: 1)
        SliderRow(label: "Weight", out: "\(f(weight)) lb", value: $weight, range: 1450...2050, step: 10)
        SliderRow(label: "Power (% of 210 hp)", out: "\(f(pct))% · \(f(2.1 * pct)) hp", value: $pct, range: 45...100, step: 1)

        VStack(alignment: .leading, spacing: 8) {
            Text("Mixture").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Chip(title: "Rich of peak (chart)", on: mode == .chart) { modeRaw = MixMode.chart.rawValue }
                Chip(title: "Lean of peak (est.)", on: mode == .lop) { modeRaw = MixMode.lop.rawValue }
            }
            Text(mode == .chart ? "Fuel flow from Lycoming Figure 3-3." : "Estimated lean-of-peak burn. Above 70% power the chart value is used.")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag estimate").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Chip(title: "Tuned to Van's", on: cal) { cal = true }
                Chip(title: "Drawing only", on: !cal) { cal = false }
            }
            Text(cal ? "Drag scaled to match Van's flight test cruise speeds." : "Raw estimate from the drawing, before tuning.")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
        Text("Weight, temperature, mixture and drag also feed the cruise finder. Altitude and power here are for the calculator.")
            .font(.footnote).foregroundStyle(Theme.muted)
    }

    // MARK: - Calculator readouts

    @ViewBuilder private var readoutsBody: some View {
        if let r = calc {
            TileGrid {
                ForEach(layout.readoutTiles) { t in
                    let v = readoutValue(t, r)
                    Tile(key: "r:\(t.rawValue)", title: t.title, value: v.0, unit: v.1, main: t == .rKtas || t == .rGph,
                         onStep: { d in LayoutStore.step(&layout.readoutTiles, t, d) },
                         onDrop: { raw in drop(raw, onto: "r:\(t.rawValue)") })
                }
            }
            if r.limited {
                Flag(text: "Full throttle at this altitude gives only \(f(r.avail)) hp, so \(f(pct))% is not available. Results shown are at full throttle.")
            }
            if r.lopBlocked {
                Flag(text: "Lean of peak is not used above 70% power. Fuel flow shown is the Lycoming chart value.")
            }
            Text("At \(f(alt)) ft, \(f(pct))% power, \(f(weight)) lb. Change these under Flight conditions.")
                .font(.footnote).foregroundStyle(Theme.muted)
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func readoutValue(_ t: ReadoutTile, _ r: SolveResult) -> (String, String) {
        switch t {
        case .rKtas: return (f(r.ktas), "kt")
        case .rGph: return (f(r.gph, 1), "gal/hr")
        case .rMpg: return (f(r.nmpg, 1), "nm/gal")
        case .rBhp: return (f(r.bhp), "hp")
        case .rKias: return (f(r.kias), "kt")
        case .rRange:
            let usable = max(0, 50 - 0.75 * r.gph)
            return (f(usable / r.gph * r.ktas), "nm")
        }
    }

    // MARK: - Drag breakdown

    @ViewBuilder private var dragBody: some View {
        if let r = calc {
            let q = r.D0 / r.f
            let parts: [(String, Double)] = r.comps.sorted { $0.value > $1.value }.map { ($0.name, $0.value * q) }
            let items: [(String, Double)] = parts + [("Induced (lift)", r.Di)]
            let total = items.reduce(0.0) { $0 + $1.1 }
            let mx = items.map { $0.1 }.max() ?? 1
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    DragBar(name: item.0, lb: item.1, share: item.1 / total, fraction: item.1 / mx, induced: item.0.hasPrefix("Induced"))
                }
            }
            Text("Total drag \(f(total)) lb at \(f(r.ktas)) KTAS. Equivalent flat-plate area \(f(r.f, 2)) sq ft (zero-lift drag coefficient \(f(r.f / 126.1, 4))). Propeller efficiency \(f(r.eta * 100))%.")
                .font(.footnote).foregroundStyle(Theme.muted)
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    // MARK: - Cruise table

    @ViewBuilder private var tableBody: some View {
        if table.isEmpty {
            ProgressView().frame(maxWidth: .infinity)
        } else {
            CruiseTableView(rows: table)
            Text("Standard day, mixture and drag settings from Flight conditions. Shaded rows are your usual 6,500 to 9,500 ft VFR cruise band. \"Full throttle\" is 2,700 RPM wide open: horsepower available and the speed it gives. Cells marked \"n/a\" need more power than the engine makes at that altitude. Swipe the table sideways to see every column.")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Planning number check

    @ViewBuilder private var planningBody: some View {
        if let p = plan {
            Text("At 8,500 ft and \(f(weight)) lb, holding 200 KTAS would take about \(f(p.hp200)) hp, but the engine makes only about \(f(p.avail)) hp at full throttle there. Burning 9 gal/hr gives about \(f(p.v9c)) KTAS on the Lycoming chart mixture (\(f(p.p9c)) hp) or about \(f(p.v9l)) KTAS lean of peak (\(f(p.p9l)) hp). For flight planning, about \(f((p.v9c / 5).rounded(.down) * 5)) KTAS at 9 gal/hr, or 170 KTAS at about 10 gal/hr, fits these numbers better. Your 200 may be miles per hour (174 KTAS), which matches roughly 70% power.")
                .font(.callout)
                .foregroundStyle(Theme.ink)
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    // MARK: - Sources and method

    private func notesList(_ items: [InfoText.Item]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    if let tag = item.tag {
                        Text(tag.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(tag == "Verified" ? Theme.gold : Theme.warn)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(tag == "Verified" ? Theme.goldSoft : Theme.warnSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(item.attributed)
                        .font(.callout)
                        .foregroundStyle(Theme.ink)
                        .tint(Theme.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Moving tiles and sections

    /// Drop "kind:item" onto "kind:target". Only moves within the same kind (sections, finder tiles, calculator tiles).
    private func drop(_ raw: String?, onto target: String) -> Bool {
        guard let raw else { return false }
        let a = raw.split(separator: ":", maxSplits: 1).map(String.init)
        let b = target.split(separator: ":", maxSplits: 1).map(String.init)
        guard a.count == 2, b.count == 2, a[0] == b[0], a[1] != b[1] else { return false }
        withAnimation(.spring(duration: 0.25)) {
            switch a[0] {
            case "s":
                if let s = PageSection(rawValue: a[1]), let t = PageSection(rawValue: b[1]) { LayoutStore.move(&layout.sections, s, onto: t) }
            case "f":
                if let s = FinderTile(rawValue: a[1]), let t = FinderTile(rawValue: b[1]) { LayoutStore.move(&layout.finderTiles, s, onto: t) }
            case "r":
                if let s = ReadoutTile(rawValue: a[1]), let t = ReadoutTile(rawValue: b[1]) { LayoutStore.move(&layout.readoutTiles, s, onto: t) }
            default: break
            }
        }
        return true
    }
}

// MARK: - Building blocks

/// The ≡ handle: drag it to move a tile or section. VoiceOver users get Move up / Move down actions.
struct Grip: View {
    let key: String
    let name: String
    let onStep: (Int) -> Void

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.muted)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .draggable(key) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(Theme.gold)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Move \(name)")
            .accessibilityAction(named: "Move up") { onStep(-1) }
            .accessibilityAction(named: "Move down") { onStep(1) }
    }
}

struct TileGrid<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) { content }
    }
}

struct Tile: View {
    let key: String
    let title: String
    let value: String
    let unit: String
    let main: Bool
    let onStep: (Int) -> Void
    let onDrop: (String?) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Grip(key: key, name: title, onStep: onStep)
                    .padding(.top, -6)
                    .padding(.trailing, -6)
            }
            (Text(value)
                .font(.system(size: 21, weight: .semibold, design: .monospaced))
                .foregroundColor(main ? Theme.gold : Theme.ink)
             + Text(unit.isEmpty ? "" : " " + unit)
                .font(.footnote)
                .foregroundColor(Theme.muted))
                .minimumScaleFactor(0.7)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(Theme.chip)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .dropDestination(for: String.self) { items, _ in onDrop(items.first) }
        .accessibilityElement(children: .combine)
    }
}

struct Chip: View {
    let title: String
    var on: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(on ? Color.black : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .padding(.horizontal, 4)
                .background(on ? Theme.gold : Theme.chip)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct Flag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.warnSoft)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.warn).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct Para: View {
    let bold: String?
    let text: String
    var body: some View {
        (Text(bold.map { $0 + " " } ?? "").bold() + Text(text))
            .font(.callout)
            .foregroundColor(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Number box with − and + buttons. Typing works too.
struct StepField: View {
    let label: String
    let hint: String
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("(\(hint))").font(.footnote).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                circleButton("minus") { value = clamp(value - step, range.lowerBound, range.upperBound) }
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 34, weight: .light, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                circleButton("plus") { value = clamp(value + step, range.lowerBound, range.upperBound) }
            }
        }
        .onAppear { text = Self.show(value) }
        .onChange(of: value) { _, v in if Double(text) != v { text = Self.show(v) } }
        .onChange(of: text) { _, t in
            if let v = Double(t.filter { $0.isNumber || $0 == "." }), v != value { value = v }
        }
    }

    private static func show(_ v: Double) -> String { String(Int(v.rounded())) }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 52, height: 52)
                .background(Theme.chip)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "minus" ? "Decrease \(label)" : "Increase \(label)")
    }
}

struct SliderRow: View {
    let label: String
    let out: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(out).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.gold)
            Slider(value: $value, in: range, step: step).tint(Theme.gold)
                .accessibilityLabel(label)
                .accessibilityValue(out)
        }
    }
}

struct DragBar: View {
    let name: String
    let lb: Double
    let share: Double
    let fraction: Double
    let induced: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.footnote).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(f(lb)) lb · \(f(share * 100))%").font(.footnote.monospacedDigit()).foregroundStyle(Theme.muted)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.chip)
                    Capsule().fill(induced ? Theme.muted : Theme.gold)
                        .frame(width: max(2, g.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

struct OptionsTable: View {
    let options: [CruiseOption]
    var body: some View {
        VStack(spacing: 0) {
            row(["RPM", "MP, in. Hg", "MP − RPM/100"], header: true, best: false)
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                row([f(o.rpm), f(o.mp, 1), f(o.oversquare, 1)], header: false, best: i == 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func row(_ cells: [String], header: Bool, best: Bool) -> some View {
        HStack {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                Text(c)
                    .font(header ? .caption2.weight(.semibold) : .callout.monospacedDigit().weight(best ? .bold : .regular))
                    .foregroundStyle(header ? Theme.muted : (best ? Theme.gold : Theme.ink))
                    .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(best ? Theme.goldSoft : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

struct CruiseTableView: View {
    let rows: [CruiseRow]
    private let w: [CGFloat] = [76, 58, 52, 58, 52, 58, 52, 128]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                line(["Altitude", "55% KTAS", "55% GPH", "65% KTAS", "65% GPH", "75% KTAS", "75% GPH", "Full throttle"], header: true, pref: false)
                ForEach(rows) { r in
                    line(cellsFor(r), header: false, pref: r.pref)
                }
            }
            .padding(.bottom, 6)
        }
    }
    private func cellsFor(_ r: CruiseRow) -> [String] {
        var cells = ["\(f(r.h)) ft"]
        for c in r.cells {
            cells += c.na ? ["n/a", "n/a"] : [f(c.ktas), f(c.gph, 1)]
        }
        cells.append("\(f(r.wideBhp)) hp · \(f(r.wideKtas)) kt")
        return cells
    }

    private func line(_ cells: [String], header: Bool, pref: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                Text(c)
                    .font(header ? .caption2.weight(.semibold) : .footnote.monospacedDigit())
                    .foregroundStyle(header || c == "n/a" ? Theme.muted : Theme.ink)
                    .lineLimit(header ? 2 : 1)
                    .multilineTextAlignment(i == 0 ? .leading : .trailing)
                    .frame(width: w[min(i, w.count - 1)], alignment: i == 0 ? .leading : .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(pref ? Theme.goldSoft : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
