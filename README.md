# Aviation Apps

N721NE and flying-related apps, kept together in one place. Each app lives in its own folder.

| App | Folder | Kind | How to get it |
|---|---|---|---|
| Hangar Voice Log | `hangar-voice-log/` | Native iPhone | TestFlight, or the `.ipa` on the Releases page with Sideloadly (see `hangar-voice-log/INSTALL.md`) |
| Weight & Balance | `weight-and-balance/` | Native iPhone | `.ipa` on the Releases page |
| Cruise Perf | `cruise-performance/` | Native iPhone | Actions → *Cruise Perf - build iPhone app* → Run workflow |
| Fuel Planner | `fuel-planner/` | Web app | https://dfwilley.github.io/Aviation-Apps/fuel-planner/ |
| Hangar Board | `hangar-board/` | ESP32 e-paper board | Installer page: https://dfwilley.github.io/Aviation-Apps/hangar-board/ |

## Builds

The build setups are in `.github/workflows/`. Each one runs only when files in its own app folder change, so editing one app doesn't rebuild the others. Release tags start with the app's folder name (for example `hangar-voice-log-build-12`).

The TestFlight upload for Hangar Voice Log needs four repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`.

## Help pages

Hangar Voice Log's privacy and help pages (linked from the app's Settings) are `hangar-voice-log/privacy.html` and `hangar-voice-log/support.html`, served at https://dfwilley.github.io/Aviation-Apps/hangar-voice-log/.

## History

These apps used to be separate repositories (Hangar-Voice-Log, Hangar-Board, Weight-And-Balance, Cruise-Performance, Fuel-Planner). Their full commit history was brought over.
