/* Hangar Board — read due items and Hobbs time from the maintenance database
   (Access .accdb back end). Read-only. Works in the browser and in Node for tests. */
(function (root) {
  'use strict';
  function iso(d) { return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }
  function fromDb(d) { // Access dates come back as Date objects in UTC; use the calendar date
    if (!(d instanceof Date) || isNaN(d)) return null;
    return new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  }
  // Day intervals that are whole years (365, 730, ...) are treated as calendar months,
  // due at the end of the month, like annual and 24-month inspections.
  function dueFrom(done, days) {
    if (days % 365 === 0) {
      var months = days / 365 * 12;
      return new Date(done.getFullYear(), done.getMonth() + months + 1, 0);   // last day of that month
    }
    var d = new Date(done); d.setDate(d.getDate() + days); return d;
  }
  function table(reader, name) {
    try { return reader.getTable(name); } catch (e) { return null; }
  }
  function cols(t, wanted) {     // read only plain columns we need (attachment columns can fail to decode)
    var have = t.getColumnNames(); return wanted.filter(function (c) { return have.indexOf(c) >= 0; });
  }
  function num(v) { return typeof v === 'number' && isFinite(v) ? v : null; }

  function importMaintenance(reader, opts) {
    opts = opts || {};
    var tail = (opts.tail || '').toUpperCase(), out = { hobbs: 0, hobbsDate: null, hobbsSource: '', items: [], skipped: [] };
    function seeHobbs(h, date, src) { h = num(h); if (h != null && h > out.hobbs) { out.hobbs = h; out.hobbsDate = date ? iso(date) : null; out.hobbsSource = src; } }

    var fl = table(reader, 'Flight Log');
    if (fl) fl.getData({ columns: cols(fl, ['Date', 'Tail Number', 'Hobbs End']) }).forEach(function (r) {
      if (tail && r['Tail Number'] && String(r['Tail Number']).toUpperCase() !== tail) return;
      seeHobbs(r['Hobbs End'], fromDb(r.Date), 'flight log');
    });
    var ml = table(reader, 'Maintenance Log');
    if (ml) ml.getData({ columns: cols(ml, ['Date', 'Hobbs']) }).forEach(function (r) { seeHobbs(r.Hobbs, fromDb(r.Date), 'maintenance log'); });

    function addItem(name, hrsInt, daysInt, doneHobbs, doneDate, kind) {
      var it = { name: String(name || '').trim(), group: 'a', src: 'db', origin: kind };
      if (!it.name) return;
      var hasH = hrsInt > 0 && doneHobbs != null, hasD = daysInt > 0 && doneDate;
      if (hasH) { it.dueHours = Math.round((doneHobbs + hrsInt) * 10) / 10; it.warnHours = Math.max(2, Math.round(hrsInt * 0.1)); }
      if (hasD) { it.dueDate = iso(dueFrom(doneDate, daysInt)); it.warnDays = daysInt >= 365 ? 60 : 14; }
      if (!hasH && !hasD) {
        if (hrsInt > 0 || daysInt > 0) out.skipped.push({ name: it.name, why: 'no completion recorded' });
        return;
      }
      it.kind = hasH && hasD ? 'b' : hasH ? 'h' : 'd';
      it.basis = (hasH ? 'every ' + hrsInt + ' hr' : '') + (hasH && hasD ? ' or ' : '') + (hasD ? (daysInt % 365 === 0 ? 'every ' + (daysInt / 365 * 12) + ' months' : 'every ' + daysInt + ' days') : '');
      it.lastDone = (doneDate ? iso(doneDate) : '') + (doneHobbs != null && hasH ? ' at ' + doneHobbs + ' hr' : '');
      out.items.push(it);
    }

    var rm = table(reader, 'Recurring Maintenance');
    if (rm) rm.getData({ columns: cols(rm, ['Inspection', 'Hour Interval', 'Time Interval (Days)', 'Completed Hobbs', 'Completed Date']) }).forEach(function (r) {
      seeHobbs(r['Completed Hobbs'], fromDb(r['Completed Date']), 'recurring maintenance');
      addItem(r.Inspection, num(r['Hour Interval']) || 0, num(r['Time Interval (Days)']) || 0, num(r['Completed Hobbs']), fromDb(r['Completed Date']), 'recurring');
    });
    var sb = table(reader, 'Service Bulletins');
    if (sb) sb.getData({ columns: cols(sb, ['SB', 'Compliance Interval (Flt Hours)', 'Compliance Interval (Days)', 'Compliance Date', 'Compliance Time']) }).forEach(function (r) {
      seeHobbs(r['Compliance Time'], fromDb(r['Compliance Date']), 'service bulletin');
      var h = num(r['Compliance Interval (Flt Hours)']) || 0, d = num(r['Compliance Interval (Days)']) || 0;
      if (!h && !d) return;   // one-time bulletin
      addItem(r.SB, h, d, num(r['Compliance Time']), fromDb(r['Compliance Date']), 'bulletin');
    });
    out.hobbs = Math.round(out.hobbs * 10) / 10;
    return out;
  }
  root.importMaintenance = importMaintenance;
  if (typeof module !== 'undefined' && module.exports) module.exports = { importMaintenance: importMaintenance };
})(typeof window !== 'undefined' ? window : globalThis);
