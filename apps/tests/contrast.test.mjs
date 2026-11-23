// Text colours of the apps against every surface they are set on, in the light
// and the dark theme: WCAG 2 AA asks for 4.5:1. The accent colour of each app
// is a fill, which reads at less than that as text on the dark panels, so text
// takes --accent-text, which each runtime gives a shade per theme. The tinted
// surfaces are the color-mix() fills of app.css, mixed here as the browser
// mixes them in sRGB.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const css = readFileSync(path.join(here, "..", "shared", "app.css"), "utf8");

function block(selector) {
  const i = css.indexOf(selector + " {");
  assert.ok(i >= 0, "app.css has " + selector);
  const body = css.slice(i, css.indexOf("}", i));
  return Object.fromEntries([...body.matchAll(/--([\w-]+):\s*(#[0-9a-fA-F]{6})\b/g)].map((m) => [m[1], m[2].toLowerCase()]));
}
const LIGHT = block(":root");
const DARK = block('html[data-theme="dark"]');

function runtime(file) {
  let src = readFileSync(path.join(here, "..", file), "utf8");
  src = src.replace(/^import .*$/m, "").replace("window.TF.start(RT);", "globalThis.__RT = RT;");
  const ctx = { window: { TF: { DIAG_SVG: [] } }, TextEncoder, TextDecoder, JSON, console };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(src, ctx);
  return ctx.__RT;
}

const rgb = (h) => h.replace("#", "").match(/../g).map((x) => parseInt(x, 16));
const mix = (a, b, p) => "#" + rgb(a).map((v, i) => Math.round(v * p + rgb(b)[i] * (1 - p)).toString(16).padStart(2, "0")).join("");
function luminance(hex) {
  const c = rgb(hex).map((v) => v / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
const contrast = (a, b) => { const [x, y] = [luminance(a), luminance(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

test("the dark media block and the dark theme set the same colours", () => {
  const media = css.match(/@media \(prefers-color-scheme: dark\)\s*\{\s*:root:not\(\[data-theme="light"\]\)\s*\{([^}]*)\}/);
  assert.ok(media, "app.css follows a dark system theme");
  const tokens = Object.fromEntries([...media[1].matchAll(/--([\w-]+):\s*(#[0-9a-fA-F]{6})\b/g)].map((m) => [m[1], m[2].toLowerCase()]));
  assert.deepEqual(tokens, DARK);
  assert.match(media[1], /--accent-text:\s*var\(--accent-text-dark/);
  assert.match(css, /html\[data-theme="dark"\] \{[^}]*--accent-text:\s*var\(--accent-text-dark/);
});

for (const file of ["r/r-runtime.js", "py/py-runtime.js"]) {
  const RT = runtime(file);
  for (const [theme, T] of [["light", LIGHT], ["dark", DARK]]) {
    test(`${file}: text meets 4.5:1 on every surface in the ${theme} theme`, () => {
      const accentText = RT.accentText[theme];
      const surfaces = {
        bg: T.bg, panel: T.panel, "panel-2": T["panel-2"],
        "the chosen operation": mix(RT.accent, T.panel, 0.12),
        "a result's reading": mix(RT.accent, T.panel, 0.07),
        "the guide button": mix(RT.accent, T.panel, 0.13),
        "a pressed switch": mix(RT.accent, T.panel, 0.14),
      };
      const boxes = { "an error box": mix(LIGHT.danger, T.panel, 0.12), "a caution": mix(LIGHT.warn, T.panel, 0.12) };
      const low = [];
      const check = (name, fg, bgs) => { for (const [s, bg] of Object.entries(bgs)) { const r = contrast(fg, bg); if (r < 4.5) low.push(`${name} on ${s}: ${r.toFixed(2)}:1`); } };
      check("accent text", accentText, surfaces);
      check("ink", T.ink, Object.assign({}, surfaces, boxes));
      check("soft ink", T["ink-soft"], Object.assign({}, surfaces, boxes));
      check("danger text", T["danger-text"], Object.assign({ bg: T.bg, panel: T.panel, "panel-2": T["panel-2"] }, boxes));
      assert.deepEqual(low, []);
    });
  }
  test(`${file}: white on the accent fill meets 4.5:1, and the fill alone does not in the dark theme`, () => {
    assert.ok(contrast(RT.accentInk, RT.accent) >= 4.5);
    // Why text needs its own token: the fill on the dark panel.
    assert.ok(contrast(RT.accent, DARK.panel) < 4.5);
  });
}

test("text set in the accent colour uses the text token, and fills keep the accent", () => {
  const rules = [...css.matchAll(/([^{}]+)\{([^}]*)\}/g)];
  const offenders = rules.filter(([, sel, body]) => /(^|[\s;])color:\s*var\(--accent\)/.test(body) && !/background/.test(sel)).map(([, sel]) => sel.trim());
  assert.deepEqual(offenders, []);
  assert.match(css, /a \{ color: var\(--accent-text\)/);
  assert.match(css, /\.op\.active \.on \{ color: var\(--accent-text\)/);
});
