//+------------------------------------------------------------------+
//|                                                   Medula_SMC.mq5 |
//|  Medula v5.24 — Price action engine.  H1 execution by default.   |
//|  Single file, zero includes, ZERO INDICATORS.                    |
//|                                                                  |
//|  Every decision comes from raw OHLC. There is no iRSI / iMACD /  |
//|  iADX / iBands / iMA / iATR handle and no CopyBuffer call in     |
//|  this file. The only market data read is CopyHigh, CopyLow,      |
//|  CopyOpen, CopyClose, CopyTime and CopyTickVolume.               |
//|                                                                  |
//|  ENGINES                                                         |
//|    §1  Market structure   swings, BOS, CHoCH, MSS                |
//|    §2  Order blocks       last opposing candle before            |
//|                           displacement that breaks structure     |
//|    §3  Fair value gaps    three-candle imbalance, GRADED:        |
//|                           breakaway / measuring / exhaustion,    |
//|                           partial fill, consequent encroachment, |
//|                           inversion, and gaps as draws on price  |
//|    §4  Liquidity          EQH/EQL pools, session and prior-day   |
//|                           highs and lows, sweep detection        |
//|    §5  Premium / discount dealing range, equilibrium, OTE        |
//|    §6  Killzones          London, New York, London close (GMT)   |
//|    §7  HTF bias           structure on M15 / H1 / H4             |
//|    §8  Displacement       impulsive legs that leave imbalance    |
//|    §9  Basket manager     average entry, basket targets, scaling |
//|    §10 Confluence score   sizes the trade instead of vetoing it  |
//|                                                                  |
//|  THE ENTRY MODEL — SKILL, NOT CERTAINTY                          |
//|                                                                  |
//|  Up to v4.10 the model was seven conditions that all had to be   |
//|  true at once. Any single one of them could stand the EA down    |
//|  for a whole session, and one did: a higher-timeframe bias of    |
//|  -0.22 against a required 0.34 refused every bar of the day.     |
//|  Seven independent gates each cleared ~50-70% of the time         |
//|  multiply out to a few percent of bars — that is an EA that      |
//|  watches, not one that trades.                                   |
//|                                                                  |
//|  v5.00 keeps exactly ONE hard condition:                         |
//|                                                                  |
//|      price is trading inside a live, unmitigated fair value gap  |
//|      or order block pointing in the trade's direction —          |
//|      OR a gap in that direction has just printed (§3b).          |
//|                                                                  |
//|  That is the ICT entry itself — without it there is no trade to  |
//|  take. Everything else (HTF bias, liquidity sweep, structure     |
//|  shift, premium/discount, OTE, killzone) is SCORED into a        |
//|  quality figure 0..1 which sets the SIZE:                        |
//|                                                                  |
//|      risk = planned x (MinSizeFactor + (1-MinSizeFactor)*quality)|
//|                                                                  |
//|  A bare POI still trades, at 40% of planned risk. A full sweep + |
//|  MSS + discount + killzone setup trades at 100%. Reward:risk is  |
//|  a target RULE — the target is stretched to the minimum R, never |
//|  used to refuse the setup.                                       |
//|                                                                  |
//|  Stop goes just beyond the POI (scalp) or beyond the swept       |
//|  extreme (swing). Target is the nearer of the R target, the      |
//|  next liquidity pool and the next unrebalanced gap.              |
//|                                                                  |
//|  v5.10 — WHAT A GAP IS WORTH                                     |
//|                                                                  |
//|  v5.00 treated every fair value gap as the same object: it was   |
//|  alive or it was rubbish. Two consequences followed, and both    |
//|  showed up in the journal.                                       |
//|                                                                  |
//|  First, a gap price had closed through was deleted. But a gap    |
//|  traded fully through does not stop existing — it INVERTS. Those |
//|  same prices now hold from the other side, and that is half of   |
//|  the model. Deleting them left three gaps live against fifteen   |
//|  order blocks, so the EA sat waiting on blocks whose stops were  |
//|  six times too wide for the account.                             |
//|                                                                  |
//|  Second, a gap 50% consumed was struck off as "filled" — yet     |
//|  price trading to the consequent encroachment IS the entry. The  |
//|  EA was throwing away the setup at the exact moment it armed.    |
//|                                                                  |
//|  v5.10 grades instead of deleting. Every gap carries its size,   |
//|  the displacement that made it, how deeply it has been consumed, |
//|  and WHICH KIND of gap it is:                                    |
//|                                                                  |
//|    BREAKAWAY (BAG)  the gap left by the candle that broke        |
//|                     structure at the start of an expansion.      |
//|                     It tends to hold. Trade with it.             |
//|    MEASURING        mid-leg imbalance. Ordinary, tradeable.      |
//|    EXHAUSTION       printed into a pool after the run is already |
//|                     extended. It tends to get filled — so it is  |
//|                     a TARGET, not an entry.                      |
//|                                                                  |
//|  Grade feeds three decisions: which POI to enter (best quality   |
//|  per unit of risk, so a two-tick breakaway gap beats a sprawling |
//|  breaker block), how much size the setup earns, and where the    |
//|  target goes — the nearest unfilled gap ahead of price is a draw |
//|  on liquidity and is used as a take-profit.                      |
//|                                                                  |
//|  v5.11 — §3b TRADE THE CANDLE AFTER THE GAP                      |
//|                                                                  |
//|  Everything above still waits for price to come BACK to the gap. |
//|  That makes the EA a retracement trader only, and after genuine  |
//|  displacement most gaps are never retraced — which is the whole  |
//|  point of displacement. Every one of those legs was a chance the |
//|  EA watched go past.                                             |
//|                                                                  |
//|  So a gap younger than InpFreshGapMaxAge is now tradeable from   |
//|  the continuation side, on the candle that follows it, with no   |
//|  retrace required. This applies to ORDINARY fair value gaps as   |
//|  much as to breakaway gaps — the imbalance is the signal.        |
//|                                                                  |
//|  It stays a trade rather than a chase because the stop is still  |
//|  placed beyond the far edge of the gap, and because the chase is |
//|  bounded: once price has run InpFreshGapMaxRun past the gap the  |
//|  stop is too wide to be worth taking and the EA goes back to     |
//|  waiting for the retrace. Exhaustion gaps are never chased.      |
//|                                                                  |
//|  These fills are tagged FRESH in the journal and named           |
//|  "fresh FVG continuation" / "fresh breakaway gap continuation".  |
//|                                                                  |
//|  v5.12 — THE SMALL ONES COUNT                                    |
//|                                                                  |
//|  The EA was still standing aside on obvious setups, and none of  |
//|  the reasons were the ones it printed. Four defects, all of them |
//|  admission gates that had no business existing:                  |
//|                                                                  |
//|  1. InpFvgMinPct required a gap to be a quarter of the average   |
//|     range before it was even RECORDED. Every small imbalance on  |
//|     the chart was deleted at birth, so nothing downstream could  |
//|     grade it, size it or trade it. The only honest floor is the  |
//|     spread: a gap narrower than the cost of crossing it cannot   |
//|     be scalped. Above that line, size is a matter of grade.      |
//|                                                                  |
//|  2. Both POI books were filled OLDEST FIRST and then capped, so  |
//|     a busy session spent every slot on 200-bar-old zones and     |
//|     dropped the fresh gaps — the only ones §3b can trade. They   |
//|     now fill newest first.                                       |
//|                                                                  |
//|  3. PoiScore ranked a 6-point gap on a 6-point stop, while entry |
//|     floors every stop at 0.25 x avg range. Micro-gaps outranked  |
//|     everything on a distance they never actually got.            |
//|                                                                  |
//|  4. The 20% risk ceiling rejected its own arithmetic. AutoFitStop|
//|     sizes the stop so min lot lands EXACTLY on the ceiling, and  |
//|     a strict > then failed on floating point: "risk 1.65 = 20%   |
//|     of equity over the 20% ceiling". Trades the EA had just made |
//|     affordable were refused for rounding.                        |
//|                                                                  |
//|  Volume imbalances — bodies gapped, wicks touching — are now      |
//|  tracked too. They are small and they are weak, and they grade   |
//|  accordingly, but a scalper is supposed to see them.             |
//+------------------------------------------------------------------+
#property copyright "Medula Project"
#property version   "5.24"

//============================== INPUTS ==============================

input group "General"
input long   InpMagic           = 770040;  // Magic number
input int    InpDeviationPts    = 30;      // Max price deviation (points)
input bool   InpVerboseLog      = true;    // Print to Experts log
input bool   InpCsvLog          = true;    // Write MedulaSMC.csv
input bool   InpShowPanel       = true;    // Live panel on chart
input bool   InpDrawObjects     = true;    // Draw zones on the chart
input bool   InpDiagnostics     = true;    // Log why an entry was skipped
input int    InpDiagThrottleSec = 900;     // Seconds between repeats of a reason
input bool   InpSelfTest        = true;    // Readiness report on attach

//--- EXECUTION TIMEFRAME.
//    Everything downstream is expressed in BARS and in average-range units, so
//    the engines travel between timeframes unchanged. What does not travel is
//    the cost of trading: on M5 gold the average range is ~1.0-1.5 against a
//    ~0.30 spread, so the spread is a quarter of a minimum stop. On H1 the
//    average range is five to ten times larger and the same spread becomes a
//    rounding error. That single ratio is the strongest argument for H1.
input group "Execution Timeframe"
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H1;  // Timeframe the EA trades

input group "Market Structure (§1)"
input int    InpBars            = 500;     // Bars of history analysed
input int    InpSwingK          = 2;       // Fractal wing size
input double InpBosBufferPct    = 0.05;    // Break must clear by this share of avg range
input int    InpStructureLookback = 60;    // Bars searched for the structure shift

input group "Order Blocks (§2)"
input bool   InpUseOrderBlocks  = true;    // Trade order-block returns
input int    InpMaxOrderBlocks  = 20;      // Order blocks tracked per side
input int    InpObMaxAgeBars    = 180;     // Forget order blocks older than this
input double InpObMitigatedPct  = 50.0;    // Mitigated once price fills this % of it
input bool   InpUseBreakers     = true;    // Trade breaker blocks (failed OB that flips)

input group "Fair Value Gaps (§3)"
input bool   InpUseFVG          = true;    // Trade FVG returns
input int    InpMaxFVGs         = 40;      // FVGs tracked
input int    InpFvgMaxAgeBars   = 120;     // Forget FVGs older than this
input double InpFvgMinPct       = 0.02;    // Gap must be >= this share of avg range
input bool   InpUseVolumeImb    = true;    // Also track 2-candle body gaps (volume imbalance)
input double InpFvgFillPct      = 50.0;    // Reported as consumed past this % (CE)
input bool   InpUseInversionFvg = true;    // A violated gap inverts and keeps trading (IFVG)
input double InpBagDisplaceMult = 1.80;    // Breakaway gap: its candle >= this x avg range
input double InpBagMaxRunIn     = 1.50;    // Breakaway only if the run into it is under this
input double InpBagRangeMax     = 2.00;    // ...and the bars before it were a range this tight
input double InpExhaustRunMult  = 3.00;    // Exhaustion once the run already exceeds this
input int    InpExhaustLookback = 12;      // Bars measured for the run into the gap
input double InpFvgGradeFloor   = 0.00;    // Drop gaps graded below this (0 = keep all)
input bool   InpFvgTargetPull   = true;    // Unfilled gaps ahead of price are targets
input bool   InpBestPoi         = true;    // Enter the best-graded POI, not the first found

//--- §3b FRESH GAP CONTINUATION.  Waiting for price to trade back INTO a gap
//    misses every gap that is never retraced, and after real displacement most
//    are not. The imbalance itself is the signal: a gap that has just printed
//    is tradeable on the candle that follows it, from the continuation side,
//    with the stop still beyond the gap. This applies to ordinary fair value
//    gaps as much as to breakaway gaps.
//--- §3c PRICE ACTION — THE CANDLE ITSELF.
//    A fair value gap needs three candles to line up before it exists. Price
//    action does not wait for that. A candle with a real body that travels a
//    real distance IS the displacement, whether or not the two candles either
//    side happen to leave a measurable gap between them — and every small gap
//    that falls under the imbalance test still shows up here, as the candle
//    that made it. This is the reading a person does off the chart: the
//    movement of the candlesticks, not a zone drawn around them.
input group "Price Action Candles (§3c)"
input bool   InpTradePaCandles  = false;   // Trade displacement candles directly (no gap needed)
input double InpPaBodyPct       = 0.55;    // Body must be this share of the candle range
input double InpPaRangeMult     = 0.90;    // Candle range >= this x average range
input int    InpPaMaxAge        = 6;       // A momentum candle stays tradeable this many bars
input double InpPaMaxRun        = 2.50;    // Stop chasing once price has run this far past it

//--- §3d THE NEXT CANDLE — UNCONDITIONAL.
//    A fair value gap is complete the moment its third candle closes. By the
//    principle, the trade is the candle AFTER that — not a retracement into
//    the gap, not a continuation once price has travelled a qualifying
//    distance, and not subject to any test at all beyond the gap existing.
//    This path has no buffer test, no run limit and no grade test. If a gap
//    printed on the last closed bar, it is traded on this one.
//--- §3e THE SECOND CANDLESTICK.
//    "A fair value gap simply tells you that you should have entered on the
//    second candlestick, when it comes higher than the previous one."
//    That is the trigger, and it fires a full candle BEFORE any gap can be
//    confirmed — a three-candle gap needs its third candle to close, by which
//    time the leg has already run. This path enters the moment the current
//    candle takes the previous candle's high (or low), with the stop under
//    the candle that was taken. A staircase of modest candles each making a
//    higher high has no displacement candle and often no measurable gap, and
//    every path before this one was blind to it.
//--- §3g THE CONFIRMED RETRACEMENT MODEL — the disciplined FVG method.
//
//    "Do not buy immediately when the gap forms. Wait for price to retrace
//     into the FVG. Look for bullish confirmation. Enter AFTER confirmation."
//
//    That sequence contradicts §3b, §3d and §3e, all of which enter the
//    moment an imbalance appears. When InpConfirmModel is on those paths are
//    switched off: the EA runs the disciplined model instead of the
//    take-everything mandate, and the avoid-list below becomes a real veto
//    again — because "the broader market structure contradicts the setup" is
//    a reason not to trade, not a reason to trade smaller.
input group "Confirmed FVG Model (§3g)"
input bool   InpConfirmModel    = true;    // Retrace + confirmation model (disables §3b/d/e)
input bool   InpRequireRetrace  = true;    // Price must trade back INTO the gap
input bool   InpRequireConfirm  = true;    // ...and print a confirmation candle
input double InpImpulseMinPct   = 0.35;    // Impulse must leave a gap this big (x avg range)
input double InpConfirmMinAnat  = 0.45;    // Anatomy score that counts as confirmation
input bool   InpAvoidRanging    = true;    // Skip when structure has no direction
input bool   InpAvoidStructAgainst = true; // Skip when broader structure contradicts
input bool   InpAvoidMomentumAgainst = true; // Skip when the retrace has strong opposing momentum
input double InpMomentumAgainstX= 1.20;    // "Strong" opposing candle (x avg range)
input bool   InpStopAtSwing     = true;    // Stop beyond the swing, not just the gap edge
input double InpMinRoomR        = 1.50;    // Require this much room to the next S/R

input group "Two-Candle Trigger (§3e)"
input bool   InpTwoCandleEntry  = false;   // Enter when this candle takes the previous one's high/low
input double InpTwoCandleMinAnat= 0.00;    // Minimum anatomy score to act (0 = any)
input bool   InpTwoCandleNeedSeq= false;   // Require an existing higher-high sequence
input double InpGapSupportBonus = 0.30;    // Grade bonus when a live gap/BAG backs the trigger

//--- §3f CANDLE ANATOMY.
//    What the candles themselves say, read the way a person reads them:
//    body size, wick size, engulfing, pin bars, closes near the extreme,
//    inside bars and outside bars. Used to grade every trigger above and
//    scored into the size the trade earns.
//--- SPEED AND THE SMALL WIN.
//
//    "If it can open a trade for a short breakaway gap or FVG that generates
//     even little profits, that is better than coordinated trades with losses."
//
//    Taken literally — small fixed target against a full stop — that is the
//    scalper's trap: banking 0.5R against a 1R stop needs a 67% win rate just
//    to break even, and the spread is already a quarter of the risk. So the
//    small win is taken as a PARTIAL, the rest is moved to break-even
//    immediately and trailed. Most trades then end at a small profit or at
//    zero, losses are cut early, and the runner carries the expectancy. That
//    is the version of this that survives its own arithmetic.
input group "Speed and Quick Profit"
input bool   InpFastConfirm     = true;    // Confirm from the LIVE candle, don't wait for close
input double InpFastMinRange    = 0.35;    // Live candle must have developed this x avg range
input bool   InpQuickProfit     = true;    // Bank a partial early, then run the rest free
input double InpQuickPartialR   = 0.50;    // Take the partial at this R
input double InpQuickPartialPct = 60.0;    // Percent of the position banked there
input bool   InpBeAfterPartial  = true;    // Move to break-even the moment the partial is banked

input group "Candle Anatomy (§3f)"
input double InpAnatStrongClose = 0.70;    // Close this far into the range counts as strong
input double InpAnatPinWick     = 2.00;    // Pin bar: wick this many times the body
input double InpAnatPinShare    = 0.55;    // ...and this share of the whole range
input double InpWeightAnatomy   = 0.16;    // Weight: candle anatomy agrees with the trade

input group "Next-Candle Execution (§3d)"
input bool   InpNextCandleEntry = false;   // Trade the candle right after a gap completes
input int    InpNextCandleBars  = 2;       // "Just printed" means a gap this many bars old
input double InpNextCandleBoost = 1.00;    // Recency multiplier on the newest gap's own worth
input bool   InpLogGaps         = true;    // Log every fresh gap found, each new bar

input group "Fresh Gap Continuation (§3b)"
input bool   InpTradeFreshGaps  = false;   // Trade the candle after a gap prints (no retrace needed)
input int    InpFreshGapMaxAge  = 5;       // A gap counts as fresh for this many bars
input double InpFreshGapMaxRun  = 2.50;    // Stop chasing once price has run this far past it
input bool   InpFreshGapSkipExh = true;    // Exhaustion gaps are targets, never entries
input double InpFreshGapMinGrade= 0.00;    // Minimum gap grade to chase (0 = any gap)

input group "Liquidity (§4)"
input double InpEqualTolPct     = 0.12;    // Equal-level tolerance (share of avg range)
input int    InpLiqLookback     = 200;     // Bars scanned for liquidity pools
input int    InpSweepMaxAgeBars = 30;      // A sweep counts as fresh for this many bars
input bool   InpUsePrevDayLevels= true;    // Include previous day high/low as liquidity

input group "Premium / Discount (§5)"
input int    InpDealingRangeBars   = 120;  // Bars forming the dealing range
input double InpOteLow              = 0.62; // OTE zone lower retracement
input double InpOteHigh             = 0.79; // OTE zone upper retracement

input group "Killzones (§6, GMT)"
input int    InpLondonStart     = 7;       // London open killzone start hour
input int    InpLondonEnd       = 10;      // London open killzone end hour
input int    InpNyStart         = 12;      // New York open killzone start hour
input int    InpNyEnd           = 15;      // New York open killzone end hour
input int    InpLnCloseStart    = 15;      // London close killzone start hour
input int    InpLnCloseEnd      = 17;      // London close killzone end hour

//--- The bias frames must sit ABOVE the execution frame. With H1 trading, H4,
//    D1 and W1 are the context; M15 is noise below it and was dropped.
input group "Higher Timeframe Bias (§7)"
input bool   InpHtfH4           = true;    // Include H4 structure
input bool   InpHtfD1           = true;    // Include D1 structure
input bool   InpHtfW1           = false;   // Include W1 structure

input group "Displacement (§8)"
input double InpDisplacementMult = 1.5;    // Leg range >= this x average range
input double InpDisplacementBody = 0.50;   // Body must be this share of the leg

//--- §10 CONFLUENCE SCORING.  Nothing in this group can refuse a trade.
//    Every classical ICT filter is a WEIGHT: it raises or lowers the size
//    the EA commits, it never vetoes the setup.  The single hard condition
//    is the setup itself — price trading inside a live, unmitigated FVG or
//    order block.  A skilled trader takes the trade small when confluence
//    is thin; it does not stand aside all day waiting for certainty.
input group "Confluence Scoring (§10) — filters SIZE the trade, never block it"
input double InpWeightHtf       = 0.28;    // Weight: higher-timeframe agreement
input double InpWeightStructure = 0.24;    // Weight: structure / MSS support
input double InpWeightSweep     = 0.18;    // Weight: fresh liquidity sweep
input double InpWeightPD        = 0.12;    // Weight: discount (buy) / premium (sell)
input double InpWeightOte       = 0.08;    // Weight: entry inside the OTE window
input double InpWeightKillzone  = 0.10;    // Weight: inside an ICT killzone
input double InpWeightPoiGrade  = 0.20;    // Weight: grade of the POI itself (BAG > FVG > OB)
input double InpHtfFullAt       = 0.35;    // HTF agreement that scores full marks
input double InpMinSizeFactor   = 0.40;    // Size at zero confluence (x planned risk)
input double InpCounterTrendFac = 0.50;    // Size multiplier when the trade fights structure
input double InpQualityFloor    = 0.00;    // Refuse below this quality (0 = never refuse)
input double InpFlipMinBias     = 0.35;    // HTF bias that counts as a flip against a basket

input group "Scalp Mode"
input bool   InpScalpMode       = true;    // Scalper profile: POI stops, quick targets
input bool   InpStopBeyondPOI   = true;    // Stop just past the FVG/OB, not past the sweep
input double InpPoiStopBuffer   = 0.30;    // Stop beyond the POI by this x average range
input double InpScalpTargetR    = 2.0;     // Target in R
input int    InpMaxHoldBars     = 18;      // Close the trade after this many bars

//--- TAKE EVERY POI.  The single switch that states the mandate: every live
//    fair value gap, breakaway gap and order block is executed, small or
//    large, high grade or low. Grade decides the SIZE, never the permission.
//    With this on, the ONLY things that can refuse a trade are the four
//    physical rails: the per-trade risk ceiling, the basket cap, free margin
//    and the circuit breaker. No hour of the day, no session, no confidence
//    level and no grade floor can stand the EA down.
input group "Execution Mandate"
input bool   InpTakeEveryPOI    = false;   // Trade every POI; only risk rails may refuse

input group "Entries"
input bool   InpEntryOnFVG      = true;    // Enter on FVG return
input bool   InpEntryOnOB       = true;    // Enter on order-block return
input double InpEntryZoneBuffer = 0.25;    // Zone widened by this share of avg range
input int    InpEntrySpacingSec = 0;       // Min seconds between entries
input int    InpMaxSetupAgeBars = 40;      // Structure shift counts for this many bars

input group "Risk"
input double InpRiskPct         = 1.0;     // Risk per trade (% equity)
input double InpSlBufferPct     = 0.25;    // Stop beyond the sweep by this x avg range
input double InpTargetMinRR     = 1.20;    // Target is never set closer than this R
input double InpMinTargetSpreads= 2.00;    // Target stretched to at least this many spreads

//--- THE COST OF THE ROUND TRIP.
//    On XAUUSD M5 the average range is ~1.0-1.5 and the spread is often
//    0.20-0.45. A stop floored at 0.25 x avg range is therefore roughly the
//    SAME SIZE as the spread — every such trade opens at -0.6R to -1.0R before
//    price has moved at all, and no entry model on earth recovers that.
//    A stop must be a multiple of what it costs to get in and out.
input double InpMinStopSpreads  = 4.00;    // Stop is never closer than this many spreads
input double InpMinStopPct      = 0.25;    // ...nor closer than this x avg range
input double InpTpRMultiple     = 3.0;     // Target when no liquidity pool is in range
input double InpDailyLossPct    = 5.0;     // Daily loss limit (%)
input int    InpBreakerMinLosses= 3;       // Losing trades before the daily limit latches
input double InpMaxDDPct        = 35.0;    // Stand down for the day past this drawdown (%)
input double InpMaxAccountDDPct = 60.0;    // Stop for the whole run past this drawdown (%)
input double InpMaxRiskPctHard  = 20.0;    // ABSOLUTE ceiling on one trade (% equity)
input double InpMarginSafety    = 1.2;     // Free-margin safety factor
input bool   InpAllowMinLot     = true;    // Round up to broker minimum lot
input bool   InpAutoFitStop     = true;    // Tighten stop so min lot fits the ceiling

input group "Basket Manager (§9)"
input bool   InpUseBasket       = true;    // Manage positions as one basket
input int    InpMaxBasketTrades = 6;       // Max positions in a basket
input double InpBasketTargetR   = 2.0;     // Close the basket at this R
input double InpBasketStopR     = 1.5;     // Close the basket at this loss in R
input double InpMaxBasketRiskPct= 4.0;     // Max combined basket risk (% equity)
input bool   InpBasketBreakEven = true;    // Move basket to break-even in profit
input double InpBasketBeAtR     = 0.5;     // Break-even trigger (R)
input bool   InpBasketPartial   = true;    // Partial close at the first target
input double InpBasketPartialR  = 0.5;     // Partial trigger (R)
input double InpBasketPartialPct= 60.0;    // Percent of volume closed
input bool   InpAllowScaleIn    = true;    // Add on a fresh confirmation
input double InpScaleDecay      = 0.6;     // Lot decay per add
input double InpScaleMinSpacing = 0.25;    // Min spacing between adds (x avg range)
input bool   InpScaleOnlyInProfit= true;   // Only add to a basket that is winning
input double InpScaleMinR       = 0.30;    // Basket must be at least this R before adding
input bool   InpCloseOnFlip     = true;    // Close basket when HTF bias flips

//--- WHERE THE MONEY IS.  A scalper that caps every winner at a fixed R and
//    lets every loser run to a fixed stop has a symmetric R distribution and
//    needs to be right more than half the time just to break even. Trailing
//    behind structure turns that distribution right-skewed: losers stay one
//    unit, winners are allowed to become three. That asymmetry — not the
//    entry — is what pays for the spread.
input group "Exit Management"
input bool   InpTrailStructure  = true;    // Trail the stop behind swing structure
input double InpTrailStartR     = 0.70;    // Start trailing at this R
input double InpTrailBufferPct  = 0.35;    // Trail this far beyond the swing (x avg range)
input bool   InpRunWinners      = true;    // Past target, hand the trade to the trail
input bool   InpExitOnInvalid   = true;    // Exit when price closes back through the POI
input double InpInvalidBufferPct= 0.10;    // Invalidation needs this much beyond the POI

//========================= TYPES & HELPERS ==========================

enum ENUM_DEC { DEC_WAIT=0, DEC_BUY, DEC_SELL, DEC_HOLD, DEC_EXIT };

double MClamp(const double x,const double lo,const double hi){ return MathMin(MathMax(x,lo),hi); }
int    MSign(const double x){ if(x>0.0) return 1; if(x<0.0) return -1; return 0; }

//--- THE MANDATE, applied.  Every floor that could refuse a setup on grounds
//    of confidence rather than solvency is forced to zero when InpTakeEveryPOI
//    is on. They stay as inputs so the behaviour can be restored deliberately,
//    but nothing in the model quietly re-introduces a confidence gate.
//--- The narrowest stop worth placing: a multiple of the round-trip cost, and
//    never a meaningless fraction of the range. Used identically by the entry
//    and by the POI scorer, so the EA ranks zones on the stop it will really use.
double MinStopDistance(void)
  {
   double sprd=MathMax(g_view.ask-g_view.bid,0.0);
   return MathMax(InpMinStopPct*g_view.avgRange,InpMinStopSpreads*sprd);
  }

double QualityFloorEff(void)   { return (InpTakeEveryPOI ? 0.0   : InpQualityFloor);    }
double FvgGradeFloorEff(void)  { return (InpTakeEveryPOI ? 0.0   : InpFvgGradeFloor);   }
double FreshGradeFloorEff(void){ return (InpTakeEveryPOI ? 0.0   : InpFreshGapMinGrade);}
//    NOT overridden by the mandate. "Exhaustion gaps get filled, so they are a
//    target and not an entry" is a directional PRINCIPLE, not a confidence
//    threshold. v5.14 folded it in with the grade floors and switched it off,
//    which had the EA buying into the end of every run it should have been
//    selling into. The mandate governs how much certainty is required, never
//    which way a setup points.
bool   SkipExhaustEff(void)    { return InpFreshGapSkipExh; }

//--- an order block: the last opposing candle before displacement (§2)
struct SOB
  {
   double            top,bottom;
   int               dir;          // +1 bullish OB (demand), -1 bearish OB (supply)
   int               shift;
   double            strength;     // displacement size in average-range units
   bool              mitigated;
   bool              breaker;      // flipped after failing
   bool              alive;
  };

//--- where a gap sits inside the leg that made it (§3 / §8)
enum ENUM_GAPKIND
  {
   GAP_MEASURING  =0,   // mid-leg imbalance — ordinary, tradeable
   GAP_BREAKAWAY  =1,   // BAG: the candle that broke structure, start of expansion
   GAP_EXHAUSTION =2,   // printed into a pool on an extended run — a target, not an entry
   GAP_VOLIMB     =3    // volume imbalance: bodies gap, wicks touch. Small but real.
  };

//--- a fair value gap: three-candle imbalance (§3)
struct SFVG
  {
   double            top,bottom;
   double            ce;           // consequent encroachment — the midpoint
   int               dir;          // +1 bullish gap, -1 bearish gap (flips on inversion)
   int               shift;
   double            size;         // height in average-range units
   double            strength;     // displacement of the gap candle, in avg-range units
   ENUM_GAPKIND      kind;
   double            filledPct;    // 0..1, deepest consumption so far
   double            grade;        // 0..1, what this gap is worth trading
   bool              filled;       // consumed past InpFvgFillPct (reporting only)
   bool              inverted;     // closed fully through — now works the other way
   bool              alive;
  };

//--- what the last closed candle says about itself (§3f)
struct SCandle
  {
   int               dir;
   double            rangeX;       // range in average-range units
   double            bodyPct;      // body as a share of range
   double            upperWick,lowerWick;
   double            closePos;     // 0 = closed on the low, 1 = on the high
   bool              strongCloseUp,strongCloseDn;
   bool              pinBull,pinBear;
   bool              engulfBull,engulfBear;
   bool              insideBar,outsideBar;
   bool              marubozu,doji;
   bool              haramiBull,haramiBear;
   bool              starBull,starBear;      // three-bar reversal
   bool              tweezerBull,tweezerBear;
   int               run;                    // consecutive closes the same way
  };

//--- a resting liquidity pool (§4)
struct SLIQ
  {
   double            price;
   int               side;         // +1 buyside (highs), -1 sellside (lows)
   int               touches;
   int               shift;
   bool              swept;
   bool              alive;
  };

//--- everything the engines see this bar
struct SView
  {
   double            avgRange;     // mean true range, a distance unit only
   double            bid,ask,spreadPts;
   // §1 structure
   int               structDir;
   bool              bullBos,bearBos,bullChoch,bearChoch;
   bool              bullMss,bearMss;      // shift right after a sweep
   int               mssAgeBars;
   double            lastSwingHigh,lastSwingLow;
   // §4 liquidity
   bool              sweptSellside,sweptBuyside;
   double            sweepLevel,sweepExtreme;
   int               sweepAgeBars;
   double            nearestBuyside,nearestSellside;
   // §5 premium / discount
   double            rangeHigh,rangeLow,equilibrium;
   double            pdPosition;           // 0 = range low, 1 = range high
   bool              inDiscount,inPremium,inOte;
   // §6 killzone
   bool              inKillzone;
   string            killzoneName;
   // §7 HTF
   double            htfBias;              // -1..+1
   // active setup
   string            setup;
   int               setupDir;
   double            zoneTop,zoneBottom;   // the POI being entered
   double            stopLevel,targetLevel;
   double            setupRR;
   // §10 confluence
   double            quality;              // 0..1, how much confluence backs it
   double            sizeFactor;           // risk multiplier derived from quality
   string            confluence;           // the tags that scored
   double            poiDistance;          // avg-range units to the nearest live POI
   double            poiGrade;             // 0..1 grade of the POI actually entered
   string            modelCode;            // short tag carried into the deal comment
   int               obCount,fvgCount,liqCount;
   int               bagCount,invCount;    // breakaway gaps and inversions live
   int               freshCount;           // gaps young enough to trade without a retrace
  };

//--- one evaluated direction, before the two are compared
struct SSetup
  {
   int               dir;
   double            zoneTop,zoneBottom;
   double            stop,target,rr;
   double            quality,sizeFactor,poiGrade;
   string            model,confluence,modelCode;
  };

//--- basket state (§9)
struct SBasket
  {
   int               count;
   double            volume,avgEntry,floatPL;
   int               dir;
   datetime          firstTime,lastTime;
   double            lastPrice,firstVolume;
  };

//=========================== GLOBAL STATE ===========================

double   g_h[],g_l[],g_o[],g_c[];
datetime g_t[];
long     g_v[];
int      g_bars=0;
ENUM_TIMEFRAMES g_tf=PERIOD_H1;      // resolved execution timeframe
string   TfName(void){ return EnumToString(g_tf); }

SOB      g_obs[];
SFVG     g_fvgs[];
SLIQ     g_liqs[];
SCandle  g_candle,g_candleLive;
SView    g_view;

double   g_basketRisk=0.0;          // R unit for the whole basket
double   g_firstLot=0.0;
double   g_basketStop=0.0;
double   g_basketZoneTop=0.0;       // the POI the basket was entered from
double   g_basketZoneBottom=0.0;
double   g_basketTrail=0.0;         // best trailed stop so far

//--- cost-of-trading census, reported at the end of the run
double   g_sumSpread=0.0,g_sumStop=0.0;
int      g_nEntries=0;
ulong    g_partialDone[],g_beDone[];

double   g_dayStartEquity=0.0,g_peakEquity=0.0,g_lifetimePeak=0.0;
bool     g_fatal=false;
datetime g_lastTickTime=0;
double   g_secBlocked=0.0,g_secTotal=0.0;
int      g_dayKey=-1;
datetime g_dayStart=0;
datetime g_lastFitLog=0;
double   g_lastFitDist=0.0;
bool     g_breaker=false,g_breakerLogged=false;

datetime g_lastBar=0,g_lastEntry=0;
int      g_logHandle=INVALID_HANDLE;
string   g_block="starting",g_lastBlock="",g_avoidReason="";
datetime g_lastBlockLog=0;
int      g_entries=0;
int      g_objCount=0;

//============================== LOGGING =============================

void LogInit(void)
  {
   g_logHandle=INVALID_HANDLE;
   if(!InpCsvLog) return;
   g_logHandle=FileOpen("MedulaSMC.csv",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(g_logHandle!=INVALID_HANDLE)
     {
      if(FileSize(g_logHandle)==0)
         FileWriteString(g_logHandle,"time;symbol;setup;dir;quality;htfBias;pd;killzone;entry;sl;tp;rr;lots;risk;basket;reason\n");
      FileSeek(g_logHandle,0,SEEK_END);
     }
  }
void LogClose(void){ if(g_logHandle!=INVALID_HANDLE){ FileClose(g_logHandle); g_logHandle=INVALID_HANDLE; } }
void LogEvent(const string m){ if(InpVerboseLog) Print("[SMC] ",m); }

void LogTrade(const string dir,const double entry,const double sl,const double tp,
              const double rr,const double lots,const double risk,const int basket,
              const string reason)
  {
   string line=StringFormat("%s;%s;%s;%s;%.2f;%.2f;%.2f;%s;%.5f;%.5f;%.5f;%.2f;%.2f;%.2f;%d;%s",
                            TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),_Symbol,
                            g_view.setup,dir,g_view.quality,g_view.htfBias,g_view.pdPosition,
                            g_view.killzoneName,entry,sl,tp,rr,lots,risk,basket,reason);
   if(InpVerboseLog) Print("[SMC] ",line);
   if(g_logHandle!=INVALID_HANDLE){ FileWriteString(g_logHandle,line+"\n"); FileFlush(g_logHandle); }
  }

void Block(const string reason)
  {
   g_block=reason;
   if(!InpDiagnostics) return;
   datetime now=TimeCurrent();
   if(reason==g_lastBlock && (now-g_lastBlockLog)<InpDiagThrottleSec) return;
   g_lastBlock=reason; g_lastBlockLog=now;
   LogEvent("no entry — "+reason);
  }

//========================= RAW PRICE ACCESS =========================

//--- true range is arithmetic on the bars, not an indicator
double TrueRange(const int i)
  {
   if(i+1>=g_bars) return g_h[i]-g_l[i];
   double a=g_h[i]-g_l[i];
   return MathMax(a,MathMax(MathAbs(g_h[i]-g_c[i+1]),MathAbs(g_l[i]-g_c[i+1])));
  }

double AverageRange(const int period)
  {
   int n=MathMin(period,g_bars-1);
   if(n<=0) return 0.0;
   double s=0.0;
   for(int i=0;i<n;i++) s+=TrueRange(i);
   return s/n;
  }

bool LoadBars(void)
  {
   ArraySetAsSeries(g_h,true); ArraySetAsSeries(g_l,true);
   ArraySetAsSeries(g_o,true); ArraySetAsSeries(g_c,true);
   ArraySetAsSeries(g_t,true); ArraySetAsSeries(g_v,true);
   int got=CopyHigh(_Symbol,g_tf,0,InpBars,g_h);
   if(got<120){ Block(StringFormat("only %d %s bars loaded, need 120+",got,TfName())); return false; }
   if(CopyLow(_Symbol,g_tf,0,got,g_l)<got)   return false;
   if(CopyOpen(_Symbol,g_tf,0,got,g_o)<got)  return false;
   if(CopyClose(_Symbol,g_tf,0,got,g_c)<got) return false;
   if(CopyTime(_Symbol,g_tf,0,got,g_t)<got)  return false;
   if(CopyTickVolume(_Symbol,g_tf,0,got,g_v)<got) ArrayInitialize(g_v,1);
   g_bars=got;
   return true;
  }

bool IsSwingHigh(const int j,const int k)
  {
   if(j-k<0 || j+k>=g_bars) return false;
   for(int m=1;m<=k;m++)
      if(g_h[j]<=g_h[j+m] || g_h[j]<=g_h[j-m]) return false;
   return true;
  }
bool IsSwingLow(const int j,const int k)
  {
   if(j-k<0 || j+k>=g_bars) return false;
   for(int m=1;m<=k;m++)
      if(g_l[j]>=g_l[j+m] || g_l[j]>=g_l[j-m]) return false;
   return true;
  }

//================== §1 MARKET STRUCTURE / MSS =======================

//--- Walk the window oldest to newest tracking swing points and the breaks
//    between them. A break in the direction of the prevailing leg is a BOS;
//    a break against it is a CHoCH. A CHoCH that lands immediately after a
//    liquidity sweep is a market structure shift — the ICT entry trigger.
void BuildStructure(void)
  {
   g_view.bullBos=false; g_view.bearBos=false;
   g_view.bullChoch=false; g_view.bearChoch=false;
   g_view.bullMss=false; g_view.bearMss=false;
   g_view.mssAgeBars=9999;
   g_view.lastSwingHigh=0.0; g_view.lastSwingLow=0.0;

   int k=InpSwingK;
   double buf=InpBosBufferPct*g_view.avgRange;
   double lastSH=0.0,lastSL=0.0;
   int dir=0;

   for(int b=g_bars-1-k;b>=0;b--)
     {
      int j=b+k;                                  // confirmed k bars later
      if(j<=g_bars-1-k)
        {
         if(IsSwingHigh(j,k)) lastSH=g_h[j];
         if(IsSwingLow(j,k))  lastSL=g_l[j];
        }
      if(lastSH>0.0 && g_c[b]>lastSH+buf)
        {
         bool choch=(dir==-1);
         dir=1;
         if(b<=InpStructureLookback)
           {
            if(choch){ g_view.bullChoch=true; g_view.bullMss=true; g_view.mssAgeBars=MathMin(g_view.mssAgeBars,b); }
            else       g_view.bullBos=true;
           }
         lastSH=0.0;
        }
      if(lastSL>0.0 && g_c[b]<lastSL-buf)
        {
         bool choch=(dir==1);
         dir=-1;
         if(b<=InpStructureLookback)
           {
            if(choch){ g_view.bearChoch=true; g_view.bearMss=true; g_view.mssAgeBars=MathMin(g_view.mssAgeBars,b); }
            else       g_view.bearBos=true;
           }
         lastSL=0.0;
        }
     }
   g_view.structDir=dir;

   for(int j=k;j<g_bars-k;j++)
     {
      if(g_view.lastSwingHigh<=0.0 && IsSwingHigh(j,k)) g_view.lastSwingHigh=g_h[j];
      if(g_view.lastSwingLow <=0.0 && IsSwingLow(j,k))  g_view.lastSwingLow =g_l[j];
      if(g_view.lastSwingHigh>0.0 && g_view.lastSwingLow>0.0) break;
     }
  }

//======================= §2 ORDER BLOCKS ============================

void PushOB(const double top,const double bottom,const int dir,const int shift,
            const double strength)
  {
   int n=ArraySize(g_obs);
   if(n>=InpMaxOrderBlocks*2) return;
   ArrayResize(g_obs,n+1);
   g_obs[n].top=top; g_obs[n].bottom=bottom; g_obs[n].dir=dir;
   g_obs[n].shift=shift; g_obs[n].strength=strength;
   g_obs[n].mitigated=false; g_obs[n].breaker=false; g_obs[n].alive=true;
  }

//--- An order block is the last candle against the move, immediately before
//    a displacement leg. Institutions are held to have positioned there, so
//    price returning to it is the classic entry. A block price has closed
//    decisively through has failed and becomes a breaker in the other
//    direction.
void BuildOrderBlocks(void)
  {
   ArrayResize(g_obs,0);
   if(!InpUseOrderBlocks || g_view.avgRange<=0.0) return;

   // newest first, for the same reason as the gap book: the fixed number of
   // slots must go to the blocks price can still reach, not to the oldest
   int scan=MathMin(g_bars-4,InpObMaxAgeBars);
   for(int i=1;i<=scan;i++)
     {
      double rng=g_h[i]-g_l[i];
      if(rng<=0.0) continue;
      double body=MathAbs(g_c[i]-g_o[i]);
      bool up=(rng>=InpDisplacementMult*g_view.avgRange &&
               body>=InpDisplacementBody*rng && g_c[i]>g_o[i]);
      bool dn=(rng>=InpDisplacementMult*g_view.avgRange &&
               body>=InpDisplacementBody*rng && g_c[i]<g_o[i]);
      if(!up && !dn) continue;

      // the last opposing candle before the displacement
      int ob=-1;
      for(int b=i+1;b<=i+6 && b<g_bars;b++)
        {
         if(up && g_c[b]<g_o[b]){ ob=b; break; }
         if(dn && g_c[b]>g_o[b]){ ob=b; break; }
        }
      if(ob<0) continue;
      PushOB(g_h[ob],g_l[ob],(up?1:-1),ob,rng/g_view.avgRange);
     }

   // mitigation and breaker state
   for(int z=ArraySize(g_obs)-1;z>=0;z--)
     {
      double top=g_obs[z].top,bot=g_obs[z].bottom,h=top-bot;
      if(h<=0.0){ g_obs[z].alive=false; continue; }
      double mitLevel=(g_obs[z].dir>0 ? top-h*InpObMitigatedPct/100.0
                                      : bot+h*InpObMitigatedPct/100.0);
      for(int i=g_obs[z].shift-1;i>=0;i--)
        {
         if(g_obs[z].dir>0)
           {
            if(g_l[i]<=mitLevel) g_obs[z].mitigated=true;
            if(g_c[i]<bot-0.2*g_view.avgRange)
              {
               if(InpUseBreakers){ g_obs[z].breaker=true; g_obs[z].dir=-1; }
               else g_obs[z].alive=false;
               break;
              }
           }
         else
           {
            if(g_h[i]>=mitLevel) g_obs[z].mitigated=true;
            if(g_c[i]>top+0.2*g_view.avgRange)
              {
               if(InpUseBreakers){ g_obs[z].breaker=true; g_obs[z].dir=1; }
               else g_obs[z].alive=false;
               break;
              }
           }
        }
     }
   g_view.obCount=0;
   for(int z=0;z<ArraySize(g_obs);z++) if(g_obs[z].alive) g_view.obCount++;
  }

//====================== §3 FAIR VALUE GAPS ==========================

//--- the most recent confirmed swing level strictly older than bar i
double SwingBefore(const int i,const bool wantHigh)
  {
   int k=InpSwingK;
   for(int j=i+1;j<i+1+InpStructureLookback && j+k<g_bars;j++)
     {
      if(wantHigh){ if(IsSwingHigh(j,k)) return g_h[j]; }
      else        { if(IsSwingLow(j,k))  return g_l[j];  }
     }
   return 0.0;
  }

//--- Not every gap is the same trade.
//
//    A BREAKAWAY gap is left by the candle that breaks structure at the START
//    of an expansion: the run into it is short, the candle itself is large,
//    and its close takes the last swing. That gap is where the move began and
//    price defends it — it is the highest-value entry on the chart.
//
//    An EXHAUSTION gap prints at the END of a run that is already extended,
//    typically as price reaches for a pool. It gets filled. Entering there is
//    stepping in front of the reversal, so the EA grades it down to near zero
//    and uses it as a TARGET instead.
//
//    Everything between the two is a MEASURING gap: ordinary continuation.
ENUM_GAPKIND ClassifyGap(const int i,const int dir,const double strength)
  {
   int n=MathMin(InpExhaustLookback,g_bars-i-2);
   if(n<3) return GAP_MEASURING;

   double hi=g_h[i+1],lo=g_l[i+1];
   for(int b=i+1;b<=i+n && b<g_bars;b++)
     { hi=MathMax(hi,g_h[b]); lo=MathMin(lo,g_l[b]); }

   // how far the market had already travelled before this candle printed
   double runIn=(dir>0 ? g_h[i]-lo : hi-g_l[i])/MathMax(g_view.avgRange,1e-9);
   double swing=SwingBefore(i,dir>0);
   double buf=InpBosBufferPct*g_view.avgRange;
   bool   bos=(swing>0.0 && (dir>0 ? g_c[i]>swing+buf : g_c[i]<swing-buf));

   // the gap candle contributes its own range to the run, so it is allowed for
   // A breakaway gap breaks decisively OUT OF A RANGE. Without the
   // consolidation test any strong BOS candle was being called a breakaway,
   // which over-counted them badly — and on M5 forex and metals true
   // breakaway gaps are genuinely rare, mostly weekly opens and news.
   double window=(hi-lo)/MathMax(g_view.avgRange,1e-9);
   bool consolidated=(window-strength<=InpBagRangeMax);
   if(bos && consolidated && strength>=InpBagDisplaceMult &&
      runIn<=InpBagMaxRunIn+strength)
      return GAP_BREAKAWAY;
   if(runIn>=InpExhaustRunMult && (dir>0 ? g_h[i]>=hi : g_l[i]<=lo))
      return GAP_EXHAUSTION;
   return GAP_MEASURING;
  }

//--- What a gap is worth, 0..1. Size and the displacement behind it say how
//    real the imbalance is, kind says whether price defends it or fills it,
//    age says whether it is still in play, and consumption discounts what has
//    already been given back. Nothing here refuses a trade — it prices one.
double GradeGap(const int z)
  {
   double sizeScore =MClamp(g_fvgs[z].size,0.0,1.0);
   double strScore  =MClamp((g_fvgs[z].strength-1.0)/MathMax(InpBagDisplaceMult,0.1),0.0,1.0);
   double kindScore =(g_fvgs[z].kind==GAP_BREAKAWAY  ? 1.00 :
                      g_fvgs[z].kind==GAP_EXHAUSTION ? 0.15 :
                      g_fvgs[z].kind==GAP_VOLIMB     ? 0.40 : 0.60);
   double fresh     =MClamp(1.0-(double)g_fvgs[z].shift/MathMax((double)InpFvgMaxAgeBars,1.0),
                            0.0,1.0);
   double g=0.28*sizeScore+0.27*strScore+0.27*kindScore+0.18*fresh;
   g*=(1.0-0.60*MClamp(g_fvgs[z].filledPct,0.0,1.0));  // a half-given-back gap is half the trade
   if(g_fvgs[z].inverted) g*=0.85;                     // an inversion is real, just second-hand
   return MClamp(g,0.0,1.0);
  }

string FvgName(const SFVG &f)
  {
   if(f.inverted)                 return "inversion FVG";
   if(f.kind==GAP_BREAKAWAY)      return "breakaway gap";
   if(f.kind==GAP_EXHAUSTION)     return "exhaustion gap";
   if(f.kind==GAP_VOLIMB)         return "volume imbalance";
   return "FVG";
  }

void PushFVG(const double top,const double bottom,const int dir,const int i,
             const bool volImb=false)
  {
   int n=ArraySize(g_fvgs);
   if(n>=InpMaxFVGs*2) return;
   double rng=g_h[i]-g_l[i];
   double strength=(g_view.avgRange>0.0 ? rng/g_view.avgRange : 0.0);
   ArrayResize(g_fvgs,n+1);
   g_fvgs[n].top=top; g_fvgs[n].bottom=bottom;
   g_fvgs[n].ce=(top+bottom)*0.5;
   g_fvgs[n].dir=dir; g_fvgs[n].shift=i;
   g_fvgs[n].size=(top-bottom)/MathMax(g_view.avgRange,1e-9);
   g_fvgs[n].strength=strength;
   g_fvgs[n].kind=(volImb ? GAP_VOLIMB : ClassifyGap(i,dir,strength));
   g_fvgs[n].filledPct=0.0; g_fvgs[n].grade=0.0;
   g_fvgs[n].filled=false; g_fvgs[n].inverted=false; g_fvgs[n].alive=true;
  }

//--- A fair value gap is a three-candle imbalance: price moved so fast that
//    candle 1 and candle 3 do not overlap. The unfilled space is inefficient
//    pricing that price tends to revisit.
void BuildFVGs(void)
  {
   ArrayResize(g_fvgs,0);
   if(!InpUseFVG || g_view.avgRange<=0.0) return;

   // v5.12 put a spread floor here and that was wrong. The spread decides
   // whether a TARGET pays, not whether a gap EXISTS. A ten-cent imbalance on
   // gold is a real imbalance; it is entered at the gap and exited at a target
   // one-and-a-bit R away, and that target clears the spread easily. Judging
   // the gap by the spread deleted exactly the small gaps this EA is supposed
   // to scalp. The viability test belongs on the target, and it is there now.
   //
   // What remains is a sanity floor: a gap must be big enough to be a gap.
   double minGap=MathMax(InpFvgMinPct*g_view.avgRange,_Point);

   // NEWEST FIRST. The book has a fixed number of slots; filling it from the
   // oldest end meant a busy session spent them on 200-bar-old gaps and threw
   // away the fresh ones — the only gaps §3b can actually trade.
   int scan=MathMin(g_bars-3,InpFvgMaxAgeBars);
   for(int i=1;i<=scan;i++)
     {
      // bullish: low of the newer candle above the high of the older one
      bool got=false;
      if(g_l[i-1]-g_h[i+1]>=minGap){ PushFVG(g_l[i-1],g_h[i+1], 1,i); got=true; }
      if(g_l[i+1]-g_h[i-1]>=minGap){ PushFVG(g_l[i+1],g_h[i-1],-1,i); got=true; }
      if(got || !InpUseVolumeImb) continue;

      // No three-candle gap here, but the bodies may still not overlap: price
      // left a volume imbalance between one close and the next open. It is a
      // smaller, weaker POI — and it is precisely the detail a scalper is
      // supposed to see. It trades, at the size its grade earns.
      if(g_o[i]-g_c[i+1]>=minGap) PushFVG(g_o[i],g_c[i+1], 1,i,true);
      if(g_c[i+1]-g_o[i]>=minGap) PushFVG(g_c[i+1],g_o[i],-1,i,true);
     }

   // Consumption and inversion. The old engine deleted any gap price closed
   // through; that is the moment the gap becomes useful in the other
   // direction, not the moment it stops mattering. Fill is tracked as a
   // fraction so the consequent encroachment — the classic entry — still
   // leaves a tradeable, correctly discounted zone.
   for(int z=ArraySize(g_fvgs)-1;z>=0;z--)
     {
      double h=g_fvgs[z].top-g_fvgs[z].bottom;
      if(h<=0.0){ g_fvgs[z].alive=false; continue; }

      for(int i=g_fvgs[z].shift-1;i>=0;i--)
        {
         double depth=(g_fvgs[z].dir>0 ? (g_fvgs[z].top-g_l[i])
                                       : (g_h[i]-g_fvgs[z].bottom))/h;
         if(depth>g_fvgs[z].filledPct) g_fvgs[z].filledPct=MClamp(depth,0.0,1.0);

         bool through=(g_fvgs[z].dir>0 ? g_c[i]<g_fvgs[z].bottom
                                       : g_c[i]>g_fvgs[z].top);
         if(!through) continue;

         // a second violation means the zone has failed both ways — drop it
         if(!InpUseInversionFvg || g_fvgs[z].inverted){ g_fvgs[z].alive=false; break; }

         g_fvgs[z].dir      =-g_fvgs[z].dir;
         g_fvgs[z].inverted =true;
         g_fvgs[z].filledPct=0.0;
         g_fvgs[z].shift    =i;              // it dates from the violation, not the print
         if(g_fvgs[z].kind==GAP_EXHAUSTION) g_fvgs[z].kind=GAP_MEASURING;
        }

      g_fvgs[z].filled=(g_fvgs[z].filledPct*100.0>=InpFvgFillPct);
      g_fvgs[z].grade =GradeGap(z);
      if(g_fvgs[z].grade<FvgGradeFloorEff()) g_fvgs[z].alive=false;
     }

   g_view.fvgCount=0; g_view.bagCount=0; g_view.invCount=0; g_view.freshCount=0;
   for(int z=0;z<ArraySize(g_fvgs);z++)
     {
      if(!g_fvgs[z].alive) continue;
      g_view.fvgCount++;
      if(g_fvgs[z].kind==GAP_BREAKAWAY)          g_view.bagCount++;
      if(g_fvgs[z].inverted)                     g_view.invCount++;
      if(g_fvgs[z].shift<=InpFreshGapMaxAge &&
         g_fvgs[z].filledPct<1.0)                g_view.freshCount++;
     }
  }

//====================== §3f CANDLE ANATOMY ==========================

//--- Everything the last closed candle says about itself, and about the one
//    before it. No indicator, no zone — the shape of the bars, which is what
//    a person actually reads off the chart.
//--- SPEED. Confirmation read only from the last CLOSED candle costs a whole
//    M5 bar between the signal and the fill — on a scalp that is most of the
//    move. The live candle is read as well, and once it has developed enough
//    body to mean something it can confirm on its own. Same test, up to five
//    minutes earlier.
void BuildCandleAnatomyAt(const int idx,SCandle &c)
  {
   ZeroMemory(c);
   if(g_bars<idx+3 || g_view.avgRange<=0.0) return;

   double o=g_o[idx],h=g_h[idx],l=g_l[idx],cl=g_c[idx];
   double rng=h-l;
   if(rng<=0.0) return;

   double body=MathAbs(cl-o);
   c.dir       =(cl>o ? 1 : (cl<o ? -1 : 0));
   c.rangeX    =rng/g_view.avgRange;
   c.bodyPct   =body/rng;
   c.upperWick =(h-MathMax(o,cl))/rng;
   c.lowerWick =(MathMin(o,cl)-l)/rng;
   c.closePos  =(cl-l)/rng;                     // 1 = closed on the high

   c.strongCloseUp=(c.closePos>=InpAnatStrongClose);
   c.strongCloseDn=(c.closePos<=1.0-InpAnatStrongClose);

   // a pin bar rejects one side: a long wick against a small body
   c.pinBull=(c.lowerWick*rng>=InpAnatPinWick*body && c.lowerWick>=InpAnatPinShare);
   c.pinBear=(c.upperWick*rng>=InpAnatPinWick*body && c.upperWick>=InpAnatPinShare);

   // engulfing, inside and outside are all relative to the candle before
   double o2=g_o[idx+1],h2=g_h[idx+1],l2=g_l[idx+1],c2=g_c[idx+1];
   double topB =MathMax(o,cl),  botB =MathMin(o,cl);
   double topB2=MathMax(o2,c2), botB2=MathMin(o2,c2);
   bool prevBear=(c2<o2), prevBull=(c2>o2);

   c.engulfBull=(c.dir> 0 && prevBear && botB<=botB2 && topB>=topB2);
   c.engulfBear=(c.dir< 0 && prevBull && botB<=botB2 && topB>=topB2);
   c.insideBar =(h< h2 && l> l2);
   c.outsideBar=(h> h2 && l< l2);

   // conviction and indecision, at the two extremes of body share
   c.marubozu=(c.bodyPct>=0.80);
   c.doji    =(c.bodyPct<=0.12);

   // harami: this body sits entirely inside the previous body — the move paused
   c.haramiBull=(c.dir> 0 && prevBear && topB<=topB2 && botB>=botB2);
   c.haramiBear=(c.dir< 0 && prevBull && topB<=topB2 && botB>=botB2);

   // tweezers: two candles rejecting from the same level
   double tol=0.10*g_view.avgRange;
   c.tweezerBull=(MathAbs(l-l2)<=tol && c.dir>0 && prevBear);
   c.tweezerBear=(MathAbs(h-h2)<=tol && c.dir<0 && prevBull);

   // three-bar reversal: drive, pause, drive back
   if(g_bars>idx+3)
     {
      double o3=g_o[idx+2],c3=g_c[idx+2];
      bool small2=(MathAbs(c2-o2)<=0.45*MathAbs(c3-o3));
      c.starBull=(c3<o3 && small2 && c.dir>0 && cl>(o3+c3)*0.5);
      c.starBear=(c3>o3 && small2 && c.dir<0 && cl<(o3+c3)*0.5);
     }

   // how long price has been closing the same way
   int run=0;
   for(int b2=idx;b2<idx+8 && b2<g_bars;b2++)
     {
      int d=(g_c[b2]>g_o[b2] ? 1 : (g_c[b2]<g_o[b2] ? -1 : 0));
      if(d==0 || (run!=0 && d!=(run>0?1:-1))) break;
      run+=(d>0?1:-1);
     }
   c.run=run;
  }

void BuildCandleAnatomy(void)
  {
   BuildCandleAnatomyAt(1,g_candle);       // the last closed candle
   BuildCandleAnatomyAt(0,g_candleLive);   // the one forming right now
  }

//--- How strongly the anatomy backs a trade in this direction, 0..1.
double AnatomyScoreOf(const SCandle &k,const int dir)
  {
   if(k.dir==0 && k.rangeX<=0.0) return 0.0;
   double s=0.0;
   s+=0.28*MClamp(k.bodyPct,0.0,1.0);
   s+=0.22*(dir>0 ? MClamp(k.closePos,0.0,1.0) : MClamp(1.0-k.closePos,0.0,1.0));
   s+=0.20*((dir>0 && k.engulfBull)||(dir<0 && k.engulfBear) ? 1.0 : 0.0);
   s+=0.14*((dir>0 && k.pinBull)   ||(dir<0 && k.pinBear)    ? 1.0 : 0.0);
   s+=0.08*MClamp(k.rangeX,0.0,1.0);
   s+=0.05*(k.outsideBar ? 1.0 : 0.0);
   s+=0.05*(k.marubozu   ? 1.0 : 0.0);
   s+=0.08*((dir>0 && k.starBull)   ||(dir<0 && k.starBear)    ? 1.0 : 0.0);
   s+=0.05*((dir>0 && k.tweezerBull)||(dir<0 && k.tweezerBear) ? 1.0 : 0.0);
   s+=0.05*MClamp(MathAbs((double)k.run)/4.0,0.0,1.0)*(MSign((double)k.run)==dir?1.0:0.0);

   if(k.doji) s*=0.55;                                 // indecision is not a signal
   if((dir>0 && k.haramiBear)||(dir<0 && k.haramiBull)) s*=0.80;
   if(k.dir!=0 && k.dir!=dir) s*=0.70;                 // the candle points the other way
   return MClamp(s,0.0,1.0);
  }
double AnatomyScore(const int dir)
  {
   double best=AnatomyScoreOf(g_candle,dir);
   if(InpFastConfirm && g_candleLive.rangeX>=InpFastMinRange)
      best=MathMax(best,AnatomyScoreOf(g_candleLive,dir));
   return best;
  }

//--- what to call it in the journal
string AnatomyName(const int dir)
  {
   string t="";
   if(dir>0 && g_candle.engulfBull) t+="bull engulfing ";
   if(dir<0 && g_candle.engulfBear) t+="bear engulfing ";
   if(dir>0 && g_candle.pinBull)    t+="bullish pin ";
   if(dir<0 && g_candle.pinBear)    t+="bearish pin ";
   if(dir>0 && g_candle.strongCloseUp) t+="strong close ";
   if(dir<0 && g_candle.strongCloseDn) t+="strong close ";
   if(dir>0 && g_candle.starBull)    t+="morning star ";
   if(dir<0 && g_candle.starBear)    t+="evening star ";
   if(dir>0 && g_candle.tweezerBull) t+="tweezer bottom ";
   if(dir<0 && g_candle.tweezerBear) t+="tweezer top ";
   if(g_candle.marubozu)   t+="marubozu ";
   if(g_candle.insideBar)  t+="inside-bar break ";
   if(g_candle.outsideBar) t+="outside bar ";
   if(g_candle.doji)       t+="doji ";
   if(t=="") t="plain candle ";
   return t;
  }

//============== §3g THE CONFIRMED RETRACEMENT MODEL =================

//--- STEP 4. Price has come back into the gap; has it shown a reason to go?
//    Rejection candle, engulfing candle, a break of the minor structure
//    against the move, or a strong close in our direction.
bool ConfirmFrom(const SCandle &k,const int dir,const int idx,string &why);

bool HasConfirmation(const int dir,string &why)
  {
   if(ConfirmFrom(g_candle,dir,1,why)) return true;
   if(InpFastConfirm && g_candleLive.rangeX>=InpFastMinRange &&
      ConfirmFrom(g_candleLive,dir,0,why))
     { why=why+" (live candle)"; return true; }
   return false;
  }

bool ConfirmFrom(const SCandle &k,const int dir,const int idx,string &why)
  {
   why="";
   if(dir>0)
     {
      if(k.engulfBull)                      { why="bullish engulfing";      return true; }
      if(k.pinBull)                         { why="bullish rejection";      return true; }
      if(k.starBull)                        { why="morning star";          return true; }
      if(k.tweezerBull)                     { why="tweezer bottom";        return true; }
      if(k.strongCloseUp && k.dir>0)        { why="strong bullish close";   return true; }
      if(g_bars>idx+2 && g_c[idx]>g_h[idx+1]){ why="minor structure break";  return true; }
     }
   else
     {
      if(k.engulfBear)                      { why="bearish engulfing";      return true; }
      if(k.pinBear)                         { why="bearish rejection";      return true; }
      if(k.starBear)                        { why="evening star";          return true; }
      if(k.tweezerBear)                     { why="tweezer top";           return true; }
      if(k.strongCloseDn && k.dir<0)        { why="strong bearish close";   return true; }
      if(g_bars>idx+2 && g_c[idx]<g_l[idx+1]){ why="minor structure break";  return true; }
     }
   if(AnatomyScoreOf(k,dir)>=InpConfirmMinAnat){ why="candle anatomy"; return true; }
   return false;
  }

//--- WHEN TO AVOID AN FVG TRADE.
//    These are the model's own exclusions, and unlike the confluence weights
//    they DO refuse. "The broader market structure contradicts the setup" is a
//    reason not to take the trade, not a reason to take it smaller.
bool AvoidSetup(const int dir,string &why)
  {
   why="";
   if(!InpConfirmModel) return false;

   if(InpAvoidRanging && g_view.structDir==0)
     { why="market is ranging with no clear directional bias"; return true; }

   if(InpAvoidStructAgainst && g_view.structDir==-dir && dir*g_view.htfBias<0.0)
     { why="broader market structure contradicts the setup"; return true; }

   // a violent candle against us during the pullback says the retracement is
   // not a retracement — it is the next leg
   if(InpAvoidMomentumAgainst && g_candle.dir!=0 && g_candle.dir!=dir &&
      g_candle.rangeX>=InpMomentumAgainstX && g_candle.bodyPct>=0.55)
     { why="strong momentum against the move during the retracement"; return true; }

   return false;
  }

//--- STEP: is there enough room to the next major level to be worth taking?
bool EnoughRoom(const int dir,const double px,const double risk)
  {
   if(!InpConfirmModel || risk<=0.0) return true;
   double pool=(dir>0 ? g_view.nearestBuyside : g_view.nearestSellside);
   bool valid=(dir>0 ? pool>px : (pool>0.0 && pool<px));
   if(!valid) return true;                       // no wall in the way at all
   return (MathAbs(pool-px)/risk>=InpMinRoomR);
  }

//--- is a live gap in this direction backing the trigger? "not ignoring fair
//    value gaps and break away gaps" — the anatomy trigger is worth more when
//    the imbalance engine agrees with it.
bool GapSupports(const int dir,const int withinBars)
  {
   for(int z=0;z<ArraySize(g_fvgs);z++)
     {
      if(!g_fvgs[z].alive || g_fvgs[z].dir!=dir) continue;
      if(g_fvgs[z].kind==GAP_EXHAUSTION) continue;
      if(g_fvgs[z].shift<=withinBars && g_fvgs[z].filledPct<1.0) return true;
     }
   return false;
  }

//--- PROOF OF WORK.  "I'm not seeing changes" and "it isn't detecting the
//    small gaps" are different problems with the same symptom, and no amount
//    of reasoning from a chart screenshot separates them. This prints every
//    gap young enough to be traded on the next candle, once per bar, with its
//    kind, size, grade and zone — so the log says plainly what the EA can see.
void LogGaps(void)
  {
   if(!InpLogGaps || !InpVerboseLog) return;
   int shown=0;
   for(int z=0;z<ArraySize(g_fvgs) && shown<6;z++)
     {
      if(!g_fvgs[z].alive) continue;
      if(g_fvgs[z].shift>InpNextCandleBars+2) continue;
      if(g_fvgs[z].filledPct>=1.0) continue;
      LogEvent(StringFormat("gap seen: %-17s dir %+d  age %d bars  size %.2f x avg  "
                            "grade %.2f  filled %.0f%%  zone %.5f-%.5f",
                            FvgName(g_fvgs[z]),g_fvgs[z].dir,g_fvgs[z].shift,
                            g_fvgs[z].size,g_fvgs[z].grade,g_fvgs[z].filledPct*100.0,
                            g_fvgs[z].bottom,g_fvgs[z].top));
      shown++;
     }
  }

//--- The nearest unrebalanced gap ahead of price is a draw on liquidity: the
//    market goes there to fix the inefficiency. Used as a TARGET only — the
//    consequent encroachment is where fills reliably reach.
double FvgDraw(const int dir,const double px)
  {
   if(!InpFvgTargetPull) return 0.0;
   double best=0.0;
   for(int z=0;z<ArraySize(g_fvgs);z++)
     {
      if(!g_fvgs[z].alive || g_fvgs[z].filledPct>=0.99) continue;
      double lvl=g_fvgs[z].ce;
      if(dir>0)
        {
         if(g_fvgs[z].bottom<=px) continue;
         if(best<=0.0 || lvl<best) best=lvl;
        }
      else
        {
         if(g_fvgs[z].top>=px) continue;
         if(best<=0.0 || lvl>best) best=lvl;
        }
     }
   return best;
  }

//==================== §4 LIQUIDITY AND SWEEPS =======================

void PushLiq(const double price,const int side,const int touches,const int shift)
  {
   int n=ArraySize(g_liqs);
   ArrayResize(g_liqs,n+1);
   g_liqs[n].price=price; g_liqs[n].side=side; g_liqs[n].touches=touches;
   g_liqs[n].shift=shift; g_liqs[n].swept=false; g_liqs[n].alive=true;
  }

//--- Stops rest above equal highs and below equal lows, and at the previous
//    day's extremes. Those pools are what gets hunted. A sweep is price
//    taking the level and closing back on the original side — the wick
//    through it is the stop run.
void BuildLiquidity(void)
  {
   ArrayResize(g_liqs,0);
   g_view.sweptBuyside=false; g_view.sweptSellside=false;
   g_view.sweepLevel=0.0; g_view.sweepExtreme=0.0; g_view.sweepAgeBars=9999;
   g_view.nearestBuyside=0.0; g_view.nearestSellside=0.0;
   if(g_view.avgRange<=0.0) return;

   double tol=InpEqualTolPct*g_view.avgRange;
   int k=InpSwingK;
   int scan=MathMin(g_bars-1-k,InpLiqLookback);

   // swing extremes become pools; equal levels stack into stronger ones
   for(int j=k;j<=scan;j++)
     {
      if(IsSwingHigh(j,k))
        {
         bool merged=false;
         for(int z=0;z<ArraySize(g_liqs);z++)
            if(g_liqs[z].side>0 && MathAbs(g_liqs[z].price-g_h[j])<=tol)
              { g_liqs[z].touches++; merged=true; break; }
         if(!merged) PushLiq(g_h[j],1,1,j);
        }
      if(IsSwingLow(j,k))
        {
         bool merged=false;
         for(int z=0;z<ArraySize(g_liqs);z++)
            if(g_liqs[z].side<0 && MathAbs(g_liqs[z].price-g_l[j])<=tol)
              { g_liqs[z].touches++; merged=true; break; }
         if(!merged) PushLiq(g_l[j],-1,1,j);
        }
     }

   // previous day's high and low are major pools
   if(InpUsePrevDayLevels)
     {
      double dh[],dl[];
      ArraySetAsSeries(dh,true); ArraySetAsSeries(dl,true);
      if(CopyHigh(_Symbol,PERIOD_D1,0,3,dh)>=2 && CopyLow(_Symbol,PERIOD_D1,0,3,dl)>=2)
        {
         PushLiq(dh[1],1,3,0);
         PushLiq(dl[1],-1,3,0);
        }
     }

   // sweep detection: level taken, then rejected
   for(int z=0;z<ArraySize(g_liqs);z++)
     {
      for(int i=MathMin(g_liqs[z].shift-1,InpSweepMaxAgeBars);i>=0;i--)
        {
         if(i<0) break;
         if(g_liqs[z].side>0 && g_h[i]>g_liqs[z].price && g_c[i]<g_liqs[z].price)
           {
            g_liqs[z].swept=true;
            if(i<g_view.sweepAgeBars)
              {
               g_view.sweptBuyside=true; g_view.sweptSellside=false;
               g_view.sweepLevel=g_liqs[z].price;
               g_view.sweepExtreme=g_h[i];
               g_view.sweepAgeBars=i;
              }
           }
         if(g_liqs[z].side<0 && g_l[i]<g_liqs[z].price && g_c[i]>g_liqs[z].price)
           {
            g_liqs[z].swept=true;
            if(i<g_view.sweepAgeBars)
              {
               g_view.sweptSellside=true; g_view.sweptBuyside=false;
               g_view.sweepLevel=g_liqs[z].price;
               g_view.sweepExtreme=g_l[i];
               g_view.sweepAgeBars=i;
              }
           }
        }
     }

   // nearest untouched pools become the natural targets
   double px=g_view.bid,bestUp=DBL_MAX,bestDn=DBL_MAX;
   for(int z=0;z<ArraySize(g_liqs);z++)
     {
      if(!g_liqs[z].alive || g_liqs[z].swept) continue;
      if(g_liqs[z].side>0 && g_liqs[z].price>px && (g_liqs[z].price-px)<bestUp)
        { bestUp=g_liqs[z].price-px; g_view.nearestBuyside=g_liqs[z].price; }
      if(g_liqs[z].side<0 && g_liqs[z].price<px && (px-g_liqs[z].price)<bestDn)
        { bestDn=px-g_liqs[z].price; g_view.nearestSellside=g_liqs[z].price; }
     }
   g_view.liqCount=ArraySize(g_liqs);
  }

//=================== §5 PREMIUM / DISCOUNT / OTE ====================

//--- The dealing range runs from the recent swing low to the recent swing
//    high. Below its midpoint is discount — where longs are cheap. Above is
//    premium. The optimal trade entry band sits at the 62-79% retracement.
void BuildPremiumDiscount(void)
  {
   int n=MathMin(InpDealingRangeBars,g_bars-1);
   double hi=-DBL_MAX,lo=DBL_MAX;
   for(int i=0;i<n;i++)
     {
      if(g_h[i]>hi) hi=g_h[i];
      if(g_l[i]<lo) lo=g_l[i];
     }
   g_view.rangeHigh=hi; g_view.rangeLow=lo;
   double span=hi-lo;
   g_view.equilibrium=(hi+lo)*0.5;
   g_view.pdPosition=(span>0.0 ? (g_view.bid-lo)/span : 0.5);
   g_view.inDiscount=(g_view.pdPosition<0.5);
   g_view.inPremium =(g_view.pdPosition>0.5);

   // OTE measured from whichever end the current leg started
   double retr=(g_view.structDir>=0 ? 1.0-g_view.pdPosition : g_view.pdPosition);
   g_view.inOte=(retr>=InpOteLow && retr<=InpOteHigh);
  }

//========================== §6 KILLZONES ============================

void BuildKillzone(void)
  {
   g_view.inKillzone=false;
   g_view.killzoneName="outside";
   MqlDateTime g;
   TimeToStruct(TimeGMT(),g);
   int h=g.hour;
   if(h>=InpLondonStart && h<InpLondonEnd){ g_view.inKillzone=true; g_view.killzoneName="London"; }
   else if(h>=InpNyStart && h<InpNyEnd)   { g_view.inKillzone=true; g_view.killzoneName="NewYork"; }
   else if(h>=InpLnCloseStart && h<InpLnCloseEnd){ g_view.inKillzone=true; g_view.killzoneName="LondonClose"; }
  }

//========================= §7 HIGHER TF BIAS ========================

//--- Higher-timeframe direction read the same way: the sequence of swing
//    highs and lows, not an average of price.
double HtfStructure(const ENUM_TIMEFRAMES tf)
  {
   double hh[],ll[];
   ArraySetAsSeries(hh,true); ArraySetAsSeries(ll,true);
   int want=100;
   if(CopyHigh(_Symbol,tf,0,want,hh)<want) return 0.0;
   if(CopyLow(_Symbol,tf,0,want,ll)<want)  return 0.0;
   int k=2,up=0,dn=0;
   double ph=0.0,pl=0.0;
   for(int j=want-1-k;j>=k;j--)
     {
      bool sh=true,sl=true;
      for(int m=1;m<=k;m++)
        {
         if(hh[j]<=hh[j+m] || hh[j]<=hh[j-m]) sh=false;
         if(ll[j]>=ll[j+m] || ll[j]>=ll[j-m]) sl=false;
        }
      if(sh){ if(ph>0.0){ if(hh[j]>ph) up++; else dn++; } ph=hh[j]; }
      if(sl){ if(pl>0.0){ if(ll[j]>pl) up++; else dn++; } pl=ll[j]; }
     }
   return (double)(up-dn)/(double)(up+dn+1);
  }

void BuildHtfBias(void)
  {
   double sum=0.0,w=0.0;
   if(InpHtfH4){ sum+=0.40*HtfStructure(PERIOD_H4); w+=0.40; }
   if(InpHtfD1){ sum+=0.40*HtfStructure(PERIOD_D1); w+=0.40; }
   if(InpHtfW1){ sum+=0.20*HtfStructure(PERIOD_W1); w+=0.20; }
   g_view.htfBias=(w>0.0 ? MClamp(sum/w,-1.0,1.0) : 0.0);
  }

//======================= THE ICT ENTRY MODEL ========================

//--- What a point of interest is worth per unit of risk.
//
//    Two live POIs are not equal even at the same grade: the one whose stop
//    sits closer returns more for the same money, and on a small account it is
//    the only one the risk ceiling can actually carry at minimum lot. The
//    constant keeps a zero-width zone from scoring infinity.
double PoiScore(const double grade,const double px,const double top,
                const double bottom,const int dir)
  {
   double far=(dir>0 ? bottom-InpPoiStopBuffer*g_view.avgRange
                     : top   +InpPoiStopBuffer*g_view.avgRange);
   // score the stop the EA will actually use. Entry floors the stop at 0.25 x
   // avg range, so scoring a 6-point gap as if it risked 6 points would rank
   // every micro-gap above everything else on a distance it never gets.
   double risk=MathMax(MathAbs(px-far),MinStopDistance())
               /MathMax(g_view.avgRange,1e-9);
   return grade/(0.60+risk);
  }

//--- Evaluate one direction.
//
//    There is exactly ONE hard condition: price must be trading inside a
//    live, unmitigated fair value gap or order block pointing this way, or
//    a gap this way must have just printed (§3b, the continuation entry).
//    That is the ICT entry itself — without it there is nothing to trade.
//
//    Every other classical filter (HTF bias, liquidity sweep, structure
//    shift, premium/discount, OTE, killzone) is scored, not enforced. They
//    add up to a quality figure between 0 and 1 which decides HOW MUCH the
//    EA commits. Thin confluence means a small trade, not no trade — the
//    edge is in taking many properly-sized setups, not in waiting for the
//    one moment when every box happens to be ticked at once.
bool EvaluateDirection(const int dir,SSetup &s)
  {
   s.dir=0; s.quality=0.0; s.sizeFactor=0.0; s.rr=0.0; s.poiGrade=0.0;
   s.zoneTop=0.0; s.zoneBottom=0.0; s.stop=0.0; s.target=0.0;
   s.model=""; s.confluence="";

   double px=g_view.bid;
   double buf=InpEntryZoneBuffer*g_view.avgRange;

   //---- THE HARD CONDITION: price inside a live POI of this direction.
   //
   //     v5.00 took the first POI the loop happened to reach and stopped. That
   //     is how a sprawling breaker block, whose stop sat six average ranges
   //     away, kept winning over a tight breakaway gap two candles old. Now
   //     every POI price is inside is scored on what it is worth PER UNIT OF
   //     RISK, and the best one is the trade.
   double zt=0.0,zb=0.0,poiGrade=0.0,bestScore=-1.0;
   string src="";

   // §3g STEP 0: the avoid-list. Checked before anything is scored, because
   // these are conditions under which the model says do not trade at all.
   string avoidWhy="";
   if(AvoidSetup(dir,avoidWhy)){ g_avoidReason=avoidWhy; return false; }

   if(InpEntryOnFVG && InpUseFVG)
      for(int z=0;z<ArraySize(g_fvgs);z++)
        {
         if(!g_fvgs[z].alive || g_fvgs[z].filledPct>=1.0) continue;
         if(g_fvgs[z].dir!=dir) continue;
         if(g_fvgs[z].shift>InpFvgMaxAgeBars) continue;
         if(InpConfirmModel)
           {
            // STEP 2: the impulse has to have left a MEANINGFUL imbalance
            if(g_fvgs[z].size<InpImpulseMinPct)      continue;
            if(g_fvgs[z].kind==GAP_EXHAUSTION)       continue;
            // STEP 3: price must have RETRACED INTO the gap — not near it
            if(InpRequireRetrace &&
               (px>g_fvgs[z].top || px<g_fvgs[z].bottom)) continue;
           }
         if(px>g_fvgs[z].top+buf || px<g_fvgs[z].bottom-buf) continue;
         double sc=PoiScore(g_fvgs[z].grade,px,g_fvgs[z].top,g_fvgs[z].bottom,dir);
         if(sc<=bestScore) continue;
         bestScore=sc; zt=g_fvgs[z].top; zb=g_fvgs[z].bottom;
         poiGrade=g_fvgs[z].grade; src=FvgName(g_fvgs[z]);
         if(!InpBestPoi) break;
        }

   if(InpEntryOnOB && InpUseOrderBlocks && (InpBestPoi || zt<=0.0))
      for(int z=0;z<ArraySize(g_obs);z++)
        {
         if(!g_obs[z].alive) continue;
         if(g_obs[z].dir!=dir) continue;
         if(g_obs[z].shift>InpObMaxAgeBars) continue;
         if(px>g_obs[z].top+buf || px<g_obs[z].bottom-buf) continue;
         double og=MClamp(0.35+0.20*MClamp((g_obs[z].strength-1.0)/1.5,0.0,1.0)
                          +(g_obs[z].breaker  ? 0.10 : 0.0)
                          -(g_obs[z].mitigated? 0.10 : 0.0),0.05,1.0);
         double sc=PoiScore(og,px,g_obs[z].top,g_obs[z].bottom,dir);
         if(sc<=bestScore) continue;
         bestScore=sc; zt=g_obs[z].top; zb=g_obs[z].bottom; poiGrade=og;
         src=(g_obs[z].breaker ? "breaker block" : "order block");
         if(!InpBestPoi) break;
        }

   //---- §3b THE FRESH GAP: trade the candle after the imbalance prints.
   //
   //     Requiring price to be INSIDE a POI means the EA only ever trades
   //     retracements, so every gap that runs without one is a chance it
   //     watched go past. After genuine displacement most gaps are not
   //     retraced — that IS the point of displacement.
   //
   //     So a gap younger than InpFreshGapMaxAge is tradeable from the
   //     continuation side too: ordinary fair value gaps as much as
   //     breakaway gaps. The stop still sits beyond the far edge of the gap,
   //     which is what keeps this a trade rather than a chase — and the chase
   //     is bounded anyway: once price has run InpFreshGapMaxRun past the
   //     gap the stop is too wide to be worth it and the EA goes back to
   //     waiting for the retrace.
   bool freshEntry=false;
   if(InpTradeFreshGaps && !InpConfirmModel && InpUseFVG && (InpBestPoi || zt<=0.0))
      for(int z=0;z<ArraySize(g_fvgs);z++)
        {
         if(!g_fvgs[z].alive || g_fvgs[z].filledPct>=1.0) continue;
         if(g_fvgs[z].dir!=dir) continue;
         if(g_fvgs[z].shift>InpFreshGapMaxAge) continue;
         if(g_fvgs[z].grade<FreshGradeFloorEff()) continue;
         if(SkipExhaustEff() && g_fvgs[z].kind==GAP_EXHAUSTION) continue;

         // how far past the gap price has already travelled; <=0 means price
         // is still in the zone, which the loop above has already handled
         double run=(dir>0 ? px-(g_fvgs[z].top+buf) : (g_fvgs[z].bottom-buf)-px);
         if(run<=0.0) continue;
         if(run>InpFreshGapMaxRun*g_view.avgRange) continue;

         double sc=PoiScore(g_fvgs[z].grade,px,g_fvgs[z].top,g_fvgs[z].bottom,dir);
         if(sc<=bestScore) continue;
         bestScore=sc; zt=g_fvgs[z].top; zb=g_fvgs[z].bottom;
         poiGrade=g_fvgs[z].grade; src="fresh "+FvgName(g_fvgs[z]);
         freshEntry=true;
        }

   //---- §3c PRICE ACTION: the candle itself is the setup.
   //
   //     Everything above needs a *zone* — three candles that leave a gap, or
   //     an order block. A displacement candle needs neither. If a candle has
   //     a real body and covers real distance, that IS the move, and the trade
   //     is either the pullback into it or the continuation off it. Small gaps
   //     the imbalance test cannot see are caught here as the candle that made
   //     them, which is the whole point.
   //
   //     Zone: the bullish candle runs from its LOW to its CLOSE, so the stop
   //     lands under the wick that made it rather than inside the body.
   bool paEntry=false;
   if(InpTradePaCandles && !InpConfirmModel && g_view.avgRange>0.0)
      for(int i=1;i<=InpPaMaxAge && i<g_bars;i++)
        {
         double rng=g_h[i]-g_l[i];
         if(rng<=0.0) continue;
         double body=MathAbs(g_c[i]-g_o[i]);
         if(body<InpPaBodyPct*rng)              continue;   // no conviction in the candle
         if(rng <InpPaRangeMult*g_view.avgRange)continue;   // no distance covered
         if((g_c[i]>g_o[i] ? 1 : -1)!=dir)      continue;

         double ztop=(dir>0 ? g_c[i] : g_h[i]);
         double zbot=(dir>0 ? g_l[i] : g_c[i]);
         if(ztop<=zbot) continue;

         double run=(dir>0 ? px-(ztop+buf) : (zbot-buf)-px);
         if(run>InpPaMaxRun*g_view.avgRange) continue;      // ran away, let it come back
         if(run<=0.0 && (px>ztop+buf || px<zbot-buf)) continue;  // not at the candle at all

         double pg=MClamp(0.25+0.35*(body/rng)
                          +0.30*MClamp((rng/g_view.avgRange-1.0)/1.5,0.0,1.0),0.05,1.0);
         double sc=PoiScore(pg,px,ztop,zbot,dir);
         if(sc<=bestScore) continue;
         bestScore=sc; zt=ztop; zb=zbot; poiGrade=pg;
         src="displacement candle";
         paEntry=true; freshEntry=(run>0.0);
        }

   //---- §3d THE NEXT CANDLE. No conditions at all.
   //
   //     Every path above asks price to do something first: be inside the
   //     zone, or be past it by a qualifying amount, or be at a candle of a
   //     certain shape. By the principle of the thing, a fair value gap is
   //     complete when its third candle closes and the trade is the candle
   //     after that. Nothing else needs to be true.
   //
   //     So this path tests one thing — a gap in this direction printed
   //     within the last InpNextCandleBars bars — and takes it. It carries a
   //     priority boost so the newest gap wins against older, better-placed
   //     POIs rather than losing the scoring contest to them.
   bool nextCandle=false;
   if(InpNextCandleEntry && !InpConfirmModel && InpUseFVG)
      for(int z=0;z<ArraySize(g_fvgs);z++)
        {
         if(!g_fvgs[z].alive)                        continue;
         if(g_fvgs[z].dir!=dir)                      continue;
         if(g_fvgs[z].shift>InpNextCandleBars)       continue;
         if(g_fvgs[z].filledPct>=1.0)                continue;
         if(SkipExhaustEff() && g_fvgs[z].kind==GAP_EXHAUSTION) continue;
         // The boost SCALES the gap's own worth rather than being added to it.
         // A flat bonus made the newest gap win outright, so a junk volume
         // imbalance outranked a textbook breakaway gap — the exact opposite of
         // valuing FVG and BAG. Multiplied, recency breaks ties between decent
         // setups and never promotes a bad one over a good one.
         double sc=PoiScore(g_fvgs[z].grade,px,g_fvgs[z].top,g_fvgs[z].bottom,dir)
                   *(1.0+InpNextCandleBoost);
         if(sc<=bestScore) continue;
         bestScore=sc; zt=g_fvgs[z].top; zb=g_fvgs[z].bottom;
         poiGrade=g_fvgs[z].grade; src="new "+FvgName(g_fvgs[z]);
         nextCandle=true; freshEntry=true; paEntry=false;
        }

   //---- §3e THE SECOND CANDLESTICK.
   //
   //     The rule as stated: a fair value gap tells you that you should have
   //     entered on the second candlestick, when it came higher than the one
   //     before it. So that is the trigger — this candle taking the previous
   //     candle's high — and it fires a full candle before any gap can be
   //     confirmed, because a three-candle gap needs its third candle to close
   //     and by then the leg has run.
   //
   //     A staircase of ordinary candles each making a higher high contains no
   //     displacement candle and often no measurable imbalance at all. Every
   //     path above this one was blind to exactly that, which is what the
   //     02:40-03:30 rally was.
   //
   //     The stop goes under the candle that was taken. The grade comes from
   //     the anatomy of that candle, plus a bonus when the gap engine agrees.
   bool twoCandle=false;
   if(InpTwoCandleEntry && !InpConfirmModel && g_bars>3 && g_view.avgRange>0.0)
     {
      bool takes=(dir>0 ? px>g_h[1] : px<g_l[1]);
      bool seqOK=(!InpTwoCandleNeedSeq ||
                  (dir>0 ? (g_h[1]>g_h[2] && g_l[1]>g_l[2])
                         : (g_h[1]<g_h[2] && g_l[1]<g_l[2])));
      double anat=AnatomyScore(dir);
      if(takes && seqOK && anat>=InpTwoCandleMinAnat)
        {
         double ztop=g_h[1],zbot=g_l[1];
         double run=(dir>0 ? px-ztop : zbot-px);
         if(run>=0.0 && run<=InpPaMaxRun*g_view.avgRange && ztop>zbot)
           {
            double tg=MClamp(0.25+0.45*anat
                             +(GapSupports(dir,4)?InpGapSupportBonus:0.0),0.05,1.0);
            double sc=PoiScore(tg,px,ztop,zbot,dir);
            if(sc>bestScore)
              {
               bestScore=sc; zt=ztop; zb=zbot; poiGrade=tg;
               src=AnatomyName(dir)+"take of prior high";
               if(dir<0) src=AnatomyName(dir)+"take of prior low";
               twoCandle=true; freshEntry=true; paEntry=false; nextCandle=false;
              }
           }
        }
     }

   if(zt<=0.0) return false;                 // nothing to trade — the only veto

   // §3g STEP 4-5: enter AFTER confirmation, never on the gap forming.
   string confirmWhy="";
   if(InpConfirmModel && InpRequireConfirm)
     {
      if(!HasConfirmation(dir,confirmWhy))
        { g_avoidReason="waiting for price-action confirmation in the gap"; return false; }
     }

   //---- CONFLUENCE. Each term is graded 0..1; none of them can return false.
   bool swept=(dir>0 ? g_view.sweptSellside : g_view.sweptBuyside);
   bool sweepFresh=(swept && g_view.sweepAgeBars<=InpSweepMaxAgeBars);
   bool mss=(dir>0 ? (g_view.bullMss || g_view.bullBos)
                   : (g_view.bearMss || g_view.bearBos));
   bool mssFresh=(mss && g_view.mssAgeBars<=InpMaxSetupAgeBars);
   bool aligned=(g_view.structDir==dir);
   bool opposed=(g_view.structDir==-dir);

   // HTF: graded agreement. Disagreement scores zero and shrinks the trade;
   // it never cancels it. This is the gate that stood the EA down all day.
   double htfScore=MClamp((dir*g_view.htfBias)/MathMax(InpHtfFullAt,1e-6),0.0,1.0);

   double structScore;
   if(mssFresh && aligned)      structScore=1.00;   // shift and trend agree
   else if(mssFresh)            structScore=0.80;   // a fresh shift our way
   else if(aligned)             structScore=0.70;   // simply with structure
   else if(mss)                 structScore=0.50;   // an older break our way
   else if(opposed)             structScore=0.15;   // counter-trend POI trade
   else                         structScore=0.40;   // structure undecided

   double sweepScore=(sweepFresh ? 1.0 : (swept ? 0.45 : 0.0));

   // depth of discount for a buy, depth of premium for a sell
   double pdScore=(dir>0 ? MClamp((0.5-g_view.pdPosition)/0.5,0.0,1.0)
                         : MClamp((g_view.pdPosition-0.5)/0.5,0.0,1.0));
   double oteScore=(g_view.inOte    ? 1.0 : 0.0);
   double kzScore =(g_view.inKillzone ? 1.0 : 0.0);

   // the POI itself is confluence. A breakaway gap with real displacement
   // behind it deserves more size than a stale mitigated block, and that
   // judgement belongs in the score rather than in a filter.
   double gradeScore=MClamp(poiGrade,0.0,1.0);

   // the candles themselves are confluence: an engulfing close on the high
   // backs the trade, a doji against it does not
   double anatScore=AnatomyScore(dir);

   double wsum=InpWeightHtf+InpWeightStructure+InpWeightSweep+
               InpWeightPD +InpWeightOte      +InpWeightKillzone+InpWeightPoiGrade+
               InpWeightAnatomy;
   double q=1.0;
   if(wsum>0.0)
      q=(InpWeightHtf*htfScore + InpWeightStructure*structScore +
         InpWeightSweep*sweepScore + InpWeightPD*pdScore +
         InpWeightOte*oteScore + InpWeightKillzone*kzScore +
         InpWeightPoiGrade*gradeScore + InpWeightAnatomy*anatScore)/wsum;
   q=MClamp(q,0.0,1.0);

   if(q<QualityFloorEff()) return false;     // off by default (floor = 0)

   //---- stop placement decides whether this is a scalp or a swing
   double sl,tp;
   if(InpStopBeyondPOI || InpScalpMode)
     {
      double buf2=InpPoiStopBuffer*g_view.avgRange;
      sl=(dir>0 ? zb-buf2 : zt+buf2);
     }
   else
     {
      double slBuf=InpSlBufferPct*g_view.avgRange;
      if(dir>0) sl=(g_view.sweepExtreme>0.0 ? MathMin(g_view.sweepExtreme,zb) : zb)-slBuf;
      else      sl=(g_view.sweepExtreme>0.0 ? MathMax(g_view.sweepExtreme,zt) : zt)+slBuf;
     }

   // §3g: stop below the recent swing low (or above the swing high), which is
   // beyond the gap edge rather than sitting on it
   if(InpConfirmModel && InpStopAtSwing)
     {
      double sw=(dir>0 ? g_view.lastSwingLow : g_view.lastSwingHigh);
      if(sw>0.0)
        {
         double swStop=(dir>0 ? sw-InpPoiStopBuffer*g_view.avgRange
                              : sw+InpPoiStopBuffer*g_view.avgRange);
         if(dir>0 ? swStop<sl : swStop>sl) sl=swStop;
        }
     }

   double risk=MathAbs(px-sl);
   double minRisk=MinStopDistance();         // never inside the round-trip cost
   if(risk<minRisk)
     {
      risk=minRisk;
      sl=(dir>0 ? px-risk : px+risk);
     }
   if(risk<=0.0) return false;

   // Reward:risk is a TARGET RULE, not an entry filter. A nearby liquidity
   // pool is used only while it still pays at least InpTargetMinRR; below
   // that the EA reverts to its R target rather than refusing the setup.
   //
   // Two things draw price: resting liquidity, and unrebalanced price. An
   // unfilled gap ahead of the trade — an exhaustion gap above all — is where
   // the market is headed to fix itself, so it competes with the pool for the
   // target. Whichever is nearer and still pays takes it.
   double rTarget=(InpScalpMode ? InpScalpTargetR : InpTpRMultiple)*risk;
   tp=(dir>0 ? px+rTarget : px-rTarget);

   double cand[2];
   cand[0]=(dir>0 ? g_view.nearestBuyside : g_view.nearestSellside);
   cand[1]=FvgDraw(dir,px);

   double drawLvl=0.0,drawR=0.0;
   for(int c=0;c<2;c++)
     {
      double lvl=cand[c];
      if(lvl<=0.0) continue;
      if(dir>0 ? lvl<=px : lvl>=px) continue;
      double lvlR=MathAbs(lvl-px)/risk;
      if(lvlR<InpTargetMinRR) continue;
      if(drawLvl<=0.0 || lvlR<drawR){ drawLvl=lvl; drawR=lvlR; }
     }
   if(drawLvl>0.0)
     {
      if(InpScalpMode){ if(drawR<rTarget/risk) tp=drawLvl; }
      else                                     tp=drawLvl;
     }
   double rr=MathAbs(tp-px)/risk;
   if(rr<InpTargetMinRR)                     // stretch the target, never skip
     {
      rr=InpTargetMinRR;
      tp=(dir>0 ? px+rr*risk : px-rr*risk);
     }

   // THIS is where the spread belongs. A target inside the cost of the round
   // trip is not a target — but the answer is to push it out, not to refuse
   // the setup. Judging the ENTRY by the spread is what deleted the small gaps.
   double sprd=MathMax(g_view.ask-g_view.bid,0.0);
   if(sprd>0.0 && MathAbs(tp-px)<InpMinTargetSpreads*sprd)
     {
      tp=(dir>0 ? px+InpMinTargetSpreads*sprd : px-InpMinTargetSpreads*sprd);
      rr=MathAbs(tp-px)/risk;
     }

   if(!EnoughRoom(dir,px,risk))
     { g_avoidReason="not enough room to the next major level"; return false; }

   if(confirmWhy!="")         s.model=src+" + "+confirmWhy;   // §3g confirmed retracement
   else if(freshEntry)        s.model=src+" continuation";    // §3b, no retrace waited for
   else if(sweepFresh && mssFresh) s.model="sweep + MSS + "+src;  // full ICT reversal
   else if(mssFresh)          s.model="MSS + "+src;           // shift into the POI
   else if(aligned)           s.model=src+" continuation";    // with-structure scalp
   else                       s.model=src+" reversion";       // counter-trend POI

   string tags="";
   if(htfScore   >=0.5) tags+="HTF ";
   if(structScore>=0.7) tags+="STRUCT ";
   if(sweepFresh)       tags+="SWEEP ";
   if(pdScore    >=0.5) tags+=(dir>0?"DISC ":"PREM ");
   if(g_view.inOte)     tags+="OTE ";
   if(g_view.inKillzone)tags+="KZ ";
   if(gradeScore >=0.55)tags+="A+POI ";
   if(freshEntry)       tags+="FRESH ";
   if(paEntry)          tags+="PA ";
   if(nextCandle)       tags+="NEXT ";
   if(twoCandle)        tags+="2CDL ";
   if(confirmWhy!="")   tags+="CONF ";
   if(anatScore>=0.55)  tags+="ANAT ";
   if(tags=="") tags="bare POI";

   s.dir=dir; s.zoneTop=zt; s.zoneBottom=zb;
   s.stop=sl; s.target=tp; s.rr=rr;
   // a short tag so the deal itself records WHICH model opened it, and the
   // end-of-run report can say which ones earn and which ones bleed
   string code;
   if(paEntry)                              code="PA";
   else if(StringFind(src,"breakaway")>=0)  code="BAG";
   else if(StringFind(src,"inversion")>=0)  code="IFVG";
   else if(StringFind(src,"volume")>=0)     code="VI";
   else if(StringFind(src,"exhaustion")>=0) code="EXH";
   else if(StringFind(src,"breaker")>=0)    code="BRK";
   else if(StringFind(src,"order block")>=0)code="OB";
   else                                     code="FVG";
   if(freshEntry)  code="F"+code;
   if(nextCandle)  code="N"+code;   // traded on the candle after it printed
   if(twoCandle)   code="2CDL";     // the second-candlestick trigger, its own model
   s.modelCode=code;

   s.quality=q; s.poiGrade=poiGrade;
   // STRATEGY WITHOUT A VETO. A setup pointing against both local structure
   // and the higher timeframes is still taken — the mandate holds — but it is
   // taken at half size. Fighting the trend and backing it with identical
   // money is what makes a run of trades look directionless.
   double sf=MClamp(InpMinSizeFactor+(1.0-InpMinSizeFactor)*q,0.05,1.0);
   if(opposed && dir*g_view.htfBias<0.0) sf*=MClamp(InpCounterTrendFac,0.05,1.0);
   s.sizeFactor=MClamp(sf,0.05,1.0);
   s.confluence=tags;
   return true;
  }

//--- how far the nearest live POI is, in average-range units (diagnostics)
double NearestPoiDistance(void)
  {
   double px=g_view.bid,best=-1.0;
   for(int z=0;z<ArraySize(g_fvgs);z++)
     {
      if(!g_fvgs[z].alive || g_fvgs[z].filledPct>=1.0) continue;
      double d=(px>g_fvgs[z].top ? px-g_fvgs[z].top
                                 : (px<g_fvgs[z].bottom ? g_fvgs[z].bottom-px : 0.0));
      if(best<0.0 || d<best) best=d;
     }
   for(int z=0;z<ArraySize(g_obs);z++)
     {
      if(!g_obs[z].alive) continue;
      double d=(px>g_obs[z].top ? px-g_obs[z].top
                                : (px<g_obs[z].bottom ? g_obs[z].bottom-px : 0.0));
      if(best<0.0 || d<best) best=d;
     }
   if(best<0.0 || g_view.avgRange<=0.0) return -1.0;
   return best/g_view.avgRange;
  }

//--- Score both sides and trade the better one. Two opposing POIs can be
//    live at once; the EA picks by quality rather than by which loop ran
//    first, and ties go to the higher timeframes.
void FindSetup(void)
  {
   g_view.setup="none";
   g_view.setupDir=0;
   g_view.zoneTop=0.0; g_view.zoneBottom=0.0;
   g_view.stopLevel=0.0; g_view.targetLevel=0.0; g_view.setupRR=0.0;
   g_view.quality=0.0; g_view.sizeFactor=0.0; g_view.confluence="";
   g_avoidReason="";
   g_view.poiDistance=NearestPoiDistance();

   SSetup up,dn,best;
   bool okUp=EvaluateDirection(1,up);
   bool okDn=EvaluateDirection(-1,dn);
   if(!okUp && !okDn) return;

   bool takeUp;
   if(okUp && okDn)
     {
      if(MathAbs(up.quality-dn.quality)<1e-9) takeUp=(g_view.htfBias>=0.0);
      else                                    takeUp=(up.quality>dn.quality);
     }
   else takeUp=okUp;
   if(takeUp) best=up; else best=dn;

   g_view.setup=StringFormat("%s %s",(best.dir>0?"bullish":"bearish"),best.model);
   g_view.setupDir=best.dir;
   g_view.zoneTop=best.zoneTop; g_view.zoneBottom=best.zoneBottom;
   g_view.stopLevel=best.stop;  g_view.targetLevel=best.target;
   g_view.setupRR=best.rr;
   g_view.quality=best.quality; g_view.sizeFactor=best.sizeFactor;
   g_view.poiGrade=best.poiGrade;
   g_view.modelCode=best.modelCode;
   g_view.confluence=best.confluence;
  }

//--- With confluence scored rather than enforced, only two things can leave
//    the EA flat: there is no POI on the chart, or price has not reached one.
//    Both are stated with the distance, so the journal shows progress rather
//    than a filter name.
string MissingLeg(void)
  {
   if(g_view.obCount==0 && g_view.fvgCount==0)
      return "no live order block or fair value gap on the chart yet";
   if(InpConfirmModel && g_avoidReason!="") return g_avoidReason;
   if(g_view.poiDistance>=0.0)
      return StringFormat("price is not in a POI yet — nearest is %.2f x avg range away "
                          "(%d blocks, %d gaps live: %d breakaway, %d inverted, %d fresh)",
                          g_view.poiDistance,g_view.obCount,g_view.fvgCount,
                          g_view.bagCount,g_view.invCount,g_view.freshCount);
   return "waiting for price to trade into a POI";
  }

//============================ RISK / SIZE ===========================

void RiskUpdate(void)
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int key=dt.year*1000+dt.day_of_year;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(key!=g_dayKey)
     {
      g_dayKey=key; g_dayStartEquity=eq; g_breaker=false;
      dt.hour=0; dt.min=0; dt.sec=0;
      g_dayStart=StructToTime(dt);
      // The peak resets with the day. Left ratcheting from the all-time high
      // it made the drawdown rail permanent — see CircuitBreaker below.
      g_peakEquity=eq;
     }
   if(eq>g_peakEquity)     g_peakEquity=eq;
   if(eq>g_lifetimePeak)   g_lifetimePeak=eq;
   if(g_lifetimePeak<=0.0) g_lifetimePeak=eq;
  }

//--- closed losing trades of ours since midnight
int DayLosingTrades(void)
  {
   if(g_dayStart<=0) return 0;
   if(!HistorySelect(g_dayStart,TimeCurrent()+1)) return 0;
   int losses=0,total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagic) continue;
      if(HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double net=HistoryDealGetDouble(tk,DEAL_PROFIT)
                +HistoryDealGetDouble(tk,DEAL_SWAP)
                +HistoryDealGetDouble(tk,DEAL_COMMISSION);
      if(net<0.0) losses++;
     }
   return losses;
  }

//--- THE BUG THAT MADE EVERY OTHER FIX INVISIBLE.
//
//    g_peakEquity only ever ratcheted upward, and the rail read
//
//        (peak - equity) >= peak * InpMaxDDPct
//
//    Once equity sat 20% below the ALL-TIME high the test was true forever.
//    The daily reset cleared g_breaker, and the very next tick re-latched it,
//    because equity was still below a peak that could never come down. And
//    recovering the drawdown requires trading, which the rail forbids.
//
//    With a 20% per-trade ceiling on a $10 account, ONE full-size loss is
//    exactly 20% — so the EA disabled itself permanently after a single
//    losing trade and spent the rest of the backtest printing nothing. Eight
//    trades across the whole history, and no change to the entry model could
//    ever have shown up, because none of it was reachable.
//
//    Drawdown is now measured from the DAY'S high-water mark, which resets
//    with the day, so the rail brakes a bad session and then lets the EA back
//    out. A second, much larger rail measured from the all-time peak is the
//    one that genuinely stops for good.
bool CircuitBreaker(void)
  {
   if(g_breaker) return true;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);

   if((g_dayStartEquity-eq)>=g_dayStartEquity*InpDailyLossPct/100.0 &&
      DayLosingTrades()>=InpBreakerMinLosses)
     {
      LogEvent(StringFormat("circuit breaker: daily loss %.2f of %.2f start equity "
                            "(%d losing trades today)",
                            g_dayStartEquity-eq,g_dayStartEquity,DayLosingTrades()));
      g_breaker=true;
     }

   if(g_peakEquity>0.0 && (g_peakEquity-eq)>=g_peakEquity*InpMaxDDPct/100.0)
     {
      LogEvent(StringFormat("circuit breaker: %.1f%% below today's peak (%.2f from %.2f) "
                            "— stood down until tomorrow",
                            100.0*(g_peakEquity-eq)/g_peakEquity,eq,g_peakEquity));
      g_breaker=true;
     }

   if(g_lifetimePeak>0.0 && (g_lifetimePeak-eq)>=g_lifetimePeak*InpMaxAccountDDPct/100.0)
     {
      if(!g_fatal)
         LogEvent(StringFormat("*** ACCOUNT DRAWDOWN %.0f%% FROM PEAK %.2f — TRADING STOPPED "
                               "FOR THE REST OF THE RUN ***",
                               100.0*(g_lifetimePeak-eq)/g_lifetimePeak,g_lifetimePeak));
      g_fatal=true;
     }
   if(g_fatal) return true;
   return g_breaker;
  }

double MinLot(void){ double m=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN); return (m>0.0?m:0.01); }
double LotStep(void){ double s=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP); return (s>0.0?s:0.01); }

double LotForRisk(const double amount,const double dist)
  {
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0.0||ts<=0.0||dist<=0.0||amount<=0.0) return 0.0;
   double perLot=dist/ts*tv;
   return (perLot>0.0 ? amount/perLot : 0.0);
  }
double RiskOfLots(const double lots,const double dist)
  {
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0.0||ts<=0.0) return 0.0;
   return dist/ts*tv*lots;
  }
double NormalizeLots(double lots)
  {
   double step=LotStep(),mn=MinLot(),mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   lots=MathFloor(lots/step+1e-9)*step;
   if(lots<mn) return (InpAllowMinLot?mn:0.0);
   if(mx>0.0)  lots=MathMin(lots,mx);
   return lots;
  }
//--- widest stop this account can carry at minimum lot inside the ceiling
double AffordableStop(void)
  {
   double cap=AccountInfoDouble(ACCOUNT_EQUITY)*InpMaxRiskPctHard/100.0;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0.0||ts<=0.0) return 0.0;
   return cap/(tv/ts*MinLot());
  }
bool MarginOK(const int dir,const double lots)
  {
   MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return false;
   double m=0.0;
   if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,lots,
                       (dir>0?t.ask:t.bid),m)) return false;
   return AccountInfoDouble(ACCOUNT_MARGIN_FREE)>=m*InpMarginSafety;
  }

//========================= TRADE PLUMBING ===========================

ENUM_ORDER_TYPE_FILLING Filling(void)
  {
   long f=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((f&SYMBOL_FILLING_FOK)!=0) return ORDER_FILLING_FOK;
   if((f&SYMBOL_FILLING_IOC)!=0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }
bool Send(MqlTradeRequest &req,MqlTradeResult &res)
  {
   if(!OrderSend(req,res)) return false;
   return (res.retcode==TRADE_RETCODE_DONE || res.retcode==TRADE_RETCODE_DONE_PARTIAL ||
           res.retcode==TRADE_RETCODE_PLACED);
  }
bool TicketSeen(const ulong &a[],const ulong t)
  { for(int i=ArraySize(a)-1;i>=0;i--) if(a[i]==t) return true; return false; }
void TicketMark(ulong &a[],const ulong t)
  { int n=ArraySize(a); ArrayResize(a,n+1); a[n]=t; }

//========================= §9 BASKET MANAGER ========================

//--- Positions on this symbol under this magic are one exposure. The basket
//    has a single average entry, a single R unit taken from the first entry,
//    and one set of targets — individual legs are never managed alone.
void GetBasket(SBasket &b)
  {
   b.count=0; b.volume=0.0; b.avgEntry=0.0; b.floatPL=0.0; b.dir=0;
   b.firstTime=0; b.lastTime=0; b.lastPrice=0.0; b.firstVolume=0.0;
   double pv=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double op =PositionGetDouble(POSITION_PRICE_OPEN);
      datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
      b.count++; b.volume+=vol; pv+=vol*op;
      b.floatPL+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      b.dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);
      if(b.firstTime==0 || ot<b.firstTime){ b.firstTime=ot; b.firstVolume=vol; }
      if(ot>=b.lastTime){ b.lastTime=ot; b.lastPrice=op; }
     }
   if(b.volume>0.0) b.avgEntry=pv/b.volume;
  }

bool ClosePartial(const ulong ticket,const double volume)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   string sym=PositionGetString(POSITION_SYMBOL);
   long tp=PositionGetInteger(POSITION_TYPE);
   MqlTick t; if(!SymbolInfoTick(sym,t)) return false;
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action=TRADE_ACTION_DEAL; req.symbol=sym; req.volume=volume; req.position=ticket;
   req.type=(tp==POSITION_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY);
   req.price=(tp==POSITION_TYPE_BUY?t.bid:t.ask);
   req.deviation=(ulong)InpDeviationPts; req.magic=(ulong)InpMagic;
   req.type_filling=Filling();
   return Send(req,res);
  }
bool CloseTicket(const ulong t)
  {
   if(!PositionSelectByTicket(t)) return false;
   return ClosePartial(t,PositionGetDouble(POSITION_VOLUME));
  }
bool ModifySL(const ulong t,const double sl,const double tp)
  {
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action=TRADE_ACTION_SLTP; req.symbol=_Symbol; req.position=t; req.sl=sl; req.tp=tp;
   return Send(req,res);
  }
void CloseBasket(const string reason)
  {
   bool any=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      CloseTicket(tk); any=true;
     }
   if(any)
     {
      LogEvent("BASKET CLOSED: "+reason);
      g_basketRisk=0.0; g_firstLot=0.0; g_basketStop=0.0;
      ArrayResize(g_partialDone,0); ArrayResize(g_beDone,0);
     }
  }
double BasketRiskUsed(void)
  {
   double used=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      double sl=PositionGetDouble(POSITION_SL);
      double op=PositionGetDouble(POSITION_PRICE_OPEN);
      double vol=PositionGetDouble(POSITION_VOLUME);
      if(sl>0.0) used+=RiskOfLots(vol,MathAbs(op-sl));
      else       used+=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPct/100.0;
     }
   return used;
  }

//--- basket-level management, run every tick while exposure exists
//--- Move every leg's stop to a level, but only ever in the winning
//    direction. A trail that can loosen is not a trail.
void TrailBasketTo(const SBasket &b,const double want,const double R)
  {
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double stops=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*pt;
   double lvl=NormalizeDouble(want,digits);

   if(g_basketTrail>0.0 && (b.dir>0 ? lvl<=g_basketTrail : lvl>=g_basketTrail)) return;
   if(b.dir>0 ? lvl>=g_view.bid-stops : lvl<=g_view.ask+stops) return;

   bool moved=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      if(sl>0.0 && (b.dir>0 ? lvl<=sl+pt : lvl>=sl-pt)) continue;
      if(ModifySL(tk,lvl,tp)) moved=true;
     }
   if(moved)
     {
      g_basketTrail=lvl;
      LogEvent(StringFormat("trail: stop moved to %.5f behind structure at %.2fR",lvl,R));
     }
  }

void ManageBasket(const SBasket &b)
  {
   if(b.count==0 || g_basketRisk<=0.0) return;
   double R=b.floatPL/g_basketRisk;

   // Past the target, a capped winner is a donated winner. If the trail is
   // armed the trade is handed to it instead of being closed: the stop is
   // already at or beyond break-even, so the downside is bounded and the
   // upside is not. That asymmetry is the only thing that pays for the spread.
   if(R>=InpBasketTargetR && !(InpRunWinners && InpTrailStructure))
     { CloseBasket(StringFormat("basket target %.2fR",R)); return; }

   // a scalp that has not resolved is dead money — release the risk
   if(InpScalpMode && b.firstTime>0)
     {
      int held=(int)((TimeCurrent()-b.firstTime)/MathMax(PeriodSeconds(g_tf),1));
      if(held>InpMaxHoldBars && R<0.3)
        { CloseBasket(StringFormat("trade timed out after %d %s bars at %.2fR",held,TfName(),R)); return; }
     }
   if(R<=-InpBasketStopR) { CloseBasket(StringFormat("basket stop %.2fR",R));  return; }

   if(InpCloseOnFlip && MSign(g_view.htfBias)!=0 && MSign(g_view.htfBias)!=b.dir &&
      MathAbs(g_view.htfBias)>=InpFlipMinBias)
     { CloseBasket("higher-timeframe bias flipped against the basket"); return; }

   if((b.dir>0 && g_view.bearChoch) || (b.dir<0 && g_view.bullChoch))
     { CloseBasket("structure shifted against the basket"); return; }

   // INVALIDATION. The trade was taken because price was at a zone that was
   // supposed to hold. When a candle CLOSES back through that zone the reason
   // is gone, and holding to the stop is paying full price for a thesis that
   // has already failed. Cutting here trims the left tail of the distribution.
   if(InpExitOnInvalid && g_basketZoneTop>g_basketZoneBottom && g_bars>2)
     {
      double pad=InpInvalidBufferPct*g_view.avgRange;
      bool dead=(b.dir>0 ? g_c[1]<g_basketZoneBottom-pad
                         : g_c[1]>g_basketZoneTop   +pad);
      if(dead)
        { CloseBasket(StringFormat("setup invalidated — closed back through the POI at %.2fR",R));
          return; }
     }

   // TRAIL BEHIND STRUCTURE. Not a fixed distance — the last swing the market
   // actually made, which is where the trade stops being right.
   if(InpTrailStructure && R>=InpTrailStartR)
     {
      double swing=(b.dir>0 ? g_view.lastSwingLow : g_view.lastSwingHigh);
      if(swing>0.0)
        {
         double want=(b.dir>0 ? swing-InpTrailBufferPct*g_view.avgRange
                              : swing+InpTrailBufferPct*g_view.avgRange);
         TrailBasketTo(b,want,R);
        }
     }

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double stops=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*pt;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double sl =PositionGetDouble(POSITION_SL);
      double tp =PositionGetDouble(POSITION_TP);
      int pd=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);

      double partialAt=(InpQuickProfit ? InpQuickPartialR : InpBasketPartialR);
      double partialPct=(InpQuickProfit ? InpQuickPartialPct : InpBasketPartialPct);
      if(InpBasketPartial && R>=partialAt && !TicketSeen(g_partialDone,tk))
        {
         double step=LotStep();
         double part=MathFloor(vol*partialPct/100.0/step+1e-9)*step;
         if(part>=MinLot() && (vol-part)>=MinLot())
           {
            if(ClosePartial(tk,part))
              {
               TicketMark(g_partialDone,tk);
               LogEvent(StringFormat("quick profit: banked %.2f of %.2f at %.2fR",part,vol,R));
               // the small win is in the account; the remainder must never
               // become a loss, so break-even goes on immediately
               if(InpBeAfterPartial) TicketMark(g_beDone,tk);
               if(InpBeAfterPartial)
                 {
                  double be=NormalizeDouble(b.avgEntry+pd*0.1*g_view.avgRange,digits);
                  bool legal=(pd>0 ? be<g_view.bid-stops : be>g_view.ask+stops);
                  if(legal) ModifySL(tk,be,tp);
                 }
              }
           }
         else TicketMark(g_partialDone,tk);
        }

      // break-even is set on the BASKET average, not on each leg
      if(InpBasketBreakEven && R>=InpBasketBeAtR && !TicketSeen(g_beDone,tk))
        {
         double be=NormalizeDouble(b.avgEntry+pd*0.1*g_view.avgRange,digits);
         bool better=(pd>0 ? (sl<=0.0||be>sl+pt) : (sl<=0.0||be<sl-pt));
         bool legal =(pd>0 ? be<g_view.bid-stops : be>g_view.ask+stops);
         if(better && legal && ModifySL(tk,be,tp))
           { TicketMark(g_beDone,tk);
             LogEvent(StringFormat("basket break-even at %.2fR (avg entry %.5f)",R,b.avgEntry)); }
        }
     }
  }

//--- a scale-in requires a fresh, independent confirmation in the same
//    direction, spacing from the last fill, and room under the basket cap
bool ScaleInAllowed(const SBasket &b)
  {
   if(!InpAllowScaleIn || b.count==0) return false;
   if(b.count>=InpMaxBasketTrades) return false;
   if(g_view.setupDir!=b.dir) return false;
   if(MathAbs(g_view.bid-b.lastPrice)<InpScaleMinSpacing*g_view.avgRange) return false;

   // ADD TO WINNERS ONLY. With six slots and no spacing to speak of, a basket
   // that kept adding while under water turned one wrong read into six. An add
   // is a second bet on an idea the market has already agreed with — so the
   // basket has to be in profit before the EA is allowed to press it.
   if(InpScaleOnlyInProfit && g_basketRisk>0.0 && b.floatPL/g_basketRisk<InpScaleMinR)
      return false;
   return true;
  }

//============================== ENTRY ===============================

void TryEnter(const SBasket &b,const bool isScale)
  {
   int dir=g_view.setupDir;
   if(dir==0) return;

   if(InpEntrySpacingSec>0 && g_lastEntry>0 &&
      (TimeCurrent()-g_lastEntry)<InpEntrySpacingSec)
     { Block("entry spacing"); return; }

   MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return;
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double stops=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*pt;
   double entry=(dir>0?t.ask:t.bid);

   double sl=g_view.stopLevel,tp=g_view.targetLevel;
   if(dir>0){ if(entry-sl<stops+pt) sl=entry-(stops+pt); if(tp-entry<stops+pt) tp=entry+(stops+pt); }
   else     { if(sl-entry<stops+pt) sl=entry+(stops+pt); if(entry-tp<stops+pt) tp=entry-(stops+pt); }
   sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);

   double dist=MathAbs(entry-sl);
   if(dist<=0.0){ Block("stop distance is zero"); return; }

   double afford=AffordableStop();
   if(afford>0.0 && dist>afford)
     {
      if(InpAutoFitStop)
        {
         double old=dist;
         dist=afford;
         double rMult=(InpScalpMode ? InpScalpTargetR : InpTpRMultiple);
         sl=NormalizeDouble(dir>0?entry-dist:entry+dist,digits);
         tp=NormalizeDouble(dir>0?entry+rMult*dist:entry-rMult*dist,digits);
         // this fires on every tick the account is too small for the structure;
         // say it once per throttle window, or when the distance actually moves
         if((TimeCurrent()-g_lastFitLog)>=InpDiagThrottleSec ||
            MathAbs(dist-g_lastFitDist)>0.05*MathMax(g_lastFitDist,1e-9))
           {
            g_lastFitLog=TimeCurrent(); g_lastFitDist=dist;
            LogEvent(StringFormat("stop tightened to fit account: %.5f -> %.5f "
                                  "(%.1fx closer than structure)",
                                  old,dist,old/MathMax(dist,1e-9)));
           }
        }
      else
        {
         Block(StringFormat("%s needs a %.5f stop, account carries %.5f at min lot "
                            "(deposit ~%.0f, or set InpAutoFitStop)",
                            g_view.setup,dist,afford,
                            RiskOfLots(MinLot(),dist)/(InpMaxRiskPctHard/100.0)));
         return;
        }
     }

   // Confluence sizes the trade. A bare POI still trades — at InpMinSizeFactor
   // of the planned risk — while a full sweep + MSS + discount + killzone
   // setup gets the whole allowance.
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double factor=(g_view.sizeFactor>0.0 ? g_view.sizeFactor : 1.0);
   double planned=eq*InpRiskPct/100.0*factor;
   double lots=NormalizeLots(LotForRisk(planned,dist));
   if(isScale && g_firstLot>0.0)
      lots=NormalizeLots(g_firstLot*MathPow(InpScaleDecay,b.count));
   if(lots<=0.0){ Block("size below broker minimum"); return; }

   // The ceiling is a solvency rail, not a confidence gate — but it was
   // rejecting its own arithmetic. InpAutoFitStop sizes the stop so that min
   // lot lands EXACTLY on the ceiling, and a strict > then failed on the last
   // bit of floating point: "risk 1.65 = 20% of equity over the 20% ceiling".
   // A trade the EA had just made affordable was refused for rounding.
   double realRisk=RiskOfLots(lots,dist);
   double riskCap =eq*InpMaxRiskPctHard/100.0;
   if(realRisk>riskCap*1.005+1e-8)
     {
      Block(StringFormat("risk %.2f = %.0f%% of equity over the %.0f%% ceiling",
                         realRisk,100.0*realRisk/MathMax(eq,0.01),InpMaxRiskPctHard));
      return;
     }
   // THE CAP THAT WAS REALLY IN CHARGE.
   //
   // The basket cap was 4% while the per-trade ceiling was 20%, and it was
   // tested against the FIRST trade with nothing else open. On a micro
   // account minimum lot risks 12-20% of equity no matter how tight the stop
   // is, so every setup the 20% ceiling had just approved was then refused by
   // a 4% cap. The ceiling was dead code; 4% was the real limit, and it
   // refused trades that were never oversized in the first place.
   //
   // A basket cap is a limit on STACKING. It cannot be tighter than the
   // ceiling that already approved the trade sitting under it.
   double basketUsed=BasketRiskUsed();
   double basketCap =eq*MathMax(InpMaxBasketRiskPct,InpMaxRiskPctHard)/100.0;
   if(InpUseBasket && basketUsed+realRisk>basketCap*1.005+1e-8)
     {
      Block(StringFormat("basket risk %.2f + %.2f over the %.0f%% basket cap",
                         basketUsed,realRisk,
                         MathMax(InpMaxBasketRiskPct,InpMaxRiskPctHard)));
      return;
     }
   if(!MarginOK(dir,lots)){ Block("insufficient free margin"); return; }

   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=lots;
   req.type=(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   req.price=entry; req.sl=sl; req.tp=tp;
   req.deviation=(ulong)InpDeviationPts; req.magic=(ulong)InpMagic;
   req.comment=(g_view.modelCode=="" ? "SMC" : g_view.modelCode);
   req.type_filling=Filling();

   if(!Send(req,res))
     {
      LogEvent(StringFormat("ORDER REJECTED: %s %.2f retcode=%u (%s)",
                            dir>0?"BUY":"SELL",lots,res.retcode,res.comment));
      Block(StringFormat("broker rejected, retcode %u",res.retcode));
      return;
     }

   if(!isScale || g_basketRisk<=0.0)
     {
      g_basketRisk=realRisk;                    // R for the whole basket
      g_firstLot=lots;
      g_basketStop=sl;
      g_basketZoneTop=g_view.zoneTop;           // the thesis, for invalidation
      g_basketZoneBottom=g_view.zoneBottom;
      g_basketTrail=0.0;
     }
   g_lastEntry=TimeCurrent();
   g_entries++;
   g_sumSpread+=MathMax(t.ask-t.bid,0.0);       // what the round trip cost
   g_sumStop  +=dist;
   g_nEntries++;
   LogTrade(dir>0?"BUY":"SELL",res.price,sl,tp,g_view.setupRR,lots,realRisk,
            b.count+1,
            StringFormat("%s | quality %.2f (%s) | POI grade %.2f | size x%.2f | htf %.2f | "
                         "pd %.0f%% | %s%s",
                         g_view.setup,g_view.quality,g_view.confluence,g_view.poiGrade,factor,
                         g_view.htfBias,g_view.pdPosition*100.0,
                         g_view.killzoneName,(isScale?" | SCALE-IN":"")));
   g_block="—";
  }

//========================== CHART OBJECTS ===========================

void ClearObjects(void)
  {
   ObjectsDeleteAll(0,"SMC_");
   g_objCount=0;
  }
void DrawBox(const string name,const datetime t1,const double p1,
             const datetime t2,const double p2,const color clr,const bool fill)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   else
     {
      ObjectMove(0,name,0,t1,p1);
      ObjectMove(0,name,1,t2,p2);
     }
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,fill);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   g_objCount++;
  }
void DrawZones(void)
  {
   if(!InpDrawObjects) return;
   ClearObjects();
   datetime now=(g_bars>0 ? g_t[0] : TimeCurrent());
   datetime fwd=now+PeriodSeconds(g_tf)*20;
   int drawn=0;
   for(int z=0;z<ArraySize(g_obs) && drawn<10;z++)
     {
      if(!g_obs[z].alive || g_obs[z].shift>=g_bars) continue;
      DrawBox(StringFormat("SMC_OB_%d",z),g_t[g_obs[z].shift],g_obs[z].top,fwd,g_obs[z].bottom,
              (g_obs[z].dir>0?clrTeal:clrFireBrick),true);
      drawn++;
     }
   drawn=0;
   for(int z=0;z<ArraySize(g_fvgs) && drawn<10;z++)
     {
      if(!g_fvgs[z].alive || g_fvgs[z].filledPct>=1.0 || g_fvgs[z].shift>=g_bars) continue;
      color c=(g_fvgs[z].dir>0 ? clrSteelBlue : clrIndianRed);
      if(g_fvgs[z].kind==GAP_BREAKAWAY)  c=(g_fvgs[z].dir>0 ? clrDodgerBlue : clrCrimson);
      if(g_fvgs[z].kind==GAP_EXHAUSTION) c=clrDimGray;
      if(g_fvgs[z].kind==GAP_VOLIMB)     c=(g_fvgs[z].dir>0 ? clrLightSeaGreen : clrPaleVioletRed);
      if(g_fvgs[z].inverted)             c=(g_fvgs[z].dir>0 ? clrMediumSpringGreen : clrOrange);
      DrawBox(StringFormat("SMC_FVG_%d",z),g_t[g_fvgs[z].shift],g_fvgs[z].top,fwd,g_fvgs[z].bottom,
              c,false);
      drawn++;
     }
  }

//========================== ANALYSIS PASS ===========================

bool Analyse(void)
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t)){ Block("no tick data"); return false; }
   if(!LoadBars()) return false;

   g_view.bid=t.bid; g_view.ask=t.ask;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   g_view.spreadPts=(pt>0.0 ? (t.ask-t.bid)/pt : 0.0);

   g_view.avgRange=AverageRange(20);
   if(g_view.avgRange<=0.0){ Block("no price movement yet"); return false; }

   BuildStructure();        // §1
   BuildOrderBlocks();      // §2
   BuildFVGs();             // §3
   BuildCandleAnatomy();    // §3f
   BuildLiquidity();        // §4
   BuildPremiumDiscount();  // §5
   BuildKillzone();         // §6
   BuildHtfBias();          // §7
   FindSetup();             // the model
   return true;
  }

//======================== SELF-TEST & PANEL =========================

//--- PARAMETER AUDIT.
//
//    A saved .set file silently overrides the build defaults for every input
//    that already existed under the same name. It happened once before, between
//    v4.10 and v5.00: the tester reloaded InpHtfMinAgreement=0.34 and friends
//    over a build whose defaults had all been relaxed, and the EA idled for a
//    whole session while the code on disk said otherwise.
//
//    Recompiling cannot fix that, because the .set is applied AFTER the build.
//    So the EA now states what is actually in force and says plainly when it
//    does not match the build it was compiled from.
int AuditD(const string name,const double have,const double want)
  {
   if(MathAbs(have-want)<1e-9) return 0;
   LogEvent(StringFormat("  *** %-20s = %-10.4f  build ships %.4f",name,have,want));
   return 1;
  }
int AuditI(const string name,const int have,const int want)
  {
   if(have==want) return 0;
   LogEvent(StringFormat("  *** %-20s = %-10d  build ships %d",name,have,want));
   return 1;
  }
int AuditB(const string name,const bool have,const bool want)
  {
   if(have==want) return 0;
   LogEvent(StringFormat("  *** %-20s = %-10s  build ships %s",name,
                         (have?"true":"false"),(want?"true":"false")));
   return 1;
  }

void ParamAudit(void)
  {
   int d=0;
   if(InpTimeframe!=PERIOD_H1)
      { LogEvent(StringFormat("  *** %-20s = %-10s  build ships PERIOD_H1",
                              "InpTimeframe",EnumToString(InpTimeframe))); d++; }
   d+=AuditI("InpMaxHoldBars"    ,InpMaxHoldBars    ,18);
   d+=AuditD("InpScalpTargetR"   ,InpScalpTargetR   ,2.0);
   d+=AuditB("InpHtfH4"          ,InpHtfH4          ,true);
   d+=AuditB("InpHtfD1"          ,InpHtfD1          ,true);
   d+=AuditB("InpFastConfirm"    ,InpFastConfirm    ,true);
   d+=AuditB("InpQuickProfit"    ,InpQuickProfit    ,true);
   d+=AuditD("InpQuickPartialR"  ,InpQuickPartialR  ,0.50);
   d+=AuditD("InpTrailStartR"    ,InpTrailStartR    ,0.70);
   d+=AuditB("InpConfirmModel"   ,InpConfirmModel   ,true);
   d+=AuditB("InpRequireRetrace" ,InpRequireRetrace ,true);
   d+=AuditB("InpRequireConfirm" ,InpRequireConfirm ,true);
   d+=AuditD("InpImpulseMinPct"  ,InpImpulseMinPct  ,0.35);
   d+=AuditD("InpMinRoomR"       ,InpMinRoomR       ,1.50);
   d+=AuditB("InpTakeEveryPOI"   ,InpTakeEveryPOI   ,false);
   d+=AuditD("InpFvgMinPct"      ,InpFvgMinPct      ,0.02);
   d+=AuditD("InpMinTargetSpreads",InpMinTargetSpreads,2.00);
   d+=AuditB("InpTradePaCandles" ,InpTradePaCandles ,false);
   d+=AuditB("InpNextCandleEntry",InpNextCandleEntry,false);
   d+=AuditB("InpTwoCandleEntry" ,InpTwoCandleEntry ,false);
   d+=AuditD("InpWeightAnatomy"  ,InpWeightAnatomy  ,0.16);
   d+=AuditI("InpNextCandleBars" ,InpNextCandleBars ,2);
   d+=AuditD("InpPaBodyPct"      ,InpPaBodyPct      ,0.55);
   d+=AuditD("InpPaRangeMult"    ,InpPaRangeMult    ,0.90);
   d+=AuditI("InpPaMaxAge"       ,InpPaMaxAge       ,6);
   d+=AuditI("InpMaxFVGs"        ,InpMaxFVGs        ,40);
   d+=AuditB("InpUseVolumeImb"   ,InpUseVolumeImb   ,true);
   d+=AuditB("InpUseInversionFvg",InpUseInversionFvg,true);
   d+=AuditB("InpFvgTargetPull"  ,InpFvgTargetPull  ,true);
   d+=AuditB("InpBestPoi"        ,InpBestPoi        ,true);
   d+=AuditB("InpTradeFreshGaps" ,InpTradeFreshGaps ,false);
   d+=AuditI("InpFreshGapMaxAge" ,InpFreshGapMaxAge ,5);
   d+=AuditD("InpFreshGapMaxRun" ,InpFreshGapMaxRun ,2.50);
   d+=AuditB("InpFreshGapSkipExh",InpFreshGapSkipExh,true);
   d+=AuditD("InpCounterTrendFac",InpCounterTrendFac,0.50);
   d+=AuditB("InpScaleOnlyInProfit",InpScaleOnlyInProfit,true);
   d+=AuditI("InpEntrySpacingSec",InpEntrySpacingSec,0);
   d+=AuditD("InpQualityFloor"   ,InpQualityFloor   ,0.00);
   d+=AuditD("InpFvgGradeFloor"  ,InpFvgGradeFloor  ,0.00);
   d+=AuditD("InpMinSizeFactor"  ,InpMinSizeFactor  ,0.40);
   d+=AuditD("InpWeightPoiGrade" ,InpWeightPoiGrade ,0.20);
   d+=AuditI("InpMaxBasketTrades",InpMaxBasketTrades,6);
   d+=AuditD("InpScaleMinSpacing",InpScaleMinSpacing,0.25);
   d+=AuditD("InpMaxRiskPctHard" ,InpMaxRiskPctHard ,20.0);
   d+=AuditI("InpBreakerMinLosses",InpBreakerMinLosses,3);
   d+=AuditD("InpMaxDDPct"       ,InpMaxDDPct       ,35.0);
   d+=AuditD("InpMaxAccountDDPct",InpMaxAccountDDPct,60.0);
   d+=AuditB("InpAutoFitStop"    ,InpAutoFitStop    ,true);
   d+=AuditD("InpMinStopSpreads" ,InpMinStopSpreads ,4.00);
   d+=AuditB("InpTrailStructure" ,InpTrailStructure ,true);
   d+=AuditD("InpTrailStartR"    ,InpTrailStartR    ,1.00);
   d+=AuditB("InpRunWinners"     ,InpRunWinners     ,true);
   d+=AuditB("InpExitOnInvalid"  ,InpExitOnInvalid  ,true);

   if(d==0)
     {
      LogEvent("parameter audit: CLEAN — every input matches this build.");
      return;
     }
   LogEvent(StringFormat("*** PARAMETER AUDIT: %d INPUT%s ABOVE DO NOT MATCH THIS BUILD ***",
                         d,(d==1?"":"S")));
   LogEvent("*** A saved .set is being applied over the compiled defaults. Recompiling ***");
   LogEvent("*** cannot fix this — the .set loads afterwards. In the Strategy Tester    ***");
   LogEvent("*** Inputs tab press Reset/Default (or delete the saved set), then re-run. ***");
  }

void SelfTest(void)
  {
   if(!InpSelfTest) return;
   LogEvent("────────── PRICE ACTION SELF-TEST ──────────");
   LogEvent(StringFormat("PRICE ACTION ENGINE — every read comes from raw OHLC on %s. No "
                         "indicator handle and no CopyBuffer call exists in this file.",
                         TfName()));
   LogEvent("candle reads: body share, upper/lower wick, close position, marubozu, doji, "
            "engulfing, harami, pin bar, tweezer, morning/evening star, inside bar, "
            "outside bar, directional run.");
   LogEvent("structure reads: fractal swings, BOS, CHoCH, MSS, displacement, imbalance "
            "(fair value gaps), order blocks, breakers, liquidity pools and sweeps, "
            "dealing range and OTE.");
   LogEvent("build: Medula_SMC v5.24  —  if the panel does not read v5.24, MT5 is "
            "running an older .ex5 and the source was never recompiled.");
   ParamAudit();
   LogEvent(StringFormat("symbol %s  execution timeframe %s  bars loaded %d  (NO INDICATORS)",
                         _Symbol,TfName(),g_bars));
   LogEvent(StringFormat("average range %.5f  spread %.0f pts",g_view.avgRange,g_view.spreadPts));
   LogEvent(StringFormat("structure dir %d | order blocks %d | FVGs %d (%d breakaway, %d inverted) "
                         "| liquidity pools %d",
                         g_view.structDir,g_view.obCount,g_view.fvgCount,
                         g_view.bagCount,g_view.invCount,g_view.liqCount));
   LogEvent(StringFormat("gap model: graded breakaway/measuring/exhaustion, partial fill tracked, "
                         "inversion %s, gaps as targets %s, best-POI selection %s",
                         (InpUseInversionFvg?"on":"off"),
                         (InpFvgTargetPull  ?"on":"off"),
                         (InpBestPoi        ?"on":"off")));
   if(InpConfirmModel)
     {
      LogEvent("MODEL: CONFIRMED RETRACEMENT. 1) trend  2) impulse leaves a meaningful "
               "imbalance  3) price RETRACES INTO the gap  4) price-action confirmation "
               "prints  5) enter. The gap forming is not an entry.");
      LogEvent(StringFormat("avoid: ranging market %s | structure contradicts %s | strong "
                            "momentum against the retrace %s | less than %.1fR of room %s",
                            (InpAvoidRanging?"YES":"no"),
                            (InpAvoidStructAgainst?"YES":"no"),
                            (InpAvoidMomentumAgainst?"YES":"no"),
                            InpMinRoomR,(InpConfirmModel?"YES":"no")));
      LogEvent("§3b fresh gaps, §3c displacement candles, §3d next candle and §3e the "
               "two-candle trigger are all OFF while this model is on — they enter the "
               "moment the imbalance appears, which this model forbids.");
      LogEvent("note: on intraday forex and metals, TRUE breakaway gaps are rare (weekly opens, "
               "news). Fair value gaps are the applicable pattern and carry the model.");
     }
   if(InpTakeEveryPOI)
     {
      LogEvent("MANDATE: TAKE EVERY POI. Every live FVG, breakaway gap and order block is "
               "executed — small or large, high grade or low. Grade sets the SIZE, never "
               "the permission.");
      LogEvent("The ONLY things that can refuse a trade: the per-trade risk ceiling, the "
               "basket cap, free margin, and the circuit breaker. No hour of the day, no "
               "session, no killzone, no HTF bias, no confidence level and no grade floor "
               "can stand this EA down.");
      if(InpQualityFloor>0.0 || InpFvgGradeFloor>0.0 || InpFreshGapMinGrade>0.0)
         LogEvent("(quality and grade floors are overridden to zero by the mandate — "
                  "set InpTakeEveryPOI=false to honour them)");
      LogEvent("The mandate governs how much CERTAINTY is required, never which way a "
               "setup points. Exhaustion gaps stay targets, counter-trend setups still "
               "trade but at half size, and adds still require a winning basket.");
     }
   LogEvent(StringFormat("killzones: SCORING ONLY — London/NY/London-close raise the size a "
                         "setup earns (weight %.2f) and can never refuse one. Outside every "
                         "session the EA still trades.",InpWeightKillzone));
   LogEvent(StringFormat("risk rails: %.0f%% ceiling on one trade, %.0f%% on the whole basket "
                         "(a basket cap below the per-trade ceiling would refuse trades the "
                         "ceiling had just approved, so the larger of the two governs)",
                         InpMaxRiskPctHard,MathMax(InpMaxBasketRiskPct,InpMaxRiskPctHard)));
   LogEvent(StringFormat("smallest gap the EA will see: %.5f (%.2f x avg range). The spread "
                         "no longer filters ENTRIES — it only stretches the target, so small "
                         "gaps are detected and traded.",
                         MathMax(InpFvgMinPct*g_view.avgRange,_Point),InpFvgMinPct));
   if(InpNextCandleEntry)
      LogEvent(StringFormat("next candle (§3d): ON — any gap under %d bars old is traded on "
                            "the following candle with NO further condition: no buffer test, "
                            "no run limit, no grade test. Tagged NEXT in the journal.",
                            InpNextCandleBars));
   if(InpTradePaCandles)
      LogEvent(StringFormat("price action (§3c): ON — any candle with a body >= %.0f%% of its "
                            "range covering >= %.2f x avg range is a setup on its own, gap or "
                            "no gap, for %d bars.",
                            InpPaBodyPct*100.0,InpPaRangeMult,InpPaMaxAge));
   if(InpTradeFreshGaps)
      LogEvent(StringFormat("fresh gaps: ON — any gap (breakaway or plain FVG) under %d bars old "
                            "trades on the following candle, no retrace required, "
                            "while price is within %.2f x avg range of it",
                            InpFreshGapMaxAge,InpFreshGapMaxRun));
   else
      LogEvent("fresh gaps: OFF — the EA only trades retracements back into a POI");
   LogEvent(StringFormat("HTF bias %.2f (scored, never required) | killzone %s | range position %.0f%%",
                         g_view.htfBias,g_view.killzoneName,g_view.pdPosition*100.0));
   LogEvent(StringFormat("gating: ONE hard condition — price inside a live FVG/order block. "
                         "HTF, sweep, structure, premium/discount, OTE and killzone only SIZE "
                         "the trade (%.0f%%..100%% of planned risk).",InpMinSizeFactor*100.0));
   if(InpQualityFloor>0.0)
      LogEvent(StringFormat("*** InpQualityFloor is %.2f — setups below that quality WILL be "
                            "refused. Set it to 0 for a pure never-block model. ***",
                            InpQualityFloor));
   LogEvent(StringFormat("broker: min lot %.2f  contract %.0f  digits %d  stops level %d",
                         MinLot(),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),
                         (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS),
                         (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)));

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double afford=AffordableStop();
   LogEvent(StringFormat("account: equity %.2f  leverage 1:%d  algo trading %s",
                         eq,(int)AccountInfoInteger(ACCOUNT_LEVERAGE),
                         (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"ENABLED":"DISABLED")));
   LogEvent(StringFormat("widest stop this account can carry at min lot: %.5f (%.2f x avg range)",
                         afford,(g_view.avgRange>0.0?afford/g_view.avgRange:0.0)));
   double needStop=(InpStopBeyondPOI||InpScalpMode ? 1.0+InpPoiStopBuffer : 3.0)*g_view.avgRange;
   if(afford<needStop && !InpAutoFitStop)
      LogEvent(StringFormat("*** WARNING: this profile needs about %.1f x average range of stop and "
                            "the account carries %.1f x at min lot. Set InpAutoFitStop=true (default) "
                            "or deposit about %.0f. ***",
                            needStop/MathMax(g_view.avgRange,1e-9),
                            (g_view.avgRange>0.0?afford/g_view.avgRange:0.0),
                            RiskOfLots(MinLot(),needStop)/(InpMaxRiskPctHard/100.0)));
   LogEvent("─────────────────────────────────────────");
  }

void Panel(const SBasket &b)
  {
   if(!InpShowPanel) return;
   string sweep="none";
   if(g_view.sweptSellside) sweep=StringFormat("SELLSIDE @ %.5f (%d bars ago)",
                                               g_view.sweepLevel,g_view.sweepAgeBars);
   else if(g_view.sweptBuyside) sweep=StringFormat("BUYSIDE @ %.5f (%d bars ago)",
                                                   g_view.sweepLevel,g_view.sweepAgeBars);
   string mss="none";
   if(g_view.bullMss) mss="BULLISH MSS";
   else if(g_view.bearMss) mss="BEARISH MSS";
   else if(g_view.bullBos) mss="bullish BOS";
   else if(g_view.bearBos) mss="bearish BOS";

   Comment(StringFormat(
      "MEDULA v5.24  PRICE ACTION  |  %s  %s\n"
      "no indicators — filters SIZE the trade, they never block it\n"
      "──────────────────────────────────────────\n"
      "HTF bias      %+5.2f  (scored, not required)\n"
      "structure     dir %+d   %s\n"
      "liquidity     %s\n"
      "order blocks  %d      FVGs %d      pools %d\n"
      "gaps          %d breakaway   %d inverted   %d fresh\n"
      "dealing range %.5f - %.5f\n"
      "position      %.0f%% (%s%s)\n"
      "killzone      %s\n"
      "nearest POI   %.2f x avg range away\n"
      "──────────────────────────────────────────\n"
      "SETUP   %s\n"
      "quality %.2f  [%s]  ->  size x%.2f   POI grade %.2f\n"
      "zone    %.5f - %.5f\n"
      "sl %.5f  tp %.5f  RR %.2f\n"
      "──────────────────────────────────────────\n"
      "BASKET  %d trades  vol %.2f  avg %.5f\n"
      "        float %.2f   R %.2f   risk unit %.2f\n"
      "entries %d   spread %.0f pts\n"
      "status  %s",
      _Symbol,TfName(),
      g_view.htfBias,
      g_view.structDir,mss,
      sweep,
      g_view.obCount,g_view.fvgCount,g_view.liqCount,
      g_view.bagCount,g_view.invCount,g_view.freshCount,
      g_view.rangeLow,g_view.rangeHigh,
      g_view.pdPosition*100.0,
      (g_view.inDiscount?"discount":"premium"),(g_view.inOte?", OTE":""),
      g_view.killzoneName,
      g_view.poiDistance,
      g_view.setup,
      g_view.quality,(g_view.confluence==""?"-":g_view.confluence),g_view.sizeFactor,
      g_view.poiGrade,
      g_view.zoneBottom,g_view.zoneTop,
      g_view.stopLevel,g_view.targetLevel,g_view.setupRR,
      b.count,b.volume,b.avgEntry,
      b.floatPL,(g_basketRisk>0.0?b.floatPL/g_basketRisk:0.0),g_basketRisk,
      g_entries,g_view.spreadPts,
      g_block));
  }

//========================== EVENT HANDLERS ==========================

int OnInit(void)
  {
   LogInit();
   ArrayResize(g_partialDone,0); ArrayResize(g_beDone,0);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEquity=eq; g_peakEquity=eq; g_dayKey=-1;
   g_breaker=false; g_fatal=false; g_lastBar=0; g_lastEntry=0; g_entries=0;
   g_lifetimePeak=0.0; g_lastTickTime=0; g_secBlocked=0.0; g_secTotal=0.0;
   g_basketRisk=0.0; g_firstLot=0.0;
   g_block="warming up";

   // PERIOD_CURRENT means "whatever chart it is on"; anything else overrides
   g_tf=(InpTimeframe==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : InpTimeframe);
   RiskUpdate();

   if(_Period!=g_tf)
      LogEvent(StringFormat("NOTE: attached to a %s chart but this EA reads %s for "
                            "execution regardless of the chart timeframe",
                            EnumToString((ENUM_TIMEFRAMES)_Period),TfName()));

   if(Analyse()) SelfTest();
   LogEvent("v5.00 SMC/ICT scalper ready — one hard condition (price in a live POI), "
            "confluence sizes the trade, basket manager active");
   return INIT_SUCCEEDED;
  }

//--- THE ONLY REPORT THAT MATTERS.
//
//    Four entry models now compete for the same capital: retrace into a POI,
//    fresh gap continuation, displacement candle, and order block — each with
//    sub-classes. Without per-model accounting, tuning any of them is
//    guesswork: a profitable model and a bleeding one net out to a flat curve
//    and the log looks the same either way.
//
//    Each fill carries its model tag in the deal comment, so the run can be
//    taken apart afterwards and the question answered directly: which of
//    these actually earns?
void Report(void)
  {
   if(!HistorySelect(0,TimeCurrent()+1)) return;

   string codes[]; int n=0;
   double win[],loss[]; int nWin[],nLoss[];
   ArrayResize(codes,0); ArrayResize(win,0); ArrayResize(loss,0);
   ArrayResize(nWin,0); ArrayResize(nLoss,0);

   int    tot=0,wins=0,losses=0;
   double gross=0.0,grossWin=0.0,grossLoss=0.0;
   double holdSum=0.0; int holdN=0;

   int deals=HistoryDealsTotal();

   // first pass: when each position was opened, so holding time can be measured
   ulong    posId[]; datetime posIn[];
   ArrayResize(posId,0); ArrayResize(posIn,0);
   for(int i=0;i<deals;i++)
     {
      ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagic) continue;
      if(HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      int m=ArraySize(posId);
      ArrayResize(posId,m+1); ArrayResize(posIn,m+1);
      posId[m]=(ulong)HistoryDealGetInteger(tk,DEAL_POSITION_ID);
      posIn[m]=(datetime)HistoryDealGetInteger(tk,DEAL_TIME);
     }
   for(int i=0;i<deals;i++)
     {
      ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagic) continue;
      if(HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;

      double net=HistoryDealGetDouble(tk,DEAL_PROFIT)
                +HistoryDealGetDouble(tk,DEAL_SWAP)
                +HistoryDealGetDouble(tk,DEAL_COMMISSION);
      string code=HistoryDealGetString(tk,DEAL_COMMENT);
      if(code=="") code="(untagged)";

      ulong pid=(ulong)HistoryDealGetInteger(tk,DEAL_POSITION_ID);
      datetime outT=(datetime)HistoryDealGetInteger(tk,DEAL_TIME);
      for(int m=0;m<ArraySize(posId);m++)
         if(posId[m]==pid)
           { holdSum+=(double)(outT-posIn[m]); holdN++; break; }

      tot++; gross+=net;
      if(net>=0.0){ wins++;   grossWin +=net; }
      else        { losses++; grossLoss+=-net; }

      int at=-1;
      for(int z=0;z<n;z++) if(codes[z]==code){ at=z; break; }
      if(at<0)
        {
         at=n++;
         ArrayResize(codes,n); ArrayResize(win,n); ArrayResize(loss,n);
         ArrayResize(nWin,n);  ArrayResize(nLoss,n);
         codes[at]=code; win[at]=0.0; loss[at]=0.0; nWin[at]=0; nLoss[at]=0;
        }
      if(net>=0.0){ win[at] +=net;  nWin[at]++;  }
      else        { loss[at]+=-net; nLoss[at]++; }
     }

   LogEvent("═════════════ RUN REPORT ═════════════");

   // FIRST, because it invalidates everything below it. An EA that was stood
   // down for most of the run did not produce a verdict on its model — it
   // produced a verdict on its risk rails, and no entry tuning is visible in
   // a period it was never allowed to trade.
   if(g_secTotal>0.0)
     {
      double pct=100.0*g_secBlocked/g_secTotal;
      LogEvent(StringFormat("time allowed to trade: %.1f%%  (stood down by the circuit "
                            "breaker for %.1f%% of the run)",100.0-pct,pct));
      if(pct>=25.0)
         LogEvent("*** The EA spent most of the run disabled. Whatever this report says "
                  "about the entry model, it was measured on the fraction of the history "
                  "it was permitted to trade. Fix the rails before reading anything else. ***");
     }
   if(g_fatal)
      LogEvent("*** the account drawdown rail stopped trading permanently during this run ***");

   if(tot==0)
     {
      LogEvent("no closed trades this run.");
      LogEvent("══════════════════════════════════════");
      return;
     }

   double pf=(grossLoss>0.0 ? grossWin/grossLoss : 0.0);
   LogEvent(StringFormat("trades %d | won %d (%.0f%%) | lost %d | net %.2f | "
                         "profit factor %.2f | expectancy %.4f per trade",
                         tot,wins,100.0*wins/tot,losses,gross,pf,gross/tot));
   LogEvent(StringFormat("average win %.4f | average loss %.4f | win/loss size ratio %.2f",
                         (wins  >0 ? grossWin /wins   : 0.0),
                         (losses>0 ? grossLoss/losses : 0.0),
                         (losses>0 && wins>0 ? (grossWin/wins)/(grossLoss/losses) : 0.0)));

   // The number that decides whether any of this can work.
   if(g_nEntries>0)
     {
      double avgSpread=g_sumSpread/g_nEntries,avgStop=g_sumStop/g_nEntries;
      double bite=(avgStop>0.0 ? 100.0*avgSpread/avgStop : 0.0);
      LogEvent(StringFormat("COST: average spread %.5f against an average stop of %.5f — "
                            "the spread is %.0f%% of your risk on every trade.",
                            avgSpread,avgStop,bite));
      if(bite>=25.0)
         LogEvent("*** Above ~25% the spread, not the model, decides the outcome. Widen "
                  "InpMinStopSpreads, or trade a symbol/account with a tighter spread. ***");
     }

   if(holdN>0)
      LogEvent(StringFormat("SPEED: average time in a trade %.1f minutes (%.1f %s bars)",
                            holdSum/holdN/60.0,
                            holdSum/holdN/MathMax(PeriodSeconds(g_tf),1),TfName()));
   LogEvent("───────── by entry model ─────────");
   for(int z=0;z<n;z++)
     {
      int    cnt=nWin[z]+nLoss[z];
      double net=win[z]-loss[z];
      LogEvent(StringFormat("  %-10s trades %3d | won %3d (%3.0f%%) | net %8.2f | "
                            "PF %5.2f | expectancy %.4f",
                            codes[z],cnt,nWin[z],(cnt>0?100.0*nWin[z]/cnt:0.0),net,
                            (loss[z]>0.0?win[z]/loss[z]:0.0),(cnt>0?net/cnt:0.0)));
     }
   LogEvent("(F- prefix = fresh continuation entry, no retrace waited for)");
   LogEvent("══════════════════════════════════════");
  }

void OnDeinit(const int reason)
  {
   Comment("");
   ClearObjects();
   LogEvent(StringFormat("stopped (reason %d) — entries this run: %d",reason,g_entries));
   Report();
   LogClose();
  }

void OnTick(void)
  {
   // how much of the run the EA actually spent allowed to trade
   datetime nowT=TimeCurrent();
   if(g_lastTickTime>0)
     {
      double dts=(double)(nowT-g_lastTickTime);
      if(dts>0.0 && dts<3600.0){ g_secTotal+=dts; if(g_breaker||g_fatal) g_secBlocked+=dts; }
     }
   g_lastTickTime=nowT;

   RiskUpdate();

   SBasket b; GetBasket(b);
   if(b.count==0 && g_basketRisk>0.0)
     {
      g_basketRisk=0.0; g_firstLot=0.0;
      g_basketZoneTop=0.0; g_basketZoneBottom=0.0; g_basketTrail=0.0;
      ArrayResize(g_partialDone,0); ArrayResize(g_beDone,0);
     }

   if(CircuitBreaker())
     {
      if(b.count>0) CloseBasket("risk circuit breaker");
      if(!g_breakerLogged){ LogEvent("CIRCUIT BREAKER ACTIVE"); g_breakerLogged=true; }
      g_block="circuit breaker";
      Panel(b);
      return;
     }
   g_breakerLogged=false;

   if(!Analyse()){ Panel(b); return; }

   datetime cur=(g_bars>0?g_t[0]:0);
   bool newBar=(cur!=g_lastBar && cur>0);
   if(newBar){ g_lastBar=cur; DrawZones(); LogGaps(); }

   if(b.count>0)
     {
      ManageBasket(b);
      GetBasket(b);
     }

   if(g_view.setupDir==0)
     {
      Block(MissingLeg());
      Panel(b);
      return;
     }

   if(b.count==0)                       TryEnter(b,false);
   else if(ScaleInAllowed(b))           TryEnter(b,true);
   else                                 g_block="holding basket";

   Panel(b);
  }
//+------------------------------------------------------------------+
