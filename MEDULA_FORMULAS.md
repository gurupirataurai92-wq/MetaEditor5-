# Medula EA — Formula Specification

This document defines the actual mathematical formulas and decision rules for each engine
in the Medula architecture. Every formula uses standard, public technical-analysis and
risk-management mathematics (ADX, ATR, Kaufman Efficiency Ratio, weighted scoring,
fractional-Kelly sizing, Pearson correlation, etc.) so it can be implemented directly in
MQL5. Symbols in `Code Font` are the variable names to use in implementation.

Notation conventions:
- `n` = lookback length (bars), configurable per formula.
- `[0]` = current/most recent bar, `[i]` = i bars back.
- `dir` = +1 for long/bullish, -1 for short/bearish.
- All "Score" values are normalized to **0–100** unless stated otherwise.
- `clamp(x, lo, hi)` = min(max(x, lo), hi).
- `sigmoid(x) = 1 / (1 + e^-x)`.

---

## 1. Market State Engine

Classifies the regime using three independent measurements combined into one label.

**Kaufman Efficiency Ratio (directional efficiency):**
```
ER(n) = |Close[0] - Close[n]| / Σ(i=1..n) |Close[i-1] - Close[i]|
```
`ER` → 1 means pure trend (no noise), `ER` → 0 means pure noise/chop.

**Volatility Ratio:**
```
VR = ATR(14) / SMA(ATR(14), 100)
```

**Volatility Percentile** (rank of current ATR in the trailing distribution):
```
VolPct = COUNT(ATR(14)[i] < ATR(14)[0], i=1..250) / 250 * 100
```

**Regime classification table:**

| Regime | Condition |
|---|---|
| `TRENDING` | `ADX(14) > 25` AND `ER(20) > 0.30` |
| `RANGING` | `ADX(14) < 20` AND `ER(20) < 0.20` |
| `BREAKOUT` | `VR > 1.5` AND `Close[0]` closes beyond Bollinger(20,2) band AND `MomentumScore` (§4) agrees in direction |
| `REVERSAL` | `CHoCH` flagged this bar (§2) AND `MomentumScore` diverges from prior trend direction |
| `HIGH_VOLATILITY` | `VolPct > 90` |
| `LOW_VOLATILITY` | `VolPct < 10` |
| `NEUTRAL` | none of the above fire |

Regimes are not mutually exclusive at the boundary; priority order when multiple fire:
`REVERSAL > BREAKOUT > HIGH_VOLATILITY > TRENDING > RANGING > LOW_VOLATILITY > NEUTRAL`.

---

## 2. Market Structure Engine

**Swing point detection** (fractal, `k` bars each side, default `k=2`):
```
SwingHigh[i]  := High[i] > High[i-k..i-1]  AND High[i] > High[i+1..i+k]
SwingLow[i]   := Low[i]  < Low[i-k..i-1]   AND Low[i]  < Low[i+1..i+k]
```
For noisy instruments, replace the fixed-bar fractal with an ATR-filtered ZigZag:
a new swing is only confirmed once price reverses by `≥ z * ATR(14)` (default `z = 1.5`).

**Break of Structure (BOS)** — continuation:
```
BullishBOS := Close[0] > LastSwingHigh  AND TrendDirection = +1
BearishBOS := Close[0] < LastSwingLow   AND TrendDirection = -1
```

**Change of Character (CHoCH)** — first reversal signal:
```
BullishCHoCH := Close[0] > LastSwingHigh  AND TrendDirection(prev) = -1
BearishCHoCH := Close[0] < LastSwingLow   AND TrendDirection(prev) = +1
```

**Structure Score** (net directional control, over last `N` swings, default `N=10`):
```
StructureScore = 100 * (BullBOS_count - BearBOS_count) / (BullBOS_count + BearBOS_count + 1)
```
Range: -100 (sellers in control) to +100 (buyers in control).

---

## 3. Trend Engine

**Normalized EMA slope** (in ATR units per bar, removes scale/instrument dependence):
```
EMA_slope(len) = (EMA(len)[0] - EMA(len)[n]) / (n * ATR(14))
```

**Trend components** (each rescaled to -1..+1 via `tanh`):
```
c1 = tanh(ADX(14)/25 - 1)              // trend strength via ADX
c2 = tanh(EMA_slope(50) * 10)          // slope of EMA50
c3 = tanh((ER(20) - 0.2) * 5)          // efficiency
c4 = sign(EMA(20) - EMA(50))           // fast/slow alignment
```

**Trend Score:**
```
TrendScore = 100 * (0.35*c1 + 0.30*c2 + 0.20*c3 + 0.15*c4)
TrendDirection = sign(TrendScore)
```

---

## 4. Momentum Engine

```
ROC(n) = (Close[0] - Close[n]) / Close[n] * 100
RSI_dev = RSI(14) - 50                              // -50..+50
MACD_hist = MACD_line - Signal_line
MACD_slope = MACD_hist[0] - MACD_hist[1]
Acceleration = Momentum[0] - Momentum[1]             // 2nd derivative of price
```

**Momentum Score:**
```
MomentumScore = 100 * tanh(
    0.40 * (RSI_dev/50) +
    0.30 * tanh(ROC(10)/2) +
    0.30 * tanh(MACD_slope / (0.1*ATR(14)))
)
```
`MomentumScore > 0` → bullish momentum, `< 0` → bearish. Magnitude = strength.
`Acceleration` sign flip against `MomentumScore` sign = early warning of exhaustion (used by Exit Engine, §14).

---

## 5. Volatility Engine

```
VR       = ATR(14) / SMA(ATR(14), 100)          // §1
VolPct   = percentile rank of ATR(14) over 250 bars   // §1
```

**Volatility Suitability Score** (penalizes both extremes — used by Confidence Engine):
```
VolSuitability = 100 * exp( -((VolPct - 55)^2) / (2 * 30^2) )
```
This is a Gaussian centered near "normal-to-slightly-elevated" volatility (peak at 55th
percentile), decaying toward 0 at both very low and very high extremes. Tune center/width
per instrument via backtest.

---

## 6. Liquidity Engine

**Equal-level clustering** — group swing highs/lows within tolerance:
```
tolerance ε = 0.15 * ATR(14)
Cluster(P) = { swing points S : |S.price - P| <= ε }
PoolStrength(P) = COUNT(Cluster(P))          // number of touches
```

**Liquidity Score** for the nearest pools above/below current price within distance
`d = 3 * ATR(14)`:
```
LiquidityAbove = Σ PoolStrength(P) for pools P > Close[0], (P - Close[0]) <= d
LiquidityBelow = Σ PoolStrength(P) for pools P < Close[0], (Close[0] - P) <= d

LiquidityScore = 100 * tanh( (LiquidityBelow - LiquidityAbove) / (LiquidityBelow + LiquidityAbove + 1) )
```
Positive → more resting liquidity below (supports longs, i.e., stronger magnet/support
below current price with sellers' stops likely resting above); use sign convention
consistent with your directional model when wiring into the Confidence Engine.

---

## 7. Multi-Timeframe Engine

```
Direction_tf = sign(TrendScore_tf)     // computed per timeframe using §3
Weight_D1 = 0.40, Weight_H4 = 0.30, Weight_H1 = 0.20, Weight_M15 = 0.10   // must sum to 1

MTF_Alignment = Σ Weight_tf * Direction_tf              // range -1..+1
MTF_Confluence = |MTF_Alignment| * 100                  // 0..100 strength of agreement
```
**Veto rule:** if `sign(Direction_M15) != sign(MTF_Alignment)` and `MTF_Confluence > 50`,
block trading against the higher-timeframe bias (hard filter, applied in Decision Engine).

---

## 8. Confidence Engine

Combine every engine's normalized -100..+100 (or 0..100) output into one probability-like
score. Weights are configurable and are the primary target of the Adaptive Parameter
Engine (§20).

```
Confidence_raw =
      w1 * (StructureScore/100)      // §2
    + w2 * (TrendScore/100)          // §3
    + w3 * (MomentumScore/100)       // §4
    + w4 * (LiquidityScore/100)      // §6
    + w5 * MTF_Alignment             // §7, already -1..+1

Default weights: w1=0.25, w2=0.25, w3=0.20, w4=0.15, w5=0.15  (Σw = 1)

Confidence_dir  = 100 * tanh(G * Confidence_raw)        // -100..+100, sign = direction
Confidence_mag  = |Confidence_dir|                       // 0..100, magnitude only

Gain G (default 2.5): because the weights sum to 1 and every component is
capped at ±1, |Confidence_raw| <= 1, and tanh(1) = 0.76 — without the gain the
score could never exceed 76 (and, after penalties, never reach a 60 threshold).
G = 2.5 maps strong multi-engine agreement (raw ≈ 0.44, i.e. ~44% of the
theoretical maximum) onto the ~80 confidence region, making the 50-85
threshold band meaningful and reachable.
```

**Penalties** (multiplicative dampeners applied to `Confidence_mag`):
```
Penalty_vol       = VolSuitability / 100                // §5, 0..1
Penalty_spread    = clamp(1 - (CurrentSpread/MaxSpread), 0, 1)
Penalty_execution = ExecutionQualityScore / 100          // §11 monitor

Confidence_final = Confidence_mag * Penalty_vol * Penalty_spread * Penalty_execution
```

---

## 9. Decision Engine

```
Direction = sign(Confidence_dir)
Cthreshold = 60          // default, adaptive (§20)
Hysteresis = 8           // prevents flip-flopping at the boundary

IF state == WAIT:
    IF Confidence_final >= Cthreshold AND MTF veto not triggered:
        Decision = (Direction > 0) ? BUY : SELL
    ELSE:
        Decision = WAIT

IF state == IN_TRADE:
    IF Confidence_final < (Cthreshold - Hysteresis) OR Direction flips:
        Decision = EXIT_SIGNAL   // handed to Exit Engine, §14
    ELSE:
        Decision = HOLD
```

---

## 10. Execution Engine

**Pre-trade validation (all must pass):**
```
Spread_ok      := CurrentSpread <= MaxSpreadPoints
Margin_ok      := FreeMargin >= RequiredMargin * SafetyFactor        // SafetyFactor default 1.5
Session_ok     := SessionMultiplier(§15) > 0
Exposure_ok    := TotalExposure + NewTradeRisk <= MaxAccountRisk     // §13
Correlation_ok := CorrelationPenalty(§17) did not veto
```

**Execution Quality Score** (rolling, used as a Confidence Engine penalty input):
```
FillRatio        = FilledOrders / AttemptedOrders
AvgSlippagePts   = mean(|RequestedPrice - FillPrice|) in points
SlipPenalty      = clamp(1 - AvgSlippagePts/MaxAcceptableSlippage, 0, 1)

ExecutionQualityScore = 100 * FillRatio * SlipPenalty
```
If `ExecutionQualityScore < 50` over the last 20 attempts, suspend new entries
(execution circuit breaker) until it recovers.

---

## 11. Basket Management Engine

```
AvgEntry        = Σ(Volume_i * Price_i) / Σ Volume_i
TotalVolume     = Σ Volume_i
BasketFloatPL   = Σ (CurrentPrice - Price_i) * Volume_i * ContractSize * dir_i
BasketBreakeven = AvgEntry + (TotalCommission + TotalSwap) / (TotalVolume * ContractSize) * dir
BasketTP_price  = AvgEntry + dir * TargetR * ATR(14)        // TargetR configurable (e.g. 2.0)
BasketRiskR     = BasketFloatPL / (AccountRiskUnit)         // expressed in "R" multiples
```
Close entire basket when `BasketFloatPL >= BasketTP_target` (in currency) **or**
`BasketRiskR >= TargetR`, whichever the config selects.

---

## 12. Position Scaling Engine

A new add-on position requires **all** of:
```
ThesisValid   := Direction_new == Direction_original
Confidence_ok := Confidence_final >= k * Confidence_at_entry     // k default 0.9 (not weaker than 90% of original)
Spacing_ok    := |CurrentPrice - LastEntryPrice| >= s * ATR(14)  // s default 1.0
RiskAllows    := BasketRiskUsed + NewPositionRisk <= MaxBasketRisk
CountAllows   := OpenPositionsInBasket < MaxScaleIns             // e.g. 4
```

**Scale-in sizing (decaying, never martingale):**
```
Lot_n = BaseLot * DecayFactor^(n-1)         // DecayFactor default 0.7, n = add-on index (1st add = n=1)
```
This guarantees each subsequent add contributes strictly less risk than the previous one.

---

## 13. Risk Management Engine

```
RiskPerTradeAmount = Equity * RiskPct                 // RiskPct default 0.5%-1.0%
SL_distance_pts    = SLmultiplier * ATR(14) / Point    // SLmultiplier default 1.5
LotSize            = RiskPerTradeAmount / (SL_distance_pts * TickValue)

DailyLossLimit      = Equity_start_of_day * DailyLossPct        // e.g. 3%
MaxDrawdownLimit    = PeakEquity * MaxDDPct                     // e.g. 10%

CircuitBreaker := (Equity_start_of_day - Equity_now) >= DailyLossLimit
               OR (PeakEquity - Equity_now) >= MaxDrawdownLimit
IF CircuitBreaker: flatten all positions, block new entries until next session/manual reset.
```

---

## 14. Exit Engine

```
SL_price = Entry - dir * SLmultiplier * ATR(14)
TP_price = Entry + dir * TPmultiplier * ATR(14)

Trailing (Chandelier-style):
TrailStop_long  = max(TrailStop_long[prev],  HighestHigh(n) - TrailMult * ATR(14))
TrailStop_short = min(TrailStop_short[prev], LowestLow(n)   + TrailMult * ATR(14))

Time-stop:
IF BarsInTrade > MaxBars AND BasketFloatPL < MinAcceptablePL: EXIT

Structure invalidation:
IF (dir=+1 AND BearishCHoCH) OR (dir=-1 AND BullishCHoCH): EXIT

Momentum exhaustion (early warning, tightens trail rather than hard-exit):
IF sign(Acceleration) != sign(MomentumScore) AND |MomentumScore| was previously > 70:
    TrailMult *= 0.6   // tighten trail
```

---

## 15. Capital Allocation Engine

**Confidence + volatility scaled sizing** (used instead of, or blended with, the flat
Risk Engine formula in §13):

```
VolAdj = ATR_reference / ATR(14)                      // inverse-volatility targeting
ConfAdj = (Confidence_final / 100) ^ gamma             // gamma default 1.5 (superlinear reward for high confidence)

Lot_final = clamp( BaseLot * ConfAdj * VolAdj, MinLot, MaxLotCap )
```

**Fractional-Kelly cross-check** (cap, not primary sizing — Kelly is only a sanity bound):
```
f_kelly = (WinRate * AvgWinR - (1-WinRate) * AvgLossR) / AvgWinR
f_used  = clamp(0.25 * f_kelly, 0, MaxRiskPct)          // quarter-Kelly, hard capped
```
`Lot_final` must never imply risk exceeding `f_used * Equity`.

---

## 16. Session Intelligence Engine

```
SessionMultiplier(session) =
    Asian only        -> 0.6
    London            -> 1.0
    New York           -> 1.0
    London/NY overlap -> 1.2
    Dead zone (post-NY, pre-Asian) -> 0.3

EffectiveRisk = RiskPerTradeAmount * SessionMultiplier(current_session)
```
If `SessionMultiplier == 0` for a configured "no-trade" window, Decision Engine forces `WAIT`.

---

## 17. Correlation Engine

**Rolling Pearson correlation** of returns between instrument A and B over `n` bars:
```
r(A,B,n) = Cov(ReturnsA, ReturnsB) / (StdDev(ReturnsA) * StdDev(ReturnsB))
```

```
NetExposure(cluster) = Σ Exposure_i * sign(dir_i)     for instruments in correlated cluster (|r|>0.7)

CorrelationPenalty := 1  if |NetExposure(cluster) + NewTradeExposure| > MaxNetExposure
                     0  otherwise   (0 = veto the new trade, 1 = allow)
```
Also apply a soft dampener to Confidence when opening a same-direction trade highly
correlated (`|r|>0.7`) with existing basket exposure:
```
Confidence_final *= (1 - 0.3 * max(0, |r| - 0.7)/0.3)
```

---

## 18. Performance Analytics Engine

```
WinRate        = WinningTrades / TotalTrades
ProfitFactor   = GrossProfit / GrossLoss
Expectancy     = WinRate * AvgWin - (1-WinRate) * AvgLoss          // in currency or R
RecoveryFactor = NetProfit / MaxDrawdown
SQN            = mean(TradeR) / stdev(TradeR) * sqrt(N)            // System Quality Number
SharpeLike     = mean(TradeReturns) / stdev(TradeReturns) * sqrt(TradesPerYear)
```
Segment every metric by: symbol, session (§16), and market regime (§1) to feed §20.

---

## 19. Adaptive Parameter Engine

Generic bounded gradient update for any tunable parameter `P` (e.g., `Cthreshold`,
confidence weights `wi`, `RiskPct`):
```
PerformanceGradient = RollingExpectancy_now - RollingExpectancy_baseline
P_new = clamp( P_old + η * PerformanceGradient, P_min, P_max )
```
Apply an EMA smoothing to avoid noisy single-trade reactions:
```
P_smoothed = α * P_new + (1-α) * P_smoothed_prev      // α default 0.1
```
Example: if rolling expectancy over the last 50 trades in `TRENDING` regime declines
below the baseline, `Cthreshold` rises (system becomes more selective) — bounded to
`[50, 85]`.

---

## 20. Logging & Diagnostics Engine

No formulas — structured schema per decision:
```
{ timestamp, symbol, regime, structure_score, trend_score, momentum_score,
  volatility_score, liquidity_score, mtf_alignment, confidence_final,
  decision, lot_size, sl, tp, reason_string, basket_id, outcome }
```
Every BUY/SELL/WAIT/EXIT must log the full input vector that produced it — this is what
makes §19's adaptation and §18's analytics auditable.

---

## 21. Validation & Testing Engine

**Walk-forward:**
```
Split history into k contiguous folds.
For fold i = 1..k-1:
    Optimize parameters on folds[1..i]  (in-sample)
    Evaluate frozen parameters on fold[i+1]  (out-of-sample)
Aggregate OOS metrics only — in-sample results are not evidence of robustness.
```

**Monte Carlo stress test:**
```
Resample the trade-return sequence (with replacement) M times (e.g., M=5000).
For each resample, compute MaxDrawdown and FinalEquity.
Report the 5th/50th/95th percentile of MaxDrawdown as the realistic risk envelope.
```

A strategy is only considered validated if OOS `ProfitFactor > 1.3` and OOS `SQN > 2`
across at least two distinct market regimes (§1), not just the regime it was tuned on.

---

## Engine Data Flow Summary

```
Tick
 → §1 Market State, §2 Structure, §3 Trend, §4 Momentum, §5 Volatility, §6 Liquidity, §7 MTF
 → §8 Confidence (weighted combination + penalties)
 → §9 Decision (threshold + hysteresis + MTF veto)
 → §10 Execution (pre-trade checks) → §11 Basket update → §12 Scaling check → §13/§15 sizing
 → §14 Exit checks (every tick, independent of new-entry logic)
 → §16 Session gating, §17 Correlation gating (applied inside §9/§10)
 → §18 Analytics (post-trade) → §19 Adaptive tuning (periodic) → §20 Logging (continuous)
 → §21 Validation (offline, pre-deployment and periodic re-validation)
```

All weights, multipliers, and thresholds above are starting defaults for backtesting —
none are "final" until validated per §21 on the target instrument and timeframe.
