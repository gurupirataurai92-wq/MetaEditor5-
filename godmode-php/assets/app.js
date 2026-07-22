/* Client-side polish for the server-rendered pages:
   confirm-delete, chart tooltips, and the Ctrl+K command palette. */
(function () {
  "use strict";
  const $ = (s, el) => (el || document).querySelector(s);
  const esc = s => String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

  /* ---------- confirm destructive forms ---------- */
  document.addEventListener("submit", e => {
    const f = e.target;
    if (f.dataset.confirm && !window.confirm(f.dataset.confirm)) e.preventDefault();
  });

  /* ---------- chart tooltip ---------- */
  const tip = $("#chart-tip");
  document.addEventListener("mousemove", e => {
    if (!tip) return;
    const bar = e.target.closest && e.target.closest(".bar[data-tip]");
    if (!bar) { tip.hidden = true; return; }
    const parts = bar.getAttribute("data-tip").split("|");
    tip.innerHTML = esc(parts[0]) + "<br><span class='t-val'>" + esc(parts[1]) + "</span>";
    tip.hidden = false;
    tip.style.left = Math.min(e.clientX + 14, window.innerWidth - 170) + "px";
    tip.style.top = (e.clientY - 14) + "px";
  });

  /* ---------- command palette ---------- */
  const cmdk = {
    open: false, sel: 0, results: [],
    el: $("#cmdk"), input: $("#cmdk-input"), out: $("#cmdk-results"),
    show() {
      this.open = true; this.sel = 0; this.el.hidden = false;
      this.input.value = ""; this.input.focus(); this.filter("");
    },
    hide() { this.open = false; this.el.hidden = true; },
    filter(query) {
      const q = query.toLowerCase().trim();
      const all = window.CMD_INDEX || [];
      this.results = (q
        ? all.filter(x => (x.label + " " + x.tag + " " + x.sub).toLowerCase().includes(q))
        : all).slice(0, 12);
      this.sel = 0; this.paint();
    },
    paint() {
      this.out.innerHTML = this.results.length
        ? this.results.map((r, i) => `<div class="cmdk-item ${i === this.sel ? "sel" : ""}" data-i="${i}">
            <span class="tag">${esc(r.tag)}</span><span>${esc(r.label)}</span>
            <span class="sub">${esc(r.sub)}</span></div>`).join("")
        : `<div class="cmdk-empty">Nothing matches. Try a client, invoice number or page name.</div>`;
    },
    pick(i) { const r = this.results[i]; if (r) { this.hide(); location.href = r.href; } }
  };

  document.addEventListener("keydown", e => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
      e.preventDefault(); cmdk.open ? cmdk.hide() : cmdk.show(); return;
    }
    if (!cmdk.open) return;
    if (e.key === "Escape") cmdk.hide();
    else if (e.key === "ArrowDown") { e.preventDefault(); cmdk.sel = Math.min(cmdk.sel + 1, cmdk.results.length - 1); cmdk.paint(); }
    else if (e.key === "ArrowUp") { e.preventDefault(); cmdk.sel = Math.max(cmdk.sel - 1, 0); cmdk.paint(); }
    else if (e.key === "Enter") { e.preventDefault(); cmdk.pick(cmdk.sel); }
  });
  if (cmdk.input) {
    cmdk.input.addEventListener("input", e => cmdk.filter(e.target.value));
    cmdk.el.addEventListener("click", e => {
      if (e.target.id === "cmdk") return cmdk.hide();
      const item = e.target.closest(".cmdk-item");
      if (item) cmdk.pick(Number(item.dataset.i));
    });
  }
})();
