import SwiftUI

enum WBField: Hashable {
    case pil, pax, bag, fuel, burn, wL, aL, wR, aR, wT, aT, dW, dA
}

struct ContentView: View {
    @State private var inp: WBInputs = Store.load()
    @State private var ewOpen = false
    @State private var addOpen = false
    @FocusState private var focus: WBField?

    private func bind(_ kp: WritableKeyPath<WBInputs, String>) -> Binding<String> {
        Binding(get: { inp[keyPath: kp] }, set: { inp[keyPath: kp] = $0 })
    }

    var body: some View {
        let r = WB.compute(inp)
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if let r { StatusBar(result: r) }
                        tiles(r, proxy: proxy).id("tiles")
                        loadPanel
                        if ewOpen { emptyWeightPanel(r, proxy: proxy).id("ew") }
                        if let r {
                            Panel {
                                PanelTitle("CG envelope")
                                EnvelopeChart(result: r)
                                legend
                            }
                            Panel {
                                PanelTitle("Loading table")
                                LoadingTable(result: r)
                            }
                        }
                        notes
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Theme.bg.ignoresSafeArea())
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }.fontWeight(.semibold)
                }
            }
        }
        .tint(Theme.accent)
        .onChange(of: inp) { Store.save($0) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("N721NE · VAN'S RV-14 · SERIAL 140336")
                .font(Theme.display(12, .semibold))
                .tracking(1.4)
                .foregroundColor(Theme.accent)
            Text("N721NE Weight & Balance")
                .font(Theme.display(24, .bold))
                .foregroundColor(Theme.ink)
        }
    }

    // MARK: Result tiles

    private func tiles(_ r: WBResult?, proxy: ScrollViewProxy) -> some View {
        let dash = "—"
        let ewTile = Button {
            toggleEmptyWeight(proxy)
        } label: {
            Tile(key: "Empty weight ✎",
                 value: r.map { WB.fmt($0.emptyWeight) } ?? dash,
                 unit: r.map { "lb · \(WB.fmt($0.emptyCG, 2)) in" } ?? "",
                 highlighted: ewOpen)
        }
        .buttonStyle(.plain)
        .accessibilityHint(ewOpen ? "Closes the empty weight editor" : "Opens the empty weight editor")

        return Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                Tile(key: "Takeoff weight", value: r.map { WB.fmt($0.toW) } ?? dash, unit: "lb",
                     bad: r?.overWeight ?? false)
                Tile(key: "Takeoff CG", value: r.map { WB.fmt($0.toCG, 2) } ?? dash,
                     unit: r.map { "in · \(WB.fmt(Limits.mac($0.toCG), 1))%" } ?? "",
                     bad: r.map { !$0.inCG($0.toCG) } ?? false)
            }
            GridRow {
                Tile(key: "Landing weight", value: r.map { WB.fmt($0.lW) } ?? dash, unit: "lb")
                Tile(key: "Landing CG", value: r.map { WB.fmt($0.lCG, 2) } ?? dash,
                     unit: r.map { "in · \(WB.fmt(Limits.mac($0.lCG), 1))%" } ?? "",
                     bad: r.map { !$0.inCG($0.lCG) } ?? false)
            }
            GridRow {
                Tile(key: "Below max weight", value: r.map { WB.fmt($0.margin) } ?? dash, unit: "lb",
                     bad: r?.overWeight ?? false)
                ewTile
            }
            GridRow {
                Tile(key: "Zero-fuel CG", value: r.map { WB.fmt($0.zfCG, 2) } ?? dash,
                     unit: r.map { "in · \(WB.fmt(Limits.mac($0.zfCG), 1))%" } ?? "",
                     bad: r.map { !$0.inCG($0.zfCG) } ?? false)
                Tile(key: "Max fuel this load",
                     value: r.map { WB.fmt(($0.maxFuel * 10).rounded(.down) / 10, 1) } ?? dash, unit: "gal")
            }
        }
        .background(Theme.rule)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weight and balance results")
    }

    private func toggleEmptyWeight(_ proxy: ScrollViewProxy) {
        let opening = !ewOpen
        withAnimation(.easeInOut(duration: 0.2)) { ewOpen = opening }
        if !opening { focus = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation { proxy.scrollTo(opening ? "ew" : "tiles", anchor: opening ? .top : .center) }
        }
    }

    // MARK: Load inputs

    private var loadPanel: some View {
        Panel {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                      alignment: .leading, spacing: 12) {
                StepField(title: "Pilot", unit: "lb", text: bind(\.pil), step: 5, lo: 0, hi: 300,
                          keyboard: .numberPad, focus: $focus, field: .pil)
                StepField(title: "Passenger", unit: "lb", text: bind(\.pax), step: 5, lo: 0, hi: 300,
                          keyboard: .numberPad, focus: $focus, field: .pax)
                StepField(title: "Baggage", unit: "lb", text: bind(\.bag), step: 5, lo: 0, hi: 150,
                          keyboard: .numberPad, focus: $focus, field: .bag)
                StepField(title: "Takeoff fuel", unit: "gal", text: bind(\.fuel), step: 1, lo: 0, hi: 50,
                          keyboard: .decimalPad, focus: $focus, field: .fuel)
                StepField(title: "Fuel burned", unit: "gal", text: bind(\.burn), step: 1, lo: 0, hi: 50,
                          keyboard: .decimalPad, focus: $focus, field: .burn)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Category").font(Theme.body(15, .semibold)).foregroundColor(Theme.ink)
                    HStack(spacing: 0) {
                        segment("Utility", .utility)
                        segment("Aerobatic", .aerobatic)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.rule, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .accessibilityLabel("Load")
    }

    private func segment(_ title: String, _ c: WBCategory) -> some View {
        let on = inp.cat == c
        return Button { inp.cat = c } label: {
            Text(title)
                .font(Theme.body(14, on ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundColor(on ? Theme.panel : Theme.ink)
                .background(on ? Theme.accent : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Empty weight editor

    private func emptyWeightPanel(_ r: WBResult?, proxy: ScrollViewProxy) -> some View {
        Panel {
            HStack {
                PanelTitle("Empty weight (scale readings)")
                Spacer(minLength: 8)
                Button { toggleEmptyWeight(proxy) } label: {
                    Text("Done").font(Theme.body(15, .semibold))
                        .padding(.horizontal, 16).frame(minHeight: 42)
                        .foregroundColor(Theme.accent)
                        .background(Theme.accentSoft)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Text("Change these when equipment changes or the airplane is reweighed. Weights are what each scale reads with the airplane level, full oil and empty tanks.")
                .font(Theme.body(14)).foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    colHead("Weight, lb")
                    colHead("Arm, in")
                }
                ewRow("Left main", \.wL, .wL, \.aL, .aL)
                ewRow("Right main", \.wR, .wR, \.aR, .aR)
                ewRow("Tailwheel", \.wT, .wT, \.aT, .aT)
            }

            emptyWeightSummary
            Button { inp.restoreWeighing() } label: {
                Text("Restore February 4, 2024 weighing")
                    .font(Theme.body(14)).underline().foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)

            DisclosureGroup(isExpanded: $addOpen) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        (Text("Weight change, lb ").font(Theme.body(15, .semibold))
                         + Text("(− to remove)").font(Theme.body(13)).foregroundColor(Theme.muted))
                        NumberBox(text: bind(\.dW), keyboard: .numbersAndPunctuation, focus: $focus, field: .dW)
                    }
                    GridRow {
                        Text("Item arm, in").font(Theme.body(15, .semibold))
                        NumberBox(text: bind(\.dA), keyboard: .decimalPad, focus: $focus, field: .dA)
                    }
                }
                .padding(.top, 8)
                Text("Measure the arm from the datum, 72 in forward of the wing leading edge. The change is added to the empty weight and moment above.")
                    .font(Theme.body(14)).foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } label: {
                Text("Add or remove an item instead of reweighing")
                    .font(Theme.body(15, .semibold)).foregroundColor(Theme.accent)
            }
            .padding(.top, 4)
        }
    }

    private func colHead(_ s: String) -> some View {
        Text(s.uppercased()).font(Theme.display(12, .semibold)).tracking(0.7).foregroundColor(Theme.muted)
    }

    private func ewRow(_ title: String,
                       _ w: WritableKeyPath<WBInputs, String>, _ wf: WBField,
                       _ a: WritableKeyPath<WBInputs, String>, _ af: WBField) -> some View {
        GridRow {
            Text(title).font(Theme.body(15, .semibold)).foregroundColor(Theme.ink)
            NumberBox(text: bind(w), keyboard: .decimalPad, focus: $focus, field: wf)
                .accessibilityLabel("\(title) weight, pounds")
            NumberBox(text: bind(a), keyboard: .decimalPad, focus: $focus, field: af)
                .accessibilityLabel("\(title) arm, inches")
        }
    }

    private var emptyWeightSummary: some View {
        let e = WB.emptyWeight(inp)
        let text: Text
        if e.weight > 0 {
            var t = Text("Empty weight ")
                + Text("\(WB.fmt(e.weight, 1)) lb").font(Theme.data(15)).foregroundColor(Theme.accent)
                + Text(" at ")
                + Text("\(WB.fmt(e.moment / e.weight, 2)) in").font(Theme.data(15)).foregroundColor(Theme.accent)
                + Text(", moment \(WB.fmt(e.moment, 1)) in-lb")
            if WB.emptyWeightChanged(inp) {
                t = t + Text(" (2024 weighing: 1,247 lb at 79.75 in)").font(Theme.body(14)).foregroundColor(Theme.muted)
            }
            text = t
        } else {
            text = Text("Enter scale weights.")
        }
        return text.font(Theme.body(15)).foregroundColor(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: Chart legend and notes

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                swatch(Theme.accent, "Utility envelope")
                swatch(Color(Palette.env2), "Aerobatic envelope")
            }
            Text("● takeoff   ○ landing   ■ zero fuel")
        }
        .font(Theme.body(13)).foregroundColor(Theme.muted)
    }

    private func swatch(_ c: Color, _ s: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 12)
            Text(s)
        }
    }

    private var notes: some View {
        Panel {
            PanelTitle("Limits and sources")
            note(verified: true, "Empty weight 1,247 lb, empty CG 79.75 in, moment 99,447.30 in-lb, weighed February 4, 2024: left main 599 lb, right main 583 lb, tail 65 lb. The sheet prints the main-wheel arms rounded to 71.33 and 71.63 in; the app uses 71.325 and 71.625 in, which reproduce the sheet’s moments exactly. Tail arm 230.25 in. Arms: seats 99.83 in, baggage 129.48 in, fuel 81.97 in. Datum 72 in forward of the wing leading edge. Source: N721NE Weight and Balance (RV-14 / Registration and Airworthiness), page 1.")
            note(verified: true, "CG range 82.08 to 88.24 in (18% to 29% of wing chord), gross weight 2,050 lb. Aerobatic: 1,900 lb maximum and aft CG 86.0 in (25% of chord). Source: Van's RV-14 Weight and Balance Data Quick Reference (RV-14 / RV-14 W&B Reference.pdf), Limits section.")
            note(verified: false, "Your N721NE Weight and Balance sheet lists the aerobatic gross weight as 1,950 lb, but Van's quick reference says aerobatic flight must not be done above 1,900 lb because that is a structural limit. This app uses Van's 1,900 lb. Check which number is in your operating limitations.")
            note(verified: true, "Baggage limit 100 lb and fuel capacity 50 gal: Van's RV-14 specification sheet (14FLY-e, February 1, 2019). Fuel at 6.0 lb/gal.")
            note(verified: false, "Burning fuel moves the CG aft, because the fuel arm (81.97 in) is ahead of the loaded CG. Check the landing point as well as the takeoff point. Oil is included in the empty weight (weighed with full oil). This is a planning aid; your aircraft's own weight and balance record governs.")
        }
    }

    private func note(verified: Bool, _ s: String) -> some View {
        (Text(verified ? "VERIFIED  " : "NOTE  ")
            .font(Theme.display(12, .semibold))
            .foregroundColor(verified ? Theme.accent : Theme.warn)
         + Text(s))
            .font(Theme.body(15))
            .foregroundColor(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Pieces

struct StatusBar: View {
    let result: WBResult

    var body: some View {
        let (line, fill): (Color, Color) = {
            switch result.level {
            case .ok: return (Theme.ok, Theme.okSoft)
            case .warn: return (Theme.warn, Theme.warnSoft)
            case .bad: return (Theme.bad, Theme.badSoft)
            }
        }()
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(line).frame(width: 12, height: 12).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(result.statusText)
                .font(Theme.body(16, .semibold))
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .background(fill)
        .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 4) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct Tile: View {
    let key: String
    let value: String
    let unit: String
    var bad = false
    var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key.uppercased())
                .font(Theme.display(11.5, .semibold))
                .tracking(1.0)
                .foregroundColor(Theme.muted)
            (Text(value).font(Theme.data(18)).foregroundColor(bad ? Theme.bad : Theme.accent)
             + Text(unit.isEmpty ? "" : " " + unit).font(Theme.body(12.5)).foregroundColor(Theme.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(highlighted ? Theme.accentSoft : Theme.panel)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Number box used in the empty weight editor.
struct NumberBox: View {
    @Binding var text: String
    let keyboard: UIKeyboardType
    var focus: FocusState<WBField?>.Binding
    let field: WBField

    var body: some View {
        TextField("", text: $text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.trailing)
            .font(Theme.data(16, .regular))
            .foregroundColor(Theme.ink)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(Theme.bg)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .focused(focus, equals: field)
    }
}

/// Load entry with ▼ and ▲ buttons, like the web app.
struct StepField: View {
    let title: String
    let unit: String
    @Binding var text: String
    let step: Double
    let lo: Double
    let hi: Double
    let keyboard: UIKeyboardType
    var focus: FocusState<WBField?>.Binding
    let field: WBField

    private var stepName: String {
        let n = WB.plain(step)
        return unit == "lb" ? "\(n) pounds" : (step == 1 ? "1 gallon" : "\(n) gallons")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(title).font(Theme.body(15, .semibold)).foregroundColor(Theme.ink)
             + Text(" " + unit).font(Theme.body(13)).foregroundColor(Theme.muted))
            HStack(spacing: 4) {
                stepButton("▼", -step).accessibilityLabel("\(title) minus \(stepName)")
                TextField("", text: $text)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.center)
                    .font(Theme.data(16, .regular))
                    .foregroundColor(Theme.ink)
                    .padding(.vertical, 8)
                    .frame(minHeight: 42)
                    .background(Theme.bg)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.rule, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .focused(focus, equals: field)
                    .accessibilityLabel("\(title), \(unit == "lb" ? "pounds" : "gallons")")
                stepButton("▲", step).accessibilityLabel("\(title) plus \(stepName)")
            }
        }
    }

    private func stepButton(_ symbol: String, _ d: Double) -> some View {
        Button {
            text = WB.stepped(text, by: d, min: lo, max: hi)
        } label: {
            Text(symbol)
                .font(.system(size: 14))
                .frame(width: 40, height: 42)
                .foregroundColor(Theme.accent)
                .background(Theme.accentSoft)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(StepPress())
    }
}

/// Fills the step button with the accent color while pressed (the web app's :active look).
struct StepPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .colorMultiply(configuration.isPressed ? Theme.accent : .white)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct LoadingTable: View {
    let result: WBResult

    private struct Row {
        let item: String
        let weight: String
        let arm: String
        let moment: String
        var total = false
    }

    private var rows: [Row] {
        let r = result
        let f = WB.fmt
        return [
            Row(item: "Empty aircraft", weight: f(r.emptyWeight, 1), arm: f(r.emptyCG, 2), moment: f(r.emptyMoment, 1)),
            Row(item: "Pilot", weight: f(r.pilot, 1), arm: f(Limits.seatArm, 2), moment: f(r.pilot * Limits.seatArm, 1)),
            Row(item: "Passenger", weight: f(r.passenger, 1), arm: f(Limits.seatArm, 2), moment: f(r.passenger * Limits.seatArm, 1)),
            Row(item: "Baggage", weight: f(r.baggage, 1), arm: f(Limits.baggageArm, 2), moment: f(r.baggage * Limits.baggageArm, 1)),
            Row(item: "Fuel at takeoff (\(f(r.fuelGal, 1)) gal)", weight: f(r.fuelW, 1), arm: f(Limits.fuelArm, 2), moment: f(r.fuelW * Limits.fuelArm, 1)),
            Row(item: "Takeoff", weight: f(r.toW, 1), arm: f(r.toCG, 2), moment: f(r.toM, 1), total: true),
            Row(item: "Fuel burned (\(f(r.burnGal, 1)) gal)", weight: "−" + f(r.burnW, 1), arm: f(Limits.fuelArm, 2), moment: "−" + f(r.burnW * Limits.fuelArm, 1)),
            Row(item: "Landing", weight: f(r.lW, 1), arm: f(r.lCG, 2), moment: f(r.lM, 1), total: true),
            Row(item: "Zero fuel", weight: f(r.zfW, 1), arm: f(r.zfCG, 2), moment: f(r.zfM, 1)),
        ]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 0) {
                GridRow {
                    head("Item").gridColumnAlignment(.leading)
                    head("Weight, lb")
                    head("Arm, in")
                    head("Moment, in-lb")
                }
                Rectangle().fill(Theme.rule).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    if row.total {
                        Rectangle().fill(Theme.rule).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                    }
                    GridRow {
                        Text(row.item)
                            .font(Theme.body(14, row.total ? .semibold : .regular))
                            .foregroundColor(Theme.ink)
                            .padding(.vertical, 7)
                            .gridColumnAlignment(.leading)
                        cell(row.weight, row.total)
                        cell(row.arm, row.total)
                        cell(row.moment, row.total)
                    }
                    Rectangle().fill(Theme.rule).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                }
            }
            .frame(minWidth: 440, alignment: .leading)
        }
    }

    private func head(_ s: String) -> some View {
        Text(s.uppercased()).font(Theme.display(12, .semibold)).tracking(0.7).foregroundColor(Theme.muted)
            .padding(.vertical, 7)
    }

    private func cell(_ s: String, _ bold: Bool) -> some View {
        Text(s).font(Theme.data(13.5, bold ? .semibold : .regular))
            .foregroundColor(Theme.ink)
            .padding(.vertical, 7)
    }
}
