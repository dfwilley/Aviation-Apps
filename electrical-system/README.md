# N721NE Electrical System

A native iPhone app that shows N721NE's electrical system as a live diagram. It is meant to be opened during an electrical problem to see what is still powered, from where, and for how long.

Shows on the phone as "N721NE Elec". Bundle ID `com.dfwilley.electricalsystem`.

## What it does

- Draws the two alternators, three batteries, the main bus and the essential bus (the engine).
- Buttons fail the main alternator, backup alternator, Battery 1 or Battery 2. Any combination works.
- An Emergency Power switch and an engine RPM choice (the backup alternator gives less near idle).
- A slider for main bus load, 0 to 40 A. Set it to the total on the VP-X page.
- For each state: which source feeds each bus, how long each bus lasts, each battery's rated and usable capacity, and plain-language notes.

Wire colors: green is alternator power, amber is battery power, gray is no current, red is failed.

## Where the numbers come from

| Item | Value | Source |
|---|---|---|
| Battery 1 (main), EarthX ETX-900 | 15.6 Ah | EarthX published rating |
| Battery 2 (alternate), EarthX ETX-680C | 12.4 Ah | EarthX published rating |
| Backup battery, EarthX EBBS | 8 Ah, 8 A continuous | POH Rev 1.10; EarthX listing |
| Main alternator, Plane Power AL12-EI60 | 60 A | POH Rev 1.10 |
| Backup alternator, Monkworkz MZ-30L | 30 A at 1,800 RPM and above, 15 A near 1,000 RPM | POH Rev 1.10 |
| Main bus output limit | 40 A | Bus Manager manual |
| Essential bus output limit | 30 A | Bus Manager manual |
| Essential bus load (default) | 35 A | Sum of System32 breakers: ECU 5 A x2, ignition 15 A, one fuel pump 10 A |
| EBBS load (default) | 8.5 A | VP-X load plan: left HXr and AHRS 3.6, audio panel 2.5, GTX-330 1.5, SL-30 0.9 |
| Usable share of rated capacity | 80% | Owner's choice, adjustable in Settings |

The power paths follow the EFII Bus Manager Installation Instructions (PN BM-1, rev 1-6-20), Drawing 5A, the two-alternator diagram:

- The main bus is fed only from the BAT1/ALT terminal (main alternator and Battery 1).
- The backup alternator and Battery 2 are on the BAT2 terminal. They can feed the essential bus but never the main bus.
- The essential bus takes power through diodes from whichever side is at the higher voltage.
- Emergency Power adds a direct path from both batteries to the essential bus.

## Things still to confirm on the airplane

These are marked in the app. Do not treat them as settled.

1. **Essential bus load.** 35 A is the breaker total, which is an upper limit and not the real draw. The real figure is lower, so real battery times are longer than the app shows until a measured value is entered in Settings.
2. **Emergency Power and the main bus.** The app leaves the main bus as it is when Emergency Power is ON, as the Bus Manager manual describes. The POH wording suggests the main bus may be dropped. Not confirmed.
3. **EBBS.** The app assumes it comes on only with Emergency Power and takes over its avionics when the main bus is lost. Its planned load (8.5 A) is slightly over its 8 A continuous rating.
4. **Which alternator carries the essential bus when both work.** It is whichever regulates higher. The app shows the main alternator.
5. **Backup alternator and the main bus.** The POH says the backup generator keeps supplying the electrical system after a main alternator failure. Drawing 5A shows it cannot reach the main bus. The app follows the drawing.

A failed battery is treated as disconnected. A shorted battery behaves differently and can trip a breaker.

## How the times are worked out

`PowerModel.swift` holds all the logic and has no screen code. It works out who supplies each bus, then steps forward in time draining the batteries until something runs out. Battery 2 picks up the essential bus before Battery 1, because Battery 1 is the one loaded by the main bus.

`ElectricalSystemTests/PowerModelTests.swift` checks the results against times worked out by hand. **These are flight-reference numbers. Do not change ratings or test expectations unless the owner asks for that specific change.**

## Building

XcodeGen from `project.yml`, built on GitHub's cloud Macs. There is no Mac.

- `.github/workflows/electrical-system-build.yml` runs the tests on every branch that changes this folder. On `main` it also publishes an unsigned `.ipa` on the Releases page for Sideloadly.
- `.github/workflows/electrical-system-testflight.yml` runs on `main` only. It runs the tests, then signs and uploads to TestFlight. The first upload needs an app record for `com.dfwilley.electricalsystem` in App Store Connect; the workflow stops with instructions if it is missing.
