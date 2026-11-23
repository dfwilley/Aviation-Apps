// A very small stand-in for a web browser, just enough to run the board page's own
// script (the <script> block at the end of index.html) under Node with no installs.
// It lets test.js seed a board, press Older and Newer, tap a grade and read what shows.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

class Node_ {
  constructor(tag) {
    this.tagName = String(tag).toUpperCase();
    this.children = []; this.parentNode = null; this._text = '';
    this.attrs = {}; this.listeners = {}; this.style = {}; this.dataset = {};
    this.hidden = false; this.disabled = false; this.className = ''; this.title = '';
    this.value = ''; this.id = ''; this.scrollLeft = 0; this.scrollWidth = 0;
  }
  get textContent() { return this.children.length ? this.children.map(c => c.textContent).join('') : this._text; }
  set textContent(v) { this.children.forEach(c => { c.parentNode = null; }); this.children = []; this._text = String(v); }
  appendChild(c) { if (c.parentNode) c.remove(); c.parentNode = this; this.children.push(c); return c; }
  remove() { if (this.parentNode) { const k = this.parentNode.children; k.splice(k.indexOf(this), 1); this.parentNode = null; } }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; }
  addEventListener(type, fn) { (this.listeners[type] = this.listeners[type] || []).push(fn); }
  dispatch(type) { (this.listeners[type] || []).slice().forEach(fn => fn.call(this, { type, target: this })); }
  click() { if (!this.disabled) this.dispatch('click'); }
  showModal() { this.open = true; } close() { this.open = false; }
  get classList() { return { contains: c => this.className.split(/\s+/).includes(c) }; }
  // Only ".class" selectors, which is all the page uses.
  querySelectorAll(sel) {
    const cls = sel.replace(/^\./, ''), out = [];
    const walk = n => n.children.forEach(c => { if (c.classList.contains(cls)) out.push(c); walk(c); });
    walk(this); return out;
  }
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
}

// Loads index.html with the given saved board. Returns the page's window and helpers.
function openBoard(saved, hash) {
  const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
  const script = html.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/)[1];
  const elements = {};
  for (const m of html.matchAll(/<(\w+)[^>]*\sid="([^"]+)"([^>]*)>/g)) {
    const e = new Node_(m[1]); e.id = m[2];
    e.hidden = /\shidden[\s>]/.test(m[0]) || /\shidden$/.test(m[0].slice(0, -1));
    elements[m[2]] = e;
  }
  const store = { 'greenie-board-v1': JSON.stringify(saved) };
  const win = { listeners: {} };
  let curHash = hash || '';
  const location = {
    pathname: '/Aviation-Apps/greenie-board/', search: '',
    get hash() { return curHash; },
    set hash(v) { v = String(v); if (v && v[0] !== '#') v = '#' + v; if (v === curHash) return; curHash = v; fire('hashchange'); },
  };
  function fire(type) { (win.listeners[type] || []).slice().forEach(fn => fn({ type })); }
  Object.assign(win, {
    document: {
      getElementById: id => elements[id] || null,
      createElement: t => new Node_(t),
      createElementNS: (ns, t) => new Node_(t),
      createTextNode: t => { const n = new Node_('#text'); n._text = String(t); return n; },
      body: new Node_('body'),
    },
    location,
    history: {
      pushState(s, t, url) { const i = String(url).indexOf('#'); curHash = i < 0 ? '' : String(url).slice(i); },
      back() { curHash = ''; fire('popstate'); },
    },
    localStorage: {
      getItem: k => (k in store ? store[k] : null),
      setItem: (k, v) => { store[k] = String(v); },
    },
    addEventListener(type, fn) { (win.listeners[type] = win.listeners[type] || []).push(fn); },
    scrollTo() {},
    fetch: () => Promise.reject(new Error('offline in tests')),
    setTimeout: () => 0,
    console,
  });
  win.window = win;
  const ctx = vm.createContext(win);
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'grt-log.js'), 'utf8'), ctx);
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'grade.js'), 'utf8'), ctx);
  vm.runInContext(script, ctx);
  const $ = id => elements[id];
  return {
    $, win, store,
    squares: () => $('squares').children.filter(c => c.tagName === 'BUTTON'),
    blanks: () => $('squares').children.filter(c => c.classList.contains('blank')),
    onBoard: () => !$('boardView').hidden && $('detailView').hidden,
    onDetail: () => $('boardView').hidden && !$('detailView').hidden,
  };
}

module.exports = { openBoard };
