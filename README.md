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

**Medula-style grid/basket recovery** (`InpEnableRecovery`, on by default): the
aggressive-recovery character of the synthetic-index EA family. When enabled, the
initial leg carries **no hard per-trade SL**; instead the position is defended as
a *basket*:

* **Martingale grid adds** — on each adverse move of `InpGridStepATR × ATR`, a new
  same-direction leg is added with lot × `InpGridLotFactor`, up to
  `InpMaxGridLevels`, lowering the basket's average entry.
* **Basket take-profit** — the whole basket closes once combined profit reaches
  `InpBasketTP_R × initial-risk` (optionally *trailed* via `InpBasketTrailing`).
* **Hard safety net** — the basket is force-closed if its loss exceeds
  `InpMaxBasketLossPct` of equity, and the global drawdown kill-switch and
  per-symbol circuit breaker still apply on top. Grid levels, lot size and margin
  are all capped.

Turn `InpEnableRecovery` **off** to revert to the conservative one-shot mode
(fixed ATR stop-loss with partial-close / breakeven / trailing / win-streak
pyramiding).

> ⚠️ Grid/martingale recovery is inherently high-risk: it improves win-rate at the
> cost of rare-but-large losing baskets. Backtest on your Weltrade symbols and size
> `InpGridLotFactor`, `InpMaxGridLevels` and `InpMaxBasketLossPct` to a loss you can
> accept before running it live.

Key inputs: `InpWatchlist`, `InpSignalTF`, `InpRiskPercent`, `InpUseTierEngine`,
`InpUseNNFilter` / `InpNNThreshold`, `InpZEntry` (FlipX), `InpAllowCounterDrift`
(GainX/PainX), the `InpEnableRecovery` grid/basket block, and the risk-management
toggles. Attach to any one synthetic chart; `OnTimer` drives the whole watchlist.
No DLLs, ONNX or external files required.

### `GoldPortfolioEA.mq5`
Gold-anchored volatility-ranked M1 multi-symbol scalping system (FX / metals /
crypto / oil).
