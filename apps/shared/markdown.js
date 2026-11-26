/* theoryforge interactive apps: Markdown to HTML for the preregistration and
 * the dossier.
 *
 * The documents the packages write use a small part of Markdown: headings,
 * bulleted and numbered lists nested by indentation, pipe tables, paragraphs,
 * emphasis, code spans and links. This renderer covers that part and no more.
 * It escapes every character of the input before it adds any tag, writes only
 * the tags listed here, with no attribute taken from the input other than a
 * link's http or https address, and so cannot pass on markup that a theory
 * file carries in a statement or a label. Anything else reads as plain text.
 */
(function () {
  "use strict";

  const escHtml = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  // Inline markup of one line of text. Code spans are taken out first, so
  // nothing inside them is read as emphasis or as a link.
  function inline(text) {
    const codes = [];
    let s = String(text).replace(/`([^`]+)`/g, (m, c) => { codes.push(c); return "\u0000" + (codes.length - 1) + "\u0000"; });
    s = escHtml(s);
    // [label](https://...) and bare http(s) addresses. The address is escaped
    // already, so it can hold no quote that would end the attribute.
    const links = [];
    const hold = (html) => { links.push(html); return "\u0001" + (links.length - 1) + "\u0001"; };
    s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, (m, label, href) =>
      hold('<a href="' + href + '" target="_blank" rel="noopener noreferrer">' + label + "</a>"));
    // The text is escaped, so a quote or bracket next to an address is now an
    // entity. The address takes &amp; and, inside it, &#39; but no other
    // entity, and gives its trailing punctuation back to the sentence.
    s = s.replace(/https?:\/\/(?:[^\s<&]|&amp;|&#39;(?=[^\s<&]))+/g, (m) => {
      const href = m.replace(/(?:&amp;|&#39;|[.,;:)])+$/, "");
      if (/^https?:\/\/$/.test(href)) return m;
      return hold('<a href="' + href + '" target="_blank" rel="noopener noreferrer">' + href + "</a>") + m.slice(href.length);
    });
    s = s.replace(/\*\*(?=\S)([^*]*?\S)\*\*/g, "<strong>$1</strong>");
    // Emphasis needs a letter inside and a space or the line's edge outside,
    // so identifiers such as c_arousal and the _||_ of an independence
    // statement stay as they are.
    s = s.replace(/(^|[\s(])_(?=[^\s_])([^_]*?[A-Za-z][^_]*?)_(?=$|[\s).,;:])/g, "$1<em>$2</em>");
    s = s.replace(/(^|[\s(])\*(?=[^\s*])([^*]*?[A-Za-z][^*]*?)\*(?=$|[\s).,;:])/g, "$1<em>$2</em>");
    s = s.replace(/\u0001(\d+)\u0001/g, (m, i) => links[Number(i)]);
    return s.replace(/\u0000(\d+)\u0000/g, (m, i) => "<code>" + escHtml(codes[Number(i)]) + "</code>");
  }

  // The cells of a table row: split at each pipe that is not escaped.
  function cells(line) {
    const inner = line.trim().replace(/^\|/, "").replace(/\|$/, "");
    const out = [];
    let cur = "";
    for (let i = 0; i < inner.length; i++) {
      if (inner[i] === "\\" && inner[i + 1] === "|") { cur += "|"; i++; }
      else if (inner[i] === "|") { out.push(cur.trim()); cur = ""; }
      else cur += inner[i];
    }
    out.push(cur.trim());
    return out;
  }
  const isRule = (line) => /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$/.test(line);
  const LIST = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;

  function toHtml(md) {
    const lines = String(md == null ? "" : md).replace(/\r\n?/g, "\n").split("\n");
    const out = [];
    let para = [];
    const flush = () => { if (para.length) { out.push("<p>" + para.map(inline).join(" ") + "</p>"); para = []; } };
    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      if (!line.trim()) { flush(); i++; continue; }
      const h = /^(#{1,6})\s+(.*?)\s*#*\s*$/.exec(line);
      if (h) { flush(); const n = h[1].length; out.push("<h" + n + ">" + inline(h[2]) + "</h" + n + ">"); i++; continue; }
      if (/^\s*\|/.test(line) && i + 1 < lines.length && isRule(lines[i + 1])) {
        flush();
        const head = cells(line);
        i += 2;
        const body = [];
        while (i < lines.length && /^\s*\|/.test(lines[i])) { body.push(cells(lines[i])); i++; }
        out.push('<div class="md-table"><table><thead><tr>' + head.map((c) => "<th>" + inline(c) + "</th>").join("") +
          "</tr></thead><tbody>" + body.map((r) => "<tr>" + r.map((c) => "<td>" + inline(c) + "</td>").join("") + "</tr>").join("") +
          "</tbody></table></div>");
        continue;
      }
      if (LIST.test(line)) {
        flush();
        const items = [];
        while (i < lines.length) {
          const m = LIST.exec(lines[i]);
          if (m) { items.push({ indent: m[1].replace(/\t/g, "    ").length, ordered: /\d/.test(m[2]), start: parseInt(m[2], 10), text: m[3] }); i++; continue; }
          // A line indented under an item continues it.
          if (lines[i].trim() && /^\s+/.test(lines[i]) && items.length) { items[items.length - 1].text += " " + lines[i].trim(); i++; continue; }
          break;
        }
        out.push(listHtml(items));
        continue;
      }
      para.push(line.trim());
      i++;
    }
    flush();
    return out.join("\n");
  }

  // Nested lists from items with their indentation: an item indented further
  // than the one before it opens a list inside that item.
  function listHtml(items) {
    let html = "";
    const stack = [];
    for (const it of items) {
      while (stack.length && it.indent < stack[stack.length - 1].indent) {
        html += "</li></" + stack.pop().tag + ">";
      }
      const top = stack[stack.length - 1];
      if (!top || it.indent > top.indent) {
        const tag = it.ordered ? "ol" : "ul";
        html += "<" + tag + (it.ordered && it.start > 1 ? ' start="' + it.start + '"' : "") + ">";
        stack.push({ indent: it.indent, tag });
      } else {
        html += "</li>";
      }
      html += "<li>" + inline(it.text);
    }
    while (stack.length) html += "</li></" + stack.pop().tag + ">";
    return html;
  }

  const api = { toHtml, inline };
  if (typeof window !== "undefined" && window.TF) window.TF.markdown = api;
  if (typeof globalThis !== "undefined") globalThis.__tfMarkdown = api;
})();
