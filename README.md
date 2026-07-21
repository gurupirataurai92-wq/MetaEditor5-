# MetaEditor5-

A modular MQL5 Expert Advisor for the **Deriv Volatility 75 Index (V75)**, built
around a confluence-based decision engine and layered risk management. Designed to
run from a low account balance, so capital-preservation controls are first-class.

> **Not financial advice, and not yet validated.** The code compiles as a
> structure but has **not** been backtested or forward-tested. Compile it in
> MetaEditor, run it through the MT5 Strategy Tester on real V75 tick data, and
> forward-test on a demo account before risking any capital. Synthetic indices are
> RNG-generated — past behavior is a weak guide to future results, and overfitting
> is a real risk.

## Architecture

The EA is split into single-responsibility modules so strategy logic and risk
logic can evolve independently.

```
MQL5/
  Experts/V75EA/V75EA.mq5            Main EA: wires modules, OnTick pipeline
  Include/V75EA/
    Types.mqh                        Shared enums/structs (ENUM_SIGNAL, dashboard state)
    VolatilityMath.mqh               V75 arithmetic: sigma, vol ratio, touch prob
    RegimeDetector.mqh               7-way market regime classification
    MultiTimeframe.mqh               Higher-timeframe directional bias (M15 + H1)
    MarketStructure.mqh              Swing points, HH/HL vs LH/LL, BOS / CHoCH, S&R
    TrendStrength.mqh                Trend quality score (ADX + slope + distance)
    MomentumEngine.mqh               Body size / candle runs / rate-of-change
    ConfluenceEngine.mqh             Scores all of the above into one decision
    RiskManager.mqh                  ATR + %-equity position sizing
    SafetyGuard.mqh                  Daily loss, drawdown, streak, spread/margin caps
    OodaEngine.mqh                   OODA cycle + adaptive God-mode feedback loop
    RecoveryManager.mqh              Bounded, opt-in loss recovery (capped martingale)
    Dashboard.mqh                    On-chart status panel + PAUSE / CLOSE-ALL buttons
    TradeManager.mqh                 Execution, breakeven, partial close, ATR trailing
    PerformanceTracker.mqh           Win rate, profit factor, drawdown, per-regime
```

## The V75 arithmetic (why the EA does what it does)

V75 is a **driftless geometric Brownian motion** with constant annualized
volatility (75%). `VolatilityMath.mqh` encodes that directly:

- **Per-bar sigma** — `σ_bar = 0.75 × √(barSeconds / yearSeconds)`: the theoretical,
  *known* expected magnitude of a bar. The one predictable parameter.
- **Vol ratio** — realized σ (from actual log-returns) ÷ theoretical σ. Above 1 =
  expansion/clustering, below 1 = compression. This is the **only exploitable
  signal**, because magnitude is predictable but direction is not. The EA skips
  markets below `InpMinVolRatio` (dead tape isn't worth the spread).
- **First-passage touch probability** — reflection principle:
  `P(touch d within t) = 2·(1 − Φ(d / (price·σ_horizon)))`. Logged on every entry so
  the risk geometry is explicit.
- **Sigma-scaled stops** — with `InpStopMode = STOP_SIGMA`, the stop is placed at
  `k` theoretical sigmas, making risk constant in *probability* terms rather than in
  arbitrary pips.

**The hard truth this encodes:** under pure driftless GBM, *no* stop/target geometry
beats break-even — first-passage odds exactly offset the payoff ratio, and spread
makes it negative. So the EA does **not** bet on price direction from geometry; it
trades the *deviations from randomness* (vol clustering + trend persistence) that the
confluence stack measures, and uses the math to size risk honestly.

## "Godmode"-style traits

Traits common to commercial synthetic-index EAs (e.g. the Medula/Godmode category),
implemented here under the same risk rails:

- **On-chart dashboard** (`Dashboard.mqh`) — live regime, confidence vs adaptive
  threshold, vol ratio, risk multiplier, recovery step, open positions, day P/L,
  equity — plus **PAUSE/RESUME** and **CLOSE ALL** buttons wired through `OnChartEvent`.
- **Bounded recovery** (`RecoveryManager.mqh`, `InpUseRecovery`, default **OFF**) — after
  a loss, raises the risk request by a capped multiplier (`stepFactor^step`, hard
  ceiling `InpRecoveryMaxMult`) for at most `InpRecoveryMaxSteps` steps, resets on any
  win, and disables itself below an equity floor. Unlike classic martingale it is
  bounded *and* still clamped by `InpMaxRiskPercent` and every SafetyGuard breaker —
  it cannot compound a losing run without limit.
- **Session filter** (`InpUseSession`) — restrict trading to chosen server hours.
- **Daily profit target** (`InpDailyProfitTarget`) — once hit, flatten and lock in for
  the day.
- **Push notifications** (`InpUseNotifications`) — entry/exit alerts to the MT5 mobile
  app (needs a MetaQuotes ID configured).

## God mode (OODA loop)

With `InpGodMode` enabled the EA runs an explicit **Observe → Orient → Decide →
Act → Feedback** cycle (`OodaEngine.mqh`):

- **Observe** — ATR, regime, and spread snapshot each cycle.
- **Orient** — the confluence score is evaluated under an *adaptive* threshold.
- **Decide** — signal, risk request, SL/TP (targets stretch 1.5× in strong-trend
  or breakout regimes), and trailing on/off.
- **Act** — same-direction pyramiding up to `InpMaxPositions`, plus an ATR
  trailing stop that only ever tightens.
- **Feedback** — a rolling 32-trade win/loss buffer adapts the loop: a win rate
  ≥ 55% slowly eases the threshold (floor `InpGodMinConfidence`) and boosts risk
  (ceiling `InpGodRiskBoostMax`); a win rate ≤ 45% tightens the threshold and cuts
  risk *faster* than it ever loosens (defensive asymmetry).

**God mode is adaptive-aggressive, not risk-free.** Every adaptive risk request is
still clamped by `RiskManager`'s hard cap (`InpMaxRiskPercent`), and every entry is
still gated by `SafetyGuard`'s daily-loss, drawdown, losing-streak, spread, and
margin circuit breakers. Worst-case simultaneous exposure is
`InpMaxPositions × InpMaxRiskPercent` — size those two inputs together.

## Per-bar decision pipeline

1. **RegimeDetector** — trending / ranging / breakout / compression.
2. **MultiTimeframe** — only trade in agreement with the higher-timeframe bias.
3. **MarketStructure** — structural bias plus BOS (continuation) / CHoCH (reversal).
4. **TrendStrength** — is the trend strong enough to be worth trading?
5. **MomentumEngine** — is price action confirming the direction?
6. **ConfluenceEngine** — combines the above into a weighted confidence score; a
   trade fires only when confidence ≥ `InpMinConfidence`. A CHoCH against the
   candidate direction vetoes the trade.
7. **RiskManager** — sizes the position from ATR-based stop distance and a fixed
   percentage of equity (optionally scaled by confidence).
8. **SafetyGuard** — blocks new trades on daily-loss, drawdown, consecutive-loss,
   wide-spread, or thin-margin conditions.
9. **TradeManager** — executes with requote retries, then manages breakeven and
   partial profit-taking on every tick.
10. **PerformanceTracker** — records realized results, including a per-regime
    breakdown, and prints a summary on deinit.

## Key inputs

| Input | Meaning | Default |
|---|---|---|
| `InpMinConfidence` | Confluence threshold to trade (0–1) | 0.60 |
| `InpRiskPercent` / `InpMaxRiskPercent` | Base / hard-cap risk per trade | 1% / 2% |
| `InpAtrStopMultiplier` / `InpAtrTakeProfitMult` | Stop / target in ATRs | 1.5 / 3.0 |
| `InpMaxDailyLossPercent` | Daily loss halt | 5% |
| `InpMaxDrawdownPercent` | Overall drawdown kill-switch | 15% |
| `InpMaxConsecutiveLoss` | Losing streak halt | 4 |

Defaults are conservative starting points, **not** tuned values — optimize them
against your own backtests.

## Not included (yet)

- **Machine learning** (blueprint item 12): the confluence score is the natural
  extension point — e.g. learn the confirmation weights or a regime classifier.
- **Martingale / grid recovery**: intentionally omitted for a low-balance account,
  where position-doubling is the fastest path to a blown account.
