// A small stand-in for the browser DOM, enough to run apps/shared/app-core.js
// and the site pages' theme scripts under Node's test runner without a browser
// or a dependency. It models elements, text, attributes, classes and the simple
// selectors the app uses (#id, .class, tag, lists and descendants). It does not
// parse HTML: innerHTML is kept as a string and counts as text.
import { readFileSync } from "node:fs";
import vm from "node:vm";

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
  get textContent() { return this.children.map((c) => c.textContent).join(""); }
  set textContent(v) { this.replaceChildren(); if (v !== "" && v != null) this.append(new Text(String(v))); }
}

class Text extends Node {
  constructor(t) { super(); this.nodeType = 3; this.data = t; }
  get textContent() { return this.data; }
  set textContent(v) { this.data = String(v); }
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
  setAttribute(k, v) { if (k === "class") this.className = String(v); else this.attributes[k] = String(v); }
  getAttribute(k) { return k === "class" ? this.className : (k in this.attributes ? this.attributes[k] : null); }
  hasAttribute(k) { return k in this.attributes; }
  removeAttribute(k) { delete this.attributes[k]; }
  addEventListener(type, fn) { (this.listeners[type] = this.listeners[type] || []).push(fn); }
  removeEventListener() {}
  dispatch(type, ev) { return Promise.all((this.listeners[type] || []).map((fn) => fn(ev || { target: this }))); }
  click() { return this.dispatch("click"); }
  focus() {}
  set innerHTML(v) { this.replaceChildren(); this._html = String(v); }
  get innerHTML() { return this._html || ""; }
  get textContent() { return (this._html || "") + super.textContent; }
  set textContent(v) { this._html = null; super.textContent = v; }
  get offsetParent() { return this.parentNode; }
  querySelectorAll(sel) { return queryAll(this, sel); }
  querySelector(sel) { return queryAll(this, sel)[0] || null; }
}

function matchesSimple(e, simple) {
  const m = simple.match(/^([a-z][a-z0-9]*)?((?:[#.][\w-]+)*)$/i);
  if (!m) throw new Error("dom.mjs does not support the selector " + simple);
  if (m[1] && e.tagName !== m[1].toUpperCase()) return false;
  for (const part of m[2].match(/[#.][\w-]+/g) || []) {
    if (part[0] === "#" && e.id !== part.slice(1)) return false;
    if (part[0] === "." && !e.classList.contains(part.slice(1))) return false;
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
  const walk = (n) => {
    for (const c of n.children) {
      if (c instanceof Element) {
        if (lists.some((s) => matches(c, s, root))) out.push(c);
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

export function makeWindow({ storage = "ok", stored, prefersDark = false, fetchText } = {}) {
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
    addEventListener() {}, removeEventListener() {},
    get activeElement() { return null; },
  };
  const ctx = {
    document, console, setTimeout, clearTimeout, URL, Blob, TextEncoder, TextDecoder, DOMException,
    location: { reload() {} },
    navigator: {},
    matchMedia: (q) => ({ matches: /dark/.test(q) ? prefersDark : !prefersDark }),
    fetch: async (url) => ({ ok: true, status: 200, text: async () => (fetchText ? fetchText(url) : "id: x\n") }),
  };
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

export { Element, Text };
