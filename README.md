# MetaEditor5-
Creating a meta editor code for a risk taking bot that is able to executes trades even from low account balance

## Medula EA

- **[MEDULA_FORMULAS.md](MEDULA_FORMULAS.md)** — formula specification for all 21 engines.
- **[MQL5/Experts/Medula/](MQL5/Experts/Medula/)** — modular MQL5 implementation (`Medula.mq5` + `.mqh` engine files) with install and testing instructions.
- **[MQL5/Experts/Medula_Single.mq5](MQL5/Experts/Medula_Single.mq5)** — **v2.70, the maintained build.** Single file, zero dependencies (no includes at all): copy into `MQL5/Experts/` and compile.
- **[tests/verify_medula.py](tests/verify_medula.py)** — 170-check regression suite covering every engine formula, including an anti-stationary guarantee. Run with `python3 tests/verify_medula.py`.

### Why v2 exists

v1 compiled cleanly but **never opened a trade**. Its confidence score was compared to a
fixed threshold of 60, but because the engine weights sum to 1 and each score is capped at
±1, the attainable confidence on real market data peaked near 55 after the volatility and
spread penalties — the bar was mathematically unreachable. A linear spread penalty made it
worse, halving every score at a routine 15-point spread.

v2 replaces the fixed bar with a **self-calibrating** one: current conviction is ranked
against its own rolling distribution, and the EA acts when conviction sits in the top
percentile band of what the symbol actually produces. A top decile always exists on any
symbol, timeframe or volatility regime, so the arithmetic tunes itself. An absolute floor
still prevents trading noise in dead markets, and every rejected entry now logs its reason
to the journal and an on-chart panel.

### v2.50 — new engines and the anti-stationary guarantee

| Engine | What it adds |
|---|---|
| §22 Order Flow | Tick-volume weighted close-location pressure — where participation actually occurred |
| §23 Volatility Forecast | RiskMetrics EWMA one-step forecast; sizes down *before* an expansion hits the stop |
| §24 Trade Quality Score | Pre-trade scorecard: edge after spread cost, regime fit, HTF backing, session, flow |
| §25 Equity Curve | Trades the EA's own equity curve — smaller size while it sits below its average |
| §26 Participation Watchdog | Releases selectivity step by step when idle too long, never the safety floor |

Three structural changes make idling impossible rather than unlikely:

1. **History seeding** — the conviction distribution is built from past bars at startup, so
   percentile mode is live on the first tick instead of after 60 bars of waiting.
2. **Participation watchdog** — after `InpIdleBarsRelax` idle bars, the entry percentile is
   released one step at a time down to a hard floor. It relaxes *how picky* the EA is; the
   absolute conviction floor, risk caps, spread limit and circuit breaker are never touched.
3. **Startup self-test** — on attach, the EA prints bars available, broker constraints, the
   seeded distribution's shape, and whether an entry is reachable at all. A configuration
   that could never trade is visible in seconds instead of after days of silence.

Profit protection was also added: partial take-profit at +1R and an automatic break-even
move, so a winner cannot round-trip into a loser.

### v2.60 — the XAUUSD postmortem

A six-year XAUUSD.m M5 backtest logged `conviction 0.0` on every bar and took zero trades.
Two independent causes:

1. **Spread was multiplied into conviction.** The spread factor reaches *exactly* zero once
   spread hits the limit, so conviction became exactly zero — and `InpMaxSpreadPoints=40`,
   calibrated for 5-digit EURUSD, is unreachable on 3-digit gold where a normal $0.30 spread
   is 300 points. **Fix:** conviction now measures the market only. Spread and execution
   quality are trading *costs* — they gate entries and feed the Trade Quality Score (§24),
   and can no longer annihilate the analysis signal.
2. **The spread limit could not travel between instruments.** **Fix:** the limit is now
   `max(InpMaxSpreadAtr × ATR, InpMaxSpreadPoints)`, self-calibrating to each symbol's own
   bar range. It is deliberately permissive — a backstop against news spikes and rollover,
   not a cost filter, because §24 already prices the economics properly.

A third blocker was **not** fixable in code: a **$10 account cannot hold 0.01 lots of gold**
(1 oz ≈ $2,000 notional → $20 margin at 1:100, $30 with the safety factor). The startup
self-test now computes this explicitly and prints a blocking warning when the account cannot
afford one minimum lot, instead of letting every order fail silently.


### v2.70 — the R-accounting postmortem

The first run that actually traded (XAUUSD.m M5, $10 deposit) closed positions within
*seconds* at reported "2.2R", "37.6R", "94.3R", then latched the circuit breaker after five
trades and tested nothing for the remaining six years. Two compounding bugs:

1. **R was measured against planned risk, not actual.** `g_initialRiskAmt` stored the
   *planned* $0.045 while the position carried $17.15 of real risk — a 381× error. Every
   R-based exit (basket target, break-even, partial take-profit, time stop) therefore fired
   on a few cents of movement. The logged "2.2R" was 9.9 cents of profit.
   **Fix:** the risk actually carried by the position is stored, so R means R.
2. **The min-lot override had no ceiling.** Built for accounts slightly over the planned cap,
   it permitted **172% of equity** on a single trade. One loss exceeded the daily limit 57×
   and latched the breaker permanently. **Fix:** `InpMaxRiskPctHard` (default 20%) is an
   absolute ceiling the override cannot cross.

The self-test now also reports the **minimum viable deposit** for the symbol at current
volatility — the binding constraint is not margin but that one stop-out must fit inside the
risk ceiling. At March-2020 gold volatility (ATR ≈ $11) a single minimum-lot stop-out costs
about $17, which needs roughly $85 of equity to sit under a 20% ceiling and ~$685 to honour
a 2.5% plan. At typical gold volatility (ATR ≈ $1.50) those figures fall to about $11 and
$90. **A $10 account cannot trade gold at COVID-era volatility under any risk setting** —
that is arithmetic, not configuration.
