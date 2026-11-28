// Checks the MyFlightbook pieces: the sign-in maths and picking the Hobbs time out of a flight list.
// Runs on an ordinary computer:
//   g++ -std=c++17 -I <ArduinoJson>/src -I ../HangarBoard test_mfb.cpp -o test_mfb && ./test_mfb
// The flights below are made up.
#include "board_logic.h"
#include <cstdio>
using namespace hb;

static int failed = 0;
static void check(const char* what, bool ok) { printf("%s %s\n", ok ? "ok  " : "FAIL", what); if (!ok) failed++; }
static std::string hex(const std::string& s) {
  uint8_t h[32]; sha256((const uint8_t*)s.data(), s.size(), h); char b[65]; for (int i = 0; i < 32; i++) snprintf(b + i * 2, 3, "%02x", h[i]); return b;
}
static bool near(double a, double b) { return a > b - 0.001 && a < b + 0.001; }

int main() {
  // SHA-256, published test values (FIPS 180-4) and the PKCE example from RFC 7636 appendix B
  check("SHA-256 of nothing", hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  check("SHA-256 of abc", hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  check("SHA-256 of a two-block message", hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  check("sign-in challenge matches RFC 7636", pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
  check("web address encoding", urlEncode("https://a.b/c d?x=1&y") == "https%3A%2F%2Fa.b%2Fc%20d%3Fx%3D1%26y");
  check("tail numbers compare without case or dashes", normTail("n-721ne ") == "N721NE");

  // Newest flight first, as MyFlightbook sends them. Fields MyFlightbook leaves out when zero are left out here too.
  const char* flights = "["
    "{\"FlightID\":9,\"Date\":\"2026-11-20T00:00:00\",\"TailNumDisplay\":\"N12345\",\"HobbsStart\":900.0,\"HobbsEnd\":901.5,\"Comment\":\"rental\",\"CustomProperties\":[{\"PropTypeID\":1,\"DecValue\":3.5}]},"
    "{\"FlightID\":8,\"Date\":\"2026-11-18T00:00:00\",\"TailNumDisplay\":\"N721NE\",\"Route\":\"KTUS KRYN\"},"
    "{\"FlightID\":7,\"Date\":\"2026-11-15T00:00:00\",\"TailNumDisplay\":\"N721NE\",\"HobbsStart\":210.2,\"HobbsEnd\":211.6,\"FlightImages\":[{\"URLFullImage\":\"x\"}]},"
    "{\"FlightID\":6,\"Date\":\"2026-11-02T00:00:00\",\"TailNumDisplay\":\"N721NE\",\"HobbsStart\":208.9,\"HobbsEnd\":210.2}]";
  { HobbsPick p; bool ok = pickHobbs(flights, "N721NE", p);
    check("flight list is read", ok && p.flights == 4 && p.matched == 3);
    check("highest ending Hobbs for this aircraft, ignoring another aircraft's higher number", near(p.hobbs, 211.6));
    check("date comes from that flight", p.date == "2026-11-15"); }
  { HobbsPick p; pickHobbs(flights, "n721ne", p); check("tail number typed in lower case still matches", near(p.hobbs, 211.6)); }
  { HobbsPick p; bool ok = pickHobbs(flights, "N999ZZ", p); check("no flights for this aircraft gives no Hobbs", ok && p.matched == 0 && p.hobbs == 0); }
  { HobbsPick p; check("an empty list is fine", pickHobbs("[]", "N721NE", p) && p.flights == 0); }
  { HobbsPick p; check("an error page is not a flight list", !pickHobbs("Error: something", "N721NE", p) && !pickHobbs("{\"error\":\"x\"}", "N721NE", p)); }

  { Config c; c.tach = 210.2; c.tachDate = "2026-11-02"; HobbsPick p; pickHobbs(flights, "N721NE", p);
    check("a higher Hobbs from MyFlightbook is taken", applyHobbs(c, p, "2026-11-27") && near(c.tach, 211.6) && c.tachDate == "2026-11-15"); }
  { Config c; c.tach = 213.0; c.tachDate = "2026-11-26"; HobbsPick p; pickHobbs(flights, "N721NE", p);
    check("a higher hand-typed Hobbs is never pulled down", !applyHobbs(c, p, "2026-11-27") && near(c.tach, 213.0) && c.tachDate == "2026-11-26"); }
  { Config c; c.tach = 211.6; c.tachDate = "2026-11-16"; HobbsPick p; pickHobbs(flights, "N721NE", p);
    check("the same Hobbs changes nothing", !applyHobbs(c, p, "2026-11-27") && c.tachDate == "2026-11-16"); }
  { Config c; HobbsPick p; p.hobbs = 50.0; check("a flight without a readable date is dated today", applyHobbs(c, p, "2026-11-27") && c.tachDate == "2026-11-27"); }

  printf(failed ? "\n%d check(s) FAILED\n" : "\nAll MyFlightbook checks passed\n", failed);
  return failed ? 1 : 0;
}
