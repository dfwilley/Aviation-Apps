import Foundation

/// Sources and method notes, same wording as the web app.
enum InfoText {
    struct Item: Identifiable {
        let id = UUID()
        let tag: String?
        let markdown: String
        var attributed: AttributedString {
            (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(markdown)
        }
    }

    static let sources: [Item] = [
        Item(tag: "Verified", markdown: "Van's Aircraft, RV-14 3-view, page 01-03, Rev 1 (April 15, 2013), scale 1:32. Your folder: *Registration and Airworthiness / 3-view RV-14 drawing.pdf*. Span 27 ft and length 21 ft 1 in set the drawing scale; wing chord, fuselage, tail and gear sizes were measured from it."),
        Item(tag: "Verified", markdown: "Van's RV-14 3-view with added dimensions. *Paint Scheme Details / RV14 3 view.JPG*. Horizontal tail span 10 ft 4 in, used to check the drawing scale (measured 10 ft 5 in)."),
        Item(tag: "Verified", markdown: "Van's Aircraft RV-14 specification sheet (14FLY-e, February 1, 2019), [vansaircraft.com](https://www.vansaircraft.com/wp-content/uploads/2019/01/14FLY-e-02012019.pdf). Wing area 126.1 sq ft; cruise 203 mph at 75% and 179 mph at 55%, 8,000 ft, 2,050 lb; top speed 216 mph."),
        Item(tag: "Verified", markdown: "Lycoming IO-390-A1A6 Operation and Installation Manual, Section 1 Operating Instructions, page 21, Figure 3-2, Sea Level and Altitude Performance Curve. *Manuals / Engine / Lycoming Manuals*. Full-throttle power at 2,700 RPM: 210 hp sea level, about 180 hp at 5,600 ft, 155 hp at 10,900 ft, 105 hp at 19,300 ft (read from the chart)."),
        Item(tag: "Verified", markdown: "Same manual, page 22, Figure 3-3, Minimum Fuel Flow vs. Power (identical chart in the YIO-390-B manual, page 22). 47 lb/hr at 110 hp, 66 at 150, 73 at 160, 81.5 at 170, 90 at 180, 105 at 210."),
        Item(tag: "Verified", markdown: "Same Figure 3-2, sea level panel: horsepower vs. manifold pressure for 2,000, 2,150, 2,350, 2,450 and 2,700 RPM. The cruise finder uses these lines (read from the chart, straight-line between RPMs) and the chart's own method for correcting to altitude and temperature."),
        Item(tag: "Verified", markdown: "Hartzell Manual 115N, Rev 24, section 61-00-15, page 2-21, Table 2-2: blade model F7497 has a 74 in basic design diameter."),
        Item(tag: "Verified", markdown: "Wing airfoil coordinates, *Solidworks / airfoil coordinates.txt.csv*: 58 in chord, 15.8% thick at 33% chord."),
        Item(tag: "Verified", markdown: "N721NE Weight and Balance (February 4, 2024): empty weight 1,247 lb, gross 2,050 lb."),
    ]

    static let method: [Item] = [
        Item(tag: nil, markdown: "**Method.** Skin-friction drag for each part comes from its wetted area (skin surface exposed to the air) and Reynolds number, multiplied by a shape factor. This is the standard component buildup in Raymer, *Aircraft Design: A Conceptual Approach*, chapter 12. Induced drag (the cost of making lift) comes from span and weight. Thrust horsepower needed is drag times speed. Engine horsepower is thrust horsepower divided by propeller efficiency."),
        Item(tag: "Assumption", markdown: "Wheel pants 0.20 sq ft of flat-plate drag each, faired gear legs 0.06 each, tailwheel 0.06, antennas, lights and exhaust 0.15, gaps and leaks 8% extra. Typical values in the style of Hoerner, *Fluid-Dynamic Drag*."),
        Item(tag: "Assumption", markdown: "Cooling drag 0.35 sq ft before tuning, about 11% of total. This is the hardest item to estimate from a drawing."),
        Item(tag: "Assumption", markdown: "Wing efficiency factor 0.78. Propeller efficiency from momentum theory times 0.86; works out to about 84% in cruise."),
        Item(tag: "Assumption", markdown: "Lean-of-peak fuel burn uses 0.40 lb of fuel per horsepower per hour, a typical figure for a well-balanced injected engine. It is not from your Lycoming manual, and it applies only at 70% power or less. Fuel weighs 6.0 lb/gal."),
        Item(tag: "Assumption", markdown: "Target mixture ratios: air/fuel about 16:1 at roughly 50 °F lean of peak, about 14.7:1 at peak EGT, and about 12.5:1 at 85 °F rich of peak, from measured data in Reinhard Metz, \"Adding Direct Air/Fuel Ratio Monitoring,\" [Kitplanes, January 18, 2019](https://www.kitplanes.com/adding-direct-air-fuel-ratio-monitoring/). Lycoming gives mixture targets only as EGT, not as ratios: peak EGT for best economy at 75% power and below, and no leaner than 150 °F rich of peak at maximum power cruise (IO-390 Operation Reference Manual, Section 3, pages 3-4 to 3-6, Figure 3-1). The 12:1 shown above 75% is an estimate for 150 °F rich of peak. Fuel/air ratio is 1 divided by the air/fuel ratio; the System32 controller displays air/fuel."),
        Item(tag: "Verified", markdown: "EFII, System32 Initial Fuel Tuning Procedure, Constant Speed Prop, rev 6/20 (*Manuals / Engine / System 32 EFII*), step 4 chart: target air/fuel at 0% trim after tuning is 15.5:1 at 2,000 to 2,100 RPM, 15 at 2,200, 14.5 at 2,300, 14 at 2,400, 13.5 at 2,500, 13 at 2,600, 12.5 at 2,700 and 12 at 2,800 (squared settings). Steps 3 and 5 apply trim percent directly to the fuel numbers, so trim scales fuel in proportion. System32 Operating Procedures rev 6/20, Emergency Procedures item 4: trim knob clockwise adds fuel, counterclockwise reduces it."),
        Item(tag: "Assumption", markdown: "Fuel trim = (air/fuel at 0% trim ÷ target air/fuel) − 1. This assumes N721NE's map was tuned to the EFII chart. If your controller reads something else at 0% trim, enter it in the finder. Pilots on Van's Air Force report about −10% to −14% trim for 50 °F lean of peak, in line with this method."),
        Item(tag: "Assumption", markdown: "Cruise finder picks the lowest RPM (2,150 to 2,700) that can make the needed power with at least 0.3 in. of manifold pressure to spare. Lower RPM with higher manifold pressure is the usual efficient choice because the engine loses less to friction and the propeller blade tips run slower. The fuel-flow chart depends on power only, so the gain from lower RPM is not counted in the gal/hr shown. Check your engine and propeller limits for any RPM or manifold pressure restrictions."),
        Item(tag: nil, markdown: "**Tuning.** The drawing-only estimate gives 162 KTAS at 75% power, 8,000 ft, 2,050 lb. Van's published 176 KTAS. Scaling all parasite drag by 0.79 matches that point; the tuned model then reproduces Van's other cruise numbers within 1% and top speed within 2%."),
        Item(tag: nil, markdown: "**Limits.** Van's numbers come from their factory airplane. N721NE's paint, fairings, baffle sealing and rigging can move results 5 to 10%. A few logged cruise points from your EFIS (altitude, outside air temperature, TAS, fuel flow, RPM, manifold pressure) would let this be tuned to your airplane instead."),
    ]
}
