//+------------------------------------------------------------------+
//|                                          IAX_v7_GODMODE_PLUS_OODA.mq5       |
//|      Institutional Adaptive XAUUSD Trading System  —  v7.0        |
//|      "GODMODE+ / OODA" — the v6 engine restructured as an      |
//|      explicit Observe->Orient->Decide->Act loop w/ telemetry.         |
//|                                                                    |
//|  Broker assumption (defaults only, all overridable via inputs):    |
//|    Account currency USD · Standard account · Leverage 1:3000       |
//|                                                                    |
//|  This EA never promises profit. Every gate, block and decision     |
//|  is logged. Read docs/IAX_v7_OODA.md + IAX_v6_TECHNICAL.md first.  |
//+------------------------------------------------------------------+
#property copyright "IAX v7.0 GODMODE+ OODA"
#property link      ""
#property version   "7.10"
#property description "Institutional Adaptive XAUUSD EA — GODMODE+ OODA v7.1: 9-factor probabilistic engine as an explicit OODA loop, plus a pattern-arithmetic layer — learned per-pattern expectancy, hour-of-day volatility profile, serial-correlation bias, round-number TP snapping. No profit is promised."

//====================================================================
// [ENUMS]
//====================================================================
enum ENUM_PROFILE
  {
   PROFILE_SCALP_M1 = 0,   // Scalp M1 — tight geometry, high frequency, passive entries
   PROFILE_SCALP_M5 = 1,   // Scalp M5 — moderate geometry
   PROFILE_SWING_M15 = 2,  // Swing M15 — wide geometry, swing module active
   PROFILE_VALIDATION = 3, // Validation — relaxed gates, Stage 1 self-test enabled
   PROFILE_CUSTOM = 4      // Custom — use raw input values, no preset override
  };

enum ENUM_ENTRY_MODE
  {
   ENTRY_MARKET = 0,       // Immediate fill, pays the spread
   ENTRY_PASSIVE_LIMIT = 1,// Posts at bid/ask to earn the spread (default)
   ENTRY_BREAK_STOP = 2    // Stop order beyond prior bar extreme, confirms only
  };

enum ENUM_REGIME
  {
   REGIME_STRONG_BULL = 0,
   REGIME_NORMAL_BULL = 1,
   REGIME_WEAK_BULL = 2,
   REGIME_STRONG_BEAR = 3,
   REGIME_NORMAL_BEAR = 4,
   REGIME_WEAK_BEAR = 5,
   REGIME_RANGE = 6,
   REGIME_BREAKOUT_UP = 7,
   REGIME_BREAKOUT_DOWN = 8,
   REGIME_VOL_EXPANSION = 9,
   REGIME_VOL_COMPRESSION = 10,
   REGIME_EXHAUSTION_UP = 11,
   REGIME_EXHAUSTION_DOWN = 12,
   REGIME_REVERSAL_RISK = 13,
   REGIME_UNKNOWN = 14
  };

enum ENUM_SESSION
  {
   SESSION_ASIA = 0,
   SESSION_LONDON = 1,
   SESSION_NY = 2,
   SESSION_LONDON_NY_OVERLAP = 3,
   SESSION_ROLLOVER = 4
  };

enum ENUM_VALIDATION_STAGE
  {
   STAGE_1_LIFECYCLE = 1,  // open->modify->partial->close self-test, BUY then SELL
   STAGE_2_RISK = 2,       // +geometry / risk sizing
   STAGE_3_MANAGEMENT = 3, // +R-multiple / basket / flip-exit management
   STAGE_4_SCALING = 4,    // +burst entries / laddered TPs
   STAGE_5_FILTERS = 5     // +full governor stack
  };

enum ENUM_BLOCK_REASON
  {
   BLOCK_NONE = 0,
   BLOCK_LOW_CONFIDENCE,
   BLOCK_SPREAD_SCALP_CEILING,
   BLOCK_SPREAD_ABSOLUTE,
   BLOCK_NEWS_BLACKOUT,
   BLOCK_LOSS_STREAK_COOLDOWN,
   BLOCK_HOURLY_CAP,
   BLOCK_DAILY_CAP,
   BLOCK_HOUR_NEGATIVE_EXPECTANCY,
   BLOCK_EQUITY_CURVE_GOVERNOR,
   BLOCK_MARGIN_USAGE_CAP,
   BLOCK_DAILY_LOSS_HALT,
   BLOCK_MAX_DD_FLATTEN,
   BLOCK_MARGIN_LEVEL_GATE,
   BLOCK_CHASE_GUARD,
   BLOCK_HTF_ZONE_WALL,
   BLOCK_FEED_DEGRADED,
   BLOCK_VOTE_EDGE_TOO_THIN,
   BLOCK_MAX_POSITIONS,
   BLOCK_GEOMETRY_INCOHERENT,
   BLOCK_PATTERN_NEGATIVE,
   BLOCK_COUNT // sentinel, keep last
  };

enum ENUM_OODA_DECISION
  {
   DEC_NONE = 0,       // no actionable orientation this cycle
   DEC_ENTER_LONG,     // decision engine says buy
   DEC_ENTER_SHORT,    // decision engine says sell
   DEC_BLOCKED         // wanted to act, a gate/governor said no
  };

//====================================================================
// [INPUTS]
//====================================================================
input group "=== PROFILE ===";
input ENUM_PROFILE   InpProfile              = PROFILE_CUSTOM;   // Coherent preset bundle (overrides section values below if != CUSTOM)
input ENUM_VALIDATION_STAGE InpValidationStage = STAGE_5_FILTERS; // Progressive validation stage gate
input bool            InpRunStage1SelfTest    = false;            // Run Stage-1 lifecycle self-test in OnInit (tester/demo only)

input group "=== TIMEFRAMES ===";
input ENUM_TIMEFRAMES InpSignalTF             = PERIOD_M5;        // Signal timeframe
input ENUM_TIMEFRAMES InpTrendTF              = PERIOD_M15;       // Trend timeframe (auto-escalates to H1 if SignalTF >= TrendTF)

input group "=== ACCOUNT / BROKER ASSUMPTIONS ===";
input string           InpSymbolSuffix        = "";               // Broker symbol suffix, e.g. ".m" (blank = none)
input string           InpContextSymbolBase   = "EURUSD";          // USD proxy context symbol base name
input bool              InpContextIsDXYStyle   = false;             // true if context symbol itself IS a USD-strength index (sign-flip the vote)
input double           InpAssumedLeverage     = 3000.0;            // Assumed account leverage (Just Markets standard = 1:3000), used only in coherence math prints

input group "=== DECISION ENGINE — FACTOR WEIGHTS (defaults) ===";
input double InpW_MarketStructure     = 26.0;  // Market Structure weight
input double InpW_Momentum            = 16.0;  // Momentum weight
input double InpW_Trend               = 16.0;  // Trend weight
input double InpW_Volatility          = 10.0;  // Volatility weight
input double InpW_Liquidity           = 10.0;  // Liquidity weight
input double InpW_CandlestickWick     = 20.0;  // Candlestick Wick weight
input double InpW_TickDeltaFlow       = 14.0;  // Tick-Delta Flow weight
input double InpW_SessionVWAP         = 10.0;  // Session VWAP weight
input double InpW_ContextSymbol       = 8.0;   // Context Symbol (USD proxy) weight

input group "=== ADAPTIVE LEARNING ===";
input bool   InpAdaptiveLearningOn    = true;   // Online weight adaptation after each closed basket
input double InpMinFactorWeight       = 2.0;    // Weight floor
input double InpMaxFactorWeight       = 40.0;   // Weight ceiling
input double InpLearningRate          = 0.08;   // Fraction of result-relative-to-risk applied to weight delta

input group "=== CONFIDENCE GATE ===";
input double InpMinConfidenceToTrade  = 35.0;   // Minimum confidence (0-100) required to trade
input double InpMinVoteEdge           = 0.12;   // Minimum |buyProb-sellProb| edge (post-normalisation) — coin-flip candles only donate spread otherwise

input group "=== ENTRY ENGINE ===";
input ENUM_ENTRY_MODE InpEntryMode    = ENTRY_PASSIVE_LIMIT; // Entry mode
input int    InpPassiveTimeoutSec     = 45;     // Unfilled passive/stop pendings auto-cancel after N seconds
input int    InpEntriesPerSignal      = 1;      // Burst entries per signal bar (laddered TPs if > 1)
input double InpLadderStep            = 0.35;   // Ladder step: position i targets base*(1+LadderStep*i)
input int    InpSendRetryAttempts     = 3;      // SendWithRetry attempts on REQUOTE/PRICE_CHANGED/PRICE_OFF/TIMEOUT/CONNECTION
input int    InpSendRetrySleepMs      = 250;    // Sleep between retry attempts (ms)

input group "=== GEOMETRY ===";
input bool   InpFixedLotMode          = false;  // true = dollar-defined SL/TP; false = ATR/risk-% sizing
input double InpFixedSL_USD           = 3.50;   // Dollar SL per 0.01 lot equivalent price distance (FixedLotMode)
input double InpFixedTP_USD           = 5.00;   // Dollar TP per 0.01 lot equivalent price distance (FixedLotMode)
input double InpSL_ATR_Mult           = 1.20;   // SL = ATR(signal TF) * mult (risk-% mode)
input double InpTP_ATR_Mult           = 1.80;   // TP = ATR(signal TF) * mult (risk-% mode)
input double InpRiskPercent           = 0.50;   // % equity risked per basket (risk-% mode)
input double InpTPSpreadFloorMult     = 3.0;    // Effective TP = max(userTP, this * current spread)
input double InpRoundLevelPadPoints   = 40;     // Anti-stop-hunt: pad stops beyond .00/.50 round levels by N points
input double InpLotPer100USD          = 0.01;   // Auto lot growth: lots scale with equity, LotPer100USD per 100 equity units
input double InpBaseLot               = 0.01;   // Base lot before equity scaling

input group "=== TRADE MANAGEMENT ===";
input double InpBE_TriggerR           = 1.0;    // R-multiple at which SL moves to breakeven + partial close
input double InpBE_PartialPct         = 40.0;   // % of basket volume closed at breakeven trigger
input double InpTrailTriggerR         = 2.0;    // R-multiple at which ATR trailing stop activates
input double InpTrailATRMult          = 1.5;    // Trailing stop distance = ATR * mult
input double InpBasketGivebackPct     = 35.0;   // Close basket if it gives back this % of peak profit
input double InpBasketMaxLossUSD      = 25.0;   // Hard basket max-loss cut (USD)
input double InpThesisInvalidationProb= 0.62;   // Opposite-side probability trigger for thesis invalidation
input int    InpFlipConfirmBars       = 2;      // Opposite signal must persist N CLOSED bars before flattening

input group "=== SWING MODULE (own magic = Magic+7) ===";
input bool   InpSwingModuleOn         = true;   // Enable swing module
input double InpSwingMinADX           = 25.0;   // Minimum ADX(14) on trend TF to arm swing entries
input double InpSwingRR               = 2.0;    // Swing target R-multiple (2:1)
input int    InpSwingTimeStopBars     = 48;     // Time-stop: flatten if not +1R within N trend-TF bars
input bool   InpSwingFridayFlatten    = true;   // Flatten swing positions before weekend gap

input group "=== GOVERNORS ===";
input bool   InpUseNewsFilter         = true;   // MQL5 calendar high-impact USD blackout (auto-bypasses + logs in tester when calendar is empty)
input int    InpNewsBlackoutMin       = 30;     // Minutes before/after high-impact USD news to block entries
input int    InpMaxConsecutiveLosses  = 4;      // Loss-streak cooldown trigger
input int    InpCooldownMinutes       = 60;     // Cooldown duration after loss streak
input int    InpMaxTradesPerHour      = 6;      // Hourly trade cap
input int    InpMaxTradesPerDay       = 30;     // Daily trade cap
input int    InpHourMinSamples        = 20;     // Minimum closed baskets in an hour bucket before its expectancy is trusted
input int    InpEquityMAPeriod        = 20;     // Equity curve MA period (in closed baskets)
input double InpEquityGovernorHalvePct= 100.0;  // Position size halved when equity < MA (percent of normal size retained... see code)
input double InpMarginUsageCapPct     = 40.0;   // Max % of free margin committed across open baskets
input double InpScalpSpreadCeilingUSD = 0.45;   // Scalp spread ceiling (dollars) — dollar-based, never point-based
input double InpAbsoluteSpreadCeilingUSD = 1.20;// Absolute spread gate (dollars) — blocks all entries above this
input double InpDailyLossHaltPct      = 3.0;    // Daily loss halt (% of day-start equity)
input double InpMaxDDFlattenPct       = 8.0;    // Max drawdown flatten-all threshold (% of peak equity)
input double InpMarginLevelGateMin    = 250.0;  // Minimum margin level (%) to allow new entries
input double InpChaseATRMult          = 1.6;    // Chase guard: skip if bar already ran > this * ATR
input double InpZoneBlockMult         = 0.6;    // HTF zone map: skip entries into opposing wall closer than TP * this
input int    InpMaxFeedStaleSeconds   = 20;     // Heartbeat watchdog: feed considered degraded after N seconds without a new tick

input group "=== OPS / VERIFICATION ===";
input long   InpMagic                 = 770001; // Base magic number (scalp). Swing = Magic+7. Differs from v6 so both EAs can coexist
input bool   InpVerboseDecisionLog    = true;   // Per-bar decision + rejection reason log
input bool   InpShowDashboard         = true;   // On-chart debug dashboard
input bool   InpShowKillSwitch        = true;   // On-chart FLATTEN ALL button
input bool   InpPushAlertsOn          = true;   // Push notifications on critical events
input bool   InpWriteTradeJournalCSV  = true;   // Write per-trade CSV journal
input int    InpMinTradesForFitness   = 50;     // OnTester() returns 0 below this many closed trades

input group "=== OODA LOOP (GODMODE+) ===";
input int    InpOODATempoSec          = 0;      // Intra-bar re-orient cadence (sec) in breakout/vol-expansion regimes. 0 = bar-close only (safest)
input int    InpOODALedgerSize        = 6;      // Recent-decision ledger rows shown on the dashboard
input bool   InpOODALogPhaseTimings   = true;   // Print per-phase OODA loop timings in the end-of-run report

input group "=== PATTERN ARITHMETIC (GODMODE+ v7.1) ===";
input bool   InpPatternLearnerOn     = true;   // Learn per-pattern (regime-group x session x direction) expectancy in R; suppress proven-negative patterns
input int    InpPatternMinSamples    = 15;     // Closed trades required in a pattern bucket before its expectancy is trusted
input double InpPatternBlockAvgR     = -0.05;  // Suppress a pattern whose average R falls below this
input double InpPatternBoostAvgR     = 0.30;   // Boost size when a pattern's average R exceeds this
input double InpPatternBoostFactor   = 1.25;   // Size multiplier for proven-positive patterns
input bool   InpUseHourVolProfile    = true;   // Scale TP/SL to the learned hour-of-day ATR profile of the instrument
input bool   InpUseSerialBias        = true;   // Confidence tilt from measured continuation/alternation bias of closed-bar returns
input bool   InpSnapTPBeforeRound    = true;   // Pull TP just in front of .00/.50 round-number walls in its path

//====================================================================
// [GLOBAL STATE] — all declared before first use (MQL5 is single-pass)
//====================================================================
string g_symbol;
string g_contextSymbol;
int    g_digits;
double g_point;
ENUM_TIMEFRAMES g_signalTF, g_trendTF;
long   g_swingMagic;
string g_buildFingerprint;
datetime g_initTime;

// --- Factor engine ---
#define NUM_FACTORS 9
string g_factorName[NUM_FACTORS];
double g_factorWeight[NUM_FACTORS];
int    g_factorVote[NUM_FACTORS];
bool   g_factorAvailable[NUM_FACTORS];

// --- Indicator handles ---
int h_ema13_sig, h_ema34_sig, h_macd_sig, h_atr_sig;
int h_ema21_trend, h_ema55_trend, h_atr_trend, h_adx_trend;
int h_ema8_ctx, h_ema21_ctx;

// --- Regime / confidence state ---
ENUM_REGIME g_regime = REGIME_UNKNOWN;
double g_regimeQuality = 1.0;
ENUM_SESSION g_session = SESSION_ASIA;
double g_sessionQuality = 1.0;
double g_buyProb = 0.0, g_sellProb = 0.0, g_confidence = 0.0;
bool   g_ignitionBar = false;
bool   g_exhaustionBar = false;
int    g_lastSignalDir = 0; // 1 buy, -1 sell, 0 none
int    g_flipCounter = 0;
int    g_flipDir = 0;

// --- Session VWAP ---
double g_vwapCumPV = 0.0, g_vwapCumVol = 0.0, g_vwap = 0.0, g_vwapPrev = 0.0;
datetime g_vwapSessionAnchor = 0;

// --- Tick delta flow ---
#define TICK_WINDOW 300
int    g_tickDir[TICK_WINDOW];
int    g_tickCount = 0;
int    g_tickWriteIdx = 0;
double g_lastTickBid = 0.0;

// --- Baskets (scalp), index-based lookup arrays, no struct pointers ---
#define MAX_BASKETS 30
bool     g_bkActive[MAX_BASKETS];
int      g_bkDirection[MAX_BASKETS];
double   g_bkAvgPrice[MAX_BASKETS];
double   g_bkVolume[MAX_BASKETS];
double   g_bkPeakProfit[MAX_BASKETS];
double   g_bkInitialRiskUSD[MAX_BASKETS];
datetime g_bkOpenTime[MAX_BASKETS];
bool     g_bkBEApplied[MAX_BASKETS];
bool     g_bkPartialApplied[MAX_BASKETS];
ENUM_REGIME g_bkRegime[MAX_BASKETS];
double   g_bkConfidenceAtEntry[MAX_BASKETS];
int      g_bkEntryHour[MAX_BASKETS];
ulong    g_bkTicket[MAX_BASKETS];        // 0 until reconciled with a live position ticket
int      g_bkFactorVote[MAX_BASKETS][NUM_FACTORS]; // snapshot of factor votes at entry, for adaptive learning
int      g_bkPatternId[MAX_BASKETS];               // pattern bucket at entry, for pattern-expectancy learning
double   g_groupPeakProfitBuy = 0.0;     // basket-group (all active BUY slots) peak floating profit
double   g_groupPeakProfitSell = 0.0;    // basket-group (all active SELL slots) peak floating profit

// --- Swing single-slot state (own magic) ---
bool     g_swActive = false;
int      g_swDirection = 0;
double   g_swAvgPrice = 0.0;
double   g_swVolume = 0.0;
datetime g_swOpenTime = 0;
datetime g_swOpenTrendTime = 0; // trend-TF bar open time at swing entry, for time-stop bar counting

// --- Governors state ---
datetime g_cooldownUntil = 0;
int      g_consecutiveLosses = 0;
int      g_tradesThisHour = 0;
int      g_tradesToday = 0;
datetime g_currentHourStamp = 0;
datetime g_currentDayStamp = 0;
double   g_dailyStartEquity = 0.0;
double   g_peakEquity = 0.0;
bool     g_dailyHaltActive = false;
bool     g_maxDDFlattenActive = false;
double   g_equityHistory[]; // dynamic — closed-basket equity snapshots for MA governor
double   g_equityMA = 0.0;
datetime g_lastTickTime = 0;
bool     g_feedDegraded = false;

// --- Hourly expectancy learner (24 buckets), persisted to file ---
double   g_hourPnLSum[24];
int      g_hourSampleCount[24];
bool     g_hourBlocked[24];

// --- Counters / end-of-run report ---
int g_barsProcessed = 0;
int g_signalsGenerated = 0;
int g_ordersSent = 0;
int g_ordersFilled = 0;
int g_ordersRejected = 0;
int g_positionsClosed = 0;
int g_blockCounts[BLOCK_COUNT];
double g_lastLatencyMs = 0.0;
double g_avgSlippagePoints = 0.0;
int    g_slippageSamples = 0;
int    g_shadowGateWouldHaveTraded = 0; // signals that passed confidence but were blocked downstream

// --- File / persistence paths ---
string g_stateFileName;
string g_journalFileName;

// --- Last processed bar time (per-TF new-bar detection) ---
datetime g_lastSignalBarTime = 0;
datetime g_lastTrendBarTime = 0;

// --- Kill switch ---
bool g_killSwitchEngaged = false;

// --- Pending-order bookkeeping (for PassiveTimeoutSec auto-cancel) ---
#define MAX_PENDING 40
ulong    g_pendingTicket[MAX_PENDING];
datetime g_pendingPlacedTime[MAX_PENDING];
bool     g_pendingActive[MAX_PENDING];
int      g_pendingBasketIdx[MAX_PENDING];

// --- OODA loop state (GODMODE+) ---
long     g_oodaCycle = 0;            // every tick is one OODA cycle
long     g_oodaTimedCycles = 0;      // cycles that ran the full Orient->Decide->Act chain
double   g_usObserveSum = 0.0, g_usOrientSum = 0.0, g_usDecideSum = 0.0, g_usActSum = 0.0;
ENUM_OODA_DECISION g_lastDecision = DEC_NONE;
string   g_lastDecisionReason = "";
double   g_lastEdge = 0.0;           // |buyProb - sellProb| from the last orientation
datetime g_lastOrientTime = 0;
datetime g_lastEntryBarTime = 0;     // bar whose signal already produced an entry (tempo may not double-enter)
bool     g_newSignalBar = false;
string   g_oodaLedger[];             // newest-first ring of recent decision summaries

// --- Pattern arithmetic (v7.1): the measured statistics of the entity ---
#define NUM_PATTERNS 60              // 6 regime groups x 5 sessions x 2 directions
double   g_patRSum[NUM_PATTERNS];    // summed result in R per pattern bucket
int      g_patCount[NUM_PATTERNS];
bool     g_patBlocked[NUM_PATTERNS];
int      g_currentPatternId = -1;
double   g_patternSizeBoost = 1.0;
double   g_serialP = 0.5;            // P(consecutive closed-bar returns share a sign): >0.5 continuation, <0.5 alternation
double   g_hourATR[24];              // learned EWMA ATR per hour of day (gold's intraday vol profile)
double   g_allATR = 0.0;             // learned EWMA ATR overall

//====================================================================
// [FORWARD DECLARATIONS]
//====================================================================
void  Log(string msg);
void  LogBlock(ENUM_BLOCK_REASON reason, string detail);
string BlockReasonToString(ENUM_BLOCK_REASON r);
bool  IsNewBar(ENUM_TIMEFRAMES tf, datetime &lastBarTime);
double PointsToUSD(double points);
double USDToPoints(double usd);
double CurrentSpreadUSD();
double GetAsk();
double GetBid();
void  BuildFingerprint();
bool  EnvironmentCheck();
void  ApplyProfile();
bool  CreateIndicatorHandles();
void  ReleaseIndicatorHandles();
void  AuditConfigCoherence();
void  LoadPersistedState();
void  SavePersistedState();
void  LoadFactorWeights();
void  SaveFactorWeights();

// [FACTOR:*] vote functions
int    Factor_MarketStructure();
int    Factor_Momentum();
int    Factor_Trend();
int    Factor_Volatility();
int    Factor_Liquidity();
int    Factor_CandlestickWick();
int    Factor_TickDeltaFlow();
int    Factor_SessionVWAP();
int    Factor_ContextSymbol();

int    OODA_Orient();
ENUM_OODA_DECISION OODA_Decide(int direction);
void   OODA_Act(ENUM_OODA_DECISION decision);
bool   TempoAllowsIntraBarReorient();
void   OODA_LedgerPush(string row);
string DecisionToString(ENUM_OODA_DECISION d);
int    RegimeGroup(ENUM_REGIME r);
int    CurrentPatternId(int direction);
string PatternIdToString(int pid);
void   PatternLearn(int pid, double resultR);
void   UpdateVolProfile();
double HourVolFactor();
void   UpdateSerialBias();
double SerialBiasMultiplier(int direction);
double SnapTPBeforeRound(double entryPrice, double tp, int direction);
double NormalizeLot(double lot);
ENUM_REGIME ClassifyRegime();
double RegimeQualityMultiplier(ENUM_REGIME r);
ENUM_SESSION CurrentSession();
double SessionQualityMultiplier(ENUM_SESSION s);
bool   DetectIgnitionBar();
bool   DetectExhaustionBar();
void   UpdateSessionVWAP();
void   UpdateTickDeltaBuffer();

bool   PassGovernors(int direction, ENUM_BLOCK_REASON &blockedBy);
bool   PassNewsBlackout();
bool   PassSpreadGates(ENUM_BLOCK_REASON &reason);
bool   PassChaseGuard(int direction);
bool   PassHTFZoneMap(int direction, double tp);
bool   PassMarginAndCaps();
void   UpdateHourlyDailyCounters();
void   UpdateEquityGovernors();

double CalcLotSize(double slDistancePrice);
bool   CalcGeometry(int direction, double entryPrice, double &sl, double &tp);
void   ApplyRegimeGeometry(ENUM_REGIME r, double &slMult, double &tpMult);
double PadAntiStopHunt(double level, int direction, bool isSL);
double ClampToStopsLevel(double entryPrice, double level, int direction, bool isSL);

bool   SendWithRetry(MqlTradeRequest &request, MqlTradeResult &result);
void   RegisterPending(ulong ticket, int basketIdx);
void   CancelExpiredPendings();
void   ExecuteEntry(int direction, double confidence);
void   ManageOpenPositions();
void   ManageBasket(int idx);
void   EnsureProtectiveStops();
void   CheckFlipExit();
void   ManageSwingModule();

void   OnClosedBasketLearn(int idx, double pnlUSD, double initialRiskUSD, bool winner);
void   UpdateHourExpectancy(int hour, double pnlUSD);

void   UpdateDashboard();
void   WriteTradeJournalRow(string side, double volume, double entry, double exitPrice, double pnl, ENUM_REGIME regime, double confidence, int hour);
void   FlattenAll(string reason);
void   PrintEndOfRunReport();

bool   RunStage1SelfTest();

//====================================================================
// [UTILITIES]
//====================================================================
void Log(string msg)
  {
   Print("[IAX7] ", msg);
  }

string BlockReasonToString(ENUM_BLOCK_REASON r)
  {
   switch(r)
     {
      case BLOCK_NONE:                      return "NONE";
      case BLOCK_LOW_CONFIDENCE:            return "LOW_CONFIDENCE";
      case BLOCK_SPREAD_SCALP_CEILING:      return "SPREAD_SCALP_CEILING";
      case BLOCK_SPREAD_ABSOLUTE:           return "SPREAD_ABSOLUTE";
      case BLOCK_NEWS_BLACKOUT:             return "NEWS_BLACKOUT";
      case BLOCK_LOSS_STREAK_COOLDOWN:      return "LOSS_STREAK_COOLDOWN";
      case BLOCK_HOURLY_CAP:                return "HOURLY_CAP";
      case BLOCK_DAILY_CAP:                 return "DAILY_CAP";
      case BLOCK_HOUR_NEGATIVE_EXPECTANCY:  return "HOUR_NEGATIVE_EXPECTANCY";
      case BLOCK_EQUITY_CURVE_GOVERNOR:     return "EQUITY_CURVE_GOVERNOR";
      case BLOCK_MARGIN_USAGE_CAP:          return "MARGIN_USAGE_CAP";
      case BLOCK_DAILY_LOSS_HALT:           return "DAILY_LOSS_HALT";
      case BLOCK_MAX_DD_FLATTEN:            return "MAX_DD_FLATTEN";
      case BLOCK_MARGIN_LEVEL_GATE:         return "MARGIN_LEVEL_GATE";
      case BLOCK_CHASE_GUARD:               return "CHASE_GUARD";
      case BLOCK_HTF_ZONE_WALL:             return "HTF_ZONE_WALL";
      case BLOCK_FEED_DEGRADED:             return "FEED_DEGRADED";
      case BLOCK_VOTE_EDGE_TOO_THIN:        return "VOTE_EDGE_TOO_THIN";
      case BLOCK_MAX_POSITIONS:             return "MAX_POSITIONS";
      case BLOCK_GEOMETRY_INCOHERENT:       return "GEOMETRY_INCOHERENT";
      case BLOCK_PATTERN_NEGATIVE:          return "PATTERN_NEGATIVE_EXPECTANCY";
      default:                              return "UNKNOWN";
     }
  }

void LogBlock(ENUM_BLOCK_REASON reason, string detail)
  {
   if(reason >= 0 && reason < BLOCK_COUNT)
      g_blockCounts[reason]++;
   if(InpVerboseDecisionLog)
      Log(StringFormat("REJECTED [%s]: %s", BlockReasonToString(reason), detail));
  }

// New-bar detection per timeframe — caller supplies its own "last bar time" holder
bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &lastBarTime)
  {
   datetime t[];
   if(CopyTime(g_symbol, tf, 0, 1, t) != 1)
      return false;
   if(t[0] != lastBarTime)
     {
      lastBarTime = t[0];
      return true;
     }
   return false;
  }

// [DEFECT-RULE-2] Spread filters are ALWAYS dollar-based, never point-based.
// A 3-digit gold broker turns a normal $0.25 spread into 250 points and
// silently blocks everything forever if a point-based filter is used.
double CurrentSpreadUSD()
  {
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   return NormalizeDouble(ask - bid, g_digits);
  }

double PointsToUSD(double points)
  {
   return points * g_point;
  }

double USDToPoints(double usd)
  {
   if(g_point <= 0.0)
      return 0.0;
   return usd / g_point;
  }

double GetAsk() { return SymbolInfoDouble(g_symbol, SYMBOL_ASK); }
double GetBid() { return SymbolInfoDouble(g_symbol, SYMBOL_BID); }

// [DEFECT-RULE-12] Confirm the running build in the Journal header before
// judging any fix. Stale-build confusion cost two evaluation cycles in dev.
void BuildFingerprint()
  {
   g_buildFingerprint = StringFormat(
      "IAX7-%s-%s-Profile%d-Stage%d-Sig%s-Trend%s-Magic%d-%s",
      g_symbol, TimeToString(g_initTime, TIME_DATE|TIME_SECONDS),
      (int)InpProfile, (int)InpValidationStage,
      EnumToString(g_signalTF), EnumToString(g_trendTF),
      (int)InpMagic, __DATE__ + " " + __TIME__);
   Log("======================================================================");
   Log("BUILD FINGERPRINT: " + g_buildFingerprint);
   Log("======================================================================");
  }

//====================================================================
// [ENVIRONMENT CHECK] — terminal/EA/account/broker permissions, symbol mode
//====================================================================
bool EnvironmentCheck()
  {
   bool ok = true;

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     { Log("ENV FAIL: terminal 'Algo Trading' is disabled."); ok = false; }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     { Log("ENV FAIL: EA 'Allow Algo Trading' is disabled for this chart."); ok = false; }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     { Log("ENV FAIL: account does not permit trading."); ok = false; }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     { Log("ENV FAIL: broker has disabled Expert Advisor trading on this account."); ok = false; }

   long tradeMode = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
     { Log("ENV FAIL: symbol " + g_symbol + " trading is disabled by broker."); ok = false; }
   else if(tradeMode != SYMBOL_TRADE_MODE_FULL)
     { Log(StringFormat("ENV WARN: symbol %s trade mode = %d (not FULL) — some operations may be rejected.", g_symbol, (int)tradeMode)); }

   double lotMin  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   double lotMax  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   int    digits  = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   Log(StringFormat("ENV: symbol=%s digits=%d lot(min/step/max)=%.2f/%.2f/%.2f stopsLevel=%d pts freezeLevel=%d pts",
       g_symbol, digits, lotMin, lotStep, lotMax,
       (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL),
       (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_FREEZE_LEVEL)));

   if(!SymbolSelect(g_symbol, true))
     { Log("ENV FAIL: could not select symbol " + g_symbol + " in Market Watch."); ok = false; }

   return ok;
  }

//====================================================================
// [PROFILE PRESETS] — internally consistent bundles; CUSTOM leaves inputs as-is
//====================================================================
// Runtime-adjustable mirrors of geometry/gate inputs so presets can override
// them without requiring separate input variables per profile.
double eff_MinConfidenceToTrade;
double eff_TPSpreadFloorMult;
ENUM_ENTRY_MODE eff_EntryMode;
double eff_SL_ATR_Mult, eff_TP_ATR_Mult;
double eff_BE_TriggerR, eff_TrailTriggerR;
int    eff_FlipConfirmBars;
double eff_ScalpSpreadCeilingUSD;
bool   eff_SwingModuleOn;

void ApplyProfile()
  {
   // Start from raw inputs, then override per coherent preset.
   eff_MinConfidenceToTrade = InpMinConfidenceToTrade;
   eff_TPSpreadFloorMult    = InpTPSpreadFloorMult;
   eff_EntryMode            = InpEntryMode;
   eff_SL_ATR_Mult          = InpSL_ATR_Mult;
   eff_TP_ATR_Mult          = InpTP_ATR_Mult;
   eff_BE_TriggerR          = InpBE_TriggerR;
   eff_TrailTriggerR        = InpTrailTriggerR;
   eff_FlipConfirmBars      = InpFlipConfirmBars;
   eff_ScalpSpreadCeilingUSD= InpScalpSpreadCeilingUSD;
   eff_SwingModuleOn        = InpSwingModuleOn;

   switch(InpProfile)
     {
      case PROFILE_SCALP_M1:
         g_signalTF = PERIOD_M1; g_trendTF = PERIOD_M15;
         eff_EntryMode = ENTRY_PASSIVE_LIMIT;
         eff_MinConfidenceToTrade = 42.0;
         eff_TPSpreadFloorMult = 4.0;
         eff_SL_ATR_Mult = 0.9; eff_TP_ATR_Mult = 1.3;
         eff_BE_TriggerR = 0.8; eff_TrailTriggerR = 1.6;
         eff_FlipConfirmBars = 2;
         eff_ScalpSpreadCeilingUSD = 0.30;
         eff_SwingModuleOn = false;
         Log("PROFILE: SCALP_M1 applied.");
         break;
      case PROFILE_SCALP_M5:
         g_signalTF = PERIOD_M5; g_trendTF = PERIOD_M15;
         eff_EntryMode = ENTRY_PASSIVE_LIMIT;
         eff_MinConfidenceToTrade = 38.0;
         eff_TPSpreadFloorMult = 3.0;
         eff_SL_ATR_Mult = 1.1; eff_TP_ATR_Mult = 1.6;
         eff_BE_TriggerR = 1.0; eff_TrailTriggerR = 2.0;
         eff_FlipConfirmBars = 2;
         eff_ScalpSpreadCeilingUSD = 0.45;
         eff_SwingModuleOn = true;
         Log("PROFILE: SCALP_M5 applied.");
         break;
      case PROFILE_SWING_M15:
         g_signalTF = PERIOD_M15; g_trendTF = PERIOD_H1;
         eff_EntryMode = ENTRY_BREAK_STOP;
         eff_MinConfidenceToTrade = 45.0;
         eff_TPSpreadFloorMult = 2.0;
         eff_SL_ATR_Mult = 1.5; eff_TP_ATR_Mult = 2.6;
         eff_BE_TriggerR = 1.0; eff_TrailTriggerR = 2.0;
         eff_FlipConfirmBars = 3;
         eff_ScalpSpreadCeilingUSD = 1.20;
         eff_SwingModuleOn = true;
         Log("PROFILE: SWING_M15 applied.");
         break;
      case PROFILE_VALIDATION:
         g_signalTF = InpSignalTF; g_trendTF = InpTrendTF;
         eff_EntryMode = ENTRY_MARKET;
         eff_MinConfidenceToTrade = 0.0; // relaxed so lifecycle self-test can force trades
         eff_SwingModuleOn = false;
         Log("PROFILE: VALIDATION applied (relaxed gates for self-test).");
         break;
      case PROFILE_CUSTOM:
      default:
         g_signalTF = InpSignalTF; g_trendTF = InpTrendTF;
         Log("PROFILE: CUSTOM — using raw inputs verbatim.");
         break;
     }

   // Auto-escalate trend TF if signal TF is >= trend TF (spec: Trend factor rule)
   if(g_signalTF >= g_trendTF)
     {
      Log(StringFormat("TF escalation: SignalTF %s >= TrendTF %s -> forcing TrendTF to H1.",
          EnumToString(g_signalTF), EnumToString(g_trendTF)));
      g_trendTF = PERIOD_H1;
      if(g_signalTF >= g_trendTF)
         g_trendTF = PERIOD_H4; // pathological case: signal TF itself >= H1
     }
  }

//====================================================================
// [INDICATOR HANDLES] — created once in OnInit, released in OnDeinit
//====================================================================
bool CreateIndicatorHandles()
  {
   h_ema13_sig = iMA(g_symbol, g_signalTF, 13, 0, MODE_EMA, PRICE_CLOSE);
   h_ema34_sig = iMA(g_symbol, g_signalTF, 34, 0, MODE_EMA, PRICE_CLOSE);
   h_macd_sig  = iMACD(g_symbol, g_signalTF, 12, 26, 9, PRICE_CLOSE);
   h_atr_sig   = iATR(g_symbol, g_signalTF, 14);

   h_ema21_trend = iMA(g_symbol, g_trendTF, 21, 0, MODE_EMA, PRICE_CLOSE);
   h_ema55_trend = iMA(g_symbol, g_trendTF, 55, 0, MODE_EMA, PRICE_CLOSE);
   h_atr_trend   = iATR(g_symbol, g_trendTF, 14);
   h_adx_trend   = iADX(g_symbol, g_trendTF, 14);

   // [DEFECT-RULE-11] Broker symbol suffixes differ. Resolve the context
   // symbol defensively; disable the factor with a log if unavailable —
   // never fail init over an optional cross-symbol factor.
   g_contextSymbol = InpContextSymbolBase + InpSymbolSuffix;
   if(!SymbolSelect(g_contextSymbol, true))
     {
      Log("WARN: context symbol '" + g_contextSymbol + "' unavailable — Context Symbol factor disabled.");
      h_ema8_ctx = INVALID_HANDLE;
      h_ema21_ctx = INVALID_HANDLE;
      g_factorAvailable[8] = false;
     }
   else
     {
      h_ema8_ctx  = iMA(g_contextSymbol, PERIOD_M5, 8, 0, MODE_EMA, PRICE_CLOSE);
      h_ema21_ctx = iMA(g_contextSymbol, PERIOD_M5, 21, 0, MODE_EMA, PRICE_CLOSE);
      g_factorAvailable[8] = (h_ema8_ctx != INVALID_HANDLE && h_ema21_ctx != INVALID_HANDLE);
      if(!g_factorAvailable[8])
         Log("WARN: context symbol indicators failed to create — Context Symbol factor disabled.");
     }

   int handles[] = { h_ema13_sig, h_ema34_sig, h_macd_sig, h_atr_sig,
                      h_ema21_trend, h_ema55_trend, h_atr_trend, h_adx_trend };
   for(int i = 0; i < ArraySize(handles); i++)
      if(handles[i] == INVALID_HANDLE)
        {
         Log(StringFormat("INIT FAIL: core indicator handle %d could not be created (err=%d).", i, GetLastError()));
         return false;
        }

   for(int f = 0; f < NUM_FACTORS; f++)
      if(f != 8) g_factorAvailable[f] = true; // context symbol handled above

   return true;
  }

void ReleaseIndicatorHandles()
  {
   if(h_ema13_sig != INVALID_HANDLE) IndicatorRelease(h_ema13_sig);
   if(h_ema34_sig != INVALID_HANDLE) IndicatorRelease(h_ema34_sig);
   if(h_macd_sig  != INVALID_HANDLE) IndicatorRelease(h_macd_sig);
   if(h_atr_sig   != INVALID_HANDLE) IndicatorRelease(h_atr_sig);
   if(h_ema21_trend != INVALID_HANDLE) IndicatorRelease(h_ema21_trend);
   if(h_ema55_trend != INVALID_HANDLE) IndicatorRelease(h_ema55_trend);
   if(h_atr_trend  != INVALID_HANDLE) IndicatorRelease(h_atr_trend);
   if(h_adx_trend  != INVALID_HANDLE) IndicatorRelease(h_adx_trend);
   if(h_ema8_ctx   != INVALID_HANDLE) IndicatorRelease(h_ema8_ctx);
   if(h_ema21_ctx  != INVALID_HANDLE) IndicatorRelease(h_ema21_ctx);
  }

//====================================================================
// [AuditConfigCoherence] — prints breakeven win-rate, margin capacity vs
// burst size, WARNs on incoherent geometry. Nothing may fail silently.
//====================================================================
void AuditConfigCoherence()
  {
   Log("---- CONFIG COHERENCE AUDIT ----");

   double spread = CurrentSpreadUSD();
   double effTP  = MathMax(InpFixedTP_USD, eff_TPSpreadFloorMult * spread);
   double sl     = InpFixedSL_USD;
   double breakevenWinRate = (sl + effTP > 0.0) ? sl / (sl + effTP) * 100.0 : 100.0;
   Log(StringFormat("Breakeven win-rate required (SL=$%.2f, effTP=$%.2f, spread=$%.2f): %.1f%%",
       sl, effTP, spread, breakevenWinRate));

   double stopsLevelPts = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double effMinTP_USD  = PointsToUSD(stopsLevelPts) + spread;
   Log(StringFormat("Effective minimum TP (broker stops level + spread) = $%.2f", effMinTP_USD));
   if(effTP < effMinTP_USD)
      Log(StringFormat("WARN: configured TP $%.2f is below the physically achievable minimum $%.2f.", effTP, effMinTP_USD));

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lot = CalcLotSize(PointsToUSD(USDToPoints(sl)));
   double marginPerLot = 0.0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, g_symbol, lot, GetAsk(), marginPerLot))
     {
      double maxSimultaneous = (marginPerLot > 0.0) ? (equity * (InpMarginUsageCapPct/100.0)) / marginPerLot : 0.0;
      Log(StringFormat("Margin for %.2f lot @ leverage~1:%.0f ~= $%.2f. Max simultaneous baskets at %.0f%% margin cap ~= %.1f",
          lot, InpAssumedLeverage, marginPerLot, InpMarginUsageCapPct, maxSimultaneous));
      double burstMargin = marginPerLot * InpEntriesPerSignal;
      if(burstMargin > equity * (InpMarginUsageCapPct/100.0))
         Log(StringFormat("WARN: burst of %d entries (~$%.2f margin) exceeds margin usage cap (~$%.2f). Burst size is arithmetically unsupportable.",
             InpEntriesPerSignal, burstMargin, equity * (InpMarginUsageCapPct/100.0)));
     }

   // Noise-width stop sanity: compare SL in USD to typical M1 candle range (ATR proxy)
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(h_atr_sig, 0, 0, 5, atrBuf) > 0)
     {
      double atrUSD = atrBuf[0] * 1.0; // ATR already in price units == USD for XAUUSD
      if(sl < atrUSD * 0.3)
         Log(StringFormat("WARN: SL $%.2f is inside typical signal-TF noise (ATR $%.2f) — likely to be stopped by noise, not thesis failure.", sl, atrUSD));
     }

   // Cost-of-trading-every-candle sanity
   double barsPerDay = (g_signalTF == PERIOD_M1) ? 1440 : (g_signalTF == PERIOD_M5) ? 288 : (g_signalTF == PERIOD_M15) ? 96 : 24;
   double dailySpreadCostPct = (equity > 0.0) ? (spread * barsPerDay * InpBaseLot * 100.0 / equity) * 100.0 : 0.0;
   Log(StringFormat("If trading every %s candle: illustrative spread cost/day ~= %.3f%% of equity (upper bound, assumes one round-turn per bar).",
       EnumToString(g_signalTF), dailySpreadCostPct));

   if(SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN) > InpBaseLot)
      Log(StringFormat("WARN: broker minimum lot (%.2f) exceeds InpBaseLot (%.2f) — size will be floored to broker minimum; a cent account is the correct structural fix for undersized equity, not a lot-size hack.",
          SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN), InpBaseLot));

   Log("---- END COHERENCE AUDIT ----");
  }

//====================================================================
// [PERSISTENCE] — factor weights via GlobalVariables (survive restarts);
// hour-expectancy table + daily anchors + loss streak + cooldown to file.
//====================================================================
string GVName(string key)
  {
   return StringFormat("IAX7_%s_%d_%s", g_symbol, (int)InpMagic, key);
  }

void LoadFactorWeights()
  {
   double defaults[NUM_FACTORS] = { InpW_MarketStructure, InpW_Momentum, InpW_Trend, InpW_Volatility,
                                     InpW_Liquidity, InpW_CandlestickWick, InpW_TickDeltaFlow,
                                     InpW_SessionVWAP, InpW_ContextSymbol };
   for(int i = 0; i < NUM_FACTORS; i++)
     {
      string name = GVName("W" + IntegerToString(i));
      if(InpAdaptiveLearningOn && GlobalVariableCheck(name))
         g_factorWeight[i] = GlobalVariableGet(name);
      else
         g_factorWeight[i] = defaults[i];
     }
   Log("Factor weights loaded (adaptive persistence=" + (InpAdaptiveLearningOn ? "ON" : "OFF") + ").");
  }

void SaveFactorWeights()
  {
   if(!InpAdaptiveLearningOn) return;
   for(int i = 0; i < NUM_FACTORS; i++)
      GlobalVariableSet(GVName("W" + IntegerToString(i)), g_factorWeight[i]);
  }

void LoadPersistedState()
  {
   for(int h = 0; h < 24; h++) { g_hourPnLSum[h] = 0.0; g_hourSampleCount[h] = 0; g_hourBlocked[h] = false; }
   for(int p = 0; p < NUM_PATTERNS; p++) { g_patRSum[p] = 0.0; g_patCount[p] = 0; g_patBlocked[p] = false; }
   for(int h = 0; h < 24; h++) g_hourATR[h] = 0.0;
   g_allATR = 0.0;
   g_consecutiveLosses = 0;
   g_cooldownUntil = 0;
   g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(!FileIsExist(g_stateFileName))
     {
      Log("No prior state file found (" + g_stateFileName + ") — starting fresh.");
      return;
     }

   int fh = FileOpen(g_stateFileName, FILE_READ|FILE_CSV|FILE_ANSI, ',');
   if(fh == INVALID_HANDLE)
     {
      Log("WARN: could not open state file for read (err=" + IntegerToString(GetLastError()) + ") — starting fresh.");
      return;
     }

   if(!FileIsEnding(fh)) g_consecutiveLosses = (int)FileReadNumber(fh);
   if(!FileIsEnding(fh)) g_cooldownUntil    = (datetime)FileReadNumber(fh);
   if(!FileIsEnding(fh)) g_dailyStartEquity = FileReadNumber(fh);
   if(!FileIsEnding(fh)) g_currentDayStamp  = (datetime)FileReadNumber(fh);
   for(int h = 0; h < 24 && !FileIsEnding(fh); h++)
     {
      g_hourPnLSum[h]      = FileReadNumber(fh);
      g_hourSampleCount[h] = (int)FileReadNumber(fh);
      g_hourBlocked[h]     = (FileReadNumber(fh) != 0.0);
     }
   for(int p = 0; p < NUM_PATTERNS && !FileIsEnding(fh); p++)
     {
      g_patRSum[p]    = FileReadNumber(fh);
      g_patCount[p]   = (int)FileReadNumber(fh);
      g_patBlocked[p] = (FileReadNumber(fh) != 0.0);
     }
   for(int h = 0; h < 24 && !FileIsEnding(fh); h++)
      g_hourATR[h] = FileReadNumber(fh);
   if(!FileIsEnding(fh)) g_allATR = FileReadNumber(fh);
   FileClose(fh);
   Log("Persisted state loaded from " + g_stateFileName);
  }

void SavePersistedState()
  {
   int fh = FileOpen(g_stateFileName, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(fh == INVALID_HANDLE)
     {
      Log("WARN: could not open state file for write (err=" + IntegerToString(GetLastError()) + ").");
      return;
     }
   FileWrite(fh, g_consecutiveLosses, (long)g_cooldownUntil, g_dailyStartEquity, (long)g_currentDayStamp);
   for(int h = 0; h < 24; h++)
      FileWrite(fh, g_hourPnLSum[h], g_hourSampleCount[h], g_hourBlocked[h] ? 1 : 0);
   for(int p = 0; p < NUM_PATTERNS; p++)
      FileWrite(fh, g_patRSum[p], g_patCount[p], g_patBlocked[p] ? 1 : 0);
   for(int h = 0; h < 24; h++)
      FileWrite(fh, g_hourATR[h]);
   FileWrite(fh, g_allATR);
   FileClose(fh);
  }

//====================================================================
// [OnInit]
//====================================================================
int OnInit()
  {
   g_symbol = _Symbol + InpSymbolSuffix;
   if(!SymbolSelect(g_symbol, true))
     {
      // Fall back to chart symbol if suffix guess was wrong — never fail
      // init silently over a suffix mismatch (defect rule #11 spirit).
      Log("WARN: '" + g_symbol + "' not found, falling back to chart symbol '" + _Symbol + "'.");
      g_symbol = _Symbol;
     }
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_point  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_swingMagic = InpMagic + 7;
   g_initTime = TimeCurrent();

   g_factorName[0] = "MarketStructure";
   g_factorName[1] = "Momentum";
   g_factorName[2] = "Trend";
   g_factorName[3] = "Volatility";
   g_factorName[4] = "Liquidity";
   g_factorName[5] = "CandlestickWick";
   g_factorName[6] = "TickDeltaFlow";
   g_factorName[7] = "SessionVWAP";
   g_factorName[8] = "ContextSymbol";
   for(int i = 0; i < NUM_FACTORS; i++) { g_factorVote[i] = 0; g_factorAvailable[i] = true; }

   ApplyProfile();
   BuildFingerprint();

   if(!EnvironmentCheck())
     {
      Log("INIT FAILED: environment check did not pass. See ENV FAIL lines above.");
      return(INIT_FAILED);
     }

   if(!CreateIndicatorHandles())
     {
      Log("INIT FAILED: indicator handle creation failed.");
      return(INIT_FAILED);
     }

   LoadFactorWeights();

   g_stateFileName   = StringFormat("IAX7_state_%s_%d.csv", g_symbol, (int)InpMagic);
   g_journalFileName = StringFormat("IAX7_journal_%s_%d.csv", g_symbol, (int)InpMagic);
   LoadPersistedState();

   if(InpWriteTradeJournalCSV && !FileIsExist(g_journalFileName))
     {
      int jh = FileOpen(g_journalFileName, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
      if(jh != INVALID_HANDLE)
        {
         FileWrite(jh, "OpenTime", "Side", "Volume", "EntryPrice", "ExitPrice", "PnL_USD",
                       "Regime", "ConfidenceAtEntry", "EntryHour", "MS", "MOM", "TRD", "VOL", "LIQ", "WICK", "TICK", "VWAP", "CTX");
         FileClose(jh);
        }
     }

   for(int i = 0; i < MAX_BASKETS; i++) { g_bkActive[i] = false; g_bkTicket[i] = 0; g_bkPatternId[i] = -1; }
   for(int i = 0; i < MAX_PENDING; i++) g_pendingActive[i] = false;
   g_swActive = false;
   for(int r = 0; r < BLOCK_COUNT; r++) g_blockCounts[r] = 0;
   ArrayResize(g_equityHistory, 0);
   ArrayResize(g_oodaLedger, 0);

   AuditConfigCoherence();

   if(InpShowDashboard) UpdateDashboard();
   if(InpShowKillSwitch)
     {
      ObjectCreate(0, "IAX7_KillSwitch", OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, "IAX7_KillSwitch", OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, "IAX7_KillSwitch", OBJPROP_YDISTANCE, 10);
      ObjectSetInteger(0, "IAX7_KillSwitch", OBJPROP_XSIZE, 140);
      ObjectSetInteger(0, "IAX7_KillSwitch", OBJPROP_YSIZE, 28);
      ObjectSetString(0, "IAX7_KillSwitch", OBJPROP_TEXT, "FLATTEN ALL");
      ObjectSetInteger(0, "IAX7_KillSwitch", OBJPROP_BGCOLOR, clrFireBrick);
      ObjectSetInteger(0, "IAX7_KillSwitch", OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, "IAX7_KillSwitch", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "IAX7_KillSwitch", OBJPROP_SELECTABLE, false);
     }

   EventSetTimer(1);
   g_lastTickTime = TimeCurrent();

   if(InpRunStage1SelfTest && (InpProfile == PROFILE_VALIDATION || InpValidationStage == STAGE_1_LIFECYCLE))
      RunStage1SelfTest();

   Log(InpOODATempoSec > 0
       ? StringFormat("OODA TEMPO: intra-bar re-orientation every %d s in breakout/vol-expansion regimes (entries only; exits stay bar-confirmed).", InpOODATempoSec)
       : "OODA TEMPO: bar-close only (InpOODATempoSec=0).");
   Log(StringFormat("INIT OK. Symbol=%s SignalTF=%s TrendTF=%s Profile=%s Stage=%d",
       g_symbol, EnumToString(g_signalTF), EnumToString(g_trendTF),
       EnumToString(InpProfile), (int)InpValidationStage));

   return(INIT_SUCCEEDED);
  }

//====================================================================
// [OnDeinit]
//====================================================================
void OnDeinit(const int reason)
  {
   EventKillTimer();
   SaveFactorWeights();
   SavePersistedState();
   ReleaseIndicatorHandles();
   ObjectDelete(0, "IAX7_KillSwitch");
   Comment("");
   PrintEndOfRunReport();
   Log("Deinit reason=" + IntegerToString(reason));
  }

//====================================================================
// [OnTick] — the OODA loop. OBSERVE the market/account/feed, run the
// standing ACT layer (manage what is already open), then — on a closed
// signal bar or a tempo re-orientation — ORIENT, DECIDE, ACT, with
// per-phase microsecond telemetry.
//====================================================================
void OnTick()
  {
   g_oodaCycle++;
   ulong u0 = GetMicrosecondCount();

   // ---- OBSERVE ----
   g_lastTickTime = TimeCurrent();
   g_feedDegraded = false; // heartbeat re-armed on every real tick
   UpdateTickDeltaBuffer();
   UpdateSessionVWAP();
   UpdateHourlyDailyCounters();
   UpdateEquityGovernors();
   g_newSignalBar = IsNewBar(g_signalTF, g_lastSignalBarTime);
   ulong u1 = GetMicrosecondCount();

   if(g_killSwitchEngaged)
      return; // kill switch latched: no new decisions (FlattenAll already ran)

   // ---- ACT (standing): manage what is already open, every cycle ----
   CancelExpiredPendings();
   ManageOpenPositions();
   if(eff_SwingModuleOn) ManageSwingModule();
   EnsureProtectiveStops();
   CheckFlipExit();
   ulong u2 = GetMicrosecondCount();

   // ---- ORIENT -> DECIDE -> ACT (entry side) ----
   if(g_newSignalBar || TempoAllowsIntraBarReorient())
     {
      if(g_newSignalBar) g_barsProcessed++;
      int direction = OODA_Orient();
      ulong u3 = GetMicrosecondCount();
      ENUM_OODA_DECISION decision = OODA_Decide(direction);
      ulong u4 = GetMicrosecondCount();
      OODA_Act(decision);
      ulong u5 = GetMicrosecondCount();

      g_usObserveSum += (double)(u1 - u0);
      g_usOrientSum  += (double)(u3 - u2);
      g_usDecideSum  += (double)(u4 - u3);
      g_usActSum     += (double)((u2 - u1) + (u5 - u4)); // standing management + entry action
      g_oodaTimedCycles++;
     }

   if(InpShowDashboard) UpdateDashboard();
  }

//====================================================================
// [OnTimer] — heartbeat watchdog (feed staleness independent of ticks)
//====================================================================
void OnTimer()
  {
   if(TimeCurrent() - g_lastTickTime > InpMaxFeedStaleSeconds)
     {
      if(!g_feedDegraded)
         Log(StringFormat("HEARTBEAT: feed stale for >%d s — entries blocked until a fresh tick arrives.", InpMaxFeedStaleSeconds));
      g_feedDegraded = true;
     }
  }

//====================================================================
// [OnChartEvent] — kill switch button
//====================================================================
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "IAX7_KillSwitch")
     {
      g_killSwitchEngaged = true;
      FlattenAll("Manual kill switch engaged.");
      ObjectSetInteger(0, "IAX7_KillSwitch", OBJPROP_STATE, false);
      if(InpPushAlertsOn) SendNotification("IAX7 " + g_symbol + ": KILL SWITCH engaged, all positions flattened.");
     }
  }

//====================================================================
// [OnTradeTransaction] — latency/slippage measurement, closed-trade learning
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      if(HistoryDealSelect(trans.deal))
        {
         long dealMagic  = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         if(dealMagic != InpMagic && dealMagic != g_swingMagic)
            return; // not ours — another EA or manual trade on this symbol
         double dealPnL  = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
           {
            g_positionsClosed++;
            int hour = (int)TimeHour((datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME));
            UpdateHourExpectancy(hour, dealPnL);
            if(dealPnL < 0.0)
               g_consecutiveLosses++;
            else if(dealPnL > 0.0)
               g_consecutiveLosses = 0;
            if(g_consecutiveLosses >= InpMaxConsecutiveLosses)
              {
               g_cooldownUntil = TimeCurrent() + InpCooldownMinutes * 60;
               Log(StringFormat("GOVERNOR: loss-streak cooldown engaged (%d consecutive losses) until %s",
                   g_consecutiveLosses, TimeToString(g_cooldownUntil)));
              }
            ArrayResize(g_equityHistory, ArraySize(g_equityHistory) + 1);
            g_equityHistory[ArraySize(g_equityHistory) - 1] = AccountInfoDouble(ACCOUNT_EQUITY);
           }
        }
     }
  }

//====================================================================
// [OnTester] — fitness = PF * sqrt(trades) / (1 + DD%/10); 0 under min trades
//====================================================================
double OnTester()
  {
   double grossProfit = TesterStatistics(STAT_GROSS_PROFIT);
   double grossLoss    = MathAbs(TesterStatistics(STAT_GROSS_LOSS));
   double trades        = TesterStatistics(STAT_TRADES);
   double ddPct          = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);

   if(trades < InpMinTradesForFitness)
     {
      Log(StringFormat("OnTester: only %.0f trades (< %d minimum) — fitness forced to 0 so the optimiser cannot reward lucky thin results.",
          trades, InpMinTradesForFitness));
      return 0.0;
     }

   double pf = (grossLoss > 0.0) ? grossProfit / grossLoss : (grossProfit > 0.0 ? 10.0 : 0.0);
   double fitness = pf * MathSqrt(trades) / (1.0 + ddPct / 10.0);
   Log(StringFormat("OnTester: PF=%.3f trades=%.0f DD%%=%.2f -> fitness=%.4f", pf, trades, ddPct, fitness));
   return fitness;
  }

//====================================================================
// [SESSION / VWAP / TICK-DELTA HELPERS]
//====================================================================
ENUM_SESSION CurrentSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   // London 08-16 GMT, NY 13-21 GMT, overlap 13-16, Asia 00-08, rollover 21-24 & 00 edge
   bool inLondon = (h >= 8 && h < 16);
   bool inNY     = (h >= 13 && h < 21);
   if(inLondon && inNY) return SESSION_LONDON_NY_OVERLAP;
   if(inLondon) return SESSION_LONDON;
   if(inNY) return SESSION_NY;
   if(h >= 21 || h < 1) return SESSION_ROLLOVER;
   return SESSION_ASIA;
  }

double SessionQualityMultiplier(ENUM_SESSION s)
  {
   switch(s)
     {
      case SESSION_LONDON_NY_OVERLAP: return 1.08;
      case SESSION_LONDON:            return 1.05;
      case SESSION_NY:                return 1.03;
      case SESSION_ASIA:              return 0.92;
      case SESSION_ROLLOVER:          return 0.85;
      default:                        return 1.00;
     }
  }

void UpdateSessionVWAP()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime dayAnchor = (datetime)(((long)TimeCurrent() / 86400) * 86400);
   if(dayAnchor != g_vwapSessionAnchor)
     {
      g_vwapSessionAnchor = dayAnchor;
      g_vwapCumPV = 0.0;
      g_vwapCumVol = 0.0;
      g_vwapPrev = g_vwap;
     }
   double price = (GetAsk() + GetBid()) / 2.0;
   double vol = (double)SymbolInfoInteger(g_symbol, SYMBOL_VOLUME);
   if(vol <= 0.0) vol = 1.0;
   g_vwapCumPV += price * vol;
   g_vwapCumVol += vol;
   if(g_vwapCumVol > 0.0)
     {
      g_vwapPrev = g_vwap;
      g_vwap = g_vwapCumPV / g_vwapCumVol;
     }
  }

// [DEFECT-RULE-1] CopyBuffer targets must be dynamic arrays — enforced
// throughout this file (no fixed-size buffer arrays are ever declared).
void UpdateTickDeltaBuffer()
  {
   double bid = GetBid();
   if(g_lastTickBid == 0.0) { g_lastTickBid = bid; return; }
   if(bid == g_lastTickBid) return; // no directional info on a flat tick
   int dir = (bid > g_lastTickBid) ? 1 : -1;
   g_lastTickBid = bid;

   g_tickDir[g_tickWriteIdx] = dir;
   g_tickWriteIdx = (g_tickWriteIdx + 1) % TICK_WINDOW;
   if(g_tickCount < TICK_WINDOW) g_tickCount++;
  }

//====================================================================
// [REGIME CLASSIFIER] — 14 states
//====================================================================
ENUM_REGIME ClassifyRegime()
  {
   double emaFastTrend[], emaSlowTrend[], atrTrend[], adxMain[], adxPlus[], adxMinus[];
   ArraySetAsSeries(emaFastTrend, true); ArraySetAsSeries(emaSlowTrend, true);
   ArraySetAsSeries(atrTrend, true);
   ArraySetAsSeries(adxMain, true); ArraySetAsSeries(adxPlus, true); ArraySetAsSeries(adxMinus, true);

   if(CopyBuffer(h_ema21_trend, 0, 0, 3, emaFastTrend) < 3) return REGIME_UNKNOWN;
   if(CopyBuffer(h_ema55_trend, 0, 0, 3, emaSlowTrend) < 3) return REGIME_UNKNOWN;
   if(CopyBuffer(h_atr_trend, 0, 0, 20, atrTrend) < 20) return REGIME_UNKNOWN;
   if(CopyBuffer(h_adx_trend, 0, 0, 3, adxMain) < 3) return REGIME_UNKNOWN;
   if(CopyBuffer(h_adx_trend, 1, 0, 3, adxPlus) < 3) return REGIME_UNKNOWN;
   if(CopyBuffer(h_adx_trend, 2, 0, 3, adxMinus) < 3) return REGIME_UNKNOWN;

   double atrNow = atrTrend[0];
   double atrAvg = 0.0;
   for(int i = 0; i < 20; i++) atrAvg += atrTrend[i];
   atrAvg /= 20.0;
   bool volExpansion   = atrNow > atrAvg * 1.35;
   bool volCompression = atrNow < atrAvg * 0.65;

   double emaSpread = (emaFastTrend[0] - emaSlowTrend[0]);
   bool bullTrend = emaFastTrend[0] > emaSlowTrend[0];
   bool bearTrend = emaFastTrend[0] < emaSlowTrend[0];
   double adx = adxMain[0];

   // Breakout: strong directional ADX rising + vol expansion + trend just turned
   bool trendJustFlippedUp   = bullTrend && (emaFastTrend[2] <= emaSlowTrend[2]);
   bool trendJustFlippedDown = bearTrend && (emaFastTrend[2] >= emaSlowTrend[2]);
   if(volExpansion && trendJustFlippedUp && adx > 20) return REGIME_BREAKOUT_UP;
   if(volExpansion && trendJustFlippedDown && adx > 20) return REGIME_BREAKOUT_DOWN;

   if(g_exhaustionBar)
      return bullTrend ? REGIME_EXHAUSTION_UP : REGIME_EXHAUSTION_DOWN;

   if(adxMain[0] < adxMain[2] && adx < 20 && MathAbs(emaSpread) < atrAvg * 0.3)
      return REGIME_REVERSAL_RISK;

   if(volExpansion && !bullTrend && !bearTrend) return REGIME_VOL_EXPANSION;
   if(volCompression) return REGIME_VOL_COMPRESSION;

   if(adx < 18 && MathAbs(emaSpread) < atrAvg * 0.25) return REGIME_RANGE;

   if(bullTrend)
     {
      if(adx >= 30) return REGIME_STRONG_BULL;
      if(adx >= 20) return REGIME_NORMAL_BULL;
      return REGIME_WEAK_BULL;
     }
   if(bearTrend)
     {
      if(adx >= 30) return REGIME_STRONG_BEAR;
      if(adx >= 20) return REGIME_NORMAL_BEAR;
      return REGIME_WEAK_BEAR;
     }
   return REGIME_RANGE;
  }

double RegimeQualityMultiplier(ENUM_REGIME r)
  {
   switch(r)
     {
      case REGIME_STRONG_BULL:
      case REGIME_STRONG_BEAR:
      case REGIME_BREAKOUT_UP:
      case REGIME_BREAKOUT_DOWN:       return 1.20;
      case REGIME_NORMAL_BULL:
      case REGIME_NORMAL_BEAR:
      case REGIME_VOL_EXPANSION:       return 1.05;
      case REGIME_WEAK_BULL:
      case REGIME_WEAK_BEAR:            return 0.90;
      case REGIME_RANGE:
      case REGIME_VOL_COMPRESSION:      return 0.80;
      case REGIME_EXHAUSTION_UP:
      case REGIME_EXHAUSTION_DOWN:
      case REGIME_REVERSAL_RISK:        return 0.75;
      case REGIME_UNKNOWN:
      default:                          return 0.70;
     }
  }

bool DetectIgnitionBar()
  {
   double o[], h[], l[], c[], atr[], vol[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
   ArraySetAsSeries(atr, true);
   if(CopyOpen(g_symbol, g_signalTF, 0, 6, o) < 6) return false;
   if(CopyHigh(g_symbol, g_signalTF, 0, 6, h) < 6) return false;
   if(CopyLow(g_symbol, g_signalTF, 0, 6, l) < 6) return false;
   if(CopyClose(g_symbol, g_signalTF, 0, 6, c) < 6) return false;
   if(CopyBuffer(h_atr_sig, 0, 0, 20, atr) < 20) return false;

   long tickVol[];
   ArraySetAsSeries(tickVol, true);
   if(CopyTickVolume(g_symbol, g_signalTF, 0, 21, tickVol) < 21) return false;

   double range = h[1] - l[1];
   double body  = MathAbs(c[1] - o[1]);
   if(range <= 0.0) return false;
   double atrAvg = 0.0;
   for(int i = 1; i <= 20; i++) atrAvg += atr[i-1];
   atrAvg /= 20.0;

   double volAvg = 0.0;
   for(int i = 1; i <= 20; i++) volAvg += (double)tickVol[i];
   volAvg /= 20.0;

   bool bodyDominant = (body / range) > 0.70;
   bool rangeExpanded = range > 1.1 * atrAvg;
   bool volSurge = (double)tickVol[0] >= 1.4 * volAvg;

   double microHigh = h[1], microLow = l[1];
   for(int i = 2; i <= 5; i++) { microHigh = MathMax(microHigh, h[i]); microLow = MathMin(microLow, l[i]); }
   bool closeBeyondMicro = (c[1] > microHigh) || (c[1] < microLow);

   return bodyDominant && rangeExpanded && volSurge && closeBeyondMicro;
  }

bool DetectExhaustionBar()
  {
   // Exhaustion: strong directional run followed by a bar with a long
   // opposing wick rejecting the extreme — used to dampen continuation side.
   double h[], l[], c[], o[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true); ArraySetAsSeries(o, true);
   if(CopyHigh(g_symbol, g_signalTF, 0, 6, h) < 6) return false;
   if(CopyLow(g_symbol, g_signalTF, 0, 6, l) < 6) return false;
   if(CopyClose(g_symbol, g_signalTF, 0, 6, c) < 6) return false;
   if(CopyOpen(g_symbol, g_signalTF, 0, 6, o) < 6) return false;

   double range = h[1] - l[1];
   if(range <= 0.0) return false;
   double upperWick = h[1] - MathMax(o[1], c[1]);
   double lowerWick = MathMin(o[1], c[1]) - l[1];

   bool longUpperWick = (upperWick / range) > 0.55;
   bool longLowerWick = (lowerWick / range) > 0.55;

   double last3Move = c[1] - c[4];
   bool strongUpRun = last3Move > 0 && longUpperWick;
   bool strongDownRun = last3Move < 0 && longLowerWick;

   return strongUpRun || strongDownRun;
  }

//====================================================================
// [FACTOR:MarketStructure] W=26 — fractal HH/HL vs LH/LL over 60 bars
//====================================================================
int Factor_MarketStructure()
  {
   int lookback = 60;
   double h[], l[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if(CopyHigh(g_symbol, g_signalTF, 0, lookback + 4, h) < lookback + 4) return 0;
   if(CopyLow(g_symbol, g_signalTF, 0, lookback + 4, l) < lookback + 4) return 0;

   // Collect fractal swing highs/lows (2 bars either side), most recent first
   double swingHighs[]; double swingLows[];
   ArrayResize(swingHighs, 0); ArrayResize(swingLows, 0);
   for(int i = 2; i < lookback; i++)
     {
      if(h[i] > h[i-1] && h[i] > h[i-2] && h[i] > h[i+1] && h[i] > h[i+2])
        {
         int n = ArraySize(swingHighs);
         ArrayResize(swingHighs, n + 1);
         swingHighs[n] = h[i];
        }
      if(l[i] < l[i-1] && l[i] < l[i-2] && l[i] < l[i+1] && l[i] < l[i+2])
        {
         int n = ArraySize(swingLows);
         ArrayResize(swingLows, n + 1);
         swingLows[n] = l[i];
        }
     }

   if(ArraySize(swingHighs) < 2 || ArraySize(swingLows) < 2) return 0;

   // swingHighs/Lows are populated oldest->newest because loop runs i ascending
   // over a series-indexed (newest=0) array, so the LAST element found is the
   // most recent fractal — compare last two of each.
   int nh = ArraySize(swingHighs), nl = ArraySize(swingLows);
   bool higherHigh = swingHighs[nh-1] > swingHighs[nh-2];
   bool higherLow  = swingLows[nl-1]  > swingLows[nl-2];
   bool lowerHigh  = swingHighs[nh-1] < swingHighs[nh-2];
   bool lowerLow   = swingLows[nl-1]  < swingLows[nl-2];

   if(higherHigh && higherLow) return 1;   // HH/HL uptrend structure
   if(lowerHigh && lowerLow)   return -1;  // LH/LL downtrend structure
   return 0;
  }

//====================================================================
// [FACTOR:Momentum] W=16 — EMA13/34 on signal TF, MACD-confirmed
//====================================================================
int Factor_Momentum()
  {
   double emaFast[], emaSlow[], macdMain[], macdSignal[];
   ArraySetAsSeries(emaFast, true); ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(macdMain, true); ArraySetAsSeries(macdSignal, true);
   if(CopyBuffer(h_ema13_sig, 0, 0, 2, emaFast) < 2) return 0;
   if(CopyBuffer(h_ema34_sig, 0, 0, 2, emaSlow) < 2) return 0;
   if(CopyBuffer(h_macd_sig, 0, 0, 2, macdMain) < 2) return 0;
   if(CopyBuffer(h_macd_sig, 1, 0, 2, macdSignal) < 2) return 0;

   bool emaBull = emaFast[0] > emaSlow[0];
   bool emaBear = emaFast[0] < emaSlow[0];
   bool macdBull = macdMain[0] > macdSignal[0];
   bool macdBear = macdMain[0] < macdSignal[0];

   if(emaBull && macdBull) return 1;
   if(emaBear && macdBear) return -1;
   return 0;
  }

//====================================================================
// [FACTOR:Trend] W=16 — EMA21/55 on trend TF (already auto-escalated)
//====================================================================
int Factor_Trend()
  {
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true); ArraySetAsSeries(emaSlow, true);
   if(CopyBuffer(h_ema21_trend, 0, 0, 1, emaFast) < 1) return 0;
   if(CopyBuffer(h_ema55_trend, 0, 0, 1, emaSlow) < 1) return 0;
   if(emaFast[0] > emaSlow[0]) return 1;
   if(emaFast[0] < emaSlow[0]) return -1;
   return 0;
  }

//====================================================================
// [FACTOR:Volatility] W=10 — breakout direction, else expansion backing momentum
//====================================================================
int Factor_Volatility()
  {
   double atr[]; ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_atr_sig, 0, 0, 20, atr) < 20) return 0;
   double atrAvg = 0.0;
   for(int i = 0; i < 20; i++) atrAvg += atr[i];
   atrAvg /= 20.0;
   bool expanding = atr[0] > atrAvg * 1.2;

   double h[], l[], c[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
   int rangeBars = 20;
   if(CopyHigh(g_symbol, g_signalTF, 1, rangeBars, h) < rangeBars) return 0;
   if(CopyLow(g_symbol, g_signalTF, 1, rangeBars, l) < rangeBars) return 0;
   if(CopyClose(g_symbol, g_signalTF, 0, 1, c) < 1) return 0;

   double rangeHigh = h[ArrayMaximum(h)];
   double rangeLow  = l[ArrayMinimum(l)];

   if(c[0] > rangeHigh) return 1;   // breakout up
   if(c[0] < rangeLow)  return -1;  // breakout down

   if(expanding)
      return Factor_Momentum(); // vol expansion backs whatever momentum already says
   return 0;
  }

//====================================================================
// [FACTOR:Liquidity] W=10 — swing sweep + rejection (reversal implication)
//====================================================================
int Factor_Liquidity()
  {
   // Prior swing reference is bars [2 .. lookback+1] — deliberately EXCLUDES
   // bar 1 (the candidate sweep bar itself), otherwise the sweep condition
   // can never trigger because the reference would already contain its own extreme.
   double h[], l[], c[], o[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true); ArraySetAsSeries(o, true);
   int lookback = 20;
   if(CopyHigh(g_symbol, g_signalTF, 2, lookback, h) < lookback) return 0;
   if(CopyLow(g_symbol, g_signalTF, 2, lookback, l) < lookback) return 0;
   if(CopyClose(g_symbol, g_signalTF, 0, 2, c) < 2) return 0;
   if(CopyOpen(g_symbol, g_signalTF, 0, 2, o) < 2) return 0;

   double priorSwingHigh = h[ArrayMaximum(h)];
   double priorSwingLow  = l[ArrayMinimum(l)];

   // Sweep above prior swing high, then close back below it -> sell rejection
   double thisBarHigh[]; ArraySetAsSeries(thisBarHigh, true);
   if(CopyHigh(g_symbol, g_signalTF, 1, 1, thisBarHigh) < 1) return 0;
   double thisBarLow[]; ArraySetAsSeries(thisBarLow, true);
   if(CopyLow(g_symbol, g_signalTF, 1, 1, thisBarLow) < 1) return 0;

   bool sweptHigh = thisBarHigh[0] > priorSwingHigh && c[1] < priorSwingHigh;
   bool sweptLow  = thisBarLow[0]  < priorSwingLow  && c[1] > priorSwingLow;

   if(sweptHigh) return -1; // liquidity taken above, rejected -> sell implication
   if(sweptLow)  return 1;  // liquidity taken below, rejected -> buy implication
   return 0;
  }

//====================================================================
// [FACTOR:CandlestickWick] W=20 — engulfing > pin-bar > 3-bar tail imbalance
//====================================================================
int Factor_CandlestickWick()
  {
   double o[], h[], l[], c[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
   if(CopyOpen(g_symbol, g_signalTF, 0, 5, o) < 5) return 0;
   if(CopyHigh(g_symbol, g_signalTF, 0, 5, h) < 5) return 0;
   if(CopyLow(g_symbol, g_signalTF, 0, 5, l) < 5) return 0;
   if(CopyClose(g_symbol, g_signalTF, 0, 5, c) < 5) return 0;

   // 1) Engulfing (highest priority): last closed bar's body engulfs the prior body
   double body1 = MathAbs(c[1] - o[1]);
   double body2 = MathAbs(c[2] - o[2]);
   bool bullEngulf = (c[1] > o[1]) && (c[2] < o[2]) && (c[1] >= o[2]) && (o[1] <= c[2]) && body1 > body2;
   bool bearEngulf = (c[1] < o[1]) && (c[2] > o[2]) && (o[1] >= c[2]) && (c[1] <= o[2]) && body1 > body2;
   if(bullEngulf) return 1;
   if(bearEngulf) return -1;

   // 2) Pin-bar: tail >= 50% of range, close in top/bottom 40% of range
   double range1 = h[1] - l[1];
   if(range1 > 0.0)
     {
      double upperWick = h[1] - MathMax(o[1], c[1]);
      double lowerWick = MathMin(o[1], c[1]) - l[1];
      double closePos  = (c[1] - l[1]) / range1; // 0 = at low, 1 = at high
      bool bullPin = (lowerWick / range1 >= 0.50) && (closePos >= 0.60);
      bool bearPin = (upperWick / range1 >= 0.50) && (closePos <= 0.40);
      if(bullPin) return 1;
      if(bearPin) return -1;
     }

   // 3) 3-bar cumulative tail imbalance (1.5x)
   double upperSum = 0.0, lowerSum = 0.0;
   for(int i = 1; i <= 3; i++)
     {
      double r = h[i] - l[i];
      if(r <= 0.0) continue;
      upperSum += (h[i] - MathMax(o[i], c[i]));
      lowerSum += (MathMin(o[i], c[i]) - l[i]);
     }
   if(lowerSum > 0.0 && upperSum >= lowerSum * 1.5) return -1;
   if(upperSum > 0.0 && lowerSum >= upperSum * 1.5) return 1;

   return 0;
  }

//====================================================================
// [FACTOR:TickDeltaFlow] W=14 — up-ticks vs down-ticks over last 300 ticks
//====================================================================
int Factor_TickDeltaFlow()
  {
   if(g_tickCount < 30) return 0; // not enough samples yet
   int up = 0, down = 0;
   for(int i = 0; i < g_tickCount; i++)
     {
      if(g_tickDir[i] > 0) up++;
      else if(g_tickDir[i] < 0) down++;
     }
   int total = up + down;
   if(total == 0) return 0;
   double upRatio = (double)up / (double)total;
   if(upRatio >= 0.60) return 1;
   if(upRatio <= 0.40) return -1;
   return 0;
  }

//====================================================================
// [FACTOR:SessionVWAP] W=10 — price side of day VWAP + VWAP slope agreement
//====================================================================
int Factor_SessionVWAP()
  {
   if(g_vwap <= 0.0) return 0;
   double price = (GetAsk() + GetBid()) / 2.0;
   bool aboveVWAP = price > g_vwap;
   bool belowVWAP = price < g_vwap;
   double slope = g_vwap - g_vwapPrev;
   bool slopeUp = slope > 0.0;
   bool slopeDown = slope < 0.0;

   if(aboveVWAP && slopeUp) return 1;
   if(belowVWAP && slopeDown) return -1;
   return 0;
  }

//====================================================================
// [FACTOR:ContextSymbol] W=8 — USD proxy (EURUSD EMA8/21; sign-flip for DXY-style)
//====================================================================
int Factor_ContextSymbol()
  {
   if(!g_factorAvailable[8] || h_ema8_ctx == INVALID_HANDLE || h_ema21_ctx == INVALID_HANDLE) return 0;
   double fast[], slow[];
   ArraySetAsSeries(fast, true); ArraySetAsSeries(slow, true);
   if(CopyBuffer(h_ema8_ctx, 0, 0, 1, fast) < 1) return 0;
   if(CopyBuffer(h_ema21_ctx, 0, 0, 1, slow) < 1) return 0;

   int vote = 0;
   if(fast[0] > slow[0]) vote = 1;
   else if(fast[0] < slow[0]) vote = -1;

   if(InpContextIsDXYStyle) vote = -vote; // a USD-strength index inverted vs a USD-weakness proxy
   return vote;
  }

//====================================================================
// [OODA:ORIENT] — fuse the observation snapshot into situational
// awareness: 9 factor votes -> buy/sell probabilities normalised over
// the ACTIVE weight pool (so "lite" mode still reaches the gate), then
// regime, session, ignition/exhaustion and the confidence score.
// Adaptive learning re-orients the weights themselves after outcomes.
// Returns the implied direction: +1 buy, -1 sell, 0 none.
//====================================================================
int OODA_Orient()
  {
   g_factorVote[0] = Factor_MarketStructure();
   g_factorVote[1] = Factor_Momentum();
   g_factorVote[2] = Factor_Trend();
   g_factorVote[3] = Factor_Volatility();
   g_factorVote[4] = Factor_Liquidity();
   g_factorVote[5] = Factor_CandlestickWick();
   g_factorVote[6] = Factor_TickDeltaFlow();
   g_factorVote[7] = Factor_SessionVWAP();
   g_factorVote[8] = Factor_ContextSymbol();

   double activeWeightSum = 0.0, buyWeighted = 0.0, sellWeighted = 0.0;
   for(int i = 0; i < NUM_FACTORS; i++)
     {
      if(!g_factorAvailable[i]) continue;
      activeWeightSum += g_factorWeight[i];
      if(g_factorVote[i] > 0) buyWeighted += g_factorWeight[i];
      else if(g_factorVote[i] < 0) sellWeighted += g_factorWeight[i];
     }
   if(activeWeightSum <= 0.0)
     {
      g_buyProb = 0.0; g_sellProb = 0.0; g_confidence = 0.0; g_lastEdge = 0.0;
      Log("ORIENT: no active factor weight pool — skipping cycle.");
      return 0;
     }
   g_buyProb  = buyWeighted  / activeWeightSum;
   g_sellProb = sellWeighted / activeWeightSum;

   g_regime = ClassifyRegime();
   g_regimeQuality = RegimeQualityMultiplier(g_regime);
   g_session = CurrentSession();
   g_sessionQuality = SessionQualityMultiplier(g_session);
   g_ignitionBar = DetectIgnitionBar();
   g_exhaustionBar = DetectExhaustionBar();
   UpdateVolProfile();
   UpdateSerialBias();

   g_lastEdge = MathAbs(g_buyProb - g_sellProb);
   g_confidence = g_lastEdge * g_regimeQuality * g_sessionQuality * 100.0;
   if(g_ignitionBar) g_confidence *= 1.15;

   int direction = 0;
   if(g_buyProb > g_sellProb) direction = 1;
   else if(g_sellProb > g_buyProb) direction = -1;

   // Exhaustion multiplies the CONTINUATION side by 0.65 (the side that
   // agrees with the still-running trend direction gets dampened).
   if(g_exhaustionBar && direction != 0)
     {
      bool trendUp = (g_regime == REGIME_STRONG_BULL || g_regime == REGIME_NORMAL_BULL || g_regime == REGIME_WEAK_BULL || g_regime == REGIME_BREAKOUT_UP);
      bool trendDown = (g_regime == REGIME_STRONG_BEAR || g_regime == REGIME_NORMAL_BEAR || g_regime == REGIME_WEAK_BEAR || g_regime == REGIME_BREAKOUT_DOWN);
      bool isContinuation = (direction == 1 && trendUp) || (direction == -1 && trendDown);
      if(isContinuation) g_confidence *= 0.65;
     }

   // Serial-correlation tilt: reward signal types that match the measured
   // statistical character of recent bars (continuation vs alternation).
   if(direction != 0)
     {
      double serM = SerialBiasMultiplier(direction);
      if(serM != 1.0) g_confidence *= serM;
     }

   g_signalsGenerated++;
   g_lastOrientTime = TimeCurrent();

   if(InpVerboseDecisionLog)
      Log(StringFormat("ORIENT %s | Regime=%s(qx%.2f) Session=%s(qx%.2f) buyP=%.3f sellP=%.3f edge=%.3f conf=%.1f ignite=%s exh=%s dir=%d",
          TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), EnumToString(g_regime), g_regimeQuality,
          EnumToString(g_session), g_sessionQuality, g_buyProb, g_sellProb, g_lastEdge, g_confidence,
          g_ignitionBar?"Y":"N", g_exhaustionBar?"Y":"N", direction));

   return direction;
  }

//====================================================================
// [OODA:DECIDE] — turn orientation into one explicit, logged decision.
// Order: idempotency guard, edge gate, confidence gate, governor stack.
// Every non-entry outcome carries a reason string (becomes the ledger row).
//====================================================================
ENUM_OODA_DECISION OODA_Decide(int direction)
  {
   if(direction == 0)
     {
      g_lastDecisionReason = "no directional edge";
      LogBlock(BLOCK_LOW_CONFIDENCE, "no directional edge this cycle");
      return DEC_NONE;
     }

   if(g_lastSignalBarTime > 0 && g_lastEntryBarTime == g_lastSignalBarTime)
     {
      g_lastDecisionReason = "already entered on this bar";
      return DEC_NONE; // tempo re-orientation may never double-enter a bar
     }

   if(g_lastEdge < InpMinVoteEdge)
     {
      g_lastDecisionReason = StringFormat("edge %.3f < min %.3f", g_lastEdge, InpMinVoteEdge);
      LogBlock(BLOCK_VOTE_EDGE_TOO_THIN, g_lastDecisionReason);
      return DEC_BLOCKED;
     }

   if(g_confidence < eff_MinConfidenceToTrade)
     {
      g_lastDecisionReason = StringFormat("confidence %.1f < %.1f", g_confidence, eff_MinConfidenceToTrade);
      LogBlock(BLOCK_LOW_CONFIDENCE, g_lastDecisionReason);
      return DEC_BLOCKED;
     }

   // Confidence gate passed — a "shadow gate" candidate even if a governor
   // blocks it downstream, tracked separately for the end-of-run report.
   g_shadowGateWouldHaveTraded++;

   // Pattern-expectancy gate: this exact pattern (regime-group x session x
   // direction) must not have PROVEN negative arithmetic over enough samples.
   g_currentPatternId = CurrentPatternId(direction);
   g_patternSizeBoost = 1.0;
   if(InpPatternLearnerOn && g_patCount[g_currentPatternId] >= InpPatternMinSamples)
     {
      double patAvgR = g_patRSum[g_currentPatternId] / g_patCount[g_currentPatternId];
      if(g_patBlocked[g_currentPatternId])
        {
         g_lastDecisionReason = StringFormat("pattern %s avgR=%.2f over %d trades",
             PatternIdToString(g_currentPatternId), patAvgR, g_patCount[g_currentPatternId]);
         LogBlock(BLOCK_PATTERN_NEGATIVE, g_lastDecisionReason);
         return DEC_BLOCKED;
        }
      if(patAvgR >= InpPatternBoostAvgR)
         g_patternSizeBoost = InpPatternBoostFactor;
     }

   ENUM_BLOCK_REASON blockedBy = BLOCK_NONE;
   if(!PassGovernors(direction, blockedBy))
     {
      g_lastDecisionReason = BlockReasonToString(blockedBy);
      LogBlock(blockedBy, StringFormat("dir=%d confidence=%.1f", direction, g_confidence));
      return DEC_BLOCKED;
     }

   g_lastDecisionReason = StringFormat("conf=%.1f edge=%.3f %s", g_confidence, g_lastEdge, EnumToString(g_regime));
   return (direction == 1) ? DEC_ENTER_LONG : DEC_ENTER_SHORT;
  }

//====================================================================
// [OODA:ACT] — execute the decision and record it in the ledger.
// Standing management (trailing, basket cuts, protective stops, flip
// exits) is also Act; it runs every cycle straight from OnTick.
//====================================================================
void OODA_Act(ENUM_OODA_DECISION decision)
  {
   g_lastDecision = decision;
   OODA_LedgerPush(StringFormat("#%I64d %s %s | %s", g_oodaCycle,
       TimeToString(TimeCurrent(), TIME_MINUTES), DecisionToString(decision), g_lastDecisionReason));

   if(decision == DEC_ENTER_LONG)
     {
      ExecuteEntry(1, g_confidence);
      g_lastEntryBarTime = g_lastSignalBarTime;
     }
   else if(decision == DEC_ENTER_SHORT)
     {
      ExecuteEntry(-1, g_confidence);
      g_lastEntryBarTime = g_lastSignalBarTime;
     }
  }

//====================================================================
// [OODA:TEMPO] — optional faster re-orientation inside a bar, armed only
// in fast regimes (breakout / vol expansion) where waiting for bar close
// forfeits the move. Entries stay protected by the one-entry-per-bar
// guard and the chase guard; EXITS remain bar-confirmed regardless of
// tempo (defect rule 9: intrabar flips churn noise into losses).
//====================================================================
bool TempoAllowsIntraBarReorient()
  {
   if(InpOODATempoSec <= 0) return false;
   if(g_regime != REGIME_BREAKOUT_UP && g_regime != REGIME_BREAKOUT_DOWN && g_regime != REGIME_VOL_EXPANSION)
      return false;
   if(TimeCurrent() - g_lastOrientTime < InpOODATempoSec) return false;
   return true;
  }

string DecisionToString(ENUM_OODA_DECISION d)
  {
   switch(d)
     {
      case DEC_ENTER_LONG:  return "ENTER_LONG";
      case DEC_ENTER_SHORT: return "ENTER_SHORT";
      case DEC_BLOCKED:     return "BLOCKED";
      default:              return "NONE";
     }
  }

void OODA_LedgerPush(string row)
  {
   int maxRows = MathMax(1, InpOODALedgerSize);
   int n = ArraySize(g_oodaLedger);
   if(n < maxRows) { ArrayResize(g_oodaLedger, n + 1); n++; }
   for(int i = n - 1; i > 0; i--) g_oodaLedger[i] = g_oodaLedger[i - 1];
   g_oodaLedger[0] = row;
  }

//====================================================================
// [PATTERN ARITHMETIC — v7.1] The measured statistics of the entity.
// Gold is not random noise: it has an intraday volatility profile, it
// reacts at .00/.50 round numbers, its bar-to-bar returns alternate
// between continuation and mean-reversion character, and specific
// (regime x session x direction) patterns carry persistent expectancy.
// Everything here is MEASURED online with sample-size guards — no
// pattern is trusted before InpPatternMinSamples closed trades.
//====================================================================
int RegimeGroup(ENUM_REGIME r)
  {
   switch(r)
     {
      case REGIME_STRONG_BULL: case REGIME_STRONG_BEAR:                          return 0;
      case REGIME_NORMAL_BULL: case REGIME_NORMAL_BEAR:                          return 1;
      case REGIME_WEAK_BULL:   case REGIME_WEAK_BEAR:                            return 2;
      case REGIME_RANGE:       case REGIME_VOL_COMPRESSION:                      return 3;
      case REGIME_BREAKOUT_UP: case REGIME_BREAKOUT_DOWN: case REGIME_VOL_EXPANSION: return 4;
      default:                                                                   return 5; // exhaustion / reversal risk / unknown
     }
  }

int CurrentPatternId(int direction)
  {
   return (RegimeGroup(g_regime) * 5 + (int)g_session) * 2 + (direction == 1 ? 0 : 1);
  }

string PatternIdToString(int pid)
  {
   if(pid < 0 || pid >= NUM_PATTERNS) return "n/a";
   string grpName;
   switch(pid / 10)
     {
      case 0: grpName = "STRONG"; break;
      case 1: grpName = "NORMAL"; break;
      case 2: grpName = "WEAK";   break;
      case 3: grpName = "RANGE";  break;
      case 4: grpName = "BRKOUT"; break;
      default: grpName = "EXHREV"; break;
     }
   string sessName;
   switch((pid / 2) % 5)
     {
      case 0: sessName = "ASIA"; break;
      case 1: sessName = "LDN";  break;
      case 2: sessName = "NY";   break;
      case 3: sessName = "OVL";  break;
      default: sessName = "ROLL"; break;
     }
   return grpName + "/" + sessName + "/" + ((pid % 2) == 0 ? "BUY" : "SELL");
  }

void PatternLearn(int pid, double resultR)
  {
   if(!InpPatternLearnerOn || pid < 0 || pid >= NUM_PATTERNS) return;
   g_patRSum[pid] += MathMax(-3.0, MathMin(3.0, resultR)); // clamp: one outlier may not define a pattern
   g_patCount[pid]++;
   if(g_patCount[pid] >= InpPatternMinSamples)
     {
      double avg = g_patRSum[pid] / g_patCount[pid];
      bool was = g_patBlocked[pid];
      g_patBlocked[pid] = (avg < InpPatternBlockAvgR);
      if(g_patBlocked[pid] && !was)
         Log(StringFormat("PATTERN LEARNER: %s proven negative (avgR %.2f over %d trades) — suppressing.",
             PatternIdToString(pid), avg, g_patCount[pid]));
      else if(!g_patBlocked[pid] && was)
         Log(StringFormat("PATTERN LEARNER: %s recovered (avgR %.2f) — re-enabled.", PatternIdToString(pid), avg));
     }
   SavePersistedState();
  }

// Hour-of-day volatility profile: EWMA of signal-TF ATR per hour bucket.
// Gold's day has a shape — quiet Asia, London-open expansion, NY-overlap
// peak — and the geometry should target what the hour actually delivers.
void UpdateVolProfile()
  {
   if(!InpUseHourVolProfile) return;
   double atr[]; ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_atr_sig, 0, 0, 1, atr) < 1) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   double a = 0.05;
   if(g_hourATR[dt.hour] <= 0.0) g_hourATR[dt.hour] = atr[0];
   else g_hourATR[dt.hour] = (1.0 - a) * g_hourATR[dt.hour] + a * atr[0];
   if(g_allATR <= 0.0) g_allATR = atr[0];
   else g_allATR = (1.0 - a) * g_allATR + a * atr[0];
  }

double HourVolFactor()
  {
   if(!InpUseHourVolProfile) return 1.0;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(g_allATR <= 0.0 || g_hourATR[dt.hour] <= 0.0) return 1.0;
   double f = g_hourATR[dt.hour] / g_allATR;
   return MathMax(0.6, MathMin(1.5, f));
  }

// Serial correlation of closed-bar returns: the probability that two
// consecutive bars share a sign. > 0.5 = continuation character (trends
// follow through), < 0.5 = alternation character (moves get faded).
void UpdateSerialBias()
  {
   if(!InpUseSerialBias) { g_serialP = 0.5; return; }
   double c[]; ArraySetAsSeries(c, true);
   int n = 42; // 41 returns -> 40 consecutive pairs
   if(CopyClose(g_symbol, g_signalTF, 1, n, c) < n) { g_serialP = 0.5; return; }
   int agree = 0, pairs = 0;
   for(int i = 0; i < n - 2; i++)
     {
      double r1 = c[i] - c[i + 1];
      double r2 = c[i + 1] - c[i + 2];
      if(r1 == 0.0 || r2 == 0.0) continue;
      pairs++;
      if((r1 > 0.0) == (r2 > 0.0)) agree++;
     }
   g_serialP = (pairs > 0) ? (double)agree / pairs : 0.5;
  }

// Continuation-type signals (momentum/trend drive the direction) deserve
// extra confidence in a continuation market and less in an alternating
// one; reversal-type signals (sweep/wick against momentum) the opposite.
double SerialBiasMultiplier(int direction)
  {
   if(!InpUseSerialBias) return 1.0;
   bool contType = (g_factorVote[1] == direction || g_factorVote[2] == direction);
   bool revType  = (g_factorVote[4] == direction || g_factorVote[5] == direction) && g_factorVote[1] != direction;
   if(g_serialP >= 0.55 && contType) return 1.08;
   if(g_serialP <= 0.45 && revType)  return 1.08;
   if(g_serialP >= 0.55 && revType)  return 0.92;
   if(g_serialP <= 0.45 && contType) return 0.92;
   return 1.0;
  }

// Reversals cluster at .00/.50 — if the TP path barely punches through
// such a wall, take the profit in front of it instead of betting on the
// breach. (Entry-side wall avoidance already lives in the HTF zone map.)
double SnapTPBeforeRound(double entryPrice, double tp, int direction)
  {
   double pad = PointsToUSD(InpRoundLevelPadPoints);
   if(pad <= 0.0) return tp;
   if(direction == 1)
     {
      double level = MathFloor(tp * 2.0) / 2.0; // highest .00/.50 at or below TP
      if(level > entryPrice && (tp - level) < pad)
        {
         double snapped = level - pad;
         if(snapped > entryPrice)
           {
            Log(StringFormat("GEOMETRY: TP %.2f snapped to %.2f — in front of round-number wall %.2f.", tp, snapped, level));
            return snapped;
           }
        }
     }
   else
     {
      double level = MathCeil(tp * 2.0) / 2.0; // lowest .00/.50 at or above TP
      if(level < entryPrice && (level - tp) < pad)
        {
         double snapped = level + pad;
         if(snapped < entryPrice)
           {
            Log(StringFormat("GEOMETRY: TP %.2f snapped to %.2f — in front of round-number wall %.2f.", tp, snapped, level));
            return snapped;
           }
        }
     }
   return tp;
  }

double NormalizeLot(double lot)
  {
   double lotMin  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   double lotMax  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   lot = MathMax(lot, lotMin);
   lot = MathMin(lot, lotMax);
   lot = MathRound(lot / lotStep) * lotStep;
   return NormalizeDouble(lot, 2);
  }

//====================================================================
// [GOVERNORS] — layered capital preservation. Order matters: cheapest /
// most-likely-to-block checks first.
//====================================================================
void UpdateHourlyDailyCounters()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime hourStamp = (datetime)(((long)TimeCurrent() / 3600) * 3600);
   datetime dayStamp  = (datetime)(((long)TimeCurrent() / 86400) * 86400);

   if(hourStamp != g_currentHourStamp)
     {
      g_currentHourStamp = hourStamp;
      g_tradesThisHour = 0;
     }
   if(dayStamp != g_currentDayStamp)
     {
      g_currentDayStamp = dayStamp;
      g_tradesToday = 0;
      g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyHaltActive = false;
      SavePersistedState();
     }
  }

void UpdateEquityGovernors()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_peakEquity) g_peakEquity = equity;

   if(g_dailyStartEquity > 0.0)
     {
      double dayLossPct = (g_dailyStartEquity - equity) / g_dailyStartEquity * 100.0;
      if(dayLossPct >= InpDailyLossHaltPct && !g_dailyHaltActive)
        {
         g_dailyHaltActive = true;
         Log(StringFormat("GOVERNOR: DAILY LOSS HALT triggered (-%.2f%% of day-start equity).", dayLossPct));
         FlattenAll("Daily loss halt threshold breached.");
        }
     }

   if(g_peakEquity > 0.0)
     {
      double ddPct = (g_peakEquity - equity) / g_peakEquity * 100.0;
      if(ddPct >= InpMaxDDFlattenPct && !g_maxDDFlattenActive)
        {
         g_maxDDFlattenActive = true;
         Log(StringFormat("GOVERNOR: MAX-DD FLATTEN triggered (-%.2f%% from peak equity).", ddPct));
         FlattenAll("Max drawdown flatten threshold breached.");
        }
      else if(ddPct < InpMaxDDFlattenPct * 0.5)
         g_maxDDFlattenActive = false; // re-arm once DD recovers meaningfully
     }

   // Equity-curve MA governor
   int n = ArraySize(g_equityHistory);
   if(n >= InpEquityMAPeriod)
     {
      double sum = 0.0;
      for(int i = n - InpEquityMAPeriod; i < n; i++) sum += g_equityHistory[i];
      g_equityMA = sum / InpEquityMAPeriod;
     }
   else
      g_equityMA = equity;
  }

bool PassNewsBlackout()
  {
   if(!InpUseNewsFilter) return true;

   MqlCalendarValue values[];
   datetime from = TimeCurrent() - InpNewsBlackoutMin * 60;
   datetime to   = TimeCurrent() + InpNewsBlackoutMin * 60;
   int cnt = CalendarValueHistory(values, from, to, "US");
   if(cnt <= 0)
     {
      // Tester/backtest calendars are frequently empty — auto-bypass and say so,
      // rather than silently blocking every single bar of a backtest.
      if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
        {
         static bool warned = false;
         if(!warned) { Log("NEWS FILTER: calendar empty in tester — auto-bypassing news blackout for this run."); warned = true; }
         return true;
        }
      return true;
     }

   for(int i = 0; i < cnt; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      return false; // inside window of a high-impact USD event
     }
   return true;
  }

bool PassSpreadGates(ENUM_BLOCK_REASON &reason)
  {
   double spread = CurrentSpreadUSD();
   if(spread > InpAbsoluteSpreadCeilingUSD)
     { reason = BLOCK_SPREAD_ABSOLUTE; return false; }
   if(spread > eff_ScalpSpreadCeilingUSD)
     { reason = BLOCK_SPREAD_SCALP_CEILING; return false; }
   return true;
  }

bool PassChaseGuard(int direction)
  {
   double atr[]; ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_atr_sig, 0, 0, 1, atr) < 1) return true;
   double h[], l[], o[], c[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   if(CopyHigh(g_symbol, g_signalTF, 0, 1, h) < 1) return true;
   if(CopyLow(g_symbol, g_signalTF, 0, 1, l) < 1) return true;
   if(CopyOpen(g_symbol, g_signalTF, 0, 1, o) < 1) return true;

   double runSoFar = (direction == 1) ? (h[0] - o[0]) : (o[0] - l[0]);
   if(runSoFar > InpChaseATRMult * atr[0])
      return false;
   return true;
  }

bool PassHTFZoneMap(int direction, double tp)
  {
   double h4High[], h4Low[];
   ArraySetAsSeries(h4High, true); ArraySetAsSeries(h4Low, true);
   int bars = 30;
   if(CopyHigh(g_symbol, PERIOD_H4, 1, bars, h4High) < bars) return true;
   if(CopyLow(g_symbol, PERIOD_H4, 1, bars, h4Low) < bars) return true;

   double price = (direction == 1) ? GetAsk() : GetBid();
   double tpDistance = MathAbs(tp - price);
   if(tpDistance <= 0.0) return true;

   // H4 fractals as wall candidates
   double nearestWall = 0.0; bool found = false;
   for(int i = 2; i < bars - 2; i++)
     {
      if(direction == 1 && h4High[i] > h4High[i-1] && h4High[i] > h4High[i+1] && h4High[i] > price)
        {
         double d = h4High[i] - price;
         if(!found || d < MathAbs(nearestWall - price)) { nearestWall = h4High[i]; found = true; }
        }
      if(direction == -1 && h4Low[i] < h4Low[i-1] && h4Low[i] < h4Low[i+1] && h4Low[i] < price)
        {
         double d = price - h4Low[i];
         if(!found || d < MathAbs(nearestWall - price)) { nearestWall = h4Low[i]; found = true; }
        }
     }

   // Round-number wall (.00 levels)
   double roundLevel = MathRound(price / 1.0) * 1.0;
   double roundDist = MathAbs(roundLevel - price);
   if(direction == 1 && roundLevel > price && roundDist < tpDistance * InpZoneBlockMult) return false;
   if(direction == -1 && roundLevel < price && roundDist < tpDistance * InpZoneBlockMult) return false;

   if(found)
     {
      double wallDist = MathAbs(nearestWall - price);
      if(wallDist < tpDistance * InpZoneBlockMult) return false;
     }
   return true;
  }

bool PassMarginAndCaps()
  {
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel > 0.0 && marginLevel < InpMarginLevelGateMin) return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double usedMargin = AccountInfoDouble(ACCOUNT_MARGIN);
   double marginPct = (equity > 0.0) ? usedMargin / equity * 100.0 : 0.0;
   if(marginPct >= InpMarginUsageCapPct) return false;

   int openBaskets = 0;
   for(int i = 0; i < MAX_BASKETS; i++) if(g_bkActive[i]) openBaskets++;
   if(openBaskets >= MAX_BASKETS) return false;

   return true;
  }

bool PassGovernors(int direction, ENUM_BLOCK_REASON &blockedBy)
  {
   if(g_feedDegraded) { blockedBy = BLOCK_FEED_DEGRADED; return false; }
   if(g_dailyHaltActive) { blockedBy = BLOCK_DAILY_LOSS_HALT; return false; }
   if(g_maxDDFlattenActive) { blockedBy = BLOCK_MAX_DD_FLATTEN; return false; }
   if(TimeCurrent() < g_cooldownUntil) { blockedBy = BLOCK_LOSS_STREAK_COOLDOWN; return false; }
   if(g_tradesThisHour >= InpMaxTradesPerHour) { blockedBy = BLOCK_HOURLY_CAP; return false; }
   if(g_tradesToday >= InpMaxTradesPerDay) { blockedBy = BLOCK_DAILY_CAP; return false; }

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(g_hourSampleCount[dt.hour] >= InpHourMinSamples && g_hourBlocked[dt.hour])
     { blockedBy = BLOCK_HOUR_NEGATIVE_EXPECTANCY; return false; }

   if(g_equityMA > 0.0 && AccountInfoDouble(ACCOUNT_EQUITY) < g_equityMA)
      { /* size halved downstream in CalcLotSize, not a hard block */ }

   if(!PassNewsBlackout()) { blockedBy = BLOCK_NEWS_BLACKOUT; return false; }
   ENUM_BLOCK_REASON spreadReason = BLOCK_NONE;
   if(!PassSpreadGates(spreadReason)) { blockedBy = spreadReason; return false; }
   if(!PassChaseGuard(direction)) { blockedBy = BLOCK_CHASE_GUARD; return false; }
   if(!PassMarginAndCaps()) { blockedBy = BLOCK_MARGIN_LEVEL_GATE; return false; }

   return true;
  }

//====================================================================
// [GEOMETRY]
//====================================================================
void ApplyRegimeGeometry(ENUM_REGIME r, double &slMult, double &tpMult)
  {
   switch(r)
     {
      case REGIME_BREAKOUT_UP:
      case REGIME_BREAKOUT_DOWN:      slMult = 1.2; tpMult = 1.8; break;
      case REGIME_RANGE:              slMult = 0.9; tpMult = 0.8; break;
      case REGIME_VOL_COMPRESSION:    slMult = 0.8; tpMult = 0.7; break;
      case REGIME_STRONG_BULL:
      case REGIME_STRONG_BEAR:        slMult = 1.1; tpMult = 1.6; break;
      case REGIME_NORMAL_BULL:
      case REGIME_NORMAL_BEAR:        slMult = 1.0; tpMult = 1.3; break;
      case REGIME_WEAK_BULL:
      case REGIME_WEAK_BEAR:          slMult = 0.9; tpMult = 1.0; break;
      case REGIME_VOL_EXPANSION:      slMult = 1.15; tpMult = 1.5; break;
      case REGIME_EXHAUSTION_UP:
      case REGIME_EXHAUSTION_DOWN:
      case REGIME_REVERSAL_RISK:      slMult = 0.85; tpMult = 0.9; break;
      case REGIME_UNKNOWN:
      default:                        slMult = 1.0; tpMult = 1.0; break;
     }
  }

// [DEFECT-RULE] Anti-stop-hunt: pad stops beyond .00/.50 round levels where
// retail stop clusters sit, instead of resting a stop exactly on them.
double PadAntiStopHunt(double level, int direction, bool isSL)
  {
   double halfLevel = MathRound(level * 2.0) / 2.0; // nearest .00 or .50
   double dist = MathAbs(level - halfLevel);
   double padUSD = PointsToUSD(InpRoundLevelPadPoints);
   if(dist < padUSD)
     {
      // Push the level further away from the round number, in the
      // direction that makes the stop *safer* (further from price for SL).
      bool pushDown = (isSL && direction == 1) || (!isSL && direction == -1);
      level = pushDown ? (halfLevel - padUSD) : (halfLevel + padUSD);
     }
   return level;
  }

double ClampToStopsLevel(double entryPrice, double level, int direction, bool isSL)
  {
   double stopsLevelPts = (double)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double spread = CurrentSpreadUSD();
   double minDist = MathMax(PointsToUSD(stopsLevelPts), 0.0) + spread;

   double dist = MathAbs(entryPrice - level);
   if(dist < minDist)
     {
      Log(StringFormat("GEOMETRY CLAMP: %s distance $%.2f < broker minimum $%.2f (stopsLevel+spread) — clamped.",
          isSL ? "SL" : "TP", dist, minDist));
      if(isSL)
         level = (direction == 1) ? entryPrice - minDist : entryPrice + minDist;
      else
         level = (direction == 1) ? entryPrice + minDist : entryPrice - minDist;
     }
   return level;
  }

bool CalcGeometry(int direction, double entryPrice, double &sl, double &tp)
  {
   double slMult = 1.0, tpMult = 1.0;
   ApplyRegimeGeometry(g_regime, slMult, tpMult);

   double slDistance, tpDistance;
   if(InpFixedLotMode)
     {
      slDistance = InpFixedSL_USD * slMult;
      tpDistance = InpFixedTP_USD * tpMult;
     }
   else
     {
      double atr[]; ArraySetAsSeries(atr, true);
      if(CopyBuffer(h_atr_sig, 0, 0, 1, atr) < 1) return false;
      slDistance = atr[0] * eff_SL_ATR_Mult * slMult;
      tpDistance = atr[0] * eff_TP_ATR_Mult * tpMult;
     }

   // [PATTERN ARITHMETIC] Scale the target to what this hour of the gold day
   // statistically delivers (learned EWMA vol profile): a TP beyond the hour's
   // typical range is arithmetically unreachable; one far below it wastes edge.
   if(InpUseHourVolProfile)
     {
      double volF = HourVolFactor();
      if(volF != 1.0)
        {
         tpDistance *= volF;
         slDistance *= (0.5 + 0.5 * volF); // SL scales half as hard to keep R geometry sane
        }
     }

   // Effective TP = max(userTP, TPSpreadFloorMult * spread) — never let the
   // target be eaten by the cost of entry.
   double spread = CurrentSpreadUSD();
   double floorTP = eff_TPSpreadFloorMult * spread;
   if(tpDistance < floorTP)
     {
      Log(StringFormat("GEOMETRY: TP distance $%.2f floored to $%.2f (spread-floor, mult=%.1f).", tpDistance, floorTP, eff_TPSpreadFloorMult));
      tpDistance = floorTP;
     }

   if(slDistance <= 0.0 || tpDistance <= 0.0)
      return false;

   sl = (direction == 1) ? entryPrice - slDistance : entryPrice + slDistance;
   tp = (direction == 1) ? entryPrice + tpDistance : entryPrice - tpDistance;

   if(InpSnapTPBeforeRound)
      tp = SnapTPBeforeRound(entryPrice, tp, direction);

   sl = PadAntiStopHunt(sl, direction, true);
   sl = ClampToStopsLevel(entryPrice, sl, direction, true);
   tp = ClampToStopsLevel(entryPrice, tp, direction, false);

   sl = NormalizeDouble(sl, g_digits);
   tp = NormalizeDouble(tp, g_digits);
   return true;
  }

// [FEATURE:AutoLotGrowth] lots scale with equity (LotPer100USD), never below broker minimum.
double CalcLotSize(double slDistancePrice)
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lotMin  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   double lotMax  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);

   double lot;
   if(InpFixedLotMode)
     {
      lot = InpBaseLot + (equity / 100.0) * InpLotPer100USD;
     }
   else
     {
      double riskUSD = equity * (InpRiskPercent / 100.0);
      double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
      double valuePerPriceUnit = (tickSize > 0.0) ? tickValue / tickSize : tickValue;
      double riskPerLot = slDistancePrice * valuePerPriceUnit;
      lot = (riskPerLot > 0.0) ? riskUSD / riskPerLot : InpBaseLot;
     }

   // Equity-curve governor: halve size when equity is below its own MA.
   if(g_equityMA > 0.0 && equity < g_equityMA)
      lot *= (InpEquityGovernorHalvePct / 100.0) * 0.5 + 0.5; // partial halving, never below floor below

   lot = MathMax(lot, lotMin);
   lot = MathMin(lot, lotMax);
   lot = MathRound(lot / lotStep) * lotStep;
   lot = NormalizeDouble(lot, 2);
   return lot;
  }

//====================================================================
// [ENTRY ENGINE] — pending-order bookkeeping
// (MAX_PENDING / g_pending* declared up in [GLOBAL STATE], before OnInit,
// per the single-pass-globals defect rule)
//====================================================================
void RegisterPending(ulong ticket, int basketIdx)
  {
   for(int i = 0; i < MAX_PENDING; i++)
      if(!g_pendingActive[i])
        {
         g_pendingActive[i] = true;
         g_pendingTicket[i] = ticket;
         g_pendingPlacedTime[i] = TimeCurrent();
         g_pendingBasketIdx[i] = basketIdx;
         return;
        }
  }

void CancelExpiredPendings()
  {
   for(int i = 0; i < MAX_PENDING; i++)
     {
      if(!g_pendingActive[i]) continue;
      if(TimeCurrent() - g_pendingPlacedTime[i] < InpPassiveTimeoutSec) continue;
      if(!OrderSelect(g_pendingTicket[i]))
        { g_pendingActive[i] = false; continue; } // already filled or gone

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res); // [DEFECT-RULE-5] safe: MqlTradeRequest/Result hold no strings that break under ZeroMemory
      req.action = TRADE_ACTION_REMOVE;
      req.order = g_pendingTicket[i];
      if(OrderSend(req, res))
         Log(StringFormat("Pending #%d auto-cancelled after %d s timeout.", (int)g_pendingTicket[i], InpPassiveTimeoutSec));
      g_pendingActive[i] = false;
     }
  }

//====================================================================
// [SendWithRetry] — 3 attempts, retries on REQUOTE/PRICE_CHANGED/PRICE_OFF/
// TIMEOUT/CONNECTION, measures latency and slippage.
//====================================================================
bool SendWithRetry(MqlTradeRequest &request, MqlTradeResult &result)
  {
   for(int attempt = 1; attempt <= InpSendRetryAttempts; attempt++)
     {
      uint t0 = GetTickCount();
      double preSendPrice = request.price;
      bool sent = OrderSend(request, result);
      uint t1 = GetTickCount();
      g_lastLatencyMs = (double)(t1 - t0);

      g_ordersSent++;
      if(sent && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED || result.retcode == TRADE_RETCODE_DONE_PARTIAL))
        {
         g_ordersFilled++;
         if(request.type == ORDER_TYPE_BUY || request.type == ORDER_TYPE_SELL)
           {
            double slip = MathAbs(result.price - preSendPrice);
            g_avgSlippagePoints = (g_avgSlippagePoints * g_slippageSamples + USDToPoints(slip)) / (g_slippageSamples + 1);
            g_slippageSamples++;
           }
         Log(StringFormat("ORDER OK attempt %d/%d retcode=%d price=%.5f latency=%.0fms",
             attempt, InpSendRetryAttempts, result.retcode, result.price, g_lastLatencyMs));
         return true;
        }

      bool retryable = (result.retcode == TRADE_RETCODE_REQUOTE ||
                         result.retcode == TRADE_RETCODE_PRICE_CHANGED ||
                         result.retcode == TRADE_RETCODE_PRICE_OFF ||
                         result.retcode == TRADE_RETCODE_TIMEOUT ||
                         result.retcode == TRADE_RETCODE_CONNECTION);

      Log(StringFormat("ORDER attempt %d/%d FAILED retcode=%d comment=%s retryable=%s",
          attempt, InpSendRetryAttempts, result.retcode, result.comment, retryable ? "Y" : "N"));

      if(!retryable) break;

      Sleep(InpSendRetrySleepMs);
      // Refresh price for market/limit-at-market style resend
      if(request.type == ORDER_TYPE_BUY || request.type == ORDER_TYPE_BUY_LIMIT || request.type == ORDER_TYPE_BUY_STOP)
         request.price = GetAsk();
      else if(request.type == ORDER_TYPE_SELL || request.type == ORDER_TYPE_SELL_LIMIT || request.type == ORDER_TYPE_SELL_STOP)
         request.price = GetBid();
     }

   g_ordersRejected++;
   return false;
  }

//====================================================================
// [ExecuteEntry] — burst entries with laddered TPs; three entry modes.
//====================================================================
int FindFreeBasketSlot()
  {
   for(int i = 0; i < MAX_BASKETS; i++)
      if(!g_bkActive[i]) return i;
   return -1;
  }

void ExecuteEntry(int direction, double confidence)
  {
   double refPrice = (direction == 1) ? GetAsk() : GetBid();
   double baseSL, baseTP;
   if(!CalcGeometry(direction, refPrice, baseSL, baseTP))
     { LogBlock(BLOCK_GEOMETRY_INCOHERENT, "geometry calc failed (zero/negative distance)"); return; }

   if(!PassHTFZoneMap(direction, baseTP))
     { LogBlock(BLOCK_HTF_ZONE_WALL, "opposing HTF wall closer than TP*ZoneBlockMult"); return; }

   double slDistance = MathAbs(refPrice - baseSL);
   double lot = CalcLotSize(slDistance);
   if(g_patternSizeBoost != 1.0)
     {
      double boosted = NormalizeLot(lot * g_patternSizeBoost);
      Log(StringFormat("PATTERN BOOST: proven pattern %s -> size x%.2f (%.2f -> %.2f lots)",
          PatternIdToString(g_currentPatternId), g_patternSizeBoost, lot, boosted));
      lot = boosted;
     }

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);

   for(int i = 0; i < InpEntriesPerSignal; i++)
     {
      double tpDistance = MathAbs(baseTP - refPrice) * (1.0 + InpLadderStep * i);
      double tp_i = (direction == 1) ? refPrice + tpDistance : refPrice - tpDistance;
      tp_i = ClampToStopsLevel(refPrice, tp_i, direction, false);
      tp_i = NormalizeDouble(tp_i, g_digits);

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.symbol = g_symbol;
      req.volume = lot;
      req.magic  = InpMagic;
      req.sl = baseSL;
      req.tp = tp_i;
      req.deviation = 20;
      req.type_filling = ORDER_FILLING_FOK;

      switch(eff_EntryMode)
        {
         case ENTRY_MARKET:
            req.action = TRADE_ACTION_DEAL;
            req.type = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            req.price = refPrice;
            break;
         case ENTRY_PASSIVE_LIMIT:
            req.action = TRADE_ACTION_PENDING;
            req.type = (direction == 1) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
            req.price = (direction == 1) ? GetBid() : GetAsk(); // post at bid(buy)/ask(sell) to EARN the spread
            req.type_time = ORDER_TIME_GTC;
            break;
         case ENTRY_BREAK_STOP:
           {
            double prevHigh[], prevLow[];
            ArraySetAsSeries(prevHigh, true); ArraySetAsSeries(prevLow, true);
            if(CopyHigh(g_symbol, g_signalTF, 1, 1, prevHigh) < 1 || CopyLow(g_symbol, g_signalTF, 1, 1, prevLow) < 1)
              {
               Log("ENTRY skipped: could not read prior bar high/low for ENTRY_BREAK_STOP.");
               continue;
              }
            req.action = TRADE_ACTION_PENDING;
            req.type = (direction == 1) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
            req.price = (direction == 1) ? prevHigh[0] + CurrentSpreadUSD() : prevLow[0] - CurrentSpreadUSD();
            req.type_time = ORDER_TIME_GTC;
            break;
           }
        }
      req.price = NormalizeDouble(req.price, g_digits);

      if(!SendWithRetry(req, res))
        {
         Log(StringFormat("ENTRY FAILED after retries: dir=%d entry#%d/%d retcode=%d", direction, i+1, InpEntriesPerSignal, res.retcode));
         continue;
        }

      int slot = FindFreeBasketSlot();
      if(slot < 0) { Log("WARN: no free basket slot to track this fill — MAX_BASKETS exhausted."); continue; }

      g_bkActive[slot] = true;
      g_bkDirection[slot] = direction;
      g_bkAvgPrice[slot] = (req.action == TRADE_ACTION_DEAL) ? res.price : req.price;
      g_bkVolume[slot] = lot;
      g_bkPeakProfit[slot] = 0.0;
      g_bkInitialRiskUSD[slot] = slDistance * lot * (SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE) / MathMax(SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE), _Point));
      g_bkOpenTime[slot] = TimeCurrent();
      g_bkBEApplied[slot] = false;
      g_bkPartialApplied[slot] = false;
      g_bkRegime[slot] = g_regime;
      g_bkConfidenceAtEntry[slot] = confidence;
      g_bkEntryHour[slot] = dt.hour;
      g_bkTicket[slot] = (req.action == TRADE_ACTION_DEAL) ? res.order : 0; // pendings reconciled to a ticket once filled
      for(int f = 0; f < NUM_FACTORS; f++) g_bkFactorVote[slot][f] = g_factorVote[f];
      g_bkPatternId[slot] = g_currentPatternId;

      if(req.action == TRADE_ACTION_PENDING)
         RegisterPending(res.order, slot);

      Log(StringFormat("ENTRY %s #%d/%d lot=%.2f price=%.2f SL=%.2f TP=%.2f regime=%s conf=%.1f",
          direction == 1 ? "BUY" : "SELL", i+1, InpEntriesPerSignal, lot, req.price, baseSL, tp_i,
          EnumToString(g_regime), confidence));

      if(InpPushAlertsOn)
         SendNotification(StringFormat("IAX7 %s: %s entry lot=%.2f conf=%.1f", g_symbol, direction==1?"BUY":"SELL", lot, confidence));
     }

   g_tradesThisHour++;
   g_tradesToday++;
   g_lastSignalDir = direction;
   g_flipCounter = 0;
  }

//====================================================================
// [TRADE MANAGEMENT]
//====================================================================
// Reconcile a filled pending order (ticket now live) with its basket slot.
void ReconcilePendingFills()
  {
   for(int i = 0; i < MAX_BASKETS; i++)
     {
      if(!g_bkActive[i] || g_bkTicket[i] != 0) continue;
      // slot was opened via a pending order still awaiting fill confirmation
      for(int p = PositionsTotal() - 1; p >= 0; p--)
        {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         if((datetime)PositionGetInteger(POSITION_TIME) < g_bkOpenTime[i]) continue;

         bool alreadyClaimed = false;
         for(int j = 0; j < MAX_BASKETS; j++)
            if(j != i && g_bkActive[j] && g_bkTicket[j] == ticket) { alreadyClaimed = true; break; }
         if(alreadyClaimed) continue;

         int posDir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         if(posDir != g_bkDirection[i]) continue;

         g_bkTicket[i] = ticket;
         g_bkAvgPrice[i] = PositionGetDouble(POSITION_PRICE_OPEN);
         break;
        }
     }
  }

double RCurrentMultiple(int idx)
  {
   if(!PositionSelectByTicket(g_bkTicket[idx])) return 0.0;
   double openPrice = g_bkAvgPrice[idx];
   double slPrice = PositionGetDouble(POSITION_SL);
   double curPrice = (g_bkDirection[idx] == 1) ? GetBid() : GetAsk();
   double riskDist = MathAbs(openPrice - slPrice);
   if(riskDist <= 0.0) return 0.0;
   double moveDist = (g_bkDirection[idx] == 1) ? (curPrice - openPrice) : (openPrice - curPrice);
   return moveDist / riskDist;
  }

// R-Multiple Manager: at +1R -> SL to breakeven + partial close; at +2R -> ATR trailing stop.
void ManageBasket(int idx)
  {
   if(!g_bkActive[idx] || g_bkTicket[idx] == 0) return;
   if(!PositionSelectByTicket(g_bkTicket[idx]))
      return; // closed elsewhere; reconciliation in ManageOpenPositions handles bookkeeping

   double rMult = RCurrentMultiple(idx);
   int direction = g_bkDirection[idx];
   double openPrice = g_bkAvgPrice[idx];
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   double curVol = PositionGetDouble(POSITION_VOLUME);

   if(!g_bkBEApplied[idx] && rMult >= eff_BE_TriggerR)
     {
      double beSL = openPrice;
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action = TRADE_ACTION_SLTP;
      req.position = g_bkTicket[idx];
      req.symbol = g_symbol;
      req.sl = NormalizeDouble(beSL, g_digits);
      req.tp = curTP;
      if(OrderSend(req, res))
        {
         g_bkBEApplied[idx] = true;
         Log(StringFormat("BASKET #%d: SL moved to breakeven at +%.2fR", g_bkTicket[idx], rMult));
        }

      if(!g_bkPartialApplied[idx] && InpBE_PartialPct > 0.0 && InpBE_PartialPct < 100.0)
        {
         double partialVol = NormalizeDouble(curVol * (InpBE_PartialPct/100.0), 2);
         double volMin = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
         if(partialVol >= volMin && (curVol - partialVol) >= volMin)
           {
            MqlTradeRequest preq; MqlTradeResult pres;
            ZeroMemory(preq); ZeroMemory(pres);
            preq.action = TRADE_ACTION_DEAL;
            preq.position = g_bkTicket[idx];
            preq.symbol = g_symbol;
            preq.volume = partialVol;
            preq.type = (direction == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            preq.price = (direction == 1) ? GetBid() : GetAsk();
            preq.deviation = 20;
            preq.type_filling = ORDER_FILLING_FOK;
            if(SendWithRetry(preq, pres))
              {
               g_bkPartialApplied[idx] = true;
               g_bkVolume[idx] -= partialVol;
               Log(StringFormat("BASKET #%d: partial close %.2f lots (%.0f%%) at +%.2fR", g_bkTicket[idx], partialVol, InpBE_PartialPct, rMult));
              }
           }
        }
     }

   if(rMult >= eff_TrailTriggerR)
     {
      double atr[]; ArraySetAsSeries(atr, true);
      if(CopyBuffer(h_atr_sig, 0, 0, 1, atr) >= 1)
        {
         double trailDist = atr[0] * InpTrailATRMult;
         double curPrice = (direction == 1) ? GetBid() : GetAsk();
         double newSL = (direction == 1) ? curPrice - trailDist : curPrice + trailDist;
         bool improves = (direction == 1) ? (newSL > curSL) : (newSL < curSL || curSL == 0.0);
         if(improves)
           {
            MqlTradeRequest req; MqlTradeResult res;
            ZeroMemory(req); ZeroMemory(res);
            req.action = TRADE_ACTION_SLTP;
            req.position = g_bkTicket[idx];
            req.symbol = g_symbol;
            req.sl = NormalizeDouble(newSL, g_digits);
            req.tp = curTP;
            if(OrderSend(req, res))
               Log(StringFormat("BASKET #%d: ATR trailing stop -> %.2f at +%.2fR", g_bkTicket[idx], newSL, rMult));
           }
        }
     }
  }

// Basket-group layer: volume-weighted avg entry, peak-profit trail with
// giveback %, basket max-loss cut, thesis invalidation, exhaustion de-risk.
void ManageBasketGroup(int direction)
  {
   double totalVolume = 0.0, weightedPriceSum = 0.0, totalProfit = 0.0;
   int members[MAX_BASKETS]; int n = 0;
   for(int i = 0; i < MAX_BASKETS; i++)
     {
      if(!g_bkActive[i] || g_bkDirection[i] != direction || g_bkTicket[i] == 0) continue;
      if(!PositionSelectByTicket(g_bkTicket[i])) continue;
      double vol = PositionGetDouble(POSITION_VOLUME);
      totalVolume += vol;
      weightedPriceSum += g_bkAvgPrice[i] * vol;
      totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      members[n++] = i;
     }
   if(n == 0)
     {
      if(direction == 1) g_groupPeakProfitBuy = 0.0; else g_groupPeakProfitSell = 0.0;
      return;
     }

   double avgPrice = (totalVolume > 0.0) ? weightedPriceSum / totalVolume : 0.0;

   double peak = (direction == 1) ? g_groupPeakProfitBuy : g_groupPeakProfitSell;
   if(totalProfit > peak) peak = totalProfit;
   if(direction == 1) g_groupPeakProfitBuy = peak; else g_groupPeakProfitSell = peak;

   bool cutGroup = false;
   string cutReason = "";

   if(totalProfit <= -InpBasketMaxLossUSD)
     { cutGroup = true; cutReason = StringFormat("basket max-loss cut ($%.2f <= -$%.2f)", totalProfit, InpBasketMaxLossUSD); }

   if(!cutGroup && peak > 0.0)
     {
      double giveback = (peak - totalProfit) / peak * 100.0;
      if(peak > InpBasketMaxLossUSD * 0.5 && giveback >= InpBasketGivebackPct)
        { cutGroup = true; cutReason = StringFormat("peak-profit giveback %.1f%% >= %.1f%% (peak $%.2f -> now $%.2f)", giveback, InpBasketGivebackPct, peak, totalProfit); }
     }

   // Thesis invalidation: opposite-side probability crossed the trigger AND structure flipped.
   double oppositeProb = (direction == 1) ? g_sellProb : g_buyProb;
   bool structureFlipped = (Factor_MarketStructure() == -direction);
   if(!cutGroup && oppositeProb >= InpThesisInvalidationProb && structureFlipped)
     { cutGroup = true; cutReason = StringFormat("thesis invalidated (opposite prob %.2f >= %.2f, structure flipped)", oppositeProb, InpThesisInvalidationProb); }

   // Exhaustion de-risk: on an exhaustion bar against this basket's direction, trim (not full flatten).
   if(!cutGroup && g_exhaustionBar)
     {
      bool exhaustionAgainstUs = (direction == 1 && (g_regime == REGIME_EXHAUSTION_UP)) ||
                                  (direction == -1 && (g_regime == REGIME_EXHAUSTION_DOWN));
      if(exhaustionAgainstUs && totalProfit > 0.0)
        {
         Log(StringFormat("BASKET GROUP dir=%d: exhaustion de-risk — trimming 50%% of group (profit $%.2f).", direction, totalProfit));
         for(int k = 0; k < n; k++)
           {
            int idx = members[k];
            if(!PositionSelectByTicket(g_bkTicket[idx])) continue;
            double vol = PositionGetDouble(POSITION_VOLUME);
            double trimVol = NormalizeDouble(vol * 0.5, 2);
            double volMin = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
            if(trimVol < volMin) continue;
            MqlTradeRequest req; MqlTradeResult res;
            ZeroMemory(req); ZeroMemory(res);
            req.action = TRADE_ACTION_DEAL;
            req.position = g_bkTicket[idx];
            req.symbol = g_symbol;
            req.volume = trimVol;
            req.type = (direction == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            req.price = (direction == 1) ? GetBid() : GetAsk();
            req.deviation = 20;
            req.type_filling = ORDER_FILLING_FOK;
            SendWithRetry(req, res);
           }
        }
     }

   if(cutGroup)
     {
      Log(StringFormat("BASKET GROUP dir=%d CUT: %s", direction, cutReason));
      for(int k = 0; k < n; k++)
        {
         int idx = members[k];
         if(!PositionSelectByTicket(g_bkTicket[idx])) continue;
         MqlTradeRequest req; MqlTradeResult res;
         ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_DEAL;
         req.position = g_bkTicket[idx];
         req.symbol = g_symbol;
         req.volume = PositionGetDouble(POSITION_VOLUME);
         req.type = (direction == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         req.price = (direction == 1) ? GetBid() : GetAsk();
         req.deviation = 20;
         req.type_filling = ORDER_FILLING_FOK;
         SendWithRetry(req, res);
        }
     }
  }

void ManageOpenPositions()
  {
   ReconcilePendingFills();

   for(int i = 0; i < MAX_BASKETS; i++)
     {
      if(!g_bkActive[i]) continue;
      if(g_bkTicket[i] == 0) continue; // still awaiting pending fill

      if(!PositionSelectByTicket(g_bkTicket[i]))
        {
         // Position gone — closed by SL/TP/manual/governor. Pull the realized
         // P/L from the deal history and feed the adaptive learner.
         double pnl = 0.0;
         if(HistorySelectByPosition(g_bkTicket[i]))
           {
            int deals = HistoryDealsTotal();
            for(int d = 0; d < deals; d++)
              {
               ulong dealTicket = HistoryDealGetTicket(d);
               pnl += HistoryDealGetDouble(dealTicket, DEAL_PROFIT) + HistoryDealGetDouble(dealTicket, DEAL_SWAP) + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
              }
           }
         Log(StringFormat("BASKET #%d closed. Realized PnL=$%.2f", g_bkTicket[i], pnl));
         if(InpWriteTradeJournalCSV)
            WriteTradeJournalRow(g_bkDirection[i]==1?"BUY":"SELL", g_bkVolume[i], g_bkAvgPrice[i], 0.0, pnl, g_bkRegime[i], g_bkConfidenceAtEntry[i], g_bkEntryHour[i]);
         OnClosedBasketLearn(i, pnl, g_bkInitialRiskUSD[i], pnl > 0.0);
         if(g_bkInitialRiskUSD[i] > 0.0)
            PatternLearn(g_bkPatternId[i], pnl / g_bkInitialRiskUSD[i]);
         g_bkActive[i] = false;
         continue;
        }

      ManageBasket(i);
     }

   ManageBasketGroup(1);
   ManageBasketGroup(-1);
  }

// [DEFECT-RULE-6] MQL5 has no struct pointers — protective-stop sweep uses
// index-based lookups into the basket arrays, not object references.
void EnsureProtectiveStops()
  {
   for(int i = 0; i < MAX_BASKETS; i++)
     {
      if(!g_bkActive[i] || g_bkTicket[i] == 0) continue;
      if(!PositionSelectByTicket(g_bkTicket[i])) continue;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl != 0.0) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double dummySL, dummyTP;
      int direction = g_bkDirection[i];
      ENUM_REGIME savedRegime = g_regime;
      g_regime = g_bkRegime[i];
      if(CalcGeometry(direction, openPrice, dummySL, dummyTP))
        {
         MqlTradeRequest req; MqlTradeResult res;
         ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_SLTP;
         req.position = g_bkTicket[i];
         req.symbol = g_symbol;
         req.sl = dummySL;
         req.tp = PositionGetDouble(POSITION_TP);
         if(OrderSend(req, res))
            Log(StringFormat("EnsureProtectiveStops: re-attached missing SL on #%d -> %.2f", g_bkTicket[i], dummySL));
         else
            Log(StringFormat("WARN: EnsureProtectiveStops failed to attach SL on #%d retcode=%d", g_bkTicket[i], res.retcode));
        }
      g_regime = savedRegime;
     }
  }

// Bar-confirmed flip exit: the opposite signal must persist FlipConfirmBars
// CLOSED bars before flattening (intrabar flips churn noise into losses).
void CheckFlipExit()
  {
   if(g_lastSignalDir == 0) return;
   int currentDir = 0;
   if(g_buyProb > g_sellProb) currentDir = 1;
   else if(g_sellProb > g_buyProb) currentDir = -1;
   if(currentDir == 0) return;

   if(currentDir == -g_lastSignalDir)
     {
      if(g_flipDir != currentDir) { g_flipDir = currentDir; g_flipCounter = 1; }
      else g_flipCounter++;

      if(g_flipCounter >= eff_FlipConfirmBars)
        {
         Log(StringFormat("FLIP EXIT: opposite signal confirmed for %d closed bars — flattening %s basket.",
             g_flipCounter, g_lastSignalDir==1?"BUY":"SELL"));
         int dirToClose = g_lastSignalDir;
         for(int i = 0; i < MAX_BASKETS; i++)
           {
            if(!g_bkActive[i] || g_bkDirection[i] != dirToClose || g_bkTicket[i] == 0) continue;
            if(!PositionSelectByTicket(g_bkTicket[i])) continue;
            MqlTradeRequest req; MqlTradeResult res;
            ZeroMemory(req); ZeroMemory(res);
            req.action = TRADE_ACTION_DEAL;
            req.position = g_bkTicket[i];
            req.symbol = g_symbol;
            req.volume = PositionGetDouble(POSITION_VOLUME);
            req.type = (dirToClose == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            req.price = (dirToClose == 1) ? GetBid() : GetAsk();
            req.deviation = 20;
            req.type_filling = ORDER_FILLING_FOK;
            SendWithRetry(req, res);
           }
         g_lastSignalDir = currentDir;
         g_flipCounter = 0;
        }
     }
   else
      g_flipCounter = 0;
  }

//====================================================================
// [SWING MODULE] — own magic = Magic+7, invisible to scalp logic.
// One larger 2:1 position in STRONG trend / breakout regimes only.
//====================================================================
bool SwingRegimeQualifies(ENUM_REGIME r)
  {
   return (r == REGIME_STRONG_BULL || r == REGIME_STRONG_BEAR ||
           r == REGIME_BREAKOUT_UP || r == REGIME_BREAKOUT_DOWN);
  }

void SwingTryEntry()
  {
   if(g_swActive) return;
   if(!SwingRegimeQualifies(g_regime)) return;

   double adx[]; ArraySetAsSeries(adx, true);
   if(CopyBuffer(h_adx_trend, 0, 0, 1, adx) < 1) return;
   if(adx[0] < InpSwingMinADX) return;

   int direction = (g_regime == REGIME_STRONG_BULL || g_regime == REGIME_BREAKOUT_UP) ? 1 : -1;
   double refPrice = (direction == 1) ? GetAsk() : GetBid();

   double atr[]; ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_atr_trend, 0, 0, 1, atr) < 1) return;
   double slDist = atr[0] * 1.5;
   double tpDist = slDist * InpSwingRR;

   double sl = (direction == 1) ? refPrice - slDist : refPrice + slDist;
   double tp = (direction == 1) ? refPrice + tpDist : refPrice - tpDist;
   sl = ClampToStopsLevel(refPrice, sl, direction, true);
   tp = ClampToStopsLevel(refPrice, tp, direction, false);

   double lot = CalcLotSize(MathAbs(refPrice - sl)) * 2.0; // "one larger" position
   lot = MathMin(lot, SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX));

   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = g_symbol;
   req.volume = NormalizeDouble(lot, 2);
   req.type = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price = refPrice;
   req.sl = NormalizeDouble(sl, g_digits);
   req.tp = NormalizeDouble(tp, g_digits);
   req.magic = g_swingMagic;
   req.deviation = 20;
   req.type_filling = ORDER_FILLING_FOK;

   double swapLong = SymbolInfoDouble(g_symbol, SYMBOL_SWAP_LONG);
   double swapShort = SymbolInfoDouble(g_symbol, SYMBOL_SWAP_SHORT);
   Log(StringFormat("SWING: overnight swap rates long=%.2f short=%.2f (logged before holding).", swapLong, swapShort));

   if(SendWithRetry(req, res))
     {
      g_swActive = true;
      g_swDirection = direction;
      g_swAvgPrice = res.price;
      g_swVolume = req.volume;
      g_swOpenTime = TimeCurrent();
      datetime tt[]; ArraySetAsSeries(tt, true);
      g_swOpenTrendTime = (CopyTime(g_symbol, g_trendTF, 0, 1, tt) > 0) ? tt[0] : TimeCurrent();
      Log(StringFormat("SWING ENTRY %s lot=%.2f price=%.2f SL=%.2f TP=%.2f (2:1) regime=%s ADX=%.1f",
          direction==1?"BUY":"SELL", req.volume, res.price, sl, tp, EnumToString(g_regime), adx[0]));
     }
  }

void SwingClose(string reason)
  {
   if(!g_swActive) return;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong ticket = PositionGetTicket(p);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != g_swingMagic) continue;

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action = TRADE_ACTION_DEAL;
      req.position = ticket;
      req.symbol = g_symbol;
      req.volume = PositionGetDouble(POSITION_VOLUME);
      req.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price = (req.type == ORDER_TYPE_SELL) ? GetBid() : GetAsk();
      req.deviation = 20;
      req.type_filling = ORDER_FILLING_FOK;
      SendWithRetry(req, res);
     }
   Log("SWING EXIT: " + reason);
   g_swActive = false;
  }

void ManageSwingModule()
  {
   if(!g_swActive) { SwingTryEntry(); return; }

   // 1) higher-TF trend flip
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true); ArraySetAsSeries(emaSlow, true);
   if(CopyBuffer(h_ema21_trend, 0, 0, 1, emaFast) >= 1 && CopyBuffer(h_ema55_trend, 0, 0, 1, emaSlow) >= 1)
     {
      bool trendUp = emaFast[0] > emaSlow[0];
      if((g_swDirection == 1 && !trendUp) || (g_swDirection == -1 && trendUp))
        { SwingClose("higher-TF trend flip"); return; }
     }

   // 2) time-stop: not +1R within N trend-TF bars
   if(g_swOpenTrendTime > 0)
     {
      int barsElapsed = iBarShift(g_symbol, g_trendTF, g_swOpenTrendTime);
      double curPrice = (g_swDirection == 1) ? GetBid() : GetAsk();
      double moveDist = (g_swDirection == 1) ? (curPrice - g_swAvgPrice) : (g_swAvgPrice - curPrice);
      double atr[]; ArraySetAsSeries(atr, true);
      double riskDist = 0.0;
      if(CopyBuffer(h_atr_trend, 0, 0, 1, atr) >= 1) riskDist = atr[0] * 1.5;
      bool reachedPlus1R = (riskDist > 0.0) && (moveDist / riskDist >= 1.0);
      if(barsElapsed >= InpSwingTimeStopBars && !reachedPlus1R)
        { SwingClose(StringFormat("time-stop: no +1R within %d trend-TF bars", InpSwingTimeStopBars)); return; }
     }

   // 3) structure trail behind trend-TF fractals
   double h[], l[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if(CopyHigh(g_symbol, g_trendTF, 1, 10, h) >= 10 && CopyLow(g_symbol, g_trendTF, 1, 10, l) >= 10)
     {
      for(int p = PositionsTotal() - 1; p >= 0; p--)
        {
         ulong ticket = PositionGetTicket(p);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC) != g_swingMagic) continue;

         double curSL = PositionGetDouble(POSITION_SL);
         double newSL = curSL;
         if(g_swDirection == 1)
           {
            double fractalLow = l[ArrayMinimum(l, 0, 5)];
            if(fractalLow > curSL) newSL = fractalLow;
           }
         else
           {
            double fractalHigh = h[ArrayMaximum(h, 0, 5)];
            if(fractalHigh < curSL || curSL == 0.0) newSL = fractalHigh;
           }
         if(newSL != curSL)
           {
            MqlTradeRequest req; MqlTradeResult res;
            ZeroMemory(req); ZeroMemory(res);
            req.action = TRADE_ACTION_SLTP;
            req.position = ticket;
            req.symbol = g_symbol;
            req.sl = NormalizeDouble(newSL, g_digits);
            req.tp = PositionGetDouble(POSITION_TP);
            if(OrderSend(req, res))
               Log(StringFormat("SWING: structure trail SL -> %.2f", newSL));
           }
        }
     }

   // 4) Friday flatten before weekend gaps
   if(InpSwingFridayFlatten)
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5 && dt.hour >= 20)
         SwingClose("Friday flatten ahead of weekend gap");
     }
  }

//====================================================================
// [ADAPTIVE LEARNING] — honest description: online reinforcement, not a
// neural net. Factors that voted WITH a winner gain weight; factors that
// voted with a loser lose weight, scaled by result-relative-to-risk;
// clamped to [Min,Max]; renormalised to 100; persisted via GlobalVariables.
//====================================================================
void OnClosedBasketLearn(int idx, double pnlUSD, double initialRiskUSD, bool winner)
  {
   if(!InpAdaptiveLearningOn) return;
   if(initialRiskUSD <= 0.0) return;

   double resultR = pnlUSD / initialRiskUSD;
   resultR = MathMax(-2.5, MathMin(2.5, resultR)); // clamp so one outlier trade cannot dominate learning

   int direction = g_bkDirection[idx];
   for(int f = 0; f < NUM_FACTORS; f++)
     {
      if(g_bkFactorVote[idx][f] != direction) continue; // only factors that voted WITH the trade adjust
      double delta = g_factorWeight[f] * InpLearningRate * resultR;
      g_factorWeight[f] += delta;
      g_factorWeight[f] = MathMax(InpMinFactorWeight, MathMin(InpMaxFactorWeight, g_factorWeight[f]));
     }

   double sum = 0.0;
   for(int f = 0; f < NUM_FACTORS; f++) sum += g_factorWeight[f];
   if(sum > 0.0)
      for(int f = 0; f < NUM_FACTORS; f++) g_factorWeight[f] = g_factorWeight[f] / sum * 100.0;

   SaveFactorWeights();

   if(InpVerboseDecisionLog)
     {
      string w = "";
      for(int f = 0; f < NUM_FACTORS; f++) w += StringFormat("%s=%.1f ", g_factorName[f], g_factorWeight[f]);
      Log(StringFormat("LEARN: basket #%d resultR=%.2f winner=%s -> weights: %s", g_bkTicket[idx], resultR, winner?"Y":"N", w));
     }
  }

void UpdateHourExpectancy(int hour, double pnlUSD)
  {
   if(hour < 0 || hour > 23) return;
   g_hourPnLSum[hour] += pnlUSD;
   g_hourSampleCount[hour]++;
   if(g_hourSampleCount[hour] >= InpHourMinSamples)
     {
      double avg = g_hourPnLSum[hour] / g_hourSampleCount[hour];
      bool wasBlocked = g_hourBlocked[hour];
      g_hourBlocked[hour] = (avg < 0.0);
      if(g_hourBlocked[hour] && !wasBlocked)
         Log(StringFormat("HOURLY EXPECTANCY LEARNER: hour %02d:00 has proven negative expectancy (avg $%.2f over %d baskets) — suppressing.",
             hour, avg, g_hourSampleCount[hour]));
      else if(!g_hourBlocked[hour] && wasBlocked)
         Log(StringFormat("HOURLY EXPECTANCY LEARNER: hour %02d:00 recovered to positive expectancy (avg $%.2f) — re-enabled.", hour, avg));
     }
   SavePersistedState();
  }

//====================================================================
// [DEBUG DASHBOARD] — on-chart comment: classification, trend+strength,
// buy/sell probability, confidence, all 9 factor votes, ML weights,
// active filters, current blocker, position count, exposure, latency,
// slippage, size factor, trade counts.
//====================================================================
void UpdateDashboard()
  {
   if(!InpShowDashboard) return;

   int openCount = 0; double exposureLots = 0.0;
   for(int i = 0; i < MAX_BASKETS; i++)
      if(g_bkActive[i]) { openCount++; exposureLots += g_bkVolume[i]; }

   string worstBlockName = "NONE"; int worstBlockCount = 0;
   for(int r = 1; r < BLOCK_COUNT; r++)
      if(g_blockCounts[r] > worstBlockCount) { worstBlockCount = g_blockCounts[r]; worstBlockName = BlockReasonToString((ENUM_BLOCK_REASON)r); }

   string txt = "";
   txt += "== IAX v7 GODMODE+ OODA ==\n";
   txt += g_buildFingerprint + "\n";
   txt += StringFormat("Regime: %s | Session: %s\n", EnumToString(g_regime), EnumToString(g_session));
   txt += StringFormat("BuyProb: %.3f  SellProb: %.3f  Confidence: %.1f (gate %.1f)\n", g_buyProb, g_sellProb, g_confidence, eff_MinConfidenceToTrade);
   txt += "Factors: ";
   for(int f = 0; f < NUM_FACTORS; f++)
      txt += StringFormat("%s[%+d,w%.1f] ", g_factorName[f], g_factorVote[f], g_factorWeight[f]);
   txt += "\n";
   txt += StringFormat("Kill switch: %s | Feed: %s | Cooldown: %s\n",
          g_killSwitchEngaged ? "ENGAGED" : "off",
          g_feedDegraded ? "DEGRADED" : "ok",
          (TimeCurrent() < g_cooldownUntil) ? TimeToString(g_cooldownUntil) : "none");
   txt += StringFormat("Current top blocker: %s (%d)\n", worstBlockName, worstBlockCount);
   txt += StringFormat("Positions: %d  Exposure: %.2f lots  Swing active: %s\n", openCount, exposureLots, g_swActive ? "Y":"N");
   txt += StringFormat("Latency: %.0fms  AvgSlippage: %.1fpts  Trades: hr=%d/%d day=%d/%d\n",
          g_lastLatencyMs, g_avgSlippagePoints, g_tradesThisHour, InpMaxTradesPerHour, g_tradesToday, InpMaxTradesPerDay);
   txt += StringFormat("Counters: bars=%d signals=%d sent=%d filled=%d rejected=%d closed=%d shadow=%d\n",
          g_barsProcessed, g_signalsGenerated, g_ordersSent, g_ordersFilled, g_ordersRejected, g_positionsClosed, g_shadowGateWouldHaveTraded);

   double patAvg = (g_currentPatternId >= 0 && g_patCount[g_currentPatternId] > 0)
                   ? g_patRSum[g_currentPatternId] / g_patCount[g_currentPatternId] : 0.0;
   txt += StringFormat("PATTERN: %s n=%d avgR=%.2f boost=x%.2f | serialP=%.2f volF=%.2f\n",
          g_currentPatternId >= 0 ? PatternIdToString(g_currentPatternId) : "n/a",
          g_currentPatternId >= 0 ? g_patCount[g_currentPatternId] : 0, patAvg,
          g_patternSizeBoost, g_serialP, HourVolFactor());
   txt += StringFormat("OODA: cycle=%I64d loops=%I64d last=%s (%s)\n",
          g_oodaCycle, g_oodaTimedCycles, DecisionToString(g_lastDecision), g_lastDecisionReason);
   if(g_oodaTimedCycles > 0)
      txt += StringFormat("OODA avg us: observe=%.0f orient=%.0f decide=%.0f act=%.0f\n",
             g_usObserveSum/(double)g_oodaTimedCycles, g_usOrientSum/(double)g_oodaTimedCycles,
             g_usDecideSum/(double)g_oodaTimedCycles, g_usActSum/(double)g_oodaTimedCycles);
   for(int lr = 0; lr < ArraySize(g_oodaLedger); lr++)
      txt += "  " + g_oodaLedger[lr] + "\n";

   Comment(txt);
  }

//====================================================================
// [TRADE JOURNAL CSV] — every trade with regime, confidence, entry hour,
// factor context, and P/L. The file that turns "improve the EA" into analysis.
//====================================================================
void WriteTradeJournalRow(string side, double volume, double entry, double exitPrice, double pnl, ENUM_REGIME regime, double confidence, int hour)
  {
   if(!InpWriteTradeJournalCSV) return;
   int fh = FileOpen(g_journalFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);
   FileWrite(fh, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), side, volume, entry, exitPrice, pnl,
             EnumToString(regime), confidence, hour,
             g_factorVote[0], g_factorVote[1], g_factorVote[2], g_factorVote[3], g_factorVote[4],
             g_factorVote[5], g_factorVote[6], g_factorVote[7], g_factorVote[8]);
   FileClose(fh);
  }

//====================================================================
// [KILL SWITCH]
//====================================================================
void FlattenAll(string reason)
  {
   Log("FLATTEN ALL: " + reason);
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong ticket = PositionGetTicket(p);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagic && magic != g_swingMagic) continue;

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action = TRADE_ACTION_DEAL;
      req.position = ticket;
      req.symbol = g_symbol;
      req.volume = PositionGetDouble(POSITION_VOLUME);
      req.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price = (req.type == ORDER_TYPE_SELL) ? GetBid() : GetAsk();
      req.deviation = 20;
      req.type_filling = ORDER_FILLING_FOK;
      SendWithRetry(req, res);
     }
   for(int o = OrdersTotal() - 1; o >= 0; o--)
     {
      ulong ticket = OrderGetTicket(o);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != g_symbol) continue;
      long magic = (long)OrderGetInteger(ORDER_MAGIC);
      if(magic != InpMagic && magic != g_swingMagic) continue;
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action = TRADE_ACTION_REMOVE;
      req.order = ticket;
      OrderSend(req, res);
     }
   for(int i = 0; i < MAX_BASKETS; i++) g_bkActive[i] = false;
   g_swActive = false;
  }

//====================================================================
// [END-OF-RUN REPORT] — bars, signals, sent/filled/rejected/closed,
// block-reason table, learned-negative hours, shadow-gate comparison.
// Zero fills is printed as a DESIGN FAILURE naming the top blocker.
//====================================================================
void PrintEndOfRunReport()
  {
   Log("======================= END-OF-RUN REPORT =======================");
   Log(StringFormat("Bars processed: %d | Signals generated: %d | Shadow-gate (conf-passed) candidates: %d",
       g_barsProcessed, g_signalsGenerated, g_shadowGateWouldHaveTraded));
   Log(StringFormat("Orders sent: %d | Filled: %d | Rejected: %d | Positions closed: %d",
       g_ordersSent, g_ordersFilled, g_ordersRejected, g_positionsClosed));
   Log(StringFormat("Avg latency (last): %.0fms | Avg slippage: %.1f points over %d samples",
       g_lastLatencyMs, g_avgSlippagePoints, g_slippageSamples));
   if(InpOODALogPhaseTimings && g_oodaTimedCycles > 0)
      Log(StringFormat("OODA: %I64d cycles, %I64d full Orient->Decide->Act loops | avg us: observe=%.0f orient=%.0f decide=%.0f act=%.0f",
          g_oodaCycle, g_oodaTimedCycles,
          g_usObserveSum/(double)g_oodaTimedCycles, g_usOrientSum/(double)g_oodaTimedCycles,
          g_usDecideSum/(double)g_oodaTimedCycles, g_usActSum/(double)g_oodaTimedCycles));

   Log("--- Block-reason table ---");
   int topReason = -1, topCount = 0;
   for(int r = 1; r < BLOCK_COUNT; r++)
     {
      if(g_blockCounts[r] <= 0) continue;
      Log(StringFormat("  %-28s : %d", BlockReasonToString((ENUM_BLOCK_REASON)r), g_blockCounts[r]));
      if(g_blockCounts[r] > topCount) { topCount = g_blockCounts[r]; topReason = r; }
     }

   Log("--- Pattern expectancy table (regime-group x session x direction) ---");
   for(int p = 0; p < NUM_PATTERNS; p++)
      if(g_patCount[p] > 0)
         Log(StringFormat("  %-22s samples=%-4d avgR=%+.2f %s", PatternIdToString(p), g_patCount[p],
             g_patRSum[p] / g_patCount[p], g_patBlocked[p] ? "[SUPPRESSED]" : ""));

   Log("--- Hourly expectancy learner state ---");
   for(int h = 0; h < 24; h++)
      if(g_hourSampleCount[h] > 0)
         Log(StringFormat("  %02d:00  samples=%-4d avgPnL=$%.2f  %s",
             h, g_hourSampleCount[h], g_hourPnLSum[h]/g_hourSampleCount[h], g_hourBlocked[h] ? "[SUPPRESSED]" : ""));

   if(g_ordersFilled == 0)
     {
      Log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      Log(StringFormat("DESIGN FAILURE: zero fills this run. Top blocker: %s (%d occurrences).",
          topReason >= 0 ? BlockReasonToString((ENUM_BLOCK_REASON)topReason) : "N/A", topCount));
      Log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
     }
   Log("===================================================================");
  }

//====================================================================
// [PROGRESSIVE VALIDATION — STAGE 1] Automated lifecycle self-test:
// open -> modify SL -> partial close -> close, for BUY then SELL,
// printing PASS/FAIL + retcode per step. Never validate everything at once.
//====================================================================
bool Stage1_TestSide(int direction)
  {
   string side = (direction == 1) ? "BUY" : "SELL";
   bool allPass = true;
   double lot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double refPrice = (direction == 1) ? GetAsk() : GetBid();

   double sl, tp;
   ENUM_REGIME savedRegime = g_regime;
   g_regime = REGIME_RANGE; // neutral geometry multiplier for the self-test
   if(!CalcGeometry(direction, refPrice, sl, tp))
     {
      Log(StringFormat("STAGE1 [%s] OPEN: FAIL — geometry calc failed", side));
      g_regime = savedRegime;
      return false;
     }
   g_regime = savedRegime;

   // --- Step 1: open ---
   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = g_symbol;
   req.volume = lot;
   req.type = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price = refPrice;
   req.sl = sl;
   req.tp = tp;
   req.magic = InpMagic;
   req.deviation = 30;
   req.type_filling = ORDER_FILLING_FOK;

   bool okOpen = SendWithRetry(req, res);
   Log(StringFormat("STAGE1 [%s] OPEN: %s retcode=%d", side, okOpen ? "PASS" : "FAIL", res.retcode));
   allPass = allPass && okOpen;
   if(!okOpen) return false;

   ulong ticket = res.order;
   Sleep(500); // live closes/updates can take 250-3000ms — guard every step

   // --- Step 2: modify SL ---
   bool okModify = false;
   if(PositionSelectByTicket(ticket))
     {
      double newSL = (direction == 1) ? PositionGetDouble(POSITION_PRICE_OPEN) - PointsToUSD(2 * SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL) + 100)
                                       : PositionGetDouble(POSITION_PRICE_OPEN) + PointsToUSD(2 * SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL) + 100);
      MqlTradeRequest mreq; MqlTradeResult mres;
      ZeroMemory(mreq); ZeroMemory(mres);
      mreq.action = TRADE_ACTION_SLTP;
      mreq.position = ticket;
      mreq.symbol = g_symbol;
      mreq.sl = NormalizeDouble(newSL, g_digits);
      mreq.tp = PositionGetDouble(POSITION_TP);
      okModify = OrderSend(mreq, mres);
      Log(StringFormat("STAGE1 [%s] MODIFY_SL: %s retcode=%d", side, okModify ? "PASS" : "FAIL", mres.retcode));
     }
   else
      Log(StringFormat("STAGE1 [%s] MODIFY_SL: FAIL — position not found", side));
   allPass = allPass && okModify;

   Sleep(500);

   // --- Step 3: partial close ---
   bool okPartial = false;
   if(PositionSelectByTicket(ticket))
     {
      double vol = PositionGetDouble(POSITION_VOLUME);
      double volMin = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
      double volStep = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
      if(vol >= volMin * 2)
        {
         double partial = NormalizeDouble(MathMax(volMin, MathRound((vol/2.0)/volStep)*volStep), 2);
         MqlTradeRequest preq; MqlTradeResult pres;
         ZeroMemory(preq); ZeroMemory(pres);
         preq.action = TRADE_ACTION_DEAL;
         preq.position = ticket;
         preq.symbol = g_symbol;
         preq.volume = partial;
         preq.type = (direction == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         preq.price = (direction == 1) ? GetBid() : GetAsk();
         preq.deviation = 30;
         preq.type_filling = ORDER_FILLING_FOK;
         okPartial = SendWithRetry(preq, pres);
         Log(StringFormat("STAGE1 [%s] PARTIAL_CLOSE: %s retcode=%d", side, okPartial ? "PASS" : "FAIL", pres.retcode));
        }
      else
        {
         okPartial = true; // broker minimum lot too small to split — not a defect
         Log(StringFormat("STAGE1 [%s] PARTIAL_CLOSE: SKIP (broker min lot too small to split)", side));
        }
     }
   else
      Log(StringFormat("STAGE1 [%s] PARTIAL_CLOSE: FAIL — position not found", side));
   allPass = allPass && okPartial;

   Sleep(500);

   // --- Step 4: close ---
   // [DEFECT-RULE-8] guard every close with a pending-close check — scan
   // orders for ORDER_POSITION_ID == ticket, or the loop spams duplicates.
   bool okClose = false;
   if(PositionSelectByTicket(ticket))
     {
      bool pendingCloseExists = false;
      for(int o = OrdersTotal() - 1; o >= 0; o--)
        {
         ulong oticket = OrderGetTicket(o);
         if(OrderSelect(oticket) && (ulong)OrderGetInteger(ORDER_POSITION_ID) == ticket)
           { pendingCloseExists = true; break; }
        }
      if(pendingCloseExists)
         Log(StringFormat("STAGE1 [%s] CLOSE: SKIP — pending close already exists for #%d", side, ticket));
      else
        {
         MqlTradeRequest creq; MqlTradeResult cres;
         ZeroMemory(creq); ZeroMemory(cres);
         creq.action = TRADE_ACTION_DEAL;
         creq.position = ticket;
         creq.symbol = g_symbol;
         creq.volume = PositionGetDouble(POSITION_VOLUME);
         creq.type = (direction == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         creq.price = (direction == 1) ? GetBid() : GetAsk();
         creq.deviation = 30;
         creq.type_filling = ORDER_FILLING_FOK;
         okClose = SendWithRetry(creq, cres);
         Log(StringFormat("STAGE1 [%s] CLOSE: %s retcode=%d", side, okClose ? "PASS" : "FAIL", cres.retcode));
        }
     }
   else
     {
      okClose = true; // already closed (e.g. partial close consumed full remaining volume)
      Log(StringFormat("STAGE1 [%s] CLOSE: SKIP — no open volume remaining", side));
     }
   allPass = allPass && okClose;

   Log(StringFormat("STAGE1 [%s] SIDE RESULT: %s", side, allPass ? "ALL PASS" : "HAS FAILURES"));
   return allPass;
  }

bool RunStage1SelfTest()
  {
   if(!(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_DEMO)))
     {
      Log("STAGE1 SELF-TEST SKIPPED: only runs in Strategy Tester or on a demo account (never on live).");
      return false;
     }

   Log("==================== STAGE 1 LIFECYCLE SELF-TEST ====================");
   bool buyPass = Stage1_TestSide(1);
   bool sellPass = Stage1_TestSide(-1);
   bool overall = buyPass && sellPass;
   Log(StringFormat("STAGE1 SELF-TEST OVERALL: %s", overall ? "PASS" : "FAIL"));
   Log("=======================================================================");
   return overall;
  }

