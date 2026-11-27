// Checks the display pin choices for each kind of board. Runs on an ordinary computer:
//   g++ -std=c++17 -I <ArduinoJson>/src -I ../HangarBoard test_pins.cpp -o test_pins && ./test_pins
#include "board_logic.h"
#include <cstdio>
using namespace hb;

static int failed = 0;
static void pins(const char* what, const Config& c, int cs, int dc, int rst, int busy, int sck, int mosi) {
  bool ok = c.cs == cs && c.dc == dc && c.rst == rst && c.busy == busy && c.sck == sck && c.mosi == mosi;
  printf("%s %s\n", ok ? "ok  " : "FAIL", what); if (!ok) failed++;
}
static void check(const char* what, bool ok) { printf("%s %s\n", ok ? "ok  " : "FAIL", what); if (!ok) failed++; }
static Config custom(int cs, int dc, int rst, int busy, int sck, int mosi) {
  Config c; c.pinPreset = 2; c.cs = cs; c.dc = dc; c.rst = rst; c.busy = busy; c.sck = sck; c.mosi = mosi; return c;
}

int main() {
  // ESP32 and ESP32-S3: unchanged from version 1.1
  { Config c; applyPreset(c, BOARD_ESP32); pins("ESP32 standard wiring", c, 5, 17, 16, 4, 18, 23); }
  { Config c; applyPreset(c, BOARD_ESP32S3); pins("ESP32-S3 standard wiring", c, 10, 9, 8, 7, 12, 11); }
  { Config c; c.pinPreset = 1; applyPreset(c, BOARD_ESP32); pins("Waveshare ESP32 driver board", c, 15, 27, 26, 25, 13, 14); }
  { Config c = custom(1, 2, 3, 6, 7, 8); applyPreset(c, BOARD_ESP32); pins("ESP32 custom pins kept as entered", c, 1, 2, 3, 6, 7, 8); }
  { Config c; configFromJson(c, "{\"pinPreset\":1}"); pins("settings without a board name mean ESP32", c, 15, 27, 26, 25, 13, 14); }

  // Pico W
  { Config c; applyPreset(c, BOARD_PICO_W); pins("Pico W, Waveshare module", c, 9, 8, 12, 13, 10, 11); check("  spare input pin avoids the display pins", picoSpareRx(c) == 28); }
  { Config c; c.pinPreset = 1; applyPreset(c, BOARD_PICO_W); pins("Pico W, adapter board", c, 9, 8, 12, 13, 10, 11); }
  { Config c = custom(17, 20, 21, 22, 18, 19); applyPreset(c, BOARD_PICO_W); pins("Pico W custom pins on the first bus", c, 17, 20, 21, 22, 18, 19); check("  spare input pin", picoSpareRx(c) == 16); }
  { Config c = custom(5, 17, 16, 4, 18, 23); applyPreset(c, BOARD_PICO_W); pins("Pico W: pin 23 is not usable, falls back", c, 9, 8, 12, 13, 10, 11); }
  { Config c = custom(9, 8, 12, 13, 10, 19); applyPreset(c, BOARD_PICO_W); pins("Pico W: clock and data on different buses, falls back", c, 9, 8, 12, 13, 10, 11); }
  { Config c = custom(9, 9, 12, 13, 10, 11); applyPreset(c, BOARD_PICO_W); pins("Pico W: same pin used twice, falls back", c, 9, 8, 12, 13, 10, 11); }
  { Config c; configFromJson(c, "{\"pinPreset\":2,\"pins\":{\"cs\":40,\"dc\":8,\"rst\":12,\"busy\":13,\"sck\":10,\"mosi\":11}}", BOARD_PICO_W); pins("Pico W: pin 40 does not exist, falls back", c, 9, 8, 12, 13, 10, 11); }

  // display choice
  { Config c; configFromJson(c, "{\"panel\":3}"); check("display choice 3 (Waveshare red) is accepted", c.panel == 3); }
  { Config c; configFromJson(c, "{\"panel\":9}"); check("unknown display choice is limited to the last one", c.panel == 3); }

  printf(failed ? "\n%d check(s) FAILED\n" : "\nAll checks passed\n", failed);
  return failed ? 1 : 0;
}
