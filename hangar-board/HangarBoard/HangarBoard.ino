/*
  Hangar Board — 7.5" e-paper status board for the hangar.
  Runs on an ESP32, an ESP32-S3 or a Raspberry Pi Pico W (the Pico with Wi-Fi).
  Shows current METAR (decoded), density altitude, sunrise/sunset and TAF for one
  airport, plus aircraft maintenance and pilot currency due items. Due items can be
  loaded from the Access maintenance database on the settings page (read-only).

  Weather: aviationweather.gov (NWS Aviation Weather Center data API).
  First power-up: join the Wi-Fi network "HangarBoard-Setup" on your phone and
  enter your hangar Wi-Fi. Settings page afterward: http://hangarboard.local
*/
#define ENABLE_GxEPD2_GFX 1   // lets one program drive any of the three displays
#if defined(ARDUINO_ARCH_RP2040)
#define HB_PICO 1               // Raspberry Pi Pico W, Arduino-Pico core (earlephilhower)
#else
#define HB_PICO 0               // ESP32 or ESP32-S3
#endif
#include <WiFi.h>
#include <WebServer.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <SPI.h>
#if HB_PICO
#include <LEAmDNS.h>
#include <DNSServer.h>
#include <LittleFS.h>
#else
#include <WiFiManager.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#endif
#include <GxEPD2_BW.h>
#include <GxEPD2_3C.h>
#include <time.h>
#include "board_logic.h"
#include "board_draw.h"
#include "web_assets.h"

using namespace hb;

#if HB_PICO
static const int BOARD = BOARD_PICO_W;
static const char* BOARD_NAME = "pico";
#elif CONFIG_IDF_TARGET_ESP32S3
static const int BOARD = BOARD_ESP32S3;
static const char* BOARD_NAME = "esp32s3";
#else
static const int BOARD = BOARD_ESP32;
static const char* BOARD_NAME = "esp32";
#endif
static const char* FW_VERSION = "1.2";
static const char* AP_NAME = "HangarBoard-Setup";

Config cfg;
BoardData data;
WebServer server(80);
#if HB_PICO
String wifiSsid, wifiPass;      // saved in the Pico's own flash storage
#else
Preferences prefs;
WiFiManager wm;
#endif
GxEPD2_GFX* epd = nullptr;
bool epdRed = false;
unsigned long lastUpdate = 0;
bool wantUpdate = true, wantRestart = false, timeOk = false;
std::string lastMetarRaw, lastTafRaw, lastUpdatedText;

/* ---------- settings storage ---------- */
#if HB_PICO
String readFile(const char* path) {
  File f = LittleFS.open(path, "r"); if (!f) return "";
  String s = f.readString(); f.close(); return s;
}
void writeFile(const char* path, const String& s) {
  File f = LittleFS.open(path, "w"); if (!f) return;
  f.print(s); f.close();
}
void loadConfig() {
  LittleFS.begin();
  applyPreset(cfg, BOARD);
  String s = readFile("/cfg.json");
  if (s.length()) configFromJson(cfg, std::string(s.c_str()), BOARD);
}
void saveConfig() { writeFile("/cfg.json", configToJson(cfg).c_str()); }
void restartBoard() { rp2040.reboot(); }
#else
void loadConfig() {
  applyPreset(cfg, BOARD);
  prefs.begin("hb", true); String s = prefs.getString("cfg", ""); prefs.end();
  if (s.length()) configFromJson(cfg, std::string(s.c_str()), BOARD);
}
void saveConfig() { prefs.begin("hb", false); prefs.putString("cfg", configToJson(cfg).c_str()); prefs.end(); }
void restartBoard() { ESP.restart(); }
#endif

/* ---------- display ---------- */
typedef GxEPD2_3C<GxEPD2_750c_GDEY075Z08, GxEPD2_750c_GDEY075Z08::HEIGHT / 4> PanelRedGoodDisplay;
typedef GxEPD2_3C<GxEPD2_750c_Z08, GxEPD2_750c_Z08::HEIGHT / 4> PanelRedWaveshare;
typedef GxEPD2_BW<GxEPD2_750_GDEY075T7, GxEPD2_750_GDEY075T7::HEIGHT / 2> PanelBwGoodDisplay;
typedef GxEPD2_BW<GxEPD2_750_T7, GxEPD2_750_T7::HEIGHT / 2> PanelBwWaveshare;

#if HB_PICO
// The Pico has two SPI buses; which one depends on the clock pin. Point the display at the right one.
#define HB_USE_BUS(d) (d)->epd2.selectSPI(picoBus(), SPISettings(4000000, MSBFIRST, SPI_MODE0))
SPIClassRP2040& picoBus() { return picoSpiBus(cfg.sck, cfg.mosi) == 1 ? SPI1 : SPI; }
#else
#define HB_USE_BUS(d)
#endif

void makeDisplay() {
#if HB_PICO
  picoBus().setSCK(cfg.sck); picoBus().setTX(cfg.mosi);
  picoBus().setRX(picoSpareRx(cfg));               // unused input, parked on a free pin so it can't take over the reset pin
  bool shortReset = cfg.pinPreset == 0;            // Waveshare's Pico e-Paper modules
#else
  SPI.end();
  SPI.begin(cfg.sck, -1, cfg.mosi, cfg.cs);
  bool shortReset = cfg.pinPreset == 1;            // Waveshare ESP32 driver board
#endif
  switch (cfg.panel) {
    case 0: { auto* d = new PanelRedGoodDisplay(GxEPD2_750c_GDEY075Z08(cfg.cs, cfg.dc, cfg.rst, cfg.busy)); HB_USE_BUS(d); epd = d; epdRed = true; break; }
    case 1: { auto* d = new PanelBwGoodDisplay(GxEPD2_750_GDEY075T7(cfg.cs, cfg.dc, cfg.rst, cfg.busy)); HB_USE_BUS(d); epd = d; epdRed = false; break; }
    case 3: { auto* d = new PanelRedWaveshare(GxEPD2_750c_Z08(cfg.cs, cfg.dc, cfg.rst, cfg.busy)); HB_USE_BUS(d); epd = d; epdRed = true; break; }
    default: { auto* d = new PanelBwWaveshare(GxEPD2_750_T7(cfg.cs, cfg.dc, cfg.rst, cfg.busy)); HB_USE_BUS(d); epd = d; epdRed = false; break; }
  }
  epd->init(115200, true, shortReset ? 2 : 10, false);   // Waveshare boards need a short reset pulse
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
#if HB_PICO
  setenv("TZ", cfg.tz.c_str(), 1); tzset();
  NTP.begin("pool.ntp.org", "time.nist.gov");
#else
  configTzTime(cfg.tz.c_str(), "pool.ntp.org", "time.nist.gov");
#endif
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
  server.on("/api/config", HTTP_GET, []() {         // settings, plus which board this is so the page can label the wiring choices
    std::string s = configToJson(cfg);
    s.insert(1, std::string("\"board\":\"") + BOARD_NAME + "\",");
    sendJson(s);
  });
  server.on("/api/config", HTTP_POST, []() {
    int oldPanel = cfg.panel, oldPreset = cfg.pinPreset, op[6] = {cfg.cs, cfg.dc, cfg.rst, cfg.busy, cfg.sck, cfg.mosi};
    std::string oldTz = cfg.tz;
    if (!configFromJson(cfg, std::string(server.arg("plain").c_str()), BOARD)) { sendJson("{\"ok\":false}", 400); return; }
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
    d["ip"] = WiFi.localIP().toString().c_str(); d["version"] = FW_VERSION; d["board"] = BOARD_NAME;
    std::string s; serializeJson(d, s); sendJson(s);
  });
  server.on("/api/wifi-reset", HTTP_POST, []() {
    sendJson("{\"ok\":true}"); delay(300);
#if HB_PICO
    LittleFS.remove("/wifi.json");
#else
    wm.resetSettings();
#endif
    restartBoard();
  });
  server.onNotFound([]() { server.sendHeader("Location", "/"); server.send(302, "text/plain", ""); });
  server.begin();
}

/* ---------- Wi-Fi ---------- */
#if HB_PICO
String htmlEsc(const String& in) {
  String o; for (size_t i = 0; i < in.length(); i++) { char c = in[i]; if (c == '&') o += "&amp;"; else if (c == '<') o += "&lt;"; else if (c == '>') o += "&gt;"; else if (c == '"') o += "&quot;"; else o += c; }
  return o;
}
void loadWifi() {
  JsonDocument d; if (deserializeJson(d, readFile("/wifi.json"))) return;
  wifiSsid = d["ssid"] | ""; wifiPass = d["pass"] | "";
}
bool joinWifi() {
  if (!wifiSsid.length()) return false;
  WiFi.mode(WIFI_STA); WiFi.setHostname("hangarboard");
  WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());            // waits until joined or timed out
  for (int i = 0; i < 80 && WiFi.status() != WL_CONNECTED; i++) delay(250);
  return WiFi.status() == WL_CONNECTED;
}
// The Pico makes its own "HangarBoard-Setup" network with a page for choosing the hangar Wi-Fi.
// Runs until a network is saved (then restarts). With a timeout, returns when it runs out.
void wifiSetupPortal(unsigned long timeoutMs) {
  WiFi.mode(WIFI_STA); WiFi.disconnect();
  String options; int n = WiFi.scanNetworks();
  for (int i = 0; i < n; i++) { String id = WiFi.SSID(i); if (id.length() && options.indexOf("\"" + htmlEsc(id) + "\"") < 0) options += "<option value=\"" + htmlEsc(id) + "\">" + htmlEsc(id) + "</option>"; }
  WiFi.mode(WIFI_AP); WiFi.softAP(AP_NAME);
  delay(500);
  IPAddress ip = WiFi.softAPIP(); String ipText = ip.toString();
  DNSServer dns; dns.start(53, "*", ip);                       // sends every address to the setup page, so phones open it by themselves
  WebServer portal(80); bool saved = false;
  String page = String("<!DOCTYPE html><html><head><meta name=viewport content='width=device-width,initial-scale=1'><title>Hangar Board Wi-Fi</title>"
    "<style>body{font:18px sans-serif;margin:20px;max-width:480px}input,select,button{font:inherit;width:100%;padding:10px;margin:6px 0 14px;box-sizing:border-box}"
    "button{background:#c62d26;color:#fff;border:0;border-radius:10px;font-weight:700}</style></head><body><h2>Hangar Board Wi-Fi</h2>"
    "<form method=post action=/save><label>Network</label><select name=pick><option value=''>(type the name below)</option>") + options +
    "</select><label>Or type the network name</label><input name=ssid autocapitalize=none autocorrect=off>"
    "<label>Password</label><input name=pass type=password><button>Save and connect</button></form>"
    "<p>The password stays on the board and is never sent anywhere else.</p></body></html>";
  portal.on("/", HTTP_GET, [&]() { portal.send(200, "text/html", page); });
  portal.on("/save", HTTP_POST, [&]() {
    String id = portal.arg("ssid"); id.trim(); if (!id.length()) id = portal.arg("pick");
    if (!id.length()) { portal.sendHeader("Location", "/"); portal.send(302, "text/plain", ""); return; }
    JsonDocument d; d["ssid"] = id; d["pass"] = portal.arg("pass"); String out; serializeJson(d, out);
    writeFile("/wifi.json", out);
    portal.send(200, "text/html", "<!DOCTYPE html><html><body style='font:18px sans-serif;margin:20px'><h2>Saved</h2><p>The board is restarting and will join <b>" + htmlEsc(id) + "</b>. If the screen comes back to the Wi-Fi setup steps, the password was wrong: join HangarBoard-Setup and try again.</p></body></html>");
    saved = true;
  });
  portal.onNotFound([&]() { portal.sendHeader("Location", "http://" + ipText + "/"); portal.send(302, "text/plain", ""); });
  portal.begin();
  showMessage("Wi-Fi setup", {
    "1. On your phone, open Wi-Fi settings and join the network \"HangarBoard-Setup\".",
    std::string("2. A setup page opens. If it doesn't, open a browser and go to ") + ipText.c_str(),
    "3. Choose your hangar network and enter its password.",
    "The board then connects and shows the weather. Settings: http://hangarboard.local"});
  unsigned long start = millis();
  while (!saved && (!timeoutMs || millis() - start < timeoutMs)) { dns.processNextRequest(); portal.handleClient(); delay(2); }
  if (saved) { unsigned long t = millis(); while (millis() - t < 1500) { portal.handleClient(); delay(2); } restartBoard(); }
  portal.stop(); dns.stop(); WiFi.softAPdisconnect(true);
}
void connectWifi() {
  loadWifi();
  if (!wifiSsid.length()) wifiSetupPortal(0);                  // first power-up: wait here until a network is chosen
  while (!joinWifi()) wifiSetupPortal(180000);                 // saved network not answering: offer setup for 3 minutes, then try it again
}
void keepWifi() { if (WiFi.status() != WL_CONNECTED) WiFi.begin(wifiSsid.c_str(), wifiPass.c_str()); }
#else
void connectWifi() {
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
}
void keepWifi() { if (WiFi.status() != WL_CONNECTED) WiFi.reconnect(); }
#endif

/* ---------- setup and loop ---------- */
void setup() {
  Serial.begin(115200);
  loadConfig();
  makeDisplay();
  connectWifi();
  MDNS.begin("hangarboard");
  MDNS.addService("http", "tcp", 80);
  setupServer();
  startTime();
  wantUpdate = true;
}

void loop() {
  server.handleClient();
#if HB_PICO
  MDNS.update();
#endif
  if (wantRestart) { delay(500); restartBoard(); }
  static unsigned long lastWifiCheck = 0;
  if (millis() - lastWifiCheck > 30000) { lastWifiCheck = millis(); keepWifi(); }
  if (wantUpdate || millis() - lastUpdate > (unsigned long)cfg.refreshMin * 60000UL) doUpdate();
  delay(5);
}
