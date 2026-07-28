# MetaEditor5-
Creating a meta editor code for a risk taking bot that is able to executes trades even from low account balance

## Medula EA

- **[MEDULA_FORMULAS.md](MEDULA_FORMULAS.md)** — formula specification for all 21 engines.
- **[MQL5/Experts/Medula/](MQL5/Experts/Medula/)** — modular MQL5 implementation (`Medula.mq5` + `.mqh` engine files) with install and testing instructions.
- **[MQL5/Experts/Medula_Single.mq5](MQL5/Experts/Medula_Single.mq5)** — **v2.50, the maintained build.** Single file, zero dependencies (no includes at all): copy into `MQL5/Experts/` and compile.
- **[tests/verify_medula.py](tests/verify_medula.py)** — 131-check regression suite covering every engine formula, including an anti-stationary guarantee. Run with `python3 tests/verify_medula.py`.

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
