// A small stand-in for the browser DOM, enough to run apps/shared/app-core.js
// and the site pages' theme scripts under Node's test runner without a browser
// or a dependency. It models elements, text, attributes, classes and simple
// selectors (#id, .class, tag, *, [attr], [attr="v"], compounds of these,
// lists, descendants and ":scope > " children). A pseudo-class, such as the
// :not() in the query the modal's focus trap runs on Tab, throws. It does not
// parse HTML: innerHTML is kept as a string and counts as text. DOMParser reads
// XML, enough for the SVG figures, and XMLSerializer writes it back.
import { readFileSync } from "node:fs";
import vm from "node:vm";

// The element that last took the focus, which document.activeElement reports.
// makeWindow clears it, so one test's focus does not reach the next.
let ACTIVE = null;

class Node {
  constructor() { this.parentNode = null; this.children = []; }
  append(...kids) {
    for (const k of kids) {
      const n = k instanceof Node ? k : new Text(String(k));
      if (n.parentNode) n.parentNode._drop(n);
      n.parentNode = this; this.children.push(n);
    }
  }
  _drop(n) { this.children = this.children.filter((c) => c !== n); n.parentNode = null; }
  replaceChildren(...kids) { for (const c of [...this.children]) this._drop(c); this.append(...kids); }
  remove() { if (this.parentNode) this.parentNode._drop(this); }
  get childNodes() { return this.children; }
  replaceWith(...nodes) {
    const p = this.parentNode; if (!p) return;
    const at = p.children.indexOf(this);
    p._drop(this);
    const kids = nodes.map((k) => (k instanceof Node ? k : new Text(String(k))));
    for (const k of kids) { if (k.parentNode) k.parentNode._drop(k); k.parentNode = p; }
    p.children.splice(at, 0, ...kids);
  }
  get textContent() { return this.children.map((c) => c.textContent).join(""); }
  set textContent(v) { this.replaceChildren(); if (v !== "" && v != null) this.append(new Text(String(v))); }
}

class Text extends Node {
  constructor(t) { super(); this.nodeType = 3; this.data = t; }
  get textContent() { return this.data; }
  set textContent(v) { this.data = String(v); }
}

class Comment extends Node {
  constructor(t) { super(); this.nodeType = 8; this.data = t; }
  get textContent() { return ""; }
}

class ClassList {
  constructor(elem) { this.e = elem; }
  _set() { return new Set(this.e.className.split(/\s+/).filter(Boolean)); }
  _put(s) { this.e.className = [...s].join(" "); }
  add(...c) { const s = this._set(); c.forEach((x) => s.add(x)); this._put(s); }
  remove(...c) { const s = this._set(); c.forEach((x) => s.delete(x)); this._put(s); }
  contains(c) { return this._set().has(c); }
  toggle(c, on) { const s = this._set(); const want = on === undefined ? !s.has(c) : !!on; if (want) s.add(c); else s.delete(c); this._put(s); return want; }
}

class Element extends Node {
  constructor(tag) {
    super();
    this.nodeType = 1; this.tagName = tag.toUpperCase(); this.attributes = {};
    this.className = ""; this.classList = new ClassList(this); this.listeners = {};
    this.disabled = false; this.value = ""; this._html = null;
    this.style = { setProperty: (k, v) => { this.style[k] = v; } };
  }
  get id() { return this.attributes.id || ""; }
  get localName() { return this._name || this.tagName.toLowerCase(); }
  getAttributeNames() { return Object.keys(this.attributes); }
  getElementsByTagName(t) { return queryAll(this, t); }
  setAttribute(k, v) { if (k === "class") this.className = String(v); else this.attributes[k] = String(v); }
  getAttribute(k) { return k === "class" ? this.className : (k in this.attributes ? this.attributes[k] : null); }
  hasAttribute(k) { return k in this.attributes; }
  removeAttribute(k) { delete this.attributes[k]; }
  addEventListener(type, fn) { (this.listeners[type] = this.listeners[type] || []).push(fn); }
  removeEventListener() {}
  dispatch(type, ev) { return Promise.all((this.listeners[type] || []).map((fn) => fn(ev || { target: this }))); }
  click() { return this.dispatch("click"); }
  focus() { ACTIVE = this; }
  blur() { if (ACTIVE === this) ACTIVE = null; }
  set innerHTML(v) { this.replaceChildren(); this._html = String(v); }
  get innerHTML() { return this._html || ""; }
  get textContent() { return (this._html || "") + super.textContent; }
  set textContent(v) { this._html = null; super.textContent = v; }
  get offsetParent() { return this.parentNode; }
  querySelectorAll(sel) { return queryAll(this, sel); }
  querySelector(sel) { return queryAll(this, sel)[0] || null; }
}

function matchesSimple(e, simple) {
  if (simple === "*") return true;
  const m = simple.match(/^([a-z][a-z0-9]*)?((?:[#.][\w-]+|\[[\w-]+(?:="[^"]*")?\])*)$/i);
  if (!m) throw new Error("dom.mjs does not support the selector " + simple);
  if (m[1] && e.tagName !== m[1].toUpperCase()) return false;
  for (const part of m[2].match(/[#.][\w-]+|\[[^\]]+\]/g) || []) {
    if (part[0] === "#" && e.id !== part.slice(1)) return false;
    if (part[0] === "." && !e.classList.contains(part.slice(1))) return false;
    if (part[0] === "[") {
      const a = /^\[([\w-]+)(?:="([^"]*)")?\]$/.exec(part);
      if (!e.hasAttribute(a[1]) || (a[2] !== undefined && e.getAttribute(a[1]) !== a[2])) return false;
    }
  }
  return true;
}
function matches(e, selector, root) {
  const parts = selector.trim().split(/\s+/);
  if (!matchesSimple(e, parts[parts.length - 1])) return false;
  let i = parts.length - 2, anc = e.parentNode;
  while (i >= 0 && anc && anc !== root.parentNode) {
    if (anc instanceof Element && matchesSimple(anc, parts[i])) i--;
    anc = anc.parentNode;
  }
  return i < 0;
}
function queryAll(root, sel) {
  const out = [], lists = sel.split(",").map((s) => s.trim());
  // ":scope > x" matches the children of the root only.
  const scoped = lists.filter((s) => s.startsWith(":scope >")).map((s) => s.slice(8).trim());
  const deep = lists.filter((s) => !s.startsWith(":scope >"));
  const walk = (n) => {
    for (const c of n.children) {
      if (c instanceof Element) {
        if ((n === root && scoped.some((s) => matchesSimple(c, s))) || deep.some((s) => matches(c, s, root))) out.push(c);
        walk(c);
      }
    }
  };
  walk(root);
  return out;
}

// A throwing localStorage reproduces a browser that blocks site data: Chrome
// and Firefox then throw a SecurityError on the first touch of the property.
export function makeStorage(mode, initial) {
  if (mode === "blocked") {
    return { get() { throw new DOMException("Access is denied for this document.", "SecurityError"); } };
  }
  const store = new Map(Object.entries(initial || {}));
  const api = {
    getItem: (k) => (store.has(k) ? store.get(k) : null),
    setItem: (k, v) => { store.set(k, String(v)); },
    removeItem: (k) => { store.delete(k); },
    _store: store,
  };
  return { get() { return api; } };
}

// A small XML reader for DOMParser: declarations, a doctype, comments,
// elements with quoted attributes, text and the five predefined entities. A
// document it cannot read holds a parsererror element, as a browser's does,
// and so does one that holds a character XML 1.0 does not allow, written as a
// character or as a reference.
const xmlChar = (n) => n === 0x9 || n === 0xA || n === 0xD || (n >= 0x20 && n <= 0xD7FF) ||
  (n >= 0xE000 && n <= 0xFFFD) || (n >= 0x10000 && n <= 0x10FFFF);
const badXmlChars = (src) => /[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/.test(src) ||
  [...src.matchAll(/&#(x[0-9a-f]+|[0-9]+);/gi)].some((m) => !xmlChar(m[1][0].toLowerCase() === "x" ? parseInt(m[1].slice(1), 16) : parseInt(m[1], 10)));
const unent = (t) => t.replace(/&(lt|gt|amp|quot|apos|#\d+|#x[0-9a-f]+);/gi, (m, e) =>
  ({ lt: "<", gt: ">", amp: "&", quot: '"', apos: "'" }[e.toLowerCase()] ||
    String.fromCodePoint(e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10))));
function parseXml(src) {
  const top = new Element("#document");
  const stack = [top];
  const re = /<\?[\s\S]*?\?>|<!DOCTYPE[^>]*>|<!--([\s\S]*?)-->|<!\[CDATA\[([\s\S]*?)\]\]>|<\/([^\s>]+)\s*>|<([^\s/>!?]+)((?:\s+[^\s=/>]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>|([^<]+)/gy;
  let m, ok = true;
  while (re.lastIndex < src.length && (m = re.exec(src))) {
    const cur = stack[stack.length - 1];
    if (m[1] !== undefined) cur.append(new Comment(m[1]));
    else if (m[2] !== undefined) cur.append(new Text(m[2]));
    else if (m[3] !== undefined) {
      if (stack.length < 2 || stack[stack.length - 1]._name !== m[3]) { ok = false; break; }
      stack.pop();
    } else if (m[4] !== undefined) {
      const e = new Element(m[4]); e._name = m[4];
      for (const a of m[5].matchAll(/([^\s=/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) e.setAttribute(a[1], unent(a[2] !== undefined ? a[2] : a[3]));
      cur.append(e);
      if (!m[6]) stack.push(e);
    } else if (m[7] !== undefined) { if (stack.length > 1) cur.append(new Text(unent(m[7]))); else if (m[7].trim()) { ok = false; break; } }
  }
  if (re.lastIndex < src.length || stack.length !== 1 || badXmlChars(src)) ok = false;
  const root = top.children.find((c) => c instanceof Element) || null;
  if (!ok || !root) {
    const err = new Element("parsererror"); err._name = "parsererror";
    const holder = root || err;
    if (root) root.append(err);
    return { documentElement: holder, getElementsByTagName: (t) => queryAll(top, t), querySelector: (q) => top.querySelector(q) };
  }
  return { documentElement: root, getElementsByTagName: (t) => queryAll(top, t), querySelector: (q) => top.querySelector(q) };
}
const escXml = (t, attr) => String(t).replace(attr ? /[&<"]/g : /[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
function serializeXml(n) {
  if (n.nodeType === 3) return escXml(n.data);
  if (n.nodeType === 8) return "<!--" + n.data + "-->";
  const name = n.localName;
  const attrs = Object.entries(n.attributes).map(([k, v]) => " " + k + '="' + escXml(v, true) + '"').join("");
  return n.children.length ? "<" + name + attrs + ">" + n.children.map(serializeXml).join("") + "</" + name + ">" : "<" + name + attrs + "/>";
}
class DOMParser { parseFromString(s) { return parseXml(String(s)); } }
class XMLSerializer { serializeToString(n) { return serializeXml(n); } }

export function makeWindow({ storage = "ok", stored, prefersDark = false, fetchText, hash = "", confirm } = {}) {
  ACTIVE = null;
  const documentElement = new Element("html");
  const body = new Element("body");
  documentElement.append(body);
  const document = {
    documentElement, body, title: "",
    createElement: (t) => new Element(t),
    createTextNode: (t) => new Text(t),
    querySelector: (s) => documentElement.querySelector(s),
    querySelectorAll: (s) => documentElement.querySelectorAll(s),
    getElementById: (id) => documentElement.querySelector("#" + id),
    importNode: (n) => n,
    addEventListener() {}, removeEventListener() {},
    get activeElement() { return ACTIVE; },
  };
  // The address's fragment and the history entries that replace it, and the
  // window's own listeners, which a test can fire (hashchange).
  const location = { pathname: "/py/", search: "", hash, reload() {}, replace(url) { this.replaced = url; },
    get href() { return "http://127.0.0.1" + this.pathname + this.search + this.hash; } };
  const history = { replaced: [], replaceState(s, t, url) {
    this.replaced.push(url); const i = String(url).indexOf("#"); location.hash = i < 0 ? "" : String(url).slice(i);
  } };
  const winListeners = {};
  const ctx = {
    document, console, setTimeout, clearTimeout, URL, Blob, TextEncoder, TextDecoder, DOMException,
    DOMParser, XMLSerializer, Response, CompressionStream, DecompressionStream, btoa, atob,
    location, history,
    navigator: {},
    addEventListener: (type, fn) => { (winListeners[type] = winListeners[type] || []).push(fn); },
    removeEventListener() {},
    __fire: (type, ev) => Promise.all((winListeners[type] || []).map((fn) => fn(ev || {}))),
    matchMedia: (q) => ({ matches: /dark/.test(q) ? prefersDark : !prefersDark }),
    fetch: async (url) => ({ ok: true, status: 200, text: async () => (fetchText ? fetchText(url) : "id: x\n") }),
  };
  if (confirm) ctx.confirm = confirm;
  ctx.window = ctx; ctx.globalThis = ctx;
  ctx.__storage = makeStorage(storage, stored).get;
  vm.createContext(ctx);
  // Defined from inside the context: a getter installed on the context object
  // from outside reaches page code as a ReferenceError, not the SecurityError
  // a browser throws.
  vm.runInContext(`Object.defineProperty(globalThis, "localStorage", { configurable: true,
    get() { return __storage(); } });`, ctx);
  return ctx;
}

export function runScript(ctx, file, transform) {
  let src = readFileSync(file, "utf8");
  if (transform) src = transform(src);
  vm.runInContext(src, ctx, { filename: file });
  return ctx;
}

export { Element, Text, DOMParser, XMLSerializer };
