// Meridian brand: publish the scrollbar width, so the full-bleed footer can be
// exactly as wide as the viewport. `100vw` includes the scrollbar, so a band
// sized from it overhangs the page by that much at each side; the difference
// between innerWidth and the document's clientWidth is the amount to give back.
// Where this script does not run the stylesheet falls back to plain 100vw.
function meridianScrollbarWidth() {
  var w = window.innerWidth - document.documentElement.clientWidth;
  document.documentElement.style.setProperty("--scrollbar-width", (w > 0 ? w : 0) + "px");
}
meridianScrollbarWidth();
window.addEventListener("resize", meridianScrollbarWidth);
document.addEventListener("DOMContentLoaded", meridianScrollbarWidth);

// Normalise the search field's label to a plain "Search".
// pkgdown's built-in search input has the placeholder "Search for" and an
// aria-label of its own; the house style is the shorter word for both. This
// rewrites only the placeholder and the accessible name; the search behaviour
// is untouched.
document.addEventListener("DOMContentLoaded", function () {
  document
    .querySelectorAll('#search-input, input[type="search"], input.form-control[role="searchbox"]')
    .forEach(function (el) {
      el.setAttribute("placeholder", "Search");
      el.setAttribute("aria-label", "Search");
    });
});
