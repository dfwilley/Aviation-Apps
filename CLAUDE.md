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
| `hangar-board/` | Arduino firmware for an ESP32 e-paper status board, plus a web installer page | Arduino IDE; compiled `.bin` files are checked in under `firmware/` |

`index.html` at the top is the GitHub Pages landing page (https://dfwilley.github.io/Aviation-Apps/).

## How a change reaches the phone

**A push to `main` is a release.** There is no staging step.

- Each app has workflows in `.github/workflows/` that run only when files in that app's folder change.
- The four iPhone apps each have an `...-testflight.yml` workflow. Any push to `main` that touches the app's folder builds, signs and uploads a new build to TestFlight, and it installs on the testers' phones automatically.
- The TestFlight workflows for Hangar Voice Log and Weight & Balance **do not run the tests**. Their tests run in the separate `...-build.yml` workflows, so a change with failing tests can still be uploaded. Check the test run before calling work finished. Cruise Perf is the exception: its TestFlight workflow runs the math check first.
- Build numbers are the workflow run number plus 1000; don't set them by hand.
- Signing uses four repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`. Never print or log them. The helper scripts are `hangar-voice-log/tools/asc_precheck.py` and `asc_signing.py`.
- Unsigned `.ipa` files for Sideloadly are published on the Releases page with tags that start with the app's folder name.
- The web pages (Fuel Planner, the Hangar Board installer, Hangar Log's privacy and support pages) go live on GitHub Pages as soon as they are pushed.

For anything larger than a small fix, work on a branch and merge to `main` only when it is ready, because the merge is what ships it.

## Tests and checks

- Hangar Voice Log: `HangarVoiceLogTests/` (logbook entry wording).
- Weight & Balance: `WeightAndBalanceTests/` checks results against the web app's numbers. `web/wb-core.js` and `WBModel.swift` hold the same math and model defaults; change both together and run `node web/test.js`. Model defaults come from Van's weight and balance quick-reference sheets (sources listed in `weight-and-balance/README.md`).
- Cruise Perf: `cruise-performance/ios/ModelCheck/` compares the Swift math with `expected.json`, which was produced by the web app's own code.
- Electrical System: `ElectricalSystemTests/` checks power paths and battery times against hand-worked numbers. Its build workflow runs the tests on every branch, and its TestFlight workflow runs them before uploading.
- These need a Mac, so they run in GitHub Actions, not locally on Linux or Windows. To test before merging, push to a branch and run the build workflow by hand on that branch (it has a "Run workflow" button).

## Things that are easy to get wrong

- **The numbers matter.** Weight & Balance and Cruise Perf are flight-planning aids, and Electrical System is an in-flight reference. Do not change limits, arms, weights, performance math or the test expectations unless the owner asks for that specific change. If a test disagrees with the code, stop and ask; don't edit the expected values to make it pass.
- **Hangar Log's data comes from outside this repository.** A daily Claude scheduled task (set up in the Claude app, not here) runs `hangar-voice-log/tools/make_hangar_data.py` against the owner's Access maintenance database and saves a `Hangar Log Data <date>.json` file in his Dropbox. The app reads the newest file from a folder the owner picks. Finished entries are written to `Claude Logbook Import.txt` in that folder for an Access import routine. If you change the JSON layout or the import file layout, the app, the Python tool and the Access side must all change together. Tell the owner, because the scheduled task and Access are his to update.
- The Access database is read-only to all of this code. Keep it that way.
- Hangar Log has a demo mode (`-demo` launch argument, fictional aircraft N512PT) used only for screenshots. Don't let demo data show in normal use.
- Hangar Log was submitted to the App Store once and rejected (see `hangar-voice-log/INSTALL.md`). The owner chose TestFlight and Sideloadly instead. Don't resubmit or change App Store settings unless asked.
- Hangar Board: after editing anything in `hangar-board/HangarBoard/web/`, run `python3 tools/embed.py` to regenerate `web_assets.h`. There is no cloud build for the firmware; new `.bin` files have to be compiled in the Arduino IDE and checked in.
- Fuel Planner's prices are a fixed snapshot (dated in its README). They do not update themselves.
- Some README text lags behind: the top README still describes Cruise Perf as Sideloadly-only, but it now uploads to TestFlight too. Trust the workflows.
- This repository is public. Never commit personal data, the Access database, Dropbox contents, or anything secret.

## Background

These apps were separate repositories until November 5, 2026 (Hangar-Voice-Log, Hangar-Board, Weight-And-Balance, Cruise-Performance, Fuel-Planner). Their history was brought over. The old standalone Hangar-Board repository still exists; this folder is the current copy.

The owner keeps a running list of app ideas in the Claude app. New apps for the airplane belong in this repository, each in its own folder with its own workflows.
