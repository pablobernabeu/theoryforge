/* theoryforge interactive apps: shared core (language-agnostic).
 *
 * Responsibilities: the operation registry, the UI, shaping a runtime's raw
 * package output into display sections, rendering, export (SVG/PNG/text), the
 * reproducible-code panel, the link that carries the session and the
 * light/dark theme. A language runtime (r-runtime.js / py-runtime.js) provides
 * booting, theory loading, package calls and the language-specific code
 * snippets, then calls TF.start(runtime). The theory editor (editor.js), the
 * Markdown renderer (markdown.js) and the link encoder (share.js) are separate
 * files that attach themselves to window.TF; the core runs without them.
 */
(function () {
  "use strict";

  // The brand logo has one source of truth (r/theoryforge/man/figures/logo.svg),
  // vendored to vendor/logo.svg by build.mjs so the apps can never drift from it.
  const logoImg = () => el("img", { class: "logo", src: "vendor/logo.svg", alt: "theoryforge logo" });

  // The operations fall into groups, each with a subtitle that says in plain
  // words what its operations are for.
  const GROUPS = [
    { id: "assess", label: "Assess", sub: "Scores and checks of the theory as it is written." },
    { id: "derive", label: "Derive", sub: "What the propositions imply beyond what the theory states." },
    { id: "compare", label: "Compare", sub: "How the theory differs from a rival or from an earlier version." },
    { id: "document", label: "Document", sub: "Diagrams and documents for readers and reviewers." },
    { id: "simulate", label: "Simulate", sub: "How the construct network behaves as a linear dynamical system." },
    { id: "literature", label: "Literature", sub: "How the words of the theory meet the themes of a literature corpus." },
  ];
  const CYCLES = { id: "cycles", label: "cycles", type: "select", default: "refuse", options: ["refuse", "sigma"] };
  const CORPUS = {
    id: "corpus", label: "Corpus", type: "corpus", default: "demo", options: ["demo", "openalex", "upload"],
  };
  const LIT_METHOD = {
    id: "method", label: "method", type: "select", default: "simple_centres", options: ["simple_centres", "components"],
  };

  const OPS = [
    { id: "check", group: "assess", label: "Checklist", desc: "Item statuses, checklist score, gate",
      help: "Reads the file against the 12 items of the checklist, such as a prediction typed point, interval or directional, a definition for every construct or a mechanism for every proposition, and gives each item's status. The checklist score is the weighted mean of the item scores, from 0 to 100, and the gate reports whether either blocking item failed. cycles decides how the items that read claims read a graph with a feedback loop. The theory card and the editor show the score under the default, refuse.",
      params: [CYCLES] },
    { id: "validate", group: "assess", label: "Validate", desc: "Structural + referential checks",
      help: "Runs the package's full validation: required fields, the type of every field and enum membership, plus referential integrity (unique ids, and every proposition, prediction, assumption, evidence and test-outcome reference points to a declared id). Lists every problem found, or confirms that the file is well-formed." },
    { id: "severity", group: "assess", label: "Claim-form rubric", desc: "Pre-data riskiness of each claim's form",
      help: "Applies the claim-form rubric, a pre-data ranking of the form of each prediction's claim, and returns its risk score and its rubric value, the risk score with the directional discount and the bonus for a declared rival. The package calls the rubric value computed_severity. It reads no data, so it is a different quantity from post-data severity." },
    { id: "post_severity", group: "assess", label: "Post-data severity", desc: "How severely each bounded claim passed",
      help: "For each test outcome that records an estimate and its standard error, and whose prediction states in bounds the region its claim allows, computes the severity with which the claim passed: the probability that the test would have given a result less in accord with the claim, had the claim been false at the nearer bound. For a claim with one finite bound this is the post-data severity of Mayo and Spanos (2006). For a claim with two finite bounds the package takes the smaller of the two one-sided values, its own extension, which equals 1 minus the p value of the two one-sided z-tests of equivalence (Lakens, 2017). It uses a normal approximation to the sampling distribution of the estimate. Unlike the claim-form rubric, it depends on the design and the data. A high value does not show that the claim is true, and the checklist does not read it." },
    { id: "redundancy", group: "assess", label: "Redundancy screen", desc: "Lexical overlap of constructs",
      help: "Compares every pair of construct definitions by the Jaccard index and the overlap coefficient of their word sets. A pair is flagged for review when its Jaccard index reaches the checklist's similarity threshold, a near-duplicate, when both definitions hold at least three content words and their overlap coefficient reaches the overlap threshold, one definition contained in the other, when the two constructs carry the same label or when every measure of one is listed for the other." },
    {
      id: "implications", group: "derive", label: "Implied independencies", desc: "What the causal graph implies",
      help: "Derives the conditional independencies that the theory's causal graph implies, the claims data can refute. Only constructs that some proposition relates to another enter the graph: a directed relation (increases, decreases, causes, mediates or moderates) is an arrow, and an association joins two constructs as covariance the theory leaves unexplained. A missing edge is read as no direct effect, so the statements hold only if the graph omits no common cause of two of its constructs. A feedback loop is refused unless cycles is set to sigma, whose statements hold only when every loop has a unique equilibrium.",
      params: [CYCLES],
    },
    {
      id: "entailments", group: "derive", label: "What the graph entails", desc: "Claims the propositions entail or contradict",
      help: "Reads each machine-readable claim of the predictions and phenomena against the causal graph of the propositions. A claim names two constructs and a sign: the effect of x on y, or the association between them, given other constructs where it says so. The signs along the paths of the graph decide whether it entails the claim, contradicts it or leaves it undetermined. The reading assumes a linear model, or at least relations that act in one direction throughout, and that no common cause of two constructs is left out unless an association stands for it. Under cycles sigma, a graph with feedback loops is read on the further assumption that each loop settles to a unique equilibrium, also once the construct whose effect is read is held fixed. It shows what the propositions commit the theory to, and does not show whether the claims hold in data.",
      params: [CYCLES],
    },
    { id: "equivalent", group: "derive", label: "Equivalent models", desc: "Directions independence tests leave open",
      help: "Finds which causal directions of the theory tests of conditional independence bear on. Graphs that imply the same conditional independencies are Markov equivalent, and no test of conditional independence can tell them apart (Verma & Pearl, 1990/2022). An edge is compelled when it points the same way in every equivalent graph, and reversible when some equivalent graph reverses it. Telling the direction of a reversible edge needs an intervention, a temporal order or distributional assumptions such as non-Gaussian errors. The function does not know which constructs a study manipulates. The rule covers acyclic graphs of directed relations only, so a feedback loop or an association leaves the answer undetermined." },
    { id: "sem", group: "derive", label: "SEM (lavaan)", desc: "Compile to lavaan model syntax",
      help: "Compiles the constructs (measurement model) and propositions (structural model) to lavaan model syntax for lavaan::sem(), a starting point for an SEM fit: rename indicators to your columns and check identification." },
    {
      id: "discriminate", group: "compare", label: "Compare with a rival", desc: "What would tell the two accounts apart",
      help: "Sets the theory's causal graph against a rival's: an alternative that states propositions of its own over the theory's constructs, or a rival theory uploaded here, whose constructs are matched to the theory's by id. It lists the conditional independencies one graph implies and the other does not, the pairs of constructs whose effect or association has a different sign under the two and how each claim of the theory reads under each graph. The comparison shows where data could tell the accounts apart. It does not say which account the data favour, and it reads only the propositions each account states.",
      params: [{ id: "rival", label: "Rival", type: "rival" }, CYCLES],
    },
    {
      id: "appraise", group: "compare", label: "Appraise amendment", desc: "Progressive or degenerating, by fixed rules", needsPrior: true,
      help: "Compares what the current theory, treated as the amendment, claims with what a prior version claims, and calls the change progressive or degenerating by fixed rules that borrow Lakatos's terms (Lakatos, 1970). Neutral is theoryforge's label for an amendment that meets neither rule. The rules read what the two files declare, and the prior must be the version before the new predictions were stated. The prior defaults to the version the theory declares as its parent, an example whose version id is the theory's parent_id and whose id the theory's id begins with. Choose another below or upload one. Predictions are matched by id, or by statement and type when an id has changed, so a version of another theory gives a meaningless verdict. Assumptions are compared by statement, so one rewritten under its id is appraised as a new one is, and one moved unchanged to another id is not.",
      params: [{ id: "prior", label: "Prior version", type: "theory" }],
    },
    {
      id: "diagram", group: "document", label: "Diagram", desc: "Nomological net, DAG, workflow…",
      help: "Renders one of ten diagram types. Nomological net, context, workflow, causal DAG, provenance, development roadmap and pipeline are graph diagrams. The venn, rigour and severity types are emitted directly as SVG.",
      params: [{
        id: "type", label: "Diagram type", type: "select", default: "nomological_net",
        options: ["nomological_net", "context", "workflow", "causal_dag", "provenance",
          "development_roadmap", "pipeline", "venn", "rigour", "severity"],
      }],
    },
    { id: "preregister", group: "document", label: "Preregistration", desc: "Hypotheses for a preregistration",
      help: "Generates the theory and hypotheses sections of a preregistration in Markdown. Each hypothesis is listed in file order with its derivation, its claim and what the causal graph says of it, the auxiliary assumptions that protect it, the rivals it is declared to discriminate and its test record. When some prediction records a sampling plan in its test block, a sampling plan section follows, with one line per prediction. The conditional independencies the causal graph implies and the claim-form rubric's value for each prediction come last. cycles decides how a graph with a feedback loop is read: refuse leaves it unread, and sigma reads it by sigma-separation.",
      params: [CYCLES] },
    { id: "dossier", group: "document", label: "Dossier", desc: "The file and its checks, for reviewers",
      help: "Assembles in one Markdown document what the theory file records and what the package derives from it: the checklist report, the claim-form rubric, the test record with each outcome's post-data severity where it can be computed, evidence, claims, equivalent models, rivals, provenance and the preregistration. cycles is passed to the checklist and the derivations, as in the preregistration.",
      params: [CYCLES] },
    {
      id: "simulate", group: "simulate", label: "Simulation", desc: "Dynamical-system trajectory",
      help: "Treats each construct as a state variable and each proposition whose relation is increases, decreases, causes or mediates as a signed coupling, then propagates the linear system and plots the trajectory. causes and mediates state no sign, so they are coupled positively by assumption, and the result lists them. The start is either one value for every construct or an impulse, which starts one chosen construct at 1 and every other at 0, so the chart traces how a change in that construct spreads. The exact method computes the solution at each step from the matrix exponential, whatever dt is. The Euler method takes fixed explicit steps, which drift from the solution when dt is large against the network's rates.",
      params: [
        { id: "method", label: "method", type: "select", default: "exact", options: ["exact", "euler"] },
        { id: "start", label: "start", type: "select", default: "uniform", options: ["uniform", "impulse"],
          labels: { uniform: "every construct at init", impulse: "an impulse in one construct" } },
        { id: "impulse", label: "impulse in", type: "construct", when: { start: "impulse" } },
        { id: "steps", label: "steps", type: "number", default: 30, min: 1, max: 500, step: 1 },
        { id: "dt", label: "dt", type: "number", default: 0.1, min: 0.001, max: 2, step: 0.01 },
        { id: "k", label: "k (coupling)", type: "number", default: 1.0, min: 0, max: 10, step: 0.1 },
        { id: "damping", label: "damping", type: "number", default: 0.5, min: 0, max: 5, step: 0.1 },
        { id: "init", label: "init", type: "number", default: 1.0, min: -10, max: 10, step: 0.1, when: { start: "uniform" } },
      ],
    },
    {
      id: "litmap", group: "literature", label: "Literature map", desc: "Co-occurrence, themes, co-citation", corpus: true,
      help: "Maps a literature corpus: the bundled demonstration corpus, a frozen OpenAlex corpus of 150 works on panic disorder or a corpus file you upload. It counts which keywords co-occur, groups them into themes and counts which references are cited together. min_link is the number of records a pair must share to count as a link. method chooses how themes are formed: simple_centres clusters keywords by the strength of their co-occurrence (Coulter et al., 1998), and components takes each connected group of keywords, which on a real corpus joins nearly all of them into one. min_df leaves out keywords that fewer records carry, and max_df those that more than that share of the records carry, the field's own terms.",
      params: [CORPUS, LIT_METHOD,
        { id: "min_link", label: "min_link", type: "number", default: 2, min: 1, max: 20, step: 1 },
        { id: "min_df", label: "min_df", type: "number", default: 1, min: 1, max: 50, step: 1 },
        { id: "max_df", label: "max_df", type: "number", default: 1, min: 0.05, max: 1, step: 0.05 }],
    },
    {
      id: "landscape", group: "literature", label: "Theory landscape", desc: "Match theory words to lit themes", corpus: true,
      help: "Matches the words of the theory's construct labels and of its alternatives against the keywords of the corpus themes, and names the words behind each match. Each theme is shown with the number of registered accounts that share a word with it: none, one or several. A shared word does not show that an account explains the theme, and a theme that shares no word with any account is not shown to be unexplained. The themes are built as in the literature map, with its other settings at the package's defaults, so min_df and max_df do not apply here.",
      params: [CORPUS, LIT_METHOD, { id: "min_link", label: "min_link", type: "number", default: 2, min: 1, max: 20, step: 1 }],
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
  const esc = (s) => String(s == null ? "" : s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

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
  // A longer message stays longer, so that it can be read before it goes.
  let toastTimer;
  function toast(msg) {
    let t = $(".toast"); if (!t) { t = el("div", { class: "toast", role: "status", "aria-live": "polite" }); document.body.append(t); }
    t.textContent = msg; t.classList.add("show");
    const ms = Math.min(10000, Math.max(2400, 60 * String(msg).length));
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove("show"), ms);
  }
  // A toast about one operation is taken away when the operation changes or a
  // run starts, so that it never stands over another result.
  function clearToast() {
    clearTimeout(toastTimer);
    const t = $(".toast"); if (t) t.classList.remove("show");
  }
  // A short status for screen readers. The result panel is replaced whole on
  // each run, so it is no live region itself, and this one says what changed.
  function announce(msg) {
    const s = $("#liveStatus"); if (!s) return;
    s.textContent = "";
    setTimeout(() => { s.textContent = msg; }, 30);
  }

  // A fetch whose failure says which file and why, rather than handing on an
  // error page as if it were the file. A request that fails before any answer,
  // as when the network drops, names the file too.
  async function fetchOk(url) {
    let r;
    try { r = await fetch(url); } catch (e) { throw new Error("Could not fetch " + url + " (" + ((e && e.message) || e) + ")"); }
    if (!r.ok) throw new Error("Could not fetch " + url + " (HTTP " + r.status + ")");
    return r;
  }
  const fetchJson = async (url) => (await fetchOk(url)).json();
  const fetchBytes = async (url) => new Uint8Array(await (await fetchOk(url)).arrayBuffer());

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
    // A div rather than a header, which would make the dialog's head a second
    // banner landmark beside the page's own.
    const header = el("div", { class: "modal-head" }, [el("h2", { id: titleId, text: title }), closeBtn]);
    const modal = el("div", { class: "modal" + (opts && opts.wide ? " wide" : ""), role: "dialog", "aria-modal": "true", "aria-labelledby": titleId },
      [header, el("div", { class: "body" }, bodyNode)]);
    backdrop.append(modal);
    document.body.append(backdrop);
    const main = $("main"); if (main) main.setAttribute("aria-hidden", "true");
    document.addEventListener("keydown", onModalKey);
    const first = opts && opts.focus ? opts.focus : closeBtn;
    first.focus();
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
  // A load that fails is forgotten, so the next figure tries again rather
  // than meet the same failure for the rest of the session. Its error is
  // marked as a failed load, which another run may get past, unlike a DOT
  // that Graphviz refuses.
  async function graphviz() {
    if (_gv) return _gv;
    if (!_gvPromise) {
      _gvPromise = (async () => {
        const mod = await import(GRAPHVIZ_URL);
        const G = mod.Graphviz || (mod.default && mod.default.Graphviz);
        _gv = await G.load();
        return _gv;
      })().catch((e) => {
        _gvPromise = null;
        const err = e && typeof e === "object" ? e : new Error(String(e));
        try { err.gvLoad = true; } catch (x) { /* a frozen error is reported all the same */ }
        throw err;
      });
    }
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
  // dagitty reads only \" as an escape inside quotes and keeps any other
  // backslash, where DOT also reads a doubled backslash as an escaped pair, so
  // `"a\\" [URL=...]` would end the id early in DOT and leave the rest as
  // attributes. Each quoted id is therefore read by dagitty's rule and written
  // again by DOT's first.
  const DAGITTY_QUOTED = /"((?:\\"|[^"\\]|\\(?!"))*)"/g;
  const DAG_ID = '("(?:[^"\\\\]|\\\\.)*"|[^\\s"]+)';
  const BIDIRECTED_LINE = new RegExp("^([ \\t]*)" + DAG_ID + " <-> " + DAG_ID + "[ \\t]*$", "gm");
  function dagToDigraph(ir) {
    return ir
      .replace(DAGITTY_QUOTED, (m, body) => '"' + body.replace(/\\"/g, '"').replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"')
      .replace(/^\s*dag\s*\{/, "digraph causal_dag {\n  rankdir=LR;\n  node [shape=box, style=rounded];")
      .replace(BIDIRECTED_LINE, "$1$2 -> $3 [dir=both, style=dashed]");
  }

  // ---- result shaping: raw package output -> display sections -------------
  // R's jsonlite auto_unbox collapses length-1 vectors to scalars; coerce any
  // field that must be an array back to one so both runtimes shape identically.
  const asArr = (v) => (Array.isArray(v) ? v : v == null ? [] : [v]);
  // A value that rounds to zero is written 0 whatever its sign, as a small
  // positive one is, rather than -0.
  const num = (x) => {
    if (typeof x !== "number") return String(x);
    if (Number.isInteger(x)) return String(x);
    const s = x.toFixed(3).replace(/\.?0+$/, "");
    return s === "-0" ? "0" : s;
  };
  // A pill takes its colour from its value, as the statuses of the checklist
  // do, unless a tone is given. The tone "plain" is a neutral fill for values
  // that report what a rule found rather than how well the theory fares: the
  // verdicts of the causal readings and the statuses of the landscape.
  function pill(s, tone) { return el("span", { class: "pill " + (tone || String(s).replace(/[^a-z_]/gi, "_")), text: s }); }
  const PLAIN = "plain";
  const NOT_FLAGGED = "not flagged";
  // The landscape's statuses, in words that say what was matched.
  const LANDSCAPE_STATUS = {
    under_theorised: "no account shares a word",
    covered: "one account shares a word",
    crowded: "several accounts share a word",
  };

  function colClass(c) {
    return ["cell", c.num ? "num" : "", c.grow ? "grow" : ""].filter(Boolean).join(" ");
  }
  // A column's `pill` is true for a pill coloured by its value, a tone for a
  // pill of that tone, or a function that gives the tone of a value.
  const pillTone = (c, v) => (typeof c.pill === "function" ? c.pill(v) : typeof c.pill === "string" ? c.pill : undefined);
  function tableSection(title, columns, rows, opts) {
    const thead = el("thead", null, el("tr", null,
      columns.map((c) => el("th", { class: colClass(c), scope: "col", text: c.label || c }))));
    const tbody = el("tbody", null, rows.map((r) =>
      el("tr", null, columns.map((c) => {
        const key = c.key || c;
        const v = r[key];
        if (c.pill) return el("td", { class: colClass(c) }, v === "" || v == null ? "—" : pill(v, pillTone(c, v)));
        if (v && v.nodeType) return el("td", { class: colClass(c) }, v);
        return el("td", { class: colClass(c) }, c.num ? (v == null ? "—" : num(v)) : (Array.isArray(v) ? (v.join(", ") || "—") : (v === "" || v == null ? "—" : String(v))));
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
  const noteSection = (title, text) => ({ kind: "node", node: wrapSection(title, null, el("p", { class: "note", text })) });
  const refusalSection = (title, message) => ({ kind: "node", node: wrapSection(title, null, el("p", { class: "refusal", text: String(message || "") })) });
  // A warning the package gave with its result, or a figure that could not be shown.
  const warningSection = (title, text) => ({ kind: "node", node: wrapSection(title, null, el("p", { class: "caution", role: "status", text })) });

  // A figure is an SVG document that carries text from the theory, and
  // Graphviz turns a DOT attribute such as URL into a link. It is therefore
  // read as XML and inserted as nodes, never as markup, and anything that can
  // run code or lead elsewhere is taken out first: scripts, foreign content,
  // style sheets, animations, every event-handler attribute and every href or
  // src that points outside the figure. A link is replaced by what it holds,
  // since the packages make none. XML 1.0 cannot hold most control
  // characters, U+FFFE or U+FFFF, which a theory's text may carry into the
  // figure, so these are taken out before the figure is read, written as
  // characters or as references. The result is the clean node and whether
  // anything was taken out, or null when the text is no SVG.
  const SVG_DROP = new Set(["script", "foreignobject", "iframe", "object", "embed", "style",
    "animate", "animatemotion", "animatetransform", "set", "handler", "listener"]);
  const XML_BAD_CHAR = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/g;
  const xmlChar = (n) => n === 0x9 || n === 0xA || n === 0xD || (n >= 0x20 && n <= 0xD7FF) ||
    (n >= 0xE000 && n <= 0xFFFD) || (n >= 0x10000 && n <= 0x10FFFF);
  function cleanSvg(svgString) {
    const raw = String(svgString == null ? "" : svgString);
    const text = raw.replace(XML_BAD_CHAR, "").replace(/&#(x[0-9a-f]+|[0-9]+);/gi, (m, n) =>
      (xmlChar(n[0] === "x" || n[0] === "X" ? parseInt(n.slice(1), 16) : parseInt(n, 10)) ? m : ""));
    let doc;
    try { doc = new DOMParser().parseFromString(text, "image/svg+xml"); }
    catch (e) { return null; }
    const root = doc && doc.documentElement;
    if (!root || root.localName !== "svg" || doc.getElementsByTagName("parsererror").length) return null;
    let changed = text !== raw;
    const scrub = (n) => {
      for (const c of [...n.childNodes]) {
        if (c.nodeType !== 1) continue;
        const name = String(c.localName).toLowerCase();
        if (SVG_DROP.has(name)) { c.remove(); changed = true; continue; }
        scrub(c);
        if (name === "a") { c.replaceWith(...c.childNodes); changed = true; }
      }
      for (const at of n.getAttributeNames()) {
        const local = at.replace(/^.*:/, "").toLowerCase();
        if (/^on/.test(local) || ((local === "href" || local === "src") && !/^\s*#/.test(n.getAttribute(at) || ""))) {
          n.removeAttribute(at); changed = true;
        }
      }
    };
    scrub(root);
    return { node: document.importNode(root, true), changed };
  }
  function figureSection(title, svgString, baseName) {
    const clean = cleanSvg(svgString);
    if (!clean) return warningSection(title, "The figure could not be shown: its SVG cannot be read.");
    const fig = el("div", { class: "figure", role: "img", "aria-label": title }, clean.node);
    const svgEl = clean.node;
    // The download is the text the package or Graphviz wrote, unless something
    // had to be taken out of it, when it is the figure as shown.
    const svgText = () => (clean.changed ? new XMLSerializer().serializeToString(svgEl) : svgString);
    const btnSvg = el("button", { class: "btn ghost sm", onclick: () => download(baseName + ".svg", svgText(), "image/svg+xml") }, "SVG");
    const btnPng = el("button", { class: "btn ghost sm", onclick: () => exportPng(svgEl, baseName) }, "PNG");
    return { kind: "node", node: wrapSection(title, [btnSvg, btnPng], fig) };
  }
  // A Graphviz figure. When it cannot be drawn, because Graphviz did not load
  // or refused the DOT, the rest of the result stays and a note takes the
  // figure's place. Only a failed load is worth another run, since a DOT that
  // Graphviz refuses is refused each time.
  async function dotFigure(title, dot, baseName) {
    try { return figureSection(title, await renderDot(dot), baseName); }
    catch (e) {
      const why = String((e && e.message) || e).trim();
      return warningSection(title, e && e.gvLoad
        ? "The figure could not be drawn: " + why + ". Run the operation again to try once more."
        : "Graphviz could not draw this figure: " + why);
    }
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
  // A Markdown document, rendered as HTML by markdown.js with the raw text one
  // click away. The renderer escapes every character of the text and writes
  // only its own tags, so nothing in the document can inject markup.
  function markdownSection(title, content, downloadName) {
    const md = window.TF && window.TF.markdown;
    if (!md) return textSection(title, content, downloadName, "text/markdown");
    const rendered = el("div", { class: "md", html: md.toHtml(content) });
    const raw = el("pre", { class: "text", text: content, hidden: "" });
    const btnR = el("button", { class: "btn ghost sm seg", "aria-pressed": "true" }, "Rendered");
    const btnM = el("button", { class: "btn ghost sm seg", "aria-pressed": "false" }, "Markdown");
    const show = (asRaw) => {
      if (asRaw) { rendered.setAttribute("hidden", ""); raw.removeAttribute("hidden"); }
      else { raw.setAttribute("hidden", ""); rendered.removeAttribute("hidden"); }
      btnR.setAttribute("aria-pressed", asRaw ? "false" : "true");
      btnM.setAttribute("aria-pressed", asRaw ? "true" : "false");
    };
    btnR.addEventListener("click", () => show(false));
    btnM.addEventListener("click", () => show(true));
    const ctrls = [
      el("span", { class: "segwrap", role: "group", "aria-label": "View" }, [btnR, btnM]),
      el("button", { class: "btn ghost sm", onclick: () => copyText(content) }, "Copy"),
      el("button", { class: "btn ghost sm", onclick: () => download(downloadName, content, "text/markdown") }, "Download"),
    ];
    return { kind: "node", node: wrapSection(title, ctrls, el("div", { class: "codewrap" }, [rendered, raw])) };
  }

  // An SVG length in CSS pixels. Graphviz sizes its SVG in points, and a
  // canvas drawn at the point size as if it were pixels comes out at three
  // quarters of the figure's size.
  function cssPx(v) {
    const m = /^\s*([0-9.]+(?:e[-+]?\d+)?)\s*(px|pt|pc|in|cm|mm)?\s*$/i.exec(String(v == null ? "" : v));
    if (!m) return 0;
    const f = { px: 1, pt: 96 / 72, pc: 16, in: 96, cm: 96 / 2.54, mm: 96 / 25.4 }[(m[2] || "px").toLowerCase()];
    return Number(m[1]) * f;
  }
  async function exportPng(svgEl, baseName) {
    try {
      const clone = svgEl.cloneNode(true);
      let w = 0, h = 0;
      const vb = (clone.getAttribute("viewBox") || "").split(/[ ,]+/).map(Number);
      if (vb.length === 4) { w = vb[2]; h = vb[3]; }
      w = cssPx(clone.getAttribute("width")) || w || svgEl.clientWidth || 0;
      h = cssPx(clone.getAttribute("height")) || h || svgEl.clientHeight || 0;
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

  // Whether a run grows or settles, read from the size of the last state
  // against the first (their Euclidean norms): "grow" or "settle" when they
  // differ by more than 1 per cent, and null when they do not, or the run
  // starts at zero or has fewer than two rows, so that it cannot tell.
  function simRegime(trajectory) {
    if (trajectory.length < 2) return null;
    const size = (row) => Math.sqrt(asArr(row).reduce((a, v) => a + (Number.isFinite(v) ? v * v : 0), 0));
    const first = size(trajectory[0]), last = size(trajectory[trajectory.length - 1]);
    if (!(first > 0)) return null;
    return last > first * 1.01 ? "grow" : last < first * 0.99 ? "settle" : null;
  }

  // trajectory line chart (SVG) for simulate. Each construct has its own colour
  // and dash pattern; coincident constructs are nudged apart by a couple of
  // pixels (disclosed in the interpretation) so every series stays visible while
  // the table below keeps the exact values.
  const TRAJ_COLOURS = ["#2fa392", "#d98a14", "#4e79a7", "#b5446e", "#6a8f3a", "#8a5fc0", "#c0563a"];
  const TRAJ_DASHES = ["", "5 3", "1 3", "7 3 1 3", "3 3", "9 4", "2 2"];
  // The axis titles and the caption travel with the exported figure, since
  // the values have no unit and the run rests on settings the theory does not
  // state. `run` holds the run's k, damping, dt and method.
  const METHOD_NAME = { exact: "exact method", euler: "Euler method" };
  const simCaption = (run) => "Linear system, k = " + num(Number(run.k)) + ", damping = " + num(Number(run.damping)) + ", " +
    (METHOD_NAME[run.method] || String(run.method || "euler") + " method") + ". Not fitted to data.";
  function trajectoryChart(states, trajectory, run) {
    run = run || {};
    const n = trajectory.length, m = states.length;
    const shown = states.map((s) => { s = String(s); return s.length > 30 ? s.slice(0, 29) + "…" : s; });
    const maxLabel = shown.reduce((a, s) => Math.max(a, s.length), 0);
    const padR = Math.min(244, Math.max(96, 36 + Math.ceil(maxLabel * 6.6)));
    const pad = { l: 64, r: padR, t: 16, b: 66 };
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
      parts.push(`<text x="${pad.l - 6}" y="${(yy + 3.5).toFixed(1)}" text-anchor="end" fill="${FIG.muted}">${num(Math.round(val * 100) / 100)}</text>`);
    }
    // axes
    parts.push(`<line x1="${pad.l}" y1="${pad.t}" x2="${pad.l}" y2="${H - pad.b}" stroke="${FIG.axis}"/>`);
    parts.push(`<line x1="${pad.l}" y1="${H - pad.b}" x2="${W - pad.r}" y2="${H - pad.b}" stroke="${FIG.axis}"/>`);
    // x labels: first, middle, last step
    const xt = n > 1 ? [[0, "start"], [Math.round((n - 1) / 2), "middle"], [n - 1, "end"]] : [[0, "start"]];
    const axisY = H - pad.b;
    for (const [i, anchor] of xt) parts.push(`<text x="${x(i).toFixed(1)}" y="${axisY + 16}" text-anchor="${anchor}" fill="${FIG.muted}">step ${i}</text>`);
    // Axis titles and the caption.
    const midX = (pad.l + (W - pad.r)) / 2, midY = (pad.t + axisY) / 2;
    const xTitle = "step (dt = " + (run.dt == null ? "?" : num(Number(run.dt))) + ")";
    parts.push(`<text x="${midX.toFixed(1)}" y="${axisY + 34}" text-anchor="middle" fill="${FIG.ink}">${esc(xTitle)}</text>`);
    parts.push(`<text x="16" y="${midY.toFixed(1)}" text-anchor="middle" fill="${FIG.ink}" transform="rotate(-90 16 ${midY.toFixed(1)})">value (no unit)</text>`);
    parts.push(`<text x="8" y="${H - 8}" font-size="11" fill="${FIG.muted}">${esc(simCaption(run))}</text>`);
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

  // What the checklist score describes, as the packages word it (API_SPEC.md,
  // section 4), with the version of the checklist that scored the theory. The
  // card's chip gives its first and last sentences, and the checklist's result
  // opens with all four.
  function scopeText(version) {
    return [
      "The checklist score describes how completely the file states what " + (version ? "checklist " + version : "the checklist") + " asks for.",
      "Most items read whether a field is filled in or how a prediction is labelled, and stated claims are checked against the causal graph.",
      "Test outcomes are read only by the parsimony item, the weights are conventions, and no study has established what difference between two scores is meaningful.",
      "The score does not show that the theory is true or well reasoned.",
    ];
  }
  const GATE_TEXT = "The gate reports whether either blocking item failed: at least one prediction is typed point, interval or directional, and every prediction cites declared propositions whose graph entails any claim it states, with no stated phenomenon contradicted. The labels are the author's.";

  // General "how to read" guidance shown at the top of each operation's result.
  // It complements the sidebar help (what the operation does) by explaining how
  // to read the output that follows. The checklist's guide follows its scope
  // statement (aboutText).
  const RESULT_GUIDE = {
    check: "Read the item statuses first, in the grid and the table below: each item passes, warns or fails on its own criterion. Some items check more than whether a field is filled in. The derivation chain reads each stated claim against the causal graph, diagnosticity sets a claim against a rival's propositions where both are stated, precision asks for two finite bounds and non-redundancy compares the words of the construct definitions. " + GATE_TEXT + " A claim that a feedback loop leaves unread under cycles refuse is not checked, and the derivation chain then warns without blocking. At draft maturity, the gate is advisory: the checklist reports but never blocks. An item with nothing to assess, such as redundancy in a theory with one construct, is marked n/a and left out of the score, which is the weighted mean of the applicable items. The coverage is their share of the checklist's weight. The range beside the score gives the lowest and the highest score with equal weights or with one weight halved or doubled in turn. It is not an interval, and how the file was coded and the rubric's constants lie outside it.",
    validate: "Validation reports structural and referential problems: missing required fields, values of the wrong type or outside the allowed set, duplicate identifiers and cross-references that point to nothing. Validate first: other operations run on an invalid file, but their results may not mean what they say.",
    diagram: "The diagram is rendered from the package's intermediate representation, shown below the figure. Export the figure as SVG or PNG, or copy the representation to render it elsewhere.",
    severity: "The rubric grades each prediction by the form of its claim alone, so it can be read before any data exist. The risk score reflects how much the form of the claim rules out, from an existence claim up to a point. The rubric value lowers it for a directional claim and raises it for predictions that name a registered rival they are declared to discriminate from (the declaration is not checked). A point or interval label without two finite bounds is rated as a directional claim. Longer bars mark riskier claim forms. The values are conventions of the package. How severely a claim is tested depends on the design and the data, which the rubric does not read and post-data severity does.",
    post_severity: "Each row is a test outcome whose prediction states the region its claim allows. The severity is the probability that the test would have given an estimate less in accord with the claim, had the true value lain at the nearer bound, under a normal approximation with the recorded standard error. For a claim with one finite bound this is the post-data severity of Mayo and Spanos (2006). With two finite bounds the package takes the smaller of the two one-sided values, its own extension, which equals 1 minus the p value of the two one-sided z-tests of equivalence (Lakens, 2017). A value near 1 means the estimate would rarely have looked this good were the claim false at its edge. A value of 0.5 or below means the estimate lies at the edge of the region or outside it. It reads the recorded estimate and standard error as they stand, and does not check the design that produced them. It treats the standard error as known, so in small samples it overstates the severity of an estimate inside the region, and it does not account for a subgroup or analysis chosen after seeing the data. A high value does not show that the claim is true.",
    redundancy: "Each pair of constructs is compared by the words their definitions share. The Jaccard index divides the shared words by all the words of the two definitions, and the overlap coefficient divides them by the words of the shorter one, so both run from 0 to 1. A pair is flagged for review when its Jaccard index reaches 0.85, a near-duplicate, when both definitions hold at least three content words and the overlap reaches 0.85, one definition contained in the other, when the two carry the same label or when every measure of one is listed for the other. Near-duplicate constructs blur a theory and inflate its apparent scope. The screen compares words only, so it cannot tell whether two constructs are empirically redundant.",
    appraise: "The verdict applies fixed rules that borrow Lakatos's terms to what the two files declare, and it holds only as far as the recorded outcomes, the registrations and the added_for and protects of each assumption are true. An amendment is progressive when a new prediction derived from content the prior version lacked is corroborated, with no ad hoc assumption added, no corroborated prediction dropped, no unrefuted content lost and no refuted prediction weakened. Unrefuted content is lost when an untested prediction is dropped, when a prediction untested or corroborated in the prior is weakened or its claim is no longer entailed, or when an independence or a signed effect that the prior's graph implies is given up and no failed prediction stated it. An amendment is degenerating when it adds an ad hoc assumption or weakens a refuted prediction without corroborating new content, and neutral otherwise. A prediction is corroborated when some test passes it and none fails it. A new or revised assumption added for an anomaly is ad hoc unless new content it protects is corroborated, and pending while every such prediction is untested. A prediction that only changed its id is a rename, and one derived only from the prior's own propositions is an articulation, so neither counts as new content. The appraisal reads no dates, so it cannot tell a prediction from an accommodation of data already seen, and the prior must be the version before the new predictions were stated. Read the verdict with the refuted new predictions and the post-data severities of the corroborating passes, which are listed below and do not decide it.",
    discriminate: "The two causal graphs are compared on the constructs that some proposition of each relates to another construct. An independence listed below is implied by one graph and not by the other, so a test of it bears on the choice between them. A sign difference is decisive when both graphs fix the sign, and a claim discriminates when one graph entails it and the other contradicts it. Both readings assume linear relations, or relations that act in one direction throughout, and no common cause left out. Markov-equivalent graphs imply the same independencies, and only an intervention or another assumption can separate them. The comparison shows which results would favour one account over the other. It does not say which account the data favour.",
    sem: "The constructs become a measurement model and the propositions a structural model, in lavaan syntax for lavaan::sem(). A closing block fixes at zero the covariances the theory rules out, which lavaan would otherwise free, and comments flag single indicators, moderations and feedback loops. The syntax is a starting point for an SEM fit: rename indicators to your columns and check identification.",
    implications: "Each statement says that two constructs are independent once the constructs after the bar are held fixed, a claim data can refute, for instance by a partial correlation in a linear model. The statements follow from the edges the theory leaves out, so each omission is read as a claim. A conditional statement tested on observed scores is rejected too often when the constructs held fixed are measured with error. A latent-variable model, such as one built on the SEM operation's measurement model, takes that error into account. A pair that no set of constructs separates is listed apart, since the theory implies no independence for it.",
    entailments: "Each row is a claim a prediction or phenomenon states about two constructs. Entailed means the signs along every path or trek of the causal graph agree with the claim, contradicted means they rule it out, and undetermined means paths of unknown or opposite sign meet. Not evaluated marks a claim that names a construct no proposition relates to another, or one that meets a feedback loop under cycles refuse. For an effect claim on an acyclic graph, the 'adjust for' column gives a smallest set of constructs whose adjustment would identify the effect from observational data, or a minimal set when more than 12 constructs are candidates, and never a construct marked latent. Where it reads 'none suffices', no adjustment identifies the effect, though another method, such as the front-door criterion, may still do so. Under cycles sigma, a graph with feedback loops is read on the assumption that each loop settles to a unique equilibrium, also once the construct whose effect is read is held fixed. Entailed means the claim follows from the propositions as written, a check of the theory's internal consistency, not evidence that the claim is true. A claim that restates one proposition is entailed by that proposition alone.",
    equivalent: "A compelled edge points the same way in every graph that implies the same independencies as the theory's, so tests of conditional independence bear on its direction, provided the rest of the graph is right. A reversible edge can be turned round without changing any implied independence, so no test of conditional independence can tell its direction. Telling it needs an intervention, a temporal order or distributional assumptions such as non-Gaussian errors. The function does not know which constructs a study manipulates, so an edge out of a construct that an experiment sets may be listed as reversible although the experiment fixes its direction. An unshielded collider, two constructs that both affect a third and are not joined, fixes the direction of the edges into it.",
    preregister: "The document holds the theory and hypotheses sections of a preregistration. Each hypothesis is listed in file order with its derivation, its claim, the auxiliary assumptions that protect it, the rivals it is declared to discriminate and its test record. A hypothesis that has already been tested is marked as such. When some prediction records a sampling plan, the plans are listed after the hypotheses, one line per prediction. The implied independencies follow, then the claim-form rubric's value for each prediction. Before data collection, complete it with the design, sampling plan, analysis plan and inference criteria that a preregistration template such as PRP-QUANT asks for (Bosnjak et al., 2022), as far as the document leaves them out.",
    dossier: "The dossier gathers what the theory file records and what the package derives from it. The score, gate and verdicts describe the file by fixed rules. Test outcomes, evidence, registrations and declared severities are as the author entered them, and the package checks only whether a recorded estimate agrees with its pass or failure and whether a declared severity exceeds the rubric. It is not an independent audit.",
    simulate: "Each construct is read as a quantity that changes over time. A directed proposition pushes one construct up (increases, and causes and mediates, which state no sign and are taken as positive) or down (decreases) in proportion to another, with one gain k for every coupling, and every construct decays towards zero at the damping rate. Moderates and associates couple nothing. The chart traces the values from the initial state, and the table below holds the numbers. The theory states no parameter values. The gain k and the damping are free settings that together decide whether a feedback loop grows or settles, unsigned relations are taken as positive, the values have no unit and the trajectory is not fitted to data. A linear system cannot show bistability.",
    litmap: "The corpus is mapped three ways: which keywords co-occur, which keywords cluster into themes and which references are cited together. The min_link setting controls how many shared records a pair needs to count as linked. With components, a theme is a connected group of keywords, which separates the small designed corpus into four but joins nearly every keyword of a real corpus into one, and the package then warns. With simple_centres, each theme also has a centrality and a density, which place it in a quadrant of the strategic diagram (Cobo et al., 2011).",
    landscape: "The theory and its rivals are matched against the corpus themes by the words a theme's keywords share with the theory's construct labels, or with a rival's label and key constructs. Words of the theory's title, words most records carry and words such as theory or model do not count. Each theme is shown with how many registered accounts share a word with it: none, one or several. The match is lexical. It shows that an account and a theme have a word in common, and does not show that the account explains what the theme's records report, nor that a theme without a match is unexplained. A theme that several accounts share a word with may call for predictions that discriminate between them, without showing that they compete. The JSON keeps the package's names for the three statuses, under_theorised, covered and crowded, and for the two lists, under_theorised_fronts and redundancy_risk.",
  };
  // Every number in a reading or a table is written as the score on the card
  // is, with no padding: 87.1, not 87.10. fmtNum is kept as the editor's name
  // for it.
  const fmtNum = num;
  const plural = (n, w, pl) => n + " " + (n === 1 ? w : pl || w + "s");
  // "a", "a and b", "a, b and c".
  const listAnd = (xs) => (xs.length < 2 ? xs.join("") : xs.slice(0, -1).join(", ") + " and " + xs[xs.length - 1]);
  // The problems of a full validation. The runtimes pass the packages' own
  // list, since a problem may quote a value of the theory that holds "; ", and
  // the message alone, "invalid theory object: " followed by the problems
  // joined by "; ", is split only when no list came with it. The Validate
  // result, its interpretation, the sidebar chip and the editor all count
  // problems through this one function, which also takes a bare message.
  const problemList = (v) => {
    if (v && typeof v === "object" && Array.isArray(v.problems)) return v.problems.map(String);
    const message = v && typeof v === "object" ? v.message || (v.ok === false ? "invalid theory object" : "") : v;
    return String(message == null ? "" : message).replace(/^invalid theory object:\s*/i, "").split(/; /).filter(Boolean);
  };
  // A post-data severity as the dossier writes it: a value that rounds to 1
  // or to 0 at three decimals is shown as a bound, since neither is reached.
  const sevText = (s) => (typeof s !== "number" ? String(s) : s >= 0.9995 ? "> 0.999" : s <= 0.0005 ? "< 0.001" : s.toFixed(3));
  const bound = (b) => (b == null ? "open" : fmtNum(b));
  // A claim in words, as the tables show it.
  function claimText(c) {
    if (!c) return "—";
    const given = asArr(c.given);
    if (c.kind === "effect") return "effect of " + c.x + " on " + c.y + ": " + c.sign;
    return "association of " + c.x + " and " + c.y + (given.length ? " given " + given.join(", ") : "") + ": " + c.sign;
  }
  const words = (s) => String(s == null ? "" : s).replace(/_/g, " ");

  // A sentence on what a refusal under cycles = refuse means for the result.
  function cycleRefusal(raw, params) {
    return /cycle found/.test(String(raw.message)) && params.cycles !== "sigma"
      ? "The directed relations form a feedback loop, which the default reading refuses. Set cycles to sigma to read the graph by sigma-separation, which assumes that every loop has a unique equilibrium."
      : "Nothing can be derived until the problem the message names is corrected.";
  }

  // The plain-language reading of one post-data severity record.
  function severityReading(r) {
    const lo = r.lower, up = r.upper, est = Number(r.estimate), se = Number(r.se);
    const zl = lo == null || !isFinite(lo) ? Infinity : (est - lo) / se;
    const zu = up == null || !isFinite(up) ? Infinity : (up - est) / se;
    const atLower = zl <= zu;
    const which = atLower ? "lower bound of " + fmtNum(lo) : "upper bound of " + fmtNum(up);
    const less = atLower ? "lower" : "higher";
    const s = Number(r.severity);
    const pct = s >= 0.9995 ? "more than 999 times in 1,000" : s <= 0.0005 ? "fewer than once in 1,000" : Math.round(s * 1000) / 10 + " times in 100";
    let txt = "Had the true value lain at the " + which + ", an estimate " + less + " than " + fmtNum(est) + " would have come up " + pct + ".";
    if (s <= 0.5) txt += " The estimate lies " + (s < 0.5 ? "outside the region the claim allows" : "on its edge") + ", so the test gives the claim no support.";
    return txt;
  }

  // How the checklist read a graph with a feedback loop: as the runtime says
  // it read it, since a package whose check() takes no cycles reads the
  // default whatever was asked, or else as it was asked.
  const checkReading = (raw, params) => (raw && raw.cycles) || params.cycles || "refuse";

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
      // The score first, then the statuses, and the gate as what the blocking
      // items' statuses give. At draft maturity the gate is advisory whatever
      // fails, so it says nothing and the sentence says why.
      let txt = "The checklist score is " + num(r.aggregate_score) + ".";
      txt += " Of the " + (items.length - na) + " applicable items, " + by("pass") + " pass, " + by("warn") + " warn and " + by("fail") + " fail";
      if (r.gate === "advisory") {
        txt += failed.length
          ? ", and the blocking " + (failed.length === 1 ? "item " : "items ") + listAnd(failed) + (failed.length === 1 ? " fails" : " fail") + ", which would block the theory at any later maturity."
          : ", and no blocking item fails.";
        txt += " The theory is at draft maturity, where the gate is advisory and blocks nothing.";
      } else if (failed.length) {
        txt += ". The blocking " + (failed.length === 1 ? "item " : "items ") + listAnd(failed) + (failed.length === 1 ? " fails" : " fail") +
          ", so the gate is " + (r.gate === "blocked" ? "blocked." : r.gate + ".");
      } else {
        txt += ". No blocking item fails, so the gate " + (r.gate === "pass" ? "passes." : "is " + r.gate + ".");
      }
      // A claim the derivation chain could not read is named, since its item
      // warns rather than fails (checklist 3.1).
      const chain = items.find((i) => i.id === "derivation_chain");
      const unread = chain ? asArr(chain.not_checked) : [];
      if (unread.length) {
        txt += " " + plural(unread.length, "prediction") + " (" + unread.join(", ") + ") " + (unread.length === 1 ? "was" : "were") +
          " not checked, since the causal graph has a feedback loop" + (checkReading(raw, params) !== "sigma" ? ". Set cycles to sigma to read the graph on the assumption that each loop settles to a unique equilibrium." : ".");
      }
      // Items with nothing to assess are left out of the score, which then
      // covers less than the whole checklist.
      if (na) txt += " " + (na === 1 ? "One item has" : na + " items have") + " nothing to assess and " + (na === 1 ? "is" : "are") + " left out of the score, which covers " + Math.round(Number(r.coverage) * 100) + " per cent of the checklist's weight.";
      return txt;
    }
    if (opId === "validate") {
      if (raw.ok) return "The file is well-formed: full validation found no problem in its structure, and every internal reference resolves.";
      const errs = problemList(raw);
      return "Validation found " + plural(errs.length, "problem") + ". Each one is listed below.";
    }
    if (opId === "severity") {
      const rows = asArr(raw.rows);
      if (!rows.length) return "This theory has no predictions to grade.";
      const sev = rows.map((r) => Number(r.computed_severity));
      if (rows.length === 1) return "The one prediction, " + rows[0].prediction_id + ", has a rubric value of " + num(sev[0]) + ".";
      const max = Math.max(...sev), mean = sev.reduce((a, b) => a + b, 0) / sev.length;
      // Every prediction at the highest value is named, since the rubric
      // gives many claims the same value.
      const top = rows.filter((r, i) => num(sev[i]) === num(max)).map((r) => r.prediction_id);
      let txt = "Across " + plural(rows.length, "prediction") + ", the rubric value runs from " + num(Math.min(...sev)) + " to " + num(max) + " (mean " + num(mean) + ").";
      if (top.length === rows.length) txt += " Every prediction's claim form has the same value.";
      else txt += top.length === 1 ? " The riskiest claim form, at " + num(max) + ", is that of " + top[0] + "."
        : " The riskiest claim forms, at " + num(max) + ", are those of " + listAnd(top) + ".";
      return txt;
    }
    if (opId === "post_severity") {
      if (raw.ok === false) return "The package refuses the test record as it stands. Full validation lists the same problem.";
      const rows = asArr(raw.result);
      if (!rows.length) return "No test outcome records both an estimate and a standard error for a prediction that states its bounds, so there is no severity to compute. The editor's bounds, estimate and SE fields supply them.";
      const sev = rows.map((r) => Number(r.severity));
      const range = rows.length === 1 ? "Its severity is " + sevText(sev[0]) + "." : "Their severities run from " + sevText(Math.min(...sev)) + " to " + sevText(Math.max(...sev)) + ".";
      return plural(rows.length, "test outcome") + (rows.length === 1 ? " carries" : " carry") + " an estimate, a standard error and a prediction with bounds. " + range;
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
      let txt = "The amendment is " + r.verdict + " by fixed rules that borrow Lakatos's terms, applied to what the two files declare. It introduces " + plural(np, "new prediction") + ", of which " + cn + (cn === 1 ? " is" : " are") + " corroborated and " + ar + (ar === 1 ? " only articulates" : " only articulate") + " the prior's propositions, and " + plural(ah, "ad hoc assumption") + ".";
      if (dr) txt += " It drops " + plural(dr, "prediction") + " of the prior, " + dc + " of them corroborated.";
      // What the verdict is to be read with. A package without these keys
      // leaves them out.
      const anomalies = asArr(r.new_anomalies), refuted = asArr(r.refuted_new);
      if (anomalies.length) txt += " " + (anomalies.length === 1 ? "One prediction the prior held now fails a test: " : anomalies.length + " predictions the prior held now fail a test: ") + listAnd(anomalies) + ".";
      if (refuted.length) txt += " " + (refuted.length === 1 ? "One new prediction failed a test: " : refuted.length + " new predictions failed a test: ") + listAnd(refuted) + ".";
      const sevs = asArr(r.corroborated_new_severity).filter((x) => x && x.id != null);
      if (sevs.length) {
        const known = sevs.filter((x) => typeof x.severity === "number"), unknown = sevs.filter((x) => typeof x.severity !== "number").map((x) => x.id);
        txt += " The lowest post-data severity of each corroborated new prediction's passes is " +
          listAnd(known.map((x) => sevText(x.severity) + " for " + x.id)) +
          (unknown.length ? (known.length ? ", and it is " : "") + "not computed for " + listAnd(unknown) + ", whose passes record no estimate and standard error for a claim with bounds" : "") + ".";
      }
      const prot = asArr(r.protected_only);
      if (prot.length) txt += " The novelty of " + listAnd(prot) + " rests on an assumption that lists " + (prot.length === 1 ? "it" : "them") + " in protects.";
      const pending = asArr(r.assumptions).filter((a) => a && a.class === "pending").map((a) => a.id);
      if (pending.length) txt += " " + (pending.length === 1 ? "The assumption " + pending[0] + " is" : "The assumptions " + listAnd(pending) + " are") + " pending, since " + (pending.length === 1 ? "its" : "their") + " independent predictions are not yet tested.";
      if (!isDeclaredParent(S, priorLineage(params.prior))) txt += " " + PRIOR_CAUTION;
      return txt;
    }
    if (opId === "discriminate") {
      if (raw.ok === false) return cycleRefusal(raw, params);
      const r = raw.result, cn = r.counts || {};
      if (!r.evaluated) return "The two graphs were not compared: " + words(r.reason || "a graph has a feedback loop") + ". Set cycles to sigma to read graphs with feedback loops.";
      const shared = asArr(r.shared).length;
      let txt = "Compared on the " + plural(shared, "construct") + " both accounts name, the graphs differ in " + plural(asArr(r.independencies).length, "implied independence", "implied independencies") +
        " and give " + plural(Number(cn.decisive_effects || 0), "effect") + " and " + plural(Number(cn.decisive_associations || 0), "association") + " decisively different signs. They read " +
        plural(Number(cn.discriminating_claims || 0), "claim") + " of the theory in opposite ways.";
      if (r.markov_equivalent === true) txt += " The two graphs are Markov equivalent, so no observational test of independence separates them.";
      if (asArr(r.only_theory).length || asArr(r.only_rival).length) txt += " Constructs that only one account names are left out of the comparison of independencies.";
      return txt;
    }
    if (opId === "sem") return "The measurement model covers " + plural(c.constructs || 0, "construct") + " and the structural model " + plural(c.propositions || 0, "proposition") + ".";
    if (opId === "implications") {
      if (raw.ok === false) return cycleRefusal(raw, params);
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
    if (opId === "entailments") {
      if (raw.ok === false) return cycleRefusal(raw, params);
      const r = raw.result, claims = asArr(r.claims), cn = r.counts || {};
      if (!claims.length) return "No prediction or phenomenon states a machine-readable claim, so there is nothing to read against the graph. The editor's claim fields add one.";
      const parts = [];
      if (cn.entailed) parts.push("entails " + cn.entailed);
      if (cn.contradicted) parts.push("contradicts " + cn.contradicted);
      if (cn.undetermined) parts.push("leaves " + cn.undetermined + " undetermined");
      let txt = "The predictions and phenomena state " + plural(claims.length, "claim") + ". " +
        (parts.length ? "The causal graph " + listAnd(parts) + "." : "The causal graph gives none of them a verdict.");
      // The reasons are the package's own, as the preregistration words them.
      const why = { malformed_claim: "the claim is incomplete", not_in_graph: "it names a construct that no proposition relates to another",
        feedback_loop: "the causal graph has a feedback loop", graph_refused: "the causal graph cannot be built" };
      const unread = claims.filter((x) => x.verdict === "not_evaluated");
      const bases = [...new Set(unread.map((x) => x.basis))];
      if (unread.length) {
        txt += " " + (unread.length === 1 ? "One claim was" : unread.length + " claims were") + " not evaluated" +
          (bases.length === 1 && why[bases[0]] ? ", since " + (unread.length === 1 ? why[bases[0]] : why[bases[0]].replace(/^it names/, "each names").replace(/^the claim is/, "each claim is")) : "") + ".";
        if (bases.includes("feedback_loop") && params.cycles !== "sigma") txt += " Set cycles to sigma to read a graph with feedback loops, on the assumption that each loop settles to a unique equilibrium.";
      }
      const faith = claims.filter((x) => x.faithfulness === true).length;
      if (faith) txt += " For " + (faith === 1 ? "one verdict" : faith + " verdicts") + ", the reading assumes that routes of unknown or opposite sign do not cancel exactly.";
      return txt;
    }
    if (opId === "equivalent") {
      if (raw.ok === false) return "";
      const r = raw.result, edges = asArr(r.edges);
      if (!r.computed) {
        return r.reason === "associations"
          ? "The theory states an association, which the rule for acyclic graphs of directed relations does not cover, so the testable directions are not determined."
          : "The causal graph has a feedback loop, and the rule for equivalent graphs covers acyclic graphs only, so the testable directions are not determined.";
      }
      if (!edges.length) return "The theory states no directed relation, so there is no direction to test.";
      const rc = Number(r.n_reversible || 0), cc = Number(r.n_compelled || 0);
      return "Of the " + plural(edges.length, "directed edge") + ", " + cc + (cc === 1 ? " is" : " are") + " compelled and " + rc + (rc === 1 ? " is" : " are") + " reversible. " +
        (rc ? "No test of conditional independence can tell the direction of a reversible edge. An intervention, a temporal order or distributional assumptions such as non-Gaussian errors can."
          : "Tests of conditional independence bear on the direction of every edge, provided the rest of the graph is right.");
    }
    if (opId === "preregister") {
      // Every hypothesis has one test-record line (API_SPEC section 11), so both
      // counts are read from the document shown.
      const doc = String(raw.text || "");
      const k = (doc.match(/^ +- Test record: /gm) || []).length;
      const m = (doc.match(/^ +- Test record: already tested:/gm) || []).length;
      if (!k) return "The theory states no prediction, so the document lists no hypothesis.";
      const listed = "The document lists " + k + (k === 1 ? " hypothesis" : " hypotheses");
      if (!m) return listed + (k === 1 ? ", not tested yet." : ", none of them tested yet.");
      if (m === k) return listed + (k === 1 ? ", already tested." : ", all of them already tested.");
      return listed + ", of which " + (m === 1 ? "one has" : m + " have") + " already been tested.";
    }
    if (opId === "dossier") return "The dossier gathers the records of " + (S.title || S.id || "this theory") + " and what the package derives from them: the checklist report, the claim-form rubric, the test record, evidence, provenance and the preregistration.";
    if (opId === "diagram") {
      const t = String(params.type || "");
      const name = t.replace(/_/g, " ");
      const byType = {
        rigour: "A status grid of the twelve checklist items and the gate.",
        severity: "Bars of the claim-form rubric's value for the theory's " + plural(c.predictions || 0, "prediction") + ".",
        venn: "Overlap of the boundary conditions declared on the theory's constructs (up to three).",
        provenance: "The recorded build steps in order.",
        pipeline: "Each prediction linked to its recorded test outcomes, one node for each.",
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
      const impulse = params.start === "impulse";
      let txt = "The " + plural(states.length, "construct") + " evolve over " + plural(r.steps, "step") + " of " + r.dt + " (" + how + "), " +
        (impulse ? "from an impulse in " + params.impulse + ", " : "") + "with values from " + num(lo) + " to " + num(hi) + ".";
      // Whether the run grows or settles rests on k and the damping, which the
      // theory does not state, so the sentence names both.
      const at = "At k = " + num(Number(r.k != null ? r.k : params.k)) + " and damping = " + num(Number(r.damping != null ? r.damping : params.damping)) + ", the values ";
      const regime = simRegime(traj);
      txt += " " + at + (regime ? regime + " over this run. Other settings can reverse this." : "change too little over this run to tell whether they grow or settle.");
      if (coincide.length) {
        const lists = coincide.map((g) => g.map((i) => states[i]).join(", ")).join("; ");
        txt += " Some constructs follow an identical path (" + lists + "), so their lines are drawn with a small offset to keep each visible. " +
          (impulse ? "Constructs that the impulse never reaches stay at zero together, and constructs that receive the same couplings from the same sources move together."
            : "Every construct starts from the same value and every coupling has the same gain, so constructs that receive the same couplings from the same sources move together.") +
          " The coincidence follows from these simplifications and is no reason to change the theory.";
      } else {
        txt += " The trajectories are distinct.";
      }
      const ignored = asArr(r.ignored), opposed = asArr(r.opposed).map(asArr), assumed = asArr(r.assumed_positive);
      if (assumed.length) txt += " " + plural(assumed.length, "proposition") + " (" + assumed.join(", ") + ") state" + (assumed.length === 1 ? "s" : "") + " causes or mediates, which carry no sign, and " + (assumed.length === 1 ? "is" : "are") + " coupled positively by assumption. That choice alone can decide whether a loop grows or settles.";
      if (ignored.length) txt += " " + plural(ignored.length, "proposition") + (ignored.length === 1 ? " couples" : " couple") + " nothing here (" + ignored.map((s) => s || "without id").join(", ") + "): moderation, association and links to undeclared constructs have no term in the model.";
      if (opposed.length) txt += " " + (opposed.length === 1 ? "One pair carries" : opposed.length + " pairs carry") + " both a positive and a negative coupling (" + opposed.map((p) => p.join(" → ")).join("; ") + "), which offset each other.";
      return txt;
    }
    if (opId === "litmap") {
      if (raw.ok === false) return "";
      const r = raw.result;
      let txt = "The corpus holds " + plural(r.n_records, "record") + ", " + plural(asArr(r.keywords).length, "distinct keyword") + " and " + plural(asArr(r.themes).length, "theme") + ", with " + plural(asArr(r.co_citation).length, "co-citation pair") + ".";
      const ft = asArr(r.field_terms);
      if (ft.length) txt += " " + plural(ft.length, "keyword") + " (" + ft.slice(0, 6).join(", ") + (ft.length > 6 ? " and others" : "") + ") " + (ft.length === 1 ? "is" : "are") + " carried by more than max_df of the records and left out as field terms.";
      if (asArr(r.keyword_cooccurrence).length > 60) txt += " The figure draws the 60 strongest of the " + asArr(r.keyword_cooccurrence).length + " keyword links.";
      return txt;
    }
    if (opId === "landscape") {
      if (raw.ok === false) return "";
      const r = raw.result;
      const none = asArr(r.under_theorised_fronts).length, several = asArr(r.redundancy_risk).length;
      return plural(asArr(r.themes).length, "theme") + " mapped. No registered account shares a word with " + none + " of them, and several share a word with " + several + ".";
    }
    return "";
  }

  // The diagram guide depends on the chosen type: the venn, rigour and severity
  // types are emitted directly as SVG, so there is no intermediate representation
  // shown beneath the figure to copy.
  function aboutText(opId, params, raw) {
    if (opId === "check") {
      const rep = raw && raw.report;
      return scopeText(rep && rep.checklist_version).join(" ") + " " + RESULT_GUIDE.check;
    }
    if (opId === "diagram") {
      if (DIAG_SVG.includes(params.type)) return "This diagram type is emitted directly as an SVG figure. Export it as SVG or PNG.";
      if (params.type === "causal_dag") return "The causal DAG is written as dagitty model code, shown below the figure. Graphviz cannot read it, so the figure here is drawn from a translation. Paste the code into dagitty.net, or read it with the dagitty R package, to examine the graph further.";
      return RESULT_GUIDE.diagram;
    }
    return RESULT_GUIDE[opId] || "";
  }

  function buildIntro(opId, raw, params) {
    const about = aboutText(opId, params, raw);
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
    if (opId === "check") {
      const rep = raw.report, read = checkReading(raw, params);
      // The package draws the grid with the default reading of a feedback
      // loop, so it is shown only for that reading, where it agrees with the
      // table.
      if (raw.svg || read !== "sigma") sections.push(figureSection("Checklist grid", raw.svg, theoryId + ".rigour"));
      else sections.push(noteSection("Checklist grid", "The package draws the grid with cycles refuse, its default, so it is not drawn for cycles sigma. The table below gives each item's status under sigma."));
      // The range with other weights, where the checklist reports one.
      const range = Array.isArray(rep.aggregate_range) && rep.aggregate_range.length === 2
        ? " (" + num(rep.aggregate_range[0]) + " to " + num(rep.aggregate_range[1]) + " with equal weights or one weight halved or doubled)" : "";
      const chain = asArr(rep.items).find((i) => i.id === "derivation_chain");
      const unread = chain ? asArr(chain.not_checked) : [];
      sections.push(kvSection("Summary", [
        ["Checklist score", num(rep.aggregate_score) + range],
        ["Coverage", num(rep.coverage) + " of the checklist's weight"],
        ["Gate", pill(rep.gate)],
        ["Blockers failed", String(rep.n_blockers_failed)],
        ["Maturity", rep.maturity],
        ["Cycles", read],
      ].concat(unread.length ? [["Not checked (feedback loop)", unread.join(", ")]] : [])));
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
          el("div", { class: "valid-ok", role: "status" }, "✓ Well-formed. Full validation found no problem in the file's structure or references.")) });
      } else {
        const errs = problemList(v);
        sections.push({ kind: "node", node: wrapSection("Validation", null,
          el("div", { class: "error", role: "alert" }, [
            el("div", { class: "et", text: "Not well-formed: " + plural(errs.length, "problem") }),
            el("ul", { class: "err-list" }, errs.map((e) => el("li", null, e))),
          ])) });
      }
    } else if (opId === "appraise") {
      const r = raw;
      // The reading above the result carries the caution when this is "no".
      const parent = isDeclaredParent(STATE.summary, priorLineage(params.prior));
      sections.push(kvSection("Appraisal", [["Verdict", pill(r.verdict)], ["Prior version", priorName(params.prior) || "—"],
        ["Declared parent", parent ? "yes" : "no"]]));
      // The keys that newer versions of the package add are shown only when
      // the result holds them, so that an older package's result does not
      // read as having none.
      const has = (k) => Object.prototype.hasOwnProperty.call(r, k);
      const ids = (v) => asArr(v).join(", ") || "—";
      const rows = [
        { k: "New predictions", v: ids(r.new_predictions) },
        { k: "Corroborated new", v: ids(r.corroborated_new) },
        has("corroborated_new_severity") && { k: "Lowest post-data severity of their passes", v: asArr(r.corroborated_new_severity)
          .map((x) => x.id + " (" + (typeof x.severity === "number" ? sevText(x.severity) : "not computed") + ")").join(", ") || "—" },
        { k: "Corroborations with a registration recorded", v: ids(r.corroborated_new_registered) },
        has("refuted_new") && { k: "New predictions that failed a test", v: ids(r.refuted_new) },
        has("protected_only") && { k: "New only through protects", v: ids(r.protected_only) },
        { k: "Articulations of prior content", v: ids(r.articulated) },
        { k: "Derived from no proposition", v: ids(r.underived) },
        { k: "Renamed", v: asArr(r.renamed).map((p) => p.prior + " → " + p.new).join(", ") || "—" },
        { k: "Revised", v: asArr(r.revised).map((p) => p.id + " (" + p.change + ")").join(", ") || "—" },
        { k: "Dropped", v: ids(r.dropped) },
        { k: "Dropped corroborated", v: ids(r.dropped_corroborated) },
        { k: "Content lost", v: ids(r.content_lost) },
        has("entailments_lost") && { k: "Entailments lost", v: asArr(r.entailments_lost)
          .map((x) => x.id + " (" + words(x.prior) + " → " + words(x.new) + ")").join(", ") || "—" },
        has("signs_lost") && { k: "Signs lost", v: asArr(r.signs_lost).join("; ") || "—" },
        { k: "New anomalies", v: ids(r.new_anomalies) },
        { k: "Ad hoc assumptions", v: ids(r.ad_hoc_assumptions) },
        { k: "Appraised assumptions", v: asArr(r.assumptions).map((a) => a.id + ": " + (ASSUMPTION_CLASS[a.class] || words(a.class))).join("; ") || "—" },
        { k: "Implications lost", v: asArr(r.implications_lost).join("; ") || "—" },
        { k: "Implications gained", v: asArr(r.implications_gained).join("; ") || "—" },
      ].filter(Boolean);
      sections.push(tableSection("Detail",
        [{ key: "k", label: "category" }, { key: "v", label: "ids", grow: true }],
        rows, { extra: [jsonBtn(theoryId + ".appraisal.json", r)] }));
    } else if (opId === "severity") {
      const rows = asArr(raw.rows);
      sections.push(figureSection("Rubric chart", raw.svg, theoryId + ".severity"));
      if (rows.length) sections.push(tableSection("Rubric value of each prediction",
        [{ key: "prediction_id", label: "prediction" }, { key: "type", label: "type" },
         { key: "risk_score", label: "risk score", num: true }, { key: "computed_severity", label: "rubric value", num: true }],
        rows, { extra: [jsonBtn(theoryId + ".severity.json", rows)] }));
      else sections.push(noteSection("Rubric value of each prediction", "This theory has no predictions."));
    } else if (opId === "post_severity") {
      if (raw.ok === false) sections.push(refusalSection("Post-data severity", raw.message));
      else {
        const rows = asArr(raw.result);
        if (rows.length) {
          sections.push(tableSection("Severity of each bounded claim",
            [{ key: "prediction_id", label: "prediction" }, { key: "n", label: "outcome", num: true },
             { key: "lo", label: "lower" }, { key: "up", label: "upper" },
             { key: "estimate", label: "estimate", num: true }, { key: "se", label: "SE", num: true },
             { key: "sev", label: "severity" }, { key: "reading", label: "reading", grow: true }],
            rows.map((r) => Object.assign({}, r, { n: Number(r.outcome) + 1, lo: bound(r.lower), up: bound(r.upper),
              sev: sevText(r.severity), reading: severityReading(r) })),
            { extra: [jsonBtn(theoryId + ".post_data_severity.json", rows)] }));
        } else sections.push(noteSection("Severity of each bounded claim", "Nothing to compute."));
      }
    } else if (opId === "redundancy") {
      const rows = asArr(raw.rows);
      const cols = [{ key: "a", label: "construct a" }, { key: "b", label: "construct b" },
        { key: "similarity", label: "Jaccard", num: true }, { key: "overlap", label: "overlap", num: true },
        { key: "flag", label: "flag", pill: (v) => (v === NOT_FLAGGED ? PLAIN : undefined) }];
      // Newer checklists say why a pair is flagged.
      if (rows.some((r) => "reason" in r)) cols.push({ key: "reason", label: "reason", grow: true });
      // A pair the screen does not flag is shown as such, not as passing.
      const shown = rows.map((r) => (r.flag === "ok" ? Object.assign({}, r, { flag: NOT_FLAGGED }) : r));
      if (rows.length) sections.push(tableSection("Construct pairs (descending similarity)", cols, shown,
        { extra: [jsonBtn(theoryId + ".redundancy.json", rows)] }));
      else sections.push(noteSection("Redundancy screen", "Fewer than two constructs, so there are no pairs to compare."));
    } else if (opId === "diagram") {
      const ir = raw.ir, type = params.type;
      const isSvg = /^\s*<svg/.test(ir);
      sections.push(isSvg ? figureSection(words(type) + " diagram", ir, theoryId + "." + type)
        : await dotFigure(words(type) + " diagram", type === "causal_dag" ? dagToDigraph(ir) : ir, theoryId + "." + type));
      if (!isSvg) sections.push(textSection(type === "causal_dag" ? "dagitty model code" : "Intermediate representation (Graphviz DOT)", ir, theoryId + "." + type + (type === "causal_dag" ? ".dag" : ".dot"), "text/plain"));
    } else if (opId === "sem") {
      sections.push(textSection("lavaan model syntax", raw.text, theoryId + ".sem.lavaan", "text/plain"));
    } else if (opId === "implications" && raw.ok === false) {
      // A refusal is the package's answer for this theory, so it is shown as a
      // result with the package's message.
      sections.push(refusalSection("Implied independencies", raw.message));
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
    } else if (opId === "entailments") {
      if (raw.ok === false) sections.push(refusalSection("What the graph entails", raw.message));
      else {
        const r = raw.result, claims = asArr(r.claims), cn = r.counts || {};
        sections.push(kvSection("Summary", [
          ["Criterion", r.criterion === "sigma" ? "sigma-separation" : "m-separation"],
          ["Acyclic", r.acyclic ? "yes" : "no"],
          ["Feedback loops", asArr(r.feedback).map((l) => asArr(l).join(", ")).join("; ") || "none"],
          ["Verdicts", ["entailed", "contradicted", "undetermined", "not_evaluated"].map((k) => (cn[k] || 0) + " " + words(k)).join(", ")],
        ]));
        if (claims.length) {
          sections.push(tableSection("Claims",
            [{ key: "who", label: "claim of" }, { key: "what", label: "claim", grow: true }, { key: "derived", label: "derived" },
             { key: "verdict", label: "verdict", pill: (v) => (v === "not evaluated" ? "not_evaluated" : PLAIN) }, { key: "why", label: "basis" }, { key: "adj", label: "adjust for" },
             { key: "via", label: "via" }],
            claims.map((x) => ({
              who: x.source + " " + x.id, what: claimText(x) + (x.faithfulness ? " (assumes no exact cancellation)" : ""),
              derived: x.derived == null ? "—" : String(x.derived), verdict: words(x.verdict), why: words(x.basis),
              adj: x.identified === true ? (asArr(x.adjustment).join(", ") || "none needed") : x.identified === false ? "none suffices" : "—",
              via: asArr(x.via),
            })),
            { extra: [jsonBtn(theoryId + ".entailments.json", r)] }));
        } else sections.push(noteSection("Claims", "No prediction or phenomenon states a claim."));
      }
    } else if (opId === "equivalent") {
      if (raw.ok === false) sections.push(refusalSection("Equivalent models", raw.message));
      else {
        const r = raw.result, edges = asArr(r.edges), vs = asArr(r.v_structures);
        if (!r.computed) sections.push(noteSection("Equivalent models", "Not determined: " + (r.reason === "associations" ? "the theory states an association." : "the causal graph has a feedback loop.")));
        else {
          sections.push(kvSection("Summary", [["Compelled edges", String(r.n_compelled)], ["Reversible edges", String(r.n_reversible)],
            ["Unshielded colliders", vs.map((v) => v.a + " → " + v.collider + " ← " + v.b).join("; ") || "none"]]));
          if (edges.length) sections.push(tableSection("Directed edges",
            [{ key: "from", label: "from" }, { key: "to", label: "to" }, { key: "props", label: "propositions" }, { key: "status", label: "status", pill: PLAIN }],
            edges.map((e) => Object.assign({}, e, { props: asArr(e.propositions) })),
            { extra: [jsonBtn(theoryId + ".equivalent_models.json", r)] }));
        }
      }
    } else if (opId === "discriminate") {
      if (raw.ok === false) sections.push(refusalSection("Compare with a rival", raw.message));
      else {
        const r = raw.result;
        sections.push(kvSection("Summary", [
          ["Rival", r.rival_id || rivalName(params.rival) || "—"],
          ["Criterion", r.criterion === "sigma" ? "sigma-separation" : "m-separation"],
          ["Compared", r.evaluated ? "yes" : "no" + (r.reason ? " (" + words(r.reason) + ")" : "")],
          ["Shared constructs", asArr(r.shared).join(", ") || "none"],
          ["Only in the theory", asArr(r.only_theory).join(", ") || "none"],
          ["Only in the rival", asArr(r.only_rival).join(", ") || "none"],
          ["Markov equivalent", r.markov_equivalent === true ? "yes" : r.markov_equivalent === false ? "no" : "not applicable"],
        ]));
        const ind = asArr(r.independencies), eff = asArr(r.effects), ass = asArr(r.associations), cl = asArr(r.claims);
        if (ind.length) sections.push(tableSection("Independencies one graph implies",
          [{ key: "statement", label: "statement", grow: true }, { key: "implied_by", label: "implied by" }], ind));
        if (eff.length) sections.push(tableSection("Effects whose signs differ",
          [{ key: "x", label: "effect of" }, { key: "y", label: "on" }, { key: "theory", label: "theory" }, { key: "rival", label: "rival" }, { key: "dec", label: "decisive" }],
          eff.map((e) => Object.assign({}, e, { dec: e.decisive ? "yes" : "no" }))));
        if (ass.length) sections.push(tableSection("Associations whose signs differ",
          [{ key: "a", label: "construct a" }, { key: "b", label: "construct b" }, { key: "theory", label: "theory" }, { key: "rival", label: "rival" }, { key: "dec", label: "decisive" }],
          ass.map((e) => Object.assign({}, e, { dec: e.decisive ? "yes" : "no" }))));
        if (cl.length) sections.push(tableSection("The theory's claims under each graph",
          [{ key: "who", label: "claim of" }, { key: "theory", label: "theory", pill: PLAIN }, { key: "rival", label: "rival", pill: PLAIN }, { key: "dis", label: "discriminates" }],
          cl.map((x) => ({ who: x.source + " " + x.id, theory: words(x.theory), rival: words(x.rival), dis: x.discriminates ? "yes" : "no" }))));
        if (!ind.length && !eff.length && !ass.length && !cl.length) sections.push(noteSection("Differences", "The comparison found no difference between the two graphs."));
        sections.push(textSection("discriminate JSON", JSON.stringify(r, null, 2), theoryId + ".discriminate.json", "application/json"));
      }
    } else if (opId === "preregister") {
      sections.push(markdownSection("Preregistration", raw.text, theoryId + ".prereg.md"));
    } else if (opId === "dossier") {
      sections.push(markdownSection("Dossier", raw.text, theoryId + ".dossier.md"));
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
      if (raw.warning) sections.push(warningSection("Euler steps", String(raw.warning) + ". The exact method gives the solution of the same system."));
      sections.push(figureSection("Trajectory", trajectoryChart(states, traj,
        { k: r.k != null ? r.k : params.k, damping: r.damping != null ? r.damping : params.damping, dt: r.dt != null ? r.dt : params.dt, method: r.method || params.method }), theoryId + ".simulate"));
      sections.push(kvSection("Couplings", [
        ["Initial state", states.map((s, i) => s + " " + fmtNum(Number(asArr(r.initial_state)[i]))).join(", ") || "—"],
        ["Assumed positive", asArr(r.assumed_positive).join(", ") || "none"],
        ["Coupling nothing", asArr(r.ignored).map((s) => s || "without id").join(", ") || "none"],
        ["Opposed pairs", asArr(r.opposed).map((p) => asArr(p).join(" → ")).join("; ") || "none"],
      ]));
      const cols = [{ key: "_step", label: "step" }].concat(states.map((s, i) => ({ key: "s" + i, label: s, num: true })));
      const rows = traj.map((row, i) => { const o = { _step: i }; row.forEach((v, j) => (o["s" + j] = v)); return o; });
      sections.push(tableSection("State trajectory (" + (r.method || "euler") + ", steps " + r.steps + ", dt " + r.dt + ")", cols, rows));
    } else if (opId === "litmap") {
      if (raw.ok === false) sections.push(refusalSection("Literature map", raw.message));
      else {
        const r = raw.result;
        const themes = asArr(r.themes), kw = asArr(r.keywords), cooc = asArr(r.keyword_cooccurrence), cocite = asArr(r.co_citation);
        if (raw.warning) sections.push(warningSection("Themes", String(raw.warning)));
        sections.push(kvSection("Summary", [
          ["Corpus", corpusName(params.corpus)],
          ["Method", r.method || params.method || "components"],
          ["Records", String(r.n_records)], ["Distinct keywords", String(kw.length)],
          ["Themes", String(themes.length)], ["Co-citation pairs", String(cocite.length)],
        ].concat(asArr(r.field_terms).length ? [["Field terms left out", asArr(r.field_terms).join(", ")]] : [])));
        const sc = themes.some((t) => "quadrant" in t);
        if (themes.length) sections.push(tableSection(sc ? "Themes (simple centres)" : "Themes (connected components)",
          [{ key: "id", label: "theme" }, { key: "size", label: "size", num: true }]
            .concat(sc ? [{ key: "centrality", label: "centrality", num: true }, { key: "density", label: "density", num: true }, { key: "q", label: "quadrant" }] : [])
            .concat([{ key: "keywords", label: "keywords", grow: true }]),
          themes.map((t) => Object.assign({}, t, { keywords: asArr(t.keywords), q: t.quadrant == null ? "—" : words(t.quadrant) }))));
        if (cooc.length) sections.push(await dotFigure("Keyword co-occurrence", raw.dots.keyword_cooccurrence, theoryId + ".keyword_cooccurrence"));
        if (cocite.length) sections.push(await dotFigure("Co-citation", raw.dots.co_citation, theoryId + ".co_citation"));
        sections.push(textSection("litmap JSON", JSON.stringify(r, null, 2), theoryId + ".litmap.json", "application/json"));
      }
    } else if (opId === "landscape") {
      if (raw.ok === false) sections.push(refusalSection("Theory landscape", raw.message));
      else {
        const r = raw.result;
        const themes = asArr(r.themes);
        if (raw.warning) sections.push(warningSection("Themes", String(raw.warning)));
        sections.push(tableSection("Themes mapped onto the theory",
          [{ key: "id", label: "theme" }, { key: "status", label: "status", pill: PLAIN },
           { key: "focal", label: "focal" }, { key: "terms", label: "shared words" }, { key: "alternatives", label: "alternatives" }, { key: "keywords", label: "keywords", grow: true }],
          themes.map((t) => Object.assign({}, t, { status: LANDSCAPE_STATUS[t.status] || words(t.status), focal: t.focal ? "yes" : "—",
            keywords: asArr(t.keywords), alternatives: asArr(t.alternatives), terms: asArr(t.focal_terms) }))));
        sections.push(kvSection("Flags", [
          ["Corpus", corpusName(params.corpus)],
          ["Themes no account shares a word with", asArr(r.under_theorised_fronts).join(", ") || "—"],
          ["Themes several accounts share a word with", asArr(r.redundancy_risk).join(", ") || "—"],
        ]));
        if (raw.dot) sections.push(await dotFigure("Theme landscape", raw.dot, theoryId + ".theme_landscape"));
        sections.push(textSection("landscape JSON", JSON.stringify(r, null, 2), theoryId + ".landscape.json", "application/json"));
      }
    }
    const intro = buildIntro(opId, raw, params);
    if (intro) sections.unshift(intro);
    return sections;
  }

  // ---- UI ------------------------------------------------------------------
  // `input` is { mode: "example", path }, { mode: "upload", name, text } or,
  // once the editor has changed the theory, { mode: "edited", name, text,
  // format }. `prior` is the uploaded prior version, { name, lineage }, and
  // `priorError` the last failed upload of one, { name, err }. `rival` and
  // `corpus` hold the uploaded rival theory and corpus in the same way.
  let RT, STATE = {
    opId: "check", params: {}, summary: null, input: null, source: null, ran: false,
    prior: null, priorError: null, rival: null, rivalError: null, corpus: null, corpusError: null,
  };
  // Whether the result panel holds an operation's output or error, which a
  // change of theory then clears.
  let resultShown = false;
  let EDITOR = null;

  // Every call into the engine goes through this queue, so a background check
  // from the editor cannot interleave with a load or an operation.
  let engineChain = Promise.resolve(), engineCalls = 0;
  function engine(fn) {
    engineCalls++;
    const p = engineChain.then(fn);
    const done = () => { engineCalls--; };
    engineChain = p.then(done, done);
    return p;
  }

  // ---- the appraisal's prior -----------------------------------------------
  // A candidate prior is the declared parent of the loaded theory when its
  // version id is the parent_id the theory declares and the theory's id equals
  // or begins with the candidate's. The amended panic network's id,
  // panic-network-2026-v2, begins with panic-network-2026. Nearly every
  // example is version v1, so the version alone would make most of them a
  // parent. The runtimes read each example's lineage at start-up, and each
  // load reports the theory's version.
  const UPLOADED = "upload";
  const UPLOADED_PRIOR = UPLOADED;
  // The class of an appraised assumption, as the package names it, with what
  // it means.
  const ASSUMPTION_CLASS = {
    ad_hoc1: "ad_hoc1 (no independent prediction)",
    ad_hoc2: "ad_hoc2 (no independent prediction corroborated)",
    pending: "pending (independent prediction not yet tested)",
    independently_corroborated: "independently corroborated",
  };
  const PRIOR_CAUTION = "This version is not the declared parent of the loaded theory. Predictions are matched by id, or by statement and type when an id has changed, so a version of another theory can make the verdict meaningless. The prior must be the version before the new predictions were stated.";
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
  // A prior chosen for one theory is no prior for the next, and a rival or an
  // impulse construct the new theory lacks is dropped.
  function resetPrior() {
    STATE.params.prior = defaultPrior();
    STATE.priorError = null;
    resetTheoryChoices();
    const op = OPS.find((o) => o.id === STATE.opId);
    if (op && op.params) renderParams();
  }
  function resetTheoryChoices() {
    if (!rivalValues().includes(STATE.params.rival)) STATE.params.rival = defaultRival();
    const cons = constructIds();
    if (!cons.includes(STATE.params.impulse)) STATE.params.impulse = cons[0] || "";
  }
  // Why the appraisal cannot run yet, or "" when it can.
  function priorMissing() {
    const v = STATE.params.prior;
    if (!v) return "Choose a prior version first";
    if (v === UPLOADED_PRIOR && !STATE.prior) return "Upload a prior version first";
    return "";
  }

  // ---- the rival, the impulse and the corpus --------------------------------
  // The alternatives of the loaded theory that state propositions of their
  // own, which discriminate() can read.
  const rivalAlternatives = () => asArr((STATE.summary || {}).alternatives).filter((a) => Number(a.propositions) > 0 && a.id);
  // An empty choice is no choice, so a theory with rivals replaces it with
  // its first.
  const rivalValues = () => rivalAlternatives().map((a) => a.id).concat([UPLOADED]);
  const defaultRival = () => { const a = rivalAlternatives(); return a.length ? a[0].id : STATE.rival ? UPLOADED : ""; };
  function rivalName(v) {
    if (v === UPLOADED) return STATE.rival ? STATE.rival.name : "";
    const a = rivalAlternatives().find((x) => x.id === v);
    return a ? a.id + " (" + a.label + ")" : String(v || "");
  }
  function rivalMissing() {
    const v = STATE.params.rival;
    if (!v) return rivalAlternatives().length ? "Choose a rival first" : "This theory has no alternative with propositions. Upload a rival theory, or add propositions to an alternative in the editor";
    if (v === UPLOADED && !STATE.rival) return "Upload a rival theory first";
    return "";
  }
  const constructIds = () => asArr((STATE.summary || {}).constructs).map((c) => c.id).filter(Boolean);
  function corpusName(key) {
    if (key === UPLOADED) return STATE.corpus ? STATE.corpus.name : "uploaded corpus";
    const c = (RT.corpora || []).find((x) => x.key === key);
    return c ? c.name : String(key || "");
  }
  function corpusMissing() {
    if (STATE.params.corpus === UPLOADED && !STATE.corpus) return "Upload a corpus first";
    return "";
  }
  // Why the chosen operation cannot run yet, and the field to look at.
  function whyNotRunnable(op) {
    if (op.needsPrior && priorMissing()) return [priorMissing(), "#param-prior"];
    if (op.id === "discriminate" && rivalMissing()) return [rivalMissing(), "#param-rival"];
    if (op.corpus && corpusMissing()) return [corpusMissing(), "#param-corpus"];
    if (op.id === "simulate" && STATE.params.start === "impulse" && !STATE.params.impulse) return ["Choose the construct the impulse starts in", "#param-impulse"];
    return null;
  }

  // ---- persistence (restore the session on refresh) -----------------------
  // The format of the saved session. Before format 2 the app saved the
  // example's place in the list and gave every theory the first example as its
  // prior by default, so a prior saved then may never have been chosen.
  const STATE_FORMAT = 2;
  function stateKey() { return "tf-app-" + (RT ? RT.lang : "x"); }
  let saveTimer = null;
  // The session is written for the browser, which the next visit restores,
  // and for this tab, with the fragment the tab's address holds. A reload of
  // the tab finds its own record and restores that, whatever another tab has
  // saved since, and even when the address has not yet caught up with the
  // latest edit. A full or blocked storage is not worth failing over.
  const tabKey = () => stateKey() + "-tab";
  function writeSession() {
    const rec = { v: STATE_FORMAT, opId: STATE.opId, params: STATE.params, input: STATE.input, ran: !!STATE.ran };
    try { localStorage.setItem(stateKey(), JSON.stringify(rec)); } catch (e) { /* not saved */ }
    try { sessionStorage.setItem(tabKey(), JSON.stringify(Object.assign({ link: lastLinkHash }, rec))); } catch (e) { /* not saved */ }
  }
  function loadTab() { try { return JSON.parse(sessionStorage.getItem(tabKey()) || "null"); } catch (e) { return null; } }
  function saveState() {
    writeSession();
    scheduleLink();
  }
  function saveSoon() { clearTimeout(saveTimer); saveTimer = setTimeout(saveState, 400); }
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

  // ---- the link that carries the session ----------------------------------
  // The theory and the chosen operation are encoded in the URL fragment, which
  // the browser never sends to a server. An example travels as its path, any
  // other theory as its text, compressed. Uploaded priors, rivals and corpora
  // stay behind, since a link cannot carry a second file.
  const LINK_PREFIX = "#s=";
  // lastLinkHash is the fragment the app last wrote, so that a fragment
  // pasted into the address bar can be told from the app's own, and a reload
  // from a link opened anew.
  let linkTimer = null, linkInfo = { ok: true, length: 0 }, lastLinkHash = "";
  // A fragment in the address that the app did not write is a link that
  // waits to be opened, which the app's own state does not replace.
  function linkWaiting() {
    const h = (typeof location !== "undefined" && location.hash) || "";
    return h.startsWith(LINK_PREFIX) && h !== lastLinkHash;
  }
  function linkState() {
    const op = OPS.find((o) => o.id === STATE.opId);
    const params = {};
    for (const p of (op && op.params) || []) {
      const v = STATE.params[p.id];
      if (v === undefined || v === UPLOADED) continue;
      params[p.id] = v;
    }
    const inp = STATE.input || {};
    // A new theory travels as one, so that the recipient's copy is still
    // named after its id.
    const theory = inp.mode === "example" ? { example: inp.path }
      : Object.assign({ name: inp.name || "theory.yaml", text: inp.text || "", format: inp.format || (/\.json$/i.test(inp.name || "") ? "json" : "yaml") },
        inp.isNew ? { isNew: true } : {});
    return { v: 1, op: STATE.opId, params, run: !!STATE.ran, theory };
  }
  async function currentLink() {
    const share = window.TF && window.TF.share;
    if (!share || !STATE.input) return null;
    const enc = await share.encode(linkState());
    return { enc, ok: enc.length <= share.LIMIT, length: enc.length, limit: share.LIMIT };
  }
  function scheduleLink() {
    clearTimeout(linkTimer);
    linkTimer = setTimeout(updateLink, 700);
  }
  async function updateLink() {
    try {
      if (linkWaiting()) return;
      const l = await currentLink();
      if (!l || typeof history === "undefined" || !history.replaceState || linkWaiting()) return;
      linkInfo = l;
      const base = location.pathname + location.search;
      lastLinkHash = l.ok ? LINK_PREFIX + l.enc : "";
      history.replaceState(null, "", base + lastLinkHash);
      writeSession();
    } catch (e) { /* no compression stream in this browser: no link */ }
  }
  async function copyLink() {
    const share = window.TF && window.TF.share;
    if (!share) { toast("This browser cannot make a link"); return; }
    // An edit typed just before the click is applied first, so the link
    // carries it.
    if (EDITOR && EDITOR.flush) await EDITOR.flush();
    let l;
    try { l = await currentLink(); } catch (e) { toast("This browser cannot compress the theory for a link"); return; }
    if (!l) return;
    if (!l.ok) {
      openModal("The theory is too large for a link", el("div", { class: "help" }, [
        el("p", null, "Encoded, this theory and its settings take " + l.length.toLocaleString("en-GB") + " characters, and links are kept below " + l.limit.toLocaleString("en-GB") + " so that mail clients and chat programs pass them on whole."),
        el("p", null, "Save the theory as YAML and send the file instead. Anyone can open it here with the upload field."),
      ]));
      return;
    }
    const base = location.href.split("#")[0];
    lastLinkHash = LINK_PREFIX + l.enc;
    history.replaceState(null, "", location.pathname + location.search + lastLinkHash);
    writeSession();
    await copyText(base + LINK_PREFIX + l.enc);
  }
  async function readLink() {
    const share = window.TF && window.TF.share;
    const hash = (typeof location !== "undefined" && location.hash) || "";
    if (!share || !hash.startsWith(LINK_PREFIX)) return null;
    return share.decode(hash.slice(LINK_PREFIX.length));
  }

  function currentSourceText() {
    if (EDITOR && EDITOR.sourceText) { const t = EDITOR.sourceText(); if (t != null) return t; }
    return STATE.source ? STATE.source.text : null;
  }
  async function openSource() {
    if (EDITOR && EDITOR.flush) await EDITOR.flush();
    if (!STATE.source) { toast("No theory loaded"); return; }
    const text = currentSourceText();
    if (text == null) {
      toast(STATE.source.error ? "Could not fetch source (" + STATE.source.error + ")" : "No source available for this input");
      return;
    }
    const name = STATE.source.name;
    const actions = el("div", { class: "modal-actions" }, [
      el("button", { class: "btn ghost sm", onclick: () => copyText(text) }, "Copy"),
      el("button", { class: "btn ghost sm", onclick: () => download(name, text, "text/plain") }, "Download"),
    ]);
    openModal("Source · " + name, el("div", null, [actions, el("pre", { class: "text", text })]), { wide: true });
  }

  // The works that the help texts and the result guides cite, in APA style.
  // Each entry is a list of plain text and italic ({ i: text }) pieces, its DOI
  // and any note that follows the DOI. The methodology page lists them too,
  // except Bosnjak et al. (2022), which the reference page of preregister()
  // gives.
  const WORKS_CITED = [
    [["Bosnjak, M., Fiebach, C. J., Mellor, D., Mueller, S., O'Connor, D. B., Oswald, F. L., & Sokol, R. I. (2022). A template for preregistration of quantitative research in psychology: Report of the joint psychological societies preregistration task force. ",
      { i: "American Psychologist" }, ", ", { i: "77" }, "(4), 602–615."], "10.1037/amp0000879"],
    [["Cobo, M. J., López-Herrera, A. G., Herrera-Viedma, E., & Herrera, F. (2011). An approach for detecting, quantifying, and visualizing the evolution of a research field: A practical application to the Fuzzy Sets Theory field. ",
      { i: "Journal of Informetrics" }, ", ", { i: "5" }, "(1), 146–166."], "10.1016/j.joi.2010.10.002"],
    [["Coulter, N., Monarch, I., & Konda, S. (1998). Software engineering as seen through its research literature: A study in co-word analysis. ",
      { i: "Journal of the American Society for Information Science" }, ", ", { i: "49" }, "(13), 1206–1223."],
      "10.1002/(SICI)1097-4571(1998)49:13<1206::AID-ASI7>3.0.CO;2-F"],
    [["Lakatos, I. (1970). Falsification and the methodology of scientific research programmes. In I. Lakatos & A. Musgrave (Eds.), ",
      { i: "Criticism and the growth of knowledge" }, " (pp. 91–196). Cambridge University Press."], "10.1017/cbo9781139171434.009"],
    [["Lakens, D. (2017). Equivalence tests: A practical primer for ", { i: "t" }, " tests, correlations, and meta-analyses. ",
      { i: "Social Psychological and Personality Science" }, ", ", { i: "8" }, "(4), 355–362."], "10.1177/1948550617697177"],
    [["Mayo, D. G., & Spanos, A. (2006). Severe testing as a basic concept in a Neyman–Pearson philosophy of induction. ",
      { i: "The British Journal for the Philosophy of Science" }, ", ", { i: "57" }, "(2), 323–357."], "10.1093/bjps/axl003"],
    [["Verma, T. S., & Pearl, J. (2022). Equivalence and synthesis of causal models. In H. Geffner, R. Dechter, & J. Y. Halpern (Eds.), ",
      { i: "Probabilistic and causal inference: The works of Judea Pearl" },
      " (pp. 221–236). Association for Computing Machinery."], "10.1145/3501714.3501732",
      " (Original work published 1990)"],
  ];
  function workCited([pieces, doi, note]) {
    const url = "https://doi.org/" + doi;
    const href = "https://doi.org/" + doi.replace(/</g, "%3C").replace(/>/g, "%3E");
    return el("li", null, [
      ...pieces.map((x) => (typeof x === "string" ? x : el("i", null, x.i))), " ",
      el("a", { href, target: "_blank", rel: "noopener" }, url), note,
    ]);
  }

  function openHelp() {
    const li = (t) => el("li", null, t);
    const byGroup = GROUPS.map((g) => [el("h4", null, g.label + ": " + g.sub),
      el("ul", { class: "help-ops" }, OPS.filter((op) => op.group === g.id).map((op) => el("li", null, op.label + ": " + (op.help || op.desc))))]);
    const body = el("div", { class: "help" }, [
      el("p", null, "This app runs the real theoryforge " + RT.langLabel + " package entirely in your browser, via " +
        RT.engineLabel + ". Nothing is uploaded to a server, and the results match running the package locally."),
      el("h3", null, "How to use"),
      el("ol", { class: "steps" }, [
        li("Pick an example theory, upload your own YAML or JSON file, or start a new theory in the editor."),
        li("Edit the theory in the editor's forms or in its source. Each change is validated in full by the package, and the problems appear beside the fields they concern. The checklist score and gate follow, except for a theory larger than the app scores as it loads, which is scored when you ask."),
        li("Choose an operation, adjust any parameters and press Run. Results appear on the right."),
        li("Export the figures (SVG or PNG), the text and JSON results and the " + RT.langLabel + " code that reproduces them. Save writes the theory as YAML with the package's own writer, so the file reads back as the same theory."),
      ]),
      el("p", { class: "note" }, "Your theory, operation and last result are remembered in this browser, so a page refresh restores the session. Copy link puts the theory and the operation in the address after the # sign, which browsers never send to a server, so the link reproduces the view without anything being stored elsewhere. A theory too large for a link is better sent as a file."),
      el("h3", null, "Operations"),
      ...byGroup.flat(),
      el("h3", null, "Works cited"),
      el("ul", { class: "help-refs" }, WORKS_CITED.map(workCited)),
      el("h3", null, "What the app leaves out"),
      el("p", { class: "note" }, "The literature operations read the bundled demonstration corpus, a frozen OpenAlex corpus or a corpus file you upload. The app makes no network request for data, by design: every result then rests on files you can see and save, and nothing about you or your theory reaches another service. OpenAlex and Crossref would answer a browser directly, so the package's fetch_corpus() could run here in principle. To map a fresh corpus, run it in the package and upload the file it writes."),
      el("p", { class: "note" }, "The embedding-based redundancy screen needs an embedding model, which the app does not ship, and the OSF deposit needs a personal access token, which a web page should not hold. Both are in the installed package."),
      el("p", { class: "note" }, ["Documentation: ", el("a", { href: RT.docsUrl, target: "_blank", rel: "noopener" }, RT.docsUrl), ". Source: ",
        el("a", { href: "https://github.com/pablobernabeu/theoryforge", target: "_blank", rel: "noopener" }, "github.com/pablobernabeu/theoryforge"), "."]),
    ]);
    openModal("How to use this app", body, { wide: true });
  }

  function updateExampleDesc() {
    const e2 = $("#exDesc"); if (!e2) return;
    let txt = "";
    const mode = STATE.input && STATE.input.mode;
    if (mode === "upload") txt = "Your uploaded theory.";
    else if (mode === "edited") txt = "Your theory, as edited here. Save writes it as YAML.";
    else if (mode === "example") {
      const ex = RT.examples.find((x) => x.path === STATE.input.path); txt = (ex && ex.desc) || "";
    }
    e2.textContent = txt; e2.style.display = txt ? "" : "none";
  }
  function updateOpHelp() {
    const e2 = $("#opHelp"); if (!e2) return;
    const op = OPS.find((o) => o.id === STATE.opId);
    e2.textContent = op ? (op.help || op.desc) : "";
  }
  // The example selector names a theory that is no example as its first
  // option, so that choosing any example, the one shown before included, is a
  // change that loads it.
  function updateExampleSel() {
    const sel = $("#exampleSel"); if (!sel) return;
    const own = $("#exampleOwn");
    const inp = STATE.input || {};
    if (inp.mode === "example") { if (own) own.setAttribute("hidden", ""); sel.value = inp.path; return; }
    if (own) {
      own.removeAttribute("hidden");
      own.textContent = (inp.mode === "edited" ? "Edited: " : "Uploaded: ") + (inp.name || "your theory");
    }
    sel.value = "";
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

  // The chip of a theory that full validation passes. "Valid" would read as a
  // judgement of the theory.
  const WELL_FORMED_TITLE = "Full validation found no problem in the file's structure or references. This says nothing about whether the theory is valid.";
  function summaryCard(s) {
    if (!s) return el("p", { class: "note", text: "No theory loaded." });
    const c = s.counts || {};
    const chip = (n, one, many) => el("span", { class: "chip", html: "<b>" + n + "</b> " + esc(n === 1 ? one : many || one + "s") });
    // The load validates the theory in full, so the card can say at once
    // whether every operation has a valid theory to work on.
    const v = s.validation;
    const status = !v ? null : v.ok
      ? el("span", { class: "chip valid", title: WELL_FORMED_TITLE, text: "well-formed" })
      : el("span", { class: "chip invalid", title: "Run Validate to list them", text: plural(problemList(v).length, "problem") });
    const edited = STATE.input && STATE.input.mode === "edited";
    const kids = [
      el("div", { class: "ttl", text: s.title || s.id || "(untitled)" }),
      el("div", { class: "meta" }, [s.id || "", s.maturity ? " · " + s.maturity : "", s.form ? " · " + s.form : "", edited ? " · edited" : ""].join("")),
      el("div", { class: "chips" }, [
        status, scoreChip(s),
        chip(c.constructs || 0, "construct"), chip(c.propositions || 0, "proposition"),
        chip(c.predictions || 0, "prediction"), chip(c.alternatives || 0, "alternative"),
        chip(c.assumptions || 0, "assumption"),
        c.phenomena ? chip(c.phenomena, "phenomenon", "phenomena") : null,
        c.outcomes ? chip(c.outcomes, "test outcome") : null,
      ]),
    ];
    kids.push(hashRow(s));
    return el("div", { class: "summary" }, kids);
  }
  // The content hash identifies exactly this content, whatever the layout of
  // the file, and the preregistration and dossier print it too. It arrives
  // after the load, and the row says when the package could not compute it.
  function hashRow(s) {
    const row = el("div", { class: "hash", id: "summaryHash" });
    if (s && s.hash) {
      const short = String(s.hash).replace(/^(sha256:[0-9a-f]{12})[0-9a-f]+([0-9a-f]{6})$/, "$1…$2");
      row.append(el("span", { class: "hk", text: "Content hash " }), el("code", { title: s.hash, text: short }),
        el("button", { class: "linklike sm", onclick: () => copyText(s.hash), "aria-label": "Copy the content hash" }, "copy"));
    } else if (s && s.hashError) {
      row.append(el("span", { class: "hk", title: s.hashError, text: "Content hash not computed: " + s.hashError }));
    } else if (s && s.hashWait === "asked") {
      row.append(el("span", { class: "hk", title: largeNote(s, "hash"), text: "Content hash not computed for a theory this long " }),
        el("button", { class: "linklike sm", type: "button", onclick: () => { requestHash("card"); }, "aria-label": "Compute the content hash" }, "compute it"));
    } else if (s && s.hashWait === "queued") {
      row.append(el("span", { class: "hk", text: "Content hash computing…" }));
    } else row.setAttribute("hidden", "");
    return row;
  }

  // ---- the checklist's score and the content hash on the card ---------------
  // Both are asked of the engine in calls of their own once a theory has
  // loaded, so that the card shows at once and neither holds up a load, a
  // restore or a change in the editor. They run one at a time, each once the
  // engine has no work the user started and the page has been drawn, so an
  // operation started meanwhile goes first, and a result for a theory since
  // replaced is dropped. Both are kept for the text they were computed on, so
  // the same theory is scored and hashed once in a session, and a Checklist
  // run under the default cycles gives the score too. Above a size the runtime sets from what
  // its engine was measured to take (RT.limits), each is computed only when the
  // user asks, and the operation a session or a link holds is not run as the
  // theory opens. The checklist's time grows faster than the theory's
  // constructs, propositions and predictions, so its limit counts those. The
  // hash reads the whole theory, so its limit is on the length of the theory
  // as the package's JSON writer gives it, which the load reports, or null for
  // a theory with more values than the glue measures (its MEASURED_VALUES).
  const LIMITS = { score: 300, hashChars: 50000, values: 20000 };
  const limits = () => Object.assign({}, LIMITS, (RT && RT.limits) || {});
  const theorySize = (s) => {
    const c = (s && s.counts) || {};
    return Number(c.constructs || 0) + Number(c.propositions || 0) + Number(c.predictions || 0);
  };
  const tooLarge = (s, kind) => (kind === "score" ? theorySize(s) > limits().score
    : !!s && (s.chars === null || (typeof s.chars === "number" && s.chars > limits().hashChars)));
  const isLarge = (s) => tooLarge(s, "score") || tooLarge(s, "hash");
  const largeNote = (s, kind) => (kind === "score"
    ? "This theory has " + theorySize(s).toLocaleString("en-GB") + " constructs, propositions and predictions, more than the " +
      limits().score.toLocaleString("en-GB") + " the app scores as it loads, since the checklist can take a while on a theory this large."
    : typeof s.chars === "number"
      ? "Written as JSON, this theory takes " + s.chars.toLocaleString("en-GB") + " characters, more than the " +
        limits().hashChars.toLocaleString("en-GB") + " the app hashes as it loads, since the hash can take a while on a theory this long."
      : "This theory holds more than " + limits().values.toLocaleString("en-GB") +
        " values, more than the app measures as it loads, so its hash is computed only when you ask.");
  // An example is known by its path, and any other theory by its format and
  // its text.
  function cardKey(inp) {
    if (!inp) return null;
    if (inp.mode === "example") return "example\n" + inp.path;
    if (typeof inp.text !== "string") return null;
    return (inp.format || (/\.json$/i.test(inp.name || "") ? "json" : "yaml")) + "\n" + inp.text;
  }
  // The scores and hashes of the theories seen most recently, as many as fit
  // in about 4 million characters of theory text.
  const cardCache = new Map();
  function keepCard(key, got) {
    if (key === null) return;
    const entry = Object.assign({}, cardCache.get(key), got);
    cardCache.delete(key);
    cardCache.set(key, entry);
    let size = 0;
    for (const k of cardCache.keys()) size += k.length;
    while (cardCache.size > 1 && (cardCache.size > 32 || size > 4e6)) {
      const k = cardCache.keys().next().value;
      size -= k.length;
      cardCache.delete(k);
    }
  }
  // What the score call gives, read from a Checklist run.
  const scoreOfReport = (r) => ({
    score: r.aggregate_score, gate: r.gate, version: r.checklist_version,
    failed: asArr(r.items).filter((i) => i.status === "fail").map((i) => i.id),
    warned: asArr(r.items).filter((i) => i.status === "warn").map((i) => i.id),
  });
  // A short wait that lets the browser draw the page first.
  const afterPaint = () => new Promise((resolve) => {
    const later = () => setTimeout(resolve, 0);
    if (typeof requestAnimationFrame === "function") requestAnimationFrame(later); else later();
  });
  // The card's calls wait in a queue of their own, and each goes to the engine
  // only when no other call is queued or running there.
  const cardJobs = [];
  let cardPumping = false;
  function whenIdle(fn) {
    return new Promise((resolve, reject) => { cardJobs.push({ fn, resolve, reject }); pumpCards(); });
  }
  async function pumpCards() {
    if (cardPumping) return;
    cardPumping = true;
    try {
      while (cardJobs.length) {
        while (engineCalls > 0) await engineChain;
        await afterPaint();
        if (engineCalls > 0) continue;
        const job = cardJobs.shift();
        try { job.resolve(await engine(job.fn)); } catch (e) { job.reject(e); }
      }
    } finally { cardPumping = false; }
  }
  // The first and the last sentence of what the score describes.
  const scoreTitle = (ck) => { const t = scopeText(ck && ck.version); return t[0] + " " + t[t.length - 1]; };
  function scoreChip(s) {
    const ck = s && s.check;
    let node;
    if (ck && !("error" in ck)) {
      node = el("span", { class: "chip score", title: scoreTitle(ck), html: "checklist <b>" + esc(num(ck.score)) + "</b> · gate " + esc(ck.gate) });
    } else if (ck) {
      node = el("span", { class: "chip", title: ck.error, text: "not scored" });
    } else if (s && s.scoreWait === "asked") {
      node = el("span", { class: "chip unscored", title: largeNote(s, "score") }, ["not scored ",
        el("button", { class: "linklike sm", type: "button", onclick: () => { requestScore("card"); }, "aria-label": "Score the theory with the checklist" }, "score it")]);
    } else if (s && s.scoreWait === "queued") {
      node = el("span", { class: "chip scoring", title: "The checklist is being computed", text: "scoring…" });
    } else node = el("span", { hidden: "" });
    node.setAttribute("id", "summaryScore");
    return node;
  }
  // The two calls, what each gives the summary, where it is shown and what is
  // said when the user asked for it.
  const CARD = {
    score: {
      call: () => RT.score(), done: (x) => !!x.check, wait: "scoreWait", by: "scoreBy",
      read: (r) => {
        const check = r && typeof r === "object" ? r : { error: "the package gave no score" };
        if ("error" in check) check.error = String(check.error || "the checklist stopped without a message");
        return { check };
      },
      failed: (err) => ({ check: { error: errorHeadline(err) } }),
      show: (s) => { const chip = $("#summaryScore"); if (chip) chip.replaceWith(scoreChip(s)); if (EDITOR && EDITOR.onSummary) EDITOR.onSummary(s); },
      focus: () => $("#summaryScore"),
      said: (s) => ("error" in s.check ? "The checklist could not score the theory: " + s.check.error
        : "Checklist score " + num(s.check.score) + ", gate " + s.check.gate),
    },
    hash: {
      call: () => RT.contentHash(), done: (x) => !!(x.hash || x.hashError), wait: "hashWait", by: "hashBy",
      read: (r) => (r && typeof r.hash === "string" ? { hash: r.hash } : { hashError: String((r && r.error) || "the package gave no hash") }),
      failed: (err) => ({ hashError: errorHeadline(err) }),
      show: () => { const row = $("#summaryHash"); if (row) row.replaceWith(hashRow(STATE.summary)); },
      focus: () => $("#summaryHash button") || $("#summaryHash"),
      said: (s) => (s.hash ? "Content hash computed" : "Content hash not computed: " + s.hashError),
    },
  };
  // After a change the user asked for, the focus moves to what replaced the
  // control they used, on the card or in the editor, so it does not fall back
  // to the page. A user who has moved on to something else keeps the focus
  // there, and the result is only announced.
  function showCard(s, kind) {
    const c = CARD[kind];
    if (STATE.summary !== s) return;
    c.show(s);
    const by = s[c.by];
    const a = document.activeElement;
    let up = a;
    while (up && up !== document.body) up = up.parentNode;
    if (a && a !== document.body && up) return;
    if (by === "editor" && EDITOR && EDITOR.focusScore && kind === "score") EDITOR.focusScore();
    else if (by === "card") {
      const n = c.focus();
      if (n) { if (n.tagName !== "BUTTON") n.setAttribute("tabindex", "-1"); n.focus(); }
    }
  }
  function takeCard(s, kind, got) {
    const c = CARD[kind];
    Object.assign(s, got);
    delete s[c.wait];
    showCard(s, kind);
    if (s[c.by] && STATE.summary === s) announce(c.said(s));
    delete s[c.by];
  }
  // Ask for the loaded theory's score or hash, unless it is known or the
  // theory is too large to ask for it unbidden. `by` names where the user
  // asked for it, the card or the editor, and is absent for the automatic
  // request. The result is a promise of the summary once it holds the answer.
  function requestCard(kind, by) {
    const c = CARD[kind], s = STATE.summary;
    const can = RT && typeof (kind === "score" ? RT.score : RT.contentHash) === "function";
    if (!s || !can || c.done(s)) return Promise.resolve(s);
    const key = cardKey(STATE.input), known = key === null ? null : cardCache.get(key);
    if (by) s[c.by] = by;
    if (known && c.done(known)) {
      takeCard(s, kind, kind === "score" ? { check: known.check } : known.hash ? { hash: known.hash } : { hashError: known.hashError });
      return Promise.resolve(s);
    }
    if (!by && tooLarge(s, kind)) { s[c.wait] = "asked"; showCard(s, kind); return Promise.resolve(s); }
    if (s[c.wait] === "queued" && s[kind + "Job"]) { showCard(s, kind); return s[kind + "Job"]; }
    s[c.wait] = "queued";
    showCard(s, kind);
    if (by && kind === "score") toast("Scoring " + theoryName(s) + " with the checklist, which can take a while for a theory this large");
    // The user's request is work the user started, so it goes to the engine
    // at once, and the automatic one waits until the engine is idle.
    const call = async () => {
      if (by) await afterPaint();
      return STATE.summary === s && !c.done(s) ? c.call() : null;
    };
    s[kind + "Job"] = (by ? engine(call) : whenIdle(call)).then((r) => {
      if (r === null || r === undefined) return s;
      const got = c.read(r);
      keepCard(key, got);
      if (STATE.summary === s && !c.done(s)) takeCard(s, kind, got);
      return s;
    }, (err) => {
      if (STATE.summary === s && !c.done(s)) takeCard(s, kind, c.failed(err));
      return s;
    });
    return s[kind + "Job"];
  }
  const requestScore = (by) => requestCard("score", by);
  const requestHash = (by) => requestCard("hash", by);
  function refreshSummary() {
    const w = $("#summaryWrap"); if (w) w.replaceChildren(summaryCard(STATE.summary));
    if (EDITOR && EDITOR.onSummary) EDITOR.onSummary(STATE.summary);
  }

  function buildSidebar() {
    const exSelect = el("select", { id: "exampleSel", onchange: onExampleChange },
      [el("option", { value: "", id: "exampleOwn", disabled: "", hidden: "" }, "Your theory")]
        .concat(RT.examples.map((e) => el("option", { value: e.path }, e.name))));
    const fileInput = el("input", { type: "file", id: "fileInput", accept: ".yaml,.yml,.json", onchange: onFileChange });
    const summaryWrap = el("div", { id: "summaryWrap" }, summaryCard(STATE.summary));

    const opGroups = GROUPS.map((g) => {
      const ops = OPS.filter((op) => op.group === g.id);
      return el("div", { class: "opgroup", role: "group", "aria-labelledby": "grp-" + g.id }, [
        el("div", { class: "gh" }, [el("h3", { id: "grp-" + g.id, text: g.label }), el("p", { class: "gs", text: g.sub })]),
        el("div", { class: "ops" }, ops.map((op) =>
          el("button", {
            class: "op" + (op.id === STATE.opId ? " active" : ""), "data-op": op.id,
            onclick: () => selectOp(op.id), "aria-pressed": op.id === STATE.opId ? "true" : "false",
            disabled: op.corpus && !RT.hasCorpus() ? "" : null,
            title: op.corpus && !RT.hasCorpus() ? "Needs a corpus" : op.desc,
          }, [el("span", { class: "on", text: op.label }), el("span", { class: "od", text: op.desc })]))),
      ]);
    });

    const paramsWrap = el("div", { class: "params", id: "paramsWrap" });
    const runBtn = el("button", { class: "btn", id: "runBtn", onclick: runOp }, "Run ▸");

    const viewSrc = el("button", { class: "btn ghost sm", id: "viewSrc", onclick: openSource }, "View source");
    const link = el("button", { class: "btn ghost sm", id: "copyLink", onclick: copyLink, title: "Copy a link that reproduces this view" }, "Copy link");
    const editBtns = window.TF && window.TF.editor ? [
      el("button", { class: "btn ghost sm", id: "editTheory", onclick: () => showTab("editor") }, "Edit theory"),
      el("button", { class: "btn ghost sm", id: "newTheory", onclick: () => { showTab("editor"); EDITOR && EDITOR.newTheory(); } }, "New theory"),
    ] : [];

    return el("div", { class: "sidebar" }, [
      el("div", { class: "panel" }, [
        el("h2", null, "Theory"),
        el("label", { class: "field" }, [el("span", null, "Example theory"), exSelect]),
        el("p", { class: "exdesc", id: "exDesc" }, ""),
        el("label", { class: "field" }, [el("span", null, "…or upload your own (YAML / JSON)"), el("div", { class: "filewrap" }, fileInput)]),
        summaryWrap,
        el("div", { class: "srcrow" }, editBtns.concat([viewSrc, link])),
      ]),
      el("div", { class: "panel" }, [
        el("h2", null, "Operation"),
        el("div", { id: "opGrid" }, opGroups),
        el("p", { class: "ophelp", id: "opHelp" }, ""),
        paramsWrap,
        el("div", { class: "runrow" }, runBtn),
      ]),
    ]);
  }

  // First-run welcome: the rationale for the package and a short set of steps,
  // shown until the first operation is run.
  function welcomeBlock() {
    const li = (t) => el("li", null, t);
    return el("div", { class: "welcome" }, [
      el("h3", null, "Develop a theory you can test"),
      el("p", null, "theoryforge reads a theory written as structured data and checks what the file states: which fields are filled in, what its propositions imply as a causal graph, how it differs from a rival or an earlier version, and whether an amendment meets fixed rules that borrow Lakatos's terms. None of these checks shows that a theory is true or well reasoned, and the checklist's weights and thresholds have not been validated against expert judgement."),
      el("ol", { class: "welcome-steps" }, [
        li("Pick an example theory on the left, upload your own YAML or JSON file, or press New theory to build one in the editor without writing YAML."),
        li("Choose an operation and adjust any parameters."),
        li(["Press ", el("b", null, "Run"), ". Each result is explained here and can be exported as a figure and as " + RT.langLabel + " code."]),
      ]),
      el("p", { class: "note" }, ["For what each operation does, open ",
        el("button", { class: "linklike", onclick: openHelp }, "the guide"), "."]),
    ]);
  }

  // The result and the editor share the main column as two tabs.
  function showTab(which) {
    const tabs = [["result", "#tabResult", "#panelResult"], ["editor", "#tabEditor", "#panelEditor"]];
    for (const [id, t, p] of tabs) {
      const tab = $(t), panel = $(p);
      if (!tab || !panel) continue;
      const on = id === which;
      tab.setAttribute("aria-selected", on ? "true" : "false");
      tab.setAttribute("tabindex", on ? "0" : "-1");
      if (on) panel.removeAttribute("hidden"); else panel.setAttribute("hidden", "");
    }
    if (which === "editor" && EDITOR) EDITOR.open();
  }
  function onTabKey(e) {
    if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
    const next = $("#tabResult").getAttribute("aria-selected") === "true" ? "editor" : "result";
    showTab(next);
    $(next === "editor" ? "#tabEditor" : "#tabResult").focus();
  }

  function buildMain() {
    const resultPanel = el("div", { id: "panelResult", role: "tabpanel", "aria-labelledby": "tabResult" }, [
      el("div", { class: "panel" }, [
        el("div", { class: "outhead" }, [el("h2", { id: "outTitle" }, "Result"), el("span", { class: "grow" })]),
        el("div", { id: "staleNote", class: "caution stale", hidden: "" }, "The theory has changed since this result was computed. Press Run to update it."),
        el("div", { id: "output" }, welcomeBlock()),
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
    if (!(window.TF && window.TF.editor)) return el("div", { class: "maincol" }, [resultPanel]);
    const tabs = el("div", { class: "tabs", role: "tablist", "aria-label": "Main view", onkeydown: onTabKey }, [
      el("button", { role: "tab", id: "tabResult", "aria-selected": "true", "aria-controls": "panelResult", onclick: () => showTab("result") }, "Result"),
      el("button", { role: "tab", id: "tabEditor", "aria-selected": "false", "aria-controls": "panelEditor", tabindex: "-1", onclick: () => showTab("editor") }, "Editor"),
    ]);
    const editorPanel = el("div", { id: "panelEditor", role: "tabpanel", "aria-labelledby": "tabEditor", hidden: "" });
    EDITOR = window.TF.editor.create(editorHost(), editorPanel);
    return el("div", { class: "maincol" }, [tabs, resultPanel, editorPanel]);
  }

  // ---- parameters -----------------------------------------------------------
  const paramShown = (p) => !p.when || Object.keys(p.when).every((k) => STATE.params[k] === p.when[k]);
  function renderParams() {
    const wrap = $("#paramsWrap"); if (!wrap) return;
    wrap.innerHTML = "";
    const op = OPS.find((o) => o.id === STATE.opId);
    if (!op || !op.params) return;
    const rows = el("div", { class: "row" });
    let inRow = false;
    for (const p of op.params) {
      if (p.type === "theory") {
        if (!priorValues().includes(STATE.params[p.id])) STATE.params[p.id] = defaultPrior();  // drop stale persisted value
        wrap.append(priorField(p));
        continue;
      }
      if (p.type === "rival") { wrap.append(rivalField(p)); continue; }
      if (p.type === "corpus") { wrap.append(corpusField(p)); continue; }
      if (!paramShown(p)) continue;
      let input;
      if (p.type === "select") {
        if (!p.options.includes(STATE.params[p.id])) STATE.params[p.id] = p.default;  // drop stale persisted value
        input = el("select", { id: "param-" + p.id, onchange: (e) => {
          STATE.params[p.id] = e.target.value; saveState();
          if (op.params.some((q) => q.when && p.id in q.when)) renderParams();
        } }, p.options.map((o) => el("option", { value: o, selected: o === STATE.params[p.id] ? "" : null }, (p.labels && p.labels[o]) || o)));
        input.value = STATE.params[p.id];
      } else if (p.type === "construct") {
        const cons = asArr((STATE.summary || {}).constructs).filter((c) => c.id);
        if (!cons.some((c) => c.id === STATE.params[p.id])) STATE.params[p.id] = cons.length ? cons[0].id : "";
        input = el("select", { id: "param-" + p.id, onchange: (e) => { STATE.params[p.id] = e.target.value; saveState(); } },
          cons.length ? cons.map((c) => el("option", { value: c.id }, c.label ? c.id + " (" + c.label + ")" : c.id))
            : [el("option", { value: "" }, "The theory has no construct")]);
        input.value = STATE.params[p.id];
      } else {
        STATE.params[p.id] = clampNum(STATE.params[p.id] === undefined ? "" : STATE.params[p.id], p);  // clamp persisted value
        input = el("input", {
          type: "number", id: "param-" + p.id, value: STATE.params[p.id], min: p.min, max: p.max, step: p.step,
          oninput: (e) => { STATE.params[p.id] = clampNum(e.target.value, p); saveSoon(); },
          // Once the entry is complete, the field shows the value a run uses.
          onchange: (e) => { e.target.value = STATE.params[p.id]; saveState(); },
        });
      }
      const field = el("label", { class: "field", style: "margin:0" }, [el("span", null, p.label), input]);
      if (p.type === "number") { rows.append(field); inRow = true; }
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

  // A file field for an upload that a parameter waits on.
  function uploadField(label, id, onchange) {
    return el("label", { class: "field", style: "margin:8px 0 0" }, [el("span", null, label),
      el("div", { class: "filewrap" }, el("input", { type: "file", id, accept: ".yaml,.yml,.json", onchange }))]);
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
    if (cur === UPLOADED_PRIOR) kids.push(uploadField("Prior version file (YAML / JSON)", "priorFile", onPriorFileChange));
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
        const lineage = await engine(() => RT.loadPriorText(text, f.name));
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

  // The rival is an alternative of the theory that states propositions, or a
  // rival theory uploaded here.
  function rivalField(p) {
    if (!rivalValues().includes(STATE.params.rival)) STATE.params.rival = defaultRival();
    const alts = rivalAlternatives();
    const sel = el("select", { id: "param-rival", onchange: (e) => { STATE.params.rival = e.target.value; STATE.rivalError = null; saveState(); renderParams(); } },
      [el("option", { value: "" }, alts.length ? "Choose a rival…" : "No alternative states propositions")]
        .concat(alts.map((a) => el("option", { value: a.id }, a.id + " (" + a.label + ")")))
        .concat([el("option", { value: UPLOADED }, STATE.rival ? "Uploaded: " + STATE.rival.name : "Upload a rival theory…")]));
    sel.value = STATE.params.rival;
    const more = [];
    if (STATE.params.rival === UPLOADED) more.push(uploadField("Rival theory file (YAML / JSON)", "rivalFile", onRivalFileChange));
    if (STATE.rivalError) more.push(errorBox("Could not load " + STATE.rivalError.name + (STATE.rival ? "; the rival is still " + STATE.rival.name : ""), STATE.rivalError.err));
    const note = STATE.params.rival === UPLOADED
      ? "An uploaded rival's constructs are matched to this theory's by id, so the two files must use the same construct ids."
      : alts.length ? "An alternative's own propositions, written over this theory's constructs." :
        "Add propositions to an alternative in the editor, or upload a rival theory that uses this theory's construct ids.";
    more.push(el("p", { class: "note prior-note", text: note }));
    return el("div", { class: "prior" }, [el("label", { class: "field", style: "margin:0 0 10px" }, [el("span", null, p.label), sel]), el("div", { id: "rivalMore" }, more)]);
  }
  async function onRivalFileChange(e) {
    const f = e.target.files && e.target.files[0]; if (!f) return;
    const text = await f.text();
    await withBusy("Loading " + f.name + "…", async () => {
      try {
        const info = await engine(() => RT.loadRivalText(text, f.name));
        STATE.rival = { name: f.name, info };
        STATE.rivalError = null;
        STATE.params.rival = UPLOADED;
        saveState();
      } catch (err) { STATE.rivalError = { name: f.name, err }; }
    });
    renderParams();
  }

  // The corpus is a bundled one or a file uploaded here.
  function corpusField(p) {
    const keys = (RT.corpora || []).map((c) => c.key).filter(Boolean);
    const options = p.options.filter((o) => o === UPLOADED || keys.includes(o) || !keys.length);
    if (!options.includes(STATE.params.corpus)) STATE.params.corpus = options.includes(p.default) ? p.default : options[0];
    const sel = el("select", { id: "param-corpus", onchange: (e) => { STATE.params.corpus = e.target.value; STATE.corpusError = null; saveState(); renderParams(); } },
      options.map((o) => el("option", { value: o }, o === UPLOADED ? (STATE.corpus ? "Uploaded: " + STATE.corpus.name : "Upload a corpus…") : corpusName(o))));
    sel.value = STATE.params.corpus;
    const more = [];
    if (STATE.params.corpus === UPLOADED) more.push(uploadField("Corpus file (YAML / JSON)", "corpusFile", onCorpusFileChange));
    if (STATE.corpusError) more.push(errorBox("Could not load " + STATE.corpusError.name + (STATE.corpus ? "; the corpus is still " + STATE.corpus.name : ""), STATE.corpusError.err));
    const c = (RT.corpora || []).find((x) => x.key === STATE.params.corpus);
    if (c && c.desc) more.push(el("p", { class: "note prior-note", text: c.desc }));
    if (STATE.params.corpus === UPLOADED && STATE.corpus && STATE.corpus.info) more.push(el("p", { class: "note prior-note", text: plural(Number(STATE.corpus.info.n_records || 0), "record") + " read from " + STATE.corpus.name + "." }));
    return el("div", { class: "prior" }, [el("label", { class: "field", style: "margin:0 0 10px" }, [el("span", null, p.label), sel]), el("div", { id: "corpusMore" }, more)]);
  }
  async function onCorpusFileChange(e) {
    const f = e.target.files && e.target.files[0]; if (!f) return;
    const text = await f.text();
    await withBusy("Loading " + f.name + "…", async () => {
      try {
        const info = await engine(() => RT.loadCorpusText(text, f.name));
        STATE.corpus = { name: f.name, info };
        STATE.corpusError = null;
        STATE.params.corpus = UPLOADED;
        saveState();
      } catch (err) { STATE.corpusError = { name: f.name, err }; }
    });
    renderParams();
  }

  function selectOp(id) {
    if (id !== STATE.opId) clearToast();
    STATE.opId = id;
    for (const b of document.querySelectorAll(".op")) {
      const on = b.getAttribute("data-op") === id;
      b.classList.toggle("active", on);
      b.setAttribute("aria-pressed", on ? "true" : "false");
    }
    updateOpHelp(); renderParams(); saveState();
  }

  const theoryName = (s) => (s && (s.title || s.id)) || "(untitled)";

  // The session in the browser's storage is the only copy of edits that Save
  // has not written, so replacing an edited theory asks first, as New theory
  // does. A browser without confirm() replaces it, as before.
  function confirmed(question) {
    if (typeof window === "undefined" || typeof window.confirm !== "function") return true;
    return !!window.confirm(question);
  }
  function mayDiscardEdits(action) {
    if (!(STATE.input && STATE.input.mode === "edited")) return true;
    return confirmed(action + "? Edits to " + theoryName(STATE.summary) + " that you have not saved will be lost.");
  }

  // A result and its code belong to the theory they were computed on, so a
  // change of theory removes both.
  function clearResult() {
    const stale = $("#staleNote"); if (stale) stale.setAttribute("hidden", "");
    if (!resultShown) return;
    resultShown = false;
    $("#output").replaceChildren(el("p", { class: "note", text: "Loaded " + theoryName(STATE.summary) + ". Choose an operation and press Run." }));
    $("#outTitle").textContent = "Result";
    $("#codePanel").style.display = "none";
    $("#codeBlock").textContent = "";
    STATE.ran = false;
  }
  // An edit keeps the result in view, marked as computed on an earlier
  // version of the theory.
  function markStale() {
    const stale = $("#staleNote");
    if (stale && resultShown) stale.removeAttribute("hidden");
  }

  // A load that fails leaves the engine on the theory it held, so the card
  // keeps that theory's summary under the error.
  function loadFailed(name, err) {
    $("#summaryWrap").replaceChildren(
      errorBox("Could not load " + name + (STATE.summary ? "; the active theory is still " + theoryName(STATE.summary) : ""), err),
      summaryCard(STATE.summary));
  }

  // After any change of theory: the card, the selector, the result, the
  // choices that depend on the theory and the editor.
  function theoryChanged() {
    refreshSummary();
    updateExampleSel();
    clearResult();
    resetPrior();
    updateExampleDesc(); saveState();
    if (EDITOR) EDITOR.reload();
    requestScore();
    requestHash();
  }

  // The choice is read before the editor's pending change is applied, which
  // puts the selector back on the edited theory. The change is applied first,
  // so that an edit made just before the choice is neither lost nor applied
  // to the example, and an edited theory is replaced only once the user agrees.
  async function onExampleChange(e) {
    const ex = RT.examples.find((x) => x.path === e.target.value);
    if (!ex) return;
    await withBusy("Loading " + ex.name + "…", async () => {
      if (EDITOR && EDITOR.flush) await EDITOR.flush();
      if (!mayDiscardEdits("Load " + ex.name)) { updateExampleSel(); return; }
      try {
        STATE.summary = await engine(() => RT.loadExample(ex.path));
      } catch (err) {
        loadFailed(ex.name, err);
        updateExampleSel();
        return;
      }
      STATE.input = { mode: "example", path: ex.path };
      STATE.source = await exampleSource(ex.path.split("/").pop(), ex.path);
      $("#fileInput").value = "";
      theoryChanged();
      announce("Loaded " + ex.name);
    });
  }
  async function onFileChange(e) {
    const f = e.target.files && e.target.files[0]; if (!f) return;
    const text = await f.text();
    await withBusy("Loading " + f.name + "…", async () => {
      if (EDITOR && EDITOR.flush) await EDITOR.flush();
      if (!mayDiscardEdits("Load " + f.name)) { $("#fileInput").value = ""; return; }
      try {
        STATE.summary = await engine(() => RT.loadTheoryText(text, f.name));
      } catch (err) {
        loadFailed(f.name, err);
        $("#fileInput").value = "";
        return;
      }
      STATE.input = { mode: "upload", name: f.name, text };
      STATE.source = { name: f.name, text };
      theoryChanged();
      announce("Loaded " + f.name);
    });
  }

  // ---- errors --------------------------------------------------------------
  // The in-browser files that hold the user's own text appear in engine
  // messages by their internal path, so each is named as the user named it.
  function cleanMessage(msg) {
    let s = String(msg == null ? "" : msg);
    const names = (RT && RT.fileNames) || {};
    for (const p of Object.keys(names).sort((a, b) => b.length - a.length)) s = s.split(p).join(names[p]);
    s = s.replace(/\/(?:tf|pkg)\/(input|prior|edit|rival|corpus)\.(yaml|json)/g, "$1.$2");
    // webR reports an R condition raised with call. = FALSE, as the package
    // raises its refusals, as "Error in unknown source: ". R itself prints
    // "Error: ", which headline() still finds on a message of several lines.
    return s.replace(/^Error in unknown source: /, "Error: ");
  }
  // The line that names the error. Python ends a traceback with the exception,
  // except that a YAML error appends the line it could not read and a caret
  // under the column, so the exception line is taken with its position. R's
  // messages are a single line. Failing both, the last line with words in it.
  function headline(lines) {
    for (let i = lines.length - 1; i >= 0; i--) {
      if (/^(?:[A-Za-z_][\w.]*(?:Error|Exception)|Error)\b[^:]*:/.test(lines[i])) {
        // R puts the message of a long call on the next line.
        let h = lines[i];
        if (/:\s*$/.test(h) && lines[i + 1]) h += " " + lines[i + 1];
        const at = lines.slice(i + 1).map((l) => /line (\d+), column (\d+)/.exec(l)).find(Boolean);
        return h + (at && !/line \d+, column \d+/.test(h) ? " (line " + at[1] + ", column " + at[2] + ")" : "");
      }
    }
    for (let i = lines.length - 1; i >= 0; i--) if (/[A-Za-z]{2}/.test(lines[i])) return lines[i];
    return lines.length ? lines[lines.length - 1] : "";
  }
  // Engine errors arrive as a whole traceback (Pyodide's PythonError) or as R's
  // condition text, of which a box or a note shows the line that names the
  // error.
  function errorLines(err) {
    const msg = cleanMessage((err && (err.message || err.toString())) || err);
    return { msg, lines: msg.split(/\r?\n/).map((s) => s.trim()).filter(Boolean) };
  }
  function errorHeadline(err) {
    const { msg, lines } = errorLines(err);
    return headline(lines) || msg;
  }
  // The box keeps the full text in a details element. `lead` is an optional
  // node or text placed between the title and the error.
  function errorBox(title, err, lead) {
    const { msg, lines } = errorLines(err);
    const last = headline(lines) || msg;
    const kids = [el("div", { class: "et", text: title })];
    if (lead) kids.push(el("p", { class: "lead" }, lead));
    kids.push(el("div", { class: "last", text: last }));
    if (lines.length > 1) kids.push(el("details", null, [el("summary", null, "Full error"), el("pre", { class: "text", text: msg })]));
    return el("div", { class: "error", role: "alert" }, kids);
  }

  // A link pasted while the app is busy waits, and opens once the work in
  // hand has finished.
  let busy = false, linkPending = false;
  async function withBusy(label, fn) {
    if (busy) return; busy = true;
    const btn = $("#runBtn"); const prev = btn ? btn.textContent : "";
    // Lock all theory/operation controls so the UI cannot desync mid-flight.
    const controls = [...document.querySelectorAll("#exampleSel, #fileInput, #viewSrc, #runBtn, .op, #param-prior, #priorFile, #param-rival, #rivalFile, #param-corpus, #corpusFile, #newTheory")];
    for (const c of controls) { c.setAttribute("data-busywas", c.disabled ? "1" : "0"); c.disabled = true; }
    if (btn && label) btn.textContent = label;
    try { await fn(); } finally {
      busy = false;
      for (const c of controls) { if (c.getAttribute("data-busywas") === "0") c.disabled = false; c.removeAttribute("data-busywas"); }
      if (btn) btn.textContent = prev;
      if (linkPending) { linkPending = false; setTimeout(() => openLinkInPlace(), 0); }
    }
  }

  async function runOp() {
    clearToast();
    const op = OPS.find((o) => o.id === STATE.opId);
    if (EDITOR && EDITOR.flush) await EDITOR.flush();
    if (!STATE.summary) { toast("Load a theory first"); return; }
    if (op.corpus && !RT.hasCorpus() && STATE.params.corpus !== UPLOADED) { toast("This operation needs a corpus"); return; }
    const why = whyNotRunnable(op);
    if (why) {
      toast(why[0]);
      const sel = $(why[1]); if (sel) sel.focus();
      return;
    }
    const out = $("#output");
    showTab("result");
    await withBusy("Running…", async () => {
      resultShown = true;
      const stale = $("#staleNote"); if (stale) stale.setAttribute("hidden", "");
      out.replaceChildren(el("p", { class: "note", text: "Running " + op.label + "…" }));
      $("#outTitle").textContent = op.label;
      announce("Running " + op.label);
      try {
        const params = Object.assign({}, STATE.params);
        const s = STATE.summary, key = cardKey(STATE.input);
        const { raw, code } = await engine(() => RT.run(op.id, params));
        // A theory loaded in the meantime would have replaced the summary.
        // The card shows the score under the default reading of a feedback
        // loop, so a run under sigma does not give it one.
        if (op.id === "check" && raw && raw.report && STATE.summary === s && checkReading(raw, params) === "refuse") {
          const got = { check: scoreOfReport(raw.report) };
          keepCard(key, got);
          if (!s.check) takeCard(s, "score", got);
        }
        const sections = await shapeResult(op.id, raw, params, STATE.summary.id || "theory");
        out.replaceChildren(...sections.map((s) => s.node));
        const cp = $("#codePanel"); cp.style.display = "";
        $("#codeBlock").textContent = code;
        STATE.ran = true; saveState();
        announce(op.label + " finished");
      } catch (err) {
        $("#codePanel").style.display = "none";
        out.replaceChildren(failureBox(err));
        announce(op.label + " failed");
        console.error(err);
      }
    });
  }

  // Most operations assume a valid theory, so a failure on an invalid one is
  // reported as such, with a way to the Validate operation that lists why.
  function failureBox(err) {
    const v = STATE.summary && STATE.summary.validation;
    if (!v || v.ok) return errorBox("Operation failed", err);
    const n = problemList(v).length;
    const toValidate = el("button", { class: "linklike", onclick: () => { selectOp("validate"); runOp(); } }, "Run Validate");
    return errorBox("Operation failed on a theory that is not well-formed", err,
      ["This theory has " + plural(n, "problem") + ". ", toValidate, " to list them, then correct them in the editor or in the file and upload it again."]);
  }

  // ---- the editor's view of the app ----------------------------------------
  // The editor holds the theory as data and asks the engine to read each
  // version, so validation, the checklist and the writer are the package's.
  // A new theory's file is named after its id, with every run of characters
  // a file name should not hold made one hyphen.
  function idFileName(id) {
    return (typeof id === "string" && id.trim() ? id.trim().replace(/[^\w.-]+/g, "-") : "new-theory") + ".theory.yaml";
  }
  // The name of the file the edited theory is saved as and read from in the
  // code. A theory that is new, or about to replace the input as a new one, is
  // named after its id; any other keeps the name of the file it came from.
  function editName(doc, isNew) {
    const inp = STATE.input || {};
    if (isNew || inp.isNew) return idFileName(doc && doc.id);
    if (inp.mode === "example") return inp.path.split("/").pop().replace(/\.json$/i, ".yaml");
    if (inp.name) return String(inp.name).replace(/\.json$/i, ".yaml");
    return idFileName(doc && doc.id);
  }
  // After the editor changes the theory: the card, the selector and the
  // choices that depend on the theory. A fresh theory clears the result, and
  // an edit marks it as computed on an earlier version.
  function theoryShown(fresh) {
    refreshSummary();
    updateExampleSel();
    updateExampleDesc();
    if (fresh) { clearResult(); resetPrior(); } else { markStale(); resetTheoryChoices(); }
    const op = OPS.find((o) => o.id === STATE.opId);
    if (op && op.params && op.params.some((p) => p.type === "rival" || p.type === "construct")) renderParams();
    saveSoon();
    requestScore();
    requestHash();
  }
  function editorHost() {
    return {
      el, esc, toast, openModal, closeModal, copyText, download, plural, problemList, errorBox, asArr, fmtNum, num,
      scoreTitle, wellFormedTitle: WELL_FORMED_TITLE,
      summary: () => STATE.summary,
      sourceOf: () => (STATE.source ? STATE.source.text : null),
      sourceName: () => (STATE.source ? STATE.source.name : ""),
      lang: () => RT.langLabel,
      // The loaded theory as data, read through the package's JSON writer.
      async theoryData() { return JSON.parse(await engine(() => RT.writeText("json"))); },
      async writeText(fmt) { return engine(() => RT.writeText(fmt)); },
      // Ask the engine to read `text` as the theory. On success the app takes
      // it as the active theory, and the result carries the summary and the
      // texts the writer gave in each of `want`.
      async apply(text, format, want, opts) {
        const isNew = !!(opts && opts.isNew) || !!(STATE.input && STATE.input.isNew);
        const name = editName(opts && opts.doc, isNew);
        let res;
        try { res = await engine(() => RT.editText(text, format, name, want || [])); }
        catch (err) { return { ok: false, error: err }; }
        const texts = res.texts || {};
        delete res.texts;
        STATE.summary = res;
        // A new theory's file is named after its id, which a change in the
        // source may have just set.
        let saved = name;
        if (isNew && !(opts && opts.doc) && typeof res.id === "string" && res.id.trim()) {
          saved = editName({ id: res.id });
          if (RT.renameTheory) RT.renameTheory(saved);
        }
        STATE.input = { mode: "edited", name: saved, text, format, isNew };
        STATE.source = { name: saved, text };
        theoryShown(!!(opts && opts.fresh));
        return { ok: true, summary: res, texts };
      },
      // The theory the package's DAGitty reader makes of `model` becomes the
      // active theory, a new one named after its id.
      canImportDagitty: () => !!RT.canImportDagitty,
      // The code names the file as Save and the code panel name it.
      importCode: (opts) => (RT.importCode ? RT.importCode(Object.assign({}, opts, { file: idFileName(opts && opts.id ? opts.id : "dagitty-import") })) : ""),
      async importDagitty(model, opts, want) {
        let res;
        try { res = await engine(() => RT.importDagitty(model, opts, want || [])); }
        catch (err) { return { ok: false, error: err }; }
        const texts = res.texts || {};
        delete res.texts;
        const name = editName({ id: res.id }, true);
        if (RT.renameTheory) RT.renameTheory(name);
        const fmt = (want || [])[0] || "yaml";
        STATE.summary = res;
        STATE.input = { mode: "edited", name, text: texts[fmt] || "", format: fmt, isNew: true };
        STATE.source = { name, text: texts[fmt] || "" };
        theoryShown(true);
        return { ok: true, summary: res, texts };
      },
      // The editor's own record of the current source, for View source.
      setSource(text) { if (STATE.source) STATE.source.text = text; },
      saveName: (doc) => editName(doc),
      // Before the editor replaces an edited theory with a new one.
      mayDiscard: (action) => mayDiscardEdits(action),
      isEdited: () => !!(STATE.input && STATE.input.mode === "edited"),
      isBusy: () => busy,
      showResultTab: () => showTab("result"),
      // Score or hash a theory too large to be scored or hashed as it loads.
      score: () => requestScore("editor"),
      hash: () => requestHash("editor"),
      largeNote: (s, kind) => largeNote(s, kind || "score"),
    };
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

  // Load the theory a saved session or a link names. Returns true on success.
  async function restoreTheory(inp, blog) {
    if (inp.mode === "edited" && typeof inp.text === "string") {
      if (blog) blog("Restoring your edited theory…");
      const name = inp.name || "theory.yaml";
      const res = await engine(() => RT.editText(inp.text, inp.format || "yaml", name, []));
      delete res.texts;
      STATE.summary = res;
      STATE.input = { mode: "edited", name, text: inp.text, format: inp.format || "yaml", isNew: !!inp.isNew };
      // A change in the forms is kept as the JSON the editor sent, while the
      // source pane, View source and the download take their format from the
      // file name. The saved text is shown when it is in that format, a
      // source-pane edit with its comments among them, and otherwise the
      // package's writer gives the text in that format.
      const viewFmt = /\.json$/i.test(name) ? "json" : "yaml";
      let shown = inp.text;
      if ((inp.format || "yaml") !== viewFmt) {
        try { shown = await engine(() => RT.writeText(viewFmt)); } catch (e) { shown = inp.text; }
      }
      STATE.source = { name, text: shown };
      return true;
    }
    if (inp.mode === "upload" && inp.text) {
      if (blog) blog("Restoring your uploaded theory…");
      STATE.summary = await engine(() => RT.loadTheoryText(inp.text, inp.name));
      STATE.input = inp;
      STATE.source = { name: inp.name, text: inp.text };
      return true;
    }
    if (inp.mode === "example") {
      const ex = RT.examples.find((x) => x.path === inp.path);
      if (!ex) throw new Error("no longer an example");
      if (blog) blog("Restoring " + ex.name + "…");
      STATE.summary = await engine(() => RT.loadExample(ex.path));
      STATE.input = { mode: "example", path: ex.path };
      return true;
    }
    return false;
  }

  // A link this app can open, or the reason it cannot: a link of another
  // format version, or one with no theory in it, is refused with a note.
  function linkProblem(link) {
    if (link && link.v === 1 && link.theory && typeof link.theory === "object" && !Array.isArray(link.theory)) return null;
    return link && typeof link.v === "number" && link.v > 1
      ? "This link was made by a newer version of the app, so the saved session is shown instead"
      : "The link could not be read, so the saved session is shown instead";
  }
  // The input a link's theory stands for.
  const linkInput = (t) => (t.example ? { mode: "example", path: t.example }
    : { mode: "edited", name: t.name, text: t.text, format: t.format, isNew: !!t.isNew });
  // What a link's theory is called, for the question asked before it replaces
  // an edited one.
  const linkName = (t) => (t.example ? ((RT.examples.find((x) => x.path === t.example) || {}).name || String(t.example)) : t.name || "a theory");
  // The address without the link, so that a reload does not open it again.
  function dropLinkHash() {
    if (typeof history === "undefined" || !history.replaceState || typeof location === "undefined") return;
    history.replaceState(null, "", location.pathname + location.search + lastLinkHash);
  }
  // While a theory from a link loads, the start panel offers to open the app
  // without it, which reloads the page with no link in the address. The
  // session saved before is kept, since nothing is saved until the theory has
  // loaded.
  function offerSkipLink() {
    const b = $("#boot");
    if (!b || $("#skipLink", b)) return;
    b.append(el("button", { class: "btn ghost sm", id: "skipLink", onclick: () => location.replace(location.pathname + location.search) },
      "Open the app without the link"));
  }

  // Restore theory + operation + params from a link or a previous session,
  // then optionally re-run the last operation so a refresh lands back where
  // the user left off. A link wins over the saved session, unless that session
  // holds edits the link would replace and the user keeps them, or the link is
  // the tab's own, whose session is at least as new. init has already loaded
  // example 0, and a load that fails leaves it loaded, so a failed restore
  // falls back to it, and the card shows why. A link whose theory cannot be
  // loaded is taken out of the address and is not saved, so the next visit
  // starts from the session saved before. The returned note says what
  // happened; start() shows it once the boot overlay, which would hide a
  // toast, is gone.
  async function applyRestore(blog) {
    let note = null, fromLink = false, linkFailed = false, failure = null;
    const hash = (typeof location !== "undefined" && location.hash) || "";
    const tab = loadTab();
    const ownReload = !!tab && tab.link === hash;
    let saved = ownReload ? tab : loadSaved();
    try {
      const link = ownReload ? null : await readLink();
      if (link) {
        const problem = linkProblem(link);
        if (problem) { note = problem; linkFailed = true; }
        else {
          const t = link.theory;
          const prev = saved && saved.input;
          // updateLink keeps the tab's own edited theory in the address, so an
          // ordinary reload arrives as a link that holds the saved text, and
          // nothing is asked then.
          const same = !t.example && prev && prev.text === t.text;
          if (prev && prev.mode === "edited" && typeof prev.text === "string" && !same &&
              !confirmed("This link opens " + linkName(t) + ". Edits to " + (prev.name || "your theory") + " that you have not saved will be lost. Open the link?")) {
            note = "The link was not opened, so your edited theory is shown";
            linkFailed = true;
          } else {
            fromLink = true;
            saved = { v: STATE_FORMAT, opId: link.op, params: link.params || {}, ran: !!link.run, input: linkInput(t) };
          }
        }
      }
    } catch (e) { note = "The link could not be read (" + ((e && e.message) || e) + "), so the saved session is shown instead"; linkFailed = true; }
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
      const inp = saved.input;
      if (inp && !(inp.mode === "example" && inp.path === first.path)) {
        if (fromLink) offerSkipLink();
        try {
          // A theory that restoreTheory cannot take, such as an edited one
          // whose text is not text, is a failure like any other.
          if (!(await restoreTheory(inp, blog))) throw new Error("the theory in it cannot be read");
        } catch (e) {
          STATE.input = { mode: "example", path: first.path };
          failure = { title: fallback(inp.mode === "example" ? ((RT.examples.find((x) => x.path === inp.path) || {}).name || String(inp.path).split("/").pop()) : inp.name || "your theory"), err: e };
          note = failure.title + ": " + errorHeadline(e);
          if (fromLink) linkFailed = true;
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
    updateExampleSel();
    refreshSummary();
    if (failure) $("#summaryWrap").replaceChildren(errorBox(failure.title, failure.err), summaryCard(STATE.summary));
    for (const b of document.querySelectorAll(".op")) {
      const on = b.getAttribute("data-op") === STATE.opId;
      b.classList.toggle("active", on);
      b.setAttribute("aria-pressed", on ? "true" : "false");
    }
    // A saved prior belongs to the saved theory, so it goes with a failed
    // restore, and one that is no longer offered falls back to the default.
    if (note || (STATE.params.prior !== undefined && !priorValues().includes(STATE.params.prior))) STATE.params.prior = defaultPrior();
    resetTheoryChoices();
    updateExampleDesc(); updateOpHelp(); renderParams();
    // The link opened, or the tab's own, is the app's fragment from now on. A
    // link pasted while the start panel showed is left in the address, and
    // start() opens it.
    const pasted = typeof location !== "undefined" && location.hash !== hash;
    if (linkFailed) { if (!pasted) dropLinkHash(); }
    else { if (fromLink || ownReload) lastLinkHash = hash; saveState(); }
    const op = OPS.find((o) => o.id === STATE.opId);
    const rerun = saved && saved.ran && op && !note && !(op.corpus && !RT.hasCorpus()) && !whyNotRunnable(op);
    if (rerun && !isLarge(STATE.summary)) await runOp();
    if (fromLink && !note) note = "Opened the theory and operation from the link";
    if (rerun && isLarge(STATE.summary)) note = (note ? note + ". " : "") + notRunNote(op);
    return note;
  }
  // Why an operation saved with a large theory was not run as it opened.
  const notRunNote = (op) => "The theory is large, so the " + op.label + " operation was not run. Press Run to run it";

  // A link pasted into the address bar of a tab that already shows the app
  // changes only the fragment, so the browser keeps the page and the app
  // opens the link here. A fragment the app wrote itself is no link to open.
  let linkOpening = false;
  async function openLinkInPlace() {
    if (!linkWaiting()) return;
    if (busy || linkOpening) { linkPending = true; return; }
    linkOpening = true;
    try { await openLink(); } finally {
      linkOpening = false;
      if (linkPending && !busy) { linkPending = false; setTimeout(() => openLinkInPlace(), 0); }
    }
  }
  async function openLink() {
    const h = location.hash;
    let link;
    try { link = await readLink(); } catch (e) { toast("The link could not be read: " + ((e && e.message) || e)); dropLinkHash(); return; }
    const problem = linkProblem(link);
    if (problem) { toast(problem.replace(/, so the saved session is shown instead$/, "")); dropLinkHash(); return; }
    const t = link.theory;
    if (EDITOR && EDITOR.flush) await EDITOR.flush();
    // A link pasted over this one is opened in its place.
    if (location.hash !== h) return;
    if (busy) { linkPending = true; return; }
    if (!mayDiscardEdits("Open " + linkName(t) + " from the link")) { dropLinkHash(); return; }
    let ok = false;
    await withBusy("Opening the link…", async () => {
      const inp = linkInput(t);
      try {
        if (!(await restoreTheory(inp))) throw new Error("the theory in it cannot be read");
      } catch (err) { loadFailed(t.example || t.name || "the theory in the link", err); dropLinkHash(); return; }
      lastLinkHash = h;
      if (inp.mode === "example") STATE.source = await exampleSource(inp.path.split("/").pop(), inp.path);
      $("#fileInput").value = "";
      // The change of theory resets the choices that depend on it, and the
      // link's operation and parameters are then applied, as at start-up.
      theoryChanged();
      if (OPS.some((o) => o.id === link.op)) STATE.opId = link.op;
      STATE.params = Object.assign({}, STATE.params, link.params || {});
      if (STATE.params.prior !== undefined && !priorValues().includes(STATE.params.prior)) STATE.params.prior = defaultPrior();
      resetTheoryChoices();
      for (const b of document.querySelectorAll(".op")) {
        const on = b.getAttribute("data-op") === STATE.opId;
        b.classList.toggle("active", on);
        b.setAttribute("aria-pressed", on ? "true" : "false");
      }
      updateOpHelp(); renderParams(); saveState();
      ok = true;
    });
    if (!ok) return;
    const op = OPS.find((o) => o.id === STATE.opId);
    const rerun = link.run && op && !(op.corpus && !RT.hasCorpus()) && !whyNotRunnable(op);
    if (rerun && !isLarge(STATE.summary)) await runOp();
    toast("Opened the theory and operation from the link" + (rerun && isLarge(STATE.summary) ? ". " + notRunNote(op) : ""));
  }

  async function start(runtime) {
    RT = runtime;
    const root = document.documentElement;
    root.style.setProperty("--accent", RT.accent);
    if (RT.accentInk) root.style.setProperty("--accent-ink", RT.accentInk);
    if (RT.accentText) {
      root.style.setProperty("--accent-text-light", RT.accentText.light);
      root.style.setProperty("--accent-text-dark", RT.accentText.dark);
    }
    root.setAttribute("data-lang", RT.lang || "");
    initTheme();
    document.title = "theoryforge (" + RT.langLabel + "): interactive app";
    document.body.append(bootOverlay());
    const blog = $("#blog");
    const onProgress = (m) => { if (blog) blog.textContent = m; };
    try {
      const info = await RT.init(onProgress);
      RT.examples = info.examples; RT.version = info.version; RT.pkgVersion = info.pkgVersion;
      if (info.corpora) RT.corpora = info.corpora;
      STATE.summary = info.summary || null;
      // The skip link moves the focus itself, since following #main would
      // replace the link that the address may hold.
      document.body.append(el("a", { class: "skip-link", href: "#main", onclick: (e) => {
        if (e && e.preventDefault) e.preventDefault();
        const m = $("#main"); if (m) m.focus();
      } }, "Skip to content"));
      document.body.append(buildHeader());
      const main = el("main", { id: "main", tabindex: "-1" }, [buildSidebar(), buildMain()]);
      document.body.append(main);
      document.body.append(el("div", { id: "liveStatus", class: "sr-only", role: "status", "aria-live": "polite" }));
      // Two distinct versions meet here: RT.pkgVersion is the version of the
      // app's own package (DESCRIPTION for R, pyproject.toml for Python), which
      // build.mjs stamps into the manifest, while RT.version is the interpreter
      // the engine booted (R.version.string / "Python x.y.z"). Keep them apart
      // in the footer so the package version is never mistaken for the
      // interpreter's.
      document.body.append(el("footer", { class: "app", html:
        "theoryforge" + (RT.pkgVersion ? " " + esc(RT.pkgVersion) : "") + " · " + esc(RT.version || "") +
        " via " + esc(RT.engineLabel) + " · running entirely client-side" +
        " · <a href='" + esc(RT.docsUrl) + "'>documentation</a> · <a href='https://github.com/pablobernabeu/theoryforge'>source</a>" }));
      updateThemeBtn();
      const note = await applyRestore(onProgress);
      $("#boot").classList.add("hidden");
      if (note) toast(note);
      requestScore();
      requestHash();
      if (typeof window !== "undefined" && window.addEventListener) window.addEventListener("hashchange", () => openLinkInPlace());
      // A link pasted while the start panel showed fired no handler.
      if (linkWaiting()) openLinkInPlace();
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

  window.TF = {
    start: startCaught, OPS, GROUPS, DIAG_SVG,
    util: {
      el, esc, download, copyText, toast, renderDot, dagToDigraph, fetchJson, fetchBytes, plural, problemList,
      headline, cleanMessage: (m) => cleanMessage(m), cssPx, sevText, severityReading, claimText,
    },
  };
})();
