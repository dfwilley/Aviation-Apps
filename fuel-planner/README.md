# Fuel Planner

Self-contained 100LL fuel-run planner for N721NE, an RV-14. The starting airport and the destination both default to KTUS and can be changed; the phone remembers each one.

When they are the same, it compares buying avgas there with a round trip to another field. When they differ, it compares fueling at the start and flying direct with a stop along the way, and with buying fuel on arrival at the destination. Distances are great-circle tracks. The Tucson-area airports are built into the page; any other US identifier is looked up in `airports.json` (OurAirports, public domain). If that directory has no match, enter a latitude, longitude, and field elevation. Cruise defaults remain still air, 200 KTAS, 10.5 gal/hr, 50 gallons usable, and a day (30 min) or night (45 min) VFR reserve. Prices are a snapshot checked 24 Oct 2026 and do not update themselves.

Open [index.html](index.html) in a browser, or use the GitHub Pages site: https://dfwilley.github.io/Fuel-Planner/

[wb.html](wb.html) is the N721NE weight and balance sheet (50.7 gal usable; aerobatic flight requires empty baggage).

On iPhone, open that site in Safari and use Share → Add to Home Screen. The pilot in command checks weather, NOTAMs, and TFRs and makes the go/no-go call.
