/* theoryforge interactive apps — shared core (language-agnostic).
 *
 * Responsibilities: the operation registry, the UI, shaping a runtime's raw
 * package output into display sections, rendering, export (SVG/PNG/text), the
 * reproducible-code panel, and the light/dark theme. A language runtime
 * (r-runtime.js / py-runtime.js) provides booting, theory loading, package calls
 * and the language-specific code snippets, then calls TF.start(runtime).
 */
(function () {
  "use strict";

  const HEX_LOGO =
    '<svg class="logo" viewBox="0 0 174 200" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">' +
    '<defs><linearGradient id="lg" x1="0" y1="0" x2="0" y2="1">' +
    '<stop offset="0" stop-color="#22384f"/><stop offset="1" stop-color="#101b27"/></linearGradient></defs>' +
    '<path d="M87 3 L168 50 L168 150 L87 197 L6 150 L6 50 Z" fill="url(#lg)" stroke="#4cc2b0" stroke-width="7"/>' +
    '<line x1="61" y1="78" x2="113" y2="78" stroke="#7fd8cb" stroke-width="3"/>' +
    '<line x1="61" y1="78" x2="87" y2="110" stroke="#7fd8cb" stroke-width="3"/>' +
    '<line x1="113" y1="78" x2="87" y2="110" stroke="#7fd8cb" stroke-width="3"/>' +
    '<circle cx="61" cy="78" r="9" fill="#4cc2b0"/><circle cx="113" cy="78" r="9" fill="#4cc2b0"/>' +
    '<circle cx="87" cy="110" r="10" fill="#f6b24a"/>' +
    '<text x="87" y="150" text-anchor="middle" font-family="system-ui,sans-serif" font-size="24" font-weight="700" letter-spacing="-0.4">' +
    '<tspan fill="#f3f6f7">theory</tspan><tspan fill="#f6b24a">forge</tspan></text></svg>';

  const OPS = [
    { id: "check", label: "Rigour checklist", desc: "12-item score, gate, per-item status" },
    {
      id: "diagram", label: "Diagram", desc: "Nomological net, DAG, workflow…",
      params: [{
        id: "type", label: "Diagram type", type: "select", default: "nomological_net",
        options: ["nomological_net", "context", "workflow", "causal_dag", "provenance",
          "development_roadmap", "pipeline", "venn", "rigor", "severity"],
      }],
    },
    { id: "severity", label: "Severity rubric", desc: "Per-prediction risk & severity" },
    { id: "redundancy", label: "Redundancy screen", desc: "Lexical overlap of constructs" },
    { id: "sem", label: "SEM (lavaan)", desc: "Compile to lavaan model syntax" },
    { id: "preregister", label: "Preregistration", desc: "Preregistration document" },
    { id: "dossier", label: "Audit dossier", desc: "Reviewer-facing bundle" },
    {
      id: "simulate", label: "Simulation", desc: "Dynamical-system trajectory",
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
      params: [{ id: "min_link", label: "min_link", type: "number", default: 2, min: 1, max: 20, step: 1 }],
    },
    {
      id: "landscape", label: "Theory landscape", desc: "Map theory onto lit themes", corpus: true,
      params: [{ id: "min_link", label: "min_link", type: "number", default: 2, min: 1, max: 20, step: 1 }],
    },
  ];

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
    let t = $(".toast"); if (!t) { t = el("div", { class: "toast" }); document.body.append(t); }
    t.textContent = msg; t.classList.add("show");
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove("show"), 1800);
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

  function tableSection(title, columns, rows, opts) {
    const thead = el("thead", null, el("tr", null, columns.map((c) => el("th", { text: c.label || c }))));
    const tbody = el("tbody", null, rows.map((r) =>
      el("tr", null, columns.map((c) => {
        const key = c.key || c;
        const v = r[key];
        if (c.pill) return el("td", null, pill(v));
        return el("td", { class: c.num ? "num" : "" }, c.num ? num(v) : (Array.isArray(v) ? v.join(", ") : (v === "" || v == null ? "—" : String(v))));
      }))));
    return { kind: "node", node: wrapSection(title, opts && opts.extra, el("table", { class: "grid" }, [thead, tbody])) };
  }
  function kvSection(title, items) {
    const tbody = el("tbody", null, items.map(([k, v]) =>
      el("tr", null, [el("td", { text: k }), el("td", null, v && v.nodeType ? v : document.createTextNode(String(v)))])));
    return { kind: "node", node: wrapSection(title, null, el("table", { class: "grid" }, tbody)) };
  }
  function wrapSection(title, extraControls, body) {
    const head = el("div", { class: "sh" }, [el("span", { text: title || "" }), el("span", { class: "grow" })]);
    if (extraControls) for (const c of extraControls) head.append(c);
    return el("div", { class: "section" }, [head, body]);
  }

  function figureSection(title, svgString, baseName) {
    const fig = el("div", { class: "figure", html: svgString });
    const svgEl = fig.querySelector("svg");
    const btnSvg = el("button", { class: "btn ghost sm", onclick: () => download(baseName + ".svg", svgString, "image/svg+xml") }, "SVG");
    const btnPng = el("button", { class: "btn ghost sm", onclick: () => exportPng(svgEl, baseName) }, "PNG");
    return { kind: "node", node: wrapSection(title, [btnSvg, btnPng], fig) };
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
      w = (parseFloat(clone.getAttribute("width")) || w || svgEl.clientWidth || 600);
      h = (parseFloat(clone.getAttribute("height")) || h || svgEl.clientHeight || 400);
      clone.setAttribute("width", w); clone.setAttribute("height", h);
      const data = new XMLSerializer().serializeToString(clone);
      const img = new Image();
      const svgUrl = URL.createObjectURL(new Blob([data], { type: "image/svg+xml;charset=utf-8" }));
      await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = svgUrl; });
      const scale = 2;
      const canvas = el("canvas"); canvas.width = Math.ceil(w * scale); canvas.height = Math.ceil(h * scale);
      const ctx = canvas.getContext("2d");
      ctx.fillStyle = "#ffffff"; ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.setTransform(scale, 0, 0, scale, 0, 0);
      ctx.drawImage(img, 0, 0, w, h);
      URL.revokeObjectURL(svgUrl);
      canvas.toBlob((blob) => { if (blob) download(baseName + ".png", blob, "image/png"); else toast("PNG export failed"); }, "image/png");
    } catch (e) { toast("PNG export failed"); console.error(e); }
  }

  // trajectory line chart (SVG) for simulate
  function trajectoryChart(states, trajectory) {
    const W = 540, H = 300, pad = { l: 44, r: 110, t: 16, b: 28 };
    const n = trajectory.length, m = states.length;
    let lo = Infinity, hi = -Infinity;
    for (const row of trajectory) for (const v of row) { if (v < lo) lo = v; if (v > hi) hi = v; }
    if (!isFinite(lo)) { lo = 0; hi = 1; }
    if (hi - lo < 1e-9) { hi += 1; lo -= 1; }
    const x = (i) => pad.l + (i / Math.max(1, n - 1)) * (W - pad.l - pad.r);
    const y = (v) => pad.t + (1 - (v - lo) / (hi - lo)) * (H - pad.t - pad.b);
    const colors = ["#2fa392", "#d98a14", "#4e79a7", "#b5446e", "#6a8f3a", "#8a5fc0", "#c0563a"];
    const parts = [`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" font-family="system-ui,sans-serif" font-size="12">`];
    parts.push(`<rect x="0" y="0" width="${W}" height="${H}" fill="#ffffff"/>`);
    // axes
    parts.push(`<line x1="${pad.l}" y1="${pad.t}" x2="${pad.l}" y2="${H - pad.b}" stroke="#bbb"/>`);
    parts.push(`<line x1="${pad.l}" y1="${H - pad.b}" x2="${W - pad.r}" y2="${H - pad.b}" stroke="#bbb"/>`);
    parts.push(`<text x="${pad.l - 6}" y="${y(hi)}" text-anchor="end" fill="#666">${hi.toFixed(2)}</text>`);
    parts.push(`<text x="${pad.l - 6}" y="${y(lo)}" text-anchor="end" fill="#666">${lo.toFixed(2)}</text>`);
    parts.push(`<text x="${pad.l}" y="${H - 8}" fill="#666">step 0</text>`);
    parts.push(`<text x="${W - pad.r}" y="${H - 8}" text-anchor="end" fill="#666">step ${n - 1}</text>`);
    for (let s = 0; s < m; s++) {
      const col = colors[s % colors.length];
      let d = "";
      for (let i = 0; i < n; i++) d += (i ? "L" : "M") + x(i).toFixed(1) + " " + y(trajectory[i][s]).toFixed(1) + " ";
      parts.push(`<path d="${d.trim()}" fill="none" stroke="${col}" stroke-width="2"/>`);
      const ly = pad.t + 6 + s * 18;
      parts.push(`<rect x="${W - pad.r + 8}" y="${ly - 9}" width="11" height="11" rx="2" fill="${col}"/>`);
      parts.push(`<text x="${W - pad.r + 24}" y="${ly}" fill="#333">${esc(states[s])}</text>`);
    }
    parts.push("</svg>");
    return parts.join("\n");
  }

  async function shapeResult(opId, raw, params, theoryId) {
    const sections = [];
    const base = (theoryId || "theory") + "." + opId;
    if (opId === "check") {
      const rep = raw.report;
      sections.push(figureSection("Rigour grid", raw.svg, theoryId + ".rigor"));
      sections.push(kvSection("Summary", [
        ["Aggregate score", rep.aggregate_score + " / 100"],
        ["Gate", pill(rep.gate)],
        ["Blockers failed", String(rep.n_blockers_failed)],
        ["Maturity", rep.maturity],
      ]));
      sections.push(tableSection("Checklist items",
        [{ key: "id", label: "item" }, { key: "status", label: "status", pill: true },
         { key: "score", label: "score", num: true }, { key: "weight", label: "weight", num: true },
         { key: "severity_if_fail", label: "severity if fail" }],
        asArr(rep.items)));
    } else if (opId === "severity") {
      const rows = asArr(raw.rows);
      sections.push(figureSection("Severity chart", raw.svg, theoryId + ".severity"));
      if (rows.length) sections.push(tableSection("Per-prediction severity",
        [{ key: "prediction_id", label: "prediction" }, { key: "type", label: "type" },
         { key: "risk_score", label: "risk", num: true }, { key: "computed_severity", label: "computed severity", num: true }],
        rows));
      else sections.push({ kind: "node", node: wrapSection("Per-prediction severity", null, el("p", { class: "note", text: "This theory has no predictions." })) });
    } else if (opId === "redundancy") {
      const rows = asArr(raw.rows);
      if (rows.length) sections.push(tableSection("Construct pairs (descending similarity)",
        [{ key: "a", label: "construct a" }, { key: "b", label: "construct b" },
         { key: "similarity", label: "Jaccard", num: true }, { key: "flag", label: "flag", pill: true }],
        rows));
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
        ["Under-theorized fronts", asArr(r.under_theorized_fronts).join(", ") || "—"],
        ["Redundancy risk", asArr(r.redundancy_risk).join(", ") || "—"],
      ]));
      if (raw.dot) sections.push(figureSection("Theme landscape", await renderDot(raw.dot), theoryId + ".theme_landscape"));
      sections.push(textSection("landscape JSON", JSON.stringify(r, null, 2), theoryId + ".landscape.json", "application/json"));
    }
    return sections;
  }

  // ---- UI ------------------------------------------------------------------
  let RT, STATE = { opId: "check", params: {}, summary: null };

  function buildHeader() {
    const toggle = el("button", { class: "icon-btn", id: "themeToggle", onclick: cycleTheme, title: "Theme" });
    return el("header", { class: "app" }, [
      el("span", { html: HEX_LOGO }),
      el("div", { class: "titles" }, [
        el("span", { class: "t", text: "theoryforge" }),
        el("span", { class: "s", text: "Interactive app · runs the " + RT.langLabel + " package in your browser" }),
      ]),
      el("span", { class: "badge", text: RT.langLabel }),
      el("span", { class: "grow" }),
      el("a", { class: "doclink", href: RT.docsUrl, target: "_blank", rel: "noopener" }, "Docs ↗"),
      el("a", { class: "doclink", href: "https://github.com/pablobernabeu/theoryforge", target: "_blank", rel: "noopener" }, "GitHub ↗"),
      toggle,
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

    const opGrid = el("div", { class: "ops", id: "opGrid" }, OPS.map((op) =>
      el("button", {
        class: "op" + (op.id === STATE.opId ? " active" : ""), "data-op": op.id,
        onclick: () => selectOp(op.id),
        disabled: op.corpus && !RT.hasCorpus() ? "" : null,
        title: op.corpus && !RT.hasCorpus() ? "Needs a corpus" : op.desc,
      }, [el("span", { class: "on", text: op.label }), el("span", { class: "od", text: op.desc })])));

    const paramsWrap = el("div", { class: "params", id: "paramsWrap" });
    const runBtn = el("button", { class: "btn", id: "runBtn", onclick: runOp }, "Run ▸");

    return el("div", { class: "sidebar" }, [
      el("div", { class: "panel" }, [
        el("h2", null, "Theory"),
        el("label", { class: "field" }, [el("span", null, "Example theory"), exSelect]),
        el("label", { class: "field" }, [el("span", null, "…or upload your own (YAML / JSON)"), el("div", { class: "filewrap" }, fileInput)]),
        summaryWrap,
      ]),
      el("div", { class: "panel" }, [
        el("h2", null, "Operation"),
        opGrid, paramsWrap,
        el("div", { style: "margin-top:14px" }, runBtn),
      ]),
    ]);
  }

  function buildMain() {
    return el("div", null, [
      el("div", { class: "panel" }, [
        el("div", { class: "outhead" }, [el("h2", { id: "outTitle" }, "Result"), el("span", { class: "grow" })]),
        el("div", { id: "output" }, el("p", { class: "note", text: "Choose an operation and press Run." })),
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
      if (STATE.params[p.id] === undefined) STATE.params[p.id] = p.default;
      let input;
      if (p.type === "select") {
        input = el("select", { onchange: (e) => { STATE.params[p.id] = e.target.value; } },
          p.options.map((o) => el("option", { value: o, selected: o === STATE.params[p.id] ? "" : null }, o)));
      } else {
        input = el("input", {
          type: "number", value: STATE.params[p.id], min: p.min, max: p.max, step: p.step,
          oninput: (e) => { STATE.params[p.id] = e.target.value === "" ? p.default : Number(e.target.value); },
        });
      }
      const field = el("label", { class: "field", style: "margin:0" }, [el("span", null, p.label), input]);
      if (op.params.length > 1 && p.type === "number") { rows.append(field); inRow = true; }
      else wrap.append(field);
    }
    if (inRow) wrap.append(rows);
  }

  function selectOp(id) {
    STATE.opId = id;
    for (const b of document.querySelectorAll(".op")) b.classList.toggle("active", b.getAttribute("data-op") === id);
    renderParams();
  }

  async function onExampleChange(e) {
    const ex = RT.examples[Number(e.target.value)];
    await withBusy("Loading " + ex.name + "…", async () => {
      STATE.summary = await RT.loadExample(ex.path);
      $("#summaryWrap").replaceChildren(summaryCard(STATE.summary));
      $("#fileInput").value = "";
    });
  }
  async function onFileChange(e) {
    const f = e.target.files && e.target.files[0]; if (!f) return;
    const text = await f.text();
    await withBusy("Loading " + f.name + "…", async () => {
      try {
        STATE.summary = await RT.loadTheoryText(text, f.name);
        $("#summaryWrap").replaceChildren(summaryCard(STATE.summary));
      } catch (err) {
        $("#summaryWrap").replaceChildren(errorBox("Could not load this file", err));
      }
    });
  }

  function errorBox(title, err) {
    const msg = (err && (err.message || err.toString())) || String(err);
    return el("div", { class: "error" }, [el("div", { class: "et", text: title }), el("div", { text: msg })]);
  }

  let busy = false;
  async function withBusy(label, fn) {
    if (busy) return; busy = true;
    const btn = $("#runBtn"); const prev = btn ? btn.textContent : "";
    if (btn) { btn.disabled = true; }
    try { await fn(); } finally { busy = false; if (btn) { btn.disabled = false; btn.textContent = prev; } }
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
      } catch (err) {
        out.replaceChildren(errorBox("Operation failed", err));
        console.error(err);
      }
    });
  }

  // ---- boot ---------------------------------------------------------------
  function bootOverlay() {
    return el("div", { id: "boot" }, [
      el("span", { html: HEX_LOGO.replace('class="logo"', 'class="logo"') }),
      el("div", { class: "bt", text: "Starting " + RT.langLabel + " in your browser" }),
      el("div", { class: "spinner" }),
      el("div", { class: "blog", id: "blog", text: "Loading runtime…" }),
    ]);
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
      document.body.append(buildHeader());
      const main = el("main", null, [buildSidebar(), buildMain()]);
      document.body.append(main);
      document.body.append(el("footer", { class: "app", html:
        "theoryforge " + esc(RT.version || "") + " · running entirely client-side via " + esc(RT.engineLabel) +
        " · <a href='https://github.com/pablobernabeu/theoryforge'>source</a>" }));
      updateThemeBtn();
      renderParams();
      $("#boot").classList.add("hidden");
    } catch (err) {
      onProgress("Startup failed: " + (err && err.message || err));
      const b = $("#boot"); if (b) { b.querySelector(".spinner").style.display = "none"; }
      console.error(err);
    }
  }

  window.TF = { start, OPS, util: { el, esc, download, copyText, toast, renderDot } };
})();
