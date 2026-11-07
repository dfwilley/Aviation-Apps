# Hangar Log (Hangar Voice Log)

A native iPhone app for recording maintenance work on N721NE by voice.

- Tap **New Entry**, tap **Record Voice Note**, and describe the work out loud.
- The recording is converted to text on the phone. Fix any misheard words.
- Add the date, tach and Hobbs times, the type of work, and photos.
- The app writes a **draft logbook entry** you can copy, share or print.
- **Export All as Spreadsheet** creates a CSV file of every entry.

Nothing leaves the phone unless you share or export it.

## How it's built and installed

There's no Mac involved. GitHub Actions builds the app on GitHub's macOS machines:

- **Hangar Voice Log - build iPhone app** runs the tests and publishes an unsigned
  `HangarVoiceLog.ipa` on the Releases page, for Sideloadly.
- **Hangar Voice Log - upload to TestFlight** signs the app and uploads it to
  App Store Connect for TestFlight.

Both run on every push to `main` that changes this folder. See
[INSTALL.md](INSTALL.md) for installing either way.

## Data from Access

A daily Claude scheduled task runs `tools/make_hangar_data.py` on
`Maintenance Record_be.accdb` and, when something changed, saves a new
`Hangar Log Data <date>.json` in Dropbox › Dropbox Documents › N721NE ›
Maintenance Software. The app reads the newest one when it opens.

## Files

| Path | What it is |
|---|---|
| `project.yml` | Project definition (app settings, permissions, targets) |
| `HangarVoiceLog/` | App source code (SwiftUI) |
| `HangarVoiceLogTests/` | Unit tests |
| `tools/make_hangar_data.py` | Builds the Hangar Log Data file from Access |
| `tools/asc_*.py` | TestFlight signing and upload helpers |
| `../.github/workflows/hangar-voice-log-*.yml` | Cloud builds |
