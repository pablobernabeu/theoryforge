// The site's landing and 404 pages (.github/landing.html and .github/404.html):
// link contrast under a dark operating-system theme, the theme toggle with
// blocked or foreign stored values, and the 404 page's links to the apps.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import { makeWindow } from "./dom.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const PAGES = {
  landing: path.join(here, "..", "..", ".github", "landing.html"),
  "404": path.join(here, "..", "..", ".github", "404.html"),
};
const read = (p) => readFileSync(p, "utf8");

// WCAG 2.x relative luminance and contrast ratio.
function luminance(hex) {
  const c = hex.replace("#", "").match(/../g).map((h) => parseInt(h, 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}
function darkMediaTokens(html) {
  const block = html.match(/@media \(prefers-color-scheme: dark\)\s*\{\s*:root\s*\{([^}]*)\}/);
  assert.ok(block, "the page has a dark media block");
  return Object.fromEntries([...block[1].matchAll(/--([\w-]+):\s*(#[0-9a-fA-F]{6})/g)].map((m) => [m[1], m[2].toLowerCase()]));
}

// Run a page's inline toggle script against a stub document holding its button.
function runToggle(file, opts) {
  const ctx = makeWindow(opts);
  const btn = ctx.document.createElement("button");
  btn.setAttribute("id", "themeToggle");
  ctx.document.body.append(btn);
  const script = read(file).match(/<script>([\s\S]*?)<\/script>/)[1];
  vm.runInContext(script, ctx);
  return { root: ctx.document.documentElement, btn, ctx };
}
const SUN = "&#9728;", MOON = "&#9789;";

for (const [name, file] of Object.entries(PAGES)) {
  test(`${name}: links meet WCAG AA contrast under a dark system theme`, () => {
    const t = darkMediaTokens(read(file));
    assert.ok(t.link, "the dark media block sets --link");
    const ratio = contrast(t.link, t.bg);
    assert.ok(ratio >= 4.5, `link contrast ${ratio.toFixed(2)}:1 is below 4.5:1`);
    assert.equal(ratio.toFixed(2), "10.37");
  });

  test(`${name}: the toggle works when the browser blocks site storage`, async () => {
    const { root, btn } = runToggle(file, { storage: "blocked", prefersDark: false });
    assert.equal(root.getAttribute("data-theme"), null);
    assert.equal(btn.innerHTML, MOON);
    await btn.click();
    assert.equal(root.getAttribute("data-theme"), "dark");
    await btn.click();
    assert.equal(root.getAttribute("data-theme"), "light");
  });

  test(`${name}: a stored "system" follows the operating system`, async () => {
    // The apps cycle light, dark and system through the same key.
    const { root, btn } = runToggle(file, { stored: { "tf-theme": "system" }, prefersDark: true });
    assert.equal(root.getAttribute("data-theme"), null);
    assert.equal(btn.innerHTML, SUN, "the page is dark, so the toggle offers light");
    await btn.click();
    assert.equal(root.getAttribute("data-theme"), "light");
  });

  test(`${name}: a stored light or dark choice is applied and saved on toggle`, async () => {
    const { root, btn, ctx } = runToggle(file, { stored: { "tf-theme": "dark" }, prefersDark: false });
    assert.equal(root.getAttribute("data-theme"), "dark");
    await btn.click();
    assert.equal(ctx.localStorage.getItem("tf-theme"), "light");
  });
}

test("404: the page links both apps by absolute path", () => {
  const html = read(PAGES["404"]);
  assert.match(html, /href="\/theoryforge\/apps\/r\/"/);
  assert.match(html, /href="\/theoryforge\/apps\/py\/"/);
});
