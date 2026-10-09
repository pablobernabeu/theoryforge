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
      help: "Scores the theory against the 12-item rigour checklist (falsifiability, precision, parsimony, and so on) and returns an aggregate 0–100 score, a pass/blocked/advisory gate and the colour-coded status grid." },
    { id: "validate", label: "Validate", desc: "Structural + referential checks",
      help: "Runs the package's full validation: required fields, the type of every field and enum membership, plus referential integrity (unique ids, and every proposition, prediction, assumption, evidence and test-outcome reference points to a declared id). Lists every problem found, or confirms the theory is valid." },
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
      help: "Applies the severity rubric, a pre-data ranking of claim form, to every prediction, returning its risk score (the riskiness of the claim form) and computed severity (with the directional discount and the diagnostic bonus)." },
    { id: "redundancy", label: "Redundancy screen", desc: "Lexical overlap of constructs",
      help: "Compares every pair of construct definitions by token-set Jaccard overlap and flags pairs above the redundancy threshold for review." },
    {
      id: "appraise", label: "Appraise amendment", desc: "Progressive vs degenerating", needsPrior: true,
      help: "Compares what the current theory, treated as the amendment, claims with what a prior version claims, and classifies the change as progressive or degenerating (Lakatos, 1970). Neutral is theoryforge's label for an amendment that meets neither rule. The prior defaults to the version the theory declares as its parent, an example whose version id is the theory's parent_id and whose id the theory's id begins with. Choose another below or upload one. Predictions are matched by id, so a version of another theory gives a meaningless verdict.",
      params: [{ id: "prior", label: "Prior version", type: "theory" }],
    },
    { id: "sem", label: "SEM (lavaan)", desc: "Compile to lavaan model syntax",
      help: "Compiles the constructs (measurement model) and propositions (structural model) to lavaan model syntax you can paste straight into an SEM fit." },
    {
      id: "implications", label: "Implied independencies", desc: "What the causal graph implies",
      help: "Derives the conditional independencies that the theory's causal graph implies, the claims data can refute. Only constructs that a directed relation (increases, decreases, causes, mediates or moderates) names enter the graph, and an association joins two of them as covariance the theory leaves unexplained. A missing edge is read as no direct effect, so the statements hold only if the graph omits no common cause of two of its constructs. A feedback loop is refused unless cycles is set to sigma, whose statements hold only when every loop has a unique equilibrium.",
      params: [{ id: "cycles", label: "cycles", type: "select", default: "refuse", options: ["refuse", "sigma"] }],
    },
    { id: "preregister", label: "Preregistration", desc: "Preregistration document",
      help: "Generates a preregistration document in Markdown: hypotheses numbered in file order with their derivation, and the per-prediction severity." },
    { id: "dossier", label: "Audit dossier", desc: "Reviewer-facing bundle",
      help: "Assembles a reviewer-facing audit bundle in Markdown: the rigour report, severity, provenance and the preregistration in one document." },
    {
      id: "simulate", label: "Simulation", desc: "Dynamical-system trajectory",
      help: "Treats each construct as a state variable and each directed proposition as a signed coupling, then propagates the linear system and plots the trajectory. The exact method computes the solution at each step from the matrix exponential, whatever dt is. The Euler method takes fixed explicit steps, which drift from the solution when dt is large against the network's rates.",
      params: [
        { id: "method", label: "method", type: "select", default: "exact", options: ["exact", "euler"] },
        { id: "steps", label: "steps", type: "number", default: 30, min: 1, max: 500, step: 1 },
        { id: "dt", label: "dt", type: "number", default: 0.1, min: 0.001, max: 2, step: 0.01 },
        { id: "k", label: "k (coupling)", type: "number", default: 1.0, min: 0, max: 10, step: 0.1 },
        { id: "damping", label: "damping", type: "number", default: 0.5, min: 0, max: 5, step: 0.1 },
        { id: "init", label: "init", type: "number", default: 1.0, min: -10, max: 10, step: 0.1 },
      ],
    },
    {
      id: "litmap", label: "Literature map", desc: "Co-occurrence, themes, co-citation", corpus: true,
      help: "Maps the bundled literature corpus: keyword co-occurrence, connected-component themes and co-citation. min_link is the minimum number of records a pair must share to count as a link. On a real corpus, connected components put nearly every keyword in one theme.",
      params: [{ id: "min_link", label: "min_link", type: "number", default: 2, min: 1, max: 20, step: 1 }],
    },
    {
      id: "landscape", label: "Theory landscape", desc: "Map theory onto lit themes", corpus: true,
      help: "Positions the theory and its alternatives against the corpus themes and names the words behind each match. A theme is under-theorised when none of the registered accounts addresses it, and crowded when two or more do, which calls for predictions that tell them apart.",
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
    catch { toast("Copy failed. Select the text and copy it manually."); }
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
  // A browser that blocks site data throws a SecurityError on any touch of
  // localStorage, so every access is guarded. The choice made in this session
  // is kept in memory as well, which lets the toggle cycle when nothing can be
  // stored. A stored value other than light or dark means "system".
  let _sessionTheme = null;
  function currentTheme() {
    let t = _sessionTheme;
    if (t === null) { try { t = localStorage.getItem("tf-theme"); } catch (e) { t = null; } }
    return t === "light" || t === "dark" ? t : "system";
  }
  function initTheme() { applyTheme(currentTheme()); }
  function cycleTheme() {
    const order = ["light", "dark", "system"];
    const next = order[(order.indexOf(currentTheme()) + 1) % order.length];
    _sessionTheme = next;
    try { localStorage.setItem("tf-theme", next); } catch (e) { /* storage blocked: kept for this session only */ }
    applyTheme(next); updateThemeBtn();
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
  // digraph purely for rendering. The exported IR keeps the dagitty form. DOT has
  // no bidirected edge, so an association, `a <-> b`, is drawn as a dashed edge
  // with an arrowhead at each end. An identifier may be bare or double-quoted.
  const DAG_ID = '("(?:[^"\\\\]|\\\\.)*"|[^\\s"]+)';
  const BIDIRECTED_LINE = new RegExp("^([ \\t]*)" + DAG_ID + " <-> " + DAG_ID + "[ \\t]*$", "gm");
  function dagToDigraph(ir) {
    return ir
      .replace(/^\s*dag\s*\{/, "digraph causal_dag {\n  rankdir=LR;\n  node [shape=box, style=rounded];")
      .replace(BIDIRECTED_LINE, "$1$2 -> $3 [dir=both, style=dashed]");
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
    // Scale to the finite extremes only. Both packages stop a run before any
    // value stops being finite, so this guard only keeps a malformed result
    // from poisoning the range or the path.
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
    check: "The checklist scores twelve facets of rigour and combines them into an overall score and a gate. Read the gate first. Pass means neither blocking item failed, and blocked means at least one did. At draft maturity, the gate is always advisory: the checklist reports but never blocks, so read the item statuses. An item with nothing to assess, such as redundancy in a theory with one construct, is marked n/a and left out of the score, which is the weighted mean of the applicable items. The coverage is their share of the checklist's weight. The grid below shows each item's status.",
    validate: "Validation reports structural and referential problems: missing required fields, values of the wrong type or outside the allowed set, duplicate identifiers and cross-references that point to nothing. A valid theory is the precondition for every other operation.",
    diagram: "The diagram is rendered from the package's intermediate representation, shown below the figure. Export the figure as SVG or PNG, or copy the representation to render it elsewhere.",
    severity: "The rubric grades each prediction by the form of its claim alone, so it can be read before any data exist. The risk score reflects how committal the claim is. The computed severity adjusts it down for merely directional claims and up for claims that discriminate between rival theories. Longer bars mark riskier claims. How severely a claim is tested depends on the design and the data, which the rubric does not read.",
    redundancy: "Each pair of constructs is compared by the words their definitions share. The Jaccard index divides the shared words by all the words of the two definitions, and the overlap coefficient divides them by the words of the shorter one, so both run from 0 to 1. A pair is flagged for review when its Jaccard index reaches 0.85, a near-duplicate, or when both definitions hold at least three content words and the overlap reaches 0.85, one definition contained in the other. Near-duplicate constructs blur a theory and inflate its apparent scope. The screen compares words only, so it cannot tell whether two constructs are empirically redundant.",
    appraise: "An amendment is progressive when a new prediction derived from content the prior version lacked is corroborated, with no ad hoc assumption added and no corroborated prediction dropped. It is degenerating when it adds an ad hoc assumption and no corroborated new content, and neutral otherwise. A prediction is corroborated when some test passes it and none fails it, and an assumption added for an anomaly is ad hoc unless new content it protects is corroborated. A prediction that only changed its id is a rename, and one derived only from the prior's own propositions is an articulation, so neither counts as new content. The verdict and its components appear below.",
    sem: "The constructs become a measurement model and the propositions a structural model, expressed in lavaan syntax. Paste it into an SEM fit in R or other lavaan-compatible software.",
    implications: "Each statement says that two constructs are independent once the constructs after the bar are held fixed, a claim data can refute, for instance by a partial correlation in a linear model. The statements follow from the edges the theory leaves out, so each omission is read as a claim. A conditional statement tested on observed scores is rejected too often when the constructs held fixed are measured with error. A latent-variable model, such as one built on the SEM operation's measurement model, takes that error into account. A pair that no set of constructs separates is listed apart, since the theory implies no independence for it.",
    preregister: "The preregistration lists each hypothesis with its derivation and severity, in file order, ready to timestamp before data collection.",
    dossier: "The dossier gathers the rigour report, severity, provenance and preregistration into one reviewer-facing document.",
    simulate: "Each construct is read as a quantity that changes over time. A directed proposition pushes one construct up (increases, causes, mediates) or down (decreases) in proportion to another, with one gain k for every coupling, and every construct decays towards zero at the damping rate. Moderates and associates couple nothing. All constructs start from the same value. The chart traces the values from the initial state, and the table below holds the numbers.",
    litmap: "The bundled corpus is mapped three ways: which keywords co-occur, which keywords cluster into themes and which references are cited together. The min_link setting controls how many shared records a pair needs to count as linked. A theme is a connected group of keywords, which separates this small designed corpus into four. On a real corpus, nearly every keyword joins one group, and the package warns that such themes are not informative.",
    landscape: "The theory and its rivals are placed against the corpus themes by the words a theme's keywords share with the theory's construct labels, or with a rival's label and key constructs. Words of the theory's title, words most records carry and words such as theory or model do not count. Under-theorised fronts are themes that none of the registered accounts addresses. Crowded themes are addressed by two or more of them and call for predictions that discriminate between the accounts.",
  };
  const fmtNum = (x) => (typeof x === "number" ? (Number.isInteger(x) ? String(x) : x.toFixed(2)) : String(x));
  const plural = (n, w) => n + " " + w + (n === 1 ? "" : "s");
  // "a", "a and b", "a, b and c".
  const listAnd = (xs) => (xs.length < 2 ? xs.join("") : xs.slice(0, -1).join(", ") + " and " + xs[xs.length - 1]);
  // Both packages report full validation as "invalid theory object: " followed
  // by the problems joined by "; ". The Validate result, its interpretation and
  // the sidebar chip all count problems through this one split.
  const problemList = (message) =>
    String(message).replace(/^invalid theory object:\s*/i, "").split(/;\s*/).filter(Boolean);

  // A result-specific sentence that reads the actual output, to help interpret it.
  function interpret(opId, raw, params) {
    const S = STATE.summary || {}, c = S.counts || {};
    if (opId === "check") {
      const r = raw.report, items = asArr(r.items);
      const by = (st) => items.filter((i) => i.status === st).length;
      const na = by("n/a");
      // The failed blockers are read from the report, so the sentence follows
      // whichever items the checklist makes blocking.
      const failed = items.filter((i) => i.severity_if_fail === "blocker" && i.status === "fail").map((i) => i.id);
      const score = "This theory scores " + fmtNum(r.aggregate_score) + " out of 100";
      // At draft maturity the gate is advisory whatever fails, so it says
      // nothing about readiness and the sentence says why it was given.
      let txt = r.gate === "advisory"
        ? score + ". It is at draft maturity, where the gate is advisory and blocks nothing."
        : score + " and " + ({ pass: "passes the gate", blocked: "is blocked" }[r.gate] || "has the gate " + r.gate) + ".";
      txt += " Of the " + (items.length - na) + " applicable items, " + by("pass") + " pass, " + by("warn") + " warn and " + by("fail") + " fail";
      txt += failed.length
        ? ", and the blocking " + (failed.length === 1 ? "item " : "items ") + listAnd(failed) + (failed.length === 1 ? " fails" : " fail") +
          (r.gate === "advisory" ? ", which would block the theory at any later maturity." : ".")
        : ", and no blocking item fails.";
      // Items with nothing to assess are left out of the score, which then
      // covers less than the whole checklist.
      if (na) txt += " " + (na === 1 ? "One item has" : na + " items have") + " nothing to assess and " + (na === 1 ? "is" : "are") + " left out of the score, which covers " + Math.round(Number(r.coverage) * 100) + " per cent of the checklist's weight.";
      return txt;
    }
    if (opId === "validate") {
      if (raw.ok) return "The theory is structurally valid and every internal reference resolves.";
      const errs = problemList(raw.message || "");
      return "Validation found " + plural(errs.length, "problem") + ". Each one is listed below.";
    }
    if (opId === "severity") {
      const rows = asArr(raw.rows);
      if (!rows.length) return "This theory has no predictions to grade.";
      const sev = rows.map((r) => Number(r.computed_severity));
      const top = rows[sev.indexOf(Math.max(...sev))];
      const mean = sev.reduce((a, b) => a + b, 0) / sev.length;
      return "Across " + plural(rows.length, "prediction") + ", computed severity runs from " + Math.min(...sev).toFixed(2) + " to " + Math.max(...sev).toFixed(2) + " (mean " + mean.toFixed(2) + "). The riskiest claim is " + top.prediction_id + ".";
    }
    if (opId === "redundancy") {
      const rows = asArr(raw.rows);
      if (!rows.length) return "There are fewer than two constructs, so there are no pairs to compare.";
      const flagged = rows.filter((r) => String(r.flag) === "review").length;
      const top = rows[0];
      const lead = flagged ? plural(flagged, "pair") + " of " + rows.length + (flagged === 1 ? " is" : " are") + " flagged for review." : "No pair is flagged for review.";
      return lead + " The most similar pair is " + top.a + " and " + top.b + " (Jaccard " + fmtNum(top.similarity) + ", overlap " + fmtNum(top.overlap) + ").";
    }
    if (opId === "appraise") {
      const r = raw, np = asArr(r.new_predictions).length, cn = asArr(r.corroborated_new).length, ah = asArr(r.ad_hoc_assumptions).length;
      const ar = asArr(r.articulated).length, dr = asArr(r.dropped).length, dc = asArr(r.dropped_corroborated).length;
      let txt = "The amendment is " + r.verdict + ". It introduces " + plural(np, "new prediction") + ", of which " + cn + (cn === 1 ? " is" : " are") + " corroborated and " + ar + (ar === 1 ? " only articulates" : " only articulate") + " the prior's propositions, and " + plural(ah, "ad hoc assumption") + ".";
      if (dr) txt += " It drops " + plural(dr, "prediction") + " of the prior, " + dc + " of them corroborated.";
      if (!isDeclaredParent(S, priorLineage(params.prior))) txt += " " + PRIOR_CAUTION;
      return txt;
    }
    if (opId === "sem") return "The measurement model covers " + plural(c.constructs || 0, "construct") + " and the structural model " + plural(c.propositions || 0, "proposition") + ".";
    if (opId === "implications") {
      if (raw.ok === false) {
        return /cycle found/.test(String(raw.message)) && params.cycles !== "sigma"
          ? "The directed relations form a feedback loop, which the default reading refuses. Set cycles to sigma to derive the statements by sigma-separation, which assumes that every loop has a unique equilibrium."
          : "No statement can be derived until the problem the message names is corrected.";
      }
      const r = raw.result, n = asArr(r.constructs).length, k = asArr(r.implications).length;
      const ins = asArr(r.inseparable).length, loops = asArr(r.feedback).map(asArr);
      if (!n) return "The theory states no directed relation between constructs, so its causal graph has no vertices and implies no independence.";
      let txt = "The causal graph holds " + plural(n, "construct") + ", " + plural(r.n_edges, "directed edge") + " and " + plural(r.n_bidirected, "association") +
        ", and implies " + plural(k, "independence statement") + " by " + (r.criterion === "sigma" ? "sigma" : "m") + "-separation.";
      if (!k && !ins) txt += " Every pair of constructs in the causal graph is adjacent, so no pair is left to state.";
      if (ins) txt += " " + (ins === 1 ? "One pair the theory leaves unjoined is" : ins + " pairs the theory leaves unjoined are") + " separated by no set of constructs, so the theory implies no independence for " + (ins === 1 ? "it." : "them.");
      if (loops.length) {
        txt += " The graph has " + plural(loops.length, "feedback loop") + " (" + loops.map((l) => l.join(", ")).join("; ") + ")" +
          (k ? ", so the statements hold only if each loop has a unique equilibrium." : ".");
      }
      return txt;
    }
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
        development_roadmap: "The checklist items that fail or warn, in the order to address them.",
      };
      return byType[t] || ("A " + name + " diagram built from " + plural(c.constructs || 0, "construct") + " and " + plural(c.propositions || 0, "proposition") + ".");
    }
    if (opId === "simulate") {
      // A refusal or a divergence arrives as { ok: false, message }, which
      // shapeResult shows in place of the chart.
      if (raw.ok === false) return "";
      const r = raw.result, states = asArr(r.states), traj = asArr(r.trajectory).map(asArr);
      let lo = Infinity, hi = -Infinity;
      for (const row of traj) for (const v of row) { if (v < lo) lo = v; if (v > hi) hi = v; }
      if (!isFinite(lo) || !isFinite(hi)) { lo = 0; hi = 0; }
      const coincide = coincidenceGroups(states, traj).filter((g) => g.length > 1);
      const how = r.method === "exact" ? "computed exactly" : "approximated with Euler steps";
      let txt = "The " + plural(states.length, "construct") + " evolve over " + plural(r.steps, "step") + " of " + r.dt + " (" + how + "), with values from " + lo.toFixed(2) + " to " + hi.toFixed(2) + ".";
      if (coincide.length) {
        const lists = coincide.map((g) => g.map((i) => states[i]).join(", ")).join("; ");
        txt += " Some constructs follow an identical path (" + lists + "), so their lines are drawn with a small offset to keep each visible. Every construct starts from the same value and every coupling has the same gain, so constructs that receive the same couplings from the same sources move together. The coincidence follows from these simplifications and is no reason to change the theory.";
      } else {
        txt += " The trajectories are distinct.";
      }
      const ignored = asArr(r.ignored), opposed = asArr(r.opposed).map(asArr);
      if (ignored.length) txt += " " + plural(ignored.length, "proposition") + (ignored.length === 1 ? " couples" : " couple") + " nothing here (" + ignored.map((s) => s || "without id").join(", ") + "): moderation, association and links to undeclared constructs have no term in the model.";
      if (opposed.length) txt += " " + (opposed.length === 1 ? "One pair carries" : opposed.length + " pairs carry") + " both a positive and a negative coupling (" + opposed.map((p) => p.join(" → ")).join("; ") + "), which offset each other.";
      return txt;
    }
    if (opId === "litmap") {
      const r = raw.result;
      return "The corpus holds " + plural(r.n_records, "record") + ", " + plural(asArr(r.keywords).length, "distinct keyword") + " and " + plural(asArr(r.themes).length, "theme") + ", with " + plural(asArr(r.co_citation).length, "co-citation pair") + ".";
    }
    if (opId === "landscape") {
      const r = raw.result;
      return plural(asArr(r.themes).length, "theme") + " mapped. " + plural(asArr(r.under_theorised_fronts).length, "front") + " under-theorised, " + plural(asArr(r.redundancy_risk).length, "theme") + " crowded.";
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
        ["Coverage", num(rep.coverage) + " of the checklist's weight"],
        ["Gate", pill(rep.gate)],
        ["Blockers failed", String(rep.n_blockers_failed)],
        ["Maturity", rep.maturity],
      ]));
      // An item with nothing to assess has a null score, shown as n/a.
      const checkRows = asArr(rep.items).map((it) => Object.assign({}, it, { score: it.score == null ? "n/a" : it.score }));
      sections.push(tableSection("Checklist items",
        [{ key: "id", label: "item" }, { key: "status", label: "status", pill: true },
         { key: "score", label: "score", num: true }, { key: "weight", label: "weight", num: true },
         { key: "severity_if_fail", label: "severity if fail", grow: true }],
        checkRows, { extra: [jsonBtn(theoryId + ".report.json", rep)] }));
    } else if (opId === "validate") {
      const v = raw;
      if (v.ok) {
        sections.push({ kind: "node", node: wrapSection("Validation", null,
          el("div", { class: "valid-ok", role: "status" }, "✓ Valid. The theory passes structural validation.")) });
      } else {
        const errs = problemList(v.message || "invalid theory object");
        sections.push({ kind: "node", node: wrapSection("Validation", null,
          el("div", { class: "error", role: "alert" }, [
            el("div", { class: "et", text: "Invalid theory: " + errs.length + " problem" + (errs.length === 1 ? "" : "s") }),
            el("ul", { class: "err-list" }, errs.map((e) => el("li", null, e))),
          ])) });
      }
    } else if (opId === "appraise") {
      const r = raw;
      // The reading above the result carries the caution when this is "no".
      const parent = isDeclaredParent(STATE.summary, priorLineage(params.prior));
      sections.push(kvSection("Appraisal", [["Verdict", pill(r.verdict)], ["Prior version", priorName(params.prior) || "—"],
        ["Declared parent", parent ? "yes" : "no"]]));
      sections.push(tableSection("Detail",
        [{ key: "k", label: "category" }, { key: "v", label: "ids", grow: true }],
        [
          { k: "New predictions", v: asArr(r.new_predictions).join(", ") || "—" },
          { k: "Corroborated new", v: asArr(r.corroborated_new).join(", ") || "—" },
          { k: "Preregistered corroborations", v: asArr(r.corroborated_new_registered).join(", ") || "—" },
          { k: "Articulations of prior content", v: asArr(r.articulated).join(", ") || "—" },
          { k: "Derived from no proposition", v: asArr(r.underived).join(", ") || "—" },
          { k: "Renamed", v: asArr(r.renamed).map((p) => p.prior + " → " + p.new).join(", ") || "—" },
          { k: "Dropped", v: asArr(r.dropped).join(", ") || "—" },
          { k: "Dropped corroborated", v: asArr(r.dropped_corroborated).join(", ") || "—" },
          { k: "New anomalies", v: asArr(r.new_anomalies).join(", ") || "—" },
          { k: "Ad hoc assumptions", v: asArr(r.ad_hoc_assumptions).join(", ") || "—" },
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
         { key: "similarity", label: "Jaccard", num: true }, { key: "overlap", label: "overlap", num: true },
         { key: "flag", label: "flag", pill: true }],
        rows, { extra: [jsonBtn(theoryId + ".redundancy.json", rows)] }));
      else sections.push({ kind: "node", node: wrapSection("Redundancy screen", null, el("p", { class: "note", text: "Fewer than two constructs, so there are no pairs to compare." })) });
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
    } else if (opId === "implications" && raw.ok === false) {
      // A refusal is the package's answer for this theory, so it is shown as a
      // result with the package's message.
      sections.push({ kind: "node", node: wrapSection("Implied independencies", null,
        el("p", { class: "refusal", text: String(raw.message || "") })) });
    } else if (opId === "implications") {
      const r = raw.result, stmts = asArr(r.implications), ins = asArr(r.inseparable);
      const loops = asArr(r.feedback).map((l) => asArr(l).join(", "));
      sections.push(kvSection("Summary", [
        ["Criterion", r.criterion === "sigma" ? "sigma-separation" : "m-separation"],
        ["Constructs in the graph", String(asArr(r.constructs).length)],
        ["Directed edges", String(r.n_edges)], ["Associations", String(r.n_bidirected)],
        ["Feedback loops", loops.join("; ") || "none"],
        ["Statements", String(stmts.length)], ["Pairs no set separates", String(ins.length)],
      ]));
      if (stmts.length) sections.push(textSection("Implied independencies", stmts.map((s) => s.statement).join("\n") + "\n", theoryId + ".implications.txt", "text/plain"));
      if (ins.length) sections.push(tableSection("Pairs no set separates", [{ key: "a", label: "construct a" }, { key: "b", label: "construct b" }], ins));
      sections.push(textSection("implications JSON", JSON.stringify(r, null, 2), theoryId + ".implications.json", "application/json"));
    } else if (opId === "preregister") {
      sections.push(textSection("Preregistration (Markdown)", raw.text, theoryId + ".prereg.md", "text/markdown"));
    } else if (opId === "dossier") {
      sections.push(textSection("Audit dossier (Markdown)", raw.text, theoryId + ".dossier.md", "text/markdown"));
    } else if (opId === "simulate" && raw.ok === false) {
      // Both packages refuse invalid knobs and stop at the step where a state
      // stops being finite, naming the step and the construct. Show their text,
      // and say what a divergence means under the method that was run: the
      // exact solution grows only when the system does, while Euler steps can
      // diverge from a system that decays.
      const msg = String(raw.message || "");
      const kids = [el("div", { class: "et", text: "The simulation stopped" }), el("div", { text: msg })];
      if (/diverged/.test(msg)) {
        kids.push(el("div", { text: params.method === "exact"
          ? "The exact solution itself grows without bound: a feedback loop's gain k outweighs the damping. Raise the damping, lower k or run fewer steps."
          : "Euler steps can diverge although the system decays, when dt is too coarse, and the system can also grow on its own when a loop's gain k outweighs the damping. Run the exact method to tell the two apart." }));
      }
      sections.push({ kind: "node", node: wrapSection("Simulation", null,
        el("div", { class: "error", role: "alert" }, kids)) });
    } else if (opId === "simulate") {
      const r = raw.result;
      const states = asArr(r.states), traj = asArr(r.trajectory).map(asArr);
      // The Euler departure warning, which both packages raise with one text.
      if (raw.warning) sections.push({ kind: "node", node: wrapSection("Euler steps", null,
        el("p", { class: "note", role: "status", text: String(raw.warning) + ". The exact method gives the solution of the same system." })) });
      sections.push(figureSection("Trajectory", trajectoryChart(states, traj), theoryId + ".simulate"));
      const cols = [{ key: "_step", label: "step" }].concat(states.map((s, i) => ({ key: "s" + i, label: s, num: true })));
      const rows = traj.map((row, i) => { const o = { _step: i }; row.forEach((v, j) => (o["s" + j] = v)); return o; });
      sections.push(tableSection("State trajectory (" + (r.method || "euler") + ", steps " + r.steps + ", dt " + r.dt + ")", cols, rows));
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
        ["Crowded themes", asArr(r.redundancy_risk).join(", ") || "—"],
      ]));
      if (raw.dot) sections.push(figureSection("Theme landscape", await renderDot(raw.dot), theoryId + ".theme_landscape"));
      sections.push(textSection("landscape JSON", JSON.stringify(r, null, 2), theoryId + ".landscape.json", "application/json"));
    }
    const intro = buildIntro(opId, raw, params);
    if (intro) sections.unshift(intro);
    return sections;
  }

  // ---- UI ------------------------------------------------------------------
  // `input` is { mode: "example", path } or { mode: "upload", name, text }.
  // `prior` is the uploaded prior version, { name, lineage }, and `priorError`
  // the last failed upload of one, { name, err }.
  let RT, STATE = { opId: "check", params: {}, summary: null, input: null, source: null, ran: false, prior: null, priorError: null };
  // Whether the result panel holds an operation's output or error, which a
  // change of theory then clears.
  let resultShown = false;

  // ---- the appraisal's prior -----------------------------------------------
  // A candidate prior is the declared parent of the loaded theory when its
  // version id is the parent_id the theory declares and the theory's id equals
  // or begins with the candidate's. The amended panic network's id,
  // panic-network-2026-v2, begins with panic-network-2026. Nearly every
  // example is version v1, so the version alone would make most of them a
  // parent. The runtimes read each example's lineage at start-up, and each
  // load reports the theory's version.
  const UPLOADED_PRIOR = "upload";
  const PRIOR_CAUTION = "This version is not the declared parent of the loaded theory. Predictions are matched by id, so a version of another theory can make the verdict meaningless.";
  function isDeclaredParent(theory, cand) {
    const tv = (theory && theory.version) || {}, cv = (cand && cand.version) || {};
    const tid = theory && theory.id, cid = cand && cand.id;
    return typeof tv.parent_id === "string" && tv.parent_id !== "" && cv.id === tv.parent_id &&
      typeof tid === "string" && typeof cid === "string" && cid !== "" && tid.startsWith(cid);
  }
  function priorLineage(value) {
    if (value === UPLOADED_PRIOR) return STATE.prior ? STATE.prior.lineage : null;
    const ex = RT.examples.find((e) => e.path === value);
    return ex ? ex.lineage : null;
  }
  function priorName(value) {
    if (value === UPLOADED_PRIOR) return STATE.prior ? STATE.prior.name : "";
    const ex = RT.examples.find((e) => e.path === value);
    return ex ? ex.name : String(value || "");
  }
  // The declared parents among the examples, other than the loaded one, and an
  // uploaded prior.
  function declaredParents() {
    const own = STATE.input && STATE.input.mode === "example" ? STATE.input.path : null;
    const cands = RT.examples.filter((e) => e.path !== own).map((e) => ({ value: e.path, lineage: e.lineage }));
    if (STATE.prior) cands.push({ value: UPLOADED_PRIOR, lineage: STATE.prior.lineage });
    return cands.filter((c) => isDeclaredParent(STATE.summary, c.lineage)).map((c) => c.value);
  }
  // The prior defaults to the declared parent when exactly one candidate is
  // one, and otherwise to no prior, which Run waits on.
  function defaultPrior() {
    const parents = declaredParents();
    return parents.length === 1 ? parents[0] : "";
  }
  const priorValues = () => ["", UPLOADED_PRIOR].concat(RT.examples.map((e) => e.path));
  // A prior chosen for one theory is no prior for the next.
  function resetPrior() {
    STATE.params.prior = defaultPrior();
    STATE.priorError = null;
    const op = OPS.find((o) => o.id === STATE.opId);
    if (op && op.needsPrior) renderParams();
  }
  // Why the appraisal cannot run yet, or "" when it can.
  function priorMissing() {
    const v = STATE.params.prior;
    if (!v) return "Choose a prior version first";
    if (v === UPLOADED_PRIOR && !STATE.prior) return "Upload a prior version first";
    return "";
  }

  // ---- persistence (restore the session on refresh) -----------------------
  // The format of the saved session. Before format 2 the app saved the
  // example's place in the list and gave every theory the first example as its
  // prior by default, so a prior saved then may never have been chosen.
  const STATE_FORMAT = 2;
  function stateKey() { return "tf-app-" + (RT ? RT.lang : "x"); }
  function saveState() {
    try {
      localStorage.setItem(stateKey(), JSON.stringify({
        v: STATE_FORMAT, opId: STATE.opId, params: STATE.params, input: STATE.input, ran: !!STATE.ran,
      }));
    } catch (e) { /* quota exceeded, or private mode; not worth failing over */ }
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
      const ex = RT.examples.find((x) => x.path === STATE.input.path); txt = (ex && ex.desc) || "";
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
    // The load validates the theory in full, so the card can say at once
    // whether every operation has a valid theory to work on.
    const v = s.validation;
    const status = !v ? null : v.ok
      ? el("span", { class: "chip valid", title: "Full validation found no problem", text: "valid" })
      : el("span", { class: "chip invalid", title: "Run Validate to list them", text: plural(problemList(v.message || "invalid theory object").length, "problem") });
    return el("div", { class: "summary" }, [
      el("div", { class: "ttl", text: s.title || s.id || "(untitled)" }),
      el("div", { class: "meta" }, [s.id || "", s.maturity ? " · " + s.maturity : "", s.form ? " · " + s.form : ""].join("")),
      el("div", { class: "chips" }, [
        status,
        chip("constructs", c.constructs || 0), chip("propositions", c.propositions || 0),
        chip("predictions", c.predictions || 0), chip("alternatives", c.alternatives || 0),
        chip("assumptions", c.assumptions || 0),
      ]),
    ]);
  }

  function buildSidebar() {
    const exSelect = el("select", { id: "exampleSel", onchange: onExampleChange },
      RT.examples.map((e) => el("option", { value: e.path }, e.name)));
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
        el("p", { class: "note", style: "margin-top:0", text: "Paste into " + RT.langLabel + " to reproduce this result with the installed package." }),
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
        input = el("select", { id: "param-" + p.id, onchange: (e) => { STATE.params[p.id] = e.target.value; saveState(); } },
          p.options.map((o) => el("option", { value: o, selected: o === STATE.params[p.id] ? "" : null }, o)));
        input.value = STATE.params[p.id];
      } else if (p.type === "theory") {
        if (!priorValues().includes(STATE.params[p.id])) STATE.params[p.id] = defaultPrior();  // drop stale persisted value
        wrap.append(priorField(p));
        continue;
      } else {
        STATE.params[p.id] = clampNum(STATE.params[p.id] === undefined ? "" : STATE.params[p.id], p);  // clamp persisted value
        input = el("input", {
          type: "number", id: "param-" + p.id, value: STATE.params[p.id], min: p.min, max: p.max, step: p.step,
          oninput: (e) => { STATE.params[p.id] = clampNum(e.target.value, p); saveState(); },
          // Once the entry is complete, the field shows the value a run uses.
          onchange: (e) => { e.target.value = STATE.params[p.id]; },
        });
      }
      const field = el("label", { class: "field", style: "margin:0" }, [el("span", null, p.label), input]);
      if (op.params.length > 1 && p.type === "number") { rows.append(field); inRow = true; }
      else wrap.append(field);
    }
    if (inRow) wrap.append(rows);
  }
  // A parameter whose step is a whole number, steps or min_link, takes whole
  // values only, and both packages refuse a fractional one. The value typed is
  // rounded, so the run and the code use the same whole number.
  function clampNum(raw, p) {
    let n = raw === "" ? p.default : Number(raw);
    if (!Number.isFinite(n)) n = p.default;
    if (Number.isInteger(p.step)) n = Math.round(n);
    if (typeof p.min === "number") n = Math.max(p.min, n);
    if (typeof p.max === "number") n = Math.min(p.max, n);
    return n;
  }

  // The prior's selector lists the examples and an option to upload a version,
  // and marks the declared parent. Choosing the upload shows a file field. The
  // note beneath says whether the chosen prior is the declared parent.
  function priorField(p) {
    const sel = el("select", { id: "param-prior", onchange: (e) => {
      STATE.params.prior = e.target.value; STATE.priorError = null; saveState(); fillPriorMore();
    } });
    fillPriorOptions(sel);
    return el("div", { class: "prior" }, [
      el("label", { class: "field", style: "margin:0" }, [el("span", null, p.label), sel]),
      fillPriorMore(el("div", { id: "priorMore" })),
    ]);
  }
  function fillPriorOptions(sel) {
    const parents = declaredParents();
    const mark = (v) => (parents.includes(v) ? " (declared parent)" : "");
    sel.replaceChildren(
      el("option", { value: "" }, "Choose a prior version…"),
      ...RT.examples.map((e) => el("option", { value: e.path }, e.name + mark(e.path))),
      el("option", { value: UPLOADED_PRIOR }, STATE.prior ? "Uploaded: " + STATE.prior.name + mark(UPLOADED_PRIOR) : "Upload a prior version…"));
    sel.value = STATE.params.prior;
  }
  function fillPriorMore(more) {
    more = more || $("#priorMore");
    if (!more) return more;
    const cur = STATE.params.prior, parents = declaredParents();
    const kids = [];
    if (cur === UPLOADED_PRIOR) {
      kids.push(el("label", { class: "field", style: "margin:8px 0 0" }, [el("span", null, "Prior version file (YAML / JSON)"),
        el("div", { class: "filewrap" }, el("input", { type: "file", id: "priorFile", accept: ".yaml,.yml,.json", onchange: onPriorFileChange }))]));
    }
    if (STATE.priorError) {
      kids.push(errorBox("Could not load " + STATE.priorError.name + (STATE.prior ? "; the prior is still " + STATE.prior.name : ""), STATE.priorError.err));
    }
    let cls = "note prior-note", txt;
    if (!cur) {
      // A theory that names no parent is not declared an amendment of anything,
      // so the note does not take for granted that it amends some version.
      const named = ((STATE.summary && STATE.summary.version) || {}).parent_id;
      txt = parents.length > 1
        ? "More than one version listed is the declared parent of this theory. Choose the one it amends."
        : named
          ? "This theory names version " + named + " as its parent, which is not listed. Upload that version, or choose the one the theory amends."
          : "This theory names no parent version. To appraise it as an amendment, choose or upload the version it amends.";
    } else if (cur === UPLOADED_PRIOR && !STATE.prior) {
      txt = "Upload the file of the version this theory amends.";
    } else if (parents.includes(cur)) {
      txt = "The declared parent of this theory: its version id is the parent_id the theory names.";
    } else {
      cls = "caution prior-note"; txt = PRIOR_CAUTION;
    }
    kids.push(el("p", { class: cls, id: "priorNote", text: txt }));
    more.replaceChildren(...kids);
    return more;
  }

  // An uploaded prior is read by the engine and held apart from the theory. A
  // file it cannot read leaves the prior uploaded before it, if any.
  async function onPriorFileChange(e) {
    const f = e.target.files && e.target.files[0]; if (!f) return;
    const text = await f.text();
    await withBusy("Loading " + f.name + "…", async () => {
      try {
        const lineage = await RT.loadPriorText(text, f.name);
        STATE.prior = { name: f.name, lineage: lineage || null };
        STATE.priorError = null;
        STATE.params.prior = UPLOADED_PRIOR;
        saveState();
      } catch (err) {
        STATE.priorError = { name: f.name, err };
      }
      const sel = $("#param-prior");
      if (sel) fillPriorOptions(sel);
      fillPriorMore();
    });
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

  const theoryName = (s) => (s && (s.title || s.id)) || "(untitled)";

  // A result and its code belong to the theory they were computed on, so a
  // change of theory removes both.
  function clearResult() {
    if (!resultShown) return;
    resultShown = false;
    $("#output").replaceChildren(el("p", { class: "note", text: "Loaded " + theoryName(STATE.summary) + ". Choose an operation and press Run." }));
    $("#outTitle").textContent = "Result";
    $("#codePanel").style.display = "none";
    $("#codeBlock").textContent = "";
    STATE.ran = false;
  }

  // A load that fails leaves the engine on the theory it held, so the card
  // keeps that theory's summary under the error.
  function loadFailed(name, err) {
    $("#summaryWrap").replaceChildren(
      errorBox("Could not load " + name + (STATE.summary ? "; the active theory is still " + theoryName(STATE.summary) : ""), err),
      summaryCard(STATE.summary));
  }

  async function onExampleChange(e) {
    const ex = RT.examples.find((x) => x.path === e.target.value);
    if (!ex) return;
    await withBusy("Loading " + ex.name + "…", async () => {
      try {
        STATE.summary = await RT.loadExample(ex.path);
      } catch (err) {
        loadFailed(ex.name, err);
        if (STATE.input && STATE.input.mode === "example") e.target.value = STATE.input.path;
        return;
      }
      STATE.input = { mode: "example", path: ex.path };
      STATE.source = await exampleSource(ex.path.split("/").pop(), ex.path);
      $("#summaryWrap").replaceChildren(summaryCard(STATE.summary));
      $("#fileInput").value = "";
      clearResult();
      resetPrior();
      updateExampleDesc(); saveState();
    });
  }
  async function onFileChange(e) {
    const f = e.target.files && e.target.files[0]; if (!f) return;
    const text = await f.text();
    await withBusy("Loading " + f.name + "…", async () => {
      try {
        STATE.summary = await RT.loadTheoryText(text, f.name);
      } catch (err) {
        loadFailed(f.name, err);
        $("#fileInput").value = "";
        return;
      }
      STATE.input = { mode: "upload", name: f.name, text };
      STATE.source = { name: f.name, text };
      $("#summaryWrap").replaceChildren(summaryCard(STATE.summary));
      clearResult();
      resetPrior();
      updateExampleDesc(); saveState();
    });
  }

  // Engine errors arrive as a whole traceback (Pyodide's PythonError) or as R's
  // condition text. The box shows the last line, which names the error, and
  // keeps the full text in a details element. `lead` is an optional node or
  // text placed between the title and the error.
  function errorBox(title, err, lead) {
    const msg = String((err && (err.message || err.toString())) || err);
    const lines = msg.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
    const last = lines.length ? lines[lines.length - 1] : msg;
    const kids = [el("div", { class: "et", text: title })];
    if (lead) kids.push(el("p", { class: "lead" }, lead));
    kids.push(el("div", { class: "last", text: last }));
    if (lines.length > 1) kids.push(el("details", null, [el("summary", null, "Full error"), el("pre", { class: "text", text: msg })]));
    return el("div", { class: "error", role: "alert" }, kids);
  }

  let busy = false;
  async function withBusy(label, fn) {
    if (busy) return; busy = true;
    const btn = $("#runBtn"); const prev = btn ? btn.textContent : "";
    // Lock all theory/operation controls so the UI cannot desync mid-flight.
    const controls = [...document.querySelectorAll("#exampleSel, #fileInput, #viewSrc, #runBtn, .op, #param-prior, #priorFile")];
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
    if (op.needsPrior && priorMissing()) {
      toast(priorMissing());
      const sel = $("#param-prior"); if (sel) sel.focus();
      return;
    }
    const out = $("#output");
    await withBusy("Running…", async () => {
      resultShown = true;
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
        $("#codePanel").style.display = "none";
        out.replaceChildren(failureBox(err));
        console.error(err);
      }
    });
  }

  // Most operations assume a valid theory, so a failure on an invalid one is
  // reported as such, with a way to the Validate operation that lists why.
  function failureBox(err) {
    const v = STATE.summary && STATE.summary.validation;
    if (!v || v.ok) return errorBox("Operation failed", err);
    const n = problemList(v.message || "invalid theory object").length;
    const toValidate = el("button", { class: "linklike", onclick: () => { selectOp("validate"); runOp(); } }, "Run Validate");
    return errorBox("Operation failed on an invalid theory", err,
      ["This theory has " + plural(n, "problem") + ". ", toValidate, " to list them, then correct the file and upload it again."]);
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
  // init has already loaded example 0, and a load that fails leaves it loaded,
  // so a failed restore falls back to it. The returned note says so; start()
  // shows it once the boot overlay, which would hide a toast, is gone.
  async function applyRestore(blog) {
    const saved = loadSaved();
    let note = null;
    const first = RT.examples[0];
    const fallback = (name) => "Could not restore " + name + "; showing " + first.name + " instead";
    STATE.input = STATE.input || { mode: "example", path: first.path };
    if (saved) {
      // A session saved in an earlier format named the example by its place in
      // the list, which an added example can shift, so the place is mapped to
      // that example's path. Its prior is dropped, uploaded theory or not:
      // restoring a default the user may never have chosen would run the
      // appraisal against an unrelated version again. The session is saved
      // again below, so this happens once.
      if (saved.v !== STATE_FORMAT) {
        if (saved.input && saved.input.mode === "example" && typeof saved.input.path !== "string") {
          const idx = Math.min(Math.max(0, saved.input.index | 0), RT.examples.length - 1);
          saved.input = { mode: "example", path: RT.examples[idx].path };
        }
        if (saved.params) delete saved.params.prior;
      }
      if (saved.input && saved.input.mode === "upload" && saved.input.text) {
        try {
          if (blog) blog("Restoring your uploaded theory…");
          STATE.summary = await RT.loadTheoryText(saved.input.text, saved.input.name);
          STATE.input = saved.input;
          STATE.source = { name: saved.input.name, text: saved.input.text };
        } catch (e) {
          STATE.input = { mode: "example", path: first.path };
          note = fallback(saved.input.name || "your uploaded theory");
        }
      } else if (saved.input && saved.input.mode === "example" && saved.input.path !== first.path) {
        const ex = RT.examples.find((x) => x.path === saved.input.path);
        try {
          if (!ex) throw new Error("no longer an example");
          if (blog) blog("Restoring " + ex.name + "…");
          STATE.summary = await RT.loadExample(ex.path);
          STATE.input = { mode: "example", path: ex.path };
        } catch (e) {
          note = fallback(ex ? ex.name : saved.input.path.split("/").pop());
        }
      }
      if (saved.opId && OPS.some((o) => o.id === saved.opId)) STATE.opId = saved.opId;
      if (saved.params) STATE.params = Object.assign({}, STATE.params, saved.params);
    }
    // Ensure the example source is available for the source viewer.
    if (STATE.input.mode === "example" && !STATE.source) {
      STATE.source = await exampleSource(STATE.input.path.split("/").pop(), STATE.input.path);
    }
    // Reflect the restored selection in the UI.
    const sel = $("#exampleSel");
    if (sel && STATE.input.mode === "example") sel.value = STATE.input.path;
    $("#summaryWrap").replaceChildren(summaryCard(STATE.summary));
    for (const b of document.querySelectorAll(".op")) b.classList.toggle("active", b.getAttribute("data-op") === STATE.opId);
    // A saved prior belongs to the saved theory, so it goes with a failed
    // restore, and one that is no longer offered falls back to the default.
    if (note || (STATE.params.prior !== undefined && !priorValues().includes(STATE.params.prior))) STATE.params.prior = defaultPrior();
    updateExampleDesc(); updateOpHelp(); renderParams();
    saveState();
    const op = OPS.find((o) => o.id === STATE.opId);
    if (saved && saved.ran && op && !note && !(op.corpus && !RT.hasCorpus()) && !(op.needsPrior && priorMissing())) await runOp();
    return note;
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
      RT.examples = info.examples; RT.version = info.version; RT.pkgVersion = info.pkgVersion;
      STATE.summary = info.summary || null;
      document.body.append(el("a", { class: "skip-link", href: "#main" }, "Skip to content"));
      document.body.append(buildHeader());
      const main = el("main", { id: "main", tabindex: "-1" }, [buildSidebar(), buildMain()]);
      document.body.append(main);
      // Two distinct versions meet here: RT.pkgVersion is the theoryforge
      // release (stamped into the manifest at build time from DESCRIPTION /
      // pyproject.toml), while RT.version is the interpreter the engine booted
      // (R.version.string / "Python x.y.z"). Keep them apart in the footer so
      // the package version is never mistaken for the interpreter's.
      document.body.append(el("footer", { class: "app", html:
        "theoryforge" + (RT.pkgVersion ? " " + esc(RT.pkgVersion) : "") + " · " + esc(RT.version || "") +
        " via " + esc(RT.engineLabel) + " · running entirely client-side" +
        " · <a href='https://github.com/pablobernabeu/theoryforge'>source</a>" }));
      updateThemeBtn();
      const note = await applyRestore(onProgress);
      $("#boot").classList.add("hidden");
      if (note) toast(note);
    } catch (err) {
      bootFailed(err);
    }
  }

  // Show why the app could not start. A failure before the boot overlay was
  // appended leaves no panel to fill, so one is created.
  function bootFailed(err) {
    console.error(err);
    let b = $("#boot");
    if (!b) { b = el("div", { id: "boot" }); document.body.append(b); }
    b.classList.remove("hidden");
    let lang = "";
    try { lang = RT && RT.langLabel ? RT.langLabel + " " : ""; } catch (e) { lang = ""; }
    b.replaceChildren(el("div", { class: "boot-error", role: "alert" }, [
      el("div", { class: "bt", text: "The app could not start" }),
      el("p", { class: "note", text: "Loading the " + lang + "runtime failed: " + ((err && err.message) || err) }),
      el("button", { class: "btn", onclick: () => location.reload() }, "Reload"),
    ]));
  }

  // The runtimes call TF.start(RT) without awaiting it, so a rejection is
  // caught here, where it can still be shown.
  const startCaught = (runtime) => start(runtime).catch(bootFailed);

  window.TF = { start: startCaught, OPS, DIAG_SVG, util: { el, esc, download, copyText, toast, renderDot, dagToDigraph } };
})();
