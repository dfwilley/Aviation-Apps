# Hangar Board

ESP32 + 7.5" e-paper hangar status board: current METAR (decoded), TAF with a plain-language summary, density altitude, sunrise/sunset, aircraft maintenance and pilot currency due items, and a note. Due items can be loaded from the Access maintenance database (Recurring Maintenance and Service Bulletins tables, read-only) on the board's settings page. Out-of-limits items turn red on the GDEY075Z08 three-color panel (⚠ marker on black-and-white panels).

**Install:** open the GitHub Pages site for this repository in Chrome or Edge on a computer and click *Connect and install*.

Supported displays: Good Display GDEY075Z08 (black/white/red), Good Display GDEY075T7, Waveshare 7.5" V2. Supported boards: ESP32, ESP32-S3.

## Building from source
Arduino IDE with the ESP32 core 3.0.x, partition scheme "Huge APP". Libraries: GxEPD2, Adafruit GFX, ArduinoJson 7, WiFiManager (tzapu). Open `HangarBoard/HangarBoard.ino`. After editing anything in `HangarBoard/web/`, run `python3 tools/embed.py` to regenerate `web_assets.h`. The Access reader is mdb-reader (MIT license), bundled for browsers from `tools/mdb-entry.js` with esbuild.

Weather data: NWS Aviation Weather Center data API (aviationweather.gov). For situational awareness only.
