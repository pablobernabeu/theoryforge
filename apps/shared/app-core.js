/* theoryforge interactive apps: shared core (language-agnostic).
 *
 * Responsibilities: the operation registry, the UI, shaping a runtime's raw
 * package output into display sections, rendering, export (SVG/PNG/text), the
 * reproducible-code panel, and the light/dark theme. A language runtime
 * (r-runtime.js / py-runtime.js) provides booting, theory loading, package calls
 * and the language-specific code snippets, then calls TF.start(runtime).
 */
(function () {
  "use strict";

  // The brand logo has one source of truth (r/theoryforge/man/figures/logo.svg),
  // vendored to vendor/logo.svg by build.mjs so the apps can never drift from it.
  const logoImg = () => el("img", { class: "logo", src: "vendor/logo.svg", alt: "theoryforge logo" });

  const OPS = [
    { id: "check", label: "Rigour checklist", desc: "12-item score, gate, per-item status",
      help: "Scores the theory against the 12-item rigour checklist (falsifiability, precision, parsimony, and so on) and returns an aggregate 0–100 score, a pass/blocked/advisory gate, and the colour-coded status grid." },
    { id: "validate", label: "Validate", desc: "Structural + referential checks",
      help: "Runs the package's full validation: required fields and enum membership, plus referential integrity (unique ids, and every proposition, prediction, assumption, evidence and test-outcome reference points to a declared id). Lists every problem found, or confirms the theory is valid." },
    {
      id: "diagram", label: "Diagram", desc: "Nomological net, DAG, workflow…",
      help: "Renders one of ten diagram types. Nomological net, context, workflow, causal DAG, provenance, development roadmap and pipeline are graph diagrams. The venn, rigour and severity types are emitted directly as SVG.",
      params: [{
        id: "type", label: "Diagram type", type: "select", default: "nomological_net",
        options: ["nomological_net", "context", "workflow", "causal_dag", "provenance",
          "development_roadmap", "pipeline", "venn", "rigour", "severity"],
      }],
    },
    { id: "severity", label: "Severity rubric", desc: "Per-prediction risk & severity",
      help: "Applies the operationalised severity rubric to every prediction, returning its risk score (the riskiness of the claim form) and computed severity (with the directional discount and the diagnostic bonus)." },
    { id: "redundancy", label: "Redundancy screen", desc: "Lexical overlap of constructs",
      help: "Compares every pair of construct definitions by token-set Jaccard overlap and flags pairs above the redundancy threshold for review." },
    {
      id: "appraise", label: "Appraise amendment", desc: "Progressive vs degenerating", needsPrior: true,
      help: "Compares the current theory, treated as the amendment, against a prior version and classifies the change as progressive, degenerating or neutral (Lakatos, 1970). Choose the prior version below.",
      params: [{ id: "prior", label: "Prior theory", type: "theory" }],
    },
    { id: "sem", label: "SEM (lavaan)", desc: "Compile to lavaan model syntax",
      help: "Compiles the constructs (measurement model) and propositions (structural model) to lavaan model syntax you can paste straight into an SEM fit." },
    { id: "preregister", label: "Preregistration", desc: "Preregistration document",
      help: "Generates a preregistration document in Markdown: hypotheses numbered in file order with their derivation, and the per-prediction severity." },
    { id: "dossier", label: "Audit dossier", desc: "Reviewer-facing bundle",
      help: "Assembles a reviewer-facing audit bundle in Markdown: the rigour report, severity, provenance and the preregistration in one document." },
    {
      id: "simulate", label: "Simulation", desc: "Dynamical-system trajectory",
      help: "Treats each construct as a state variable and each directed proposition as a signed coupling, then integrates the network with fixed-step (Euler) updates and plots the trajectory.",
      params: [
        { id: "steps", label: "steps", type: "number", default: 30, min: 1, max: 500, step: 1 },
        { id: "dt", label: "dt", type: "number", default: 0.1, min: 0.001, max: 2, step: 0.01 },
        { id: "k", label: "k (coupling)", type: "number", default: 1.0, min: 0, max: 10, step: 0.1 },
        { id: "damping", label: "damping", type: "number", default: 0.5, min: 0, max: 5, step: 0.1 },
        { id: "init", label: "init", type: "number", default: 1.0, min: -10, max: 10, step: 0.1 },
      ],
    },
    {
      id: "litmap", label: "Literature map", desc: "Co-occurrence, themes, co-citation", corpus: true,
      help: "Maps the bundled literature corpus: keyword co-occurrence, connected-component themes, and co-citation. min_link is the minimum number of records a pair must share to count as a link.",
      params: [{ id: "min_link", label: "min_link", type: "number", default: 2, min: 1, max: 20, step: 1 }],
    },
    {
      id: "landscape", label: "Theory landscape", desc: "Map theory onto lit themes", corpus: true,
      help: "Positions the theory and its alternatives against the corpus themes, flagging under-theorised fronts (no theory addresses them) and redundancy risk (crowded themes).",
      params: [{ id: "min_link", label: "min_link", type: "number", default: 2, min: 1, max: 20, step: 1 }],
    },
  ];

  // Diagram types the package emits directly as SVG (vs Graphviz DOT / dagitty).
  // Shared so the two runtimes' code-snippet generators cannot drift.
  const DIAG_SVG = ["venn", "rigour", "severity"];

  // Figures render on a light "paper" canvas in both themes so the package's
  // black-text SVGs and the trajectory chart stay legible. Single source for
  // the paper/ink/axis colours used by the chart and the PNG exporter.
  const FIG = { paper: "#ffffff", ink: "#333333", muted: "#666666", axis: "#bbbbbb" };

  // ---- small DOM / utility helpers ----------------------------------------
  const $ = (sel, root) => (root || document).querySelector(sel);
  function el(tag, attrs, kids) {
    const n = document.createElement(tag);
    if (attrs) for (const k in attrs) {
      if (k === "class") n.className = attrs[k];
      else if (k === "html") n.innerHTML = attrs[k];
      else if (k === "text") n.textContent = attrs[k];
      else if (k.slice(0, 2) === "on" && typeof attrs[k] === "function") n.addEventListener(k.slice(2), attrs[k]);
      else if (attrs[k] != null) n.setAttribute(k, attrs[k]);
    }
    for (const c of [].concat(kids || [])) if (c != null) n.append(c.nodeType ? c : document.createTextNode(c));
    return n;
  }
  const esc = (s) => String(s == null ? "" : s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));

  function download(filename, content, mime) {
    const blob = content instanceof Blob ? content : new Blob([content], { type: mime || "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = el("a", { href: url, download: filename });
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
  }
  async function copyText(t) {
    try { await navigator.clipboard.writeText(t); toast("Copied to clipboard"); }
    catch { toast("Copy failed — select and copy manually"); }
  }
  let toastTimer;
  function toast(msg) {
    let t = $(".toast"); if (!t) { t = el("div", { class: "toast", role: "status", "aria-live": "polite" }); document.body.append(t); }
    t.textContent = msg; t.classList.add("show");
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove("show"), 1800);
  }

  // ---- modal (WAI-ARIA dialog: labelled, focus-trapped, restores focus) ----
  let _modalReturnFocus = null;
  function focusables(root) {
    return [...root.querySelectorAll('button,a[href],select,input,textarea,[tabindex]:not([tabindex="-1"])')]
      .filter((x) => !x.disabled && x.offsetParent !== null);
  }
  function onModalKey(e) {
    if (e.key === "Escape") { closeModal(); return; }
    if (e.key !== "Tab") return;
    const m = $("#tfModal .modal"); if (!m) return;
    const f = focusables(m); if (!f.length) return;
    const first = f[0], last = f[f.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  }
  function closeModal() {
    const m = $("#tfModal"); if (m) m.remove();
    document.removeEventListener("keydown", onModalKey);
    const main = $("main"); if (main) main.removeAttribute("aria-hidden");
    if (_modalReturnFocus && _modalReturnFocus.focus) { try { _modalReturnFocus.focus(); } catch (e) { /* gone */ } }
    _modalReturnFocus = null;
  }
  function openModal(title, bodyNode, opts) {
    closeModal();
    _modalReturnFocus = document.activeElement;
    const titleId = "tfModalTitle";
    const backdrop = el("div", { class: "modal-backdrop", id: "tfModal", onclick: (e) => { if (e.target === backdrop) closeModal(); } });
    const closeBtn = el("button", { class: "icon-btn close", onclick: closeModal, title: "Close (Esc)", "aria-label": "Close dialog", html: "&times;" });
    const header = el("header", null, [el("h3", { id: titleId, text: title }), closeBtn]);
    const modal = el("div", { class: "modal" + (opts && opts.wide ? " wide" : ""), role: "dialog", "aria-modal": "true", "aria-labelledby": titleId },
      [header, el("div", { class: "body" }, bodyNode)]);
    backdrop.append(modal);
    document.body.append(backdrop);
    const main = $("main"); if (main) main.setAttribute("aria-hidden", "true");
    document.addEventListener("keydown", onModalKey);
    closeBtn.focus();
  }

  // ---- theme (shared 'tf-theme' key with the docs landing page) -----------
  function applyTheme(mode) {
    if (mode === "system") document.documentElement.removeAttribute("data-theme");
    else document.documentElement.setAttribute("data-theme", mode);
  }
  function currentTheme() { return localStorage.getItem("tf-theme") || "system"; }
  function initTheme() { applyTheme(currentTheme()); }
  function cycleTheme() {
    const order = ["light", "dark", "system"];
    const next = order[(order.indexOf(currentTheme()) + 1) % order.length];
    localStorage.setItem("tf-theme", next); applyTheme(next); updateThemeBtn();
    toast("Theme: " + next);
  }
  function updateThemeBtn() {
    const b = $("#themeToggle"); if (!b) return;
    const m = currentTheme();
    b.innerHTML = m === "light" ? "&#9728;" : m === "dark" ? "&#9789;" : "&#9681;";
    b.title = "Theme: " + m + " (click to change)";
    b.setAttribute("aria-label", "Colour theme: " + m + ", click to change");
  }

  // ---- Graphviz (DOT -> SVG), lazily loaded -------------------------------
  let _gv = null, _gvPromise = null;
  const GRAPHVIZ_URL = "https://cdn.jsdelivr.net/npm/@hpcc-js/wasm-graphviz@1.22.2/dist/index.js";
  async function graphviz() {
    if (_gv) return _gv;
    if (!_gvPromise) _gvPromise = (async () => {
      const mod = await import(GRAPHVIZ_URL);
      const G = mod.Graphviz || (mod.default && mod.default.Graphviz);
      _gv = await G.load();
      return _gv;
    })();
    return _gvPromise;
  }
  async function renderDot(dot) {
    const gv = await graphviz();
    // Instance exposes .dot(src) in @hpcc-js/wasm-graphviz; fall back to .layout.
    const svg = typeof gv.dot === "function" ? gv.dot(dot) : gv.layout(dot, "svg", "dot");
    return svg;
  }
  // The causal DAG is emitted as dagitty syntax (`dag { a -> b }`); wrap it as a
  // digraph purely for rendering. The exported IR keeps the dagitty form.
  function dagToDigraph(ir) {
    return ir.replace(/^\s*dag\s*\{/, "digraph causal_dag {\n  rankdir=LR;\n  node [shape=box, style=rounded];");
  }

  // ---- result shaping: raw package output -> display sections -------------
  // R's jsonlite auto_unbox collapses length-1 vectors to scalars; coerce any
  // field that must be an array back to one so both runtimes shape identically.
  const asArr = (v) => (Array.isArray(v) ? v : v == null ? [] : [v]);
  const num = (x) => (typeof x === "number" ? (Number.isInteger(x) ? String(x) : x.toFixed(3).replace(/\.?0+$/, "")) : String(x));
  function pill(s) { return el("span", { class: "pill " + String(s).replace(/[^a-z_]/gi, "_"), text: s }); }

  function colClass(c) {
    return ["cell", c.num ? "num" : "", c.grow ? "grow" : ""].filter(Boolean).join(" ");
  }
  function tableSection(title, columns, rows, opts) {
    const thead = el("thead", null, el("tr", null,
      columns.map((c) => el("th", { class: colClass(c), scope: "col", text: c.label || c }))));
    const tbody = el("tbody", null, rows.map((r) =>
      el("tr", null, columns.map((c) => {
        const key = c.key || c;
        const v = r[key];
        if (c.pill) return el("td", { class: colClass(c) }, pill(v));
        return el("td", { class: colClass(c) }, c.num ? num(v) : (Array.isArray(v) ? v.join(", ") : (v === "" || v == null ? "—" : String(v))));
      }))));
    const table = el("div", { class: "tablewrap" }, el("table", { class: "grid" }, [thead, tbody]));
    return { kind: "node", node: wrapSection(title, opts && opts.extra, table) };
  }
  function kvSection(title, items) {
    const tbody = el("tbody", null, items.map(([k, v]) =>
      el("tr", null, [
        el("td", { class: "cell kvk", text: k }),
        el("td", { class: "cell grow" }, v && v.nodeType ? v : document.createTextNode(String(v))),
      ])));
    return { kind: "node", node: wrapSection(title, null, el("div", { class: "tablewrap" }, el("table", { class: "grid kv" }, tbody))) };
  }
  function wrapSection(title, extraControls, body) {
    const head = el("div", { class: "sh" }, [el("span", { text: title || "" }), el("span", { class: "grow" })]);
    if (extraControls) for (const c of extraControls) head.append(c);
    return el("div", { class: "section" }, [head, body]);
  }

  function figureSection(title, svgString, baseName) {
    const fig = el("div", { class: "figure", role: "img", "aria-label": title, html: svgString });
    const svgEl = fig.querySelector("svg");
    const btnSvg = el("button", { class: "btn ghost sm", onclick: () => download(baseName + ".svg", svgString, "image/svg+xml") }, "SVG");
    const btnPng = el("button", { class: "btn ghost sm", onclick: () => exportPng(svgEl, baseName) }, "PNG");
    return { kind: "node", node: wrapSection(title, [btnSvg, btnPng], fig) };
  }
  function jsonBtn(filename, obj) {
    return el("button", { class: "btn ghost sm", onclick: () => download(filename, JSON.stringify(obj, null, 2), "application/json") }, "JSON");
  }
  function textSection(title, content, downloadName, mime) {
    const pre = el("pre", { class: "text", text: content });
    const ctrls = [
      el("button", { class: "btn ghost sm", onclick: () => copyText(content) }, "Copy"),
      el("button", { class: "btn ghost sm", onclick: () => download(downloadName, content, mime) }, "Download"),
    ];
    return { kind: "node", node: wrapSection(title, ctrls, el("div", { class: "codewrap" }, pre)) };
  }

  async function exportPng(svgEl, baseName) {
    try {
      const clone = svgEl.cloneNode(true);
      let w = 0, h = 0;
      const vb = (clone.getAttribute("viewBox") || "").split(/[ ,]+/).map(Number);
      if (vb.length === 4) { w = vb[2]; h = vb[3]; }
      w = parseFloat(clone.getAttribute("width")) || w || svgEl.clientWidth || 0;
      h = parseFloat(clone.getAttribute("height")) || h || svgEl.clientHeight || 0;
      if (!w || !h) { try { const bb = svgEl.getBBox(); w = w || Math.ceil(bb.width); h = h || Math.ceil(bb.height); } catch (e) { /* not laid out */ } }
      if (!w || !h) { w = w || 600; h = h || 400; toast("PNG size could not be determined; used " + w + "×" + h); }
      clone.setAttribute("width", w); clone.setAttribute("height", h);
      const data = new XMLSerializer().serializeToString(clone);
      const img = new Image();
      const svgUrl = URL.createObjectURL(new Blob([data], { type: "image/svg+xml;charset=utf-8" }));
      await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = svgUrl; });
      const scale = 2;
      const canvas = el("canvas"); canvas.width = Math.ceil(w * scale); canvas.height = Math.ceil(h * scale);
      const ctx = canvas.getContext("2d");
      ctx.fillStyle = FIG.paper; ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.setTransform(scale, 0, 0, scale, 0, 0);
      ctx.drawImage(img, 0, 0, w, h);
      URL.revokeObjectURL(svgUrl);
      canvas.toBlob((blob) => { if (blob) download(baseName + ".png", blob, "image/png"); else toast("PNG export failed"); }, "image/png");
    } catch (e) { toast("PNG export failed"); console.error(e); }
  }

  // Group state indices whose trajectories are numerically identical across every
  // step. Symmetric networks collapse several constructs onto one curve, so the
  // chart and the interpretation both need to know which series coincide.
  function coincidenceGroups(states, trajectory) {
    const sig = (s) => trajectory.map((row) => row[s]).join(",");
    const seen = new Map();
    for (let s = 0; s < states.length; s++) {
      const k = sig(s);
      if (!seen.has(k)) seen.set(k, []);
      seen.get(k).push(s);
    }
    return [...seen.values()];
  }

  // trajectory line chart (SVG) for simulate. Each construct has its own colour
  // and dash pattern; coincident constructs are nudged apart by a couple of
  // pixels (disclosed in the interpretation) so every series stays visible while
  // the table below keeps the exact values.
  const TRAJ_COLOURS = ["#2fa392", "#d98a14", "#4e79a7", "#b5446e", "#6a8f3a", "#8a5fc0", "#c0563a"];
  const TRAJ_DASHES = ["", "5 3", "1 3", "7 3 1 3", "3 3", "9 4", "2 2"];
  function trajectoryChart(states, trajectory) {
    const n = trajectory.length, m = states.length;
    const shown = states.map((s) => { s = String(s); return s.length > 30 ? s.slice(0, 29) + "…" : s; });
    const maxLabel = shown.reduce((a, s) => Math.max(a, s.length), 0);
    const padR = Math.min(244, Math.max(96, 36 + Math.ceil(maxLabel * 6.6)));
    const pad = { l: 48, r: padR, t: 16, b: 30 };
    const W = pad.l + 380 + pad.r, H = Math.max(300, pad.t + pad.b + m * 18 + 8);
    // Scale to the finite extremes only. A positive-feedback theory can overflow
    // the Euler integrator to Infinity/NaN under the parameters the UI allows;
    // those samples must not poison the range or the path.
    let lo = Infinity, hi = -Infinity;
    for (const row of trajectory) for (const v of row) { if (Number.isFinite(v)) { if (v < lo) lo = v; if (v > hi) hi = v; } }
    if (!isFinite(lo) || !isFinite(hi)) { lo = 0; hi = 1; }
    if (hi - lo < 1e-9) { hi += 1; lo -= 1; }
    const x = (i) => pad.l + (i / Math.max(1, n - 1)) * (W - pad.l - pad.r);
    const y = (v) => pad.t + (1 - (v - lo) / (hi - lo)) * (H - pad.t - pad.b);
    // small symmetric offset within each coincident group so the lines separate
    const offset = new Array(m).fill(0);
    for (const g of coincidenceGroups(states, trajectory)) {
      if (g.length > 1) g.forEach((s, k) => (offset[s] = (k - (g.length - 1) / 2) * 2.4));
    }
    const parts = [`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" font-family="system-ui,sans-serif" font-size="12">`];
    parts.push(`<rect x="0" y="0" width="${W}" height="${H}" fill="${FIG.paper}"/>`);
    // horizontal gridlines with value labels (five levels)
    for (let t = 0; t <= 4; t++) {
      const val = lo + (hi - lo) * (t / 4), yy = y(val);
      parts.push(`<line x1="${pad.l}" y1="${yy.toFixed(1)}" x2="${(W - pad.r).toFixed(1)}" y2="${yy.toFixed(1)}" stroke="${FIG.axis}" stroke-opacity="0.5"/>`);
      parts.push(`<text x="${pad.l - 6}" y="${(yy + 3.5).toFixed(1)}" text-anchor="end" fill="${FIG.muted}">${val.toFixed(2)}</text>`);
    }
    // axes
    parts.push(`<line x1="${pad.l}" y1="${pad.t}" x2="${pad.l}" y2="${H - pad.b}" stroke="${FIG.axis}"/>`);
    parts.push(`<line x1="${pad.l}" y1="${H - pad.b}" x2="${W - pad.r}" y2="${H - pad.b}" stroke="${FIG.axis}"/>`);
    // x labels: first, middle, last step
    const xt = n > 1 ? [[0, "start"], [Math.round((n - 1) / 2), "middle"], [n - 1, "end"]] : [[0, "start"]];
    for (const [i, anchor] of xt) parts.push(`<text x="${x(i).toFixed(1)}" y="${H - 10}" text-anchor="${anchor}" fill="${FIG.muted}">step ${i}</text>`);
    for (let s = 0; s < m; s++) {
      const col = TRAJ_COLOURS[s % TRAJ_COLOURS.length], dash = TRAJ_DASHES[s % TRAJ_DASHES.length], off = offset[s];
      const da = dash ? ` stroke-dasharray="${dash}"` : "";
      let d = "", pen = false;
      for (let i = 0; i < n; i++) {
        const v = trajectory[i][s];
        if (!Number.isFinite(v)) { pen = false; continue; }   // break the line across non-finite samples
        d += (pen ? "L" : "M") + x(i).toFixed(1) + " " + (y(v) + off).toFixed(1) + " ";
        pen = true;
      }
      parts.push(`<path d="${d.trim()}" fill="none" stroke="${col}" stroke-width="2"${da} stroke-linejoin="round"/>`);
      const ly = pad.t + 10 + s * 18, lx = W - pad.r + 8;
      parts.push(`<line x1="${lx}" y1="${ly - 4}" x2="${lx + 22}" y2="${ly - 4}" stroke="${col}" stroke-width="2.5"${da}/>`);
      parts.push(`<text x="${lx + 28}" y="${ly}" fill="${FIG.ink}">${esc(shown[s])}</text>`);
    }
    parts.push("</svg>");
    return parts.join("\n");
  }

  // General "how to read" guidance shown at the top of each operation's result.
  // It complements the sidebar help (what the operation does) by explaining how
  // to read the output that follows.
  const RESULT_GUIDE = {
    check: "The checklist scores twelve facets of rigour and combines them into an overall score and a gate. Read the gate first. Pass means the theory is ready to test, advisory means it is usable with the noted gaps, and blocked means a must-fix criterion is unmet. The grid below shows each item's status.",
    validate: "Validation reports structural and referential problems: missing required fields, values outside the allowed set, duplicate identifiers and cross-references that point to nothing. A valid theory is the precondition for every other operation.",
    diagram: "The diagram is rendered from the package's intermediate representation, shown below the figure. Export the figure as SVG or PNG, or copy the representation to render it elsewhere.",
    severity: "Severity grades each prediction by how much a passing test would corroborate the theory. The risk score reflects how committal the claim is. The computed severity adjusts it down for merely directional claims and up for claims that discriminate between rival theories. Longer bars are stronger tests.",
    redundancy: "Each pair of constructs is compared by the word overlap of their definitions, the Jaccard index, which runs from 0 to 1. Pairs above the threshold are flagged for review, because near-duplicate constructs blur a theory and inflate its apparent scope.",
    appraise: "Following Lakatos, an amendment is progressive when it adds independently testable content that survives testing, and degenerating when it mainly adds assumptions that shield the theory from refutation. The verdict and its components appear below.",
    sem: "The constructs become a measurement model and the propositions a structural model, expressed in lavaan syntax. Paste it into an SEM fit in R or other lavaan-compatible software.",
    preregister: "The preregistration lists each hypothesis with its derivation and severity, in file order, ready to timestamp before data collection.",
    dossier: "The dossier gathers the rigour report, severity, provenance and preregistration into one reviewer-facing document.",
    simulate: "Each construct is read as a quantity that changes over time. A directed proposition pushes one construct up (increases, causes, mediates) or down (decreases) in proportion to another, and every construct decays towards zero at the damping rate. The chart traces the values from the initial state. The table below holds the exact numbers.",
    litmap: "The bundled corpus is mapped three ways: which keywords co-occur, which keywords cluster into themes and which references are cited together. The min_link setting controls how many shared records a pair needs to count as linked.",
    landscape: "The theory and its rivals are placed against the corpus themes. Under-theorised fronts are themes no theory addresses. Redundancy risk marks crowded themes where a new theory would add little.",
  };
  const fmtNum = (x) => (typeof x === "number" ? (Number.isInteger(x) ? String(x) : x.toFixed(2)) : String(x));
  const plural = (n, w) => n + " " + w + (n === 1 ? "" : "s");

  // A result-specific sentence that reads the actual output, to help interpret it.
  function interpret(opId, raw, params) {
    const S = STATE.summary || {}, c = S.counts || {};
    if (opId === "check") {
      const r = raw.report, items = asArr(r.items);
      const by = (st) => items.filter((i) => i.status === st).length;
      const gate = { pass: "passes the gate", advisory: "clears the gate with advisories", blocked: "is blocked" }[r.gate] || ("gate " + r.gate);
      const blockers = r.n_blockers_failed > 0 ? ", with " + plural(r.n_blockers_failed, "blocking item") + " unmet." : ", and no blocking item is unmet.";
      return "This theory scores " + fmtNum(r.aggregate_score) + " out of 100 and " + gate + ". Of " + items.length + " items, " + by("pass") + " pass, " + by("warn") + " warn and " + by("fail") + " fail" + blockers;
    }
    if (opId === "validate") {
      if (raw.ok) return "The theory is structurally valid and every internal reference resolves.";
      const errs = String(raw.message || "").replace(/^invalid theory object:\s*/i, "").split(/;\s*/).filter(Boolean);
      return "Validation found " + plural(errs.length, "problem") + ". Each one is listed below.";
    }
    if (opId === "severity") {
      const rows = asArr(raw.rows);
      if (!rows.length) return "This theory has no predictions to grade.";
      const sev = rows.map((r) => Number(r.computed_severity));
      const top = rows[sev.indexOf(Math.max(...sev))];
      const mean = sev.reduce((a, b) => a + b, 0) / sev.length;
      return "Across " + plural(rows.length, "prediction") + ", computed severity runs from " + Math.min(...sev).toFixed(2) + " to " + Math.max(...sev).toFixed(2) + " (mean " + mean.toFixed(2) + "). The strongest test is " + top.prediction_id + ".";
    }
    if (opId === "redundancy") {
      const rows = asArr(raw.rows);
      if (!rows.length) return "There are fewer than two constructs, so there are no pairs to compare.";
      const flagged = rows.filter((r) => String(r.flag) === "review").length;
      const top = rows[0];
      const lead = flagged ? plural(flagged, "pair") + " of " + rows.length + " exceed the threshold and are flagged for review." : "No pair exceeds the threshold.";
      return lead + " The most similar pair is " + top.a + " and " + top.b + " (Jaccard " + fmtNum(top.similarity) + ").";
    }
    if (opId === "appraise") {
      const r = raw, np = asArr(r.new_predictions).length, cn = asArr(r.corroborated_new).length, ah = asArr(r.ad_hoc_assumptions).length;
      return "The amendment is " + r.verdict + ". It introduces " + plural(np, "new prediction") + ", of which " + cn + (cn === 1 ? " is" : " are") + " corroborated, and " + plural(ah, "ad-hoc assumption") + ".";
    }
    if (opId === "sem") return "The measurement model covers " + plural(c.constructs || 0, "construct") + " and the structural model " + plural(c.propositions || 0, "proposition") + ".";
    if (opId === "preregister") { const k = c.predictions || 0; return "The document preregisters " + k + (k === 1 ? " hypothesis." : " hypotheses."); }
    if (opId === "dossier") return "The dossier bundles the rigour report, severity, provenance and preregistration for " + (S.title || S.id || "this theory") + ".";
    if (opId === "diagram") {
      const t = String(params.type || "");
      const name = t.replace(/_/g, " ");
      const byType = {
        rigour: "A status grid of the twelve rigour checklist items and the overall gate.",
        severity: "Severity bars for the theory's " + plural(c.predictions || 0, "prediction") + ".",
        venn: "Overlap of the boundary conditions declared on the theory's constructs (up to three).",
        provenance: "The recorded build steps in order.",
        pipeline: "Each prediction linked to its recorded test outcome.",
        development_roadmap: "The checklist items not yet passing.",
      };
      return byType[t] || ("A " + name + " diagram built from " + plural(c.constructs || 0, "construct") + " and " + plural(c.propositions || 0, "proposition") + ".");
    }
    if (opId === "simulate") {
      const r = raw.result, states = asArr(r.states), traj = asArr(r.trajectory).map(asArr);
      let lo = Infinity, hi = -Infinity, diverged = false;
      for (const row of traj) for (const v of row) { if (Number.isFinite(v)) { if (v < lo) lo = v; if (v > hi) hi = v; } else diverged = true; }
      if (!isFinite(lo) || !isFinite(hi)) { lo = 0; hi = 0; }
      if (diverged) return "The simulation diverged. Some values grew beyond what can be plotted. Lower dt, k or the number of steps to keep it bounded.";
      const coincide = coincidenceGroups(states, traj).filter((g) => g.length > 1);
      let txt = "The " + plural(states.length, "construct") + " evolve over " + plural(r.steps, "step") + ", with values from " + lo.toFixed(2) + " to " + hi.toFixed(2) + ".";
      if (coincide.length) {
        const lists = coincide.map((g) => g.map((i) => states[i]).join(", ")).join("; ");
        txt += " Some constructs follow an identical path (" + lists + "), so their lines are drawn with a small offset to keep each visible. Give them different couplings, for example a “decreases” relation, to separate the trajectories.";
      } else {
        txt += " The trajectories are distinct.";
      }
      return txt;
    }
    if (opId === "litmap") {
      const r = raw.result;
      return "The corpus holds " + plural(r.n_records, "record") + ", " + plural(asArr(r.keywords).length, "distinct keyword") + " and " + plural(asArr(r.themes).length, "theme") + ", with " + plural(asArr(r.co_citation).length, "co-citation pair") + ".";
    }
    if (opId === "landscape") {
      const r = raw.result;
      return plural(asArr(r.themes).length, "theme") + " mapped. " + plural(asArr(r.under_theorised_fronts).length, "front") + " under-theorised, " + plural(asArr(r.redundancy_risk).length, "theme") + " at redundancy risk.";
    }
    return "";
  }

  // The diagram guide depends on the chosen type: the venn, rigour and severity
  // types are emitted directly as SVG, so there is no intermediate representation
  // shown beneath the figure to copy.
  function aboutText(opId, params) {
    if (opId === "diagram") {
      return DIAG_SVG.includes(params.type)
        ? "This diagram type is emitted directly as an SVG figure. Export it as SVG or PNG."
        : RESULT_GUIDE.diagram;
    }
    return RESULT_GUIDE[opId] || "";
  }

  function buildIntro(opId, raw, params) {
    const about = aboutText(opId, params);
    let interp = "";
    try { interp = interpret(opId, raw, params) || ""; } catch (e) { interp = ""; }
    const kids = [];
    if (about) kids.push(el("p", { class: "ri-about", text: about }));
    if (interp) kids.push(el("p", { class: "ri-interp", text: interp }));
    if (!kids.length) return null;
    return { kind: "node", node: el("div", { class: "result-intro" }, kids) };
  }

  async function shapeResult(opId, raw, params, theoryId) {
    const sections = [];
    const base = (theoryId || "theory") + "." + opId;
    if (opId === "check") {
      const rep = raw.report;
      sections.push(figureSection("Rigour grid", raw.svg, theoryId + ".rigour"));
      sections.push(kvSection("Summary", [
        ["Aggregate score", rep.aggregate_score + " / 100"],
        ["Gate", pill(rep.gate)],
        ["Blockers failed", String(rep.n_blockers_failed)],
        ["Maturity", rep.maturity],
      ]));
      sections.push(tableSection("Checklist items",
        [{ key: "id", label: "item" }, { key: "status", label: "status", pill: true },
         { key: "score", label: "score", num: true }, { key: "weight", label: "weight", num: true },
         { key: "severity_if_fail", label: "severity if fail", grow: true }],
        asArr(rep.items), { extra: [jsonBtn(theoryId + ".report.json", rep)] }));
    } else if (opId === "validate") {
      const v = raw;
      if (v.ok) {
        sections.push({ kind: "node", node: wrapSection("Validation", null,
          el("div", { class: "valid-ok", role: "status" }, "✓ Valid — the theory passes structural validation.")) });
      } else {
        const errs = String(v.message || "invalid theory object").replace(/^invalid theory object:\s*/i, "").split(/;\s*/).filter(Boolean);
        sections.push({ kind: "node", node: wrapSection("Validation", null,
          el("div", { class: "error", role: "alert" }, [
            el("div", { class: "et", text: "Invalid theory — " + errs.length + " problem" + (errs.length === 1 ? "" : "s") }),
            el("ul", { class: "err-list" }, errs.map((e) => el("li", null, e))),
          ])) });
      }
    } else if (opId === "appraise") {
      const r = raw;
      const priorName = (RT.examples.find((e) => e.path === params.prior) || {}).name || params.prior || "—";
      sections.push(kvSection("Appraisal", [["Verdict", pill(r.verdict)], ["Prior version", priorName]]));
      sections.push(tableSection("Detail",
        [{ key: "k", label: "category" }, { key: "v", label: "ids", grow: true }],
        [
          { k: "New predictions", v: asArr(r.new_predictions).join(", ") || "—" },
          { k: "Corroborated new", v: asArr(r.corroborated_new).join(", ") || "—" },
          { k: "Ad-hoc assumptions", v: asArr(r.ad_hoc_assumptions).join(", ") || "—" },
        ], { extra: [jsonBtn(theoryId + ".appraisal.json", r)] }));
    } else if (opId === "severity") {
      const rows = asArr(raw.rows);
      sections.push(figureSection("Severity chart", raw.svg, theoryId + ".severity"));
      if (rows.length) sections.push(tableSection("Per-prediction severity",
        [{ key: "prediction_id", label: "prediction" }, { key: "type", label: "type" },
         { key: "risk_score", label: "risk", num: true }, { key: "computed_severity", label: "computed severity", num: true }],
        rows, { extra: [jsonBtn(theoryId + ".severity.json", rows)] }));
      else sections.push({ kind: "node", node: wrapSection("Per-prediction severity", null, el("p", { class: "note", text: "This theory has no predictions." })) });
    } else if (opId === "redundancy") {
      const rows = asArr(raw.rows);
      if (rows.length) sections.push(tableSection("Construct pairs (descending similarity)",
        [{ key: "a", label: "construct a" }, { key: "b", label: "construct b" },
         { key: "similarity", label: "Jaccard", num: true }, { key: "flag", label: "flag", pill: true }],
        rows, { extra: [jsonBtn(theoryId + ".redundancy.json", rows)] }));
      else sections.push({ kind: "node", node: wrapSection("Redundancy screen", null, el("p", { class: "note", text: "Fewer than two constructs — no pairs to compare." })) });
    } else if (opId === "diagram") {
      const ir = raw.ir, type = params.type;
      const isSvg = /^\s*<svg/.test(ir);
      let svg;
      if (isSvg) svg = ir;
      else svg = await renderDot(type === "causal_dag" ? dagToDigraph(ir) : ir);
      sections.push(figureSection(type + " diagram", svg, theoryId + "." + type));
      if (!isSvg) sections.push(textSection("Intermediate representation (" + (type === "causal_dag" ? "dagitty" : "Graphviz DOT") + ")", ir, theoryId + "." + type + (type === "causal_dag" ? ".dag" : ".dot"), "text/plain"));
    } else if (opId === "sem") {
      sections.push(textSection("lavaan model syntax", raw.text, theoryId + ".sem.lavaan", "text/plain"));
    } else if (opId === "preregister") {
      sections.push(textSection("Preregistration (Markdown)", raw.text, theoryId + ".prereg.md", "text/markdown"));
    } else if (opId === "dossier") {
      sections.push(textSection("Audit dossier (Markdown)", raw.text, theoryId + ".dossier.md", "text/markdown"));
    } else if (opId === "simulate") {
      const r = raw.result;
      const states = asArr(r.states), traj = asArr(r.trajectory).map(asArr);
      sections.push(figureSection("Trajectory", trajectoryChart(states, traj), theoryId + ".simulate"));
      const cols = [{ key: "_step", label: "step" }].concat(states.map((s, i) => ({ key: "s" + i, label: s, num: true })));
      const rows = traj.map((row, i) => { const o = { _step: i }; row.forEach((v, j) => (o["s" + j] = v)); return o; });
      sections.push(tableSection("State trajectory (steps " + r.steps + ", dt " + r.dt + ")", cols, rows));
    } else if (opId === "litmap") {
      const r = raw.result;
      const themes = asArr(r.themes), kw = asArr(r.keywords), cooc = asArr(r.keyword_cooccurrence), cocite = asArr(r.co_citation);
      sections.push(kvSection("Summary", [
        ["Records", String(r.n_records)], ["Distinct keywords", String(kw.length)],
        ["Themes", String(themes.length)], ["Co-citation pairs", String(cocite.length)],
      ]));
      if (themes.length) sections.push(tableSection("Themes (connected components)",
        [{ key: "id", label: "theme" }, { key: "size", label: "size", num: true }, { key: "keywords", label: "keywords" }],
        themes.map((t) => Object.assign({}, t, { keywords: asArr(t.keywords) }))));
      if (cooc.length) sections.push(figureSection("Keyword co-occurrence", await renderDot(raw.dots.keyword_cooccurrence), theoryId + ".keyword_cooccurrence"));
      if (cocite.length) sections.push(figureSection("Co-citation", await renderDot(raw.dots.co_citation), theoryId + ".co_citation"));
      sections.push(textSection("litmap JSON", JSON.stringify(r, null, 2), theoryId + ".litmap.json", "application/json"));
    } else if (opId === "landscape") {
      const r = raw.result;
      const themes = asArr(r.themes);
      sections.push(tableSection("Themes mapped onto the theory",
        [{ key: "id", label: "theme" }, { key: "status", label: "status", pill: true },
         { key: "focal", label: "focal" }, { key: "keywords", label: "keywords" }, { key: "alternatives", label: "alternatives" }],
        themes.map((t) => Object.assign({}, t, { focal: t.focal ? "yes" : "—", keywords: asArr(t.keywords), alternatives: asArr(t.alternatives) }))));
      sections.push(kvSection("Flags", [
        ["Under-theorised fronts", asArr(r.under_theorised_fronts).join(", ") || "—"],
        ["Redundancy risk", asArr(r.redundancy_risk).join(", ") || "—"],
      ]));
      if (raw.dot) sections.push(figureSection("Theme landscape", await renderDot(raw.dot), theoryId + ".theme_landscape"));
      sections.push(textSection("landscape JSON", JSON.stringify(r, null, 2), theoryId + ".landscape.json", "application/json"));
    }
    const intro = buildIntro(opId, raw, params);
    if (intro) sections.unshift(intro);
    return sections;
  }

  // ---- UI ------------------------------------------------------------------
  let RT, STATE = { opId: "check", params: {}, summary: null, input: null, source: null, ran: false };

  // ---- persistence (restore the session on refresh) -----------------------
  function stateKey() { return "tf-app-" + (RT ? RT.lang : "x"); }
  function saveState() {
    try {
      localStorage.setItem(stateKey(), JSON.stringify({
        opId: STATE.opId, params: STATE.params, input: STATE.input, ran: !!STATE.ran,
      }));
    } catch (e) { /* quota or private mode — non-fatal */ }
  }
  function loadSaved() { try { return JSON.parse(localStorage.getItem(stateKey()) || "null"); } catch (e) { return null; } }
  async function fetchSource(path) {
    const r = await fetch("vendor/" + path);
    if (!r.ok) throw new Error("HTTP " + r.status);
    return r.text();
  }
  // Fetch an example's source, recording a fetch error distinctly from "no source".
  async function exampleSource(name, path) {
    try { return { name, text: await fetchSource(path) }; }
    catch (e) { return { name, text: null, error: (e && e.message) || String(e) }; }
  }

  function openSource() {
    if (!STATE.source) { toast("No theory loaded"); return; }
    if (STATE.source.text == null) {
      toast(STATE.source.error ? "Could not fetch source (" + STATE.source.error + ")" : "No source available for this input");
      return;
    }
    const { name, text } = STATE.source;
    const actions = el("div", { class: "modal-actions" }, [
      el("button", { class: "btn ghost sm", onclick: () => copyText(text) }, "Copy"),
      el("button", { class: "btn ghost sm", onclick: () => download(name, text, "text/plain") }, "Download"),
    ]);
    openModal("Source · " + name, el("div", null, [actions, el("pre", { class: "text", text })]), { wide: true });
  }

  function openHelp() {
    const li = (t) => el("li", null, t);
    const body = el("div", { class: "help" }, [
      el("p", null, "This app runs the real theoryforge " + RT.langLabel + " package entirely in your browser, via " +
        RT.engineLabel + ". Nothing is uploaded to a server, and the results match running the package locally."),
      el("h4", null, "How to use"),
      el("ol", { class: "steps" }, [
        li("Pick an example theory, or upload your own YAML / JSON. Use “View source” to inspect the input."),
        li("Choose an operation, then adjust any parameters."),
        li("Press Run. Results appear on the right; every figure sits on a white panel."),
        li("Export the visualisation (SVG / PNG) and the " + RT.langLabel + " code that reproduces it."),
      ]),
      el("p", { class: "note" }, "Your theory, operation and last result are remembered, so a page refresh restores the session."),
      el("h4", null, "Operations"),
      el("ul", { class: "help-ops" }, OPS.map((op) =>
        el("li", null, [el("b", null, op.label), document.createTextNode(" — " + (op.help || op.desc))]))),
      el("p", { class: "note" }, "The literature operations use a bundled demonstration corpus."),
      el("p", { class: "note" }, "The package's network and credentialed adapters are intentionally not offered here. " +
        "The OpenAlex corpus fetch, the embedding-based redundancy screen and the OSF deposit each need a live connection, " +
        "an embedding model or credentials, so they belong in the desktop package."),
    ]);
    openModal("How to use this app", body, { wide: true });
  }

  function updateExampleDesc() {
    const e2 = $("#exDesc"); if (!e2) return;
    let txt = "";
    if (STATE.input && STATE.input.mode === "upload") txt = "Your uploaded theory.";
    else if (STATE.input && STATE.input.mode === "example") {
      const ex = RT.examples[STATE.input.index]; txt = (ex && ex.desc) || "";
    }
    e2.textContent = txt; e2.style.display = txt ? "" : "none";
  }
  function updateOpHelp() {
    const e2 = $("#opHelp"); if (!e2) return;
    const op = OPS.find((o) => o.id === STATE.opId);
    e2.textContent = op ? (op.help || op.desc) : "";
  }

  function buildHeader() {
    const toggle = el("button", { class: "icon-btn", id: "themeToggle", onclick: cycleTheme, title: "Theme", "aria-label": "Toggle colour theme" });
    const help = el("button", { class: "help-cta", id: "helpBtn", onclick: openHelp, title: "How to use this app", "aria-label": "How to use this app" },
      [el("span", { class: "hq", "aria-hidden": "true" }, "?"), el("span", { class: "ht" }, "How to use")]);
    return el("header", { class: "app" }, [
      logoImg(),
      el("div", { class: "titles" }, [
        el("h1", { class: "t", text: "theoryforge" }),
        el("span", { class: "s", text: "Interactive app · runs the " + RT.langLabel + " package in your browser" }),
      ]),
      el("span", { class: "badge", text: RT.langLabel }),
      el("span", { class: "grow" }),
      el("nav", { class: "navlinks", "aria-label": "External links" }, [
        el("a", { class: "doclink", href: RT.docsUrl, target: "_blank", rel: "noopener" }, "Docs ↗"),
        el("a", { class: "doclink", href: "https://github.com/pablobernabeu/theoryforge", target: "_blank", rel: "noopener" }, "GitHub ↗"),
      ]),
      help, toggle,
    ]);
  }

  function summaryCard(s) {
    if (!s) return el("p", { class: "note", text: "No theory loaded." });
    const c = s.counts || {};
    const chip = (label, n) => el("span", { class: "chip", html: "<b>" + n + "</b> " + label });
    return el("div", { class: "summary" }, [
      el("div", { class: "ttl", text: s.title || s.id || "(untitled)" }),
      el("div", { class: "meta" }, [s.id || "", s.maturity ? " · " + s.maturity : "", s.form ? " · " + s.form : ""].join("")),
      el("div", { class: "chips" }, [
        chip("constructs", c.constructs || 0), chip("propositions", c.propositions || 0),
        chip("predictions", c.predictions || 0), chip("alternatives", c.alternatives || 0),
        chip("assumptions", c.assumptions || 0),
      ]),
    ]);
  }

  function buildSidebar() {
    const exSelect = el("select", { id: "exampleSel", onchange: onExampleChange },
      RT.examples.map((e, i) => el("option", { value: i }, e.name)));
    const fileInput = el("input", { type: "file", id: "fileInput", accept: ".yaml,.yml,.json", onchange: onFileChange });
    const summaryWrap = el("div", { id: "summaryWrap" }, summaryCard(STATE.summary));

    const opGrid = el("div", { class: "ops", id: "opGrid", role: "group", "aria-label": "Operation" }, OPS.map((op) =>
      el("button", {
        class: "op" + (op.id === STATE.opId ? " active" : ""), "data-op": op.id,
        onclick: () => selectOp(op.id), "aria-pressed": op.id === STATE.opId ? "true" : "false",
        disabled: op.corpus && !RT.hasCorpus() ? "" : null,
        title: op.corpus && !RT.hasCorpus() ? "Needs a corpus" : op.desc,
      }, [el("span", { class: "on", text: op.label }), el("span", { class: "od", text: op.desc })])));

    const paramsWrap = el("div", { class: "params", id: "paramsWrap" });
    const runBtn = el("button", { class: "btn", id: "runBtn", onclick: runOp }, "Run ▸");

    const viewSrc = el("button", { class: "btn ghost sm", id: "viewSrc", onclick: openSource }, "View source ⤢");

    return el("div", { class: "sidebar" }, [
      el("div", { class: "panel" }, [
        el("h2", null, "Theory"),
        el("label", { class: "field" }, [el("span", null, "Example theory"), exSelect]),
        el("p", { class: "exdesc", id: "exDesc" }, ""),
        el("label", { class: "field" }, [el("span", null, "…or upload your own (YAML / JSON)"), el("div", { class: "filewrap" }, fileInput)]),
        summaryWrap,
        el("div", { class: "srcrow" }, viewSrc),
      ]),
      el("div", { class: "panel" }, [
        el("h2", null, "Operation"),
        opGrid,
        el("p", { class: "ophelp", id: "opHelp" }, ""),
        paramsWrap,
        el("div", { style: "margin-top:14px" }, runBtn),
      ]),
    ]);
  }

  // First-run welcome: the rationale for the package and a short set of steps,
  // shown until the first operation is run.
  function welcomeBlock() {
    const li = (t) => el("li", null, t);
    return el("div", { class: "welcome" }, [
      el("h3", null, "Develop a theory you can test"),
      el("p", null, "Theories often drift into vague constructs, claims that cannot be falsified, near-duplicate ideas and amendments that quietly weaken them. theoryforge takes a theory written as structured data and helps you keep it honest. It scores the theory against a rigour checklist, screens its constructs for redundancy, draws its structure, compiles it to a statistical model, simulates its dynamics and appraises whether an amendment strengthens or weakens it."),
      el("ol", { class: "welcome-steps" }, [
        li("Pick an example theory on the left, or upload your own YAML or JSON. Use “View source” to inspect the input."),
        li("Choose an operation and adjust any parameters."),
        li(["Press ", el("b", null, "Run"), ". Each result is explained here and can be exported as a figure and as " + RT.langLabel + " code."]),
      ]),
      el("p", { class: "note" }, ["For what each operation does, open ",
        el("button", { class: "linklike", onclick: openHelp }, "the guide"), "."]),
    ]);
  }

  function buildMain() {
    return el("div", null, [
      el("div", { class: "panel" }, [
        el("div", { class: "outhead" }, [el("h2", { id: "outTitle" }, "Result"), el("span", { class: "grow" })]),
        el("div", { id: "output", "aria-live": "polite", "aria-atomic": "false" }, welcomeBlock()),
      ]),
      el("div", { class: "panel", id: "codePanel", style: "display:none" }, [
        el("div", { class: "outhead" }, [
          el("h2", null, "Reproducible " + RT.langLabel + " code"),
          el("span", { class: "grow" }),
          el("button", { class: "btn ghost sm", id: "copyCode", onclick: () => copyText($("#codeBlock").textContent) }, "Copy"),
          el("button", { class: "btn ghost sm", id: "dlCode", onclick: () => download("theoryforge_reproduce." + (RT.lang === "r" ? "R" : "py"), $("#codeBlock").textContent, "text/plain") }, "Download"),
        ]),
        el("p", { class: "note", style: "margin-top:0", text: "Paste into " + RT.langLabel + " to reproduce exactly what the app computed." }),
        el("pre", { class: "code" }, el("code", { id: "codeBlock" }, "")),
      ]),
    ]);
  }

  function renderParams() {
    const wrap = $("#paramsWrap"); wrap.innerHTML = "";
    const op = OPS.find((o) => o.id === STATE.opId);
    if (!op || !op.params) return;
    const rows = el("div", { class: "row" });
    let inRow = false;
    for (const p of op.params) {
      let input;
      if (p.type === "select") {
        if (!p.options.includes(STATE.params[p.id])) STATE.params[p.id] = p.default;  // drop stale persisted value
        input = el("select", { onchange: (e) => { STATE.params[p.id] = e.target.value; saveState(); } },
          p.options.map((o) => el("option", { value: o, selected: o === STATE.params[p.id] ? "" : null }, o)));
      } else if (p.type === "theory") {
        const opts = RT.examples.map((e) => ({ value: e.path, label: e.name }));
        if (!opts.some((o) => o.value === STATE.params[p.id])) STATE.params[p.id] = opts.length ? opts[0].value : null;
        input = el("select", { onchange: (e) => { STATE.params[p.id] = e.target.value; saveState(); } },
          opts.map((o) => el("option", { value: o.value, selected: o.value === STATE.params[p.id] ? "" : null }, o.label)));
      } else {
        STATE.params[p.id] = clampNum(STATE.params[p.id] === undefined ? "" : STATE.params[p.id], p);  // clamp persisted value
        input = el("input", {
          type: "number", value: STATE.params[p.id], min: p.min, max: p.max, step: p.step,
          oninput: (e) => { STATE.params[p.id] = clampNum(e.target.value, p); saveState(); },
        });
      }
      const field = el("label", { class: "field", style: "margin:0" }, [el("span", null, p.label), input]);
      if (op.params.length > 1 && p.type === "number") { rows.append(field); inRow = true; }
      else wrap.append(field);
    }
    if (inRow) wrap.append(rows);
  }
  function clampNum(raw, p) {
    let n = raw === "" ? p.default : Number(raw);
    if (!Number.isFinite(n)) n = p.default;
    if (typeof p.min === "number") n = Math.max(p.min, n);
    if (typeof p.max === "number") n = Math.min(p.max, n);
    return n;
  }

  function selectOp(id) {
    STATE.opId = id;
    for (const b of document.querySelectorAll(".op")) {
      const on = b.getAttribute("data-op") === id;
      b.classList.toggle("active", on);
      b.setAttribute("aria-pressed", on ? "true" : "false");
    }
    updateOpHelp(); renderParams(); saveState();
  }

  async function onExampleChange(e) {
    const idx = Number(e.target.value);
    const ex = RT.examples[idx];
    await withBusy("Loading " + ex.name + "…", async () => {
      STATE.summary = await RT.loadExample(ex.path);
      STATE.input = { mode: "example", index: idx };
      STATE.source = await exampleSource(ex.path.split("/").pop(), ex.path);
      $("#summaryWrap").replaceChildren(summaryCard(STATE.summary));
      $("#fileInput").value = "";
      updateExampleDesc(); saveState();
    });
  }
  async function onFileChange(e) {
    const f = e.target.files && e.target.files[0]; if (!f) return;
    const text = await f.text();
    await withBusy("Loading " + f.name + "…", async () => {
      try {
        STATE.summary = await RT.loadTheoryText(text, f.name);
        STATE.input = { mode: "upload", name: f.name, text };
        STATE.source = { name: f.name, text };
        $("#summaryWrap").replaceChildren(summaryCard(STATE.summary));
        updateExampleDesc(); saveState();
      } catch (err) {
        $("#summaryWrap").replaceChildren(errorBox("Could not load this file", err));
      }
    });
  }

  function errorBox(title, err) {
    const msg = (err && (err.message || err.toString())) || String(err);
    return el("div", { class: "error", role: "alert" }, [el("div", { class: "et", text: title }), el("div", { text: msg })]);
  }

  let busy = false;
  async function withBusy(label, fn) {
    if (busy) return; busy = true;
    const btn = $("#runBtn"); const prev = btn ? btn.textContent : "";
    // Lock all theory/operation controls so the UI cannot desync mid-flight.
    const controls = [...document.querySelectorAll("#exampleSel, #fileInput, #viewSrc, #runBtn, .op")];
    for (const c of controls) { c.setAttribute("data-busywas", c.disabled ? "1" : "0"); c.disabled = true; }
    if (btn && label) btn.textContent = label;
    try { await fn(); } finally {
      busy = false;
      for (const c of controls) { if (c.getAttribute("data-busywas") === "0") c.disabled = false; c.removeAttribute("data-busywas"); }
      if (btn) btn.textContent = prev;
    }
  }

  async function runOp() {
    const op = OPS.find((o) => o.id === STATE.opId);
    if (!STATE.summary) { toast("Load a theory first"); return; }
    if (op.corpus && !RT.hasCorpus()) { toast("This operation needs a corpus"); return; }
    const out = $("#output");
    await withBusy("Running…", async () => {
      out.replaceChildren(el("p", { class: "note", text: "Running " + op.label + "…" }));
      $("#outTitle").textContent = op.label;
      try {
        const params = Object.assign({}, STATE.params);
        const { raw, code } = await RT.run(op.id, params);
        const sections = await shapeResult(op.id, raw, params, STATE.summary.id || "theory");
        out.replaceChildren(...sections.map((s) => s.node));
        const cp = $("#codePanel"); cp.style.display = "";
        $("#codeBlock").textContent = code;
        STATE.ran = true; saveState();
      } catch (err) {
        out.replaceChildren(errorBox("Operation failed", err));
        console.error(err);
      }
    });
  }

  // ---- boot ---------------------------------------------------------------
  function bootOverlay() {
    return el("div", { id: "boot" }, [
      logoImg(),
      el("div", { class: "bt", text: "Starting " + RT.langLabel + " in your browser" }),
      el("div", { class: "spinner" }),
      el("div", { class: "blog", id: "blog", text: "Loading runtime…" }),
    ]);
  }

  // Restore theory + operation + params from a previous session, then optionally
  // re-run the last operation so a refresh lands back where the user left off.
  async function applyRestore(blog) {
    const saved = loadSaved();
    STATE.input = STATE.input || { mode: "example", index: 0 };
    if (saved) {
      if (saved.input && saved.input.mode === "upload" && saved.input.text) {
        try {
          if (blog) blog("Restoring your uploaded theory…");
          STATE.summary = await RT.loadTheoryText(saved.input.text, saved.input.name);
          STATE.input = saved.input;
          STATE.source = { name: saved.input.name, text: saved.input.text };
        } catch (e) { STATE.input = { mode: "example", index: 0 }; }
      } else if (saved.input && saved.input.mode === "example") {
        const idx = Math.min(Math.max(0, saved.input.index | 0), RT.examples.length - 1);
        if (idx !== 0) {
          try {
            if (blog) blog("Restoring " + RT.examples[idx].name + "…");
            STATE.summary = await RT.loadExample(RT.examples[idx].path);
          } catch (e) { /* keep default example 0 already loaded */ }
        }
        STATE.input = { mode: "example", index: idx };
      }
      if (saved.opId && OPS.some((o) => o.id === saved.opId)) STATE.opId = saved.opId;
      if (saved.params) STATE.params = Object.assign({}, STATE.params, saved.params);
    }
    // Ensure the example source is available for the source viewer.
    if (STATE.input.mode === "example" && !STATE.source) {
      const ex = RT.examples[STATE.input.index];
      STATE.source = await exampleSource(ex.path.split("/").pop(), ex.path);
    }
    // Reflect the restored selection in the UI.
    const sel = $("#exampleSel");
    if (sel && STATE.input.mode === "example") sel.value = String(STATE.input.index);
    $("#summaryWrap").replaceChildren(summaryCard(STATE.summary));
    for (const b of document.querySelectorAll(".op")) b.classList.toggle("active", b.getAttribute("data-op") === STATE.opId);
    updateExampleDesc(); updateOpHelp(); renderParams();
    const op = OPS.find((o) => o.id === STATE.opId);
    if (saved && saved.ran && op && !(op.corpus && !RT.hasCorpus())) await runOp();
  }

  async function start(runtime) {
    RT = runtime;
    document.documentElement.style.setProperty("--accent", RT.accent);
    if (RT.accentInk) document.documentElement.style.setProperty("--accent-ink", RT.accentInk);
    initTheme();
    document.title = "theoryforge (" + RT.langLabel + ") — interactive app";
    document.body.append(bootOverlay());
    const blog = $("#blog");
    const onProgress = (m) => { if (blog) blog.textContent = m; };
    try {
      const info = await RT.init(onProgress);
      RT.examples = info.examples; RT.version = info.version;
      STATE.summary = info.summary || null;
      document.body.append(el("a", { class: "skip-link", href: "#main" }, "Skip to content"));
      document.body.append(buildHeader());
      const main = el("main", { id: "main", tabindex: "-1" }, [buildSidebar(), buildMain()]);
      document.body.append(main);
      document.body.append(el("footer", { class: "app", html:
        "theoryforge " + esc(RT.version || "") + " · running entirely client-side via " + esc(RT.engineLabel) +
        " · <a href='https://github.com/pablobernabeu/theoryforge'>source</a>" }));
      updateThemeBtn();
      await applyRestore(onProgress);
      $("#boot").classList.add("hidden");
    } catch (err) {
      console.error(err);
      const b = $("#boot");
      if (b) b.replaceChildren(el("div", { class: "boot-error", role: "alert" }, [
        el("div", { class: "bt", text: "The app could not start" }),
        el("p", { class: "note", text: "Loading the " + RT.langLabel + " runtime failed: " + (err && err.message || err) }),
        el("button", { class: "btn", onclick: () => location.reload() }, "Reload"),
      ]));
    }
  }

  window.TF = { start, OPS, DIAG_SVG, util: { el, esc, download, copyText, toast, renderDot } };
})();
