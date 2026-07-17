# XAUUSD GODMODE EA

An MQL5 Expert Advisor for MetaTrader 5: an adaptive M5 scalper for XAUUSD (gold),
built from `XAUUSD_GODMODE_EA_SPEC.md` — a thesis-driven, cost-aware, risk-governed
architecture that refuses to trade rather than trade badly.

No martingale, no grid, no averaging down, no basket recovery. Every position carries
a server-side stop. Every rejected setup is logged with a machine-readable reason —
if the EA isn't trading, the Journal says exactly which module blocked it.

## Layout

```
MQL5/
  Experts/GodmodeEA/XAUUSD_GodmodeEA.mq5   -- main EA, wires all modules together
  Include/GodmodeEA/                       -- one file per module, independently testable
    Defines.mqh              shared enums/structs
    BrokerAdapter.mqh         Module 1  -- symbol/contract auto-detect, quality gate
    MarketState.mqh           Module 2  -- TREND / STAND_DOWN regime engine
    ThesisEngine.mqh          Module 3  -- 4 thesis archetypes + invalidation + expectancy tracking
    ConfidenceEngine.mqh      Module 4  -- weighted scoring, tiered sizing, v1 adaptive weights
    CostGate.mqh              Module 5  -- spread/ATR cost ratio, spike circuit breaker
    ExecutionEngine.mqh       Module 6  -- M5 arm / M1 confirm pending-order cascade
    PositionManager.mqh       Module 7  -- structural SL, partials, trail, time/decay exits
    RiskGovernor.mqh          Module 8  -- money-based sizing, DD cutoffs, cooldowns, persistence
    Blackouts.mqh             Module 9  -- news/rollover/session/gap guards
    ExecutionQualityMonitor.mqh Module 10 -- slippage/rejection/latency tracking
    Journal.mqh               Module 11 -- CSV trade log + per-bar rejection log
    DegradationMonitor.mqh    Module 12 -- rolling expectancy drift detection, auto-halve/halt
    Dashboard.mqh             Module 13 -- on-chart status, shadow-mode indicator
```

## Install

1. Copy the contents of `MQL5/` into your MetaTrader 5 terminal's `MQL5/` data folder
   (File → Open Data Folder → `MQL5/`), merging the `Experts/` and `Include/` subfolders.
2. Open `XAUUSD_GodmodeEA.mq5` in MetaEditor and compile (F7). This repo was built
   without a Windows/MetaEditor toolchain available, so **compile and fix any
   reported syntax issues before first use** — the code has been carefully
   hand-verified (brace balance, signature matching, MQL5 API usage) but not
   run through the real compiler.
3. Attach to an XAUUSD (or broker-variant) M5 chart with `InpShadowMode = true`
   first. Watch the Experts log and the two CSV files it produces
   (`GodmodeEA_<symbol>_trades.csv`, `GodmodeEA_<symbol>_rejections.csv`) in
   `MQL5/Files/` before ever setting `InpShadowMode = false`.
4. Follow the spec's own validation staging (Part 3): shadow mode → real-tick
   backtest on your broker's data → walk-forward across ≥12 months spanning both
   trending and ranging regimes → demo 2-4 weeks → micro-live at 0.25% risk.
   Nothing here validates itself — `InpExpectedAvgR` (used by the
   DegradationMonitor) **must** come from your own backtest, not a guess.

## Known simplifications (v1)

These are deliberate scope cuts, not hidden bugs — flagging them so nothing is
mistaken for more validated than it is:

- **Swing detection** uses a confirmed k-bar fractal (lags the live edge by
  `InpFractalK` bars). Fine for structural SL/invalidation anchoring; not a
  zero-lag pivot detector.
- **Blended R-multiple on partial exits**: after the 50%-at-1R partial, the
  Journal's `r_multiple` for a trade is computed from the final closing price
  only — it does not volume-weight the banked partial-R together with the
  runner's R. Expectancy/degradation stats will slightly understate trades that
  took a partial.
- **Correlation guard blocks rather than halves** (spec offers either). Simpler
  and stricter by default; change `RiskGovernor::CanTrade()` if you'd rather
  halve size when XAGUSD is open.
- **Shadow mode logs the would-be entry decision only** (archetype, confidence,
  sizing, levels) — it does not run a full parallel-simulated position through
  partials/trailing/exits. Good enough to validate signal generation; a fuller
  paper-trading simulator would be a natural v1.1.
- **Position state does not survive an EA restart mid-trade.** Risk-limit state
  (daily/weekly halts, loss streaks, degradation halt) persists via
  `GlobalVariables` and correctly survives a VPS reboot, but if a position is
  open when the EA restarts, `PositionManager` will not resume managing it —
  the broker-side SL is still live, but partials/trailing/time-stop/invalidation
  won't fire until you re-attach cleanly between trades.
- **Not implemented**: v2 meta-labeling ML (spec explicitly gates this behind
  having 500-1,000+ Journal-logged trades first — v1 must run first), HMM/k-means
  regime clustering (spec lists this as optional v2), dynamic broker-rollover-time
  detection (uses a fixed configurable server hour instead).
- **Economic Calendar dependency**: the news blackout uses MQL5's built-in
  Calendar API. If it's unavailable (e.g. some brokers/testers), the EA fails
  *closed* — it assumes a blackout rather than silently trading through an
  unmonitored news window, per the spec's "tighten, never loosen" directive.

## Validation reminder

Zero trades over a 2-year backtest is a design failure, not discipline — but so
is a suspiciously perfect equity curve. Read Part 3 of the spec before trusting
any backtest this produces: in-sample/out-of-sample split, walk-forward across
both the 2022 rate-hike regime and a trending bull run, a parameter-sensitivity
plateau check, and Monte Carlo trade-order shuffling judged on worst-case
drawdown — not the average.
