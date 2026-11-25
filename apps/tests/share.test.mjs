// apps/shared/share.js writes the session into the URL fragment: JSON,
// compressed with deflate-raw and encoded as base64url. A link must read back
// as the state it was made from, use only characters a URL fragment keeps and
// stay below the limit for every example the apps offer.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { randomBytes } from "node:crypto";
import zlib from "node:zlib";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const ctx = { TextEncoder, TextDecoder, Blob, Response, CompressionStream, DecompressionStream, btoa, atob, JSON, Uint8Array, String };
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(readFileSync(path.join(here, "..", "shared", "share.js"), "utf8"), ctx);
const share = ctx.__tfShare;

test("a link reads back as the state it was made from", async () => {
  const state = { v: 1, op: "simulate", params: { method: "exact", steps: 30, dt: 0.1 }, run: true,
    theory: { name: "théorie.yaml", format: "yaml", text: "id: x\ntitle: \"Ünïcode — and emoji 🧪\"\n" } };
  const enc = await share.encode(state);
  assert.match(enc, /^[A-Za-z0-9_-]+$/, "only base64url characters");
  assert.deepEqual(JSON.parse(JSON.stringify(await share.decode(enc))), state);
});

test("a link that is not one is refused", async () => {
  await assert.rejects(share.decode("not a link!"), /base64url/);
  await assert.rejects(share.decode("AAAA"));
});

test("every example the apps offer fits in a link as text", async () => {
  const dirs = [path.join(here, "..", "examples"), path.join(here, "..", "..", "fixtures")];
  for (const dir of dirs) {
    for (const f of readdirSync(dir).filter((x) => x.endsWith(".theory.yaml"))) {
      const text = readFileSync(path.join(dir, f), "utf8");
      const enc = await share.encode({ v: 1, op: "check", params: {}, run: false, theory: { name: f, format: "yaml", text } });
      assert.ok(enc.length < share.LIMIT, `${f}: ${enc.length} characters`);
      assert.ok(enc.length < text.length, `${f}: compression makes the link shorter than the file`);
    }
  }
});

test("a theory too large for a link is longer than the limit once encoded", async () => {
  // Random text does not compress, so the encoded state outgrows the limit.
  const text = randomBytes(20000).toString("base64");
  const enc = await share.encode({ v: 1, theory: { text } });
  assert.ok(enc.length > share.LIMIT);
});

// A link is refused before it is decompressed whole: one longer than the
// limit at once, and one within the limit that would decompress past
// MAX_BYTES as soon as its text passes that size. 12 MB of one letter
// compresses to about 15,700 characters.
test("a link longer than the limit, or one that decompresses past MAX_BYTES, is refused", async () => {
  const b64url = (buf) => buf.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  await assert.rejects(share.decode("A".repeat(share.LIMIT + 1)), /longer than 16000 characters/);
  const bomb = b64url(zlib.deflateRawSync(Buffer.from(JSON.stringify({ v: 1, theory: { text: "title: " + "a".repeat(12e6) } }))));
  assert.ok(bomb.length <= share.LIMIT, `the bomb takes ${bomb.length} characters`);
  await assert.rejects(share.decode(bomb), /holds more than 1048576 bytes/);
  // A link just under the cap still reads.
  const big = { v: 1, theory: { text: "a".repeat(share.MAX_BYTES - 100) } };
  const enc = b64url(zlib.deflateRawSync(Buffer.from(JSON.stringify(big))));
  assert.equal((await share.decode(enc)).theory.text.length, share.MAX_BYTES - 100);
});
