// Hangar Board — pure logic (no hardware): calculations, config, weather parsing.
// Compiles on the ESP32 and on a desktop computer (for testing).
#pragma once
#include <string>
#include <vector>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <ArduinoJson.h>

namespace hb {

/* ---------------- calculations ---------------- */
inline double densityAltitudeFt(double tempC, double altimHpa, double elevFt) {
  double inHg = altimHpa * 0.0295299830714;
  double pa = elevFt + (29.92 - inHg) * 1000.0;          // pressure altitude
  double isa = 15.0 - 2.0 * pa / 1000.0;                 // standard temperature at that altitude
  return pa + 120.0 * (tempC - isa);
}

// Days since 1970-01-01 for a civil date (H. Hinnant's algorithm)
inline long daysFromCivil(int y, int m, int d) {
  y -= m <= 2;
  long era = (y >= 0 ? y : y - 399) / 400;
  unsigned yoe = (unsigned)(y - era * 400);
  unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + (long)doe - 719468;
}
inline bool parseDate(const std::string& s, int& y, int& m, int& d) {
  if (sscanf(s.c_str(), "%d-%d-%d", &y, &m, &d) != 3) return false;
  return y > 1900 && m >= 1 && m <= 12 && d >= 1 && d <= 31;
}
inline std::string fmtDate(const std::string& iso) {           // "2027-09-30" -> "Sep 30, 2027"
  static const char* M[] = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
  int y, m, d; if (!parseDate(iso, y, m, d)) return iso;
  char b[24]; snprintf(b, sizeof b, "%s %d, %d", M[m - 1], d, y); return b;
}

// Sunrise / sunset in minutes after 00:00 UTC (NOAA approximation, ~1-2 min accuracy).
inline bool sunTimesUTC(int y, int m, int d, double lat, double lon, double& rise, double& set) {
  const double kPi = 3.14159265358979, R = kPi / 180;
  long n = daysFromCivil(y, m, d) - daysFromCivil(y, 1, 1) + 1;
  bool leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
  double g = 2 * kPi / (leap ? 366 : 365) * (n - 1);
  double eqt = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g));
  double decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g) - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g);
  double c = cos(90.833 * R) / (cos(lat * R) * cos(decl)) - tan(lat * R) * tan(decl);
  if (c < -1 || c > 1) return false;
  double ha = acos(c) / R;
  rise = 720 - 4 * (lon + ha) - eqt;
  set = 720 - 4 * (lon - ha) - eqt;
  return true;
}

inline double parseVisib(const std::string& v) {             // "10+", "6", "1/2", "1 1/2", "P6"
  if (v.empty()) return -1;
  std::string s = v; s.erase(std::remove(s.begin(), s.end(), '+'), s.end()); if (!s.empty() && s[0] == 'P') s.erase(0, 1);
  double whole = 0; int a = 0, b = 0;
  if (sscanf(s.c_str(), "%lf %d/%d", &whole, &a, &b) == 3 && b) return whole + (double)a / b;
  if (sscanf(s.c_str(), "%d/%d", &a, &b) == 2 && b) return (double)a / b;
  return atof(s.c_str());
}

/* ---------------- TAF scan ---------------- */
struct TafAlert { int maxWind = 0, maxGust = 0, minCeil = 99999; double minVis = 99; bool ts = false; std::string wx; bool bad = false; std::string summary; };

inline bool isWxToken(const std::string& t) {
  static const char* codes[] = {"TS","FG","BR","RA","SN","DZ","DS","SS","FC","GR","GS","SQ","FU","HZ","DU","SH","PL","UP","VA","PO"};
  if (t == "NSW" || t.size() < 2 || t.size() > 9) return false;
  size_t i = 0; if (t[0] == '+' || t[0] == '-') i = 1; if (t.compare(i, 2, "VC") == 0) i += 2;
  if (i >= t.size()) return false;
  for (; i + 1 < t.size() + 1 && i < t.size(); i += 2) {
    bool ok = false; for (auto c : codes) if (t.compare(i, 2, c) == 0) ok = true;
    if (!ok && !(t.compare(i, 2, "MI") == 0 || t.compare(i, 2, "BC") == 0 || t.compare(i, 2, "PR") == 0 || t.compare(i, 2, "DR") == 0 || t.compare(i, 2, "BL") == 0 || t.compare(i, 2, "FZ") == 0)) return false;
  }
  return true;
}

inline TafAlert scanTaf(const std::string& raw) {
  TafAlert a; std::vector<std::string> tok; std::string cur;
  for (char ch : raw) { if (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t') { if (!cur.empty()) tok.push_back(cur); cur.clear(); } else cur += ch; }
  if (!cur.empty()) tok.push_back(cur);
  for (size_t i = 0; i < tok.size(); i++) {
    const std::string& t = tok[i];
    if (t.size() >= 7 && t.substr(t.size() - 2) == "KT") {                 // wind dddffGggKT / VRBffKT
      std::string w = t.substr(3, t.size() - 5); size_t g = w.find('G');
      int sp = atoi(w.substr(0, g).c_str()); a.maxWind = std::max(a.maxWind, sp);
      if (g != std::string::npos) a.maxGust = std::max(a.maxGust, atoi(w.substr(g + 1).c_str()));
    } else if ((t.rfind("BKN", 0) == 0 || t.rfind("OVC", 0) == 0) && t.size() >= 6) {
      a.minCeil = std::min(a.minCeil, atoi(t.substr(3, 3).c_str()) * 100);
    } else if (t.rfind("VV", 0) == 0 && t.size() >= 5 && isdigit((unsigned char)t[2])) {
      a.minCeil = std::min(a.minCeil, atoi(t.substr(2, 3).c_str()) * 100);
    } else if (t.size() >= 3 && t.substr(t.size() - 2) == "SM") {
      std::string v = t.substr(0, t.size() - 2);
      if (i > 0 && v.find('/') != std::string::npos && tok[i - 1].size() == 1 && isdigit((unsigned char)tok[i - 1][0])) v = tok[i - 1] + " " + v;
      a.minVis = std::min(a.minVis, parseVisib(v));
    } else if (isWxToken(t)) {
      if (t.find("TS") != std::string::npos) a.ts = true;
      if (a.wx.find(t) == std::string::npos) { if (!a.wx.empty()) a.wx += " "; a.wx += t; }
    }
  }
  std::vector<std::string> parts;
  char b[64];
  if (a.maxGust >= 20 || a.maxWind >= 20) { snprintf(b, sizeof b, "wind to %d kt%s", std::max(a.maxGust, a.maxWind), a.maxGust ? " (gusts)" : ""); parts.push_back(b); }
  if (a.minCeil < 3000) { snprintf(b, sizeof b, "ceiling as low as %d ft", a.minCeil); parts.push_back(b); }
  if (a.minVis < 5) { snprintf(b, sizeof b, "visibility down to %g mi", a.minVis); parts.push_back(b); }
  if (a.ts) parts.push_back("thunderstorms");
  else if (!a.wx.empty() && (a.wx.find("FG") != std::string::npos || a.wx.find('+') != std::string::npos || a.wx.find("DS") != std::string::npos || a.wx.find("SS") != std::string::npos)) parts.push_back(a.wx);
  a.bad = !parts.empty();
  if (a.bad) { a.summary = "Forecast: "; for (size_t i = 0; i < parts.size(); i++) a.summary += (i ? ", " : "") + parts[i]; }
  else a.summary = "Forecast: no significant weather";
  return a;
}

// Put each forecast change group (FM, TEMPO, BECMG, PROB) on its own line.
inline std::string formatTaf(const std::string& raw) {
  std::string out, tok; std::vector<std::string> toks;
  for (char ch : raw) { if (isspace((unsigned char)ch)) { if (!tok.empty()) toks.push_back(tok); tok.clear(); } else tok += ch; }
  if (!tok.empty()) toks.push_back(tok);
  for (size_t i = 0; i < toks.size(); i++) {
    const std::string& t = toks[i];
    bool brk = i > 0 && (t.rfind("FM", 0) == 0 || t == "TEMPO" || t == "BECMG" || (t.rfind("PROB", 0) == 0 && t.size() == 6));
    if (brk && !(toks[i - 1].rfind("PROB", 0) == 0)) out += "\n"; else if (i) out += " ";
    out += t;
  }
  return out;
}

/* ---------------- configuration ---------------- */
struct DueItem {
  std::string name; char group = 'a';      // 'a' aircraft, 'p' pilot
  char kind = 'd';                         // 'd' due date, 'h' Hobbs hours, 'b' both (whichever comes first)
  std::string dueDate; double dueHours = 0; int warnDays = 30; double warnHours = 5;
  std::string src;                         // "db" = imported from the maintenance database
};
struct Config {
  std::string tail = "N721NE", station = "KTUS", tz = "MST7";
  int panel = 0;                 // 0 GDEY075Z08 (red), 1 GDEY075T7, 2 Waveshare 7.5 V2
  int pinPreset = 0;             // 0 ESP32 dev board standard wiring, 1 Waveshare ESP32 driver board, 2 custom
  int cs = 5, dc = 17, rst = 16, busy = 4, sck = 18, mosi = 23;
  int refreshMin = 15, daCaution = 5000, staleMin = 90;
  double tach = 0; std::string tachDate;
  std::vector<DueItem> items; std::string note;
};

inline void applyPreset(Config& c, bool s3) {
  if (c.pinPreset == 1) { c.cs = 15; c.dc = 27; c.rst = 26; c.busy = 25; c.sck = 13; c.mosi = 14; }
  else if (c.pinPreset == 0) {
    if (s3) { c.cs = 10; c.dc = 9; c.rst = 8; c.busy = 7; c.sck = 12; c.mosi = 11; }
    else { c.cs = 5; c.dc = 17; c.rst = 16; c.busy = 4; c.sck = 18; c.mosi = 23; }
  }
}

inline std::string configToJson(const Config& c) {
  JsonDocument d;
  d["tail"] = c.tail; d["station"] = c.station; d["tz"] = c.tz; d["panel"] = c.panel; d["pinPreset"] = c.pinPreset;
  JsonObject p = d["pins"].to<JsonObject>(); p["cs"] = c.cs; p["dc"] = c.dc; p["rst"] = c.rst; p["busy"] = c.busy; p["sck"] = c.sck; p["mosi"] = c.mosi;
  d["refreshMin"] = c.refreshMin; d["daCaution"] = c.daCaution; d["staleMin"] = c.staleMin;
  d["tach"] = c.tach; d["tachDate"] = c.tachDate; d["note"] = c.note;
  JsonArray a = d["items"].to<JsonArray>();
  for (auto& it : c.items) {
    JsonObject o = a.add<JsonObject>(); o["name"] = it.name; o["group"] = std::string(1, it.group); o["kind"] = std::string(1, it.kind);
    if (it.kind != 'd') { o["dueHours"] = it.dueHours; o["warnHours"] = it.warnHours; }
    if (it.kind != 'h') { o["dueDate"] = it.dueDate; o["warnDays"] = it.warnDays; }
    if (!it.src.empty()) o["src"] = it.src;
  }
  std::string out; serializeJson(d, out); return out;
}

// Merge JSON into config. Returns false if the JSON can't be read.
inline bool configFromJson(Config& c, const std::string& js, bool s3 = false) {
  JsonDocument d; if (deserializeJson(d, js)) return false;
  if (d["tail"].is<const char*>()) c.tail = d["tail"].as<std::string>();
  if (d["station"].is<const char*>()) { c.station = d["station"].as<std::string>(); for (auto& ch : c.station) ch = toupper((unsigned char)ch); }
  if (d["tz"].is<const char*>() && d["tz"].as<std::string>().size() > 2) c.tz = d["tz"].as<std::string>();
  if (!d["panel"].isNull()) c.panel = std::max(0, std::min(2, d["panel"].as<int>()));
  if (!d["pinPreset"].isNull()) c.pinPreset = std::max(0, std::min(2, d["pinPreset"].as<int>()));
  JsonObject p = d["pins"];
  if (!p.isNull() && c.pinPreset == 2) { c.cs = p["cs"] | c.cs; c.dc = p["dc"] | c.dc; c.rst = p["rst"] | c.rst; c.busy = p["busy"] | c.busy; c.sck = p["sck"] | c.sck; c.mosi = p["mosi"] | c.mosi; }
  applyPreset(c, s3);
  if (!d["refreshMin"].isNull()) c.refreshMin = std::max(5, std::min(120, d["refreshMin"].as<int>()));
  if (!d["daCaution"].isNull()) c.daCaution = d["daCaution"].as<int>();
  if (!d["staleMin"].isNull()) c.staleMin = d["staleMin"].as<int>();
  if (!d["tach"].isNull()) c.tach = d["tach"].as<double>();
  if (d["tachDate"].is<const char*>()) c.tachDate = d["tachDate"].as<std::string>();
  if (d["note"].is<const char*>()) c.note = d["note"].as<std::string>();
  if (d["items"].is<JsonArray>()) {
    c.items.clear();
    for (JsonObject o : d["items"].as<JsonArray>()) {
      DueItem it; it.name = o["name"] | std::string(""); if (it.name.empty()) continue;
      std::string g = o["group"] | std::string("a"), k = o["kind"] | std::string("d");
      it.group = g.empty() ? 'a' : g[0]; it.kind = k.empty() ? 'd' : k[0];
      it.dueDate = o["dueDate"] | std::string(""); it.dueHours = o["dueHours"] | 0.0;
      it.warnDays = o["warnDays"] | 30; it.warnHours = o["warnHours"] | 5.0; it.src = o["src"] | std::string("");
      c.items.push_back(it);
    }
  }
  return true;
}

/* ---------------- what the screen shows ---------------- */
struct Line { std::string label, value; bool alert = false; long sortKey = 0; };
struct BoardData {
  std::string tail, station, updated, footer;
  bool haveWx = false; std::string wxError;
  std::string fltCat, wind, vis, sky, temp, altim, da, sun, age, rawMetar;
  bool catAlert = false, windAlert = false, daAlert = false, ageAlert = false, visAlert = false, skyAlert = false;
  std::string rawTaf; TafAlert taf; bool haveTaf = false;
  std::vector<Line> aircraft, pilot; std::string tachLine; std::string note;
};

// Turn a METAR JSON response (array from aviationweather.gov) into display text.
// nowEpoch: current time (UTC seconds); tzOffsetMin: local offset (Arizona = -420).
inline bool fillWeather(BoardData& b, const Config& c, const std::string& metarJson, long nowEpoch, int tzOffsetMin) {
  JsonDocument d; if (deserializeJson(d, metarJson)) { b.wxError = "Weather data unreadable"; return false; }
  JsonObject m = d.is<JsonArray>() ? d[0].as<JsonObject>() : d.as<JsonObject>();
  if (m.isNull()) { b.wxError = "No METAR for " + c.station; return false; }
  char t[96];
  b.fltCat = m["fltCat"] | std::string("");
  b.catAlert = !b.fltCat.empty() && b.fltCat != "VFR";
  // wind
  int spd = m["wspd"] | 0, gst = m["wgst"] | 0; std::string wdir;
  if (m["wdir"].is<const char*>()) wdir = m["wdir"].as<std::string>(); else if (!m["wdir"].isNull()) { snprintf(t, sizeof t, "%03d", m["wdir"].as<int>()); wdir = t; }
  if (spd == 0) b.wind = "Calm";
  else { snprintf(t, sizeof t, "%s%s at %d kt", wdir.c_str(), wdir == "VRB" ? "" : "\xB0", spd); b.wind = t; if (gst) { snprintf(t, sizeof t, " G%d", gst); b.wind += t; } }
  b.windAlert = spd >= 20 || gst >= 20;
  // visibility
  std::string vs; if (m["visib"].is<const char*>()) vs = m["visib"].as<std::string>(); else if (!m["visib"].isNull()) { snprintf(t, sizeof t, "%g", m["visib"].as<double>()); vs = t; }
  double vis = parseVisib(vs);
  b.vis = vs.empty() ? "--" : (vs + " mi"); b.visAlert = vis >= 0 && vis < 5;
  std::string wx = m["wxString"] | std::string(""); if (!wx.empty()) b.vis += " " + wx;
  // sky
  b.sky.clear(); int ceil = 99999;
  for (JsonObject cl : m["clouds"].as<JsonArray>()) {
    std::string cov = cl["cover"] | std::string(""); int base = cl["base"] | -1;
    if (!b.sky.empty()) b.sky += " ";
    if (base >= 0) { snprintf(t, sizeof t, "%s %d", cov.c_str(), base); b.sky += t; } else b.sky += cov;
    if ((cov == "BKN" || cov == "OVC" || cov == "OVX") && base >= 0) ceil = std::min(ceil, base);
  }
  if (b.sky.empty() || b.sky == "CLR" || b.sky == "SKC" || b.sky == "CAVOK") b.sky = "Clear";
  b.skyAlert = ceil < 3000;
  // temperature, altimeter, density altitude
  double tc = m["temp"] | -99.0, dc = m["dewp"] | -99.0, alt = m["altim"] | 0.0, elevM = m["elev"] | 0.0;
  if (tc > -90) { snprintf(t, sizeof t, "%.0f\xB0" "C (%.0f\xB0" "F) / dew %.0f\xB0" "C", tc, tc * 9 / 5 + 32, dc); b.temp = t; }
  if (alt > 0) { snprintf(t, sizeof t, "%.2f in", alt * 0.0295299830714); b.altim = t; }
  if (alt > 0 && tc > -90) {
    double da = densityAltitudeFt(tc, alt, elevM * 3.28084);
    long r = lround(da / 100.0) * 100;
    snprintf(t, sizeof t, "%ld,%03ld ft", r / 1000, labs(r % 1000)); b.da = r >= 1000 ? t : std::to_string(r) + " ft";
    b.daAlert = da >= c.daCaution;
  }
  // sunrise / sunset (local)
  double lat = m["lat"] | 0.0, lon = m["lon"] | 0.0; long localDays = (nowEpoch + tzOffsetMin * 60L) / 86400;
  long z = localDays + 719468, era = (z >= 0 ? z : z - 146096) / 146097; unsigned doe = (unsigned)(z - era * 146097);
  unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; int y = (int)(yoe + era * 400); unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  unsigned mp = (5 * doy + 2) / 153; int dd = doy - (153 * mp + 2) / 5 + 1; int mm = mp < 10 ? mp + 3 : mp - 9; y += mm <= 2;
  double rise, set;
  if (sunTimesUTC(y, mm, dd, lat, lon, rise, set)) {
    int r = ((int)lround(rise) + tzOffsetMin + 1440) % 1440, s = ((int)lround(set) + tzOffsetMin + 1440) % 1440;
    snprintf(t, sizeof t, "Sunrise %02d%02d  Sunset %02d%02d", r / 60, r % 60, s / 60, s % 60); b.sun = t;
  }
  // age
  long obs = m["obsTime"] | 0L; long ageMin = obs ? (nowEpoch - obs) / 60 : -1;
  if (ageMin >= 0) { snprintf(t, sizeof t, "METAR %ld min old", ageMin); b.age = t; b.ageAlert = ageMin > c.staleMin; }
  b.rawMetar = m["rawOb"] | std::string("");
  b.haveWx = true; b.wxError.clear();
  return true;
}

// Fill the due-item lists. todayDays = local days since 1970.
inline void fillItems(BoardData& b, const Config& c, long todayDays) {
  b.aircraft.clear(); b.pilot.clear(); char t[64];
  for (auto& it : c.items) {
    Line l; l.label = it.name;
    bool useH = it.kind != 'd' && it.dueHours > 0 && c.tach > 0;
    int y, m, d; bool useD = it.kind != 'h' && parseDate(it.dueDate, y, m, d);
    if (!useH && !useD) continue;
    std::string hv, dv; bool ha = false, da = false, hOver = false, dOver = false; long hKey = 1L << 30, dKey = 1L << 30;
    if (useH) {
      double left = it.dueHours - c.tach;
      if (left < 0) { snprintf(t, sizeof t, "OVERDUE %.1f hr", -left); ha = hOver = true; }
      else { snprintf(t, sizeof t, "%.1f hr left", left); ha = left <= it.warnHours; }
      hv = t; hKey = (long)(left * 10);
    }
    if (useD) {
      long left = daysFromCivil(y, m, d) - todayDays;
      if (left < 0) { dv = "OVERDUE " + fmtDate(it.dueDate); da = dOver = true; }
      else if (left == 0) { dv = "DUE TODAY " + fmtDate(it.dueDate); da = true; }
      else if (left <= it.warnDays) { snprintf(t, sizeof t, "%ld day%s - ", left, left == 1 ? "" : "s"); dv = t + fmtDate(it.dueDate); da = true; }
      else dv = fmtDate(it.dueDate);
      dKey = left;
    }
    l.alert = ha || da;
    if (useH && useD) {            // show the one that matters most
      if (hOver || (ha && !dOver && !da)) l.value = hv; else if (dOver || da) l.value = dv;
      else l.value = hv + " / " + dv;
    } else l.value = useH ? hv : dv;
    l.sortKey = std::min(hKey, dKey);
    (it.group == 'p' ? b.pilot : b.aircraft).push_back(l);
  }
  auto byDue = [](const Line& a, const Line& b) { return a.sortKey < b.sortKey; };
  std::sort(b.aircraft.begin(), b.aircraft.end(), byDue); std::sort(b.pilot.begin(), b.pilot.end(), byDue);
  if (c.tach > 0) { snprintf(t, sizeof t, "Hobbs %.1f", c.tach); b.tachLine = t; if (!c.tachDate.empty()) b.tachLine += " (as of " + fmtDate(c.tachDate) + ")"; }
  b.note = c.note;
}

} // namespace hb
