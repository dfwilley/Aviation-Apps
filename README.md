# N721NE Weight & Balance (native iPhone app)

A native SwiftUI version of the N721NE Weight & Balance web app, for iPhone only. It has the same screen, the same inputs and the same math:

- Status bar and result tiles: takeoff and landing weight and CG, how far under max weight you are, empty weight, zero-fuel CG, and max fuel for the load
- Pilot, passenger, baggage, takeoff fuel and fuel burned, with ▼ ▲ buttons, plus the Utility/Aerobatic switch
- Tap the **Empty weight ✎** tile to edit the left main, right main and tailwheel scale weights and arms, add or remove a single item, or restore the February 4, 2024 weighing
- CG envelope chart, loading table, and the limits and sources notes
- Your entries are saved on the phone between launches

This is a planning aid. The aircraft's own weight and balance record governs.

## Getting it onto your iPhone (no Mac needed)

Every push to `main` builds the app on a GitHub cloud Mac, runs the calculation tests, and produces an unsigned `.ipa` file.

1. Open the **Actions** tab of this repository and click the newest green **Build iPhone app** run.
2. Under **Artifacts**, download **N721NE-Weight-and-Balance-ipa**. It downloads as a .zip; unzip it to get `N721NE-Weight-and-Balance.ipa`.
3. Connect the iPhone to your Windows PC, open **Sideloadly**, drag in the `.ipa`, enter your Apple ID and click **Start**.
4. On the iPhone, go to **Settings › General › VPN & Device Management**, tap your Apple ID and choose **Trust**. (Developer Mode must also be on: **Settings › Privacy & Security › Developer Mode**.)

With a free Apple ID the app stops opening after 7 days; re-run step 3 to renew it. Your saved entries stay on the phone. A paid Apple Developer account ($99/year) makes it last a year.

## Project layout

- `WeightAndBalance/WBModel.swift`: limits, arms and all calculations
- `WeightAndBalance/ContentView.swift`: the screen
- `WeightAndBalance/EnvelopeChart.swift`: the CG envelope chart
- `WeightAndBalanceTests/`: tests that check the results against the web app's numbers
- `project.yml`: the project description that XcodeGen turns into an Xcode project during the cloud build
