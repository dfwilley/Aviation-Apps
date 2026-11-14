import SwiftUI

/// The live one-line diagram of the electrical system.
/// Green = alternator power, amber = battery power, gray = no current, red = failed or dead.
/// Touch an alternator, a battery or the EMER box to fail it or turn it back on.
struct DiagramView: View {
    @Binding var inputs: ElectricalInputs
    let result: ElectricalResult

    // Where the touchable boxes sit on the drawing grid.
    private static let mainAltBox = CGRect(x: 8, y: 20, width: 80, height: 36)
    private static let battery1Box = CGRect(x: 8, y: 70, width: 80, height: 36)
    private static let backupAltBox = CGRect(x: 8, y: 170, width: 80, height: 36)
    private static let battery2Box = CGRect(x: 8, y: 220, width: 80, height: 36)
    private static let emergencyBox = CGRect(x: 150, y: 131, width: 44, height: 22)

    /// The drawing is laid out on a 340 x 264 grid and scaled to fit.
    static let designSize = CGSize(width: 340, height: 264)

    private enum Kind { case alt, battery, off, dead }

    var body: some View {
        Canvas { context, size in
            let s = size.width / Self.designSize.width
            draw(context, s)
        }
        .aspectRatio(Self.designSize.width / Self.designSize.height, contentMode: .fit)
        .accessibilityLabel("Electrical system diagram")
        .overlay(
            GeometryReader { geo in
                let s = geo.size.width / Self.designSize.width
                ZStack {
                    touchArea(Self.mainAltBox, s, "Main alternator", on: inputs.mainAltOK) { inputs.mainAltOK.toggle() }
                    touchArea(Self.battery1Box, s, "Battery 1", on: inputs.battery1OK) { inputs.battery1OK.toggle() }
                    touchArea(Self.backupAltBox, s, "Backup alternator", on: inputs.backupAltOK) { inputs.backupAltOK.toggle() }
                    touchArea(Self.battery2Box, s, "Battery 2", on: inputs.battery2OK) { inputs.battery2OK.toggle() }
                    touchArea(Self.emergencyBox, s, "Emergency power", on: inputs.emergencyPower, pad: 9) {
                        inputs.emergencyPower.toggle()
                    }
                }
            }
        )
    }

    /// An invisible button laid over one box of the drawing. `pad` makes a small box easier to hit.
    private func touchArea(_ r: CGRect, _ s: CGFloat, _ name: String, on: Bool, pad: CGFloat = 3,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Color.clear
        }
        .buttonStyle(.plain)
        .frame(width: (r.width + 2 * pad) * s, height: (r.height + 2 * pad) * s)
        .contentShape(Rectangle())
        .position(x: r.midX * s, y: r.midY * s)
        .accessibilityLabel(name)
        .accessibilityValue(on ? "on" : "off")
    }

    // MARK: - Drawing

    private func color(_ k: Kind) -> Color {
        switch k {
        case .alt: return Theme.alt
        case .battery: return Theme.battery
        case .off: return Theme.off
        case .dead: return Theme.fail
        }
    }

    private func draw(_ ctx: GraphicsContext, _ s: CGFloat) {
        let f = result.now

        // What is on each wire right now.
        let sideA: Kind = inputs.mainAltOK ? .alt : (f.mainBusPowered ? .battery : .off)
        let sideB: Kind = inputs.backupAltOK ? .alt : (f.essentialFromBattery2 > 0.01 ? .battery : .off)
        let mainBus: Kind = !f.mainBusPowered ? .dead : (f.mainFromBattery1 > 0.01 || !inputs.mainAltOK ? .battery : .alt)
        let d1: Kind = !f.sideAFeedsEssential ? .off : (f.essentialFromBattery1 > 0.01 ? .battery : .alt)
        let d2: Kind = !f.sideBFeedsEssential ? .off : (f.essentialFromBattery2 > 0.01 ? .battery : .alt)
        let essential: Kind = !f.essentialPowered ? .dead
            : (f.essentialFromBattery1 + f.essentialFromBattery2 > 0.01 ? .battery : .alt)
        let bat1Wire: Kind = wire(for: result.battery1State)
        let bat2Wire: Kind = wire(for: result.battery2State)

        // BAT1/ALT side
        line(ctx, s, [(88, 38), (100, 38)], inputs.mainAltOK ? .alt : .off)
        line(ctx, s, [(88, 88), (100, 88)], bat1Wire)
        line(ctx, s, [(100, 38), (100, 134)], sideA, width: 3)
        line(ctx, s, [(100, 38), (215, 38)], mainBus == .dead ? .off : mainBus)
        label(ctx, s, "BAT1/ALT", 104, 62, anchor: .leading, size: 7, color: Theme.dim)

        // BAT2 side
        line(ctx, s, [(88, 188), (100, 188)], inputs.backupAltOK ? .alt : .off)
        line(ctx, s, [(88, 238), (100, 238)], bat2Wire)
        line(ctx, s, [(100, 150), (100, 238)], sideB == .off && inputs.battery2OK ? .off : sideB, width: 3)
        label(ctx, s, "BAT2", 104, 212, anchor: .leading, size: 7, color: Theme.dim)

        // D1 and D2 into the essential bus
        line(ctx, s, [(100, 118), (200, 118)], d1)
        diode(ctx, s, 166, 118, d1)
        label(ctx, s, "D1", 166, 108, size: 7, color: Theme.dim)
        line(ctx, s, [(100, 166), (200, 166)], d2)
        diode(ctx, s, 166, 166, d2)
        label(ctx, s, "D2", 166, 177, size: 7, color: Theme.dim)

        // Emergency Power path (D3, D4 and the switch)
        let e3: Kind = inputs.emergencyPower ? d1 : .off
        let e4: Kind = inputs.emergencyPower ? d2 : .off
        let eOut: Kind = !inputs.emergencyPower ? .off : (e3 == .battery || e4 == .battery ? .battery : (e3 == .alt || e4 == .alt ? .alt : .off))
        line(ctx, s, [(100, 134), (140, 134), (140, 142)], e3, dashed: !inputs.emergencyPower)
        line(ctx, s, [(100, 150), (140, 150), (140, 142)], e4, dashed: !inputs.emergencyPower)
        line(ctx, s, [(140, 142), (150, 142)], eOut, dashed: !inputs.emergencyPower)
        line(ctx, s, [(194, 142), (200, 142)], eOut, dashed: !inputs.emergencyPower)
        box(ctx, s, Self.emergencyBox,
            title: "EMER", sub: inputs.emergencyPower ? "ON" : "OFF",
            border: inputs.emergencyPower ? Theme.emergency : Theme.off,
            subColor: inputs.emergencyPower ? Theme.emergency : Theme.dim, titleSize: 7, subSize: 8)

        // Essential bus bar and the engine
        let barRect = CGRect(x: 200 * s, y: 108 * s, width: 10 * s, height: 68 * s)
        ctx.fill(Path(roundedRect: barRect, cornerRadius: 2 * s), with: .color(color(essential)))
        line(ctx, s, [(210, 142), (222, 142)], essential)
        box(ctx, s, CGRect(x: 222, y: 118, width: 84, height: 48),
            title: "ESSENTIAL BUS", sub: f.essentialPowered ? "Engine" : "NO POWER",
            border: color(essential), subColor: f.essentialPowered ? .white : Theme.fail)

        // Main bus
        box(ctx, s, CGRect(x: 215, y: 18, width: 118, height: 40),
            title: "MAIN BUS", sub: f.mainBusPowered ? "VP-X · avionics" : "NO POWER",
            border: color(mainBus), subColor: f.mainBusPowered ? .white : Theme.fail)

        // EBBS, charged from the main bus
        line(ctx, s, [(320, 58), (320, 196)], f.mainBusPowered ? (mainBus == .battery ? .battery : .alt) : .off)
        let ebbsText: String
        let ebbsBorder: Color
        switch result.ebbsState {
        case .notArmed: ebbsText = "Not armed"; ebbsBorder = Theme.off
        case .armed: ebbsText = "Armed"; ebbsBorder = Theme.emergency
        case .supplying: ebbsText = "ON BATTERY"; ebbsBorder = Theme.battery
        }
        box(ctx, s, CGRect(x: 215, y: 196, width: 118, height: 44),
            title: "EBBS  8 Ah", sub: ebbsText, border: ebbsBorder,
            subColor: result.ebbsState == .supplying ? Theme.battery : .white)
        label(ctx, s, "L HXr · SL-30 · audio · xpdr", 274, 250, size: 7, color: Theme.dim)

        // Sources
        sourceBox(ctx, s, Self.mainAltBox, title: "MAIN ALT",
                  sub: "60 A", ok: inputs.mainAltOK, active: inputs.mainAltOK ? .alt : .off)
        sourceBox(ctx, s, Self.battery1Box, title: "BAT 1",
                  sub: batteryText(result.battery1State), ok: inputs.battery1OK, active: bat1Wire)
        sourceBox(ctx, s, Self.backupAltBox, title: "BKUP ALT",
                  sub: inputs.lowRPM ? "15 A low RPM" : "30 A", ok: inputs.backupAltOK,
                  active: inputs.backupAltOK ? .alt : .off)
        sourceBox(ctx, s, Self.battery2Box, title: "BAT 2",
                  sub: batteryText(result.battery2State), ok: inputs.battery2OK, active: bat2Wire)
    }

    private func wire(for state: BatteryState) -> Kind {
        switch state {
        case .failed, .standby: return .off
        case .charging: return .alt
        case .discharging: return .battery
        }
    }

    private func batteryText(_ state: BatteryState) -> String {
        switch state {
        case .failed: return "FAILED"
        case .charging: return "Charging"
        case .standby: return "Standing by"
        case .discharging(let amps): return "Supplying \(PowerModel.ampsText(amps))"
        }
    }

    private func line(_ ctx: GraphicsContext, _ s: CGFloat, _ pts: [(CGFloat, CGFloat)], _ kind: Kind,
                      width: CGFloat = 2, dashed: Bool = false) {
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let point = CGPoint(x: pt.0 * s, y: pt.1 * s)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        let live = kind == .alt || kind == .battery
        let style = StrokeStyle(lineWidth: (live ? width + 0.5 : width) * s, lineCap: .round, lineJoin: .round,
                                dash: dashed ? [3 * s, 3 * s] : [])
        ctx.stroke(p, with: .color(color(kind)), style: style)
    }

    private func diode(_ ctx: GraphicsContext, _ s: CGFloat, _ x: CGFloat, _ y: CGFloat, _ kind: Kind) {
        var tri = Path()
        tri.move(to: CGPoint(x: (x - 6) * s, y: (y - 6) * s))
        tri.addLine(to: CGPoint(x: (x + 5) * s, y: y * s))
        tri.addLine(to: CGPoint(x: (x - 6) * s, y: (y + 6) * s))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(Theme.background))
        if kind == .alt || kind == .battery {
            ctx.fill(tri, with: .color(color(kind)))
        }
        ctx.stroke(tri, with: .color(color(kind)), lineWidth: 1.5 * s)
        var bar = Path()
        bar.move(to: CGPoint(x: (x + 5) * s, y: (y - 6) * s))
        bar.addLine(to: CGPoint(x: (x + 5) * s, y: (y + 6) * s))
        ctx.stroke(bar, with: .color(color(kind)), lineWidth: 2 * s)
    }

    private func label(_ ctx: GraphicsContext, _ s: CGFloat, _ text: String, _ x: CGFloat, _ y: CGFloat,
                       anchor: UnitPoint = .center, size: CGFloat = 9, weight: Font.Weight = .semibold,
                       color: Color = .white) {
        ctx.draw(Text(text).font(.system(size: size * s, weight: weight)).foregroundColor(color),
                 at: CGPoint(x: x * s, y: y * s), anchor: anchor)
    }

    private func box(_ ctx: GraphicsContext, _ s: CGFloat, _ r: CGRect, title: String, sub: String,
                     border: Color, subColor: Color = .white, titleSize: CGFloat = 9, subSize: CGFloat = 8) {
        let rect = CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s)
        let path = Path(roundedRect: rect, cornerRadius: 5 * s)
        ctx.fill(path, with: .color(Theme.card))
        ctx.stroke(path, with: .color(border), lineWidth: 2 * s)
        let gap: CGFloat = r.height > 30 ? 7 : 5
        label(ctx, s, title, r.midX, r.midY - gap, size: titleSize, weight: .bold)
        label(ctx, s, sub, r.midX, r.midY + gap, size: subSize, weight: .medium, color: subColor)
    }

    private func sourceBox(_ ctx: GraphicsContext, _ s: CGFloat, _ r: CGRect, title: String, sub: String,
                           ok: Bool, active: Kind) {
        box(ctx, s, r, title: title, sub: ok ? sub : "FAILED",
            border: ok ? color(active) : Theme.fail, subColor: ok ? .white : Theme.fail)
        if !ok {
            var x = Path()
            x.move(to: CGPoint(x: r.minX * s, y: r.minY * s))
            x.addLine(to: CGPoint(x: r.maxX * s, y: r.maxY * s))
            x.move(to: CGPoint(x: r.maxX * s, y: r.minY * s))
            x.addLine(to: CGPoint(x: r.minX * s, y: r.maxY * s))
            ctx.stroke(x, with: .color(Theme.fail.opacity(0.45)), lineWidth: 1.5 * s)
        }
    }
}
