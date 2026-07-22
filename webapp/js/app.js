/* ============================================================
   GOD MODE — Business Consultant OS
   Modules: Dashboard, OODA Engine, Consulting/CRM, Auditing,
   Accounting, Microfinance, Tax & Compliance, HR & Payroll,
   Risk Register, Financial Analysis.
   ============================================================ */

/* ---------- tiny helpers ---------- */
const $ = (s, el) => (el || document).querySelector(s);
const $$ = (s, el) => Array.from((el || document).querySelectorAll(s));
const esc = s => String(s == null ? "" : s)
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const money = n => {
  const cur = DB.settings.currency || "USD";
  const v = Number(n) || 0;
  return v.toLocaleString(undefined, { style: "currency", currency: cur, maximumFractionDigits: 2 });
};
const num = n => (Number(n) || 0).toLocaleString(undefined, { maximumFractionDigits: 2 });
const today = () => new Date().toISOString().slice(0, 10);
const daysUntil = d => Math.ceil((new Date(d) - new Date(today())) / 86400000);

function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(t._h);
  t._h = setTimeout(() => { t.hidden = true; }, 2600);
}

function openModal(html, onMount) {
  $("#modal").innerHTML = html;
  $("#modal-backdrop").hidden = false;
  if (onMount) onMount($("#modal"));
  const f = $("#modal input, #modal select, #modal textarea");
  if (f) f.focus();
}
function closeModal() { $("#modal-backdrop").hidden = true; $("#modal").innerHTML = ""; }
$("#modal-backdrop").addEventListener("click", e => { if (e.target.id === "modal-backdrop") closeModal(); });
document.addEventListener("keydown", e => { if (e.key === "Escape") closeModal(); });

const clientName = id => (DB.clients.find(c => c.id === id) || {}).name || "—";
const clientOptions = sel =>
  `<option value="">— none / internal —</option>` +
  DB.clients.map(c => `<option value="${c.id}" ${c.id === sel ? "selected" : ""}>${esc(c.name)}</option>`).join("");

/* ============================================================
   ACCOUNTING computations
   ============================================================ */
function accountBalances() {
  const bal = {}; // id -> debit-credit net
  DB.accounts.forEach(a => bal[a.id] = 0);
  DB.journal.forEach(j => {
    bal[j.debit] = (bal[j.debit] || 0) + Number(j.amount);
    bal[j.credit] = (bal[j.credit] || 0) - Number(j.amount);
  });
  return bal;
}
function normalBalance(acc, raw) {
  // Assets/Expenses are debit-normal; others credit-normal.
  return (acc.type === "Asset" || acc.type === "Expense") ? raw : -raw;
}
function financials() {
  const bal = accountBalances();
  const by = t => DB.accounts.filter(a => a.type === t)
    .map(a => ({ acc: a, amt: normalBalance(a, bal[a.id] || 0) }));
  const sum = rows => rows.reduce((s, r) => s + r.amt, 0);
  const income = by("Income"), expense = by("Expense");
  const assets = by("Asset"), liabs = by("Liability"), equity = by("Equity");
  const netIncome = sum(income) - sum(expense);
  return { income, expense, assets, liabs, equity, netIncome,
    totalAssets: sum(assets), totalLiabs: sum(liabs), totalEquity: sum(equity) };
}

/* ============================================================
   MICROFINANCE computations
   ============================================================ */
function loanSchedule(loan) {
  const P = Number(loan.principal), months = Number(loan.months);
  const annual = Number(loan.rate) / 100;
  const rows = [];
  if (!P || !months) return { rows, totalInterest: 0, totalDue: P, payment: 0 };
  if (loan.method === "flat") {
    const totalInterest = P * annual * (months / 12);
    const payment = (P + totalInterest) / months;
    let balance = P + totalInterest;
    for (let m = 1; m <= months; m++) {
      balance -= payment;
      rows.push({ m, payment, principal: P / months, interest: totalInterest / months, balance: Math.max(0, balance) });
    }
    return { rows, totalInterest, totalDue: P + totalInterest, payment };
  }
  // declining balance (amortized)
  const r = annual / 12;
  const payment = r === 0 ? P / months : P * r / (1 - Math.pow(1 + r, -months));
  let bal = P, totalInterest = 0;
  for (let m = 1; m <= months; m++) {
    const interest = bal * r;
    const princ = payment - interest;
    bal = Math.max(0, bal - princ);
    totalInterest += interest;
    rows.push({ m, payment, principal: princ, interest, balance: bal });
  }
  return { rows, totalInterest, totalDue: P + totalInterest, payment };
}
const loanOutstanding = l => Math.max(0, loanSchedule(l).totalDue - (Number(l.repaid) || 0));
function portfolioStats() {
  const active = DB.loans.filter(l => l.status === "active");
  const outstanding = active.reduce((s, l) => s + loanOutstanding(l), 0);
  const par30 = active.filter(l => Number(l.daysOverdue) > 30)
    .reduce((s, l) => s + loanOutstanding(l), 0);
  return { count: active.length, outstanding, par30,
    parPct: outstanding ? (par30 / outstanding) * 100 : 0 };
}

/* ============================================================
   VIEWS
   ============================================================ */
const OODA_STAGES = ["Observe", "Orient", "Decide", "Act"];
const views = {};

/* ---------- Dashboard ---------- */
views.dashboard = () => {
  const fin = financials();
  const pf = portfolioStats();
  const openFindings = DB.findings.filter(f => f.status === "open");
  const critFindings = openFindings.filter(f => f.severity === "critical" || f.severity === "high").length;
  const openRisks = DB.risks.filter(r => r.status === "open");
  const highRisks = openRisks.filter(r => r.likelihood * r.impact >= 15).length;
  const activeEng = DB.engagements.filter(e => e.status === "active");
  const pipeline = DB.engagements.filter(e => e.status === "proposal").reduce((s, e) => s + Number(e.fee || 0), 0);
  const activeFees = activeEng.reduce((s, e) => s + Number(e.fee || 0), 0);
  const dueSoon = DB.obligations.filter(o => o.status === "pending" && daysUntil(o.dueDate) <= 14);
  const overdue = DB.obligations.filter(o => o.status === "pending" && daysUntil(o.dueDate) < 0);
  const activeLoops = DB.ooda.filter(o => o.status === "active");
  const payroll = DB.employees.reduce((s, e) => s + Number(e.gross || 0), 0);

  const upcoming = DB.obligations.filter(o => o.status === "pending")
    .sort((a, b) => a.dueDate.localeCompare(b.dueDate)).slice(0, 6);

  return `
  <div class="view-head">
    <div><h1>Command Dashboard</h1>
      <div class="sub">Every practice area at a glance — observe first, then act.</div></div>
    <div class="head-actions">
      <button class="btn btn-primary" data-action="nav" data-view="ooda">⟳ Run OODA Loop</button>
    </div>
  </div>

  <div class="grid grid-4">
    <div class="stat accent"><div class="label">Clients</div><div class="value">${DB.clients.length}</div>
      <div class="hint">${activeEng.length} active engagement${activeEng.length === 1 ? "" : "s"}</div></div>
    <div class="stat ${fin.netIncome >= 0 ? "good" : "bad"}"><div class="label">Net Income (books)</div>
      <div class="value">${money(fin.netIncome)}</div><div class="hint">${DB.journal.length} journal entries</div></div>
    <div class="stat"><div class="label">Loan Portfolio</div><div class="value">${money(pf.outstanding)}</div>
      <div class="hint">${pf.count} active loans</div></div>
    <div class="stat ${pf.parPct > 5 ? "bad" : "good"}"><div class="label">PAR &gt; 30 days</div>
      <div class="value">${num(pf.parPct)}%</div><div class="hint">target &lt; 5%</div></div>
    <div class="stat ${critFindings ? "bad" : "good"}"><div class="label">Open Audit Findings</div>
      <div class="value">${openFindings.length}</div><div class="hint">${critFindings} high / critical</div></div>
    <div class="stat ${highRisks ? "warn" : ""}"><div class="label">Open Risks</div>
      <div class="value">${openRisks.length}</div><div class="hint">${highRisks} severe (score ≥ 15)</div></div>
    <div class="stat ${overdue.length ? "bad" : dueSoon.length ? "warn" : "good"}"><div class="label">Compliance</div>
      <div class="value">${overdue.length ? overdue.length + " overdue" : dueSoon.length + " due soon"}</div>
      <div class="hint">next 14 days window</div></div>
    <div class="stat accent"><div class="label">Active OODA Loops</div><div class="value">${activeLoops.length}</div>
      <div class="hint">decision cycles in flight</div></div>
  </div>

  <div class="grid grid-2 mt">
    <div class="card">
      <h3>Revenue Snapshot</h3>
      <div class="report-line"><span>Active engagement fees</span><span class="amt">${money(activeFees)}</span></div>
      <div class="report-line"><span>Proposal pipeline</span><span class="amt">${money(pipeline)}</span></div>
      <div class="report-line"><span>Monthly payroll cost</span><span class="amt neg">${money(payroll)}</span></div>
      <div class="report-line total"><span>Net income per books</span>
        <span class="amt ${fin.netIncome >= 0 ? "pos" : "neg"}">${money(fin.netIncome)}</span></div>
    </div>
    <div class="card">
      <h3>Upcoming Compliance Deadlines</h3>
      ${upcoming.length ? `<div class="tbl-wrap"><table>
        <tr><th>Obligation</th><th>Due</th><th></th></tr>
        ${upcoming.map(o => {
          const d = daysUntil(o.dueDate);
          return `<tr><td>${esc(o.name)}<div class="muted" style="font-size:11px">${esc(o.authority || "")}</div></td>
          <td>${o.dueDate}</td>
          <td>${d < 0 ? `<span class="badge b-red">${-d}d overdue</span>`
            : d <= 14 ? `<span class="badge b-amber">${d}d left</span>`
            : `<span class="badge b-grey">${d}d</span>`}</td></tr>`;
        }).join("")}</table></div>`
      : `<div class="empty">No pending obligations. Add them in Tax &amp; Compliance.</div>`}
    </div>
  </div>

  <div class="card mt">
    <h3>Active OODA Loops</h3>
    ${activeLoops.length ? activeLoops.map(o => `
      <div class="report-line"><span><strong>${esc(o.title)}</strong>
        <span class="muted"> — cycle ${o.cycles + 1}, stage: </span>
        <span class="badge b-gold">${OODA_STAGES[o.stage]}</span></span>
        <button class="btn btn-sm" data-action="nav" data-view="ooda">Open</button></div>`).join("")
    : `<div class="empty">No active decision loops. Every big call should run through OODA.</div>`}
  </div>`;
};

/* ---------- OODA Engine ---------- */
views.ooda = () => {
  const loops = DB.ooda.slice().sort((a, b) => (a.status === "active" ? -1 : 1) - (b.status === "active" ? -1 : 1));
  return `
  <div class="view-head">
    <div><h1>OODA Decision Engine</h1>
      <div class="sub">Observe → Orient → Decide → Act. Cycle faster than the problem changes.</div></div>
    <div class="head-actions"><button class="btn btn-primary" data-action="ooda-new">+ New Loop</button></div>
  </div>
  ${loops.length ? loops.map(o => `
    <div class="ooda-loop">
      <div class="ooda-top">
        <div>
          <div class="ooda-title">${esc(o.title)}
            ${o.status === "done" ? `<span class="badge b-green">Completed</span>` : `<span class="badge b-gold">Cycle ${o.cycles + 1}</span>`}
          </div>
          <div class="muted" style="font-size:12px">${esc(o.objective || "")}</div>
        </div>
        <div>
          <button class="btn btn-icon" data-action="ooda-del" data-id="${o.id}">✕</button>
        </div>
      </div>
      <div class="ooda-stages">
        ${OODA_STAGES.map((s, i) => {
          const key = s.toLowerCase();
          const cls = o.status === "done" ? "done" : i < o.stage ? "done" : i === o.stage ? "current" : "";
          return `<div class="ooda-stage ${cls}">
            <h4>${i + 1}. ${s.toUpperCase()}</h4>
            <p>${o.notes[key] ? esc(o.notes[key]) : `<span class="placeholder">${{
              observe: "Gather raw facts, data, signals.",
              orient: "Analyze context, biases, models.",
              decide: "Choose the course of action.",
              act: "Execute and measure the result."
            }[key]}</span>`}</p>
          </div>`;
        }).join("")}
      </div>
      ${o.status === "active" ? `
      <div class="ooda-foot">
        <button class="btn btn-primary btn-sm" data-action="ooda-note" data-id="${o.id}">✎ ${OODA_STAGES[o.stage]}: add notes &amp; advance</button>
        <button class="btn btn-sm" data-action="ooda-skip" data-id="${o.id}">Advance without notes</button>
        <button class="btn btn-sm btn-ghost" data-action="ooda-done" data-id="${o.id}">Mark loop complete</button>
        <span class="cycle-chip">${o.log.length} past cycle note${o.log.length === 1 ? "" : "s"} archived</span>
      </div>` : ""}
    </div>`).join("")
  : `<div class="card"><div class="empty">No loops yet. Create one for any decision: pricing a proposal, restructuring a client, entering a market.</div></div>`}`;
};

function oodaAdvance(o) {
  if (o.stage < 3) { o.stage++; }
  else {
    // full cycle completed — archive notes, restart at Observe
    o.log.push({ cycle: o.cycles + 1, at: today(), notes: { ...o.notes } });
    o.cycles++;
    o.stage = 0;
    o.notes = { observe: "", orient: "", decide: "", act: "" };
    toast("Cycle " + o.cycles + " archived — loop restarts at Observe.");
  }
  saveDB(); render();
}

/* ---------- Consulting / CRM ---------- */
views.consulting = () => `
  <div class="view-head">
    <div><h1>Consulting &amp; CRM</h1>
      <div class="sub">Clients, engagements, pipeline and strategy (SWOT) per client.</div></div>
    <div class="head-actions">
      <button class="btn" data-action="eng-new">+ Engagement</button>
      <button class="btn btn-primary" data-action="client-new">+ Client</button>
    </div>
  </div>
  <div class="grid grid-2">
    <div class="card">
      <h3>Clients (${DB.clients.length})</h3>
      ${DB.clients.length ? `<div class="tbl-wrap"><table>
        <tr><th>Name</th><th>Industry</th><th>Contact</th><th></th></tr>
        ${DB.clients.map(c => `<tr>
          <td><strong>${esc(c.name)}</strong></td><td>${esc(c.industry || "—")}</td><td>${esc(c.contact || "—")}</td>
          <td style="white-space:nowrap">
            <button class="btn btn-icon" data-action="client-swot" data-id="${c.id}" title="SWOT">S/W</button>
            <button class="btn btn-icon" data-action="client-del" data-id="${c.id}">✕</button>
          </td></tr>`).join("")}
      </table></div>` : `<div class="empty">No clients yet.</div>`}
    </div>
    <div class="card">
      <h3>Engagements (${DB.engagements.length})</h3>
      ${DB.engagements.length ? `<div class="tbl-wrap"><table>
        <tr><th>Client</th><th>Service</th><th class="num">Fee</th><th>Status</th><th></th></tr>
        ${DB.engagements.map(e => `<tr>
          <td>${esc(clientName(e.clientId))}</td><td>${esc(e.service)}</td>
          <td class="num">${money(e.fee)}</td>
          <td>${e.status === "active" ? `<span class="badge b-green">active</span>`
              : e.status === "proposal" ? `<span class="badge b-blue">proposal</span>`
              : `<span class="badge b-grey">completed</span>`}</td>
          <td style="white-space:nowrap">
            ${e.status !== "completed" ? `<button class="btn btn-icon" data-action="eng-next" data-id="${e.id}" title="advance status">→</button>` : ""}
            <button class="btn btn-icon" data-action="eng-del" data-id="${e.id}">✕</button>
          </td></tr>`).join("")}
      </table></div>` : `<div class="empty">No engagements yet.</div>`}
    </div>
  </div>
  ${DB.clients.filter(c => c.swot && Object.values(c.swot).some(x => x.length)).map(c => `
    <div class="card mt">
      <h3>SWOT — ${esc(c.name)}</h3>
      <div class="swot-grid">
        ${[["s", "Strengths"], ["w", "Weaknesses"], ["o", "Opportunities"], ["t", "Threats"]].map(([k, label]) => `
          <div class="swot-cell swot-${k}"><h4>${label.toUpperCase()}</h4>
            <ul>${(c.swot[k] || []).map(x => `<li>• ${esc(x)}</li>`).join("") || `<li class="muted">—</li>`}</ul>
          </div>`).join("")}
      </div>
    </div>`).join("")}`;

/* ---------- Auditing ---------- */
const AUDIT_STAGES = ["planning", "fieldwork", "reporting", "closed"];
views.auditing = () => {
  const open = DB.findings.filter(f => f.status === "open");
  const sevBadge = s => ({ critical: "b-red", high: "b-red", medium: "b-amber", low: "b-blue" }[s] || "b-grey");
  return `
  <div class="view-head">
    <div><h1>Audit Practice</h1>
      <div class="sub">Engagement tracking, findings log and remediation status.</div></div>
    <div class="head-actions">
      <button class="btn" data-action="finding-new">+ Finding</button>
      <button class="btn btn-primary" data-action="audit-new">+ Audit</button>
    </div>
  </div>
  <div class="grid grid-4">
    <div class="stat"><div class="label">Audits</div><div class="value">${DB.audits.length}</div></div>
    <div class="stat ${open.length ? "warn" : "good"}"><div class="label">Open Findings</div><div class="value">${open.length}</div></div>
    <div class="stat ${open.some(f => f.severity === "critical") ? "bad" : "good"}"><div class="label">Critical Open</div>
      <div class="value">${open.filter(f => f.severity === "critical").length}</div></div>
    <div class="stat"><div class="label">Resolved</div><div class="value">${DB.findings.filter(f => f.status === "resolved").length}</div></div>
  </div>
  <div class="card mt">
    <h3>Audit Engagements</h3>
    ${DB.audits.length ? `<div class="tbl-wrap"><table>
      <tr><th>Client</th><th>Scope</th><th>Period</th><th>Stage</th><th></th></tr>
      ${DB.audits.map(a => `<tr>
        <td>${esc(clientName(a.clientId))}</td><td>${esc(a.scope)}</td><td>${esc(a.period)}</td>
        <td><span class="badge ${a.status === "closed" ? "b-grey" : "b-gold"}">${a.status}</span></td>
        <td style="white-space:nowrap">
          ${a.status !== "closed" ? `<button class="btn btn-icon" data-action="audit-next" data-id="${a.id}" title="advance stage">→</button>` : ""}
          <button class="btn btn-icon" data-action="audit-del" data-id="${a.id}">✕</button>
        </td></tr>`).join("")}
    </table></div>` : `<div class="empty">No audits yet.</div>`}
  </div>
  <div class="card mt">
    <h3>Findings Register</h3>
    ${DB.findings.length ? `<div class="tbl-wrap"><table>
      <tr><th>Finding</th><th>Audit</th><th>Severity</th><th>Recommendation</th><th>Status</th><th></th></tr>
      ${DB.findings.map(f => {
        const audit = DB.audits.find(a => a.id === f.auditId);
        return `<tr>
        <td><strong>${esc(f.title)}</strong></td>
        <td>${audit ? esc(clientName(audit.clientId)) + " · " + esc(audit.period) : "—"}</td>
        <td><span class="badge ${sevBadge(f.severity)}">${f.severity}</span></td>
        <td>${esc(f.recommendation || "—")}</td>
        <td>${f.status === "open" ? `<span class="badge b-amber">open</span>` : `<span class="badge b-green">resolved</span>`}</td>
        <td style="white-space:nowrap">
          ${f.status === "open" ? `<button class="btn btn-icon" data-action="finding-resolve" data-id="${f.id}" title="resolve">✓</button>` : ""}
          <button class="btn btn-icon" data-action="finding-del" data-id="${f.id}">✕</button>
        </td></tr>`;
      }).join("")}
    </table></div>` : `<div class="empty">No findings recorded.</div>`}
  </div>`;
};

/* ---------- Accounting ---------- */
views.accounting = () => {
  const fin = financials();
  const bal = accountBalances();
  const equityTotal = fin.totalEquity + fin.netIncome;
  const section = (title, rows, totalLabel) => `
    <div class="report-section"><h4>${title}</h4>
      ${rows.map(r => `<div class="report-line"><span>${esc(r.acc.name)}</span><span class="amt">${money(r.amt)}</span></div>`).join("") || `<div class="muted" style="font-size:12px">—</div>`}
      <div class="report-line total"><span>${totalLabel}</span><span class="amt">${money(rows.reduce((s, r) => s + r.amt, 0))}</span></div>
    </div>`;
  return `
  <div class="view-head">
    <div><h1>Accounting</h1>
      <div class="sub">Double-entry ledger with live P&amp;L, balance sheet and trial balance.</div></div>
    <div class="head-actions">
      <button class="btn" data-action="account-new">+ Account</button>
      <button class="btn btn-primary" data-action="journal-new">+ Journal Entry</button>
    </div>
  </div>
  <div class="grid grid-3">
    <div class="card">
      <h3>Income Statement</h3>
      ${section("Income", fin.income, "Total income")}
      ${section("Expenses", fin.expense, "Total expenses")}
      <div class="report-line total"><span>NET INCOME</span>
        <span class="amt ${fin.netIncome >= 0 ? "pos" : "neg"}">${money(fin.netIncome)}</span></div>
    </div>
    <div class="card">
      <h3>Balance Sheet</h3>
      ${section("Assets", fin.assets, "Total assets")}
      ${section("Liabilities", fin.liabs, "Total liabilities")}
      <div class="report-section"><h4>Equity</h4>
        ${fin.equity.map(r => `<div class="report-line"><span>${esc(r.acc.name)}</span><span class="amt">${money(r.amt)}</span></div>`).join("")}
        <div class="report-line"><span>Retained earnings (period)</span><span class="amt">${money(fin.netIncome)}</span></div>
        <div class="report-line total"><span>Liabilities + Equity</span><span class="amt">${money(fin.totalLiabs + equityTotal)}</span></div>
      </div>
      <div class="muted" style="font-size:11.5px">${Math.abs(fin.totalAssets - (fin.totalLiabs + equityTotal)) < 0.005
        ? "✓ Books are balanced." : "⚠ Books do not balance — check entries."}</div>
    </div>
    <div class="card">
      <h3>Trial Balance</h3>
      <div class="tbl-wrap"><table>
        <tr><th>Account</th><th class="num">Debit</th><th class="num">Credit</th></tr>
        ${DB.accounts.map(a => {
          const raw = bal[a.id] || 0;
          return `<tr><td>${esc(a.name)} <span class="muted">(${a.type})</span></td>
            <td class="num">${raw > 0 ? num(raw) : ""}</td>
            <td class="num">${raw < 0 ? num(-raw) : ""}</td></tr>`;
        }).join("")}
      </table></div>
    </div>
  </div>
  <div class="card mt">
    <h3>Journal (${DB.journal.length} entries)</h3>
    ${DB.journal.length ? `<div class="tbl-wrap"><table>
      <tr><th>Date</th><th>Memo</th><th>Debit</th><th>Credit</th><th class="num">Amount</th><th></th></tr>
      ${DB.journal.slice().reverse().map(j => {
        const acc = id => (DB.accounts.find(a => a.id === id) || {}).name || "?";
        return `<tr><td>${j.date}</td><td>${esc(j.memo)}</td>
          <td>${esc(acc(j.debit))}</td><td>${esc(acc(j.credit))}</td>
          <td class="num">${money(j.amount)}</td>
          <td><button class="btn btn-icon" data-action="journal-del" data-id="${j.id}">✕</button></td></tr>`;
      }).join("")}
    </table></div>` : `<div class="empty">No entries. Record your first transaction — e.g. debit Cash, credit Consulting Fees.</div>`}
  </div>`;
};

/* ---------- Microfinance ---------- */
views.microfinance = () => {
  const pf = portfolioStats();
  return `
  <div class="view-head">
    <div><h1>Microfinance</h1>
      <div class="sub">Loan book, amortization schedules and portfolio-at-risk monitoring.</div></div>
    <div class="head-actions"><button class="btn btn-primary" data-action="loan-new">+ Loan</button></div>
  </div>
  <div class="grid grid-4">
    <div class="stat"><div class="label">Active Loans</div><div class="value">${pf.count}</div></div>
    <div class="stat accent"><div class="label">Outstanding</div><div class="value">${money(pf.outstanding)}</div></div>
    <div class="stat ${pf.parPct > 5 ? "bad" : "good"}"><div class="label">PAR &gt; 30</div><div class="value">${num(pf.parPct)}%</div>
      <div class="hint">${money(pf.par30)} at risk</div></div>
    <div class="stat"><div class="label">Closed Loans</div><div class="value">${DB.loans.filter(l => l.status === "closed").length}</div></div>
  </div>
  <div class="card mt">
    <h3>Loan Book</h3>
    ${DB.loans.length ? `<div class="tbl-wrap"><table>
      <tr><th>Borrower</th><th class="num">Principal</th><th class="num">Rate</th><th class="num">Months</th>
      <th>Method</th><th class="num">Repaid</th><th class="num">Outstanding</th><th>Overdue</th><th>Status</th><th></th></tr>
      ${DB.loans.map(l => {
        const od = Number(l.daysOverdue) || 0;
        return `<tr>
        <td><strong>${esc(l.borrower)}</strong></td>
        <td class="num">${money(l.principal)}</td><td class="num">${num(l.rate)}%</td><td class="num">${l.months}</td>
        <td>${l.method}</td><td class="num">${money(l.repaid || 0)}</td>
        <td class="num">${money(loanOutstanding(l))}</td>
        <td>${od > 30 ? `<span class="badge b-red">${od}d</span>` : od > 0 ? `<span class="badge b-amber">${od}d</span>` : `<span class="badge b-green">current</span>`}</td>
        <td>${l.status === "active" ? `<span class="badge b-gold">active</span>` : `<span class="badge b-grey">closed</span>`}</td>
        <td style="white-space:nowrap">
          <button class="btn btn-icon" data-action="loan-sched" data-id="${l.id}" title="schedule">▤</button>
          ${l.status === "active" ? `<button class="btn btn-icon" data-action="loan-pay" data-id="${l.id}" title="record repayment">＋</button>` : ""}
          <button class="btn btn-icon" data-action="loan-del" data-id="${l.id}">✕</button>
        </td></tr>`;
      }).join("")}
    </table></div>` : `<div class="empty">No loans yet. Add one to generate its amortization schedule automatically.</div>`}
  </div>`;
};

/* ---------- Tax & Compliance ---------- */
views.tax = () => `
  <div class="view-head">
    <div><h1>Tax &amp; Compliance</h1>
      <div class="sub">Filing calendar and statutory obligations — never miss a deadline.</div></div>
    <div class="head-actions"><button class="btn btn-primary" data-action="obl-new">+ Obligation</button></div>
  </div>
  <div class="card">
    <h3>Obligations</h3>
    ${DB.obligations.length ? `<div class="tbl-wrap"><table>
      <tr><th>Obligation</th><th>Authority</th><th>Client</th><th>Due</th><th>Frequency</th><th>Status</th><th></th></tr>
      ${DB.obligations.slice().sort((a, b) => a.dueDate.localeCompare(b.dueDate)).map(o => {
        const d = daysUntil(o.dueDate);
        return `<tr>
        <td><strong>${esc(o.name)}</strong></td><td>${esc(o.authority || "—")}</td>
        <td>${esc(clientName(o.clientId))}</td>
        <td>${o.dueDate} ${o.status === "pending" ? (d < 0 ? `<span class="badge b-red">${-d}d overdue</span>` : d <= 14 ? `<span class="badge b-amber">${d}d</span>` : "") : ""}</td>
        <td>${esc(o.frequency)}</td>
        <td>${o.status === "pending" ? `<span class="badge b-amber">pending</span>` : `<span class="badge b-green">filed</span>`}</td>
        <td style="white-space:nowrap">
          ${o.status === "pending" ? `<button class="btn btn-icon" data-action="obl-file" data-id="${o.id}" title="mark filed">✓</button>` : ""}
          <button class="btn btn-icon" data-action="obl-del" data-id="${o.id}">✕</button>
        </td></tr>`;
      }).join("")}
    </table></div>` : `<div class="empty">No obligations tracked. Add VAT returns, payroll taxes, license renewals, AGM filings…</div>`}
  </div>`;

/* ---------- HR & Payroll ---------- */
views.hr = () => {
  const totalGross = DB.employees.reduce((s, e) => s + Number(e.gross || 0), 0);
  const totalNet = DB.employees.reduce((s, e) => s + Number(e.gross || 0) * (1 - Number(e.deductPct || 0) / 100), 0);
  return `
  <div class="view-head">
    <div><h1>HR &amp; Payroll</h1>
      <div class="sub">Headcount and monthly payroll with statutory deduction estimates.</div></div>
    <div class="head-actions"><button class="btn btn-primary" data-action="emp-new">+ Employee</button></div>
  </div>
  <div class="grid grid-4">
    <div class="stat"><div class="label">Headcount</div><div class="value">${DB.employees.length}</div></div>
    <div class="stat accent"><div class="label">Gross Payroll / mo</div><div class="value">${money(totalGross)}</div></div>
    <div class="stat"><div class="label">Net Payroll / mo</div><div class="value">${money(totalNet)}</div></div>
    <div class="stat"><div class="label">Deductions / mo</div><div class="value">${money(totalGross - totalNet)}</div></div>
  </div>
  <div class="card mt">
    <h3>Employees</h3>
    ${DB.employees.length ? `<div class="tbl-wrap"><table>
      <tr><th>Name</th><th>Role</th><th class="num">Gross / mo</th><th class="num">Deductions</th><th class="num">Net Pay</th><th></th></tr>
      ${DB.employees.map(e => {
        const ded = Number(e.gross) * Number(e.deductPct || 0) / 100;
        return `<tr><td><strong>${esc(e.name)}</strong></td><td>${esc(e.role || "—")}</td>
        <td class="num">${money(e.gross)}</td>
        <td class="num">${money(ded)} <span class="muted">(${num(e.deductPct || 0)}%)</span></td>
        <td class="num">${money(Number(e.gross) - ded)}</td>
        <td><button class="btn btn-icon" data-action="emp-del" data-id="${e.id}">✕</button></td></tr>`;
      }).join("")}
    </table></div>` : `<div class="empty">No employees on payroll.</div>`}
  </div>`;
};

/* ---------- Risk Register ---------- */
views.risk = () => {
  const scoreBadge = s => s >= 15 ? "b-red" : s >= 8 ? "b-amber" : "b-green";
  return `
  <div class="view-head">
    <div><h1>Risk Register</h1>
      <div class="sub">Likelihood × impact scoring (1–5 each). Score ≥ 15 is severe, ≥ 8 elevated.</div></div>
    <div class="head-actions"><button class="btn btn-primary" data-action="risk-new">+ Risk</button></div>
  </div>
  <div class="card">
    ${DB.risks.length ? `<div class="tbl-wrap"><table>
      <tr><th>Risk</th><th>Category</th><th class="num">L</th><th class="num">I</th><th class="num">Score</th><th>Mitigation</th><th>Owner</th><th>Status</th><th></th></tr>
      ${DB.risks.slice().sort((a, b) => (b.likelihood * b.impact) - (a.likelihood * a.impact)).map(r => {
        const s = r.likelihood * r.impact;
        return `<tr>
        <td><strong>${esc(r.title)}</strong></td><td>${esc(r.category)}</td>
        <td class="num">${r.likelihood}</td><td class="num">${r.impact}</td>
        <td class="num"><span class="badge ${scoreBadge(s)} risk-score">${s}</span></td>
        <td>${esc(r.mitigation || "—")}</td><td>${esc(r.owner || "—")}</td>
        <td>${r.status === "open" ? `<span class="badge b-amber">open</span>` : `<span class="badge b-green">mitigated</span>`}</td>
        <td style="white-space:nowrap">
          ${r.status === "open" ? `<button class="btn btn-icon" data-action="risk-close" data-id="${r.id}" title="mark mitigated">✓</button>` : ""}
          <button class="btn btn-icon" data-action="risk-del" data-id="${r.id}">✕</button>
        </td></tr>`;
      }).join("")}
    </table></div>` : `<div class="empty">No risks logged. Think market, credit, operational, compliance, key-person, FX…</div>`}
  </div>`;
};

/* ---------- Financial Analysis toolkit ---------- */
views.analysis = () => `
  <div class="view-head">
    <div><h1>Financial Analysis Toolkit</h1>
      <div class="sub">Ratio analysis, break-even and NPV — instant answers in client meetings.</div></div>
  </div>
  <div class="grid grid-3">
    <div class="card">
      <h3>Ratio Analysis</h3>
      <form id="f-ratios">
        <div class="form-row">
          <div><label>Current assets</label><input name="ca" type="number" step="any" value="0"></div>
          <div><label>Current liabilities</label><input name="cl" type="number" step="any" value="0"></div>
          <div><label>Inventory</label><input name="inv" type="number" step="any" value="0"></div>
          <div><label>Total debt</label><input name="debt" type="number" step="any" value="0"></div>
          <div><label>Total equity</label><input name="eq" type="number" step="any" value="0"></div>
          <div><label>Total assets</label><input name="ta" type="number" step="any" value="0"></div>
          <div><label>Revenue</label><input name="rev" type="number" step="any" value="0"></div>
          <div><label>Net income</label><input name="ni" type="number" step="any" value="0"></div>
        </div>
        <button class="btn btn-primary mt" type="submit">Compute</button>
      </form>
      <div id="out-ratios" class="mt"></div>
    </div>
    <div class="card">
      <h3>Break-even</h3>
      <form id="f-be">
        <label>Fixed costs / period</label><input name="fc" type="number" step="any" value="0">
        <label>Price per unit</label><input name="p" type="number" step="any" value="0">
        <label>Variable cost per unit</label><input name="vc" type="number" step="any" value="0">
        <button class="btn btn-primary mt" type="submit">Compute</button>
      </form>
      <div id="out-be" class="mt"></div>
    </div>
    <div class="card">
      <h3>NPV &amp; Payback</h3>
      <form id="f-npv">
        <label>Discount rate % / period</label><input name="rate" type="number" step="any" value="10">
        <label>Initial investment (positive number)</label><input name="inv" type="number" step="any" value="0">
        <label>Cash flows (comma separated, per period)</label>
        <input name="cf" placeholder="e.g. 500, 700, 900, 900">
        <button class="btn btn-primary mt" type="submit">Compute</button>
      </form>
      <div id="out-npv" class="mt"></div>
    </div>
  </div>`;

/* ============================================================
   FORMS (modal builders)
   ============================================================ */
function formModal(title, bodyHtml, onSubmit, submitLabel) {
  openModal(`
    <h2>${title}</h2>
    <form id="modal-form">${bodyHtml}
      <div class="modal-actions">
        <button type="button" class="btn" data-action="modal-close">Cancel</button>
        <button type="submit" class="btn btn-primary">${submitLabel || "Save"}</button>
      </div>
    </form>`, m => {
    $("#modal-form", m).addEventListener("submit", e => {
      e.preventDefault();
      const fd = new FormData(e.target);
      const data = {};
      fd.forEach((v, k) => data[k] = typeof v === "string" ? v.trim() : v);
      if (onSubmit(data) !== false) { closeModal(); saveDB(); render(); }
    });
  });
}

const forms = {
  "client-new": () => formModal("New Client", `
    <label>Client name *</label><input name="name" required>
    <div class="form-row">
      <div><label>Industry</label><input name="industry"></div>
      <div><label>Contact</label><input name="contact" placeholder="phone / email"></div>
    </div>
    <label>Notes</label><textarea name="notes"></textarea>`,
    d => { DB.clients.push({ id: uid("cl"), swot: { s: [], w: [], o: [], t: [] }, ...d }); toast("Client added."); }),

  "client-swot": id => {
    const c = DB.clients.find(x => x.id === id);
    if (!c.swot) c.swot = { s: [], w: [], o: [], t: [] };
    formModal("SWOT — " + esc(c.name), `
      <div class="muted" style="font-size:12px;margin-bottom:4px">One item per line.</div>
      <div class="form-row">
        <div><label>Strengths</label><textarea name="s">${esc(c.swot.s.join("\n"))}</textarea></div>
        <div><label>Weaknesses</label><textarea name="w">${esc(c.swot.w.join("\n"))}</textarea></div>
        <div><label>Opportunities</label><textarea name="o">${esc(c.swot.o.join("\n"))}</textarea></div>
        <div><label>Threats</label><textarea name="t">${esc(c.swot.t.join("\n"))}</textarea></div>
      </div>`,
      d => {
        ["s", "w", "o", "t"].forEach(k => c.swot[k] = d[k].split("\n").map(x => x.trim()).filter(Boolean));
        toast("SWOT updated.");
      });
  },

  "eng-new": () => {
    if (!DB.clients.length) return toast("Add a client first.");
    formModal("New Engagement", `
      <label>Client *</label><select name="clientId" required>${DB.clients.map(c => `<option value="${c.id}">${esc(c.name)}</option>`).join("")}</select>
      <div class="form-row">
        <div><label>Service</label><select name="service">
          ${["Consulting", "Audit", "Accounting", "Microfinance", "Tax", "HR", "Other"].map(s => `<option>${s}</option>`).join("")}
        </select></div>
        <div><label>Fee</label><input name="fee" type="number" step="any" value="0"></div>
      </div>
      <label>Status</label><select name="status">
        <option value="proposal">Proposal</option><option value="active" selected>Active</option>
      </select>`,
      d => { DB.engagements.push({ id: uid("en"), start: today(), ...d }); toast("Engagement added."); });
  },

  "audit-new": () => {
    if (!DB.clients.length) return toast("Add a client first.");
    formModal("New Audit", `
      <label>Client *</label><select name="clientId" required>${DB.clients.map(c => `<option value="${c.id}">${esc(c.name)}</option>`).join("")}</select>
      <div class="form-row">
        <div><label>Scope</label><input name="scope" placeholder="Financial statements, internal controls…" required></div>
        <div><label>Period</label><input name="period" placeholder="FY2025" required></div>
      </div>`,
      d => { DB.audits.push({ id: uid("au"), status: "planning", ...d }); toast("Audit created."); });
  },

  "finding-new": () => {
    if (!DB.audits.length) return toast("Create an audit first.");
    formModal("New Finding", `
      <label>Audit *</label><select name="auditId" required>
        ${DB.audits.map(a => `<option value="${a.id}">${esc(clientName(a.clientId))} · ${esc(a.period)}</option>`).join("")}
      </select>
      <label>Finding title *</label><input name="title" required>
      <label>Severity</label><select name="severity">
        <option>low</option><option selected>medium</option><option>high</option><option>critical</option>
      </select>
      <label>Recommendation</label><textarea name="recommendation"></textarea>`,
      d => { DB.findings.push({ id: uid("fi"), status: "open", ...d }); toast("Finding logged."); });
  },

  "account-new": () => formModal("New Account", `
    <label>Account name *</label><input name="name" required>
    <label>Type</label><select name="type">
      ${["Asset", "Liability", "Equity", "Income", "Expense"].map(t => `<option>${t}</option>`).join("")}
    </select>`,
    d => { DB.accounts.push({ id: uid("ac"), ...d }); toast("Account added."); }),

  "journal-new": () => {
    const opts = DB.accounts.map(a => `<option value="${a.id}">${esc(a.name)} (${a.type})</option>`).join("");
    formModal("New Journal Entry", `
      <div class="form-row">
        <div><label>Date</label><input name="date" type="date" value="${today()}" required></div>
        <div><label>Amount *</label><input name="amount" type="number" step="any" min="0.01" required></div>
      </div>
      <label>Debit account</label><select name="debit">${opts}</select>
      <label>Credit account</label><select name="credit">${opts}</select>
      <label>Memo</label><input name="memo" placeholder="Invoice #12 — consulting retainer">`,
      d => {
        if (d.debit === d.credit) { toast("Debit and credit accounts must differ."); return false; }
        DB.journal.push({ id: uid("je"), ...d, amount: Number(d.amount) });
        toast("Entry posted.");
      });
  },

  "loan-new": () => formModal("New Loan", `
    <label>Borrower *</label><input name="borrower" required>
    <div class="form-row-3">
      <div><label>Principal *</label><input name="principal" type="number" step="any" min="1" required></div>
      <div><label>Annual rate %</label><input name="rate" type="number" step="any" value="24"></div>
      <div><label>Term (months)</label><input name="months" type="number" min="1" value="12"></div>
    </div>
    <div class="form-row">
      <div><label>Interest method</label><select name="method">
        <option value="declining">Declining balance</option><option value="flat">Flat rate</option>
      </select></div>
      <div><label>Days overdue</label><input name="daysOverdue" type="number" min="0" value="0"></div>
    </div>`,
    d => { DB.loans.push({ id: uid("ln"), status: "active", repaid: 0, start: today(), ...d }); toast("Loan booked."); }),

  "loan-pay": id => {
    const l = DB.loans.find(x => x.id === id);
    formModal("Record Repayment — " + esc(l.borrower), `
      <div class="muted" style="font-size:12.5px">Outstanding: <strong>${money(loanOutstanding(l))}</strong></div>
      <label>Amount received *</label><input name="amt" type="number" step="any" min="0.01" required>
      <label>Days overdue after payment</label><input name="od" type="number" min="0" value="${l.daysOverdue || 0}">`,
      d => {
        l.repaid = (Number(l.repaid) || 0) + Number(d.amt);
        l.daysOverdue = Number(d.od) || 0;
        if (loanOutstanding(l) <= 0.005) { l.status = "closed"; l.daysOverdue = 0; toast("Loan fully repaid — closed."); }
        else toast("Repayment recorded.");
      }, "Record");
  },

  "loan-sched": id => {
    const l = DB.loans.find(x => x.id === id);
    const s = loanSchedule(l);
    openModal(`
      <h2>Amortization — ${esc(l.borrower)}</h2>
      <div class="muted" style="font-size:12.5px;margin-bottom:10px">
        ${l.method} · payment ≈ <strong>${money(s.payment)}</strong>/mo ·
        total interest <strong>${money(s.totalInterest)}</strong> ·
        total due <strong>${money(s.totalDue)}</strong></div>
      <div class="tbl-wrap" style="max-height:340px;overflow-y:auto"><table>
        <tr><th>#</th><th class="num">Payment</th><th class="num">Principal</th><th class="num">Interest</th><th class="num">Balance</th></tr>
        ${s.rows.map(r => `<tr><td>${r.m}</td><td class="num">${num(r.payment)}</td>
          <td class="num">${num(r.principal)}</td><td class="num">${num(r.interest)}</td>
          <td class="num">${num(r.balance)}</td></tr>`).join("")}
      </table></div>
      <div class="modal-actions"><button class="btn" data-action="modal-close">Close</button></div>`);
  },

  "obl-new": () => formModal("New Obligation", `
    <label>Obligation *</label><input name="name" placeholder="VAT return, PAYE, license renewal…" required>
    <div class="form-row">
      <div><label>Authority</label><input name="authority" placeholder="Revenue authority…"></div>
      <div><label>Client</label><select name="clientId">${clientOptions()}</select></div>
    </div>
    <div class="form-row">
      <div><label>Due date *</label><input name="dueDate" type="date" required></div>
      <div><label>Frequency</label><select name="frequency">
        <option>one-off</option><option>monthly</option><option>quarterly</option><option>annual</option>
      </select></div>
    </div>`,
    d => { DB.obligations.push({ id: uid("ob"), status: "pending", ...d }); toast("Obligation tracked."); }),

  "emp-new": () => formModal("New Employee", `
    <label>Name *</label><input name="name" required>
    <label>Role</label><input name="role">
    <div class="form-row">
      <div><label>Gross salary / month *</label><input name="gross" type="number" step="any" min="0" required></div>
      <div><label>Deductions % (tax + social)</label><input name="deductPct" type="number" step="any" min="0" max="100" value="15"></div>
    </div>`,
    d => { DB.employees.push({ id: uid("em"), ...d }); toast("Employee added."); }),

  "risk-new": () => formModal("New Risk", `
    <label>Risk title *</label><input name="title" required>
    <div class="form-row">
      <div><label>Category</label><select name="category">
        ${["Strategic", "Financial", "Credit", "Operational", "Compliance", "Market", "Reputational", "Other"].map(c => `<option>${c}</option>`).join("")}
      </select></div>
      <div><label>Owner</label><input name="owner"></div>
    </div>
    <div class="form-row">
      <div><label>Likelihood (1–5)</label><input name="likelihood" type="number" min="1" max="5" value="3" required></div>
      <div><label>Impact (1–5)</label><input name="impact" type="number" min="1" max="5" value="3" required></div>
    </div>
    <label>Mitigation plan</label><textarea name="mitigation"></textarea>`,
    d => {
      DB.risks.push({ id: uid("rk"), status: "open", ...d, likelihood: Number(d.likelihood), impact: Number(d.impact) });
      toast("Risk logged.");
    }),

  "ooda-new": () => formModal("New OODA Loop", `
    <label>Decision / mission title *</label><input name="title" placeholder="e.g. Should client X expand to region Y?" required>
    <label>Objective</label><textarea name="objective" placeholder="What outcome defines success?"></textarea>`,
    d => {
      DB.ooda.push({ id: uid("oo"), status: "active", stage: 0, cycles: 0,
        notes: { observe: "", orient: "", decide: "", act: "" }, log: [], ...d });
      toast("Loop started — begin with Observe.");
    }),

  "ooda-note": id => {
    const o = DB.ooda.find(x => x.id === id);
    const stage = OODA_STAGES[o.stage];
    const key = stage.toLowerCase();
    formModal(stage + " — " + esc(o.title), `
      <label>${stage} notes</label>
      <textarea name="note" rows="5" placeholder="${{
        observe: "Facts, data, market signals, client numbers…",
        orient: "What does it mean? Context, models, biases challenged…",
        decide: "The chosen course of action and why…",
        act: "What was executed, and the measured result…"
      }[key]}">${esc(o.notes[key])}</textarea>`,
      d => { o.notes[key] = d.note; oodaAdvance(o); }, "Save & Advance");
  }
};

/* ============================================================
   ANALYSIS calculators (inline, non-persistent)
   ============================================================ */
function bindAnalysis() {
  const g = (fd, k) => Number(fd.get(k)) || 0;
  const line = (l, v, note) => `<div class="report-line"><span>${l}${note ? ` <span class="muted">(${note})</span>` : ""}</span><span class="amt">${v}</span></div>`;

  const fr = $("#f-ratios");
  if (fr) fr.addEventListener("submit", e => {
    e.preventDefault();
    const fd = new FormData(fr);
    const ca = g(fd, "ca"), cl = g(fd, "cl"), inv = g(fd, "inv"), debt = g(fd, "debt"),
      eq = g(fd, "eq"), ta = g(fd, "ta"), rev = g(fd, "rev"), ni = g(fd, "ni");
    const r = (a, b) => b ? num(a / b) : "—";
    const pct = (a, b) => b ? num(a / b * 100) + "%" : "—";
    $("#out-ratios").innerHTML =
      line("Current ratio", r(ca, cl), "≥ 1.5 healthy") +
      line("Quick ratio", r(ca - inv, cl), "≥ 1.0 healthy") +
      line("Debt-to-equity", r(debt, eq), "< 2.0 typical") +
      line("Net margin", pct(ni, rev)) +
      line("Return on assets", pct(ni, ta)) +
      line("Return on equity", pct(ni, eq));
  });

  const fb = $("#f-be");
  if (fb) fb.addEventListener("submit", e => {
    e.preventDefault();
    const fd = new FormData(fb);
    const fc = g(fd, "fc"), p = g(fd, "p"), vc = g(fd, "vc");
    const cm = p - vc;
    $("#out-be").innerHTML = cm > 0
      ? line("Contribution margin / unit", money(cm)) +
        line("Break-even units", num(Math.ceil(fc / cm))) +
        line("Break-even revenue", money(Math.ceil(fc / cm) * p)) +
        line("CM ratio", num(cm / p * 100) + "%")
      : `<div class="muted">Price must exceed variable cost per unit.</div>`;
  });

  const fn = $("#f-npv");
  if (fn) fn.addEventListener("submit", e => {
    e.preventDefault();
    const fd = new FormData(fn);
    const rate = g(fd, "rate") / 100, inv = g(fd, "inv");
    const cfs = String(fd.get("cf") || "").split(",").map(s => s.trim()).filter(Boolean)
      .map(Number).filter(x => !isNaN(x));
    let npv = -inv, cum = -inv, payback = null;
    cfs.forEach((cf, i) => {
      npv += cf / Math.pow(1 + rate, i + 1);
      const prev = cum;
      cum += cf;
      if (payback === null && cum >= 0 && cf > 0) payback = i + (prev < 0 ? (-prev / cf) : 0);
    });
    $("#out-npv").innerHTML =
      line("NPV", money(npv)) +
      line("Verdict", npv > 0 ? `<span class="pos">Accept — value creating</span>` : `<span class="neg">Reject — value destroying</span>`) +
      line("Simple payback", payback !== null ? num(payback) + " periods" : "not recovered");
  });
}

/* ============================================================
   ROUTER / EVENTS
   ============================================================ */
let currentView = "dashboard";

function render() {
  $("#main").innerHTML = views[currentView]();
  $$("#nav a").forEach(a => a.classList.toggle("active", a.dataset.view === currentView));
  if (currentView === "analysis") bindAnalysis();
  window.scrollTo(0, 0);
}

function nav(v) { currentView = v; render(); }

document.addEventListener("click", e => {
  const el = e.target.closest("[data-action], #nav a");
  if (!el) return;

  if (el.matches("#nav a")) { nav(el.dataset.view); return; }

  const act = el.dataset.action, id = el.dataset.id;
  const del = (arr, msg) => {
    const i = arr.findIndex(x => x.id === id);
    if (i > -1 && confirm("Delete this item?")) { arr.splice(i, 1); saveDB(); render(); toast(msg); }
  };

  switch (act) {
    case "nav": nav(el.dataset.view); break;
    case "modal-close": closeModal(); break;
    case "export-data": exportDB(); toast("Backup downloaded."); break;
    case "import-data": $("#import-file").click(); break;

    case "client-new": case "client-swot": case "eng-new": case "audit-new":
    case "finding-new": case "account-new": case "journal-new": case "loan-new":
    case "loan-pay": case "loan-sched": case "obl-new": case "emp-new":
    case "risk-new": case "ooda-new": case "ooda-note":
      forms[act](id); break;

    case "client-del": {
      const hasDeps = DB.engagements.some(x => x.clientId === id) || DB.audits.some(x => x.clientId === id);
      if (hasDeps && !confirm("This client has engagements/audits attached. Delete anyway?")) break;
      const i = DB.clients.findIndex(x => x.id === id);
      if (i > -1) { DB.clients.splice(i, 1); saveDB(); render(); toast("Client removed."); }
      break;
    }
    case "eng-del": del(DB.engagements, "Engagement removed."); break;
    case "eng-next": {
      const g = DB.engagements.find(x => x.id === id);
      g.status = g.status === "proposal" ? "active" : "completed";
      saveDB(); render(); break;
    }
    case "audit-del": del(DB.audits, "Audit removed."); break;
    case "audit-next": {
      const a = DB.audits.find(x => x.id === id);
      a.status = AUDIT_STAGES[Math.min(AUDIT_STAGES.indexOf(a.status) + 1, 3)];
      saveDB(); render(); break;
    }
    case "finding-del": del(DB.findings, "Finding removed."); break;
    case "finding-resolve": {
      const f = DB.findings.find(x => x.id === id);
      f.status = "resolved"; saveDB(); render(); toast("Finding resolved."); break;
    }
    case "journal-del": del(DB.journal, "Entry removed."); break;
    case "loan-del": del(DB.loans, "Loan removed."); break;
    case "obl-del": del(DB.obligations, "Obligation removed."); break;
    case "obl-file": {
      const o = DB.obligations.find(x => x.id === id);
      o.status = "filed"; saveDB(); render(); toast("Marked as filed."); break;
    }
    case "emp-del": del(DB.employees, "Employee removed."); break;
    case "risk-del": del(DB.risks, "Risk removed."); break;
    case "risk-close": {
      const r = DB.risks.find(x => x.id === id);
      r.status = "mitigated"; saveDB(); render(); toast("Risk mitigated."); break;
    }
    case "ooda-del": del(DB.ooda, "Loop removed."); break;
    case "ooda-skip": oodaAdvance(DB.ooda.find(x => x.id === id)); break;
    case "ooda-done": {
      const o = DB.ooda.find(x => x.id === id);
      o.status = "done"; saveDB(); render(); toast("Loop completed."); break;
    }
  }
});

$("#import-file").addEventListener("change", e => {
  const f = e.target.files[0];
  if (f) importDB(f, ok => {
    toast(ok ? "Data imported." : "Import failed — invalid file.");
    if (ok) render();
  });
  e.target.value = "";
});

render();
