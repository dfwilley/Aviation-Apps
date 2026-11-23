// Run with: node test.js
// Builds made-up HXr recordings in memory (same byte layout as the real files),
// then checks that the reader finds the landing and the grader scores it as expected.
'use strict';
const assert = require('assert');
const GrtLog = require('./grt-log.js');
const Greenie = require('./grade.js');

// A test runway: 6,000 ft long, 100 ft wide, heading 090, with no displaced threshold.
const LAT = 32.0, LON = -111.0;
const COS = Math.cos(LAT * Math.PI / 180);
const ROW = ['KTST', '09', '27', LAT, LON, LAT, +(LON + 6000 / (364567 * COS)).toFixed(6), 100, 0, 0];
const END = Greenie.runwayEnds(ROW)[0];

function record(stream, tick, bytes) {
  const head = Buffer.alloc(9);
  head.writeUInt8(stream, 0);
  head.writeUInt32BE(tick, 1);
  head.writeUInt32BE(bytes.length, 5);
  return Buffer.concat([head, Buffer.from(bytes)]);
}
function ahrs(o) {
  const b = Buffer.alloc(28);
  b[0] = 0x7f; b[1] = 0xff; b[2] = 0xfe; b[3] = 4;
  b.writeInt16BE(Math.round((o.roll || 0) * 65536 / 360), 4);
  b.writeInt16BE(Math.round((o.pitch || 0) * 65536 / 360), 6);
  b.writeUInt16BE(Math.round(90 * 65536 / 360), 8);
  b.writeUInt16BE(Math.round(o.palt) + 5000, 10);
  b.writeInt16BE(0, 12);
  b.writeInt16BE(Math.round(o.ias * 1.68781 * 10), 14);
  b.writeInt16BE(Math.round((o.g || 1) * 980.665), 20);
  return b;
}
function rmc(utcMs, lat, lon, gs, trk) {
  const d = new Date(utcMs), p2 = n => String(n).padStart(2, '0');
  const dm = (v, w) => { const a = Math.abs(v), deg = Math.floor(a); return String(deg).padStart(w, '0') + ((a - deg) * 60).toFixed(5).padStart(8, '0'); };
  const tm = p2(d.getUTCHours()) + p2(d.getUTCMinutes()) + p2(d.getUTCSeconds()) + '.' + p2(Math.round(d.getUTCMilliseconds() / 10));
  const dt = p2(d.getUTCDate()) + p2(d.getUTCMonth() + 1) + p2(d.getUTCFullYear() % 100);
  return `$GPRMC,${tm},A,${dm(lat, 2)},${lat < 0 ? 'S' : 'N'},${dm(lon, 3)},${lon < 0 ? 'W' : 'E'},${gs.toFixed(3)},${trk.toFixed(2)},${dt},,,D,V*00\r`;
}

// Flies a straight-in approach and landing. Options change how well it is flown.
//   kias: approach speed. cross: ft right of centerline. tdAlong: touchdown, ft past threshold.
//   glide: glidepath angle. stopBefore: seconds before touchdown where the recording ends.
//   goAfter: take off again this many seconds after touchdown (touch and go), then land again.
function fly(o) {
  o = Object.assign({ kias: 70, cross: 0, tdAlong: 300, glide: 3, secondsOut: 32, tdG: 1.05, roll: 0, field: 2500 }, o);
  const t0 = Date.UTC(2026, 10, 20, 16, 0, 0);
  const parts = [];
  let tick = 500000;
  const tan = Math.tan(o.glide * Math.PI / 180);
  // One circuit: returns the list of states every 1/60 s from secondsOut before touchdown.
  const states = [];
  const pass = (tdAlong, firstTime, rollFor) => {
    const fps = o.kias * 1.68781;
    for (let s = -o.secondsOut; s <= rollFor; s += 1 / 60) {
      let along, h, ias = o.kias, g = 1;
      if (s < 0) { along = tdAlong + fps * s; h = -s * fps * tan; }
      else {
        const dec = 6 * 1.68781, t = Math.min(s, fps / dec - 3);   // slow down at 6 kt a second, keep rolling
        along = tdAlong + fps * t - dec * t * t / 2 + (s - t) * (fps - dec * t);
        h = 0; ias = (fps - dec * t) / 1.68781;
        if (s < 0.3) g = o.tdG;
      }
      states.push({ along, cross: o.cross, h, ias, g, roll: s > -1 && s < 0.5 ? o.roll : 0 });
    }
  };
  if (o.goAfter) {
    pass(o.tdAlong, true, o.goAfter);
    // Climb away to 600 ft over 40 seconds, well clear of the runway, then come back around.
    const last = states[states.length - 1];
    for (let s = 0; s < 40; s += 1 / 60) states.push({ along: last.along + 118 * s, cross: 0, h: s * 15, ias: 80, g: 1, roll: 0, away: true });
    for (let s = 0; s < 20; s += 1 / 60) states.push({ along: -20000, cross: 3000, h: 600, ias: 80, g: 1, roll: 0, away: true });
    pass(o.tdAlong, false, 12);
  } else pass(o.tdAlong, true, 12);

  const stopAt = o.stopBefore ? Math.round((o.secondsOut - o.stopBefore) * 60) : states.length;
  for (let k = 0; k < stopAt; k++) {
    const s = states[k], ms = k * 1000 / 60;
    if (k % 4 === 0) parts.push(record(1, tick + Math.round(ms), ahrs({ palt: o.field + s.h, ias: s.ias, g: s.g, roll: s.roll })));
    if (k % 15 === 0) {
      const e = s.along * END.ue + s.cross * END.un, n = s.along * END.un - s.cross * END.ue;
      const lat = LAT + n / 364567, lon = LON + e / (364567 * COS);
      parts.push(record(3, tick + Math.round(ms) + 20, Buffer.from(rmc(t0 + ms, lat, lon, s.ias, s.away ? 200 : 90), 'latin1')));
    }
  }
  return Buffer.concat(parts);
}

function run(o) {
  const parsed = GrtLog.parseLog(new Uint8Array(fly(o)));
  return Greenie.findLandings(GrtLog.mergeSamples([parsed]), [ROW]);
}
const codes = r => r.tokens.map(t => (t.level === 1 ? '(' + t.text + ')' : t.level === 3 ? '_' + t.text + '_' : t.text));

let passed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log('ok   ' + name); }
  catch (e) { console.log('FAIL ' + name + '\n     ' + e.message); process.exitCode = 1; }
}

test('reads a GPS sentence', () => {
  const f = GrtLog.parseRmc('$GPRMC,164352.50,A,3207.99519,N,11056.72266,W,1.705,93.34,170924,,,D,V*39');
  assert.ok(Math.abs(f.lat - 32.1332532) < 1e-6);
  assert.ok(Math.abs(f.lon - -110.9453777) < 1e-6);
  assert.strictEqual(f.gs, 1.705);
  assert.strictEqual(new Date(f.t * 1000).toISOString(), '2024-09-17T16:43:52.500Z');
});

test('reads an AHRS packet the same way GRTDecode does', () => {
  // A real packet from N721NE; GRTDecode 2.22 reads it as roll -0.46, pitch +8.22,
  // pressure altitude 2479 ft, airspeed 22.5 ft/s (13.33 kt), 9.77 m/s2.
  const pkt = Buffer.from('7ffffe04ffac05d943691d37000b00e10027fff403d19a0790000003', 'hex');
  const log = Buffer.concat([record(3, 1000, Buffer.from(rmc(Date.UTC(2024, 8, 17, 16, 43, 52), 32, -111, 0, 0), 'latin1')), record(1, 1100, pkt)]);
  const a = GrtLog.parseLog(new Uint8Array(log)).air[0];
  assert.strictEqual(a.palt, 2479);
  assert.ok(Math.abs(a.roll - -0.46) < 0.01 && Math.abs(a.pitch - 8.22) < 0.01);
  assert.ok(Math.abs(a.ias - 13.33) < 0.01);
  assert.ok(Math.abs(a.g * 9.80665 - 9.77) < 0.001);
});

test('a well-flown approach on the target is a perfect pass', () => {
  const f = run({});
  assert.strictEqual(f.passes.length, 1);
  const p = f.passes[0], r = Greenie.gradePass(p);
  assert.strictEqual(p.airport, 'KTST');
  assert.strictEqual(p.runway, '09');
  assert.ok(Math.abs(p.td.along - 300) <= 40, 'touchdown at ' + p.td.along);
  assert.ok(Math.abs(p.td.cross) <= 2);
  assert.strictEqual(p.touchAndGo, false);
  assert.deepStrictEqual(codes(r), []);
  assert.strictEqual(r.onTarget, true);
  assert.strictEqual(r.grade, 'OKU');
  assert.strictEqual(r.points, 5);
});

test('a little fast and a little left is a fair pass with those comments', () => {
  const r = Greenie.gradePass(run({ kias: 76, cross: -20 }).passes[0]);
  assert.deepStrictEqual(codes(r), ['(LULIC)', '(FIC)', '(LULAR)', '(FAR)', '(LL)']);
  assert.strictEqual(r.grade, 'FAIR');
});

test('touching down 400 ft past the target is a little long', () => {
  const r = Greenie.gradePass(run({ tdAlong: 700 }).passes[0]);
  assert.strictEqual(r.onTarget, false);
  assert.ok(codes(r).includes('(LONG)'), codes(r).join(' '));
  assert.ok(r.plain.includes('touched down a little long'));
});

test('landing 45 ft left on a 100 ft wide runway is no grade', () => {
  const r = Greenie.gradePass(run({ cross: -45 }).passes[0]);
  assert.ok(codes(r).includes('_LL_'), codes(r).join(' '));
  assert.strictEqual(r.grade, 'NOGRADE');
});

test('a steep approach is called high', () => {
  const r = Greenie.gradePass(run({ glide: 5 }).passes[0]);
  assert.ok(codes(r).some(c => /^\(?_?H(IM|IC)/.test(c)), codes(r).join(' '));
});

test('a recording that stops before touchdown is reported, not graded', () => {
  const f = run({ stopBefore: 2 });
  assert.strictEqual(f.passes.length, 0);
  assert.strictEqual(f.cutOff.length, 1);
  assert.strictEqual(f.cutOff[0].runway, '09');
});

test('a touch and go then a full stop gives two landings', () => {
  const f = run({ goAfter: 4 });
  assert.strictEqual(f.passes.length, 2);
  assert.strictEqual(f.passes[0].touchAndGo, true);
  assert.strictEqual(f.passes[1].touchAndGo, false);
});

test('the same data loaded twice gives the same single landing', () => {
  const p = GrtLog.parseLog(new Uint8Array(fly({})));
  assert.strictEqual(Greenie.findLandings(GrtLog.mergeSamples([p, p]), [ROW]).passes.length, 1);
});

test('grade rules: hard, short, bolter and settings', () => {
  const base = run({}).passes[0];
  const with_ = td => Object.assign({}, base, { td: Object.assign({}, base.td, td) });
  assert.strictEqual(Greenie.gradePass(with_({ g: 2.1 })).grade, 'CUT');
  assert.strictEqual(Greenie.gradePass(with_({ along: -40 })).grade, 'NOGRADE');
  assert.strictEqual(Greenie.gradePass(with_({ along: 1500 })).grade, 'BOLTER');
  assert.strictEqual(Greenie.gradePass(with_({ roll: 9 })).grade, 'FAIR');
  // The same pass against a 58-knot target is fast in close.
  assert.ok(codes(Greenie.gradePass(base, { approachKias: 58 })).includes('FIC'));
});

test('day and night at Tucson', () => {
  const tus = [32.116, -110.941];
  // September 28, 2024: 9:39 in the morning local (the real runway 12 landing) is day.
  assert.strictEqual(Greenie.isNight(Date.UTC(2024, 8, 28, 16, 39) / 1000, tus[0], tus[1]), false);
  // Sunset that day was about 6:13 pm local (01:13 UTC). Ten minutes later is twilight, still day.
  assert.strictEqual(Greenie.isNight(Date.UTC(2024, 8, 29, 1, 23) / 1000, tus[0], tus[1]), false);
  // An hour after sunset is night; so is 4 in the morning.
  assert.strictEqual(Greenie.isNight(Date.UTC(2024, 8, 29, 2, 13) / 1000, tus[0], tus[1]), true);
  assert.strictEqual(Greenie.isNight(Date.UTC(2024, 8, 28, 11, 0) / 1000, tus[0], tus[1]), true);
  // The sun is on the horizon (within a degree) at the published sunset time.
  assert.ok(Math.abs(Greenie.sunElevation(Date.UTC(2024, 8, 29, 1, 13) / 1000, tus[0], tus[1])) < 1.2);
  // Passes found in a recording carry the flag (the made-up flight is at 9 am local).
  assert.strictEqual(run({}).passes[0].night, false);
});

// ---------- the board page: paging through more than 30 landings ----------
const { openBoard } = require('./test-dom.js');
// n landings one day apart, oldest first. Every third one lands long, so the grades vary.
function board(n) {
  const good = run({}).passes[0], long = run({ tdAlong: 700 }).passes[0];
  const passes = [];
  for (let i = 0; i < n; i++) {
    const p = JSON.parse(JSON.stringify(i % 3 ? good : long));
    p.t = good.t + i * 86400;
    passes.push(p);
  }
  return { passes, settings: {} };
}
const tOf = (b, i) => Math.round(b.passes[i].t);
// Taps a square and returns which landing (0 = oldest) it opened.
const landingAt = (pg, b, sq) => { sq.click(); const t = +pg.win.location.hash.replace('#landing=', ''); return b.passes.findIndex(p => Math.round(p.t) === t); };

test('30 landings or fewer: no paging buttons', () => {
  const pg = openBoard(board(30));
  assert.strictEqual(pg.$('pager').hidden, true);
  assert.strictEqual(pg.$('pageInfo').hidden, true);
  assert.strictEqual(pg.squares().length, 30);
  assert.strictEqual(pg.blanks().length, 0);
});

test('33 landings: the newest 30 first, then the oldest 3', () => {
  const b = board(33), pg = openBoard(b);
  assert.strictEqual(pg.$('pager').hidden, false);
  assert.strictEqual(pg.$('pageInfo').hidden, false);
  assert.strictEqual(pg.$('olderBtn').disabled, false);
  assert.strictEqual(pg.$('newerBtn').disabled, true);
  assert.match(pg.$('pageInfo').textContent, /^Landings 4 to 33 of 33 · /);
  assert.strictEqual(pg.squares().length, 30);
  // Oldest at the top left, newest at the bottom right.
  assert.strictEqual(landingAt(pg, b, pg.squares()[0]), 3);
  pg.win.location.hash = '';
  assert.strictEqual(landingAt(pg, b, pg.squares()[29]), 32);
  pg.win.location.hash = '';
  assert.ok(pg.onBoard());
  pg.$('olderBtn').click();
  assert.match(pg.$('pageInfo').textContent, /^Landings 1 to 3 of 33 · /);
  assert.strictEqual(pg.$('olderBtn').disabled, true);
  assert.strictEqual(pg.$('newerBtn').disabled, false);
  assert.strictEqual(pg.squares().length, 3);
  assert.strictEqual(pg.blanks().length, 27);
  pg.$('olderBtn').click();   // disabled: nothing happens
  assert.match(pg.$('pageInfo').textContent, /^Landings 1 to 3 of 33 · /);

  pg.$('newerBtn').click();
  assert.match(pg.$('pageInfo').textContent, /^Landings 4 to 33 of 33 · /);
  assert.strictEqual(pg.$('newerBtn').disabled, true);
});

test('61 landings: three pages, the last holds one landing', () => {
  const b = board(61), pg = openBoard(b);
  const seen = [];
  const info = () => pg.$('pageInfo').textContent;
  assert.match(info(), /^Landings 32 to 61 of 61 · /);
  seen.push(...pg.squares().map(s => s.title));
  pg.$('olderBtn').click();
  assert.match(info(), /^Landings 2 to 31 of 61 · /);
  assert.strictEqual(pg.$('olderBtn').disabled, false);
  assert.strictEqual(pg.$('newerBtn').disabled, false);
  seen.push(...pg.squares().map(s => s.title));
  pg.$('olderBtn').click();
  // One landing on the page: no "1 to 1", and the date is not repeated.
  const day = new Date(b.passes[0].t * 1000).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
  assert.strictEqual(info(), 'Landing 1 of 61 · ' + day);
  assert.strictEqual(pg.$('olderBtn').disabled, true);
  assert.strictEqual(pg.squares().length, 1);
  assert.strictEqual(pg.blanks().length, 29);
  seen.push(...pg.squares().map(s => s.title));
  // Every landing shows exactly once across the pages.
  assert.strictEqual(seen.length, 61);
  assert.strictEqual(new Set(seen).size, 61);
  // The date range on a full page runs from its first to its last landing.
  pg.$('newerBtn').click();
  const d = i => new Date(b.passes[i].t * 1000).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
  assert.strictEqual(info(), 'Landings 2 to 31 of 61 · ' + d(1) + ' to ' + d(30));
});

test('61 landings: tapping a grade on an older page opens that landing, and Back returns to the same page', () => {
  const b = board(61), pg = openBoard(b);
  pg.$('olderBtn').click();
  const sq = pg.squares()[4];          // landing 6 of 61 (index 5)
  sq.click();
  assert.strictEqual(pg.win.location.hash, '#landing=' + tOf(b, 5));
  assert.ok(pg.onDetail(), 'the details page is showing');
  assert.ok(pg.$('detail').textContent.includes('KTST runway 09'), pg.$('detail').textContent.slice(0, 80));
  pg.$('backBtn').click();
  assert.ok(pg.onBoard());
  assert.match(pg.$('pageInfo').textContent, /^Landings 2 to 31 of 61 · /);
  // The phone's own back gesture does the same.
  pg.squares()[0].click();
  assert.ok(pg.onDetail());
  pg.win.history.back();
  assert.ok(pg.onBoard());
  assert.match(pg.$('pageInfo').textContent, /^Landings 2 to 31 of 61 · /);
  // The single landing on the last page opens too.
  pg.$('olderBtn').click();
  pg.squares()[0].click();
  assert.strictEqual(pg.win.location.hash, '#landing=' + tOf(b, 0));
  assert.ok(pg.onDetail());
});

test('a link straight to an old landing opens it even though it is not on the first page', () => {
  const b = board(61), pg = openBoard(b, '#landing=' + tOf(b, 2));
  assert.ok(pg.onDetail());
});

test('the KTUS-only setting pages through only the KTUS landings', () => {
  const b = board(40);
  b.passes.forEach((p, i) => { p.airport = i < 35 ? 'KTUS' : 'KTST'; });
  b.settings.scope = 'KTUS';
  const pg = openBoard(b);
  assert.match(pg.$('pageInfo').textContent, /^Landings 6 to 35 of 35 · /);
  pg.$('olderBtn').click();
  assert.match(pg.$('pageInfo').textContent, /^Landings 1 to 5 of 35 · /);
});

test('the page average covers only the landings on that page', () => {
  const b = board(33), pg = openBoard(b);
  const avg = list => (list.reduce((s, p) => s + Greenie.gradePass(p).points, 0) / list.length).toFixed(2) + ' average';
  assert.strictEqual(pg.$('gpa').textContent, avg(b.passes.slice(3)));
  pg.$('olderBtn').click();
  assert.strictEqual(pg.$('gpa').textContent, avg(b.passes.slice(0, 3)));
});

console.log(passed + ' passed');
