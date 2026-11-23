/* theoryforge interactive apps: the session as a link.
 *
 * The app's state, the theory and the chosen operation, is written as JSON,
 * compressed with the browser's own CompressionStream ('deflate-raw') and
 * encoded as base64url, so that it can stand in the URL fragment. Browsers do
 * not send the fragment to the server, so a link carries the theory without
 * anything being stored or received elsewhere. Links longer than LIMIT
 * characters are refused, since mail clients and chat programs cut or wrap
 * long addresses.
 */
(function () {
  "use strict";

  const LIMIT = 16000;

  function toBase64Url(bytes) {
    let bin = "";
    for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  function fromBase64Url(s) {
    if (!/^[A-Za-z0-9_-]*$/.test(s)) throw new Error("the link holds characters that base64url does not use");
    const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  async function pipe(bytes, stream) {
    const s = new Blob([bytes]).stream().pipeThrough(stream);
    return new Uint8Array(await new Response(s).arrayBuffer());
  }

  async function encode(obj) {
    const json = new TextEncoder().encode(JSON.stringify(obj));
    return toBase64Url(await pipe(json, new CompressionStream("deflate-raw")));
  }
  async function decode(str) {
    const bytes = await pipe(fromBase64Url(str), new DecompressionStream("deflate-raw"));
    return JSON.parse(new TextDecoder().decode(bytes));
  }

  const api = { encode, decode, LIMIT };
  if (typeof window !== "undefined" && window.TF) window.TF.share = api;
  if (typeof globalThis !== "undefined") globalThis.__tfShare = api;
})();
