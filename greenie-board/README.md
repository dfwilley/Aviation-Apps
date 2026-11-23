# KTUS Greenie Board

Real landings in N721NE, graded the way a Landing Signal Officer (LSO) grades a carrier pass, and posted as colored squares on a "greenie board".

Open it at https://dfwilley.github.io/Aviation-Apps/greenie-board/

## How to use it

1. After a flight, copy the `DEMO-....LOG` files from the HXr's USB stick to the computer (or to Dropbox for the phone).
2. Open the page, press **Choose HXr log files**, and pick all the files from the flight. The landing is usually in the last one or two.
3. Each touchdown on a known runway is added to the board as a box. The page opens on the board alone: your last 30 landings in a grid 6 across and 5 down, oldest at the top left, with one small Import button under it. Once there are more than 30, Older and Newer buttons page back through the rest, 30 at a time. Settings and How grading works are links at the bottom of the page. Tap a box to open that landing's page: the grade, the LSO comment, the same thing in plain words, the numbers, and a picture of the approach.

The files are read in the browser. Nothing is uploaded. The board is kept in that browser only; **Settings** has buttons to save and load a backup file, which is also how to move the board to another device.

## iPhone app

`ios/` turns this same page into an iPhone app called **Greenie Board**, for installing with Sideloadly. The app carries its own copy of the page's files (copied in when it is built), so it works with no internet and grades exactly the way the web page does. There is only one copy to edit: change the web page and the app follows on the next build.

- **Download:** https://github.com/dfwilley/Aviation-Apps/releases/download/greenie-board-latest/GreenieBoard.ipa (always the newest build). Open it in Sideloadly on the PC and sign in with the paid Apple Developer Apple ID; the install lasts about a year.
- **Building:** `.github/workflows/greenie-board-ipa.yml` runs `node test.js`, builds the app on a GitHub Mac, takes a simulator screenshot, and on `main` replaces the files in the `greenie-board-latest` release.
- **Import:** the Import button opens the iPhone file picker; choose the `DEMO-....LOG` files from Files or Dropbox.
- **Backup:** Save backup opens the iPhone share sheet, so the file can go to Files or Dropbox. Load backup reads it back.
- The app keeps its own board, separate from the web page in Safari. Save a backup in one and load it in the other to move landings across.

## What it reads

The HXr recording is a raw copy of what arrived on its serial ports. Each record is a stream number (1 byte), a time in milliseconds since power-on (4 bytes), a length (4 bytes) and the data. The app uses two kinds of data:

| Data | Rate | Used for |
|---|---|---|
| GPS `$GPRMC` text sentences | 4 per second | Position, ground speed, track, date and time |
| AHRS high-rate packets (`7F FF FE`, 28 bytes) | about 15 per second | Pressure altitude, indicated airspeed, pitch, bank, G |

The AHRS packet layout was checked against the output of GRTDecode 2.22 for the same recording; one real packet is in `test.js`.

## How a landing is found

A touchdown is the moment the descent stops (after at least 25 ft of descent in the previous 10 seconds) while the airplane is over a runway, lined up within 25 degrees, between 35 and 95 knots, and it does not climb in the next 2 seconds. Height is pressure altitude compared with the altitude at touchdown, so the altimeter setting does not matter.

If a recording stops while the airplane is still coming down over a runway, the app reports that approach as cut off and does not grade it. (One of the three 2024 test landings was like this: the file ends about 8 ft above the runway.)

## How it is graded

The targets are in **Settings**. They are debrief settings chosen by Claude as starting points, not numbers from the airplane's documents: 70 knots indicated, a 3.0 degree glidepath, and a touchdown point 300 ft past the threshold.

| Code | Where | Distance before the threshold |
|---|---|---|
| X | At the start | 4,500 to 3,000 ft |
| IM | In the middle | 3,000 to 1,500 ft |
| IC | In close | 1,500 to 300 ft |
| AR | At the ramp | Crossing the threshold |

| Check | Codes | A little / clearly / way off |
|---|---|---|
| Glidepath angle to the target point | H, LO | 0.5 / 1.0 / 2.0 degrees |
| Lineup, feet from centerline | LUL, LUR | X 60/120/240, IM 40/80/160, IC 25/50/100, AR 20/35/60 |
| Speed (in close and at the ramp only) | F, SLO | fast 5/10/15 kt, slow 4/7/10 kt |
| Height crossing the threshold | H, LO | high by 15/30/60 ft; low is under 10 ft, clearly low under 5 ft |
| Touchdown left or right | LL, LR | 15 / 30 / 50 ft |
| Wing down at touchdown | LLWD, LRWD | 4 / 8 degrees |
| Touchdown G | HARD | 1.3 / 1.6 / 2.0 |
| Time lined up | NESA, LIG | under 12 seconds, over 35 seconds |

Lineup limits from in close onward are scaled for runway width (150 ft is full scale, never less than half).

Touchdown point, measured from the target: more than 150 ft short is (SHORT), 200 to 500 ft long is (LONG), 500 to 1,000 ft long is LONG, and more than 1,000 ft long is a bolter. Before the threshold is SHORT underlined.

Each comment scores 1, 3 or 8 points (a little, clearly, way off), multiplied by 0.5 at the start, 1 in the middle, 1.5 in close and 2 at the ramp and touchdown.

| Grade | Points | When |
|---|---|---|
| Underlined OK | 5.0 | No comments at all, touching down on the target (150 ft short to 200 ft long) |
| OK | 4.0 | Small comments only |
| (OK) Fair | 3.0 | A clear deviation from the middle on in, or a score of 6 or more |
| B Bolter | 2.5 | Touchdown more than 1,000 ft past the target |
| No grade | 2.0 | Way off in close, at the ramp or at touchdown; touchdown before the threshold; or a score of 14 or more |
| C Cut pass | 0.0 | Touchdown of 2.0 G or more |

## The board

Each landing is a box in the grade color with the grade symbol on it, in date order. A day landing is a full box. A night landing is a box cut corner to corner: grade color above, black below. Night is the FAA meaning (the sun more than 6 degrees below the horizon at the airport), worked out from the GPS time and the airport's position.

Real greenie boards were not standard. Accounts from squadron pilots online describe each ready room marking night its own way: a black circle (VF-33), a box cut diagonally and filled black, a black corner, or a D/N in the date column. The colors (green OK, yellow fair, brown no grade, red cut pass) are the ones those accounts agree on.

## Limits

- Runway positions come from the OurAirports public-domain data and are good to about 20 ft. Both 2024 test landings show 10 to 13 ft right of centerline all the way down the rollout, which may be the data and not the pilot.
- The HXr smooths its G reading (the test landings peak at 1.07 G), so a firm landing may not show as HARD.
- Only runways in `runways.json` are graded: about 6,900 open US runways of 1,500 ft or more that have published coordinates for both ends.
- A low go-around that levels off within a few feet of the runway for 2 seconds would be counted as a touchdown.

## Files

| File | What it is |
|---|---|
| `index.html` | The page |
| `grt-log.js` | Reads the HXr recording |
| `grade.js` | Finds landings and grades them |
| `runways.json` | Runway list, built by `tools/make_runways.py` from https://ourairports.com/data/ (downloaded November 23, 2026) |
| `test.js` | Tests: `node test.js`. Checks the reader and the grades, and pages the board with 33 and 61 made-up landings |
| `test-dom.js` | A tiny stand-in browser so `test.js` can run the board page under Node with nothing to install |

The owner's real recordings are personal flight data and are not in this repository.
