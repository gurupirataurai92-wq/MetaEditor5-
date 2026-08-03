# MetaEditor5-
Creating a meta editor code for a risk taking bot that is able to executes trades even from low account balance

## Medula EA

- **[MEDULA_FORMULAS.md](MEDULA_FORMULAS.md)** — formula specification for all 21 engines.
- **[MQL5/Experts/Medula/](MQL5/Experts/Medula/)** — modular MQL5 implementation (`Medula.mq5` + `.mqh` engine files) with install and testing instructions.
- **[MQL5/Experts/Medula_Single.mq5](MQL5/Experts/Medula_Single.mq5)** — **v2.70, the maintained build.** Single file, zero dependencies (no includes at all): copy into `MQL5/Experts/` and compile.
- **[MQL5/Experts/Medula_PriceAction.mq5](MQL5/Experts/Medula_PriceAction.mq5)** — **v3.00, pure price action.** No indicators at all: supply/demand zones, swing structure and candle anatomy only. Single file, zero includes.
- **[MQL5/Experts/Medula_SMC.mq5](MQL5/Experts/Medula_SMC.mq5)** — **v5.12, SMC / ICT scalper.** M5 execution, zero indicators, POI-anchored stops, full basket manager, and confluence that **sizes** the trade instead of vetoing it. This is the current build.
- **[tests/verify_medula.py](tests/verify_medula.py)** — 290-check regression suite covering every engine formula, including an anti-stationary guarantee. Run with `python3 tests/verify_medula.py`.

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


## v3.00 — the price-action build

`Medula_PriceAction.mq5` is a separate EA that discards indicators entirely. Verified by the
test suite: **zero** `iRSI` / `iMACD` / `iADX` / `iBands` / `iMA` / `iATR` handles and zero
`CopyBuffer` calls in executable code. The only market data it reads is `CopyHigh`,
`CopyLow`, `CopyOpen`, `CopyClose` and `CopyTickVolume`.

| Engine | Derived from |
|---|---|
| §A Structure | Fractal swing highs/lows, break of structure, change of character |
| §B Supply & demand | Base candles + impulse departure; tracks freshness, tests, strength |
| §C Trend | Higher-high/higher-low sequence — no moving average |
| §D Momentum | Body dominance, directional runs, displacement |
| §E Volatility | True range computed directly (a distance unit only, never a signal) |
| §F Liquidity | Equal highs/lows where stops cluster |
| §G Order flow | Close location within each bar's range, tick-volume weighted |
| §H Multi-timeframe | Higher-timeframe swing structure |

**Entries are setups, not score crossings:**

1. **Zone rejection** — price returns to a fresh zone, prints a rejection wick, and closes
   back out on the correct side, with structure agreeing.
2. **BOS retest** — structure breaks, price returns to the broken level and holds it.
3. **Break with momentum** — a structure break backed by decisive candle bodies.

**Stops are placed by price action**, beyond the zone or swing that would invalidate the
idea, with ATR only as a buffer. Targets are a configured R multiple of that real risk.

Risk carries the v2.70 corrections: R is measured against the risk actually taken, and
`InpMaxRiskPctHard` caps any single trade regardless of the min-lot override.


## v4.00 — Smart Money Concepts / ICT

`Medula_SMC.mq5` trades a single ICT model on **M5**. Verified by the suite: zero indicator
handles and zero `CopyBuffer` calls in executable code — the only market data read is
`CopyHigh`, `CopyLow`, `CopyOpen`, `CopyClose`, `CopyTime`, `CopyTickVolume`.

| Engine | Concept |
|---|---|
| §1 Market structure | Swing points, BOS, CHoCH, and market structure shift (MSS) |
| §2 Order blocks | Last opposing candle before displacement; mitigation and breaker flip |
| §3 Fair value gaps | Three-candle imbalance, **graded**: breakaway / measuring / exhaustion, partial fill, consequent encroachment, inversion |
| §4 Liquidity | EQH/EQL pools, previous-day high/low, sweep (stop-hunt) detection |
| §5 Premium / discount | Dealing range, equilibrium, 62–79% OTE window |
| §6 Killzones | London, New York, London Close (GMT) |
| §7 HTF bias | M15 / H1 / H4 swing structure, weighted |
| §8 Displacement | Impulsive legs that leave imbalance behind |
| §9 Basket manager | Average entry, basket R, targets, break-even, partials, scaling |

**The entry model** — every leg required, checked in order, and the first missing one is
named in the journal:

1. Higher-timeframe bias agrees
2. Liquidity is swept — a prior high/low taken and rejected
3. Market structure shifts against the sweep (CHoCH / BOS)
4. That shift was displacement, leaving an FVG or order block
5. Price returns into that FVG or order block
6. Entry sits in discount (longs) or premium (shorts)
7. Inside a killzone, and reward:risk clears the minimum

Stops go beyond the swept extreme. Targets are the opposing liquidity pool, falling back to
an R multiple when none is in range.

**The basket manager** treats every position on the symbol as one exposure: a single average
entry, one R unit taken from the first fill and shared by all legs, basket-level target and
stop in R, break-even set on the *basket average*, partial closes, decaying scale-ins that
can never martingale, and a full close when higher-timeframe bias or structure flips.


### v4.10 — the scalper profile

The first SMC run took no trades and the self-test named the cause: stops were anchored
**beyond the swept extreme**, which on XAUUSD M5 is 2–5× the average range ($3–8), while a
$10 account carries $2.00. That is a swing trader's stop, and it is also why the EA held no
scalper character at all.

**Stop placement decides which trader the EA is:**

| Anchor | Distance | Meaning |
|---|---|---|
| Beyond the swept extreme | 2–5× avg range | The idea is wrong only if the whole liquidity raid fails |
| **Beyond the POI** (v4.10 default) | **0.5–1.5× avg range** | The idea is wrong the moment the FVG/order block fails |

The POI anchor is 2–6× tighter, which makes it both scalper-appropriate and affordable on a
small account. Targets follow the same logic: a scalper banks at the **nearer** of the R
target and the next liquidity pool, a swing trader runs to the pool.

**The model is now tiered** rather than seven mandatory conditions at once:

- **Core** (always required): price at an unmitigated FVG or order block, with structure
  supporting the direction.
- **Optional filters** (each independently switchable): liquidity sweep, killzone,
  premium/discount, OTE, higher-timeframe agreement threshold.

Three entry models are recognised and named in the journal, so the log shows which one fired:
`sweep + MSS + FVG` (full ICT reversal), `MSS + order block` (shift into a POI), and
`FVG continuation` (with-structure scalp — the one that actually occurs often on M5).

A scalp that has not resolved within `InpMaxHoldBars` and is below +0.3R is closed to release
the risk, and the basket now works on scalper timings: break-even at 0.5R, partial at 0.6R,
basket target 1.6R.


### v5.00 — filters size the trade, they never block it

v4.10 still took zero trades. The journal named one reason and repeated it all session:

```
no entry — higher timeframes undecided (bias -0.22, need 0.34)
```

Two separate faults, and the second is the one that mattered.

**1. Independent gates multiply.** v4.00 required seven conditions simultaneously. Even if
each is generously true 60% of the time, all seven align on `0.6⁷ ≈ 2.8%` of bars — and they
are not independent, so in practice it is worse. An EA built that way watches the market; it
does not trade it. **Fix:** exactly **one** hard condition survives —

> price is trading inside a live, unmitigated fair value gap or order block pointing in the
> trade's direction.

That *is* the ICT entry; without it there is nothing to take. Higher-timeframe bias, liquidity
sweep, structure shift, premium/discount, OTE and killzone are now **scored** into a quality
figure between 0 and 1 which sets the **size**:

```
risk = planned_risk × ( MinSizeFactor + (1 − MinSizeFactor) × quality )
```

A bare POI with no confluence trades at 40% of planned risk. A full sweep + MSS + discount +
OTE + killzone setup trades at 100%. Hostile higher-timeframe bias scores zero and shrinks the
trade — it can no longer cancel it. Reward:risk became a **target rule**: a liquidity pool is
used as the target only while it still pays `InpTargetMinRR`, otherwise the target is stretched
to that minimum. It never refuses a setup.

The suite proves this rather than asserting it: each filter is removed one at a time and must
(a) fail to produce a refusal and (b) still reduce the size committed. A filter that cannot
change the size is decoration; a filter that can refuse is a v4.10 relapse.

**2. MetaTester was running the old parameters.** The v4.10 log dumped `48324 bytes of input
parameters loaded` listing `InpHtfMinAgreement=0.34`, `InpRequireSweep=true`,
`InpUseKillzones=true`, `InpMinRR=2.0`, `InpFitStopToAccount=false` — all **v4.00** values. A
saved `.set` had been applied over the new build, so every default relaxed in v4.10 was
silently discarded. Only the newly *named* inputs (the Scalp Mode group) took their defaults,
because a `.set` file cannot bind to a name that did not exist when it was written.

**That is the fix.** v5.00 does not merely change those defaults again — it **deletes the
blocking inputs outright**:

| Removed in v5.00 | Replaced by | Why the rename matters |
|---|---|---|
| `InpUseHtfBias`, `InpHtfMinAgreement` | `InpWeightHtf`, `InpHtfFullAt` | a stale `.set` has nothing to bind to |
| `InpRequireSweep` | `InpWeightSweep` | " |
| `InpUsePremiumDiscount`, `InpRequireOte` | `InpWeightPD`, `InpWeightOte` | " |
| `InpUseKillzones` | `InpWeightKillzone` | " |
| `InpMinRR` | `InpTargetMinRR` (target rule, not a gate) | " |
| `InpEntryCooldownSec` | `InpEntrySpacingSec` | " |
| `InpFitStopToAccount` | `InpAutoFitStop` (default `true`) | " |

An old parameter set can now only carry forward settings that cannot stand the EA down.

The panel and journal report the quality, the tags that scored (`HTF STRUCT SWEEP DISC KZ`)
and the resulting size multiplier on every fill, and when the EA is flat the reason is a
distance, not a filter name: *"price is not in a POI yet — nearest is 1.84 x avg range away"*.


### v5.10 — what a gap is worth

v5.00 traded. The journal then showed *why it was still standing aside*, and the count gave
it away: **`13 blocks, 3 gaps live`**. Order blocks outnumbered fair value gaps four to one,
so the EA kept waiting on blocks whose stops were 2–6× too wide for the account, and the
`InpAutoFitStop` clamp then dragged the stop back to whatever the equity could carry —
decoupling it from the structure it was supposed to protect. The first trade lasted 26
seconds.

The gap inventory was starved by the gap model itself. v5.00 knew two states, alive and
filled, and both threw work away:

| v5.00 behaviour | What was actually happening | v5.10 |
|---|---|---|
| Price closes through a gap → **delete it** | A gap traded fully through **inverts** — those prices now hold from the other side | `inverted`, the zone flips direction and keeps trading (IFVG) |
| Gap 50% consumed → struck off as **filled** | Price reaching the consequent encroachment **is** the entry | `filledPct` 0..1 discounts the grade instead of deleting the zone |
| Every gap is the same object | A gap that starts a move and a gap that ends one are opposite trades | `kind`: breakaway / measuring / exhaustion |
| First POI the loop reached wins | A sprawling breaker block beat a two-candle gap | Best **quality per unit of risk** wins |

**The three kinds:**

| Kind | Formed | Behaviour | Used as |
|---|---|---|---|
| **Breakaway (BAG)** | The candle that breaks structure at the start of an expansion — short run in, large body, close takes the last swing | Price defends it | The highest-graded entry on the chart |
| **Measuring** | Mid-leg imbalance | Ordinary continuation | A normal entry |
| **Exhaustion** | Into a pool once the run is already extended | Gets filled | A **target**, graded near zero as an entry |

Grade (0..1) combines gap size, the displacement behind it, kind, freshness, and how much has
already been given back. It feeds three decisions:

1. **Which POI to enter** — `PoiScore = grade / (0.60 + stop distance in avg ranges)`. A tight
   breakaway gap now outranks a wide breaker block, which is also the honest fix for the
   over-tight stop clamp: pick a POI whose *natural* stop the account can carry.
2. **How much size** — `InpWeightPoiGrade` puts the POI's own quality into the confluence
   score, tagged `A+POI` in the journal.
3. **Where the target goes** — `FvgDraw()` finds the nearest unrebalanced gap ahead of price
   and competes it against the liquidity pool. Whichever draw is nearer and still pays
   `InpTargetMinRR` takes the target.

New inputs: `InpUseInversionFvg`, `InpBagDisplaceMult`, `InpBagMaxRunIn`, `InpExhaustRunMult`,
`InpExhaustLookback`, `InpFvgGradeFloor`, `InpFvgTargetPull`, `InpBestPoi`,
`InpWeightPoiGrade`.

**Two fixes to the surrounding machinery**, both of which destroyed the graded setups that
did fire:

- `InpBreakerMinLosses` (default 3). A 5% daily loss limit on a $10 account is $0.50, while a
  single minimum-lot stop-out risks $0.28–1.65 — so one loss latched the breaker and ended
  the day. The daily limit now also requires a *run* of losers. Max drawdown from peak is
  unchanged and still latches on its own.
- `stop tightened to fit account` printed on every tick for hours. It is throttled to
  `InpDiagThrottleSec`, or to a real change in the distance.

The panel adds a gap census (`gaps  N breakaway   N inverted   N fresh`) and the POI grade of
the live setup; gap boxes are coloured by kind, with inversions drawn in their new direction.


### v5.11 — trade the candle after the gap

Everything up to v5.10 still waited for price to come **back** into the gap. That makes the EA
a retracement trader and nothing else — and after genuine displacement most gaps are never
retraced, which is the entire point of displacement. Every one of those legs was a setup the
EA correctly identified, graded, drew on the chart, and then watched go past.

**§3b, the fresh gap.** A gap younger than `InpFreshGapMaxAge` (3 bars) is now tradeable from
the **continuation side**, on the candle that follows it, with no retrace required. This is
not limited to breakaway gaps — an ordinary fair value gap qualifies on the same terms. The
imbalance itself is the signal.

It stays a trade rather than a chase because of two limits:

- **The stop is still anchored beyond the far edge of the gap**, exactly as a retrace entry
  would be. It is not a fixed distance, and it is not the whole displacement candle.
- **The chase is bounded.** Once price has run `InpFreshGapMaxRun` (1.25 × avg range) past the
  gap, the stop is too wide to be worth taking, and the EA reverts to waiting for the retrace.
  `PoiScore` already prefers the nearer of two equal gaps, so the EA takes these early or not
  at all.

Exhaustion gaps are never chased (`InpFreshGapSkipExh`) — they are the ones that get filled.

Fresh entries are tagged **`FRESH`** in the journal and named `fresh FVG continuation` or
`fresh breakaway gap continuation`, so the log separates them from retrace fills. The panel
and the flat-reason line both carry a fresh-gap count.

New inputs: `InpTradeFreshGaps`, `InpFreshGapMaxAge`, `InpFreshGapMaxRun`,
`InpFreshGapSkipExh`, `InpFreshGapMinGrade`. Setting `InpTradeFreshGaps=false` restores pure
v5.10 retracement behaviour.


### v5.12 — the small ones count

Screenshots of missed setups showed the EA standing aside on plainly tradeable imbalances, and
**none of the reasons were the ones it printed**. Four defects, all of them admission gates
that had no business existing:

| # | Defect | Effect |
|---|---|---|
| 1 | `InpFvgMinPct` required a gap to be **¼ of the average range before it was recorded at all** | Every small imbalance was deleted at birth. Nothing downstream could grade it, size it or trade it — the grading engine never saw them |
| 2 | Both POI books filled **oldest-first**, then hit a fixed cap | A busy session spent every slot on 200-bar-old zones and dropped the fresh gaps — the only ones §3b can trade |
| 3 | `PoiScore` ranked a 6-point gap on a **6-point stop**, while entry floors every stop at 0.25 × avg range | Micro-gaps outranked everything on a distance they never actually got |
| 4 | The 20% risk ceiling **rejected its own arithmetic** | `InpAutoFitStop` sizes the stop so min lot lands *exactly* on the ceiling; a strict `>` then failed on floating point — `risk 1.65 = 20% of equity over the 20% ceiling`. Trades the EA had just made affordable were refused for rounding |

**The only honest floor on a gap is the spread.** A gap narrower than the cost of crossing it
cannot be scalped, no matter how real it is. Above that line, size is a matter of *grade*, not
of admission — which is the whole point of the v5.10 grading engine. `InpFvgMinPct` drops to
0.06 and `InpFvgMinSpreads` (1.0) becomes the real limit; the self-test prints the resulting
minimum in price terms so it is visible rather than invisible.

**Volume imbalances** — bodies gapped, wicks touching — are now tracked as a fourth gap kind
(`InpUseVolumeImb`). They are small and they are weak, and they grade accordingly at 0.40
against a measuring gap's 0.60. But a scalper is supposed to see them.

Both books now fill **newest-first**, `InpMaxFVGs` doubles to 40, and `InpEntrySpacingSec`
drops to 15.
