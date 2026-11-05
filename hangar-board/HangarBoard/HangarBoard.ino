/*
  Hangar Board — ESP32 + 7.5" e-paper status board for the hangar.
  Shows current METAR (decoded), density altitude, sunrise/sunset and TAF for one
  airport, plus aircraft maintenance and pilot currency due items. Due items can be
  loaded from the Access maintenance database on the settings page (read-only).

  Weather: aviationweather.gov (NWS Aviation Weather Center data API).
  First power-up: join the Wi-Fi network "HangarBoard-Setup" on your phone and
  enter your hangar Wi-Fi. Settings page afterward: http://hangarboard.local
*/
#define ENABLE_GxEPD2_GFX 1   // lets one program drive any of the three displays
#include <WiFi.h>
#include <WiFiManager.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <Preferences.h>
#include <SPI.h>
#include <GxEPD2_BW.h>
#include <GxEPD2_3C.h>
#include <time.h>
#include "board_logic.h"
#include "board_draw.h"
#include "web_assets.h"

using namespace hb;

#if CONFIG_IDF_TARGET_ESP32S3
static const bool IS_S3 = true;
#else
static const bool IS_S3 = false;
#endif
static const char* FW_VERSION = "1.1";
static const char* AP_NAME = "HangarBoard-Setup";

Config cfg;
BoardData data;
Preferences prefs;
WebServer server(80);
WiFiManager wm;
GxEPD2_GFX* epd = nullptr;
bool epdRed = false;
unsigned long lastUpdate = 0;
bool wantUpdate = true, wantRestart = false, timeOk = false;
std::string lastMetarRaw, lastTafRaw, lastUpdatedText;

/* ---------- settings storage ---------- */
void loadConfig() {
  applyPreset(cfg, IS_S3);
  prefs.begin("hb", true); String s = prefs.getString("cfg", ""); prefs.end();
  if (s.length()) configFromJson(cfg, std::string(s.c_str()), IS_S3);
}
void saveConfig() { prefs.begin("hb", false); prefs.putString("cfg", configToJson(cfg).c_str()); prefs.end(); }

/* ---------- display ---------- */
void makeDisplay() {
  SPI.end();
  SPI.begin(cfg.sck, -1, cfg.mosi, cfg.cs);
  switch (cfg.panel) {
    case 0: epd = new GxEPD2_3C<GxEPD2_750c_GDEY075Z08, GxEPD2_750c_GDEY075Z08::HEIGHT / 4>(GxEPD2_750c_GDEY075Z08(cfg.cs, cfg.dc, cfg.rst, cfg.busy)); epdRed = true; break;
    case 1: epd = new GxEPD2_BW<GxEPD2_750_GDEY075T7, GxEPD2_750_GDEY075T7::HEIGHT / 2>(GxEPD2_750_GDEY075T7(cfg.cs, cfg.dc, cfg.rst, cfg.busy)); epdRed = false; break;
    default: epd = new GxEPD2_BW<GxEPD2_750_T7, GxEPD2_750_T7::HEIGHT / 2>(GxEPD2_750_T7(cfg.cs, cfg.dc, cfg.rst, cfg.busy)); epdRed = false; break;
  }
  epd->init(115200, true, cfg.pinPreset == 1 ? 2 : 10, false);   // Waveshare driver boards need a short reset pulse
  epd->setRotation(0);
}

void showBoard() {
  epd->setFullWindow();
  epd->firstPage();
  do { drawBoard(*epd, data, epdRed); } while (epd->nextPage());
  epd->hibernate();
}

// Simple full-screen message (setup instructions, errors)
void showMessage(const char* title, const std::vector<std::string>& lines) {
  epd->setFullWindow();
  epd->firstPage();
  do {
    Painter p(*epd, epdRed);
    epd->fillScreen(C_WHITE);
    epd->fillRect(0, 0, 800, 42, C_BLACK);
    p.text(&FreeSansBold12pt7b, 14, 29, cfg.tail + "  hangar board", C_WHITE);
    p.text(&FreeSansBold18pt7b, 30, 110, title, epdRed ? C_RED : C_BLACK);
    int y = 160;
    for (auto& l : lines) { for (auto& w : p.wrap(&FreeSans12pt7b, l, 740)) { p.text(&FreeSans12pt7b, 30, y, w, C_BLACK); y += 34; } y += 8; }
  } while (epd->nextPage());
  epd->hibernate();
}

/* ---------- network ---------- */
bool httpGet(const String& url, std::string& out, int& code) {
  WiFiClientSecure client; client.setInsecure();      // public weather data; certificate not pinned
  HTTPClient http; http.setTimeout(15000); http.setUserAgent("HangarBoard/1.0 (ESP32 e-paper)");
  if (!http.begin(client, url)) { code = -1; return false; }
  code = http.GET();
  bool ok = code == 200;
  if (ok) out = http.getString().c_str();
  http.end();
  return ok;
}

int tzOffsetMin(time_t now) {
  struct tm lt, gt; localtime_r(&now, &lt); gmtime_r(&now, &gt);
  int d = (lt.tm_year - gt.tm_year) * 400 + (lt.tm_yday - gt.tm_yday);
  if (d > 1) d = -1; else if (d < -1) d = 1;
  return d * 1440 + (lt.tm_hour - gt.tm_hour) * 60 + (lt.tm_min - gt.tm_min);
}

void startTime() {
  configTzTime(cfg.tz.c_str(), "pool.ntp.org", "time.nist.gov");
  for (int i = 0; i < 40 && time(nullptr) < 1700000000; i++) delay(250);
  timeOk = time(nullptr) >= 1700000000;
}

/* ---------- the update cycle ---------- */
void doUpdate() {
  wantUpdate = false; lastUpdate = millis();
  if (!timeOk) startTime();
  time_t now = time(nullptr); int off = tzOffsetMin(now);
  data.tail = cfg.tail; data.station = cfg.station;

  std::string body; int code = 0;
  String base = "https://aviationweather.gov/api/data/";
  if (WiFi.status() != WL_CONNECTED) { data.wxError = "No Wi-Fi connection"; }
  else if (httpGet(base + "metar?ids=" + cfg.station.c_str() + "&format=json", body, code)) {
    if (fillWeather(data, cfg, body, (long)now, off)) lastMetarRaw = data.rawMetar;
  } else {
    char b[64];
    if (code == 204) snprintf(b, sizeof b, "No report for %s", cfg.station.c_str());
    else snprintf(b, sizeof b, "Weather server error %d", code);
    data.wxError = b;
  }
  if (WiFi.status() == WL_CONNECTED && httpGet(base + "taf?ids=" + cfg.station.c_str() + "&format=raw", body, code) && body.size() > 10) {
    lastTafRaw = body; data.rawTaf = formatTaf(body); data.taf = scanTaf(body); data.haveTaf = true;
  } else if (code == 204) { data.haveTaf = false; }

  fillItems(data, cfg, (long)((now + off * 60L) / 86400));
  char t[64]; struct tm lt; localtime_r(&now, &lt);
  strftime(t, sizeof t, "Updated %a %b %d, %Y %H%M %Z", &lt); data.updated = timeOk ? t : "Clock not set";
  lastUpdatedText = data.updated.substr(timeOk ? 8 : 0);
  time_t nx = now + cfg.refreshMin * 60; struct tm nt; localtime_r(&nx, &nt); char nb[8]; strftime(nb, sizeof nb, "%H%M", &nt);
  data.footer = std::string("Settings: http://hangarboard.local  (") + WiFi.localIP().toString().c_str() + ")    Next update " + nb;
  showBoard();
}

/* ---------- settings web server ---------- */
void sendJson(const std::string& s, int code = 200) { server.send(code, "application/json", s.c_str()); }
void setupServer() {
  server.on("/", HTTP_GET, []() { server.send_P(200, "text/html", SETTINGS_HTML); });
  server.on("/dbimport.js", HTTP_GET, []() { server.send_P(200, "application/javascript", DBIMPORT_JS); });
  server.on("/mdb.js", HTTP_GET, []() {          // Access-file reader for the import button (gzip)
    server.sendHeader("Content-Encoding", "gzip"); server.sendHeader("Cache-Control", "max-age=86400");
    server.send_P(200, "application/javascript", (const char*)MDB_JS_GZ, MDB_JS_GZ_LEN);
  });
  server.on("/api/config", HTTP_GET, []() { sendJson(configToJson(cfg)); });
  server.on("/api/config", HTTP_POST, []() {
    int oldPanel = cfg.panel, oldPreset = cfg.pinPreset, op[6] = {cfg.cs, cfg.dc, cfg.rst, cfg.busy, cfg.sck, cfg.mosi};
    std::string oldTz = cfg.tz;
    if (!configFromJson(cfg, std::string(server.arg("plain").c_str()), IS_S3)) { sendJson("{\"ok\":false}", 400); return; }
    saveConfig();
    int np[6] = {cfg.cs, cfg.dc, cfg.rst, cfg.busy, cfg.sck, cfg.mosi};
    bool restart = oldPanel != cfg.panel || oldPreset != cfg.pinPreset || memcmp(op, np, sizeof op) != 0;
    if (oldTz != cfg.tz) { setenv("TZ", cfg.tz.c_str(), 1); tzset(); }
    sendJson(restart ? "{\"ok\":true,\"restart\":true}" : "{\"ok\":true,\"restart\":false}");
    if (restart) wantRestart = true; else wantUpdate = true;
  });
  server.on("/api/refresh", HTTP_POST, []() { wantUpdate = true; sendJson("{\"ok\":true}"); });
  server.on("/api/status", HTTP_GET, []() {
    JsonDocument d; d["updated"] = lastUpdatedText; d["wxError"] = data.wxError; d["metar"] = lastMetarRaw; d["taf"] = lastTafRaw;
    d["ip"] = WiFi.localIP().toString().c_str(); d["version"] = FW_VERSION;
    std::string s; serializeJson(d, s); sendJson(s);
  });
  server.on("/api/wifi-reset", HTTP_POST, []() { sendJson("{\"ok\":true}"); delay(300); wm.resetSettings(); ESP.restart(); });
  server.onNotFound([]() { server.sendHeader("Location", "/"); server.send(302, "text/plain", ""); });
  server.begin();
}

/* ---------- setup and loop ---------- */
void setup() {
  Serial.begin(115200);
  loadConfig();
  makeDisplay();

  WiFi.mode(WIFI_STA);
  wm.setConfigPortalTimeout(900);
  wm.setTitle("Hangar Board");
  wm.setAPCallback([](WiFiManager*) {
    showMessage("Wi-Fi setup", {
      "1. On your phone, open Wi-Fi settings and join the network \"HangarBoard-Setup\".",
      "2. A setup page opens. If it doesn't, open a browser and go to 192.168.4.1",
      "3. Tap \"Configure WiFi\", choose your hangar network, and enter its password.",
      "The board then connects and shows the weather. Settings: http://hangarboard.local"});
  });
  if (!wm.autoConnect(AP_NAME)) {
    showMessage("Wi-Fi not set up", {"Setup timed out. Unplug the board and plug it back in to try again."});
    delay(2000); ESP.deepSleep(0);
  }
  WiFi.setAutoReconnect(true);
  MDNS.begin("hangarboard");
  MDNS.addService("http", "tcp", 80);
  setupServer();
  startTime();
  wantUpdate = true;
}

void loop() {
  server.handleClient();
  if (wantRestart) { delay(500); ESP.restart(); }
  static unsigned long lastWifiCheck = 0;
  if (millis() - lastWifiCheck > 30000) { lastWifiCheck = millis(); if (WiFi.status() != WL_CONNECTED) WiFi.reconnect(); }
  if (wantUpdate || millis() - lastUpdate > (unsigned long)cfg.refreshMin * 60000UL) doUpdate();
  delay(5);
}
