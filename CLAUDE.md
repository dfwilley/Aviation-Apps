# Handoff note for Claude Code: Aviation-Apps

Read this first, then `README.md` and the README inside the app folder you are working on. This note covers what those files don't: how the owner works, how changes reach his phone, and the traps.

## The owner and how to work with him

- The owner is a pilot and aircraft builder, not a programmer. Claude writes all the code. Explain things in plain language and define technical terms.
- He has a Windows PC and an iPhone. **There is no Mac.** Everything Apple-related is built on GitHub's cloud Macs (GitHub Actions). Never suggest opening Xcode.
- He has a paid Apple Developer account. Apps reach the phone by TestFlight (preferred) or by Sideloadly on the PC.
- Lead with the result, then limitations. Make low-risk decisions without asking. Ask first before deleting files, publishing anything new, spending money, or any change that can't be undone.
- Keep changes focused on what was asked. Don't add dependencies unless the task needs them.
- Commit messages follow the existing pattern: `App name: what changed, in plain words` (see `git log`).

## What is in this repository

All apps are for one aircraft, N721NE, a Van's RV-14.

| Folder | What it is | How it is built |
|---|---|---|
| `hangar-voice-log/` | Native iPhone app (SwiftUI). Voice notes become draft maintenance logbook entries. Shows on the phone as "Hangar Log". Bundle ID `com.dfwilley.hangarvoicelog` | XcodeGen from `project.yml` |
| `weight-and-balance/` | "Homebuilt W&B": native iPhone app (SwiftUI) for any registration, with RV model defaults, plus a matching web app in `web/`. Bundle ID `com.dfwilley.weightandbalance` | XcodeGen from `project.yml` |
| `cruise-performance/` | Native iPhone app (SwiftUI), "Cruise Perf". Bundle ID `com.n721ne.cruise` | Checked-in Xcode project in `ios/` (no XcodeGen) |
| `electrical-system/` | Native iPhone app (SwiftUI), "N721NE Elec". Live diagram of the electrical system with power paths and battery life. Bundle ID `com.dfwilley.electricalsystem` | XcodeGen from `project.yml` |
| `fuel-planner/` | Web app, plain HTML and JavaScript, no build step | GitHub Pages |
| `N721NE-To-Do-List/` | Web app, one HTML file, no build step. A checklist of flight and ground test points, inspection items and records fixes. The list itself is shared by every connected device from a private repository | GitHub Pages |
| `greenie-board/` | Web app, "KTUS Greenie Board", plain HTML and JavaScript, no build step. Reads the GRT HXr's raw `DEMO-....LOG` recordings in the browser, finds each touchdown and grades it LSO-style. Each browser keeps its own board. `ios/` wraps the same page in an iPhone app (bundle ID `com.dfwilley.greenieboard`) | GitHub Pages; `node greenie-board/test.js` runs in `greenie-board-test.yml`. The iPhone app is built by `greenie-board-ipa.yml` (XcodeGen from `ios/project.yml`) and published on every `main` push to the fixed release `greenie-board-latest` |
| `hangar-board/` | Arduino firmware for an e-paper status board (ESP32, ESP32-S3 or Raspberry Pi Pico W), plus a web installer page | Arduino IDE, or `hangar-board-build.yml` on GitHub; compiled firmware files are checked in under `firmware/` |

`index.html` at the top is the GitHub Pages landing page (https://dfwilley.github.io/Aviation-Apps/).

## How a change reaches the phone

**A push to `main` is a release.** There is no staging step.

- Each app has workflows in `.github/workflows/` that run only when files in that app's folder change.
- Hangar Voice Log, Weight & Balance and Cruise Perf each have an `...-testflight.yml` workflow. Any push to `main` that touches the app's folder builds, signs and uploads a new build to TestFlight, and it installs on the testers' phones automatically.
- **Electrical System is Sideloadly only.** The owner does not want it in App Store Connect or TestFlight at all (November 26, 2026). Its TestFlight workflow is switched off (manual start only); don't turn it back on or upload it unless he asks. A push to `main` publishes its unsigned `.ipa` on the Releases page.
- The TestFlight workflows for Hangar Voice Log and Weight & Balance **do not run the tests**. Their tests run in the separate `...-build.yml` workflows, so a change with failing tests can still be uploaded. Check the test run before calling work finished. Cruise Perf is the exception: its TestFlight workflow runs the math check first.
- Build numbers are the workflow run number plus 1000; don't set them by hand.
- Signing uses four repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`. Never print or log them. The helper scripts are `hangar-voice-log/tools/asc_precheck.py` and `asc_signing.py`.
- Unsigned `.ipa` files for Sideloadly are published on the Releases page with tags that start with the app's folder name.
- The web pages (Fuel Planner, the N721NE To Do List, the Hangar Board installer, Hangar Log's privacy and support pages) go live on GitHub Pages as soon as they are pushed.

For anything larger than a small fix, work on a branch and merge to `main` only when it is ready, because the merge is what ships it.

**Standing instruction from the owner (November 14, 2026): once the tests pass on the branch, merge to `main` without asking.** Then confirm the `main` builds went through. Still ask first if the tests fail, if a test expectation or a flight number had to change, or if the change publishes something new.

## Tests and checks

- Greenie Board: `node greenie-board/test.js` (runs anywhere, no Mac needed). It builds made-up recordings and checks the grades. The owner's real log files are personal flight data: test against them locally, never commit them.
- Hangar Voice Log: `HangarVoiceLogTests/` (logbook entry wording).
- Weight & Balance: `WeightAndBalanceTests/` checks results against the web app's numbers. `web/wb-core.js` and `WBModel.swift` hold the same math and model defaults; change both together and run `node web/test.js`. Model defaults come from Van's weight and balance quick-reference sheets (sources listed in `weight-and-balance/README.md`).
- Cruise Perf: `cruise-performance/ios/ModelCheck/` compares the Swift math with `expected.json`, which was produced by the web app's own code.
- Electrical System: `ElectricalSystemTests/` checks power paths and battery times against hand-worked numbers, and `ElectricalSystemUITests/` runs the app on a simulator and touches the diagram. Its build workflow runs the tests on every branch, and on `main` it runs them before publishing the `.ipa`.
- These need a Mac, so they run in GitHub Actions, not locally on Linux or Windows. To test before merging, push to a branch and run the build workflow by hand on that branch (it has a "Run workflow" button).

## Things that are easy to get wrong

- **The numbers matter.** Weight & Balance and Cruise Perf are flight-planning aids, and Electrical System is an in-flight reference. Do not change limits, arms, weights, performance math or the test expectations unless the owner asks for that specific change. If a test disagrees with the code, stop and ask; don't edit the expected values to make it pass.
- **Hangar Log's data comes from outside this repository.** A daily Claude scheduled task (set up in the Claude app, not here) runs `hangar-voice-log/tools/make_hangar_data.py` against the owner's Access maintenance database and saves a `Hangar Log Data <date>.json` file in his Dropbox. The app reads the newest file from a folder the owner picks. Finished entries are written to `Claude Logbook Import.txt` in that folder for an Access import routine. If you change the JSON layout or the import file layout, the app, the Python tool and the Access side must all change together. Tell the owner, because the scheduled task and Access are his to update.
- The Access database is read-only to all of this code. Keep it that way.
- Hangar Log has a demo mode (`-demo` launch argument, fictional aircraft N512PT) used only for screenshots. Don't let demo data show in normal use.
- Hangar Log was submitted to the App Store once and rejected (see `hangar-voice-log/INSTALL.md`). The owner chose TestFlight and Sideloadly instead. Don't resubmit or change App Store settings unless asked.
- Hangar Board: after editing anything in `hangar-board/HangarBoard/web/`, run `python3 tools/embed.py` to regenerate `web_assets.h`. `hangar-board-build.yml` compiles the firmware for all three boards on every push that touches it and, on a work branch, commits the new Pico W file (`firmware/hangarboard-picow.uf2`) back to that branch, so pull before pushing again. The ESP32 `.bin` files are not updated automatically: take them from the workflow run's saved files or compile in the Arduino IDE, then check them in. The board can read the Hobbs time from the owner's MyFlightbook logbook (read-only). `hangar-board/mfb.html` is the address registered with MyFlightbook as the callback, so don't rename or move it. Keep the board's requests to MyFlightbook rare (it asks every six hours), and never test against the live MyFlightbook site from a session.
- **The To Do List's data is not in this repository.** It is `list.json` in the owner's private repository `dfwilley/N721NE-To-Do-Data`, which holds nothing else. The page reads and saves that file through GitHub from each device where the owner has pasted an access key, and a device without a key shows only its own copy. The key is limited to that repository on purpose; never point the page back at this repository or ask for a key that can reach it. To check off, add or edit an item from a Claude session, that repository has to be added to the session: edit `list.json` and set the item's `updated` to the current time in milliseconds, because the newest `updated` wins when devices merge. To remove an item, delete it and add its id with a time to `deleted`, or a device will put it back. The `SEED` and `DONE_UPDATES` lists inside `index.html` are only the starting list for a browser that has never connected; don't add new items there, because this repository is public.
- Fuel Planner's prices are a fixed snapshot (dated in its README). They do not update themselves.
- This repository is public. Never commit personal data, the Access database, Dropbox contents, or anything secret.

## Background

These apps were separate repositories until November 5, 2026 (Hangar-Voice-Log, Hangar-Board, Weight-And-Balance, Cruise-Performance, Fuel-Planner). Their history was brought over. The old standalone Hangar-Board repository still exists; this folder is the current copy.

The owner keeps a running list of app ideas in the Claude app. New apps for the airplane belong in this repository, each in its own folder with its own workflows.
