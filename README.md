# MetaEditor5-
Creating a meta editor code for a risk taking bot that is able to executes trades even from low account balance 

## Experts

### `WeltradeSynthEA.mq5` — Weltrade GainX / FlipX adaptive EA
An **entity-aware** EA for Weltrade synthetic indices. It auto-classifies every
symbol on the watchlist and applies *the technique that suits how the entity is
generated*.

**How these instruments are built** (Weltrade mirrors the Deriv synthetic engine —
RNG tick series, not real markets):

* **GainX = "Boom"-type spike index.** Price **grinds slowly *down*** on ~every
  tick, then prints a **large upward spike** on average once every *N* ticks
  (`N` = the number in the name: 800 / 999 / 1200). Tuned so `N × grind ≈ spike`,
  i.e. ~zero drift with **strong positive skew** (many small down-bars, rare huge
  up-bars).
* **PainX = "Crash"-type.** Mirror: grinds *up*, rare *down* spikes (negative skew).
* **FlipX = "Volatility"-type.** Driftless symmetric random walk — no spikes, no
  drift; the number is the volatility tier.

| Family | Generation | Engine applied |
|--------|-----------|----------------|
| **GainX** | down-grind + rare up-spike | **buy the grind** (spike side only); a spike bails the basket |
| **PainX** | up-grind + rare down-spike | **sell the grind** (spike side only) |
| **FlipX** | driftless random walk | **z-score mean-reversion** fade around the mean |
| *other*  | unknown synthetic | generic EMA trend + grind entry |

**Self-calibration (`InpAutoCalibrate`, on by default).** The name is only the
*initial guess*. For the first `InpSpikeWarmupBars` bars the EA observes every
symbol and measures its **actual** spike direction, frequency (`~bars/spike`) and
magnitude (`avgMag × ATR`). It then locks each engine to what the data shows:

* a dominant spike side (≥ `InpSpikeDirDominance` of spikes one way, with at least
  `InpMinSpikesForCal` spikes) → **spike engine** on that measured side;
* no reliable spike side → **FlipX-style mean reversion**.

So if your broker's GainX actually spikes the other way, or a "FlipX" turns out to
drift, the EA corrects itself instead of trusting the label — and it logs the
verdict (`Calibrated [SYMBOL]: … => SPIKE spikeDir=+1 (name-guess was …)`).

**Arithmetic EV engine (`InpUseEVGate`, on by default).** The generation formula
`N × grind ≈ spike` is traded *directly*: after calibration the EA knows each
symbol's average spike magnitude, average bars between spikes and average grind
per bar, and computes the measured expected value of every entry —

```
EV = capture% × avgSpike  −  hold% × avgBarsBetween × |grind/bar|  −  spread
```

Entries fire **only when EV clears costs by `InpEVSafety`**; the spike TP is
sized from the *measured* average spike (`InpSpikeCaptureFrac`), and early-cycle
entries right after a spike are skipped (`InpMinCycleFrac`). FlipX fades get the
mirror-image test: level mean-reversion implies **negative lag-1 return
autocorrelation**, so the EA measures it and only fades when it is really there
(`InpACGateMax`) — a pure random walk is stood aside instead of paying spread on
zero-EV trades. The calibration log prints each symbol's EV verdict
(`TRADEABLE` / `gate will block`).

**Why this is the profitable-by-design choice, honestly stated:** a correctly
specified synthetic is ~**zero expectancy** — no directional rule creates a real
edge, and fading a FlipX random walk is zero-E minus spread. So the EA does not
chase a fabricated edge; it maximises **survivability and skew**. It trades only
the spike-favourable side (positive skew), never grid-martingales the unbounded
anti-spike tail, and **banks the basket the moment a favourable spike prints**
(`InpBankOnSpike`). A post-spike cooldown (`InpPostSpikeCoolBars`) avoids chasing
stretched price, and spikes are detected via `InpSpikeATRmult × ATR`.

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
`InpUseNNFilter` / `InpNNThreshold`, `InpZEntry` (FlipX), the spike-engine block
(`InpSpikeDirOnly`, `InpGrindEntryRSI`, `InpSpikeATRmult`, `InpPostSpikeCoolBars`,
`InpBankOnSpike`), the `InpEnableRecovery` grid/basket block, and the
risk-management toggles. `InpSpikeDirOnly=true` (default) restricts GainX to longs
and PainX to shorts — the survivable skew; set it false only if you knowingly want
to fade the grind on both sides. Attach to any one synthetic chart; `OnTimer`
drives the whole watchlist. No DLLs, ONNX or external files required.

### `GoldPortfolioEA.mq5`
Gold-anchored volatility-ranked M1 multi-symbol scalping system (FX / metals /
crypto / oil).
