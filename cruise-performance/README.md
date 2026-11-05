# Cruise Perf (iPhone)

Shows on the home screen as **Cruise Perf**.

Native iPhone version of the N721NE Cruise Fuel Burn web app. Everything in the web app is here:

- **Efficient cruise finder**: target KTAS and altitude (±5 kt / ±500 ft or type a value), optional A/F at 0% trim. Shows power, RPM / manifold pressure, fuel flow, mileage, fuel/air ratio, EFII fuel trim, indicated airspeed and mixture, the trim, target-mixture and mixture notes, a better-altitude suggestion, the RPM / MP table, and "Show this in the calculator".
- **Flight conditions**: pressure altitude, temperature vs. standard, weight, power, Lycoming chart or lean-of-peak mixture, tuned or drawing-only drag.
- **Calculator results**: true airspeed, fuel flow, mileage, power, indicated airspeed, range with 45-minute reserve, plus full-throttle and lean-of-peak warnings.
- **Where the drag goes**, **cruise table**, **200 KTAS at 9 gal/hr check**, **sources** and **method and assumptions**.
- **Light or dark mode**: tap the sun/moon button at the top left any time to pick Light, Dark, or Match iPhone. Starts in Dark and remembers your choice.
- **Arrange**: hold the ≡ handle on any tile or section and drag it into place, or tap Arrange to reorder everything in a list. Layout and last-used settings are saved on the phone. Reset tile layout and Reset layout put things back.

## Build and install

For iPhone installs, every change pushed to `cruise-performance/` builds, signs and uploads to **TestFlight** automatically (Actions → *Cruise Perf - upload to TestFlight*). For a Sideloadly copy instead, run **Actions → Cruise Perf - build iPhone app (run by hand) → Run workflow**. The build first checks the app's math against numbers produced by the web app's own code (`ios/ModelCheck`), then builds `CruisePerformance.ipa`. Download the artifact and install it with Sideloadly using your Apple ID.
