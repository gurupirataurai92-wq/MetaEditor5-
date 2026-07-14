# IAX v6.0 "GODMODE" — Technical Documentation

Institutional Adaptive XAUUSD Trading System. EA file: `MQL5/Experts/IAX_v6/IAX_v6_GODMODE.mq5`.

This document covers every formula used by the EA, labels every design assumption explicitly, gives a parameter tuning guide, and lays out the staged testing procedure. **No part of this system promises profit.** Every gate, block, and decision is logged; read the logs, not your hopes.

---

## 1. Broker / account assumptions (ASSUMPTION)

- **ASSUMPTION**: account currency USD, "Just Markets"-style standard account, leverage 1:3000 (`InpAssumedLeverage`). This value is used only in `AuditConfigCoherence()` margin-capacity prints — actual margin math uses live `AccountInfoDouble`/`OrderCalcMargin` calls, not the assumed value, so a wrong assumption only skews a log line, never a risk calculation.
- **ASSUMPTION**: symbol is quoted as `XAUUSD` with an optional broker suffix (`InpSymbolSuffix`, e.g. `.m`). The EA falls back to the chart's native `_Symbol` if the suffixed symbol isn't found (never fails init over a suffix guess).
- **ASSUMPTION**: the USD-proxy context symbol defaults to `EURUSD` (a USD-weakness proxy: EURUSD up ⇒ USD weak ⇒ gold-bullish, same direction as a gold buy vote, so no sign flip). If you instead point `InpContextSymbolBase` at a USD-strength index (DXY-style), set `InpContextIsDXYStyle = true` to invert the vote.

## 2. Decision engine

### 2.1 Factor votes

Each of the 9 factors returns **+1** (bullish), **−1** (bearish), or **0** (neutral/unavailable):

| # | Factor | Default weight | Formula |
|---|---|---|---|
| 0 | Market Structure | 26 | Fractal swing highs/lows (2-bar-each-side pivots) over the last 60 signal-TF bars. +1 if the last two swing highs AND the last two swing lows are both rising (HH & HL). −1 if both falling (LH & LL). Else 0. |
| 1 | Momentum | 16 | EMA13 vs EMA34 (signal TF) AND MACD(12,26,9) main vs signal line must agree in direction. |
| 2 | Trend | 16 | EMA21 vs EMA55 on the trend TF. Trend TF auto-escalates to H1 (then H4 in the pathological case) whenever `SignalTF >= TrendTF`. |
| 3 | Volatility | 10 | If close breaks the prior-20-bar high/low → breakout vote in that direction. Else, if ATR(14) > 1.2× its 20-bar average, the vote **backs whatever Momentum already says** (vol expansion confirms, doesn't originate). |
| 4 | Liquidity | 10 | Swing-sweep-and-reject: if the last closed bar's high exceeds the prior 20-bar (bars 2..21) swing high but closes back below it → −1 (sell, liquidity grab reversal). Symmetric for lows → +1. |
| 5 | Candlestick Wick | 20 | Priority cascade: (a) engulfing (body fully engulfs prior body) → strongest signal; else (b) pin-bar (tail ≥ 50% of range, close in outer 40% of range); else (c) 3-bar cumulative tail imbalance ≥ 1.5×. |
| 6 | Tick-Delta Flow | 14 | Up-ticks vs down-ticks over the last 300 bid ticks. ≥60% up → +1, ≤40% up (⇒ ≥60% down) → −1. |
| 7 | Session VWAP | 10 | +1 if price is above the running session VWAP **and** VWAP is sloping up; −1 if below **and** sloping down (both must agree). |
| 8 | Context Symbol | 8 | EMA8 vs EMA21 on the context symbol (M5), sign-flipped if `InpContextIsDXYStyle`. Disabled (vote forced to 0, weight excluded from the pool) if the context symbol can't be resolved. |

### 2.2 Probability & confidence

```
activeWeightSum = Σ weight[f]                    for all AVAILABLE factors
buyProb  = Σ weight[f] where vote[f] > 0  / activeWeightSum
sellProb = Σ weight[f] where vote[f] < 0  / activeWeightSum
edge     = |buyProb − sellProb|
confidence = edge × regimeQuality × sessionQuality × 100
if ignitionBar: confidence *= 1.15
if exhaustionBar AND direction is the continuation side: confidence *= 0.65
```

A trade requires **both** `edge >= InpMinVoteEdge` (default 0.12) **and** `confidence >= eff_MinConfidenceToTrade`. The edge floor exists because a near-50/50 vote split only "donates the spread" to the broker — it is not a real signal even if weighted probability nudges the confidence number up via regime/session multipliers.

### 2.3 Regime classifier (14 states)

Built from EMA21/55 (trend TF) spread, ADX(14) (trend TF), and ATR(14) (trend TF) expansion/compression vs its 20-bar average:

`STRONG_BULL/BEAR` (ADX≥30), `NORMAL_BULL/BEAR` (ADX≥20), `WEAK_BULL/BEAR` (ADX<20), `RANGE` (ADX<18, tight EMA spread), `BREAKOUT_UP/DOWN` (vol expansion + trend just flipped + ADX>20), `VOL_EXPANSION`, `VOL_COMPRESSION`, `EXHAUSTION_UP/DOWN` (long opposing wick after a directional run), `REVERSAL_RISK` (falling ADX, tight spread), `UNKNOWN` (insufficient data — always the most conservative multiplier).

Regime quality multipliers: 1.20 (strong/breakout), 1.05 (normal/vol-expansion), 0.90 (weak), 0.80 (range/compression), 0.75 (exhaustion/reversal-risk), 0.70 (unknown).

### 2.4 Session quality

GMT-hour based: London∩NY overlap (13-16h) ×1.08, London (8-16h) ×1.05, NY (13-21h) ×1.03, Asia ×0.92, rollover (21-01h) ×0.85.

### 2.5 Ignition / exhaustion bars

- **Ignition**: body ≥70% of range, range >1.1×ATR(20-avg), tick-volume ≥1.4× its 20-bar average, close beyond the prior 5-bar micro-range.
- **Exhaustion**: a directional 3-bar run capped by a bar whose opposing wick is ≥55% of its own range.

## 3. Entry engine

Three modes (`InpEntryMode` / profile override):
- **MARKET** — immediate fill, pays the spread.
- **PASSIVE_LIMIT** (default) — posts a limit at the current bid (buy) / ask (sell), so a fill **earns** the spread instead of paying it. Unfilled pendings auto-cancel after `InpPassiveTimeoutSec`.
- **BREAK_STOP** — stop order at the prior bar's high/low + spread; only fills on confirmation.

`InpEntriesPerSignal` positions are opened per qualifying bar, each with its own laddered TP: position *i* targets `base × (1 + InpLadderStep × i)`, so the group scales itself out through a move instead of sharing one exit. All order placement goes through `SendWithRetry()` — up to `InpSendRetryAttempts` (default 3) attempts, retrying only on REQUOTE / PRICE_CHANGED / PRICE_OFF / TIMEOUT / CONNECTION, refreshing price between attempts, and recording latency + slippage.

## 4. Geometry

```
effectiveTP = max(userTP, InpTPSpreadFloorMult × currentSpreadUSD)
```
never lets the target be smaller than a multiple of the entry cost. SL/TP distances (ATR-based or fixed-dollar) are then scaled by a **regime geometry multiplier** (e.g. breakout 1.2×SL/1.8×TP, range 0.9/0.8, compression 0.8/0.7 — see `ApplyRegimeGeometry()` for the full 14-state table), padded away from `.00`/`.50` round-number levels by `InpRoundLevelPadPoints` (anti-stop-hunt), and finally clamped so `|entry - SL/TP| >= brokerStopsLevel + spread` (a sub-clamp TP is physically impossible and is logged as such, never silently accepted). Lot size auto-grows with equity via `InpLotPer100USD`, always floored at the broker's minimum lot and capped at its maximum.

## 5. Trade management

- **R-Multiple Manager**: at `+InpBE_TriggerR` (default 1.0) → SL to breakeven + `InpBE_PartialPct`% partial close. At `+InpTrailTriggerR` (default 2.0) → ATR(14)×`InpTrailATRMult` trailing stop, one-directional (only ever tightens).
- **Basket-group layer**: all open same-direction positions are aggregated (volume-weighted average entry, summed floating profit). The group is cut entirely if: floating loss ≤ `−InpBasketMaxLossUSD`, OR floating profit has given back ≥ `InpBasketGivebackPct`% from its peak (only once peak exceeds half the max-loss threshold, so a $2 peak doesn't trigger a "giveback" cut), OR thesis invalidation (`oppositeProb >= InpThesisInvalidationProb` **and** the Market Structure factor has flipped against the basket). On an exhaustion bar against the basket's direction, the group trims 50% rather than fully flattening.
- **Bar-confirmed flip exit**: the opposite-direction vote must persist for `InpFlipConfirmBars` **closed** signal-TF bars before the basket is flattened — intrabar flips are noise, not thesis changes.
- **EnsureProtectiveStops()**: runs every tick; any open position missing an SL gets one re-attached from the same regime-geometry formula used at entry. No naked positions, ever.

## 6. Swing module

Own magic number (`InpMagic + 7`), fully separate bookkeeping from the scalp baskets. Fires **only** when the current regime is `STRONG_BULL/BEAR` or `BREAKOUT_UP/DOWN` **and** ADX(14) on the trend TF ≥ `InpSwingMinADX`. Sizes at 2× the normal risk-based lot ("one larger position"), targets `InpSwingRR`:1 (default 2:1). Exits on: higher-TF EMA21/55 flip, a rolling 5-bar trend-TF fractal trail, a time-stop (`InpSwingTimeStopBars` trend-TF bars elapsed without reaching +1R), or a Friday-evening flatten ahead of the weekend gap. Overnight swap rates are logged before every entry that could hold overnight.

## 7. Governors (evaluated in this order — cheapest / most-likely-to-block first)

1. Feed degraded (heartbeat watchdog — no tick for `InpMaxFeedStaleSeconds`)
2. Daily loss halt (`InpDailyLossHaltPct` of day-start equity)
3. Max-DD flatten (`InpMaxDDFlattenPct` from peak equity; re-arms once DD recovers to half the threshold)
4. Loss-streak cooldown (`InpMaxConsecutiveLosses` → `InpCooldownMinutes` lockout)
5. Hourly / daily trade caps
6. Hourly expectancy learner (an hour bucket with ≥`InpHourMinSamples` closed baskets and negative average P/L is suppressed)
7. News blackout (MQL5 economic calendar, high-impact USD, ±`InpNewsBlackoutMin` minutes — **auto-bypasses and logs it** when the calendar is empty in the Strategy Tester, rather than silently blocking every bar of a backtest)
8. Spread gates — **dollar-based**, never point-based (absolute ceiling, then scalp ceiling)
9. Chase guard (skip if the current bar has already run > `InpChaseATRMult` × ATR)
10. Margin/caps (margin level, margin usage %, basket slot exhaustion)
11. HTF zone map (skip if an H4 fractal or `.00` round-number wall sits closer than `TP × InpZoneBlockMult`)

The equity-curve governor (equity below its own moving average) is **not** a hard block — it halves position size in `CalcLotSize()` instead.

## 8. Adaptive learning (online reinforcement — explicitly NOT a neural net)

On every closed basket, for each factor that voted **with** the trade's direction:
```
resultR = clamp(pnlUSD / initialRiskUSD, −2.5, +2.5)
weight[f] += weight[f] × InpLearningRate × resultR
weight[f]  = clamp(weight[f], InpMinFactorWeight, InpMaxFactorWeight)
```
then all 9 weights are renormalised to sum to 100 and persisted via `GlobalVariableSet` (survives terminal/EA restarts, keyed by symbol + magic). Factors that voted against or sat out the trade are untouched by that trade's outcome. The hourly-expectancy table, daily equity anchor, loss-streak counter, and cooldown timer persist to a CSV state file (`IAX6_state_<symbol>_<magic>.csv`) in `MQL5/Files`.

## 9. Ops / verification

- `AuditConfigCoherence()` (every init): prints the breakeven win rate implied by your SL/TP/spread, the effective minimum achievable TP, margin capacity vs burst size, noise-width SL sanity, and illustrative daily spread cost — WARNs on incoherent geometry rather than trading it silently.
- Build fingerprint printed at the top of every init (symbol, profile, stage, timeframes, magic, compile date/time) — confirm this before judging any fix.
- Environment check: terminal algo-trading flag, EA algo-trading flag, account trade permission, account expert permission, symbol trade mode, lot min/step/max, digits.
- Per-bar decision log (`InpVerboseDecisionLog`) with every rejection reason; every governor block increments a named counter.
- On-chart debug dashboard (`InpShowDashboard`): regime, session, probabilities, confidence, all 9 factor votes + live weights, kill-switch/feed/cooldown state, top blocker, position count, exposure, latency, slippage, trade counts.
- End-of-run report: bars/signals/sent/filled/rejected/closed, full block-reason table, hourly-expectancy state, shadow-gate count (signals that passed confidence but were blocked downstream). **Zero fills is printed as a DESIGN FAILURE naming the single most common blocker** — never a silent, quiet backtest.
- Trade journal CSV (`IAX6_journal_<symbol>_<magic>.csv`): every closed trade with regime, confidence, entry hour, all 9 factor votes, and realized P/L.
- On-chart **FLATTEN ALL** kill-switch button; push notifications on entries and the kill switch.
- Heartbeat watchdog: blocks new entries (does not stop position management) when no tick has arrived for `InpMaxFeedStaleSeconds`.
- `OnTester()` fitness: `PF × sqrt(trades) / (1 + DD%/10)`, forced to **0** below `InpMinTradesForFitness` (default 50) closed trades — so the optimiser cannot reward a lucky thin sample.

## 10. Progressive validation

`InpValidationStage` (1-5) documents which layer you're testing; `InpRunStage1SelfTest = true` (only active in the Strategy Tester or on a demo account, **never live**) runs an automated lifecycle self-test at `OnInit`: open → modify SL → partial close → close, for BUY then SELL, printing PASS/FAIL + retcode at every step. Never validate everything at once — bring stages up incrementally:

1. **Stage 1 — Lifecycle**: run with `InpRunStage1SelfTest=true` on `PROFILE_VALIDATION` (confidence gate relaxed to 0) in the Strategy Tester. All 8 steps (4 per side) must PASS before touching anything else.
2. **Stage 2 — Risk/geometry**: switch to a real profile (`SCALP_M1`/`SCALP_M5`/`SWING_M15`), confirm `AuditConfigCoherence()` shows no WARNs, and that trades open with correctly clamped SL/TP.
3. **Stage 3 — Management**: verify breakeven/partial/trailing/flip-exit/basket-group cuts fire correctly in the tester's chart/log across a volatile stretch of history.
4. **Stage 4 — Scaling**: raise `InpEntriesPerSignal` above 1, confirm laddered TPs and margin math in `AuditConfigCoherence()` still clears the burst-margin WARN.
5. **Stage 5 — Full filter stack**: enable every governor at realistic thresholds; check the end-of-run block-reason table for a sane distribution (not 99% blocked by one governor, not zero fills).

### Coherent presets (`InpProfile`)

`SCALP_M1`, `SCALP_M5`, `SWING_M15`, `VALIDATION`, `CUSTOM` — each is an internally consistent bundle of timeframe, entry mode, confidence gate, geometry multipliers, and spread ceiling (see `ApplyProfile()`), so a hand-mixed contradictory setting (e.g. M1 scalp geometry with a swing-sized spread ceiling) is structurally unreachable outside `CUSTOM`.

## 11. Economic honesty constraints (ASSUMPTION-labelled, computed live, never silently skipped)

- **Breakeven win rate** = `SL / (SL + effectiveTP)` — printed every init for your actual configured numbers, not a generic textbook figure.
- **Effective minimum TP** = broker stops level + current spread. A target below this is not "aggressive," it is physically impossible on this broker/symbol, and `CalcGeometry()` clamps to it.
- **Margin capacity**: `AuditConfigCoherence()` computes margin for one lot via live `OrderCalcMargin` and states the maximum number of simultaneous baskets the account can actually hold at the configured margin-usage cap — and separately WARNs if a single burst (`InpEntriesPerSignal` positions) alone would exceed that cap.
- **Cost of trading every candle**: an illustrative daily spread-cost-as-%-of-equity figure is printed for the configured signal timeframe.
- **Sub-minimum-lot accounts**: if the broker's minimum lot exceeds `InpBaseLot`, size is floored to the broker minimum and a WARN states plainly that a cent/micro account is the correct structural fix — not a parameter hack.
- If your parameter set is arithmetically negative before strategy quality is even considered (e.g. sub-spread targets + noise-width stops + more simultaneous positions than margin allows + no halts), the coherence audit will show it. The EA does not pretend this can be fixed by lot-size tricks.

## 12. Parameter tuning guide

Optimise **3–5 parameters at a time**, never all ~90 inputs simultaneously. Use **Custom max** as the Strategy Tester optimisation criterion so `OnTester()`'s PF/sqrt(trades)/DD-penalty formula drives selection. **Always validate the winning parameter set on a different, disjoint date range** — if performance collapses out-of-sample, that's curve-fitting, not edge, no matter how good the in-sample run looked.

1. **Stage 1 — whether it trades at all**: `MinConfidenceToTrade`, `InpMinVoteEdge`, `InpEntryMode`. Goal: a healthy, non-zero fill rate with a reasonable block-reason distribution.
2. **Stage 2 — geometry**: `InpFixedSL_USD`/`InpFixedTP_USD` or `InpSL_ATR_Mult`/`InpTP_ATR_Mult`, `InpTPSpreadFloorMult`. Goal: breakeven win rate (from the coherence audit) that your factor edge can plausibly clear.
3. **Stage 3 — management**: `InpBE_TriggerR`, `InpTrailTriggerR`, `InpFlipConfirmBars`, `InpBasketGivebackPct`. Goal: R-multiple capture that doesn't get chopped by noise but also doesn't give back full winners.

Lock each stage's winner before advancing to the next — don't re-open Stage 1 while tuning Stage 3.

## 13. Grade-A acceptance criteria (spec, not a guarantee)

Compiles clean in MetaEditor · Stage-1 lifecycle passes with zero FAILs · produces trades in "every tick based on real ticks" backtests across both trending and ranging periods · profit factor ≥ 1.5 over ≥ 300 trades · max drawdown < 15% · profitable on two disjoint date ranges · every decision explainable from the logs · no subsystem silently blocks trading · **then** 2–4 weeks of demo trading matching the backtest within ±20% before any live capital, starting at micro/cent-account size.

This EA has not been backtested or demo-traded as part of this build — the acceptance criteria above are the bar it must clear before you trust it, not a claim that it already has.
