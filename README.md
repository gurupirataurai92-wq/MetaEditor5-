# MetaEditor5-
Creating a meta editor code for a risk taking bot that is able to executes trades even from low account balance 

## Experts

### `WeltradeSynthEA.mq5` — Weltrade GainX / FlipX adaptive EA
An **entity-aware** EA for Weltrade synthetic indices. It auto-classifies every
symbol on the watchlist and applies *the technique that suits the entity*:

| Family | Behaviour | Engine applied |
|--------|-----------|----------------|
| **GainX** | persistent upward drift + spikes | Trend/pullback **drift-rider** (bias long) |
| **PainX** | persistent downward drift | Trend/pullback drift-rider (bias short) |
| **FlipX** | oscillating, no drift | **z-score mean-reversion** fader (both sides, TP → mean) |
| *other*  | unknown synthetic | generic HTF trend follower |

Built with an **OODA** control loop — *Observe* (ATR / EMA / StdDev / RSI / drift),
*Orient* (classify entity + regime), *Decide* (rule trigger + online neural-net
confidence gate), *Act* (tiered risk sizing, execution, then partial / breakeven /
trailing / pyramid management).

Techniques harvested from the gold portfolio EA and adapted to synthetics:
tiered low-balance sizing (trades from a ~$2 floor, cent-account aware), ATR risk
model, native self-training neural filter, per-symbol circuit breakers, rolling
win-rate guard, drawdown recovery, portfolio risk governor and an equity
kill-switch. **Session and news-blackout gating are deliberately removed** —
Weltrade synthetics trade 24/7 and are not driven by real-market news, so that
logic does not suit these instruments.

Key inputs: `InpWatchlist`, `InpSignalTF`, `InpRiskPercent`, `InpUseTierEngine`,
`InpUseNNFilter` / `InpNNThreshold`, `InpZEntry` (FlipX), `InpAllowCounterDrift`
(GainX/PainX), and the risk-management toggles. Attach to any one synthetic chart;
`OnTimer` drives the whole watchlist. No DLLs, ONNX or external files required.

### `GoldPortfolioEA.mq5`
Gold-anchored volatility-ranked M1 multi-symbol scalping system (FX / metals /
crypto / oil).
