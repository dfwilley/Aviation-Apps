// Finds landings in HXr flight data and grades them the way a Landing Signal
// Officer (LSO) grades a carrier pass. No flight-planning numbers here: the
// targets and tolerances are debrief settings, listed in DEFAULTS and the README.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.Greenie = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var FT_PER_DEG_LAT = 364567;   // feet in one degree of latitude
  var RAD = Math.PI / 180;

  // What the pilot can change on the Settings screen.
  var DEFAULTS = {
    approachKias: 70,    // target speed on final, knots indicated
    glidepathDeg: 3.0,   // target glidepath angle
    aimFt: 300           // target touchdown point, feet past the threshold
  };

  // Distances are feet before the runway threshold.
  var PHASES = [
    { key: 'X', name: 'at the start', from: 4500, to: 3000, weight: 0.5, lineup: [60, 120, 240], speed: false },
    { key: 'IM', name: 'in the middle', from: 3000, to: 1500, weight: 1, lineup: [40, 80, 160], speed: false },
    { key: 'IC', name: 'in close', from: 1500, to: 300, weight: 1.5, lineup: [25, 50, 100], speed: true }
  ];
  var AR = { key: 'AR', name: 'at the ramp (crossing the threshold)', weight: 2, lineup: [20, 35, 60] };
  var TD = { key: 'TD', name: 'at touchdown', weight: 2, lineup: [15, 30, 50] };

  var GLIDE_DEG = [0.5, 1.0, 2.0];      // off the glidepath: a little, clearly, way off
  var FAST_KT = [5, 10, 15];
  var SLOW_KT = [4, 7, 10];
  var RAMP_HIGH_FT = [15, 30, 60];
  var WING_DEG = [4, 8];
  var G_FIRM = [1.3, 1.6, 2.0];
  var GROOVE_SHORT_S = 12, GROOVE_LONG_S = 35;
  var POINTS = [0, 1, 3, 8];            // none, a little, clearly, way off

  var GRADES = {
    OKU: { symbol: 'OK', underline: true, points: 5.0, name: 'Perfect pass', color: 'green' },
    OK: { symbol: 'OK', points: 4.0, name: 'OK pass', color: 'green' },
    FAIR: { symbol: '(OK)', points: 3.0, name: 'Fair pass', color: 'yellow' },
    BOLTER: { symbol: 'B', points: 2.5, name: 'Bolter (landed very long)', color: 'blue' },
    NOGRADE: { symbol: '—', points: 2.0, name: 'No grade', color: 'brown' },
    CUT: { symbol: 'C', points: 0.0, name: 'Cut pass (unsafe)', color: 'red' }
  };

  function angDiff(a, b) {
    var d = ((a - b) % 360 + 540) % 360 - 180;
    return d;
  }

  // One landing direction of a runway, from a runways.json row.
  // row: [airport, low name, high name, low lat, low lon, high lat, high lon, width, low displaced, high displaced]
  function runwayEnds(row) {
    var mk = function (name, lat0, lon0, lat1, lon1, displaced) {
      var cos = Math.cos(lat0 * RAD);
      var e = (lon1 - lon0) * FT_PER_DEG_LAT * cos, n = (lat1 - lat0) * FT_PER_DEG_LAT;
      var len = Math.sqrt(e * e + n * n);
      return {
        airport: row[0], name: name, lat: lat0, lon: lon0, cos: cos,
        ue: e / len, un: n / len, length: len, width: row[7] || 75,
        displaced: displaced || 0, hdg: (Math.atan2(e, n) / RAD + 360) % 360
      };
    };
    return [mk(row[1], row[3], row[4], row[5], row[6], row[8]), mk(row[2], row[5], row[6], row[3], row[4], row[9])];
  }

  // Position relative to a landing direction: along = feet past the landing
  // threshold (negative before it), cross = feet right of the centerline.
  function relPos(end, lat, lon) {
    var e = (lon - end.lon) * FT_PER_DEG_LAT * end.cos, n = (lat - end.lat) * FT_PER_DEG_LAT;
    return { along: e * end.ue + n * end.un - end.displaced, cross: e * end.un - n * end.ue };
  }

  function findRunway(runwayRows, s) {
    var best = null;
    for (var i = 0; i < runwayRows.length; i++) {
      var r = runwayRows[i];
      if (Math.abs(r[3] - s.lat) > 0.06 || Math.abs(r[4] - s.lon) > 0.08) continue;
      var ends = runwayEnds(r);
      for (var k = 0; k < 2; k++) {
        var end = ends[k], p = relPos(end, s.lat, s.lon);
        var onIt = p.along > -end.displaced - 200 && p.along < end.length - end.displaced &&
          Math.abs(p.cross) < end.width / 2 + 60;
        if (!onIt || Math.abs(angDiff(s.trk, end.hdg)) > 25) continue;
        if (!best || Math.abs(p.cross) < best.absCross) best = { end: end, absCross: Math.abs(p.cross) };
      }
    }
    return best ? best.end : null;
  }

  // Looks through samples (from GrtLog.mergeSamples) for touchdowns on known runways.
  // Returns { passes, cutOff }. passes has one raw pass per landing; grade them with
  // gradePass(). cutOff lists approaches where the recording stopped just before
  // touchdown, so there is nothing to grade.
  function findLandings(samples, runwayRows) {
    var passes = [], cutOff = [];
    var n = samples.length;
    var armed = true, armAlt = 0;
    var back = function (i, sec) {      // index of the sample about sec seconds before i, same stretch of data
      var j = i;
      while (j > 0 && samples[i].t - samples[j].t < sec && samples[j].t - samples[j - 1].t < 3) j--;
      return samples[i].t - samples[j].t >= sec * 0.8 ? j : -1;
    };
    for (var i = 1; i < n; i++) {
      var s = samples[i];
      if (!armed) {
        if (s.palt > armAlt + 100 && s.ias > 50) armed = true;
        else continue;
      }
      if (s.ias < 35 || s.ias > 95 || s.gs < 25) continue;
      var j10 = back(i, 10);
      if (j10 < 0 || samples[j10].palt - s.palt < 25) continue;
      if (i === n - 1 || samples[i + 1].t - s.t >= 3) {
        // The data stops here, low and still coming down over a runway.
        var cutEnd = findRunway(runwayRows, s);
        if (cutEnd) cutOff.push({ t: s.t, airport: cutEnd.airport, runway: cutEnd.name });
        continue;
      }
      // Has the descent stopped? Compare half a second either side.
      var a = i, b = i;
      while (a > 0 && s.t - samples[a].t < 0.5 && samples[a].t - samples[a - 1].t < 3) a--;
      while (b < n - 1 && samples[b].t - s.t < 0.5 && samples[b + 1].t - samples[b].t < 3) b++;
      var dt = samples[b].t - samples[a].t;
      if (dt < 0.4 || (samples[b].palt - samples[a].palt) / dt < -1.5) continue;
      // It has to stay down: no real climb in the next 2 seconds, and nothing lower in the next 45.
      var ok = true;
      for (var k = i + 1; k < n && samples[k].t - samples[k - 1].t < 3 && samples[k].t - s.t < 45; k++) {
        var d = samples[k].palt - s.palt;
        if (samples[k].t - s.t <= 2 && (d > 5 || d < -4)) { ok = false; break; }
        if (d < -25) { ok = false; break; }
      }
      if (!ok) continue;
      var end = findRunway(runwayRows, s);
      if (!end) continue;
      // The descent actually stopped a moment earlier: step back to where the altitude first settled.
      var iTd = i;
      while (iTd > 0 && s.t - samples[iTd - 1].t <= 1.5 && Math.abs(samples[iTd - 1].palt - s.palt) <= 1) iTd--;
      passes.push(buildPass(samples, iTd, end));
      armed = false;
      armAlt = s.palt;
    }
    return { passes: passes, cutOff: cutOff };
  }

  // Everything needed to grade (and re-grade) one landing, small enough to keep.
  function buildPass(samples, i, end) {
    var td = samples[i];
    var prof = [];                     // [seconds before touchdown, ft past threshold, ft right, ft above touchdown, KIAS, track off runway heading]
    var lastKept = Infinity;
    for (var j = i; j >= 0; j--) {
      var s = samples[j];
      if (td.t - s.t > 90) break;
      if (j < i && samples[j + 1].t - s.t > 3) break;
      if (lastKept - s.t < 0.45 && j !== i) continue;     // keep about two points a second
      lastKept = s.t;
      var p = relPos(end, s.lat, s.lon);
      prof.push([+(td.t - s.t).toFixed(2), Math.round(p.along), Math.round(p.cross), Math.round(s.palt - td.palt),
        +s.ias.toFixed(1), Math.round(angDiff(s.trk, end.hdg))]);
    }
    prof.reverse();
    // After touchdown: firmest G, how far off the centerline the rollout went, and whether it took off again.
    var g = td.g, rollMax = null, tng = false, rollSecs = 0;
    for (var k = i; k < samples.length; k++) {
      var r = samples[k];
      if (k > i && r.t - samples[k - 1].t > 3) break;
      var since = r.t - td.t;
      if (since > 40) break;
      if (since <= 1.5 && r.g > g) g = r.g;
      if (r.palt > td.palt + 50 && r.ias > 55) { tng = true; break; }
      if (r.gs < 30) break;
      var c = relPos(end, r.lat, r.lon).cross;
      if (rollMax === null || Math.abs(c) > Math.abs(rollMax)) rollMax = c;
      rollSecs = since;
    }
    for (var m = i - 1; m >= 0 && td.t - samples[m].t <= 0.5; m--) if (samples[m].g > g) g = samples[m].g;
    var tp = relPos(end, td.lat, td.lon);
    return {
      t: td.t, airport: end.airport, runway: end.name, width: end.width,
      td: { along: Math.round(tp.along), cross: Math.round(tp.cross), ias: +td.ias.toFixed(1), gs: +td.gs.toFixed(1),
        roll: +td.roll.toFixed(1), pitch: +td.pitch.toFixed(1), g: +g.toFixed(2) },
      rollout: rollSecs >= 2 ? { maxCross: Math.round(rollMax), secs: Math.round(rollSecs) } : null,
      touchAndGo: tng,
      prof: prof
    };
  }

  function level(value, limits) {       // 0 none, 1 a little, 2 clearly, 3 way off
    var v = Math.abs(value), l = 0;
    for (var i = 0; i < limits.length; i++) if (v > limits[i]) l = i + 1;
    return l;
  }

  function interpAt(prof, along) {      // profile values where the airplane crossed a given distance
    for (var i = prof.length - 1; i > 0; i--) {
      var a = prof[i - 1], b = prof[i];
      if (a[1] <= along && b[1] >= along && b[1] > a[1]) {
        var f = (along - a[1]) / (b[1] - a[1]);
        return a.map(function (v, k) { return v + (b[k] - v) * f; });
      }
    }
    return null;
  }

  // Grades one pass from findLandings(). Returns the grade, the LSO comment in
  // shorthand, the same thing in plain words, and the measured numbers.
  function gradePass(pass, settings) {
    var st = {};
    for (var k in DEFAULTS) st[k] = settings && isFinite(settings[k]) && settings[k] !== null ? +settings[k] : DEFAULTS[k];
    var prof = pass.prof, wScale = Math.min(1.33, Math.max(0.5, pass.width / 150));
    var devs = [];     // { code, level, phase, text }
    var add = function (code, lvl, phase, text) { if (lvl > 0) devs.push({ code: code, level: lvl, phase: phase, text: text }); };
    var word = ['', 'a little ', '', 'very '];

    // The groove: the last unbroken stretch lined up with the runway.
    var g0 = prof.length - 1;
    while (g0 > 0 && Math.abs(prof[g0 - 1][5]) <= 15 && Math.abs(prof[g0 - 1][2]) <= 400) g0--;
    var grooveSecs = prof.length ? prof[g0][0] : 0;
    var grooveFromStart = g0 === 0;    // lined up for as far back as the data goes
    var groove = prof.slice(g0);

    var phases = [];
    PHASES.forEach(function (ph) {
      var pts = groove.filter(function (p) { return -p[1] <= ph.from && -p[1] > ph.to; });
      if (pts.length < 2) return;
      var span = Math.abs(pts[pts.length - 1][1] - pts[0][1]);
      if (span < (ph.from - ph.to) * 0.5) return;
      var sumA = 0, sumX = 0, sumV = 0;
      pts.forEach(function (p) {
        sumA += Math.atan2(p[3], -p[1] + st.aimFt) / RAD - st.glidepathDeg;
        sumX += p[2];
        sumV += p[4] - st.approachKias;
      });
      var m = { key: ph.key, name: ph.name, glideDeg: sumA / pts.length, cross: sumX / pts.length, speed: sumV / pts.length };
      phases.push(m);
      var gl = level(m.glideDeg, GLIDE_DEG);
      add(m.glideDeg > 0 ? 'H' : 'LO', gl, ph, word[gl] + (m.glideDeg > 0 ? 'high ' : 'low ') + ph.name);
      var ll = level(m.cross, ph.lineup.map(function (v) { return v * (ph.key === 'IC' ? wScale : 1); }));
      add(m.cross < 0 ? 'LUL' : 'LUR', ll, ph, word[ll] + 'lined up ' + (m.cross < 0 ? 'left ' : 'right ') + ph.name);
      // Speed is graded in close and at the ramp only; farther out it is shown but not judged.
      var sl = !ph.speed ? 0 : m.speed > 0 ? level(m.speed, FAST_KT) : level(m.speed, SLOW_KT);
      add(m.speed > 0 ? 'F' : 'SLO', sl, ph, word[sl] + (m.speed > 0 ? 'fast ' : 'slow ') + ph.name);
    });

    // At the ramp: crossing the threshold.
    var ramp = null, at = interpAt(groove, 0);
    if (at) {
      var expect = st.aimFt * Math.tan(st.glidepathDeg * RAD);
      ramp = { height: at[3], expected: expect, cross: at[2], speed: at[4] - st.approachKias };
      var hi = at[3] - expect;
      if (hi > 0) {
        var hl = level(hi, RAMP_HIGH_FT);
        add('H', hl, AR, word[hl] + 'high crossing the threshold');
      } else if (at[3] < 5) {
        add('LO', 2, AR, 'low crossing the threshold');
      } else if (hi < -8 && at[3] < 10) {
        add('LO', 1, AR, 'a little low crossing the threshold');
      }
      var rl = level(at[2], AR.lineup.map(function (v) { return v * wScale; }));
      add(at[2] < 0 ? 'LUL' : 'LUR', rl, AR, word[rl] + 'lined up ' + (at[2] < 0 ? 'left' : 'right') + ' crossing the threshold');
      var rs = ramp.speed > 0 ? level(ramp.speed, FAST_KT) : level(ramp.speed, SLOW_KT);
      add(ramp.speed > 0 ? 'F' : 'SLO', rs, AR, word[rs] + (ramp.speed > 0 ? 'fast' : 'slow') + ' crossing the threshold');
    }

    // Touchdown.
    var td = pass.td, past = td.along - st.aimFt, wire = null, bolter = false, shortOfRunway = td.along < 0;
    if (shortOfRunway) add('SHORT', 3, TD, 'touched down before the threshold');
    else if (past < -150) { wire = 1; add(null, 1, TD, 'touched down a little short of the target (1 wire)'); }
    else if (past < 0) wire = 2;
    else if (past <= 200) wire = 3;
    else if (past <= 500) { wire = 4; add(null, 1, TD, 'touched down a little long (4 wire)'); }
    else if (past <= 1000) add('LONG', 2, TD, 'touched down long');
    else { bolter = true; add('LONG', 2, TD, 'touched down very long (more than 1,000 ft past the target)'); }
    var tl = level(td.cross, TD.lineup.map(function (v) { return v * wScale; }));
    add(td.cross < 0 ? 'LL' : 'LR', tl, TD, 'landed ' + word[tl] + (td.cross < 0 ? 'left' : 'right') + ' of the centerline');
    var wl = level(td.roll, WING_DEG);
    add(td.roll < 0 ? 'LLWD' : 'LRWD', wl, TD, 'landed ' + (wl === 1 ? 'a little ' : '') + (td.roll < 0 ? 'left' : 'right') + ' wing down');
    var gl2 = level(td.g, G_FIRM);
    add('HARD', gl2, TD, ['', 'firm touchdown', 'hard touchdown', 'very hard touchdown'][gl2]);

    var grooveDev = null;
    if (!grooveFromStart && grooveSecs < GROOVE_SHORT_S) grooveDev = { code: 'NESA', level: 1, text: 'not enough straightaway (a short final)' };
    else if (grooveSecs > GROOVE_LONG_S) grooveDev = { code: 'LIG', level: 1, text: 'long in the groove (a long final)' };

    var score = grooveDev ? 0.5 : 0, worstClose = 0;
    devs.forEach(function (d) {
      score += POINTS[d.level] * d.phase.weight;
      if (d.phase.key !== 'X' && d.phase.key !== 'IM') worstClose = Math.max(worstClose, d.level);
      else if (d.phase.key === 'IM' && d.level === 2) worstClose = Math.max(worstClose, 2);
    });

    var grade;
    if (td.g >= G_FIRM[2]) grade = 'CUT';
    else if (shortOfRunway || worstClose >= 3 || score >= 14) grade = 'NOGRADE';
    else if (bolter) grade = 'BOLTER';
    else if (worstClose >= 2 || score >= 6) grade = 'FAIR';
    else if (score === 0 && (wire === 2 || wire === 3)) grade = 'OKU';
    else grade = 'OK';

    // The comment an LSO would write: (X) = a little, X = clearly, underlined = way off.
    // (The 1 and 4 wires speak for themselves, so they get no code of their own.)
    var tokens = devs.filter(function (d) { return d.code; }).map(function (d) {
      return { text: d.code + (d.phase.key === 'TD' ? '' : d.phase.key), level: d.level };
    });
    if (grooveDev) tokens.unshift({ text: grooveDev.code, level: 1 });
    if (wire) tokens.push({ text: wire + ' WIRE', level: 2 });
    else if (bolter) tokens.push({ text: 'BOLTER', level: 2 });
    var plain = devs.map(function (d) { return d.text; });
    if (grooveDev) plain.unshift(grooveDev.text);

    return {
      grade: grade, symbol: GRADES[grade].symbol, points: GRADES[grade].points, color: GRADES[grade].color,
      name: GRADES[grade].name, underline: !!GRADES[grade].underline,
      tokens: tokens, plain: plain, wire: wire, score: score,
      phases: phases, ramp: ramp, grooveSecs: grooveSecs, grooveFromStart: grooveFromStart,
      settings: st
    };
  }

  function commentText(result) {
    return result.tokens.map(function (t) {
      return t.level === 1 ? '(' + t.text + ')' : t.level === 3 ? '_' + t.text + '_' : t.text;
    }).join(' ');
  }

  return {
    DEFAULTS: DEFAULTS, GRADES: GRADES, PHASES: PHASES,
    findLandings: findLandings, gradePass: gradePass, commentText: commentText,
    runwayEnds: runwayEnds, relPos: relPos, angDiff: angDiff
  };
});
