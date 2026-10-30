import SwiftUI

/// Weight vs CG with the utility and aerobatic envelopes, drawn on the same 440 × 340 layout as the web app.
struct EnvelopeChart: View {
    let result: WBResult
    @Environment(\.colorScheme) private var scheme

    private let L: CGFloat = 50, R: CGFloat = 430, T: CGFloat = 14, B: CGFloat = 296
    private let x0 = 80.0, x1 = 90.0, y0 = 1200.0, y1 = 2150.0

    private func X(_ c: Double) -> CGFloat { L + CGFloat((c - x0) / (x1 - x0)) * (R - L) }
    private func Y(_ w: Double) -> CGFloat { B - CGFloat((w - y0) / (y1 - y0)) * (B - T) }

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 440
            ctx.scaleBy(x: s, y: s)
            draw(&ctx)
        }
        .aspectRatio(440.0 / 340.0, contentMode: .fit)
        .frame(maxWidth: 640)
        .accessibilityElement()
        .accessibilityLabel("Weight versus center of gravity with the utility and aerobatic envelopes")
        .accessibilityValue("Takeoff \(WB.fmt(result.toW)) pounds at \(WB.fmt(result.toCG, 2)) inches. Landing \(WB.fmt(result.lW)) pounds at \(WB.fmt(result.lCG, 2)) inches.")
    }

    private func label(_ s: String, bold: Bool = false) -> Text {
        Text(s)
            .font(.system(size: 11, weight: bold ? .semibold : .regular))
            .foregroundColor(Theme.fixed(bold ? Palette.ink : Palette.muted, scheme))
    }

    private func line(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color, _ style: StrokeStyle) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        ctx.stroke(p, with: .color(color), style: style)
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let rule = Theme.fixed(Palette.rule, scheme)
        let env = Theme.fixed(Palette.env, scheme)
        let env2 = Theme.fixed(Palette.env2, scheme)
        let pt = Theme.fixed(Palette.point, scheme)
        let panel = Theme.fixed(Palette.panel, scheme)
        let thin = StrokeStyle(lineWidth: 1)

        // Grid and axis numbers
        for c in 80...90 {
            let x = X(Double(c))
            line(&ctx, CGPoint(x: x, y: T), CGPoint(x: x, y: B), rule, thin)
            ctx.draw(label("\(c)"), at: CGPoint(x: x, y: B + 16), anchor: .bottom)
        }
        for w in stride(from: 1200, through: 2100, by: 100) {
            let y = Y(Double(w))
            line(&ctx, CGPoint(x: L, y: y), CGPoint(x: R, y: y), rule, thin)
            ctx.draw(label(WB.fmt(Double(w))), at: CGPoint(x: L - 6, y: y), anchor: .trailing)
        }
        ctx.draw(label("CG, inches aft of datum"), at: CGPoint(x: (L + R) / 2, y: B + 34), anchor: .bottom)
        var rot = ctx
        rot.translateBy(x: 14, y: (T + B) / 2)
        rot.rotate(by: .degrees(-90))
        rot.draw(label("Weight, lb"), at: .zero, anchor: .center)

        // Envelopes: the selected category is solid and stronger
        let utilityOn = result.category == .utility
        let fwd = Limits.forwardCG
        let uRect = CGRect(x: X(fwd), y: Y(Limits.grossUtility),
                           width: X(Limits.aftCGUtility) - X(fwd), height: Y(y0) - Y(Limits.grossUtility))
        let aRect = CGRect(x: X(fwd), y: Y(Limits.grossAerobatic),
                           width: X(Limits.aftCGAerobatic) - X(fwd), height: Y(y0) - Y(Limits.grossAerobatic))
        ctx.fill(Path(uRect), with: .color(env.opacity(utilityOn ? 0.12 : 0.05)))
        ctx.stroke(Path(uRect), with: .color(env), lineWidth: utilityOn ? 2 : 1)
        ctx.fill(Path(aRect), with: .color(env2.opacity(utilityOn ? 0.05 : 0.14)))
        ctx.stroke(Path(aRect), with: .color(env2),
                   style: StrokeStyle(lineWidth: utilityOn ? 1 : 2, dash: utilityOn ? [5, 4] : []))
        ctx.draw(label("Utility \(WB.fmt(Limits.grossUtility)) lb", bold: true),
                 at: CGPoint(x: X(fwd) + 4, y: Y(Limits.grossUtility) - 4), anchor: .bottomLeading)
        ctx.draw(label("Aerobatic \(WB.fmt(Limits.grossAerobatic)) lb", bold: true),
                 at: CGPoint(x: X(fwd) + 4, y: Y(Limits.grossAerobatic) + 14), anchor: .bottomLeading)

        // Takeoff, landing and zero-fuel points, kept on the chart if they fall off it
        func P(_ c: Double, _ w: Double) -> CGPoint {
            CGPoint(x: min(max(X(c), L), R), y: min(max(Y(w), T), B))
        }
        let to = P(result.toCG, result.toW), ld = P(result.lCG, result.lW), zf = P(result.zfCG, result.zfW)
        line(&ctx, to, zf, pt, StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        line(&ctx, to, ld, pt, StrokeStyle(lineWidth: 2))
        ctx.fill(Path(CGRect(x: zf.x - 5, y: zf.y - 5, width: 10, height: 10)), with: .color(pt))
        let landing = Path(ellipseIn: CGRect(x: ld.x - 6, y: ld.y - 6, width: 12, height: 12))
        ctx.fill(landing, with: .color(panel))
        ctx.stroke(landing, with: .color(pt), lineWidth: 2)
        ctx.fill(Path(ellipseIn: CGRect(x: to.x - 6.5, y: to.y - 6.5, width: 13, height: 13)), with: .color(pt))
    }
}
