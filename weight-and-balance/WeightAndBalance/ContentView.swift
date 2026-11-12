import SwiftUI

struct ContentView: View {
    @State private var p: WBProfile
    @State private var setupOpen: Bool
    @State private var firstRun: Bool
    @State private var ewOpen = false
    @State private var limOpen: Bool
    @State private var addOpen = false
    @State private var restoreAsk = false
    @FocusState private var focus: String?

    init() {
        let saved = Store.load()
        _p = State(initialValue: saved ?? WBProfile.new(reg: "", model: "rv14"))
        _firstRun = State(initialValue: saved == nil)
        _setupOpen = State(initialValue: saved == nil || DemoMode.screen == "setup")
        _limOpen = State(initialValue: DemoMode.screen == "limits")
    }

    // MARK: Bindings

    private func bind(_ kp: WritableKeyPath<WBProfile, String>) -> Binding<String> {
        Binding(get: { p[keyPath: kp] }, set: { p[keyPath: kp] = $0 })
    }

    private func station(_ i: Int, _ kp: WritableKeyPath<WBStation, String>) -> Binding<String> {
        Binding(get: { i < p.stations.count ? p.stations[i][keyPath: kp] : "" },
                set: { if i < p.stations.count { p.stations[i][keyPath: kp] = $0 } })
    }

    private func category(_ i: Int, _ kp: WritableKeyPath<WBCat, String>) -> Binding<String> {
        Binding(get: { i < p.cats.count ? p.cats[i][keyPath: kp] : "" },
                set: { if i < p.cats.count { p.cats[i][keyPath: kp] = $0 } })
    }

    var body: some View {
        let r = WB.compute(p)
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        statusView(r)
                        tiles(r, proxy: proxy).id("tiles")
                        loadPanel
                        if ewOpen { emptyWeightPanel(proxy: proxy).id("ew") }
                        if limOpen { limitsPanel(proxy: proxy).id("lim") }
                        if let r {
                            Panel {
                                PanelTitle("CG envelope")
                                EnvelopeChart(profile: p, result: r)
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
        .onChange(of: p) { Store.save($0) }
        .sheet(isPresented: $setupOpen) {
            SetupView(profile: p, first: firstRun) { reg, model, gear in
                p.reg = WBProfile.cleanReg(reg)
                p.gear = gear
                if firstRun || model != p.model { p.applyPreset(model) }
                firstRun = false
                Store.save(p)
                setupOpen = false
            }
            .interactiveDismissDisabled(firstRun)
        }
        .confirmationDialog("Replace the limits and arms with the \(WBData.preset(p.model).name) defaults? Your scale readings and loads are kept.",
                            isPresented: $restoreAsk, titleVisibility: .visible) {
            Button("Restore defaults", role: .destructive) { p.applyPreset(p.model) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerLine)
                    .font(Theme.display(12, .semibold))
                    .tracking(1.4)
                    .foregroundColor(Theme.accent)
                Text("Weight & Balance")
                    .font(Theme.display(24, .bold))
                    .foregroundColor(Theme.ink)
            }
            Spacer(minLength: 8)
            Button { focus = nil; setupOpen = true } label: { pill("Aircraft") }
                .buttonStyle(.plain)
                .accessibilityHint("Change the registration, model or landing gear")
        }
    }

    private var headerLine: String {
        let reg = p.reg.isEmpty ? "NO REGISTRATION" : p.reg
        let m = p.modelName
        return m.isEmpty ? reg : "\(reg) · \(m)"
    }

    private func pill(_ title: String) -> some View {
        Text(title).font(Theme.body(15, .semibold))
            .padding(.horizontal, 16).frame(minHeight: 42)
            .foregroundColor(Theme.accent)
            .background(Theme.accentSoft)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func statusView(_ r: WBResult?) -> some View {
        if let r {
            StatusBar(level: r.level, text: r.statusText)
        } else {
            StatusBar(level: .warn,
                      text: "To see results, enter \(WB.missing(p).joined(separator: " and ")). Tap the tiles marked ✎.")
        }
    }

    // MARK: Result tiles

    private func pct(_ cg: Double) -> String {
        guard let m = WB.mac(p, cg) else { return "in" }
        return "in · \(WB.fmt(m, 1))%"
    }

    private func tiles(_ r: WBResult?, proxy: ScrollViewProxy) -> some View {
        let dash = "—"
        let e = WB.emptyWeight(p)
        let cat = p.activeCat
        let ewTile = Button { toggle("ew", proxy) } label: {
            Tile(key: "Empty weight ✎",
                 value: e.weight > 0 ? WB.fmt(e.weight) : dash,
                 unit: e.weight > 0 ? "lb · \(WB.fmt(e.moment / e.weight, 2)) in" : "",
                 highlighted: ewOpen)
        }
        .buttonStyle(.plain)
        .accessibilityHint(ewOpen ? "Closes the empty weight editor" : "Opens the empty weight editor")
        let limTile = Button { toggle("lim", proxy) } label: {
            Tile(key: "Limits and arms ✎",
                 value: cat.ready ? WB.fmt(WB.value(cat.gross)) : dash,
                 unit: cat.ready ? "lb · \(WB.plain(WB.value(cat.fwd)))–\(WB.plain(WB.value(cat.aft))) in" : "not set",
                 highlighted: limOpen)
        }
        .buttonStyle(.plain)
        .accessibilityHint(limOpen ? "Closes the limits and arms editor" : "Opens the limits and arms editor")

        return Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                Tile(key: "Takeoff weight", value: r.map { WB.fmt($0.toW) } ?? dash, unit: "lb",
                     bad: r?.overWeight ?? false)
                Tile(key: "Takeoff CG", value: r.map { WB.fmt($0.toCG, 2) } ?? dash,
                     unit: r.map { pct($0.toCG) } ?? "",
                     bad: r.map { !$0.inCG($0.toCG) } ?? false)
            }
            GridRow {
                Tile(key: "Landing weight", value: r.map { WB.fmt($0.lW) } ?? dash, unit: "lb")
                Tile(key: "Landing CG", value: r.map { WB.fmt($0.lCG, 2) } ?? dash,
                     unit: r.map { pct($0.lCG) } ?? "",
                     bad: r.map { !$0.inCG($0.lCG) } ?? false)
            }
            GridRow {
                Tile(key: "Below max weight", value: r.map { WB.fmt($0.margin) } ?? dash, unit: "lb",
                     bad: r?.overWeight ?? false)
                ewTile
            }
            GridRow {
                Tile(key: "Zero-fuel CG", value: r.map { WB.fmt($0.zfCG, 2) } ?? dash,
                     unit: r.map { pct($0.zfCG) } ?? "",
                     bad: r.map { !$0.inCG($0.zfCG) } ?? false)
                Tile(key: "Max fuel this load",
                     value: r.map { WB.fmt(($0.maxFuel * 10).rounded(.down) / 10, 1) } ?? dash, unit: "gal")
            }
            GridRow {
                limTile
                Tile(key: "Category", value: cat.name.isEmpty ? dash : cat.name, unit: "")
            }
        }
        .background(Theme.rule)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weight and balance results")
    }

    private func toggle(_ which: String, _ proxy: ScrollViewProxy) {
        let opening = which == "ew" ? !ewOpen : !limOpen
        withAnimation(.easeInOut(duration: 0.2)) {
            if which == "ew" { ewOpen = opening } else { limOpen = opening }
        }
        if !opening { focus = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation { proxy.scrollTo(opening ? which : "tiles", anchor: opening ? .top : .center) }
        }
    }

    // MARK: Load inputs

    private var fuelTop: Double {
        let cap = WB.positive(p.fuelCap)
        return cap > 0 ? cap : 500
    }

    private var loadPanel: some View {
        Panel {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                      alignment: .leading, spacing: 12) {
                ForEach(Array(p.stations.enumerated()), id: \.element.id) { i, s in
                    StepField(title: s.name.isEmpty ? "Item" : s.name, unit: "lb", text: station(i, \.load),
                              step: 5, lo: 0, hi: 1000,
                              keyboard: .numberPad, focus: $focus, field: "load\(i)")
                }
                StepField(title: "Takeoff fuel", unit: "gal", text: bind(\.fuel), step: 1, lo: 0, hi: fuelTop,
                          keyboard: .decimalPad, focus: $focus, field: "fuel")
                StepField(title: "Fuel burned", unit: "gal", text: bind(\.burn), step: 1, lo: 0, hi: fuelTop,
                          keyboard: .decimalPad, focus: $focus, field: "burn")
                if p.twoCats && p.cats.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Category").font(Theme.body(15, .semibold)).foregroundColor(Theme.ink)
                        HStack(spacing: 0) {
                            segment(0)
                            segment(1)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.rule, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .accessibilityLabel("Load")
    }

    private func segment(_ i: Int) -> some View {
        let on = p.cat == i
        let name = p.cats[i].name.isEmpty ? "Category \(i + 1)" : p.cats[i].name
        return Button { p.cat = i } label: {
            Text(name)
                .font(Theme.body(14, on ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundColor(on ? Theme.panel : Theme.ink)
                .background(on ? Theme.accent : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Empty weight editor

    private func hint(_ s: String) -> some View {
        Text(s).font(Theme.body(14)).foregroundColor(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func panelHead(_ title: String, _ which: String, _ proxy: ScrollViewProxy) -> some View {
        HStack {
            PanelTitle(title)
            Spacer(minLength: 8)
            Button { toggle(which, proxy) } label: { pill("Done") }
                .buttonStyle(.plain)
        }
    }

    private func emptyWeightPanel(proxy: ScrollViewProxy) -> some View {
        Panel {
            panelHead("Empty weight (scale readings)", "ew", proxy)
            hint("Weights are what each scale reads with the airplane level, in the condition your empty weight is defined (for most RVs: full oil, unusable fuel only). Arms are measured from the datum. If you only have a total empty weight and empty CG, enter them on one line and leave the others at 0.")

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    colHead("Weight, lb")
                    colHead("Arm, in")
                }
                ewRow("Left main", \.wL, "wL", \.aL, "aL")
                ewRow("Right main", \.wR, "wR", \.aR, "aR")
                ewRow(p.gear.thirdWheel, \.w3, "w3", \.a3, "a3")
            }

            emptyWeightSummary

            DisclosureGroup(isExpanded: $addOpen) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        (Text("Weight change, lb ").font(Theme.body(15, .semibold))
                         + Text("(− to remove)").font(Theme.body(13)).foregroundColor(Theme.muted))
                        NumberBox(text: bind(\.dW), keyboard: .numbersAndPunctuation, focus: $focus, field: "dW")
                    }
                    GridRow {
                        Text("Item arm, in").font(Theme.body(15, .semibold))
                        NumberBox(text: bind(\.dA), keyboard: .decimalPad, focus: $focus, field: "dA")
                    }
                }
                .padding(.top, 8)
                hint("The change is added to the empty weight and moment above.")
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
            .fixedSize(horizontal: false, vertical: true)
    }

    private func ewRow(_ title: String,
                       _ w: WritableKeyPath<WBProfile, String>, _ wf: String,
                       _ a: WritableKeyPath<WBProfile, String>, _ af: String) -> some View {
        GridRow {
            Text(title).font(Theme.body(15, .semibold)).foregroundColor(Theme.ink)
            NumberBox(text: bind(w), keyboard: .decimalPad, focus: $focus, field: wf)
                .accessibilityLabel("\(title) weight, pounds")
            NumberBox(text: bind(a), keyboard: .decimalPad, focus: $focus, field: af)
                .accessibilityLabel("\(title) arm, inches")
        }
    }

    private var emptyWeightSummary: some View {
        let e = WB.emptyWeight(p)
        let text: Text
        if e.weight > 0 {
            text = Text("Empty weight ")
                + Text("\(WB.fmt(e.weight, 1)) lb").font(Theme.data(15)).foregroundColor(Theme.accent)
                + Text(" at ")
                + Text("\(WB.fmt(e.moment / e.weight, 2)) in").font(Theme.data(15)).foregroundColor(Theme.accent)
                + Text(", moment \(WB.fmt(e.moment, 1)) in-lb")
        } else {
            text = Text("Enter scale weights and arms.")
        }
        return text.font(Theme.body(15)).foregroundColor(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: Limits and arms editor

    private func limitsPanel(proxy: ScrollViewProxy) -> some View {
        Panel {
            panelHead("Limits and arms", "lim", proxy)
            hint("Change these to match your aircraft's operating limitations and weight and balance record. All arms are inches aft of the datum.")

            Toggle(isOn: Binding(get: { p.twoCats }, set: { p.twoCats = $0; if !$0 { p.cat = 0 } })) {
                Text("Use a second category (for example aerobatic)")
                    .font(Theme.body(15, .semibold)).foregroundColor(Theme.ink)
            }

            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    colHead("Envelope")
                    colHead("Max weight, lb")
                    colHead("Fwd CG, in")
                    colHead("Aft CG, in")
                }
                ForEach(0..<min(p.cats.count, 2), id: \.self) { i in
                    catRow(i)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    colHead("Loading point")
                    colHead("Arm, in")
                    colHead("Limit, lb")
                }
                ForEach(Array(p.stations.enumerated()), id: \.element.id) { i, s in
                    stationRow(i, s.name)
                }
                GridRow {
                    (Text("Fuel tanks ").font(Theme.body(15, .semibold))
                     + Text("(limit in gal)").font(Theme.body(13)).foregroundColor(Theme.muted))
                    NumberBox(text: bind(\.fuelArm), keyboard: .decimalPad, focus: $focus, field: "fuelArm")
                        .accessibilityLabel("Fuel tank arm, inches")
                    NumberBox(text: bind(\.fuelCap), keyboard: .decimalPad, focus: $focus, field: "fuelCap")
                        .accessibilityLabel("Fuel capacity, gallons")
                }
            }
            .padding(.top, 6)
            hint("Leave a limit blank for none.")

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                smallRow("Fuel weight, lb/gal", \.lbGal, "lbGal")
                smallRow("Wing leading edge, in aft of datum", \.le, "le")
                smallRow("Wing chord, in", \.chord, "chord")
            }
            hint("Leading edge and chord are only used to show CG as a percent of chord. Leave them blank to hide it.")

            if p.model != "custom" {
                Button { focus = nil; restoreAsk = true } label: {
                    Text("Restore \(WBData.preset(p.model).name) default limits and arms")
                        .font(Theme.body(14)).underline().foregroundColor(Theme.accent)
                        .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func catRow(_ i: Int) -> some View {
        let dim: Double = i == 1 && !p.twoCats ? 0.45 : 1
        return GridRow {
            NumberBox(text: category(i, \.name), keyboard: .default, focus: $focus, field: "cn\(i)", isName: true)
                .opacity(dim)
                .accessibilityLabel("Envelope \(i + 1) name")
            NumberBox(text: category(i, \.gross), keyboard: .decimalPad, focus: $focus, field: "cg\(i)")
                .opacity(dim)
                .accessibilityLabel("Envelope \(i + 1) maximum weight, pounds")
            NumberBox(text: category(i, \.fwd), keyboard: .decimalPad, focus: $focus, field: "cf\(i)")
                .opacity(dim)
                .accessibilityLabel("Envelope \(i + 1) forward CG limit, inches")
            NumberBox(text: category(i, \.aft), keyboard: .decimalPad, focus: $focus, field: "ca\(i)")
                .opacity(dim)
                .accessibilityLabel("Envelope \(i + 1) aft CG limit, inches")
        }
    }

    private func stationRow(_ i: Int, _ name: String) -> some View {
        GridRow {
            NumberBox(text: station(i, \.name), keyboard: .default, focus: $focus, field: "sn\(i)", isName: true)
                .accessibilityLabel("Loading point \(i + 1) name")
            NumberBox(text: station(i, \.arm), keyboard: .decimalPad, focus: $focus, field: "sa\(i)")
                .accessibilityLabel("\(name) arm, inches")
            NumberBox(text: station(i, \.max), keyboard: .decimalPad, focus: $focus, field: "sm\(i)")
                .accessibilityLabel("\(name) limit, pounds")
        }
    }

    private func smallRow(_ title: String, _ kp: WritableKeyPath<WBProfile, String>, _ field: String) -> some View {
        GridRow {
            Text(title).font(Theme.body(15, .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            NumberBox(text: bind(kp), keyboard: .decimalPad, focus: $focus, field: field)
                .frame(width: 96)
                .accessibilityLabel(title)
        }
    }

    // MARK: Chart legend and notes

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                if let c = p.cats.first { swatch(Theme.accent, "\(c.name) envelope") }
                if p.twoCats && p.cats.count > 1 { swatch(Color(Palette.env2), "\(p.cats[1].name) envelope") }
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
        let d = WBData.preset(p.model)
        let lb = WB.value(p.lbGal) > 0 ? WB.value(p.lbGal) : 6
        return Panel {
            PanelTitle("Limits and sources")
            note(source: p.model != "custom", d.note)
            if p.model != "custom" {
                note(source: false, "These are starting values for a standard \(d.name). The builder sets the gross weight of an amateur-built aircraft, and your airplane may differ. Check every number against your own operating limitations and weight and balance record, and change them under Limits and arms.")
            }
            note(source: false, "Wheel arms and scale weights come from your own weighing; none are pre-filled. Fuel is figured at \(WB.plain(lb)) lb/gal. Fuel burn moves the CG, so check the landing and zero-fuel points as well as takeoff.")
            note(source: false, "This is a planning aid, not an approved source of data. The pilot in command is responsible for loading the aircraft within its limits. Not affiliated with or endorsed by Van's Aircraft, Inc.")
        }
    }

    private func note(source: Bool, _ s: String) -> some View {
        (Text(source ? "SOURCE  " : "NOTE  ")
            .font(Theme.display(12, .semibold))
            .foregroundColor(source ? Theme.accent : Theme.warn)
         + Text(s))
            .font(Theme.body(15))
            .foregroundColor(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Aircraft setup

/// Shown on first launch and from the Aircraft button: registration, model and landing gear.
struct SetupView: View {
    let first: Bool
    let onSave: (String, String, WBGear) -> Void
    private let startModel: String

    @State private var reg: String
    @State private var model: String
    @State private var gear: WBGear
    @Environment(\.dismiss) private var dismiss

    init(profile: WBProfile, first: Bool, onSave: @escaping (String, String, WBGear) -> Void) {
        self.first = first
        self.onSave = onSave
        self.startModel = profile.model
        _reg = State(initialValue: profile.reg)
        _model = State(initialValue: profile.model)
        _gear = State(initialValue: profile.gear)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your aircraft").font(Theme.display(26, .bold)).foregroundColor(Theme.ink)
                Text(first
                     ? "Enter your registration and pick your model. The model fills in Van's published limits and arms, and you can change any of them afterward."
                     : "Changing the model replaces the limits and arms with that model's defaults. Your scale readings are kept.")
                    .font(Theme.body(15)).foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    label("Registration")
                    TextField("N123AB", text: $reg)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(Theme.data(18, .regular))
                        .padding(10)
                        .background(Theme.bg)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.rule, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Registration")
                }

                VStack(alignment: .leading, spacing: 4) {
                    label("Model")
                    Picker("Model", selection: $model) {
                        ForEach(WBData.presets) { d in
                            Text(d.menuName).tag(d.id)
                        }
                        Text(WBData.custom.menuName).tag("custom")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 6)
                    .background(Theme.bg)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.rule, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    label("Landing gear")
                    Picker("Landing gear", selection: $gear) {
                        Text("Tailwheel").tag(WBGear.tail)
                        Text("Nosewheel").tag(WBGear.nose)
                    }
                    .pickerStyle(.segmented)
                }

                Text(WBData.preset(model).note)
                    .font(Theme.body(14)).foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This is a planning aid. Your aircraft's own weight and balance record and operating limitations govern.")
                    .font(Theme.body(14)).foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    if !first {
                        Button { dismiss() } label: {
                            Text("Cancel").font(Theme.body(16, .semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundColor(Theme.accent)
                                .background(Theme.accentSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { onSave(reg, model, gear) } label: {
                        Text(first ? "Start" : "Save").font(Theme.body(16, .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundColor(Theme.panel)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Theme.panel.ignoresSafeArea())
        .tint(Theme.accent)
        .onChange(of: model) { m in
            if first || m != startModel { gear = WBData.preset(m).gear }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(Theme.body(15, .semibold)).foregroundColor(Theme.ink)
    }
}

// MARK: - Pieces

struct StatusBar: View {
    let level: WBResult.Level
    let text: String

    var body: some View {
        let (line, fill): (Color, Color) = {
            switch level {
            case .ok: return (Theme.ok, Theme.okSoft)
            case .warn: return (Theme.warn, Theme.warnSoft)
            case .bad: return (Theme.bad, Theme.badSoft)
            }
        }()
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(line).frame(width: 12, height: 12).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(text)
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
    var focus: FocusState<String?>.Binding
    let field: String
    /// True for name boxes: plain text, left aligned.
    var isName = false

    var body: some View {
        TextField("", text: $text)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .multilineTextAlignment(isName ? .leading : .trailing)
            .font(isName ? Theme.body(15) : Theme.data(15, .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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
    var focus: FocusState<String?>.Binding
    let field: String

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
        var out = [Row(item: "Empty aircraft", weight: f(r.emptyWeight, 1), arm: f(r.emptyCG, 2), moment: f(r.emptyMoment, 1))]
        for x in r.rows {
            out.append(Row(item: x.name, weight: f(x.weight, 1), arm: f(x.arm, 2), moment: f(x.moment, 1)))
        }
        out.append(Row(item: "Fuel at takeoff (\(f(r.fuelGal, 1)) gal)", weight: f(r.fuelW, 1), arm: f(r.fuelArm, 2), moment: f(r.fuelW * r.fuelArm, 1)))
        out.append(Row(item: "Takeoff", weight: f(r.toW, 1), arm: f(r.toCG, 2), moment: f(r.toM, 1), total: true))
        out.append(Row(item: "Fuel burned (\(f(r.burnGal, 1)) gal)", weight: "−" + f(r.burnW, 1), arm: f(r.fuelArm, 2), moment: "−" + f(r.burnW * r.fuelArm, 1)))
        out.append(Row(item: "Landing", weight: f(r.lW, 1), arm: f(r.lCG, 2), moment: f(r.lM, 1), total: true))
        out.append(Row(item: "Zero fuel", weight: f(r.zfW, 1), arm: f(r.zfCG, 2), moment: f(r.zfM, 1)))
        return out
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
