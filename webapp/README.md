# GOD MODE — Business Consultant OS

A self-contained web app for a full-service business consultant. No build step,
no server, no dependencies — open `index.html` in any browser (or serve the
folder with any static server) and everything runs locally. All data is stored
in your browser's localStorage, with JSON export/import for backup and moving
between machines.

## Run it

```bash
# option 1: just open the file
open webapp/index.html

# option 2: any static server
cd webapp && python3 -m http.server 8080
# then visit http://localhost:8080
```

## Modules

| Module | What it does |
|---|---|
| **Command Dashboard** | God-mode view: net income, loan portfolio, PAR%, open findings, risks, compliance deadlines and active OODA loops in one screen. |
| **OODA Engine** | Run any decision through Observe → Orient → Decide → Act. Notes per stage, full cycles archived, loops repeat until you close them. |
| **Consulting / CRM** | Clients, engagements with fee pipeline (proposal → active → completed), and a SWOT board per client. |
| **Auditing** | Audit engagements through planning → fieldwork → reporting → closed, plus a findings register with severity and remediation status. |
| **Accounting** | Double-entry journal with a chart of accounts. Live income statement, balance sheet (with balance check) and trial balance. |
| **Microfinance** | Loan book with flat or declining-balance amortization schedules, repayment tracking, auto-close on payoff, and PAR>30 monitoring. |
| **Tax & Compliance** | Filing calendar with authorities, frequencies, overdue/due-soon flags feeding the dashboard. |
| **HR & Payroll** | Headcount with gross → net payroll and deduction estimates. |
| **Risk Register** | Likelihood × impact scoring (1–25), sorted by severity, with mitigation owner and status. |
| **Financial Analysis** | Instant calculators: liquidity/leverage/profitability ratios, break-even, and NPV with simple payback. |

## Data

- Everything persists in `localStorage` under one key.
- **Export Data** downloads a JSON backup; **Import Data** restores it.
- The chart of accounts ships pre-seeded with common consultant accounts and
  can be extended from the Accounting view.
