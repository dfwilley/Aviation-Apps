// Checks the shared weight and balance math. Run with: node web/test.js
const WB = require('./wb-core.js');
const assert = require('assert');
const near = (a, b, tol = 1e-9) => assert(Math.abs(a - b) < tol, a + ' is not ' + b);
const set = (p, o) => Object.assign(p, o);

// RV-14 tailwheel: same numbers as the first version of the app
let p = WB.newProfile(' n721ne ', 'rv14', 'tail');
set(p, { wL: '599', aL: '71.325', wR: '583', aR: '71.625', w3: '65', a3: '230.25', fuel: '50', burn: '30' });
p.stations[0].load = '240'; p.stations[2].load = '20';
let r = WB.compute(p);
assert.strictEqual(p.reg, 'N721NE');
near(r.emptyWeight, 1247); near(r.emptyMoment, 99447.30, 1e-6);
near(r.toW, 1807); near(r.toCG, 83.33541781959049); near(r.lCG, 83.48647818070067); near(r.zfCG, 83.60723291307234);
near(WB.mac(p, r.toCG), 20.241817534983017);
assert.strictEqual(r.statusText, 'Within utility limits for takeoff and landing.');
p.stations[1].load = '220'; p.stations[2].load = '100'; p.cat = 1;
r = WB.compute(p);
assert.strictEqual(r.statusText, 'Out of limits: takeoff weight is 207 lb over the 1,900 lb aerobatic limit; takeoff CG 86.81 in is aft of 86 in; landing CG 87.26 in is aft of 86 in; zero-fuel CG 87.61 in is aft of 86 in.');

// RV-7A nosewheel
p = WB.newProfile('N512PT', 'rv7', 'nose');
set(p, { wL: '420', aL: '90.5', wR: '418', aR: '90.5', w3: '262', a3: '37.2', fuel: '42', burn: '20' });
p.stations[0].load = '180'; p.stations[1].load = '170'; p.stations[2].load = '60';
assert.strictEqual(WB.modelName(p.model, p.gear), 'RV-7A');
r = WB.compute(p);
near(r.emptyCG, 77.80490909090909); near(r.toW, 1762); near(r.toCG, 83.69477866061294);
assert.deepStrictEqual(WB.chartRange(p, r), { x0: 76, x1: 89, xStep: 1, y0: 1000, y1: 1900, yStep: 100 });
// edited envelope, baggage arm and fuel arm
p.cats[0].aft = '83';
assert(/takeoff CG 83.69 in is aft of 83 in/.test(WB.compute(p).statusText));
p.cats[0].aft = '86.82'; p.stations[2].arm = '130'; p.fuelArm = '81';
r = WB.compute(p);
near(r.zfM, 85585.4 + 350 * 97.48 + 60 * 130, 1e-6); near(r.toM, r.zfM + 252 * 81, 1e-6);
WB.applyPreset(p, p.model);
assert.strictEqual(p.stations[2].arm, '126.78'); assert.strictEqual(p.fuelArm, '80');
assert.strictEqual(p.stations[0].load, '180'); assert.strictEqual(p.wL, '420');

// RV-10: four seats, one category
p = WB.newProfile('N10XX', 'rv10');
assert.strictEqual(p.gear, 'nose'); assert.strictEqual(WB.compute(p), null);
set(p, { wL: '610', aL: '124.4', wR: '612', aR: '124.4', w3: '398', a3: '50.4', fuel: '60', burn: '40', cat: 1 });
['200', '180', '300', '120'].forEach((v, i) => { p.stations[i].load = v; });
r = WB.compute(p);
near(r.toCG, 115.47424460431655);
assert.strictEqual(r.statusText, 'Out of limits: takeoff weight is 80 lb over the 2,700 lb normal limit; zero-fuel CG 116.45 in is aft of 116.24 in; baggage is 20 lb over the 100 lb limit.');

// custom aircraft and saved-data repair
assert.deepStrictEqual(WB.missing(WB.newProfile('C-GABC', 'custom', 'nose')), ['the empty weight (scale readings)', 'the weight limit and CG range']);
assert.strictEqual(WB.normalize({ model: 'rv9', gear: 'nose', reg: 'N9' }).stations[2].max, '100');
assert.strictEqual(WB.normalize(JSON.parse(JSON.stringify(p))).stations[2].load, '300');

// Van's sheets give limits in inches and percent of chord; the two must agree
const pct = { rv4: [15, 30, 27.5], rv6: [15, 29, 26.5], rv7: [15, 29, 25], rv8: [15, 29, 26.5], rv9: [15, 28, 24], rv10: [15, 30], rv14: [18, 29, 25] };
for (const id in pct) {
  const q = WB.newProfile('', id);
  near(WB.mac(q, +q.cats[0].fwd), pct[id][0], 0.15); near(WB.mac(q, +q.cats[0].aft), pct[id][1], 0.15);
  if (pct[id][2]) near(WB.mac(q, +q.cats[1].aft), pct[id][2], 0.15);
}
console.log('All weight and balance checks passed.');
