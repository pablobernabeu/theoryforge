// apps/shared/markdown.js renders the preregistration and the dossier. It must
// render the part of Markdown the packages write, and it must never pass on
// markup a theory file carries in a statement or a label.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const ctx = {};
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(readFileSync(path.join(here, "..", "shared", "markdown.js"), "utf8"), ctx);
const { toHtml } = ctx.__tfMarkdown;
const EXPECTED = path.join(here, "..", "..", "fixtures", "expected");

// Every tag in the output, by name.
const tags = (html) => [...new Set([...html.matchAll(/<\/?([a-z0-9]+)/g)].map((m) => m[1]))].sort();
const ALLOWED = ["a", "code", "div", "em", "h1", "h2", "h3", "h4", "h5", "h6", "li", "ol", "p", "strong", "table", "tbody", "td", "th", "thead", "tr", "ul"];

test("headings, nested lists, tables and emphasis render as the documents use them", () => {
  const html = toHtml("# Title\n\n- Theory ID: t\n\n## Hypotheses\n1. [point] Claim. (pred1)\n   - Test record: untested\n2. Second\n\n| item | status |\n| --- | --- |\n| falsifiability | pass |\n\n_None: every pair is adjacent._\n");
  assert.match(html, /<h1>Title<\/h1>/);
  assert.match(html, /<ol><li>\[point\] Claim\. \(pred1\)<ul><li>Test record: untested<\/li><\/ul><\/li><li>Second<\/li><\/ol>/);
  assert.match(html, /<thead><tr><th>item<\/th><th>status<\/th><\/tr><\/thead><tbody><tr><td>falsifiability<\/td><td>pass<\/td><\/tr><\/tbody>/);
  assert.match(html, /<p><em>None: every pair is adjacent\.<\/em><\/p>/);
});

test("identifiers and independence statements keep their underscores", () => {
  const html = toHtml("- c_arousal _||_ c_avoidance | c_perceived_threat\n- see `c_x_y` and snake_case_name");
  assert.match(html, /c_arousal _\|\|_ c_avoidance \| c_perceived_threat/);
  assert.match(html, /<code>c_x_y<\/code> and snake_case_name/);
  assert.doesNotMatch(html, /<em>/);
});

test("markup in the text is escaped, and only http and https addresses become links", () => {
  const html = toHtml('- <script>alert(1)</script> <img src=x onerror="alert(2)">\n- [x](javascript:alert(3)) and [doc](https://doi.org/10.1/x?a=1&b="2")\n- `<b>code</b>`');
  assert.doesNotMatch(html, /<script|<img|<b>/);
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.doesNotMatch(html, /href="javascript/);
  assert.match(html, /<a href="https:\/\/doi\.org\/10\.1\/x\?a=1&amp;b=&quot;2&quot;" target="_blank" rel="noopener noreferrer">doc<\/a>/);
  assert.match(html, /<code>&lt;b&gt;code&lt;\/b&gt;<\/code>/);
  assert.deepEqual(tags(html).filter((t) => !ALLOWED.includes(t)), []);
});

test("every golden preregistration and dossier renders with the allowed tags and loses no text", () => {
  const files = readdirSync(EXPECTED).filter((f) => /\.(prereg|dossier)\.md$/.test(f));
  assert.ok(files.length >= 4);
  for (const f of files) {
    const md = readFileSync(path.join(EXPECTED, f), "utf8");
    const html = toHtml(md);
    assert.deepEqual(tags(html).filter((t) => !ALLOWED.includes(t)), [], f);
    // The words of the document survive, markup aside.
    const text = html.replace(/<[^>]+>/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&");
    for (const word of md.match(/[A-Za-z]{4,}/g)) assert.ok(text.includes(word), `${f}: ${word}`);
    const headings = (md.match(/^#{1,6} /gm) || []).length;
    assert.equal((html.match(/<h\d>/g) || []).length, headings, f);
  }
});

test("an address in quotes or angle brackets links to itself and leaves the quote or bracket as text", () => {
  const html = toHtml('See "https://example.org/x" and <https://osf.io/xyz>, (\'https://osf.io/abc\') and https://a.org/?a=1&b=2.');
  assert.match(html, /&quot;<a href="https:\/\/example\.org\/x" target="_blank" rel="noopener noreferrer">https:\/\/example\.org\/x<\/a>&quot;/);
  assert.match(html, /&lt;<a href="https:\/\/osf\.io\/xyz" target="_blank" rel="noopener noreferrer">https:\/\/osf\.io\/xyz<\/a>&gt;,/);
  assert.match(html, /&#39;<a href="https:\/\/osf\.io\/abc"[^>]*>https:\/\/osf\.io\/abc<\/a>&#39;\)/);
  assert.match(html, /href="https:\/\/a\.org\/\?a=1&amp;b=2"/);
  assert.doesNotMatch(html, /&quot"|&gt"|&#39"|<\/a>;/);
  // An apostrophe inside an address stays in it, and a bare scheme is no link.
  assert.match(toHtml("https://en.wikipedia.org/wiki/Hick's_law."), /href="https:\/\/en\.wikipedia\.org\/wiki\/Hick&#39;s_law"/);
  assert.doesNotMatch(toHtml("see https://."), /<a /);
});
