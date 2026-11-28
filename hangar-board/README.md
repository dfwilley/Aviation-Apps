# Hangar Board

7.5" e-paper hangar status board for an ESP32 or a Raspberry Pi Pico W: current METAR (decoded), TAF with a plain-language summary, density altitude, sunrise/sunset, aircraft maintenance and pilot currency due items, and a note. Due items can be loaded from the Access maintenance database (Recurring Maintenance and Service Bulletins tables, read-only) on the board's settings page. Out-of-limits items turn red on the GDEY075Z08 three-color panel (⚠ marker on black-and-white panels).

**Install on an ESP32:** open https://dfwilley.github.io/Aviation-Apps/hangar-board/ in Chrome or Edge on a computer and click *Connect and install*.

**Install on a Raspberry Pi Pico W:** hold the Pico's BOOTSEL button while plugging it into the computer. It shows up as a drive named RPI-RP2. Copy `firmware/hangarboard-picow.uf2` onto that drive. The Pico restarts by itself. Only the Pico W works (the plain Pico has no Wi-Fi). Full step-by-step build instructions are in [PICO-BUILD.md](PICO-BUILD.md).

Supported displays: Good Display GDEY075Z08 (black/white/red), Good Display GDEY075T7, Waveshare 7.5" V2, Waveshare 7.5" (B) V2 (black/white/red). Supported boards: ESP32, ESP32-S3, Raspberry Pi Pico W.

On the Pico W the display uses the pins of Waveshare's Pico e-Paper modules, so the Pico plugs straight into the back of one: DC GP8, CS GP9, CLK GP10, DIN GP11, RST GP12, BUSY GP13, power from 3V3. An adapter board such as the DESPI-C02 can be wired to the same pins.

**Hobbs time from MyFlightbook (firmware 1.3, optional):** the board can read the owner's latest flights from MyFlightbook a few times a day and use the highest ending Hobbs for the aircraft named on the board. It only reads flights, never lowers a Hobbs typed on the settings page, and never sees the MyFlightbook password: the owner approves it on MyFlightbook's own site (OAuth with PKCE). One-time setup steps are on [mfb.html](https://dfwilley.github.io/Aviation-Apps/hangar-board/mfb.html), which is also the page MyFlightbook sends the browser back to after approval; it passes the one-time code on to the board on the local network. The access keys are stored on the board, apart from the settings, and are not included in a settings backup. As with the weather, the connection is encrypted but the server certificate is not pinned.

The Pico W version's Wi-Fi setup and settings page have been confirmed on a real board (firmware 1.2.1). The MyFlightbook connection in 1.3 has been compiled and its logic tested, but not yet run against MyFlightbook. The checked-in ESP32 files are still version 1.1.

## Building from source
Arduino IDE with the ESP32 core 3.0.x, partition scheme "Huge APP". Libraries: GxEPD2, Adafruit GFX, ArduinoJson 7, WiFiManager (tzapu). For the Pico W, use the Raspberry Pi Pico/RP2040 core by Earle Philhower, board "Raspberry Pi Pico W", flash size "2MB (Sketch: 1792KB, FS: 256KB)"; WiFiManager is not needed. The `hangar-board-build.yml` workflow compiles all three boards on GitHub whenever the firmware changes and, on a work branch, saves the new Pico W file into `firmware/`. Open `HangarBoard/HangarBoard.ino`. After editing anything in `HangarBoard/web/`, run `python3 tools/embed.py` to regenerate `web_assets.h`. `tests/test_pins.cpp` and `tests/test_mfb.cpp` check the pin choices and the MyFlightbook logic on an ordinary computer (the workflow runs both). The Access reader is mdb-reader (MIT license), bundled for browsers from `tools/mdb-entry.js` with esbuild.

Weather data: NWS Aviation Weather Center data API (aviationweather.gov). For situational awareness only.
