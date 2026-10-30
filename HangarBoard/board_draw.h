// Hangar Board — screen layout for an 800 x 480 e-paper panel.
// Uses only the Adafruit GFX drawing interface, so the same code renders on the
// e-paper display and in a desktop preview.
#pragma once
#include <Adafruit_GFX.h>
#include <Fonts/FreeSans9pt7b.h>
#include <Fonts/FreeSansBold9pt7b.h>
#include <Fonts/FreeSans12pt7b.h>
#include <Fonts/FreeSansBold12pt7b.h>
#include <Fonts/FreeSansBold18pt7b.h>
#include <Fonts/FreeMono9pt7b.h>
#include "board_logic.h"

namespace hb {

const uint16_t C_BLACK = 0x0000, C_WHITE = 0xFFFF, C_RED = 0xF800;

struct Painter {
  Adafruit_GFX& g; bool red;
  Painter(Adafruit_GFX& gfx, bool hasRed) : g(gfx), red(hasRed) {}
  uint16_t alertColor() const { return red ? C_RED : C_BLACK; }

  int width(const GFXfont* f, const std::string& s) {
    g.setFont(f); int16_t x1, y1; uint16_t w = 0, h; std::string t;
    int degs = 0; for (char c : s) { if (c == '\xB0') degs++; else t += c; }
    g.getTextBounds(t.c_str(), 0, 0, &x1, &y1, &w, &h);
    return (int)w + degs * 9 + (t.empty() ? 0 : x1);
  }
  // Print text; '\xB0' is drawn as a small degree circle (the built-in fonts have no degree sign).
  int text(const GFXfont* f, int x, int y, const std::string& s, uint16_t color) {
    g.setFont(f); g.setTextColor(color); g.setTextWrap(false); g.setCursor(x, y);
    std::string seg;
    auto flush = [&]() { if (!seg.empty()) { g.print(seg.c_str()); seg.clear(); } };
    int cap = (f == &FreeSansBold18pt7b) ? 25 : (f == &FreeSans12pt7b || f == &FreeSansBold12pt7b) ? 17 : 13;
    int r = cap > 20 ? 3 : 2;
    for (char c : s) {
      if (c == '\xB0') { flush(); int cx = g.getCursorX() + r + 1; g.drawCircle(cx, y - cap + r, r, color); if (r > 2) g.drawCircle(cx, y - cap + r, r - 1, color); g.setCursor(g.getCursorX() + 2 * r + 4, y); }
      else seg += c;
    }
    flush(); return g.getCursorX();
  }
  void textRight(const GFXfont* f, int xr, int y, const std::string& s, uint16_t color) { text(f, xr - width(f, s), y, s, color); }
  // Marker drawn before alert text on black-and-white panels
  int alertMark(int x, int y, int size = 12) {
    if (red) return x;
    g.fillTriangle(x, y, x + size, y, x + size / 2, y - size, C_BLACK);
    g.fillRect(x + size / 2 - 1, y - size + 4, 2, size - 7, C_WHITE); g.fillRect(x + size / 2 - 1, y - 3, 2, 2, C_WHITE);
    return x + size + 5;
  }
  // Word-wrap s into lines no wider than w
  std::vector<std::string> wrap(const GFXfont* f, const std::string& s, int w) {
    std::vector<std::string> out; std::string line, word;
    auto push = [&](std::string wd) {
      std::string cand = line.empty() ? wd : line + " " + wd;
      if (width(f, cand) <= w || line.empty()) line = cand; else { out.push_back(line); line = wd; }
    };
    for (char c : s) { if (c == ' ' || c == '\n') { if (!word.empty()) push(word); word.clear(); if (c == '\n' && !line.empty()) { out.push_back(line); line.clear(); } } else word += c; }
    if (!word.empty()) push(word); if (!line.empty()) out.push_back(line);
    return out;
  }
};

inline void drawBoard(Adafruit_GFX& gfx, const BoardData& b, bool hasRed) {
  Painter p(gfx, hasRed); Adafruit_GFX& g = gfx;
  const int W = 800, H = 480, L = 14, COL = 478, R0 = 494, R1 = 786;
  g.fillScreen(C_WHITE);
  // header bar
  g.fillRect(0, 0, W, 42, C_BLACK);
  p.text(&FreeSansBold12pt7b, L, 29, b.tail + "  hangar board", C_WHITE);
  p.textRight(&FreeSans9pt7b, W - L, 27, b.updated, C_WHITE);

  /* ---------- left: weather ---------- */
  int y = 66;
  p.text(&FreeSansBold9pt7b, L, y, b.station + " weather", C_BLACK);
  if (!b.wxError.empty()) { int x = p.alertMark(L + 150, y); p.text(&FreeSansBold9pt7b, x, y, b.haveWx ? "Update failed - showing last report" : b.wxError, p.alertColor()); }
  if (!b.haveWx) {
    p.text(&FreeSansBold18pt7b, L, 120, "Weather unavailable", p.alertColor());
    int yy = 160; for (auto& ln : p.wrap(&FreeSans9pt7b, b.wxError, COL - L - 10)) { p.text(&FreeSans9pt7b, L, yy, ln, C_BLACK); yy += 22; }
  } else {
    y = 106; int x = L;
    std::string cat = b.fltCat.empty() ? "--" : b.fltCat;
    if (b.catAlert) x = p.alertMark(x, y - 4, 16);
    x = p.text(&FreeSansBold18pt7b, x, y, cat, b.catAlert ? p.alertColor() : C_BLACK) + 18;
    const GFXfont* wf = p.width(&FreeSansBold18pt7b, b.wind) <= COL - x - 8 ? &FreeSansBold18pt7b : &FreeSansBold12pt7b;
    if (b.windAlert) x = p.alertMark(x, y - 4, 16);
    p.text(wf, x, y, b.wind, b.windAlert ? p.alertColor() : C_BLACK);
    struct Row { const char* label; std::string value; bool alert; bool bold; };
    Row rows[] = {
      {"Visibility", b.vis, b.visAlert, false}, {"Sky", b.sky, b.skyAlert, false}, {"Temp", b.temp, false, false},
      {"Altimeter", b.altim, false, false}, {"Density alt", b.da, b.daAlert, true}, {"Sun", b.sun, false, false}};
    y = 142;
    for (auto& r : rows) {
      if (r.value.empty()) continue;
      p.text(&FreeSans9pt7b, L, y, r.label, C_BLACK);
      int vx = L + 112; if (r.alert) vx = p.alertMark(vx, y - 2);
      std::string v = r.value; if (std::string(r.label) == "Sun") v = v;   // already formatted
      p.text(r.bold ? &FreeSansBold12pt7b : &FreeSans12pt7b, vx, y, v, r.alert ? p.alertColor() : C_BLACK);
      y += 28;
    }
    if (!b.age.empty()) { int ax = L; if (b.ageAlert) ax = p.alertMark(ax, y - 2); p.text(&FreeSans9pt7b, ax, y, b.age + (b.ageAlert ? " - may be out of date" : ""), b.ageAlert ? p.alertColor() : C_BLACK); y += 8; }
    // TAF
    y = std::max(y + 4, 318);
    g.drawFastHLine(L, y, COL - L - 6, C_BLACK); y += 22;
    if (b.haveTaf) {
      int tx = L; if (b.taf.bad) tx = p.alertMark(tx, y - 2);
      auto sl = p.wrap(&FreeSansBold9pt7b, b.taf.summary, COL - tx - 8);
      for (size_t i = 0; i < sl.size() && i < 2; i++) { p.text(&FreeSansBold9pt7b, i ? L : tx, y, sl[i], b.taf.bad ? p.alertColor() : C_BLACK); y += 20; }
      y += 2;
      auto lines = p.wrap(&FreeMono9pt7b, b.rawTaf, COL - L - 8);
      for (size_t i = 0; i < lines.size(); i++) {
        if (y > H - 30) break;
        std::string ln = lines[i];
        if (y + 17 > H - 30 && i + 1 < lines.size()) ln = ln.substr(0, std::min<size_t>(ln.size(), 36)) + "...";
        p.text(&FreeMono9pt7b, L, y, ln, C_BLACK); y += 17;
      }
    } else p.text(&FreeSans9pt7b, L, y, "No TAF available", C_BLACK);
  }

  /* ---------- right: due items ---------- */
  g.drawFastVLine(COL + 6, 52, H - 52 - 26, C_BLACK);
  const int bottom = H - 30;
  auto fitsOne = [&](const Line& it) {
    int lw = p.width(it.alert ? &FreeSansBold9pt7b : &FreeSans9pt7b, it.label) + (it.alert && !hasRed ? 17 : 0);
    return lw + 14 + p.width(&FreeSansBold9pt7b, it.value) <= R1 - R0;
  };
  auto rowH = [&](const Line& it) { return fitsOne(it) ? 23 : 42; };
  // Budget the space so the pilot section always shows; trim the least urgent aircraft items if needed.
  int fixed = 26 + (b.tachLine.empty() ? 0 : 21) + 8 + 26 + 4, pilotH = 0;
  for (auto& it : b.pilot) pilotH += rowH(it);
  if (b.pilot.empty()) pilotH = 24;
  int roomA = (bottom - 66) - fixed - pilotH, usedA = 0; size_t showA = 0;
  for (size_t i = 0; i < b.aircraft.size(); i++) {
    int h = rowH(b.aircraft[i]); bool last = i + 1 == b.aircraft.size();
    if (usedA + h + (last ? 0 : 20) > roomA) break;
    usedA += h; showA++;
  }
  y = 66;
  auto row = [&](const Line& it) {
    uint16_t col = it.alert ? p.alertColor() : C_BLACK;
    int nx = R0; if (it.alert) nx = p.alertMark(nx, y - 2);
    p.text(it.alert ? &FreeSansBold9pt7b : &FreeSans9pt7b, nx, y, it.label, col);
    if (!fitsOne(it)) y += 19;
    p.textRight(&FreeSansBold9pt7b, R1, y, it.value, col);
    y += 23;
  };
  p.text(&FreeSansBold12pt7b, R0, y + 2, "Aircraft", C_BLACK); y += 26;
  if (!b.tachLine.empty()) { p.text(&FreeSans9pt7b, R0, y, b.tachLine, C_BLACK); y += 21; }
  if (b.aircraft.empty()) { p.text(&FreeSans9pt7b, R0, y, "Nothing set up yet", C_BLACK); y += 23; }
  for (size_t i = 0; i < showA; i++) row(b.aircraft[i]);
  if (showA < b.aircraft.size()) {
    char more[48]; snprintf(more, sizeof more, "+ %d more, not due soon", (int)(b.aircraft.size() - showA));
    bool hiddenAlert = false; for (size_t i = showA; i < b.aircraft.size(); i++) hiddenAlert |= b.aircraft[i].alert;
    if (hiddenAlert) snprintf(more, sizeof more, "+ %d more (some due!) - see settings", (int)(b.aircraft.size() - showA));
    p.text(&FreeSans9pt7b, R0, y, more, hiddenAlert ? p.alertColor() : C_BLACK); y += 20;
  }
  y += 8;
  p.text(&FreeSansBold12pt7b, R0, y + 2, "Pilot", C_BLACK); y += 26;
  if (b.pilot.empty()) { p.text(&FreeSans9pt7b, R0, y, "Nothing set up yet", C_BLACK); y += 23; }
  for (auto& it : b.pilot) { if (y > bottom) break; row(it); }
  if (!b.note.empty() && y + 44 <= bottom) {
    y += 6; p.text(&FreeSansBold12pt7b, R0, y + 2, "Note", C_BLACK); y += 24;
    for (auto& ln : p.wrap(&FreeSans9pt7b, b.note, R1 - R0)) { if (y > bottom) break; p.text(&FreeSans9pt7b, R0, y, ln, C_BLACK); y += 19; }
  }
  // footer
  g.drawFastHLine(0, H - 24, W, C_BLACK);
  p.text(&FreeSans9pt7b, L, H - 7, b.footer, C_BLACK);
}

} // namespace hb
