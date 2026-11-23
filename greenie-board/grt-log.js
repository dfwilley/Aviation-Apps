// Reads GRT HXr "DEMO-....LOG" flight recordings.
//
// A recording is a list of records. Each record is:
//   1 byte   stream number (which serial port or data source it came from)
//   4 bytes  tick, in milliseconds since the EFIS was switched on (big-endian)
//   4 bytes  length of the data that follows (big-endian)
//   n bytes  the data, exactly as it arrived
//
// Two kinds of data are used here:
//   GPS text sentences ($GPRMC ...) for position, ground speed, track and time.
//   AHRS "high rate" packets (7F FF FE, 28 bytes) for pitch, roll, heading,
//   pressure altitude, airspeed and G.
//
// The AHRS layout was checked against GRTDecode 2.22 output for the same file.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.GrtLog = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var FPS_PER_KT = 1.68781;

  function u32(b, i) {
    return ((b[i] << 24) >>> 0) + (b[i + 1] << 16) + (b[i + 2] << 8) + b[i + 3];
  }
  function i16(b, i) {
    var v = (b[i] << 8) | b[i + 1];
    return v & 0x8000 ? v - 0x10000 : v;
  }
  function u16(b, i) {
    return (b[i] << 8) | b[i + 1];
  }

  function nmeaLatLon(v, hemi, degDigits) {
    if (!v || v.length < degDigits + 2) return null;
    var deg = parseInt(v.slice(0, degDigits), 10);
    var min = parseFloat(v.slice(degDigits));
    if (!isFinite(deg) || !isFinite(min)) return null;
    var out = deg + min / 60;
    return hemi === 'S' || hemi === 'W' ? -out : out;
  }

  // "$GPRMC,164352.50,A,3207.99519,N,11056.72266,W,1.705,93.34,170924,..."
  function parseRmc(line) {
    var f = line.split(',');
    if (f.length < 10 || f[2] !== 'A') return null;
    var lat = nmeaLatLon(f[3], f[4], 2);
    var lon = nmeaLatLon(f[5], f[6], 3);
    var tm = f[1], dt = f[9];
    if (lat === null || lon === null || tm.length < 6 || dt.length !== 6) return null;
    var utc = Date.UTC(2000 + parseInt(dt.slice(4, 6), 10), parseInt(dt.slice(2, 4), 10) - 1,
      parseInt(dt.slice(0, 2), 10), parseInt(tm.slice(0, 2), 10), parseInt(tm.slice(2, 4), 10), 0) / 1000 +
      parseFloat(tm.slice(4));
    if (!isFinite(utc)) return null;
    return { t: utc, lat: lat, lon: lon, gs: parseFloat(f[7]) || 0, trk: parseFloat(f[8]) || 0 };
  }

  // Returns { fixes: [...], air: [...] } with times in seconds since 1970 (UTC).
  //   fixes: { t, lat, lon, gs (kt), trk (deg true) }
  //   air:   { t, palt (ft), ias (kt), g, pitch, roll, hdg (deg) }
  function parseLog(input) {
    var b = input instanceof Uint8Array ? input : new Uint8Array(input);
    var n = b.length, i = 0, lastTick = -1;
    var gpsText = {};          // stream number -> text waiting for the end of its line
    var fixes = [];            // with .tick until times are worked out
    var airByStream = {};      // stream number -> packets
    while (i + 9 <= n) {
      var stream = b[i], tick = u32(b, i + 1), len = u32(b, i + 5);
      // A damaged spot: step forward one byte at a time until records line up again.
      if (len > 70000 || i + 9 + len > n || (lastTick >= 0 && Math.abs(tick - lastTick) > 3600000)) {
        i++;
        continue;
      }
      lastTick = tick;
      var p = i + 9;
      if (len === 28 && b[p] === 0x7f && b[p + 1] === 0xff && b[p + 2] === 0xfe) {
        var palt = u16(b, p + 10) - 5000;
        var ias = i16(b, p + 14) / 10 / FPS_PER_KT;
        if (palt > -2000 && palt < 40000 && ias > -40 && ias < 400) {
          (airByStream[stream] = airByStream[stream] || []).push({
            tick: tick,
            roll: i16(b, p + 4) * 360 / 65536,
            pitch: i16(b, p + 6) * 360 / 65536,
            hdg: u16(b, p + 8) * 360 / 65536,
            palt: palt,
            ias: ias,
            g: i16(b, p + 20) / 980.665
          });
        }
      } else if (len > 0 && (b[p] === 0x24 || gpsText[stream] !== undefined)) {
        // Text. Keep it only for streams that have shown a "$GP" / "$GN" sentence.
        var s = '';
        for (var k = 0; k < len; k++) s += String.fromCharCode(b[p + k]);
        var cur = gpsText[stream];
        if (cur === undefined) {
          if (/^\$G[PN]/.test(s)) cur = gpsText[stream] = { text: '', tick: tick };
        }
        if (cur) {
          if (cur.text === '') cur.tick = tick;
          cur.text += s;
          var nl;
          while ((nl = cur.text.search(/[\r\n]/)) >= 0) {
            var line = cur.text.slice(0, nl).trim();
            cur.text = cur.text.slice(nl + 1);
            if (/^\$G[PN]RMC,/.test(line)) {
              var fix = parseRmc(line);
              if (fix) { fix.tick = cur.tick; fixes.push(fix); }
            }
            cur.tick = tick;
          }
          if (cur.text.length > 400) cur.text = '';
        }
      }
      i = p + len;
    }

    // Use the lowest-numbered AHRS stream (the airplane has two AHRS units).
    var streams = Object.keys(airByStream).map(Number).sort(function (a, c) { return a - c; });
    var air = streams.length ? airByStream[streams[0]] : [];

    // Give every AHRS packet a UTC time using the nearest GPS fix before it.
    var fi = 0;
    var out = [];
    if (fixes.length) {
      for (var a = 0; a < air.length; a++) {
        while (fi + 1 < fixes.length && fixes[fi + 1].tick <= air[a].tick) fi++;
        var ref = fixes[fi];
        air[a].t = ref.t + (air[a].tick - ref.tick) / 1000;
        out.push(air[a]);
      }
    }
    return { fixes: fixes, air: out };
  }

  // Joins fixes and AHRS packets from one or more files into one list of samples,
  // one per GPS fix, in time order: { t, lat, lon, gs, trk, palt, ias, g, pitch, roll }.
  // g is the largest G seen since the previous fix, so a touchdown bump is not lost.
  function mergeSamples(parsedList) {
    var fixes = [], air = [];
    parsedList.forEach(function (p) {
      fixes = fixes.concat(p.fixes);
      air = air.concat(p.air);
    });
    var byT = function (a, c) { return a.t - c.t; };
    fixes.sort(byT);
    air.sort(byT);
    var samples = [], ai = 0, lastT = -1;
    for (var i = 0; i < fixes.length; i++) {
      var f = fixes[i];
      if (f.t <= lastT) continue;   // the same moment loaded twice
      var gmax = null, last = null;
      while (ai < air.length && air[ai].t <= f.t) {
        last = air[ai];
        if (f.t - last.t < 1 && (gmax === null || last.g > gmax)) gmax = last.g;
        ai++;
      }
      if (!last && ai > 0) last = air[ai - 1];
      if (!last || f.t - last.t > 1) { lastT = f.t; continue; }   // no air data for this fix
      samples.push({
        t: f.t, lat: f.lat, lon: f.lon, gs: f.gs, trk: f.trk,
        palt: last.palt, ias: last.ias, g: gmax === null ? last.g : gmax,
        pitch: last.pitch, roll: last.roll
      });
      lastT = f.t;
    }
    return samples;
  }

  return { parseLog: parseLog, mergeSamples: mergeSamples, parseRmc: parseRmc };
});
