//+------------------------------------------------------------------+
//|                                          GoldPriceActionEA.mq5   |
//|              Pure price action Gold expert advisor (XAUUSD)      |
//|        Market structure + candlestick behaviour. No indicators.  |
//+------------------------------------------------------------------+
#property copyright "Quant Systems"
#property version   "1.00"
#property description "Gold EA driven exclusively by raw price action: "
#property description "swing structure (BOS / CHoCH), impulse-pullback "
#property description "geometry and candlestick behaviour read straight "
#property description "from OHLC. No indicators, no indicator handles, "
#property description "no supply/demand or order-block zones, no DLLs "
#property description "and no external files. Entries and exits are both "
#property description "produced by price action alone."

#include <Trade\Trade.mqh>

//======================================================================
// ENUMS
//======================================================================
enum ENUM_BIAS      { BIAS_NONE = 0, BIAS_BULL = 1, BIAS_BEAR = -1 };
enum ENUM_TRAIL     { TRAIL_OFF, TRAIL_STRUCTURE, TRAIL_CANDLE };
enum ENUM_RISK_BASE { RISK_ON_BALANCE, RISK_ON_EQUITY };
enum ENUM_CENT_MODE { CENT_AUTO, CENT_FORCE_ON, CENT_FORCE_OFF };

//======================================================================
// INPUT PARAMETERS
//======================================================================
input group "=== General ==="
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_H1;   // Working timeframe
input long            InpMagic            = 20260807;    // Magic number
input int             InpSlippagePoints   = 30;          // Max deviation (points)
input string          InpComment          = "GoldPA";    // Order comment

input group "=== Market structure (raw swings) ==="
input int             InpSwingStrength    = 2;      // Bars either side that define a swing
input int             InpStructureLookback= 180;    // Bars scanned for structure
input int             InpMaxBarsSinceBreak= 12;     // Only trade structure broken this recently

input group "=== Entry models (price action only) ==="
input bool            InpTradeBreakouts   = true;   // Enter on the break-of-structure candle
input bool            InpTradePullbacks   = true;   // Enter on a pullback + rejection candle
input bool            InpUseEngulfing     = true;   // Engulfing confirmation
input bool            InpUsePinBar        = true;   // Rejection / pin bar confirmation
input bool            InpUseInsideBreak   = true;   // Inside-bar breakout confirmation
input double          InpMinPullbackPct   = 20.0;   // Min retracement of the impulse leg (%)
input double          InpMaxPullbackPct   = 80.0;   // Max retracement of the impulse leg (%)
input double          InpCloseStrengthPct = 60.0;   // Signal close must sit in this % of its range

input group "=== Candle pattern geometry ==="
input double          InpEngulfBodyFactor = 1.0;    // Engulfing body >= factor x prior body
input double          InpPinWickRatio     = 0.55;   // Rejection wick >= ratio of candle range
input double          InpPinBodyMaxRatio  = 0.35;   // Pin body <= ratio of candle range
input double          InpPinOppWickMax    = 0.25;   // Opposite wick <= ratio of candle range

input group "=== Raw range filters (no indicators) ==="
input int             InpRangeLookback    = 20;     // Bars used for the average candle range
input double          InpMinRangeFactor   = 0.55;   // Signal range >= factor x average range
input double          InpMaxRangeFactor   = 3.50;   // Signal range <= factor x average range (no climax)
input int             InpMaxSpreadPoints  = 0;      // Max spread in points (0 = auto from range)

input group "=== Risk & position sizing ==="
input ENUM_RISK_BASE  InpRiskBase         = RISK_ON_BALANCE; // Risk reference
input double          InpRiskPercent      = 1.0;    // Risk per trade (%)
input bool            InpUseFixedLot      = false;  // Use a fixed lot instead of % risk
input double          InpFixedLot         = 0.01;   // Fixed lot size
input double          InpMinAccountUSD    = 5.0;    // Do not trade below this balance (real USD, cent-adjusted)
input ENUM_CENT_MODE  InpCentAccount      = CENT_AUTO; // Cent account detection
input double          InpCentFactor       = 100.0;  // Account units per 1 real USD on a cent account
input double          InpMaxRiskPercentCap = 0.0;   // Hard risk ceiling %: skip trade if min lot exceeds it (0 = off)
input double          InpSLBufferFactor   = 0.15;   // SL buffer as a factor of average range
input double          InpMinStopRangeFactor = 0.35; // Stop must be >= factor x average range (blocks noise-width stops)

input group "=== Trade management (price action exits) ==="
input double          InpRewardR          = 2.0;    // Take profit in R (0 = no fixed TP)
input double          InpBreakevenR       = 1.0;    // Move to breakeven at this R (0 = off)
input double          InpPartialR         = 1.0;    // Partial close at this R (0 = off)
input double          InpPartialPercent   = 50.0;   // Percent of the position closed at InpPartialR
input ENUM_TRAIL      InpTrailMode        = TRAIL_STRUCTURE; // Trailing method
input double          InpTrailStartR      = 1.0;    // Start trailing at this R
input int             InpTrailCandles     = 3;      // Bars used by the candle trail
input bool            InpExitOnStructure  = true;   // Exit when structure flips against the trade
input bool            InpExitOnReversalBar= true;   // Exit on an opposing rejection/engulfing bar
input int             InpTimeStopBars     = 0;      // Give up after N bars (0 = off)
input double          InpTimeStopMinR     = 0.5;    // ...unless the trade is at least this many R

input group "=== Session & exposure limits ==="
input bool            InpUseTimeFilter    = false;  // Restrict trading hours (server time)
input int             InpStartHour        = 7;      // Session start hour
input int             InpEndHour          = 20;     // Session end hour
input int             InpMaxTradesPerDay  = 0;      // Max entries per day (0 = unlimited)
input double          InpMaxDailyLossPct  = 0.0;    // Stop for the day after this loss % (0 = off)
input bool            InpAllowLongs       = true;   // Allow long trades
input bool            InpAllowShorts      = true;   // Allow short trades

//======================================================================
// NAMED CONSTANTS
//======================================================================
#define MAX_SWINGS            64
#define EXTRA_BARS_MARGIN     50
#define MIN_BARS_REQUIRED     60
#define STATE_PREFIX          "GPA_"
#define AUTO_SPREAD_FRACTION  0.15   // auto spread ceiling = 15% of the average candle range
#define PCT                   100.0

//======================================================================
// STRUCTS
//======================================================================
struct SwingPoint
{
   int      bar;      // series index (0 = forming bar)
   double   price;
   datetime time;
};

//======================================================================
// GLOBALS
//======================================================================
CTrade      trade;
MqlRates    g_rates[];

SwingPoint  g_swingHigh[MAX_SWINGS];
SwingPoint  g_swingLow[MAX_SWINGS];
int         g_swingHighCount = 0;
int         g_swingLowCount  = 0;

ENUM_BIAS   g_bias        = BIAS_NONE;
int         g_breakBar    = -1;    // series index of the break-of-structure candle
double      g_breakLevel  = 0.0;   // swing level that was broken
double      g_legAnchor   = 0.0;   // origin of the impulse leg (invalidation reference)

double      g_avgRange    = 0.0;   // mean high-low range over InpRangeLookback bars
datetime    g_lastBarTime = 0;
datetime    g_currentDay  = 0;
double      g_dayStartEquity = 0.0;
bool        g_dayBlocked  = false;

// Sizing-refusal telemetry: what balance this symbol would actually need.
long        g_sizeSkips      = 0;
double      g_sizeNeedSum    = 0.0;
double      g_sizeNeedMin    = 0.0;
double      g_sizeNeedMax    = 0.0;
bool        g_sizeExplained  = false;   // CalculateLot already logged the reason

// Cent accounts denominate the balance in 1/100 USD. Percentages are
// unaffected, but every absolute figure the EA prints or compares against a
// USD threshold has to be divided by this.
double      g_centFactor  = 1.0;
bool        g_isCent      = false;

//======================================================================
// SMALL UTILITIES
//======================================================================
double PriceNorm(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double PointSize()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

//======================================================================
// CENT ACCOUNT DETECTION
//======================================================================
// MT5 exposes no cent-account flag, so this reads the account currency and
// the broker naming. Brokers label these accounts with a currency code such
// as USC / USDC / EUC, or put "cent" in the server or company name.
bool LooksLikeCentAccount()
{
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   StringToUpper(cur);

   if(cur == "USC" || cur == "USDC" || cur == "EUC" || cur == "EURC" ||
      cur == "GBC" || cur == "JPC"  || cur == "RUC" || cur == "AUC") return true;
   if(StringFind(cur, "CENT") >= 0) return true;

   // USDC / EURC style: a standard three-letter code with a trailing C.
   if(StringLen(cur) == 4 && StringSubstr(cur, 3, 1) == "C") return true;

   string server = AccountInfoString(ACCOUNT_SERVER);
   StringToUpper(server);
   if(StringFind(server, "CENT") >= 0) return true;

   string company = AccountInfoString(ACCOUNT_COMPANY);
   StringToUpper(company);
   if(StringFind(company, "CENT") >= 0) return true;

   return false;
}

void ResolveCentAccount()
{
   if(InpCentAccount == CENT_FORCE_ON)       g_isCent = true;
   else if(InpCentAccount == CENT_FORCE_OFF) g_isCent = false;
   else                                      g_isCent = LooksLikeCentAccount();

   g_centFactor = (g_isCent && InpCentFactor > 0.0) ? InpCentFactor : 1.0;

   if(g_isCent)
      Print("Cent account detected (currency ", AccountInfoString(ACCOUNT_CURRENCY),
            "). Balance figures are divided by ", DoubleToString(g_centFactor, 0),
            " when reported in real USD. Risk percentages are unchanged.");
}

// Account balance expressed in real USD, whatever the account denomination.
double RealBalance()
{
   return AccountInfoDouble(ACCOUNT_BALANCE) / g_centFactor;
}

double StopsDistance()
{
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freeze     = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double lvl        = (double)MathMax(stopsLevel, freeze) * PointSize();
   double spread     = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return MathMax(lvl, spread);
}

double CandleRange(const int i)   { return g_rates[i].high - g_rates[i].low; }
double CandleBody(const int i)    { return MathAbs(g_rates[i].close - g_rates[i].open); }
double UpperWick(const int i)     { return g_rates[i].high - MathMax(g_rates[i].open, g_rates[i].close); }
double LowerWick(const int i)     { return MathMin(g_rates[i].open, g_rates[i].close) - g_rates[i].low; }
bool   IsBullCandle(const int i)  { return g_rates[i].close > g_rates[i].open; }
bool   IsBearCandle(const int i)  { return g_rates[i].close < g_rates[i].open; }

double HighestHigh(const int fromBar, const int toBar)
{
   double hi = -DBL_MAX;
   for(int i = toBar; i <= fromBar && i < ArraySize(g_rates); i++)
      if(g_rates[i].high > hi) hi = g_rates[i].high;
   return hi;
}

double LowestLow(const int fromBar, const int toBar)
{
   double lo = DBL_MAX;
   for(int i = toBar; i <= fromBar && i < ArraySize(g_rates); i++)
      if(g_rates[i].low < lo) lo = g_rates[i].low;
   return lo;
}

//======================================================================
// PERSISTENT PER-TRADE STATE
// MT5 positions carry no custom payload, so the 1R reference and the
// management flags live in terminal global variables. They survive a
// restart or a recompile while the position is still open.
//======================================================================
string StateKey(const ulong ticket, const string suffix)
{
   return STATE_PREFIX + IntegerToString(InpMagic) + "_" +
          IntegerToString((long)ticket) + "_" + suffix;
}

void StateSet(const ulong ticket, const string suffix, const double value)
{
   GlobalVariableSet(StateKey(ticket, suffix), value);
}

double StateGet(const ulong ticket, const string suffix, const double fallback)
{
   double value = 0.0;
   if(GlobalVariableGet(StateKey(ticket, suffix), value)) return value;
   return fallback;
}

void StateClear(const ulong ticket)
{
   string keys[] = {"R", "PARTIAL", "BE", "OPENBAR"};
   for(int i = 0; i < ArraySize(keys); i++)
   {
      string name = StateKey(ticket, keys[i]);
      if(GlobalVariableCheck(name)) GlobalVariableDel(name);
   }
}

// Drop state left behind by positions that no longer exist.
void PruneState()
{
   string prefix = STATE_PREFIX + IntegerToString(InpMagic) + "_";
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) != 0) continue;

      string rest = StringSubstr(name, StringLen(prefix));
      int    sep  = StringFind(rest, "_");
      if(sep <= 0) continue;

      ulong ticket = (ulong)StringToInteger(StringSubstr(rest, 0, sep));
      if(ticket != 0 && PositionSelectByTicket(ticket)) continue;
      GlobalVariableDel(name);
   }
}

//======================================================================
// PRICE DATA
//======================================================================
bool RefreshRates()
{
   int need = InpStructureLookback + InpSwingStrength * 2 + EXTRA_BARS_MARGIN;
   ArraySetAsSeries(g_rates, true);
   int copied = CopyRates(_Symbol, InpTimeframe, 0, need, g_rates);
   if(copied < MIN_BARS_REQUIRED)
   {
      g_avgRange = 0.0;
      return false;
   }

   int    lookback = MathMin(InpRangeLookback, copied - 2);
   double sum      = 0.0;
   for(int i = 1; i <= lookback; i++) sum += CandleRange(i);
   g_avgRange = (lookback > 0) ? sum / lookback : 0.0;

   return (g_avgRange > 0.0);
}

bool IsNewBar()
{
   datetime t = (datetime)SeriesInfoInteger(_Symbol, InpTimeframe, SERIES_LASTBAR_DATE);
   if(t == 0 || t == g_lastBarTime) return false;
   g_lastBarTime = t;
   return true;
}

//======================================================================
// SWING DETECTION — raw fractal pivots, nothing smoothed or averaged
//======================================================================
bool IsSwingHigh(const int i)
{
   int total = ArraySize(g_rates);
   if(i - InpSwingStrength < 1 || i + InpSwingStrength > total - 1) return false;

   for(int k = 1; k <= InpSwingStrength; k++)
   {
      if(g_rates[i].high <= g_rates[i + k].high) return false;  // older side
      if(g_rates[i].high <= g_rates[i - k].high) return false;  // newer side
   }
   return true;
}

bool IsSwingLow(const int i)
{
   int total = ArraySize(g_rates);
   if(i - InpSwingStrength < 1 || i + InpSwingStrength > total - 1) return false;

   for(int k = 1; k <= InpSwingStrength; k++)
   {
      if(g_rates[i].low >= g_rates[i + k].low) return false;
      if(g_rates[i].low >= g_rates[i - k].low) return false;
   }
   return true;
}

//======================================================================
// STRUCTURE ENGINE
// Walks the window oldest -> newest, tracking the last swing that was
// already confirmed at that point in time, and flags a break of
// structure the moment a candle closes through it. A swing is only
// usable once InpSwingStrength bars have printed after it, so the walk
// never sees a level before the market could have seen it.
//======================================================================
void UpdateStructure()
{
   g_swingHighCount = 0;
   g_swingLowCount  = 0;
   g_bias           = BIAS_NONE;
   g_breakBar       = -1;
   g_breakLevel     = 0.0;
   g_legAnchor      = 0.0;

   int total   = ArraySize(g_rates);
   int deepest = MathMin(InpStructureLookback, total - InpSwingStrength - 1);
   if(deepest <= InpSwingStrength + 1) return;

   // Newest-first catalogue of confirmed swings (used by stops and trails).
   for(int i = InpSwingStrength + 1; i <= deepest; i++)
   {
      if(IsSwingHigh(i) && g_swingHighCount < MAX_SWINGS)
      {
         g_swingHigh[g_swingHighCount].bar   = i;
         g_swingHigh[g_swingHighCount].price = g_rates[i].high;
         g_swingHigh[g_swingHighCount].time  = g_rates[i].time;
         g_swingHighCount++;
      }
      if(IsSwingLow(i) && g_swingLowCount < MAX_SWINGS)
      {
         g_swingLow[g_swingLowCount].bar   = i;
         g_swingLow[g_swingLowCount].price = g_rates[i].low;
         g_swingLow[g_swingLowCount].time  = g_rates[i].time;
         g_swingLowCount++;
      }
   }

   // Chronological walk: bar index counts down towards the newest closed bar.
   double refHigh = 0.0, refLow = 0.0;
   int    refHighBar = -1, refLowBar = -1;
   bool   hasHigh = false, hasLow = false;

   for(int b = deepest - InpSwingStrength; b >= 1; b--)
   {
      int s = b + InpSwingStrength;   // swing candidate confirmed exactly at bar b

      if(IsSwingHigh(s))
      {
         refHigh = g_rates[s].high; refHighBar = s; hasHigh = true;
      }
      if(IsSwingLow(s))
      {
         refLow = g_rates[s].low; refLowBar = s; hasLow = true;
      }

      if(hasHigh && g_rates[b].close > refHigh)
      {
         g_bias       = BIAS_BULL;
         g_breakBar   = b;
         g_breakLevel = refHigh;
         g_legAnchor  = (hasLow && refLowBar > b) ? refLow : LowestLow(refHighBar, b);
         hasHigh      = false;       // consumed: a fresh swing high must form first
      }
      else if(hasLow && g_rates[b].close < refLow)
      {
         g_bias       = BIAS_BEAR;
         g_breakBar   = b;
         g_breakLevel = refLow;
         g_legAnchor  = (hasHigh && refHighBar > b) ? refHigh : HighestHigh(refLowBar, b);
         hasLow       = false;
      }
   }
}

// Most recent confirmed swing that is older than (or at) the given bar.
bool LastSwingLowBefore(const int bar, double &price)
{
   for(int i = 0; i < g_swingLowCount; i++)
      if(g_swingLow[i].bar >= bar) { price = g_swingLow[i].price; return true; }
   return false;
}

bool LastSwingHighBefore(const int bar, double &price)
{
   for(int i = 0; i < g_swingHighCount; i++)
      if(g_swingHigh[i].bar >= bar) { price = g_swingHigh[i].price; return true; }
   return false;
}

//======================================================================
// CANDLESTICK BEHAVIOUR
// Every test below reads open/high/low/close directly.
//======================================================================
bool BullishEngulfing(const int i)
{
   if(!IsBullCandle(i) || !IsBearCandle(i + 1)) return false;
   if(CandleBody(i) < CandleBody(i + 1) * InpEngulfBodyFactor) return false;
   if(g_rates[i].close < g_rates[i + 1].open) return false;
   if(g_rates[i].open  > g_rates[i + 1].close) return false;
   return true;
}

bool BearishEngulfing(const int i)
{
   if(!IsBearCandle(i) || !IsBullCandle(i + 1)) return false;
   if(CandleBody(i) < CandleBody(i + 1) * InpEngulfBodyFactor) return false;
   if(g_rates[i].close > g_rates[i + 1].open) return false;
   if(g_rates[i].open  < g_rates[i + 1].close) return false;
   return true;
}

bool BullishPinBar(const int i)
{
   double range = CandleRange(i);
   if(range <= 0.0) return false;
   if(LowerWick(i) / range < InpPinWickRatio)    return false;
   if(CandleBody(i) / range > InpPinBodyMaxRatio) return false;
   if(UpperWick(i) / range > InpPinOppWickMax)    return false;
   return (g_rates[i].close - g_rates[i].low) / range >= 0.5;
}

bool BearishPinBar(const int i)
{
   double range = CandleRange(i);
   if(range <= 0.0) return false;
   if(UpperWick(i) / range < InpPinWickRatio)     return false;
   if(CandleBody(i) / range > InpPinBodyMaxRatio) return false;
   if(LowerWick(i) / range > InpPinOppWickMax)    return false;
   return (g_rates[i].high - g_rates[i].close) / range >= 0.5;
}

// Bar i+1 compressed inside bar i+2, bar i then closes out of the mother bar.
bool InsideBarBreakUp(const int i)
{
   if(g_rates[i + 1].high > g_rates[i + 2].high) return false;
   if(g_rates[i + 1].low  < g_rates[i + 2].low)  return false;
   return (IsBullCandle(i) && g_rates[i].close > g_rates[i + 2].high);
}

bool InsideBarBreakDown(const int i)
{
   if(g_rates[i + 1].high > g_rates[i + 2].high) return false;
   if(g_rates[i + 1].low  < g_rates[i + 2].low)  return false;
   return (IsBearCandle(i) && g_rates[i].close < g_rates[i + 2].low);
}

// Close position inside the candle range: conviction into the close.
bool ClosesStrong(const int i, const int direction)
{
   double range = CandleRange(i);
   if(range <= 0.0) return false;
   double pos = (direction > 0)
                ? (g_rates[i].close - g_rates[i].low) / range
                : (g_rates[i].high - g_rates[i].close) / range;
   return (pos * PCT >= InpCloseStrengthPct);
}

// Candle is neither dead nor a climax bar, measured against raw ranges.
bool RangeAcceptable(const int i)
{
   if(g_avgRange <= 0.0) return false;
   double range = CandleRange(i);
   if(range < g_avgRange * InpMinRangeFactor) return false;
   if(range > g_avgRange * InpMaxRangeFactor) return false;
   return true;
}

int ConfirmationPattern(const int i, string &name)
{
   if(InpUseEngulfing && BullishEngulfing(i))    { name = "bull engulfing";    return  1; }
   if(InpUseEngulfing && BearishEngulfing(i))    { name = "bear engulfing";    return -1; }
   if(InpUsePinBar    && BullishPinBar(i))       { name = "bull rejection";    return  1; }
   if(InpUsePinBar    && BearishPinBar(i))       { name = "bear rejection";    return -1; }
   if(InpUseInsideBreak && InsideBarBreakUp(i))  { name = "inside bar break up";   return  1; }
   if(InpUseInsideBreak && InsideBarBreakDown(i)){ name = "inside bar break down"; return -1; }
   name = "";
   return 0;
}

//======================================================================
// GUARDS
//======================================================================
void ResetDayIfNeeded()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime day = StructToTime(dt);

   if(day != g_currentDay)
   {
      g_currentDay     = day;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dayBlocked     = false;
   }
}

void TodayStats(int &entries, double &realized)
{
   entries  = 0;
   realized = 0.0;
   if(!HistorySelect(g_currentDay, TimeCurrent() + 60)) return;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) continue;

      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN) entries++;
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
         realized += HistoryDealGetDouble(deal, DEAL_PROFIT)
                   + HistoryDealGetDouble(deal, DEAL_SWAP)
                   + HistoryDealGetDouble(deal, DEAL_COMMISSION);
   }
}

bool SpreadAcceptable()
{
   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point   = PointSize();
   if(point <= 0.0) return false;

   double ceiling = (InpMaxSpreadPoints > 0)
                    ? InpMaxSpreadPoints * point
                    : g_avgRange * AUTO_SPREAD_FRACTION;
   if(ceiling <= 0.0) return true;
   return (spread <= ceiling);
}

bool WithinSession()
{
   if(!InpUseTimeFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpStartHour == InpEndHour) return true;
   if(InpStartHour < InpEndHour)  return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
   return (dt.hour >= InpStartHour || dt.hour < InpEndHour);   // window crosses midnight
}

// Retcode 10018 (market closed) fires when a bar closes outside the symbol's
// trading session - common on Gold's daily break. Check the session table
// rather than sending an order that is certain to be rejected.
bool MarketOpen()
{
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   ENUM_DAY_OF_WEEK day = (ENUM_DAY_OF_WEEK)dt.day_of_week;
   long secNow = (long)dt.hour * 3600 + (long)dt.min * 60 + (long)dt.sec;

   datetime from = 0, to = 0;
   bool anySession = false;
   for(uint i = 0; SymbolInfoSessionTrade(_Symbol, day, i, from, to); i++)
   {
      anySession = true;
      if(secNow >= (long)from && secNow < (long)to) return true;
   }
   return !anySession;   // no session table published - let the broker decide
}

bool TradingAllowed()
{
   if(!MarketOpen()) return false;
   if(!MQLInfoInteger(MQL_TESTER) && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) return false;
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL) return false;
   if(RealBalance() < InpMinAccountUSD) return false;
   if(g_dayBlocked) return false;

   int    entries  = 0;
   double realized = 0.0;
   TodayStats(entries, realized);

   if(InpMaxTradesPerDay > 0 && entries >= InpMaxTradesPerDay) return false;

   if(InpMaxDailyLossPct > 0.0 && g_dayStartEquity > 0.0)
   {
      double lossPct = -realized / g_dayStartEquity * PCT;
      if(lossPct >= InpMaxDailyLossPct)
      {
         g_dayBlocked = true;
         Print("Daily loss limit reached (", DoubleToString(lossPct, 2), "%) - trading paused until tomorrow.");
         return false;
      }
   }
   return true;
}

//======================================================================
// POSITION HELPERS
//======================================================================
ulong FindPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      return ticket;
   }
   return 0;
}

double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = minLot;
   if(step <= 0.0) return 0.0;

   lot = MathFloor(lot / step) * step;
   // A broker minimum below the risk budget still trades: on a small account
   // the minimum lot is the floor, so the real risk can exceed InpRiskPercent.
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   int decimals = (int)MathMax(0, MathCeil(-MathLog10(step)));
   return NormalizeDouble(lot, decimals);
}

double CalculateLot(const double stopDistance, const ENUM_ORDER_TYPE type, const double price)
{
   if(stopDistance <= 0.0) return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return 0.0;

   double base = (InpRiskBase == RISK_ON_EQUITY)
                 ? AccountInfoDouble(ACCOUNT_EQUITY)
                 : AccountInfoDouble(ACCOUNT_BALANCE);
   double lossPerLot  = (stopDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0) return 0.0;

   double lot;
   if(InpUseFixedLot)
      lot = NormalizeLot(InpFixedLot);
   else
      lot = NormalizeLot(base * InpRiskPercent / PCT / lossPerLot);

   // NormalizeLot raises anything below the broker minimum up to that minimum,
   // so on an undersized account a single stop can cost many times
   // InpRiskPercent. Refuse the trade rather than take it at that size.
   if(InpMaxRiskPercentCap > 0.0 && base > 0.0)
   {
      double riskPct = lot * lossPerLot / base * PCT;
      if(riskPct > InpMaxRiskPercentCap)
      {
         // Record what this signal would have needed, then stay quiet. A run on
         // an undersized account otherwise buries the journal in identical
         // lines; the totals are printed once in OnDeinit.
         if(!InpUseFixedLot && InpRiskPercent > 0.0)
         {
            double need = lot * lossPerLot / (InpRiskPercent / PCT);
            g_sizeNeedSum += need;
            if(g_sizeSkips == 0 || need < g_sizeNeedMin) g_sizeNeedMin = need;
            if(need > g_sizeNeedMax)                     g_sizeNeedMax = need;
         }
         g_sizeSkips++;

         if(g_sizeSkips == 1)
            Print("Entry skipped: ", DoubleToString(lot, 2), " lots risk ",
                  DoubleToString(riskPct, 1), "% of ", DoubleToString(base, 2),
                  " (cap ", DoubleToString(InpMaxRiskPercentCap, 1),
                  "%). Further sizing refusals are summarised at the end of the run.");

         g_sizeExplained = true;
         return 0.0;
      }
   }

   // Never let the sized position exceed the free margin available.
   double margin = 0.0;
   if(OrderCalcMargin(type, _Symbol, lot, price, margin) && margin > 0.0)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin)
      {
         double scaled = lot * (freeMargin / margin) * 0.95;
         lot = NormalizeLot(scaled);
         if(OrderCalcMargin(type, _Symbol, lot, price, margin) && margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
            return 0.0;
      }
   }
   return lot;
}

//======================================================================
// ENTRY
//======================================================================
// Retracement of the impulse leg, expressed as a percentage. For a bull
// leg: 0% = at the extreme of the leg, 100% = back at its origin.
double PullbackPercent(const int direction, const double legExtreme, const double signalPrice)
{
   double legSize = (direction > 0) ? (legExtreme - g_legAnchor) : (g_legAnchor - legExtreme);
   if(legSize <= 0.0) return -1.0;

   double retrace = (direction > 0) ? (legExtreme - signalPrice) : (signalPrice - legExtreme);
   return retrace / legSize * PCT;
}

bool BuildSignal(int &direction, double &stopLoss, string &reason)
{
   direction = 0;
   stopLoss  = 0.0;
   reason    = "";

   if(g_bias == BIAS_NONE || g_breakBar < 1) return false;
   if(g_breakBar > InpMaxBarsSinceBreak)     return false;

   int dir = (g_bias == BIAS_BULL) ? 1 : -1;
   if(dir > 0 && !InpAllowLongs)  return false;
   if(dir < 0 && !InpAllowShorts) return false;

   const int sig = 1;                       // the just-closed candle
   if(!RangeAcceptable(sig)) return false;

   // --- Model A: the break-of-structure candle itself -----------------
   bool breakoutEntry = false;
   if(InpTradeBreakouts && g_breakBar == sig)
   {
      if(ClosesStrong(sig, dir))
      {
         breakoutEntry = true;
         reason = (dir > 0) ? "BOS close above swing high" : "BOS close below swing low";
      }
   }

   // --- Model B: pullback into the leg, then a rejection candle -------
   bool pullbackEntry = false;
   if(!breakoutEntry && InpTradePullbacks && g_breakBar > sig)
   {
      double legExtreme = (dir > 0) ? HighestHigh(g_breakBar, sig) : LowestLow(g_breakBar, sig);
      double signalEdge = (dir > 0) ? g_rates[sig].low : g_rates[sig].high;
      double depth      = PullbackPercent(dir, legExtreme, signalEdge);

      bool structureIntact = (dir > 0) ? (g_rates[sig].low > g_legAnchor)
                                       : (g_rates[sig].high < g_legAnchor);

      if(structureIntact && depth >= InpMinPullbackPct && depth <= InpMaxPullbackPct)
      {
         string pattern = "";
         int    signal  = ConfirmationPattern(sig, pattern);
         if(signal == dir && ClosesStrong(sig, dir))
         {
            pullbackEntry = true;
            reason = pattern + " at " + DoubleToString(depth, 0) + "% pullback";
         }
      }
   }

   if(!breakoutEntry && !pullbackEntry) return false;

   // --- Stop placement: behind the price action that produced the signal
   double buffer = g_avgRange * InpSLBufferFactor;
   if(dir > 0)
   {
      double swing = 0.0;
      double anchor = MathMin(g_rates[sig].low, g_rates[sig + 1].low);
      if(LastSwingLowBefore(sig, swing) && swing < anchor && (anchor - swing) <= g_avgRange * 2.0)
         anchor = swing;
      stopLoss = anchor - buffer;
   }
   else
   {
      double swing = 0.0;
      double anchor = MathMax(g_rates[sig].high, g_rates[sig + 1].high);
      if(LastSwingHighBefore(sig, swing) && swing > anchor && (swing - anchor) <= g_avgRange * 2.0)
         anchor = swing;
      stopLoss = anchor + buffer;
   }

   direction = dir;
   return true;
}

void TryEntry()
{
   int    direction = 0;
   double stopLoss  = 0.0;
   string reason    = "";
   if(!BuildSignal(direction, stopLoss, reason)) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = (direction > 0) ? ask : bid;

   double stopDistance = (direction > 0) ? (entry - stopLoss) : (stopLoss - entry);
   // The broker floor alone can leave a stop only a few cents wide, which is
   // inside the noise and gets hit within the entry bar. Hold it to a
   // fraction of recent range as well.
   double minDistance  = MathMax(StopsDistance(), g_avgRange * InpMinStopRangeFactor);
   if(stopDistance <= minDistance)
   {
      stopDistance = minDistance + PointSize();
      stopLoss     = (direction > 0) ? entry - stopDistance : entry + stopDistance;
   }
   if(stopDistance <= 0.0) return;

   ENUM_ORDER_TYPE type = (direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   g_sizeExplained = false;
   double lot = CalculateLot(stopDistance, type, entry);
   if(lot <= 0.0)
   {
      if(!g_sizeExplained)
         Print("Entry skipped: lot size resolved to zero (balance or margin too small).");
      return;
   }

   double takeProfit = 0.0;
   if(InpRewardR > 0.0)
      takeProfit = (direction > 0) ? entry + stopDistance * InpRewardR
                                   : entry - stopDistance * InpRewardR;

   stopLoss   = PriceNorm(stopLoss);
   takeProfit = (takeProfit > 0.0) ? PriceNorm(takeProfit) : 0.0;

   bool ok = (direction > 0)
             ? trade.Buy(lot, _Symbol, 0.0, stopLoss, takeProfit, InpComment)
             : trade.Sell(lot, _Symbol, 0.0, stopLoss, takeProfit, InpComment);

   if(!ok)
   {
      Print("Entry failed: retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return;
   }

   // The deal ticket is not the position ticket - resolve the live position.
   ulong ticket = FindPosition();
   if(ticket != 0)
   {
      StateSet(ticket, "R", stopDistance);
      StateSet(ticket, "PARTIAL", 0.0);
      StateSet(ticket, "BE", 0.0);
      StateSet(ticket, "OPENBAR", (double)(long)g_rates[0].time);
   }

   Print((direction > 0 ? "BUY " : "SELL "), _Symbol, " ", DoubleToString(lot, 2), " lots @ ",
         DoubleToString(entry, _Digits), "  SL ", DoubleToString(stopLoss, _Digits),
         "  1R ", DoubleToString(stopDistance, _Digits), "  | ", reason);
}

//======================================================================
// TRADE MANAGEMENT — every exit rule below is price action
//======================================================================
double CurrentR(const ulong ticket, const long type, const double openPrice)
{
   double riskDistance = StateGet(ticket, "R", 0.0);
   if(riskDistance <= 0.0) return 0.0;

   double price = (type == POSITION_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                  : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double move  = (type == POSITION_TYPE_BUY) ? (price - openPrice) : (openPrice - price);
   return move / riskDistance;
}

void ApplyStop(const ulong ticket, const long type, const double newStop, const double takeProfit)
{
   if(!PositionSelectByTicket(ticket)) return;

   double current = PositionGetDouble(POSITION_SL);
   double target  = PriceNorm(newStop);
   double minDist = StopsDistance();
   double price   = (type == POSITION_TYPE_BUY)
                    ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                    : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(type == POSITION_TYPE_BUY)
   {
      if(target > price - minDist) return;                 // broker distance rule
      if(current > 0.0 && target <= current) return;       // never loosen a stop
   }
   else
   {
      if(target < price + minDist) return;
      if(current > 0.0 && target >= current) return;
   }

   if(!trade.PositionModify(ticket, target, takeProfit))
      Print("Stop update failed: retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
}

void TakePartial(const ulong ticket, const double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = minLot;

   double slice = MathFloor((volume * InpPartialPercent / PCT) / step) * step;
   if(slice < minLot) return;
   if(volume - slice < minLot) return;   // the remainder must still be tradable

   if(trade.PositionClosePartial(ticket, slice))
   {
      StateSet(ticket, "PARTIAL", 1.0);
      PrintFormat("Partial close %.2f lots at %.2fR.", slice, InpPartialR);
   }
   else
   {
      Print("Partial close failed: retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
}

// Structural exit: the trade is closed when price action itself says the
// idea is done — the structure flips, or an opposing rejection prints.
bool ShouldExitOnPriceAction(const long type)
{
   int dir = (type == POSITION_TYPE_BUY) ? 1 : -1;

   if(InpExitOnStructure && g_bias != BIAS_NONE && (int)g_bias == -dir && g_breakBar >= 1)
      return true;

   if(InpExitOnReversalBar)
   {
      string pattern = "";
      int    signal  = ConfirmationPattern(1, pattern);
      if(signal == -dir && RangeAcceptable(1) && ClosesStrong(1, -dir))
         return true;
   }
   return false;
}

void ManagePosition(const bool barClosed)
{
   ulong ticket = FindPosition();
   if(ticket == 0) return;
   if(!PositionSelectByTicket(ticket)) return;

   long   type       = PositionGetInteger(POSITION_TYPE);
   double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
   double volume     = PositionGetDouble(POSITION_VOLUME);
   double takeProfit = PositionGetDouble(POSITION_TP);
   double risk       = StateGet(ticket, "R", 0.0);

   // Rebuild the 1R reference if the state was lost (fresh install, etc).
   if(risk <= 0.0)
   {
      double sl = PositionGetDouble(POSITION_SL);
      if(sl > 0.0)
      {
         risk = MathAbs(openPrice - sl);
         if(risk > 0.0) StateSet(ticket, "R", risk);
      }
   }

   double rNow = CurrentR(ticket, type, openPrice);

   // --- 1. Breakeven ------------------------------------------------
   if(InpBreakevenR > 0.0 && rNow >= InpBreakevenR && StateGet(ticket, "BE", 0.0) < 1.0)
   {
      double buffer = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double be = (type == POSITION_TYPE_BUY) ? openPrice + buffer : openPrice - buffer;
      ApplyStop(ticket, type, be, takeProfit);
      StateSet(ticket, "BE", 1.0);
   }

   // --- 2. Partial profit -------------------------------------------
   if(InpPartialR > 0.0 && InpPartialPercent > 0.0 && rNow >= InpPartialR &&
      StateGet(ticket, "PARTIAL", 0.0) < 1.0)
   {
      TakePartial(ticket, volume);
      if(!PositionSelectByTicket(ticket)) return;   // fully closed by the broker
      takeProfit = PositionGetDouble(POSITION_TP);
   }

   // --- 3. Trailing behind price action ------------------------------
   if(InpTrailMode != TRAIL_OFF && rNow >= InpTrailStartR && ArraySize(g_rates) > InpTrailCandles + 2)
   {
      double buffer = g_avgRange * InpSLBufferFactor;
      double target = 0.0;
      bool   found  = false;

      if(InpTrailMode == TRAIL_STRUCTURE)
      {
         double swing = 0.0;
         if(type == POSITION_TYPE_BUY)
         {
            if(g_swingLowCount > 0) { swing = g_swingLow[0].price; target = swing - buffer; found = true; }
         }
         else
         {
            if(g_swingHighCount > 0) { swing = g_swingHigh[0].price; target = swing + buffer; found = true; }
         }
      }
      else // TRAIL_CANDLE
      {
         int bars = MathMax(1, InpTrailCandles);
         if(type == POSITION_TYPE_BUY) { target = LowestLow(bars, 1) - buffer;  found = true; }
         else                          { target = HighestHigh(bars, 1) + buffer; found = true; }
      }

      if(found) ApplyStop(ticket, type, target, takeProfit);
   }

   if(!barClosed) return;

   // --- 4. Price action reversal exit --------------------------------
   if(ShouldExitOnPriceAction(type))
   {
      if(trade.PositionClose(ticket))
      {
         Print("Closed on opposing price action.");
         StateClear(ticket);
      }
      return;
   }

   // --- 5. Time stop: the move failed to develop ----------------------
   if(InpTimeStopBars > 0)
   {
      datetime openBar = (datetime)(long)StateGet(ticket, "OPENBAR", 0.0);
      if(openBar > 0)
      {
         int barsHeld = Bars(_Symbol, InpTimeframe, openBar, TimeCurrent()) - 1;
         if(barsHeld >= InpTimeStopBars && rNow < InpTimeStopMinR)
         {
            if(trade.PositionClose(ticket))
            {
               PrintFormat("Time stop: %d bars held at %.2fR.", barsHeld, rNow);
               StateClear(ticket);
            }
         }
      }
   }
}

//======================================================================
// ACCOUNT VIABILITY REPORT
//======================================================================
// The broker minimum lot sets a floor on how little can be risked. On Gold
// that floor is large relative to a small account, so state the real numbers
// at startup instead of letting the first stop reveal them.
void ReportAccountViability()
{
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   if(minLot <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0) return;

   double perUnit = minLot * tickValue / tickSize;   // account currency per 1.00 of price move
   double margin  = 0.0;
   // A failed margin query is not fatal here - this routine only reports - so
   // fall back to "unknown" rather than abandoning the whole check.
   bool haveMargin = OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, minLot,
                                     SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin);
   if(!haveMargin) margin = 0.0;

   Print("Sizing check | min lot ", DoubleToString(minLot, 2),
         " costs ", DoubleToString(perUnit, 2), " ", AccountInfoString(ACCOUNT_CURRENCY),
         " per 1.00 price move | margin ",
         (haveMargin ? DoubleToString(margin, 2) : "unavailable"),
         " | balance ", DoubleToString(balance, 2),
         (g_isCent ? " (" + DoubleToString(balance / g_centFactor, 2) + " real USD)" : ""));

   if(haveMargin && margin > 0.0 && balance < margin * 2.0)
      Print("WARNING: balance ", DoubleToString(balance, 2), " is below 2x the margin of one minimum lot (",
            DoubleToString(margin, 2), "). A single position can trigger a stop out.");

   // A structure stop runs roughly one average candle range plus the buffer,
   // so size the estimate off live range instead of a hard-coded number.
   double typicalStop = (g_avgRange > 0.0) ? g_avgRange * (1.0 + InpSLBufferFactor) : 0.0;
   if(typicalStop <= 0.0) return;

   double costPerTrade = perUnit * typicalStop;
   string realCost = g_isCent
                     ? " (" + DoubleToString(costPerTrade / g_centFactor, 2) + " real USD)"
                     : "";
   Print("Typical ", EnumToString(InpTimeframe), " stop is ", DoubleToString(typicalStop, _Digits),
         " wide = ", DoubleToString(costPerTrade, 2), " ", AccountInfoString(ACCOUNT_CURRENCY),
         realCost, " at the minimum lot.");

   if(!InpUseFixedLot && InpRiskPercent > 0.0)
   {
      double needed = costPerTrade / (InpRiskPercent / PCT);
      Print("Balance that makes that stop cost ", DoubleToString(InpRiskPercent, 2), "%: ",
            DoubleToString(needed, 2), " ", AccountInfoString(ACCOUNT_CURRENCY),
            (g_isCent ? " = " + DoubleToString(needed / g_centFactor, 2) + " real USD" : ""), ".");
   }

   if(balance > 0.0)
   {
      double realRisk = costPerTrade / balance * PCT;
      if(realRisk > InpRiskPercent * 2.0)
      {
         Print("WARNING: on a balance of ", DoubleToString(balance, 2),
               " the minimum lot puts ", DoubleToString(realRisk, 1),
               "% at risk per trade, not the ", DoubleToString(InpRiskPercent, 2), "% requested.");
         if(InpMaxRiskPercentCap <= 0.0)
            Print("WARNING: InpMaxRiskPercentCap is 0 (off), so every signal will be taken at that risk. ",
                  "At ", DoubleToString(realRisk, 1), "% per trade, ",
                  (int)MathCeil(PCT / MathMax(realRisk, 0.01)),
                  " consecutive losses empty the account. Set the cap above 0 to refuse these trades.");
      }
   }
}

//======================================================================
// LIFECYCLE
//======================================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   if(InpSwingStrength < 1)
   {
      Print("InpSwingStrength must be at least 1.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpStructureLookback < MIN_BARS_REQUIRED)
   {
      Print("InpStructureLookback must be at least ", MIN_BARS_REQUIRED, ".");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMinPullbackPct >= InpMaxPullbackPct)
   {
      Print("InpMinPullbackPct must be below InpMaxPullbackPct.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!InpTradeBreakouts && !InpTradePullbacks)
   {
      Print("Enable at least one entry model.");
      return INIT_PARAMETERS_INCORRECT;
   }

   string symbol = _Symbol;
   StringToUpper(symbol);
   if(StringFind(symbol, "XAU") < 0 && StringFind(symbol, "GOLD") < 0)
      Print("Warning: this EA is tuned for Gold; current symbol is ", _Symbol, ".");

   ResolveCentAccount();

   ResetDayIfNeeded();
   PruneState();

   if(!RefreshRates())
      Print("Waiting for enough history on ", _Symbol, " ", EnumToString(InpTimeframe), ".");
   else
      UpdateStructure();

   ReportAccountViability();   // after RefreshRates, so the range estimate is real

   g_lastBarTime = (datetime)SeriesInfoInteger(_Symbol, InpTimeframe, SERIES_LASTBAR_DATE);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(reason == REASON_REMOVE) PruneState();

   if(g_sizeSkips > 0)
   {
      Print("=== Sizing summary ===");
      Print(g_sizeSkips, " valid signals were skipped because the smallest tradable lot ",
            "exceeded the ", DoubleToString(InpMaxRiskPercentCap, 1), "% risk cap.");
      if(g_sizeNeedSum > 0.0)
      {
         double avgNeed = g_sizeNeedSum / (double)g_sizeSkips;
         Print("Balance required to take these at ", DoubleToString(InpRiskPercent, 2), "% risk: ",
               "average ", DoubleToString(avgNeed, 2),
               ", tightest stop ", DoubleToString(g_sizeNeedMin, 2),
               ", widest stop ", DoubleToString(g_sizeNeedMax, 2),
               " ", AccountInfoString(ACCOUNT_CURRENCY),
               (g_isCent ? " (average " + DoubleToString(avgNeed / g_centFactor, 2) + " real USD)" : ""), ".");
      }
      Print("Fund the account to at least the average figure, or raise InpRiskPercent ",
            "and InpMaxRiskPercentCap if you accept the larger drawdown.");
   }
}

void OnTick()
{
   ResetDayIfNeeded();

   if(!RefreshRates()) return;      // rates first, so a data gap never eats a bar

   bool barClosed = IsNewBar();
   if(barClosed) UpdateStructure();

   ManagePosition(barClosed);

   if(!barClosed) return;
   if(FindPosition() != 0) return;      // one price action idea at a time

   PruneState();

   if(!WithinSession())  return;
   if(!TradingAllowed()) return;
   if(!SpreadAcceptable()) return;

   TryEntry();
}
