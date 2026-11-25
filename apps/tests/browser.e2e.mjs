#!/usr/bin/env node
// The two apps in a real browser, with Playwright and Chromium.
//
// It serves apps/ over HTTP, boots the R app on webR and the Python app on
// Pyodide, and then, in each app:
//   - runs every operation, at the parameters the UI gives it, on every
//     example and on a theory built in the editor (a DAGitty import, or a
//     new theory, then field edits, a claim, bounds, an estimate and its SE);
//   - checks that a copied link reproduces the view in a fresh tab, and that
//     a link pasted into a tab that shows the app opens there, after asking
//     before it replaces the edited theory;
//   - checks that a source the package cannot read is reported by the line
//     that names the error, with the user's file name in place of the
//     in-browser path;
//   - checks the layout at 390 and 768 px wide (no sideways scroll, the
//     header's buttons on screen, the sidebar not sticky) and the contrast of
//     coloured text in the light and the dark theme.
// The displayed text of the two apps is then compared, operation by
// operation, where the packages promise the same output: the readings, the
// tables, the documents and the refusals. The reproducible code, the raw JSON
// views and the engine versions differ by design and are left out.
//
// It needs the vendor trees (`node apps/build.mjs`), Playwright and its
// Chromium, and network access to webr.r-wasm.org, repo.r-wasm.org and
// cdn.jsdelivr.net. `node --test` does not run it, since its name does not end
// in .test.mjs. Run it from the repository root:
//
//   node apps/tests/browser.e2e.mjs [--apps r,py] [--examples 2] [--shots DIR] [--skip-layout]
//
// Exit 0 when every check passes, 1 otherwise.
import http from "node:http";
import { promises as fs, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = path.dirname(fileURLToPath(import.meta.url));
const APPS = path.resolve(here, "..");
const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require("playwright")); }
catch (e) {
  try { ({ chromium } = require(path.join(process.env.NODE_PATH || "", "playwright"))); }
  catch (e2) { console.error("Playwright is not installed: npm install playwright and npx playwright install chromium"); process.exit(2); }
}

const args = process.argv.slice(2);
const opt = (name, dflt) => { const i = args.indexOf("--" + name); return i < 0 ? dflt : args[i + 1]; };
const flag = (name) => args.includes("--" + name);
const WHICH = String(opt("apps", "r,py")).split(",");
const MAX_EX = Number(opt("examples", "0")) || Infinity;
const SHOTS = opt("shots", "");
const BOOT_MS = 300000, RUN_MS = 180000;

const failures = [];
const fail = (where, why) => { failures.push(where + ": " + why); console.log("FAIL " + where + ": " + why); };

// ---- a static server for apps/ ---------------------------------------------
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css",
  ".json": "application/json", ".svg": "image/svg+xml", ".yaml": "text/plain", ".R": "text/plain", ".r": "text/plain", ".py": "text/plain", ".typed": "text/plain" };
function serve() {
  const server = http.createServer(async (req, res) => {
    try {
      let p = decodeURIComponent(new URL(req.url, "http://x").pathname);
      if (p.endsWith("/")) p += "index.html";
      const file = path.join(APPS, path.normalize(p));
      if (!file.startsWith(APPS)) { res.writeHead(403).end(); return; }
      const body = await fs.readFile(file);
      res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream" }).end(body);
    } catch (e) { res.writeHead(404).end("not found"); }
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

// ---- driving one app -------------------------------------------------------
async function boot(browser, base, lang) {
  const ctx = await browser.newContext({ viewport: { width: 1400, height: 950 }, deviceScaleFactor: 1, acceptDownloads: true });
  const page = await ctx.newPage();
  page.errors = [];
  page.on("pageerror", (e) => page.errors.push(e.message));
  page.on("console", (m) => { if (m.type() === "error") page.errors.push(m.text()); });
  await page.goto(base + lang + "/");
  await page.waitForSelector("#boot.hidden", { state: "attached", timeout: BOOT_MS });
  if (await page.$(".boot-error")) throw new Error(await page.textContent(".boot-error"));
  return page;
}
const idle = (page) => page.waitForFunction(() => {
  const b = document.querySelector("#runBtn");
  return b && !b.disabled && /^Run/.test(b.textContent);
}, null, { timeout: RUN_MS });

// The comparable text of the result: every section but the raw JSON and the
// intermediate representations, which differ in layout between the two
// engines' JSON writers.
const resultText = (page) => page.evaluate(() => {
  const out = document.querySelector("#output");
  const parts = [];
  for (const node of out.children) {
    const head = node.querySelector(".sh span");
    const title = head ? head.textContent : "";
    if (/JSON$/.test(title)) continue;
    const clone = node.cloneNode(true);
    for (const b of clone.querySelectorAll("button")) b.remove();
    for (const raw of clone.querySelectorAll("pre[hidden]")) raw.remove();
    parts.push(clone.textContent.replace(/\s+/g, " ").trim());
  }
  return parts.join("\n");
});

async function runOp(page, opId) {
  const label = await page.evaluate((id) => window.TF.OPS.find((o) => o.id === id).label, opId);
  await page.click(`.op[data-op="${opId}"]`);
  // A result from an earlier run is cleared first, so one that stays shows
  // that the run did not start.
  await page.evaluate(() => { document.querySelector("#outTitle").textContent = "Result"; });
  await page.click("#runBtn");
  await idle(page);
  const ran = (await page.textContent("#outTitle")) === label;
  const err = await page.$("#output > .error");
  return { ran, error: ran && err ? await err.textContent() : null, text: ran ? await resultText(page) : "", code: ran ? await page.textContent("#codeBlock") : "" };
}

async function opsOf(page) { return page.evaluate(() => window.TF.OPS.map((o) => o.id)); }

async function chooseExample(page, value) {
  await page.selectOption("#exampleSel", value);
  await idle(page);
}

// Every operation on the loaded theory, recorded under `key`.
async function runAll(page, lang, key, record) {
  for (const op of await opsOf(page)) {
    let r;
    try { r = await runOp(page, op); }
    catch (e) { fail(`${lang} ${key} ${op}`, "did not finish: " + e.message); continue; }
    record[key + " :: " + op] = r;
    const why = await page.evaluate(() => { const t = document.querySelector(".toast.show"); return t ? t.textContent : ""; });
    // Only two operations may wait: the appraisal for a prior the theory does
    // not declare, and the comparison for a theory with no rival that states
    // propositions. Anything else that does not run is a failure.
    const waits = (op === "appraise" && /prior version/.test(why || "")) ||
      (op === "discriminate" && /no alternative with propositions/.test(why || ""));
    if (!r.ran && !waits) fail(`${lang} ${key} ${op}`, "no result: " + (why || "nothing said"));
    if (!r.ran && waits) record[key + " :: " + op].waited = why;
    if (r.error) fail(`${lang} ${key} ${op}`, "error box: " + r.error.slice(0, 300));
  }
}

// A theory built in the editor without writing YAML: through the package's
// DAGitty reader when the engine has one, and otherwise construct by
// construct and proposition by proposition in the forms. Either way the
// theory has the same ids, labels and propositions, so the two apps can be
// compared on it.
async function buildTheory(page, lang) {
  await page.click("#tabEditor");
  await page.waitForSelector("#edForms .ed-sec");
  await page.click('.ed-toolbar [data-view="both"]');
  const ids = ["demand", "fatigue", "recovery", "sleep_debt"];
  const labels = ["Task demand", "Fatigue", "Recovery effort", "Sleep debt"];
  const edges = [["demand", "increases", "fatigue"], ["fatigue", "increases", "recovery"], ["sleep_debt", "increases", "fatigue"], ["demand", "associates", "sleep_debt"]];
  page.once("dialog", (d) => d.accept());
  if (await page.isEnabled("#edImport")) {
    await page.click("#edImport");
    await page.fill("#dagText", "dag {\n  demand -> fatigue -> recovery\n  fatigue <- sleep_debt [exposure]\n  demand <-> sleep_debt\n}");
    await page.selectOption("#dagRelation", "increases");
    await page.fill("#dagId", "edited-demo");
    await page.click("#dagImport");
    await page.waitForSelector("#tfModal", { state: "detached", timeout: RUN_MS });
    console.log(`${lang}: built the theory through the package's DAGitty reader`);
  } else {
    await page.click("#edNew");
    await page.waitForFunction(() => /Untitled theory/.test(document.querySelector("#summaryWrap").textContent));
    await page.fill('[data-k="id"]', "edited-demo");
    for (let i = 0; i < ids.length; i++) {
      await page.click('.ed-sec[data-sec="constructs"] .add');
      await page.fill(`[data-k="constructs.${i}.id"]`, ids[i]);
      await page.press(`[data-k="constructs.${i}.id"]`, "Tab");
    }
    for (let i = 0; i < edges.length; i++) {
      await page.click('.ed-sec[data-sec="propositions"] .add');
      await page.selectOption(`[data-k="propositions.${i}.from"]`, edges[i][0]);
      await page.selectOption(`[data-k="propositions.${i}.relation"]`, edges[i][1]);
      await page.selectOption(`[data-k="propositions.${i}.to"]`, edges[i][2]);
    }
    console.log(`${lang}: built the theory in the forms (this package version has no DAGitty reader)`);
  }
  await page.fill('[data-k="title"]', "A theory built in the editor");
  await page.selectOption('[data-k="maturity"]', "developing");
  const defs = ["The cognitive load the work imposes.", "Accumulated strain that lowers capacity.", "Deliberate rest that restores capacity.", "Hours of sleep owed against need."];
  for (let i = 0; i < 4; i++) {
    await page.fill(`[data-k="constructs.${i}.label"]`, labels[i]);
    await page.fill(`[data-k="constructs.${i}.definition"]`, defs[i]);
  }
  await page.click('.ed-sec[data-sec="predictions"] .add');
  await page.fill('[data-k="predictions.0.statement"]', "Higher task demand raises end-of-day fatigue by 0.2 to 0.6 SD.");
  await page.selectOption('[data-k="predictions.0.type"]', "interval");
  await page.check('[data-k="predictions.0.derives_from#p1"]');
  await page.fill('[data-k="predictions.0.bounds#lower"]', "0.2");
  await page.fill('[data-k="predictions.0.bounds#upper"]', "0.6");
  await page.selectOption('[data-k="predictions.0.claim.kind"]', "effect");
  await page.selectOption('[data-k="predictions.0.claim.x"]', "demand");
  await page.selectOption('[data-k="predictions.0.claim.y"]', "fatigue");
  await page.selectOption('[data-k="predictions.0.claim.sign"]', "positive");
  await page.click('.ed-sec[data-sec="alternatives"] summary');
  await page.click('.ed-sec[data-sec="alternatives"] .add');
  await page.fill('[data-k="alternatives.0.label"]', "Pure accumulation account");
  await page.click('.ed-sec[data-sec="alternatives"] .nestwrap > button');
  await page.selectOption('[data-k="alternatives.0.propositions.0.from"]', "sleep_debt");
  await page.selectOption('[data-k="alternatives.0.propositions.0.relation"]', "increases");
  await page.selectOption('[data-k="alternatives.0.propositions.0.to"]', "fatigue");
  await page.check('[data-k="predictions.0.diagnostic_vs#alt1"]');
  await page.click('.ed-sec[data-sec="test_outcomes"] summary');
  await page.click('.ed-sec[data-sec="test_outcomes"] .add');
  await page.selectOption('[data-k="test_outcomes.0.prediction_id"]', "pred1");
  await page.selectOption('[data-k="test_outcomes.0.passed"]', "true");
  await page.fill('[data-k="test_outcomes.0.estimate"]', "0.41");
  await page.fill('[data-k="test_outcomes.0.se"]', "0.08");
  await page.fill('[data-k="test_outcomes.0.observed"]', "Illustrative values, not a reported result.");
  // The engine reads the last change once typing pauses.
  await page.waitForFunction(() => /0\.41|valid|problem/.test(document.querySelector("#edLint").textContent) &&
    /A theory built in the editor/.test(document.querySelector("#summaryWrap").textContent), null, { timeout: RUN_MS });
  await page.waitForTimeout(1500);
  const lint = await page.textContent("#edLint");
  const summary = await page.textContent("#summaryWrap");
  if (!/valid/.test(summary) || /problem/.test(summary)) fail(`${lang} editor`, "the built theory is not valid: " + lint.slice(0, 400));
  if (!/checklist \d/.test(lint)) fail(`${lang} editor`, "the lint bar shows no checklist score: " + lint.slice(0, 200));
  const src = await page.inputValue("#edSource");
  if (!/edited-demo/.test(src) || !/Task demand/.test(src)) fail(`${lang} editor`, "the source pane does not follow the forms");
  // An empty definition is reported beside the field.
  await page.fill('[data-k="constructs.0.definition"]', "");
  await page.waitForSelector("#fp-constructs-0-definition li", { timeout: RUN_MS });
  await page.fill('[data-k="constructs.0.definition"]', defs[0]);
  await page.waitForFunction(() => !document.querySelector("#fp-constructs-0-definition li"), null, { timeout: RUN_MS });
  // Save downloads the theory as the package's writer writes it, the text the
  // source pane shows after a change in the forms.
  await page.waitForTimeout(800);
  const [dl] = await Promise.all([page.waitForEvent("download"), page.click("#edSave")]);
  const saved = await fs.readFile(await dl.path(), "utf8");
  if (dl.suggestedFilename() !== "edited-demo.theory.yaml") fail(`${lang} save`, "the file is named " + dl.suggestedFilename());
  if (saved !== await page.inputValue("#edSource")) fail(`${lang} save`, "the saved file is not the writer's text the source pane shows");
  return src;
}

// A source the package cannot read: the headline names the error and the
// user's file, never the in-browser path or a bare caret.
async function brokenSource(page, lang) {
  await page.click("#tabEditor");
  await page.click('.ed-toolbar [data-view="source"]');
  const good = await page.inputValue("#edSource");
  await page.fill("#edSource", good.replace(/^title: .*$/m, "title: A: B: C"));
  await page.waitForSelector("#edLint .error .last", { timeout: RUN_MS });
  const head = await page.textContent("#edLint .error .last");
  const full = await page.textContent("#edLint .error");
  if (/^\s*\^/.test(head) || !/[A-Za-z]{3}/.test(head)) fail(`${lang} parse error`, "the headline is not informative: " + head);
  // The package's own files may appear in a traceback, but the user's text
  // is named by the user's file name.
  if (/\/(tf|pkg)\/(input|edit|prior|rival|corpus)\./.test(full)) fail(`${lang} parse error`, "the message shows an in-browser path: " + full.slice(0, 300));
  await page.fill("#edSource", good);
  await page.waitForFunction(() => !document.querySelector("#edLint .error"), null, { timeout: RUN_MS });
  await page.click('.ed-toolbar [data-view="both"]');
  return head;
}

// A link reproduces the view: the edited theory and the operation, run again,
// in a page that has no saved session.
async function linkRoundTrip(browser, page, base, lang) {
  await page.click('.op[data-op="entailments"]');
  await page.click("#runBtn");
  await idle(page);
  const want = await resultText(page);
  // The app keeps the fragment up to date by itself, 0.7 s after a change, so
  // the address is read once that has settled.
  await page.click("#copyLink");
  await page.waitForTimeout(2000);
  const url = page.url();
  if (!url.startsWith(base + lang + "/#s=")) { fail(`${lang} link`, "the address carries no state: " + url); return; }
  const ctx = await browser.newContext({ viewport: { width: 1400, height: 950 } });
  const fresh = await ctx.newPage();
  await fresh.goto(url);
  await fresh.waitForSelector("#boot.hidden", { state: "attached", timeout: BOOT_MS });
  await fresh.waitForFunction(() => /What the graph entails/.test(document.querySelector("#outTitle").textContent), null, { timeout: RUN_MS });
  await idle(fresh);
  const title = await fresh.textContent("#summaryWrap .ttl");
  if (title !== "A theory built in the editor") fail(`${lang} link`, "the link opened " + title);
  if ((await resultText(fresh)) !== want) fail(`${lang} link`, "the result the link reproduces differs");
  console.log(`${lang}: a link of ${url.length - url.indexOf("#")} characters reproduced the view`);
  // A link pasted into a tab that shows the app opens there, without a
  // reload, once the user agrees to replace the edited theory.
  const ex = (await fresh.$$eval("#exampleSel option", (os) => os.map((o) => o.value))).filter(Boolean)[1];
  const pasted = base + lang + "/#s=" + await fresh.evaluate((p) => window.TF.share.encode({ v: 1, op: "validate", run: true, theory: { example: p } }), ex);
  await fresh.evaluate(() => { window.__sameDocument = true; });
  const asked = [];
  fresh.once("dialog", (d) => { asked.push(d.message()); d.accept(); });
  await fresh.goto(pasted);
  try {
    await fresh.waitForFunction(() => /^Validate$/.test(document.querySelector("#outTitle").textContent), null, { timeout: RUN_MS });
    await idle(fresh);
    if (!(await fresh.evaluate(() => window.__sameDocument === true))) fail(`${lang} pasted link`, "the page was loaded again");
    if ((await fresh.$eval("#exampleSel", (s) => s.value)) !== ex) fail(`${lang} pasted link`, "the example in the link was not loaded");
    if (!/that you have not saved will be lost/.test(asked[0] || "")) fail(`${lang} pasted link`, "the edited theory was replaced without a question");
  } catch (e) { fail(`${lang} pasted link`, "the link did not open in the tab: " + e.message); }
  await ctx.close();
}

// ---- layout and contrast -----------------------------------------------------
async function layout(page, lang) {
  for (const [tab, width] of [["#tabResult", 390], ["#tabEditor", 390], ["#tabResult", 768], ["#tabEditor", 768]]) {
    await page.click(tab);
    await page.setViewportSize({ width, height: 860 });
    await page.waitForTimeout(250);
    const m = await page.evaluate(() => {
      const r = (s) => { const e = document.querySelector(s); if (!e) return null; const b = e.getBoundingClientRect(); return { l: b.left, r: b.right, t: b.top, b: b.bottom }; };
      return {
        sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth,
        help: r("#helpBtn"), theme: r("#themeToggle"),
        sidebar: getComputedStyle(document.querySelector(".sidebar")).position,
      };
    });
    const where = `${lang} ${width}px ${tab.slice(4).toLowerCase()}`;
    if (m.sw > m.cw + 1) fail(where, `the page scrolls sideways (${m.sw} > ${m.cw})`);
    for (const k of ["help", "theme"]) if (!m[k] || m[k].r > m.cw || m[k].l < 0) fail(where, `the ${k} button is off screen`);
    if (m.sidebar === "sticky") fail(where, "the sidebar is still sticky");
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, `${lang}-${width}-${tab.slice(4).toLowerCase()}.png`), fullPage: false });
  }
  await page.setViewportSize({ width: 1400, height: 950 });
}

// The contrast of every element whose text takes a theme colour, against the
// colour behind it, in both themes.
async function contrast(page, lang) {
  for (const [tab, theme] of [["#tabResult", "light"], ["#tabEditor", "light"], ["#tabResult", "dark"], ["#tabEditor", "dark"]]) {
    await page.click(tab);
    await page.evaluate((t) => document.documentElement.setAttribute("data-theme", t), theme);
    await page.waitForTimeout(100);
    const bad = await page.evaluate(() => {
      const parse = (c) => {
        let m = /rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/.exec(c);
        if (m) return [+m[1], +m[2], +m[3], m[4] === undefined ? 1 : +m[4]];
        m = /color\(srgb ([\d.]+) ([\d.]+) ([\d.]+)(?: \/ ([\d.]+))?\)/.exec(c);
        if (m) return [+m[1] * 255, +m[2] * 255, +m[3] * 255, m[4] === undefined ? 1 : +m[4]];
        return null;
      };
      const lum = ([r, g, b]) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
      const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
      const bgOf = (e) => {
        const layers = [];
        for (let n = e; n && n.nodeType === 1; n = n.parentElement) {
          const c = parse(getComputedStyle(n).backgroundColor);
          if (c && c[3] > 0) { layers.push(c); if (c[3] >= 1) break; }
        }
        let out = [255, 255, 255];
        for (const c of layers.reverse()) out = out.map((v, i) => v * (1 - c[3]) + c[i] * c[3]);
        return out;
      };
      const sel = [".op.active .on", ".linklike", "main a", "footer a", ".error .et", "ul.fp li", ".ed-sec .sp",
        ".chip", ".note", ".tabs [role=tab]", "label.field > span", ".result-intro p"];
      const out = [];
      for (const s of sel) for (const e of document.querySelectorAll(s)) {
        if (!e.offsetParent || !e.textContent.trim()) continue;
        const fg = parse(getComputedStyle(e).color);
        if (!fg) continue;
        const r = ratio(fg, bgOf(e));
        if (r < 4.5) out.push(s + " '" + e.textContent.trim().slice(0, 30) + "' " + r.toFixed(2) + ":1");
      }
      return [...new Set(out)];
    });
    for (const b of bad) fail(`${lang} ${theme} contrast`, b);
    if (SHOTS && theme === "dark") await page.screenshot({ path: path.join(SHOTS, `${lang}-dark-${tab.slice(4).toLowerCase()}.png`) });
  }
  await page.evaluate(() => document.documentElement.removeAttribute("data-theme"));
}

// ---- main --------------------------------------------------------------------
const server = await serve();
const base = `http://127.0.0.1:${server.address().port}/`;
if (!existsSync(path.join(APPS, "r", "vendor", "manifest.json")) || !existsSync(path.join(APPS, "py", "vendor", "manifest.json"))) {
  console.error("Run node apps/build.mjs first"); process.exit(2);
}
if (SHOTS) await fs.mkdir(SHOTS, { recursive: true });
const browser = await chromium.launch();
const results = {};
try {
  for (const lang of WHICH) {
    const t0 = Date.now();
    let page;
    try { page = await boot(browser, base, lang); }
    catch (e) { fail(lang, "the app did not start: " + e.message); continue; }
    console.log(`${lang}: booted in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
    const record = results[lang] = {};
    const examples = (await page.$$eval("#exampleSel option", (os) => os.map((o) => [o.value, o.textContent]))).filter(([v]) => v);
    let n = 0;
    for (const [value, name] of examples) {
      if (n++ >= MAX_EX) break;
      await chooseExample(page, value);
      if (SHOTS && n === 1) await page.screenshot({ path: path.join(SHOTS, `${lang}-start.png`) });
      await runAll(page, lang, name, record);
      console.log(`${lang}: ${name} done`);
    }
    await buildTheory(page, lang);
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, `${lang}-editor.png`) });
    await runAll(page, lang, "edited theory", record);
    if (SHOTS) {
      await page.click('.op[data-op="preregister"]'); await page.click("#runBtn"); await idle(page);
      await page.screenshot({ path: path.join(SHOTS, `${lang}-prereg.png`) });
      await page.click('.op[data-op="post_severity"]'); await page.click("#runBtn"); await idle(page);
      await page.screenshot({ path: path.join(SHOTS, `${lang}-post-severity.png`) });
    }
    await linkRoundTrip(browser, page, base, lang);
    record["parse error"] = { text: await brokenSource(page, lang) };
    if (!flag("skip-layout")) { await layout(page, lang); await contrast(page, lang); }
    for (const e of page.errors) if (!/favicon|ERR_ABORTED/.test(e)) fail(`${lang} console`, e.slice(0, 300));
    await page.context().close();
  }
} finally {
  await browser.close();
  server.close();
}

for (const [lang, rec] of Object.entries(results)) {
  const all = Object.entries(rec).filter(([k]) => k !== "parse error");
  console.log(`${lang}: ${all.filter(([, r]) => r.ran).length} results, ${all.filter(([, r]) => r.waited).length} waiting for a prior or a rival`);
}

// The two apps' text, where the packages promise the same output.
if (results.r && results.py) {
  let compared = 0;
  for (const key of Object.keys(results.r)) {
    if (key === "parse error" || !(key in results.py)) continue;
    if (results.r[key].ran !== results.py[key].ran) { fail("R vs Python " + key, "one app ran it and the other did not"); continue; }
    if (!results.r[key].ran) continue;
    compared++;
    const a = results.r[key].text, b = results.py[key].text;
    if (a !== b) {
      let i = 0;
      while (i < a.length && a[i] === b[i]) i++;
      fail("R vs Python " + key, `the text differs at ${i}: R "…${a.slice(Math.max(0, i - 60), i + 80)}" Python "…${b.slice(Math.max(0, i - 60), i + 80)}"`);
    }
  }
  console.log(`compared ${compared} results across the two apps`);
}
console.log(failures.length ? `${failures.length} failures` : "browser checks passed");
process.exit(failures.length ? 1 : 0);
