// Homebuilt W&B: weight and balance math and RV model defaults.
// The native iPhone app (WBModel.swift) mirrors this file line for line.
(function (root) {
  'use strict';

  // ---- RV model defaults --------------------------------------------------
  // Limits and arms come from Van's Aircraft "Weight and Balance Data Quick
  // Reference" sheets (RV-12: Pilot's Operating Handbook Section IV).
  // Fuel capacity and baggage figures come from Van's specification tables
  // unless the note says otherwise. Wheel arms are not published by Van's;
  // they come from each airplane's own weighing.
  var st = function (id, name, arm, max) { return { id: id, name: name, arm: arm, max: max || '' }; };
  var PRESETS = [
    { id: 'rv4', name: 'RV-4', aName: '', gear: 'tail', le: '60', chord: '58',
      fuelArm: '70', fuelCap: '32',
      cats: [{ name: 'Utility', gross: '1500', fwd: '68.7', aft: '77.4' },
             { name: 'Aerobatic', gross: '1375', fwd: '68.7', aft: '75.9' }], twoCats: true,
      stations: [st('pilot', 'Pilot', '82.5'), st('pax', 'Passenger', '107'),
                 st('bagF', 'Forward baggage', '56.5'), st('bag', 'Rear baggage', '130', '30')],
      note: 'Van\'s RV-4 Weight and Balance Data Quick Reference. Fuel 32 gal and baggage about 30 lb: Van\'s specifications table. The forward baggage area is an option; leave it at 0 if you do not have one.' },
    { id: 'rv6', name: 'RV-6', aName: 'RV-6A', gear: 'tail', le: '60', chord: '58',
      fuelArm: '70', fuelCap: '38',
      cats: [{ name: 'Utility', gross: '1650', fwd: '68.7', aft: '76.8' },
             { name: 'Aerobatic', gross: '1375', fwd: '68.7', aft: '75.3' }], twoCats: true,
      stations: [st('pilot', 'Pilot', '87.4'), st('pax', 'Passenger', '87.4'), st('bag', 'Baggage', '117')],
      note: 'Van\'s RV-6 Weight and Balance Data Quick Reference. Fuel capacity 38 gal is the commonly published figure, not from a Van\'s sheet; check yours. No baggage limit is pre-filled; enter the limit from your own records.' },
    { id: 'rv7', name: 'RV-7', aName: 'RV-7A', gear: 'tail', le: '70', chord: '58',
      fuelArm: '80', fuelCap: '42',
      cats: [{ name: 'Utility', gross: '1800', fwd: '78.7', aft: '86.82' },
             { name: 'Aerobatic', gross: '1600', fwd: '78.7', aft: '84.5' }], twoCats: true,
      stations: [st('pilot', 'Pilot', '97.48'), st('pax', 'Passenger', '97.48'), st('bag', 'Baggage', '126.78', '100')],
      note: 'Van\'s RV-7 Weight and Balance Data Quick Reference. Fuel 42 gal and baggage 100 lb: Van\'s specifications table.' },
    { id: 'rv8', name: 'RV-8', aName: 'RV-8A', gear: 'tail', le: '70', chord: '58',
      fuelArm: '80', fuelCap: '42',
      cats: [{ name: 'Utility', gross: '1800', fwd: '78.7', aft: '86.82' },
             { name: 'Aerobatic', gross: '1600', fwd: '78.7', aft: '85.3' }], twoCats: true,
      stations: [st('pilot', 'Pilot', '91.78'), st('pax', 'Passenger', '119.12'),
                 st('bagF', 'Forward baggage', '58.51'), st('bag', 'Aft baggage floor', '138'),
                 st('bagS', 'Aft baggage shelf', '152.91')],
      note: 'Van\'s RV-8 Weight and Balance Data Quick Reference. Aerobatic gross weight is 1,600 lb with the Dash-One wing and 1,550 lb without it; change it if yours is the earlier wing. Fuel 42 gal: Van\'s specifications table, which lists about 125 lb of baggage in total. No limit is pre-filled for each baggage area; enter your own.' },
    { id: 'rv9', name: 'RV-9', aName: 'RV-9A', gear: 'tail', le: '70', chord: '53',
      fuelArm: '76.75', fuelCap: '36',
      cats: [{ name: 'Normal', gross: '1750', fwd: '77.95', aft: '84.84' },
             { name: 'Utility', gross: '1600', fwd: '77.95', aft: '82.72' }], twoCats: true,
      stations: [st('pilot', 'Pilot', '92.7'), st('pax', 'Passenger', '92.7'), st('bag', 'Baggage', '122', '100')],
      note: 'Van\'s RV-9 Weight and Balance Data Quick Reference. The RV-9 is not aerobatic; its second envelope is the utility category (1,600 lb, aft limit 82.72 in). Fuel 36 gal and baggage 100 lb: Van\'s specifications table.' },
    { id: 'rv10', name: 'RV-10', aName: '', gear: 'nose', le: '99.44', chord: '56',
      fuelArm: '108.9', fuelCap: '60',
      cats: [{ name: 'Normal', gross: '2700', fwd: '107.84', aft: '116.24' },
             { name: 'Category 2', gross: '', fwd: '', aft: '' }], twoCats: false,
      stations: [st('pilot', 'Pilot', '114.58'), st('pax', 'Front passenger', '114.58'),
                 st('rear', 'Rear passengers', '151.26'), st('bag', 'Baggage', '173.5', '100')],
      note: 'Van\'s RV-10 Weight and Balance Data Quick Reference. Fuel capacity 60 gal and baggage 100 lb are the commonly published figures, not from a Van\'s sheet; check yours.' },
    { id: 'rv12', name: 'RV-12', aName: '', gear: 'nose', le: '', chord: '',
      fuelArm: '110.28', fuelCap: '20',
      cats: [{ name: 'Light-sport', gross: '1320', fwd: '80.49', aft: '85.39' },
             { name: 'Category 2', gross: '', fwd: '', aft: '' }], twoCats: false,
      stations: [st('pilot', 'Pilot', '78.85'), st('pax', 'Passenger', '78.85'), st('bag', 'Baggage', '110.81', '50')],
      note: 'Van\'s RV-12 Pilot\'s Operating Handbook, Section IV (CG limits and arms). Gross weight 1,320 lb, fuel 20 gal and baggage 50 lb are the commonly published figures; check your handbook. These are for the original RV-12. The RV-12iS has a different fuel tank arm, so use Custom values from your own handbook for an RV-12iS.' },
    { id: 'rv14', name: 'RV-14', aName: 'RV-14A', gear: 'tail', le: '72', chord: '56',
      fuelArm: '81.97', fuelCap: '50',
      cats: [{ name: 'Utility', gross: '2050', fwd: '82.08', aft: '88.24' },
             { name: 'Aerobatic', gross: '1900', fwd: '82.08', aft: '86' }], twoCats: true,
      stations: [st('pilot', 'Pilot', '99.83'), st('pax', 'Passenger', '99.83'), st('bag', 'Baggage', '129.48', '100')],
      note: 'Van\'s RV-14 Weight and Balance Data Quick Reference. Fuel 50 gal and baggage 100 lb: Van\'s RV-14 specification sheet.' }
  ];

  var CUSTOM = { id: 'custom', name: 'Custom', aName: '', gear: 'tail', le: '', chord: '',
    fuelArm: '', fuelCap: '',
    cats: [{ name: 'Utility', gross: '', fwd: '', aft: '' }, { name: 'Aerobatic', gross: '', fwd: '', aft: '' }],
    twoCats: false,
    stations: [st('pilot', 'Pilot', ''), st('pax', 'Passenger', ''), st('bag', 'Baggage', '')],
    note: 'Custom aircraft: every limit and arm is entered by you from your aircraft\'s own records.' };

  function preset(id) {
    for (var i = 0; i < PRESETS.length; i++) if (PRESETS[i].id === id) return PRESETS[i];
    return CUSTOM;
  }

  /** Name shown for the model: the "A" name when it has a nosewheel. */
  function modelName(id, gear) {
    var p = preset(id);
    if (p.id === 'custom') return '';
    return gear === 'nose' && p.aName ? p.aName : p.name;
  }

  // ---- Profile ------------------------------------------------------------
  /** Copies a model's limits and arms into the profile. Loads typed for stations with the same id are kept. */
  function applyPreset(p, id) {
    var d = preset(id), old = {};
    (p.stations || []).forEach(function (s) { old[s.id] = s.load; });
    p.model = d.id;
    p.le = d.le; p.chord = d.chord;
    p.fuelArm = d.fuelArm; p.fuelCap = d.fuelCap;
    p.cats = d.cats.map(function (c) { return { name: c.name, gross: c.gross, fwd: c.fwd, aft: c.aft }; });
    p.twoCats = d.twoCats;
    if (!p.twoCats) p.cat = 0;
    p.stations = d.stations.map(function (s) {
      return { id: s.id, name: s.name, arm: s.arm, max: s.max, load: old[s.id] != null ? old[s.id] : '0' };
    });
    return p;
  }

  function newProfile(reg, modelId, gear) {
    var d = preset(modelId);
    var p = { v: 1, reg: cleanReg(reg), model: d.id, gear: gear || d.gear,
      wL: '', aL: '', wR: '', aR: '', w3: '', a3: '', dW: '0', dA: '0',
      stations: [], fuelArm: '', fuelCap: '', lbGal: '6', fuel: '0', burn: '0',
      cats: [], twoCats: false, cat: 0, le: '', chord: '' };
    return applyPreset(p, d.id);
  }

  function cleanReg(s) { return String(s == null ? '' : s).trim().toUpperCase().slice(0, 12); }

  /** Fills in anything missing from a saved profile so old saves keep working. */
  function normalize(p) {
    var d = newProfile('', (p && p.model) || 'custom', p && p.gear);
    if (!p || typeof p !== 'object') return d;
    ['reg', 'model', 'gear', 'wL', 'aL', 'wR', 'aR', 'w3', 'a3', 'dW', 'dA', 'fuelArm', 'fuelCap', 'lbGal',
      'fuel', 'burn', 'le', 'chord'].forEach(function (k) { if (typeof p[k] === 'string') d[k] = p[k]; });
    if (p.gear !== 'nose' && p.gear !== 'tail') d.gear = preset(d.model).gear;
    if (Array.isArray(p.cats) && p.cats.length === 2) {
      d.cats = p.cats.map(function (c, i) {
        c = c || {};
        return { name: str(c.name, d.cats[i].name), gross: str(c.gross, ''), fwd: str(c.fwd, ''), aft: str(c.aft, '') };
      });
    }
    if (typeof p.twoCats === 'boolean') d.twoCats = p.twoCats;
    d.cat = (p.cat === 1 && d.twoCats) ? 1 : 0;
    if (Array.isArray(p.stations) && p.stations.length) {
      d.stations = p.stations.map(function (s, i) {
        s = s || {};
        return { id: str(s.id, 's' + i), name: str(s.name, 'Item'), arm: str(s.arm, ''), max: str(s.max, ''), load: str(s.load, '0') };
      });
    }
    return d;
  }
  function str(v, fallback) { return typeof v === 'string' ? v : fallback; }

  // ---- Reading and writing numbers ---------------------------------------
  function value(s) {
    var t = String(s == null ? '' : s).trim().replace(/,/g, '');
    if (t === '') return 0;
    var v = Number(t);
    return isFinite(v) ? v : 0;
  }
  function positive(s) { var v = value(s); return v > 0 ? v : 0; }
  function plain(v) {
    var r = Math.round(v * 1e6) / 1e6;
    return String(r);
  }
  function stepped(s, step, lo, hi) { return plain(Math.max(lo, Math.min(hi, value(s) + step))); }
  function fmt(x, digits) {
    digits = digits || 0;
    var tiny = 0.5 * Math.pow(10, -digits);
    var v = Math.abs(x) < tiny ? 0 : x;
    // round half up like the iPhone app
    var m = Math.pow(10, digits);
    v = Math.sign(v) * Math.round(Math.abs(v) * m + 1e-9) / m;
    return v.toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits });
  }

  // ---- Math ---------------------------------------------------------------
  function emptyWeight(p) {
    var w0 = value(p.wL) + value(p.wR) + value(p.w3);
    var m0 = value(p.wL) * value(p.aL) + value(p.wR) * value(p.aR) + value(p.w3) * value(p.a3);
    return { weight: w0 + value(p.dW), moment: m0 + value(p.dW) * value(p.dA) };
  }

  /** Percent of wing chord, or null when the chord is not entered. */
  function mac(p, cg) {
    var c = value(p.chord);
    if (!(c > 0) || String(p.le).trim() === '') return null;
    return (cg - value(p.le)) / c * 100;
  }

  function activeCat(p) { return p.cats[p.twoCats && p.cat === 1 ? 1 : 0]; }

  /** True when a category has a usable weight limit and CG range. */
  function catReady(c) { return value(c.gross) > 0 && value(c.aft) > value(c.fwd); }

  /** What still has to be entered before a result can be shown; empty when ready. */
  function missing(p) {
    var out = [];
    if (!(emptyWeight(p).weight > 0)) out.push('the empty weight (scale readings)');
    if (!catReady(activeCat(p))) out.push('the weight limit and CG range');
    return out;
  }

  function compute(p) {
    if (missing(p).length) return null;
    var e = emptyWeight(p), ew = e.weight, em = e.moment;
    var cat = activeCat(p);
    var catName = (String(cat.name).trim() || 'category').toLowerCase();
    var gw = value(cat.gross), fwd = value(cat.fwd), aft = value(cat.aft);
    var lb = value(p.lbGal) > 0 ? value(p.lbGal) : 6;
    var cap = positive(p.fuelCap);
    var fuelArm = value(p.fuelArm);

    var rows = [], sumW = 0, sumM = 0, issues = [];
    p.stations.forEach(function (s) {
      var w = positive(s.load), a = value(s.arm);
      rows.push({ id: s.id, name: s.name, weight: w, arm: a, moment: w * a });
      sumW += w; sumM += w * a;
    });

    var fuelEntered = positive(p.fuel);
    var fuelG = cap > 0 ? Math.min(fuelEntered, cap) : fuelEntered;
    var burnG = Math.min(positive(p.burn), fuelG);
    var zfW = ew + sumW, zfM = em + sumM;
    var fW = fuelG * lb, lfW = (fuelG - burnG) * lb;
    var toW = zfW + fW, toM = zfM + fW * fuelArm, toCG = toM / toW;
    var lW = zfW + lfW, lM = zfM + lfW * fuelArm, lCG = lM / lW;
    var zfCG = zfM / zfW;
    var room = (gw - zfW) / lb;
    var maxFuel = Math.max(0, cap > 0 ? Math.min(cap, room) : room);

    function inCG(c) { return c >= fwd - 1e-9 && c <= aft + 1e-9; }
    function side(c) { return c < fwd ? 'forward of ' + plain(fwd) : 'aft of ' + plain(aft); }

    if (toW > gw) issues.push('takeoff weight is ' + fmt(toW - gw) + ' lb over the ' + fmt(gw) + ' lb ' + catName + ' limit');
    if (!inCG(toCG)) issues.push('takeoff CG ' + fmt(toCG, 2) + ' in is ' + side(toCG) + ' in');
    if (!inCG(lCG)) issues.push('landing CG ' + fmt(lCG, 2) + ' in is ' + side(lCG) + ' in');
    if (!inCG(zfCG)) issues.push('zero-fuel CG ' + fmt(zfCG, 2) + ' in is ' + side(zfCG) + ' in');
    p.stations.forEach(function (s) {
      var mx = positive(s.max), w = positive(s.load);
      if (mx > 0 && w > mx) issues.push(String(s.name).toLowerCase() + ' is ' + fmt(w - mx) + ' lb over the ' + plain(mx) + ' lb limit');
    });
    if (cap > 0 && fuelEntered > cap) issues.push('fuel is more than the ' + plain(cap) + ' gal capacity');

    var near = !issues.length &&
      (gw - toW < 25 || aft - Math.max(toCG, lCG, zfCG) < 0.3 || Math.min(toCG, lCG) - fwd < 0.3);
    var level = issues.length ? 'bad' : (near ? 'warn' : 'ok');
    var status = level === 'bad' ? 'Out of limits: ' + issues.join('; ') + '.'
      : level === 'warn' ? 'Within ' + catName + ' limits, but close to an edge.'
      : 'Within ' + catName + ' limits for takeoff and landing.';

    return { catName: catName, emptyWeight: ew, emptyMoment: em, emptyCG: em / ew, rows: rows,
      fuelGal: fuelG, burnGal: burnG, fuelArm: fuelArm, lbGal: lb, gross: gw, fwdCG: fwd, aftCG: aft,
      zfW: zfW, zfM: zfM, zfCG: zfCG, fuelW: fW, burnW: burnG * lb,
      toW: toW, toM: toM, toCG: toCG, lW: lW, lM: lM, lCG: lCG, maxFuel: maxFuel,
      margin: gw - toW, overWeight: toW > gw, inCG: inCG, issues: issues, level: level, statusText: status };
  }

  /** Axis ranges for the envelope chart, sized to the limits and the loading points. */
  function chartRange(p, r) {
    var xs = [r.toCG, r.lCG, r.zfCG], top = 0;
    p.cats.forEach(function (c, i) {
      if ((i === 0 || p.twoCats) && catReady(c)) { xs.push(value(c.fwd), value(c.aft)); top = Math.max(top, value(c.gross)); }
    });
    var lo = Math.min.apply(null, xs.slice(3)), hi = Math.max.apply(null, xs.slice(3));
    var x0 = Math.floor(lo) - 2, x1 = Math.ceil(hi) + 2;
    var xStep = (x1 - x0) > 14 ? 2 : 1;
    var y1 = Math.ceil((Math.max(top, 0) + 100) / 100) * 100;
    var y0 = Math.floor((Math.min(r.emptyWeight, r.zfW) - 50) / 100) * 100;
    if (y0 >= y1 - 200) y0 = y1 - 400;
    if (y0 < 0) y0 = 0;
    var yStep = (y1 - y0) > 1400 ? 200 : 100;
    return { x0: x0, x1: x1, xStep: xStep, y0: y0, y1: y1, yStep: yStep };
  }

  var api = { PRESETS: PRESETS, CUSTOM: CUSTOM, preset: preset, modelName: modelName, applyPreset: applyPreset,
    newProfile: newProfile, normalize: normalize, cleanReg: cleanReg, value: value, positive: positive,
    plain: plain, stepped: stepped, fmt: fmt, emptyWeight: emptyWeight, mac: mac, activeCat: activeCat,
    catReady: catReady, missing: missing, compute: compute, chartRange: chartRange };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.WB = api;
})(typeof self !== 'undefined' ? self : this);
