# Medula EA — MQL5 Implementation

Modular, event-driven Expert Advisor implementing the engines defined in
[`MEDULA_FORMULAS.md`](../../../MEDULA_FORMULAS.md) (repo root).

> **Prefer a single file?** [`../Medula_Single.mq5`](../Medula_Single.mq5) is
> the same EA consolidated into one `.mq5` with **zero dependencies** — no
> `.mqh` files, no standard-library includes (raw `OrderSend` instead of
> `CTrade`). Copy that one file into `MQL5/Experts/` and compile. The modular
> version in this folder is easier to maintain and extend; the single-file
> version is easier to distribute. Both trade identically.

## Files

| File | Engines |
|---|---|
| `Medula.mq5` | Core Engine — event loop, wiring, inputs, adaptive threshold |
| `MedulaTypes.mqh` | Shared types, config, math helpers, Logging & Diagnostics (§20) |
| `MedulaIndicators.mqh` | Indicator handle manager (chart TF + D1/H4/H1) |
| `MedulaAnalysis.mqh` | Market State (§1), Structure (§2), Trend (§3), Momentum (§4), Volatility (§5), Liquidity (§6), Multi-Timeframe (§7) |
| `MedulaConfidence.mqh` | Confidence Engine (§8), Decision Engine (§9) |
| `MedulaRisk.mqh` | Risk Management (§13), Session Intelligence (§16), Correlation (§17), sizing helpers (§15) |
| `MedulaTrade.mqh` | Execution (§10), Basket Management (§11), Position Scaling (§12), Exit Engine (§14) |
| `MedulaAnalytics.mqh` | Performance Analytics (§18), Kelly cap (§15), Adaptive Parameters (§19) |

## Installation

1. In MetaTrader 5: **File → Open Data Folder**.
2. Copy the whole `Medula` folder into `MQL5/Experts/` so you have
   `MQL5/Experts/Medula/Medula.mq5` plus the seven `.mqh` files beside it.
3. Open `Medula.mq5` in MetaEditor and press **F7** (Compile). All includes are
   relative, so no extra include-path setup is needed.
4. In the terminal, drag **Medula** onto an **M15** chart (the architecture
   assumes M15 execution with D1/H4/H1 context) and enable **Algo Trading**.

## Before going anywhere near real money (§21)

This code base is a starting point, not a validated strategy. Follow the
Validation & Testing Engine workflow:

1. **Backtest** in the Strategy Tester ("Every tick based on real ticks")
   over multiple years and instruments.
2. **Walk-forward**: optimize on one period, evaluate frozen parameters on the
   next; only out-of-sample results count.
3. Only trust a configuration with OOS profit factor > 1.3 across at least two
   distinct market regimes, then **forward test on a demo account**.
4. All input defaults are the spec's starting values — they are meant to be
   re-derived per instrument via this workflow.

## Notes

- Decisions are logged to the Experts tab and (optionally) to
  `MQL5/Files/MedulaLog.csv` with the full input vector that produced each
  action, so every trade is explainable and auditable.
- `InpAllowMinLot` rounds sizes up to the broker minimum so small accounts can
  trade, at the cost of exceeding the configured risk percentage — disable it
  if strict risk adherence matters more than trade frequency.
- The daily-loss/drawdown circuit breaker flattens all positions and suspends
  trading; the daily component re-arms at the next calendar day.
- Correlation gating only activates when the EA holds positions on other
  symbols under the same magic number (e.g., when attached to several charts).
