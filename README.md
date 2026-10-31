# N721NE Cruise Fuel Burn (iPhone)

Native iPhone version of the N721NE Cruise Fuel Burn web app. Everything in the web app is here:

- **Efficient cruise finder**: target KTAS and altitude (±5 kt / ±500 ft or type a value), optional A/F at 0% trim. Shows power, RPM / manifold pressure, fuel flow, mileage, fuel/air ratio, EFII fuel trim, indicated airspeed and mixture, the trim, target-mixture and mixture notes, a better-altitude suggestion, the RPM / MP table, and "Show this in the calculator".
- **Flight conditions**: pressure altitude, temperature vs. standard, weight, power, Lycoming chart or lean-of-peak mixture, tuned or drawing-only drag.
- **Calculator results**: true airspeed, fuel flow, mileage, power, indicated airspeed, range with 45-minute reserve, plus full-throttle and lean-of-peak warnings.
- **Where the drag goes**, **cruise table**, **200 KTAS at 9 gal/hr check**, **sources** and **method and assumptions**.
- **Arrange**: hold the ≡ handle on any tile or section and drag it into place, or tap Arrange to reorder everything in a list. Layout and last-used settings are saved on the phone. Reset tile layout and Reset layout put things back.

## Build and install

Run **Actions → iOS IPA → Run workflow**. The build first checks the app's math against numbers produced by the web app's own code (`ios/ModelCheck`), then builds `CruisePerformance.ipa`. Download the artifact and install it with Sideloadly using your Apple ID.
