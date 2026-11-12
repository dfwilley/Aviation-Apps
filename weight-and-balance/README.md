# Homebuilt W&B (weight and balance for RV and other homebuilt aircraft)

A weight and balance calculator for iPhone, with a matching web app. It began as the N721NE Weight & Balance app and now works for any registration.

- **First launch:** enter your registration, pick your model and choose nosewheel or tailwheel
- **Model defaults:** RV-4, RV-6/6A, RV-7/7A, RV-8/8A, RV-9/9A, RV-10, RV-12 and RV-14/14A fill in the CG range, weight limits and the seat, baggage and fuel arms from Van's published data. "Other / custom" starts blank
- **Everything is editable:** the CG envelope for each category (for example utility and aerobatic), weight limits, seat, baggage and fuel tank arms, baggage limits and fuel capacity. One tap restores the model's defaults
- **Empty weight:** left main, right main and nosewheel or tailwheel scale weights and arms, plus add or remove a single item
- Results, CG envelope chart and loading table update as you type. Entries are saved on the device

This is a planning aid. The aircraft's own weight and balance record and operating limitations govern. Not affiliated with Van's Aircraft, Inc.

## Where the default numbers come from

| Model | Source |
|---|---|
| RV-4, RV-6, RV-7, RV-8, RV-9, RV-10, RV-14 | Van's "Weight and Balance Data Quick Reference" sheet for each model (vansaircraft.com): datum, CG range, gross weights, aerobatic or utility limits, and fuel, seat and baggage arms |
| RV-12 | Van's RV-12 Pilot's Operating Handbook, Section IV |
| Fuel capacity, baggage limits | Van's specifications tables for RV-4, 7, 8, 9 and 14. For RV-6, RV-10 and RV-12 these are the commonly published figures and the app says so |

Not included: RV-3 and RV-12iS (no Van's quick-reference sheet was found for them) and RV-15. Use "Other / custom" for those. Wheel arms are never pre-filled because Van's does not publish them; they come from each airplane's weighing.

## Getting it

- **Web app:** https://dfwilley.github.io/Aviation-Apps/weight-and-balance/web/ (on iPhone: Share, then Add to Home Screen)
- **TestFlight:** every change to this folder builds, signs and uploads a new build (workflow *Weight & Balance - upload to TestFlight*)
- **Sideloadly:** download `Homebuilt-WB.ipa` from the newest **Homebuilt W&B** build at https://github.com/dfwilley/Aviation-Apps/releases

If the earlier N721NE version is on your phone, updating keeps your N721NE scale readings and loads.

## App Store

- Privacy policy: https://dfwilley.github.io/Aviation-Apps/weight-and-balance/privacy.html
- Support: https://dfwilley.github.io/Aviation-Apps/weight-and-balance/support.html
- Each build's release includes screenshots made with a sample aircraft (N512PT, an RV-7A), as Apple requires: no real aircraft's data

## Project layout

- `WeightAndBalance/WBModel.swift`: model defaults and all calculations
- `WeightAndBalance/ContentView.swift`: the screens
- `WeightAndBalance/EnvelopeChart.swift`: the CG envelope chart
- `WeightAndBalanceTests/`: tests that check the results against the web app's numbers
- `web/`: the web app. `wb-core.js` holds the same math as `WBModel.swift`; `node web/test.js` checks it
- `project.yml`: the project description that XcodeGen turns into an Xcode project during the cloud build
