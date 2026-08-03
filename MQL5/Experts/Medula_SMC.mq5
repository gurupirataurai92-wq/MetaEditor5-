//+------------------------------------------------------------------+
//|                                                   Medula_SMC.mq5 |
//|  Medula v5.11 — Smart Money Concepts / ICT.  M5 execution.       |
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
//+------------------------------------------------------------------+
#property copyright "Medula Project"
#property version   "5.11"

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

input group "Market Structure (§1)"
input int    InpBars            = 500;     // Bars of M5 history analysed
input int    InpSwingK          = 2;       // Fractal wing size
input double InpBosBufferPct    = 0.05;    // Break must clear by this share of avg range
input int    InpStructureLookback = 60;    // Bars searched for the structure shift

input group "Order Blocks (§2)"
input bool   InpUseOrderBlocks  = true;    // Trade order-block returns
input int    InpMaxOrderBlocks  = 20;      // Order blocks tracked per side
input int    InpObMaxAgeBars    = 300;     // Forget order blocks older than this
input double InpObMitigatedPct  = 50.0;    // Mitigated once price fills this % of it
input bool   InpUseBreakers     = true;    // Trade breaker blocks (failed OB that flips)

input group "Fair Value Gaps (§3)"
input bool   InpUseFVG          = true;    // Trade FVG returns
input int    InpMaxFVGs         = 20;      // FVGs tracked
input int    InpFvgMaxAgeBars   = 200;     // Forget FVGs older than this
input double InpFvgMinPct       = 0.25;    // Gap must be >= this share of avg range
input double InpFvgFillPct      = 50.0;    // Reported as consumed past this % (CE)
input bool   InpUseInversionFvg = true;    // A violated gap inverts and keeps trading (IFVG)
input double InpBagDisplaceMult = 1.80;    // Breakaway gap: its candle >= this x avg range
input double InpBagMaxRunIn     = 1.50;    // Breakaway only if the run into it is under this
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
input group "Fresh Gap Continuation (§3b)"
input bool   InpTradeFreshGaps  = true;    // Trade the candle after a gap prints (no retrace needed)
input int    InpFreshGapMaxAge  = 3;       // A gap counts as fresh for this many bars
input double InpFreshGapMaxRun  = 1.25;    // Stop chasing once price has run this far past it
input bool   InpFreshGapSkipExh = true;    // Never chase an exhaustion gap
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

input group "Higher Timeframe Bias (§7)"
input bool   InpHtfM15          = true;    // Include M15 structure
input bool   InpHtfH1           = true;    // Include H1 structure
input bool   InpHtfH4           = true;    // Include H4 structure

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
input double InpQualityFloor    = 0.00;    // Refuse below this quality (0 = never refuse)
input double InpFlipMinBias     = 0.35;    // HTF bias that counts as a flip against a basket

input group "Scalp Mode"
input bool   InpScalpMode       = true;    // Scalper profile: POI stops, quick targets
input bool   InpStopBeyondPOI   = true;    // Stop just past the FVG/OB, not past the sweep
input double InpPoiStopBuffer   = 0.30;    // Stop beyond the POI by this x average range
input double InpScalpTargetR    = 1.6;     // Scalp target in R
input int    InpMaxHoldBars     = 24;      // Close a scalp after this many M5 bars

input group "Entries"
input bool   InpEntryOnFVG      = true;    // Enter on FVG return
input bool   InpEntryOnOB       = true;    // Enter on order-block return
input double InpEntryZoneBuffer = 0.25;    // Zone widened by this share of avg range
input int    InpEntrySpacingSec = 60;      // Min seconds between entries
input int    InpMaxSetupAgeBars = 40;      // Structure shift counts for this many bars

input group "Risk"
input double InpRiskPct         = 1.0;     // Risk per trade (% equity)
input double InpSlBufferPct     = 0.25;    // Stop beyond the sweep by this x avg range
input double InpTargetMinRR     = 1.20;    // Target is never set closer than this R
input double InpTpRMultiple     = 3.0;     // Target when no liquidity pool is in range
input double InpDailyLossPct    = 5.0;     // Daily loss limit (%)
input int    InpBreakerMinLosses= 3;       // Losing trades before the daily limit latches
input double InpMaxDDPct        = 20.0;    // Max drawdown from peak (%)
input double InpMaxRiskPctHard  = 20.0;    // ABSOLUTE ceiling on one trade (% equity)
input double InpMarginSafety    = 1.2;     // Free-margin safety factor
input bool   InpAllowMinLot     = true;    // Round up to broker minimum lot
input bool   InpAutoFitStop     = true;    // Tighten stop so min lot fits the ceiling

input group "Basket Manager (§9)"
input bool   InpUseBasket       = true;    // Manage positions as one basket
input int    InpMaxBasketTrades = 4;       // Max positions in a basket
input double InpBasketTargetR   = 1.6;     // Close the basket at this R
input double InpBasketStopR     = 1.5;     // Close the basket at this loss in R
input double InpMaxBasketRiskPct= 4.0;     // Max combined basket risk (% equity)
input bool   InpBasketBreakEven = true;    // Move basket to break-even in profit
input double InpBasketBeAtR     = 0.5;     // Break-even trigger (R)
input bool   InpBasketPartial   = true;    // Partial close at the first target
input double InpBasketPartialR  = 0.6;     // Partial trigger (R)
input double InpBasketPartialPct= 50.0;    // Percent of volume closed
input bool   InpAllowScaleIn    = true;    // Add on a fresh confirmation
input double InpScaleDecay      = 0.6;     // Lot decay per add
input double InpScaleMinSpacing = 0.75;    // Min spacing between adds (x avg range)
input bool   InpCloseOnFlip     = true;    // Close basket when HTF bias flips

//========================= TYPES & HELPERS ==========================

enum ENUM_DEC { DEC_WAIT=0, DEC_BUY, DEC_SELL, DEC_HOLD, DEC_EXIT };

double MClamp(const double x,const double lo,const double hi){ return MathMin(MathMax(x,lo),hi); }
int    MSign(const double x){ if(x>0.0) return 1; if(x<0.0) return -1; return 0; }

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
   GAP_EXHAUSTION =2    // printed into a pool on an extended run — a target, not an entry
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
   string            model,confluence;
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

SOB      g_obs[];
SFVG     g_fvgs[];
SLIQ     g_liqs[];
SView    g_view;

double   g_basketRisk=0.0;          // R unit for the whole basket
double   g_firstLot=0.0;
double   g_basketStop=0.0;
ulong    g_partialDone[],g_beDone[];

double   g_dayStartEquity=0.0,g_peakEquity=0.0;
int      g_dayKey=-1;
datetime g_dayStart=0;
datetime g_lastFitLog=0;
double   g_lastFitDist=0.0;
bool     g_breaker=false,g_breakerLogged=false;

datetime g_lastBar=0,g_lastEntry=0;
int      g_logHandle=INVALID_HANDLE;
string   g_block="starting",g_lastBlock="";
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
   int got=CopyHigh(_Symbol,PERIOD_M5,0,InpBars,g_h);
   if(got<120){ Block(StringFormat("only %d M5 bars loaded, need 120+",got)); return false; }
   if(CopyLow(_Symbol,PERIOD_M5,0,got,g_l)<got)   return false;
   if(CopyOpen(_Symbol,PERIOD_M5,0,got,g_o)<got)  return false;
   if(CopyClose(_Symbol,PERIOD_M5,0,got,g_c)<got) return false;
   if(CopyTime(_Symbol,PERIOD_M5,0,got,g_t)<got)  return false;
   if(CopyTickVolume(_Symbol,PERIOD_M5,0,got,g_v)<got) ArrayInitialize(g_v,1);
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

   int scan=MathMin(g_bars-4,InpObMaxAgeBars);
   for(int i=scan;i>=1;i--)
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
   if(bos && strength>=InpBagDisplaceMult && runIn<=InpBagMaxRunIn+strength)
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
                      g_fvgs[z].kind==GAP_EXHAUSTION ? 0.15 : 0.60);
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
   return "FVG";
  }

void PushFVG(const double top,const double bottom,const int dir,const int i)
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
   g_fvgs[n].kind=ClassifyGap(i,dir,strength);
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
   double minGap=InpFvgMinPct*g_view.avgRange;

   int scan=MathMin(g_bars-3,InpFvgMaxAgeBars);
   for(int i=scan;i>=1;i--)
     {
      // bullish: low of the newer candle above the high of the older one
      if(g_l[i-1]-g_h[i+1]>=minGap) PushFVG(g_l[i-1],g_h[i+1], 1,i);
      if(g_l[i+1]-g_h[i-1]>=minGap) PushFVG(g_l[i+1],g_h[i-1],-1,i);
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
      if(g_fvgs[z].grade<InpFvgGradeFloor) g_fvgs[z].alive=false;
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
   if(InpHtfM15){ sum+=0.25*HtfStructure(PERIOD_M15); w+=0.25; }
   if(InpHtfH1) { sum+=0.35*HtfStructure(PERIOD_H1);  w+=0.35; }
   if(InpHtfH4) { sum+=0.40*HtfStructure(PERIOD_H4);  w+=0.40; }
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
   double risk=MathAbs(px-far)/MathMax(g_view.avgRange,1e-9);
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

   if(InpEntryOnFVG && InpUseFVG)
      for(int z=0;z<ArraySize(g_fvgs);z++)
        {
         if(!g_fvgs[z].alive || g_fvgs[z].filledPct>=1.0) continue;
         if(g_fvgs[z].dir!=dir) continue;
         if(g_fvgs[z].shift>InpFvgMaxAgeBars) continue;
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
   if(InpTradeFreshGaps && InpUseFVG && (InpBestPoi || zt<=0.0))
      for(int z=0;z<ArraySize(g_fvgs);z++)
        {
         if(!g_fvgs[z].alive || g_fvgs[z].filledPct>=1.0) continue;
         if(g_fvgs[z].dir!=dir) continue;
         if(g_fvgs[z].shift>InpFreshGapMaxAge) continue;
         if(g_fvgs[z].grade<InpFreshGapMinGrade) continue;
         if(InpFreshGapSkipExh && g_fvgs[z].kind==GAP_EXHAUSTION) continue;

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

   if(zt<=0.0) return false;                 // nothing to trade — the only veto

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

   double wsum=InpWeightHtf+InpWeightStructure+InpWeightSweep+
               InpWeightPD +InpWeightOte      +InpWeightKillzone+InpWeightPoiGrade;
   double q=1.0;
   if(wsum>0.0)
      q=(InpWeightHtf*htfScore + InpWeightStructure*structScore +
         InpWeightSweep*sweepScore + InpWeightPD*pdScore +
         InpWeightOte*oteScore + InpWeightKillzone*kzScore +
         InpWeightPoiGrade*gradeScore)/wsum;
   q=MClamp(q,0.0,1.0);

   if(q<InpQualityFloor) return false;       // off by default (floor = 0)

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

   double risk=MathAbs(px-sl);
   if(risk<0.25*g_view.avgRange)             // never a meaningless stop
     {
      risk=0.25*g_view.avgRange;
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

   if(freshEntry)             s.model=src+" continuation";    // §3b, no retrace waited for
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
   if(tags=="") tags="bare POI";

   s.dir=dir; s.zoneTop=zt; s.zoneBottom=zb;
   s.stop=sl; s.target=tp; s.rr=rr;
   s.quality=q; s.poiGrade=poiGrade;
   s.sizeFactor=MClamp(InpMinSizeFactor+(1.0-InpMinSizeFactor)*q,0.05,1.0);
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
     }
   if(eq>g_peakEquity) g_peakEquity=eq;
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

//--- The daily loss limit is a percentage, which on a small account can be
//    less than one minimum-lot stop. Latching the breaker on a single trade
//    ends the session before the model has been given a chance to work, so
//    the day limit also requires a run of losers. Max drawdown from peak is
//    the hard rail and still latches on its own.
bool CircuitBreaker(void)
  {
   if(g_breaker) return true;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if((g_dayStartEquity-eq)>=g_dayStartEquity*InpDailyLossPct/100.0 &&
      DayLosingTrades()>=InpBreakerMinLosses)                        g_breaker=true;
   if((g_peakEquity-eq)>=g_peakEquity*InpMaxDDPct/100.0)             g_breaker=true;
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
void ManageBasket(const SBasket &b)
  {
   if(b.count==0 || g_basketRisk<=0.0) return;
   double R=b.floatPL/g_basketRisk;

   if(R>=InpBasketTargetR){ CloseBasket(StringFormat("basket target %.2fR",R)); return; }

   // a scalp that has not resolved is dead money — release the risk
   if(InpScalpMode && b.firstTime>0)
     {
      int held=(int)((TimeCurrent()-b.firstTime)/MathMax(PeriodSeconds(PERIOD_M5),1));
      if(held>InpMaxHoldBars && R<0.3)
        { CloseBasket(StringFormat("scalp timed out after %d M5 bars at %.2fR",held,R)); return; }
     }
   if(R<=-InpBasketStopR) { CloseBasket(StringFormat("basket stop %.2fR",R));  return; }

   if(InpCloseOnFlip && MSign(g_view.htfBias)!=0 && MSign(g_view.htfBias)!=b.dir &&
      MathAbs(g_view.htfBias)>=InpFlipMinBias)
     { CloseBasket("higher-timeframe bias flipped against the basket"); return; }

   if((b.dir>0 && g_view.bearChoch) || (b.dir<0 && g_view.bullChoch))
     { CloseBasket("structure shifted against the basket"); return; }

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

      if(InpBasketPartial && R>=InpBasketPartialR && !TicketSeen(g_partialDone,tk))
        {
         double step=LotStep();
         double part=MathFloor(vol*InpBasketPartialPct/100.0/step+1e-9)*step;
         if(part>=MinLot() && (vol-part)>=MinLot())
           {
            if(ClosePartial(tk,part))
              { TicketMark(g_partialDone,tk);
                LogEvent(StringFormat("basket partial: closed %.2f at %.2fR",part,R)); }
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

   double realRisk=RiskOfLots(lots,dist);
   if(realRisk>eq*InpMaxRiskPctHard/100.0)
     {
      Block(StringFormat("risk %.2f = %.0f%% of equity over the %.0f%% ceiling",
                         realRisk,100.0*realRisk/MathMax(eq,0.01),InpMaxRiskPctHard));
      return;
     }
   if(InpUseBasket && BasketRiskUsed()+realRisk>eq*InpMaxBasketRiskPct/100.0)
     { Block("basket risk cap reached"); return; }
   if(!MarginOK(dir,lots)){ Block("insufficient free margin"); return; }

   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=lots;
   req.type=(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   req.price=entry; req.sl=sl; req.tp=tp;
   req.deviation=(ulong)InpDeviationPts; req.magic=(ulong)InpMagic;
   req.comment="SMC"; req.type_filling=Filling();

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
     }
   g_lastEntry=TimeCurrent();
   g_entries++;
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
   datetime fwd=now+PeriodSeconds(PERIOD_M5)*20;
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
   BuildLiquidity();        // §4
   BuildPremiumDiscount();  // §5
   BuildKillzone();         // §6
   BuildHtfBias();          // §7
   FindSetup();             // the model
   return true;
  }

//======================== SELF-TEST & PANEL =========================

void SelfTest(void)
  {
   if(!InpSelfTest) return;
   LogEvent("────────── SMC / ICT SELF-TEST ──────────");
   LogEvent(StringFormat("symbol %s  execution timeframe M5  bars loaded %d  (NO INDICATORS)",
                         _Symbol,g_bars));
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
      "MEDULA v5.11  SMC / ICT SCALPER  |  %s  M5\n"
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
      _Symbol,
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
   g_breaker=false; g_lastBar=0; g_lastEntry=0; g_entries=0;
   g_basketRisk=0.0; g_firstLot=0.0;
   g_block="warming up";
   RiskUpdate();

   if(_Period!=PERIOD_M5)
      LogEvent(StringFormat("NOTE: attached to %s but this EA reads M5 for execution "
                            "regardless of the chart timeframe",EnumToString(_Period)));

   if(Analyse()) SelfTest();
   LogEvent("v5.00 SMC/ICT scalper ready — one hard condition (price in a live POI), "
            "confluence sizes the trade, basket manager active");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Comment("");
   ClearObjects();
   LogEvent(StringFormat("stopped (reason %d) — entries this run: %d",reason,g_entries));
   LogClose();
  }

void OnTick(void)
  {
   RiskUpdate();

   SBasket b; GetBasket(b);
   if(b.count==0 && g_basketRisk>0.0)
     {
      g_basketRisk=0.0; g_firstLot=0.0;
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
   if(newBar){ g_lastBar=cur; DrawZones(); }

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
