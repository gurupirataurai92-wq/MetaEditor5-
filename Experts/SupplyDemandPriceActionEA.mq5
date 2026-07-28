//+------------------------------------------------------------------+
//|                                 SupplyDemandPriceActionEA.mq5     |
//|         Smart-Money-Concepts Supply & Demand engine (no indics)  |
//|                     Gold (XAUUSD) & EURUSD - M15 timeframe        |
//+------------------------------------------------------------------+
#property copyright "Quant Systems"
#property version   "2.00"
#property description "Institutional-style Supply & Demand / Smart-Money "
#property description "price-action EA for Gold (XAUUSD) and EURUSD on M15. "
#property description "Uses NO indicators - only raw candle structure. "
#property description "Stacks confluence: higher-timeframe (H4) bias + "
#property description "premium/discount, liquidity sweeps (stop hunts), "
#property description "break-of-structure / CHoCH, order blocks, fair-value "
#property description "gaps, and price-action confirmation. Trades only when "
#property description "a minimum confluence score is met, in-session. "
#property description "Manages risk with zone stops, partial TP, break-even, "
#property description "and structure trailing. No DLLs or external files."

#include <Trade\Trade.mqh>

//======================================================================
// SECTION 1 - INPUT PARAMETERS
//======================================================================
input group    "=== Symbols & Timeframes ==="
input string   GoldSymbol          = "XAUUSD";    // Gold symbol (exact broker name)
input string   ForexSymbol         = "EURUSD";    // Forex symbol (exact broker name)
input ENUM_TIMEFRAMES  EntryTF      = PERIOD_M15;  // Entry / execution timeframe
input ENUM_TIMEFRAMES  BiasTF       = PERIOD_H4;   // Higher-timeframe directional bias
input ENUM_TIMEFRAMES  StructureTF  = PERIOD_H1;   // Intermediate structure confirmation

input group    "=== Risk Management ==="
input double   RiskPercent         = 0.75;   // Risk per trade (% of balance)
input double   TP1_R               = 1.0;    // First target (R) - partial close here
input double   TP2_R               = 3.0;    // Final target (R) for the runner
input double   PartialClosePct     = 50.0;   // % of position closed at TP1
input double   MinLot              = 0.01;   // Minimum lot floor
input double   MaxLotCap           = 5.0;    // Maximum lot ceiling
input int      MaxOpenPerSymbol    = 1;      // Max positions per symbol
input int      MaxOpenTotal        = 2;      // Max positions across all symbols
input int      MagicBase           = 20260726;

input group    "=== Higher-Timeframe Bias (SMC) ==="
input bool     UseHTFBias          = true;   // Require H4 bias alignment
input bool     UsePremiumDiscount  = true;   // Buy only in discount, sell only in premium
input int      HTFSwingStrength    = 2;      // Swing definition on bias/structure TFs
input int      HTFLookback         = 120;    // Bars scanned on higher timeframes

input group    "=== HTF Order-Block Filter ==="
input bool     UseHTFZoneFilter    = true;   // Only trade M15 zones nested in an HTF zone
input ENUM_TIMEFRAMES  HTFZoneTF   = PERIOD_H1;  // Timeframe whose zones must contain the entry
input double   HTFZonePadPct       = 0.25;   // Tolerance (% of HTF zone height) around it
input bool     HTFZoneHardFilter   = true;   // true = required; false = confluence bonus only

input group    "=== Zone / Order Block Detection ==="
input int      LookbackBars        = 400;    // M15 bars scanned when mapping zones
input int      MaxBaseCandles      = 3;      // Max consolidation candles in a base
input double   BasingBodyFactor    = 0.50;   // Body <= factor*range => base candle
input double   ImpulseBodyFactor   = 0.60;   // Body >= factor*range => impulse candle
input double   ImpulseLegFactor    = 1.40;   // Leg-out range >= factor * avg base range
input double   ZoneEntryBufferPct  = 0.15;   // Tolerance (% zone height) around proximal
input int      MaxZoneAgeBars      = 250;    // Ignore zones older than this
input int      MaxZoneTouches      = 1;      // Only fresh/near-fresh zones (retests allowed)
input bool     RefineToOrderBlock  = true;   // Tighten zone to the origin candle (tighter SL)

input group    "=== Confluence & Confirmation ==="
input int      MinConfluenceScore  = 6;      // Minimum score required to trade (see docs)
input bool     RequireLiquiditySweep = true; // Require a stop-hunt before the zone tap
input int      SweepLookback       = 20;     // Bars scanned for the swept liquidity level
input bool     RequireBOS          = true;   // Require break-of-structure confirmation
input int      SwingStrength       = 2;      // M15 swing definition
input bool     RequireFVG          = false;  // Require a fair-value-gap in the impulse
input bool     RequirePA           = true;   // Require a PA confirmation candle
input double   PinWickFactor       = 1.8;    // Pin-bar: rejection wick >= factor * body

input group    "=== Volatility Filter (no indicators) ==="
input bool     UseVolatilityFilter = true;   // Skip dead / abnormal volatility
input int      RangeSampleBars     = 20;     // Bars used to gauge average candle range
input double   MinRangeFactor      = 0.40;   // Skip if last range < factor * average
input double   MaxRangeFactor      = 3.50;   // Skip if last range > factor * average (news spike)

input group    "=== Trade Management ==="
input double   SL_BufferPoints     = 0.0;    // Extra SL beyond distal (points, 0 = auto)
input bool     UseBreakEven        = true;   // Move SL to BE after TP1 / trigger
input double   BreakEvenTriggerR   = 1.0;    // R profit that arms break-even
input bool     UseStructureTrail   = true;   // Trail SL behind swing points
input double   TrailStartR         = 1.2;    // Begin trailing after this R
input int      TrailSwingStrength  = 2;      // Swing strength used for the trailing stop

input group    "=== Sessions (GMT) ==="
input bool     UseSessionFilter    = true;   // Trade only inside the window below
input int      SessionStartHourGMT = 7;      // London open ~07:00 GMT
input int      SessionEndHourGMT   = 20;     // NY afternoon ~20:00 GMT
input bool     TradeMonday         = true;
input bool     TradeFriday         = true;   // (late-Friday still gated by session hours)

input group    "=== Safety / Circuit Breakers ==="
input int      MaxTradesPerDay     = 6;      // Per-symbol daily trade cap (0 = off)
input int      ConsecLossCooldown  = 3;      // Pause a symbol after N losses in a row (0 = off)
input int      CooldownBars        = 12;     // Bars to pause after the loss streak
input double   DailyLossLimitPct   = 4.0;    // Halt all new trades after this daily loss %
input double   MinAccountUSD       = 5.0;    // Do not trade below this equity
input double   MaxSpreadPoints     = 0.0;    // Max spread in points (0 = auto)

//======================================================================
// SECTION 2 - NAMED CONSTANTS
//======================================================================
#define ZONE_DEMAND        1
#define ZONE_SUPPLY       -1
#define DIR_BUY            1
#define DIR_SELL          -1
#define DIR_NONE           0
#define TREND_UP           1
#define TREND_DOWN        -1
#define TREND_RANGE        0
#define MAX_ZONES          64
#define MIN_RATES_BARS     60
#define SPREAD_ZONE_FRAC   0.40

//======================================================================
// SECTION 3 - DATA STRUCTURES
//======================================================================
struct Zone
{
   int      type;        // ZONE_DEMAND / ZONE_SUPPLY
   double   proximal;    // near edge (price touches first on return)
   double   distal;      // far edge (stop beyond this)
   datetime formed;      // base formation time
   int      touches;     // retests since formation
   int      impulseIdx;  // index of the leg-out candle
   double   strength;    // leg-out range / avg base range
   bool     hasFVG;      // fair-value gap in the impulse
   bool     valid;
};

struct Setup
{
   int    dir;
   Zone   zone;
   int    score;
   double entry, sl, tp1, tp2, risk;
};

struct SymbolState
{
   string    name;
   bool      ready;
   long      magic;
   double    point;
   int       digits;
   double    volMin, volMax, volStep;
   datetime  lastBarTime;
   double    lastTradedProx;
   int       tradesToday;
   int       consecLosses;
   datetime  cooldownUntilBar;
   Zone      zones[MAX_ZONES];
   int       zoneCount;
};

//======================================================================
// SECTION 4 - GLOBALS
//======================================================================
CTrade        Trade;
SymbolState   Symbols[2];
int           SymbolTotal = 0;
datetime      CurrentDay  = 0;
double        DayStartBalance = 0.0;

ulong         g_partialDone[];   // tickets that already took TP1
ulong         g_beDone[];        // tickets already moved to break-even

//======================================================================
// SECTION 5 - INITIALISATION
//======================================================================
int OnInit()
{
   SymbolTotal = 0;
   if(!SetupSymbol(GoldSymbol,  0)) Print("WARN: could not initialise ", GoldSymbol);
   if(!SetupSymbol(ForexSymbol, 1)) Print("WARN: could not initialise ", ForexSymbol);

   if(SymbolTotal == 0)
   {
      Print("ERROR: no tradable symbols. Check GoldSymbol / ForexSymbol names.");
      return(INIT_FAILED);
   }

   Trade.SetDeviationInPoints(15);
   Trade.SetAsyncMode(false);

   CurrentDay      = DayStart(TimeCurrent());
   DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   ArrayResize(g_partialDone, 0);
   ArrayResize(g_beDone, 0);

   PrintFormat("SD-SMC EA v2.00 | symbols=%d | entry=%s bias=%s | risk=%.2f%% | minScore=%d",
               SymbolTotal, EnumToString(EntryTF), EnumToString(BiasTF),
               RiskPercent, MinConfluenceScore);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
bool SetupSymbol(const string sym, const long magicOffset)
{
   if(sym == "") return(false);
   if(!SymbolSelect(sym, true)) { Print("Not in Market Watch: ", sym); return(false); }

   SymbolState st;
   st.name    = sym;
   st.magic   = MagicBase + magicOffset;
   st.point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   st.digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   st.volMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   st.volMax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   st.volStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(st.volStep <= 0.0) st.volStep = 0.01;
   st.lastBarTime      = 0;
   st.lastTradedProx   = 0.0;
   st.tradesToday      = 0;
   st.consecLosses     = 0;
   st.cooldownUntilBar = 0;
   st.zoneCount        = 0;
   st.ready            = true;

   Symbols[SymbolTotal] = st;
   SymbolTotal++;
   return(true);
}

//======================================================================
// SECTION 6 - MAIN EVENT LOOP
//======================================================================
void OnTick()
{
   RollDailyCounters();

   for(int s = 0; s < SymbolTotal; s++)
   {
      if(!Symbols[s].ready) continue;
      ManageOpenPositions(s);
      if(IsNewBar(s))
         ProcessSymbol(s);
   }
}

//+------------------------------------------------------------------+
void ProcessSymbol(const int s)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbols[s].name, EntryTF, 0, LookbackBars + 5, rates);
   if(copied < MIN_RATES_BARS) return;

   // OBSERVE + ORIENT
   BuildZones(s, rates, copied);

   // safety gates
   if(!TradingAllowed(s, rates)) return;
   if(CountPositions(s) >= MaxOpenPerSymbol) return;
   if(TotalPositions() >= MaxOpenTotal) return;

   // DECIDE
   Setup setup;
   if(!FindSetup(s, rates, copied, setup)) return;

   // ACT
   ExecuteTrade(s, setup);
}

//======================================================================
// SECTION 7 - OBSERVE/ORIENT: ZONE + ORDER BLOCK CONSTRUCTION
//======================================================================
void BuildZones(const int s, const MqlRates &rates[], const int n)
{
   Symbols[s].zoneCount = DetectZones(rates, n, Symbols[s].zones, MAX_ZONES, true);
}

//+------------------------------------------------------------------+
//| Generic zone/order-block detector - reusable on any timeframe.    |
//| enforceFresh=true applies the touch/age freshness filters (M15    |
//| entry map); false keeps every structural zone (HTF context map).  |
//+------------------------------------------------------------------+
int DetectZones(const MqlRates &rates[], const int n, Zone &dest[],
                const int maxZones, const bool enforceFresh)
{
   int count = 0;
   int scan  = MathMin(n - 2, LookbackBars);

   for(int i = 2; i < scan && count < maxZones; i++)
   {
      if(!IsImpulse(rates[i])) continue;
      bool bullLeg = (rates[i].close > rates[i].open);

      int    baseStart = i + 1;
      int    baseCount = 0;
      double baseHigh = -DBL_MAX, baseLow = DBL_MAX, sumRange = 0.0;

      for(int b = baseStart; b < baseStart + MaxBaseCandles && b < n; b++)
      {
         if(!IsBase(rates[b])) break;
         baseHigh = MathMax(baseHigh, rates[b].high);
         baseLow  = MathMin(baseLow,  rates[b].low);
         sumRange += (rates[b].high - rates[b].low);
         baseCount++;
      }
      if(baseCount == 0) continue;

      double avgBaseRange = sumRange / baseCount;
      double legRange     = rates[i].high - rates[i].low;
      if(avgBaseRange <= 0.0) continue;
      if(legRange < ImpulseLegFactor * avgBaseRange) continue;
      if(bullLeg  && rates[i].close <= baseHigh) continue;
      if(!bullLeg && rates[i].close >= baseLow)  continue;

      Zone z;
      z.formed     = rates[baseStart].time;
      z.impulseIdx = i;
      z.strength   = legRange / avgBaseRange;
      z.valid      = true;
      z.hasFVG     = false;

      if(bullLeg)
      {
         z.type     = ZONE_DEMAND;
         z.proximal = baseHigh;
         z.distal   = baseLow;
      }
      else
      {
         z.type     = ZONE_SUPPLY;
         z.proximal = baseLow;
         z.distal   = baseHigh;
      }

      // Order-block refinement: shrink the zone to the origin candle.
      if(RefineToOrderBlock && baseCount >= 1)
      {
         int obIdx = baseStart + baseCount - 1;   // oldest base candle = origin
         if(z.type == ZONE_DEMAND)
         {
            z.proximal = MathMax(rates[obIdx].open, rates[obIdx].close);
            z.distal   = rates[obIdx].low;
         }
         else
         {
            z.proximal = MathMin(rates[obIdx].open, rates[obIdx].close);
            z.distal   = rates[obIdx].high;
         }
      }

      if(i > MaxZoneAgeBars) continue;

      z.hasFVG  = HasFVG(rates, i, z.type, n);
      z.touches = CountTouches(rates, i, z);

      if(enforceFresh && z.touches > MaxZoneTouches) continue;
      if(ZoneArrayOverlaps(dest, count, z)) continue;

      dest[count] = z;
      count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
bool IsBase(const MqlRates &r)
{
   double range = r.high - r.low;
   if(range <= 0.0) return(false);
   return(MathAbs(r.close - r.open) <= BasingBodyFactor * range);
}

//+------------------------------------------------------------------+
bool IsImpulse(const MqlRates &r)
{
   double range = r.high - r.low;
   if(range <= 0.0) return(false);
   return(MathAbs(r.close - r.open) >= ImpulseBodyFactor * range);
}

//+------------------------------------------------------------------+
//| Fair-value gap: gap between candle (idx+1) and (idx-1) around the |
//| impulse at idx. Series order: idx-1 newer, idx+1 older.           |
//+------------------------------------------------------------------+
bool HasFVG(const MqlRates &rates[], const int idx, const int zoneType, const int n)
{
   if(idx - 1 < 0 || idx + 1 >= n) return(false);
   if(zoneType == ZONE_DEMAND)      // bullish gap: low of newer > high of older
      return(rates[idx-1].low > rates[idx+1].high);
   else                             // bearish gap: high of newer < low of older
      return(rates[idx-1].high < rates[idx+1].low);
}

//+------------------------------------------------------------------+
int CountTouches(const MqlRates &rates[], const int idxFrom, const Zone &z)
{
   int touches = 0;
   double lo = MathMin(z.proximal, z.distal);
   double hi = MathMax(z.proximal, z.distal);
   for(int k = idxFrom - 1; k >= 1; k--)
   {
      if(z.type == ZONE_DEMAND)
      { if(rates[k].low <= hi && rates[k].low >= lo) touches++; }
      else
      { if(rates[k].high >= lo && rates[k].high <= hi) touches++; }
   }
   return(touches);
}

//+------------------------------------------------------------------+
bool ZoneArrayOverlaps(const Zone &arr[], const int count, const Zone &z)
{
   for(int i = 0; i < count; i++)
   {
      if(arr[i].type != z.type) continue;
      double aLo = MathMin(z.proximal, z.distal), aHi = MathMax(z.proximal, z.distal);
      double bLo = MathMin(arr[i].proximal, arr[i].distal), bHi = MathMax(arr[i].proximal, arr[i].distal);
      if(aHi >= bLo && bHi >= aLo) return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| HTF order-block filter: is `price` sitting inside a same-type     |
//| zone on the higher timeframe? Buys must nest in an HTF demand     |
//| zone, sells in an HTF supply zone.                                |
//+------------------------------------------------------------------+
bool InHTFZone(const string sym, const int dir, const double price)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int c = CopyRates(sym, HTFZoneTF, 0, HTFLookback + 5, r);
   if(c < 20) return(false);

   Zone htf[];
   ArrayResize(htf, MAX_ZONES);
   int hc = DetectZones(r, c, htf, MAX_ZONES, false);

   int want = (dir == DIR_BUY) ? ZONE_DEMAND : ZONE_SUPPLY;
   for(int i = 0; i < hc; i++)
   {
      if(htf[i].type != want) continue;
      double lo = MathMin(htf[i].proximal, htf[i].distal);
      double hi = MathMax(htf[i].proximal, htf[i].distal);
      double pad = (hi - lo) * HTFZonePadPct;
      if(price >= lo - pad && price <= hi + pad) return(true);
   }
   return(false);
}

//======================================================================
// SECTION 8 - SWING / STRUCTURE PRIMITIVES (generic)
//======================================================================
bool IsSwingHigh(const MqlRates &rates[], const int i, const int strength, const int n)
{
   if(i - strength < 0 || i + strength >= n) return(false);
   for(int k = 1; k <= strength; k++)
   {
      if(rates[i].high <= rates[i-k].high) return(false);
      if(rates[i].high <= rates[i+k].high) return(false);
   }
   return(true);
}

//+------------------------------------------------------------------+
bool IsSwingLow(const MqlRates &rates[], const int i, const int strength, const int n)
{
   if(i - strength < 0 || i + strength >= n) return(false);
   for(int k = 1; k <= strength; k++)
   {
      if(rates[i].low >= rates[i-k].low) return(false);
      if(rates[i].low >= rates[i+k].low) return(false);
   }
   return(true);
}

//+------------------------------------------------------------------+
//| Most-recent swing value of the requested kind. Returns index or -1|
//+------------------------------------------------------------------+
int RecentSwing(const MqlRates &rates[], const int n, const bool wantHigh,
                const int strength, const int startIdx, double &outValue)
{
   int limit = MathMin(n - strength - 1, LookbackBars);
   for(int i = MathMax(startIdx, strength + 1); i < limit; i++)
   {
      if(wantHigh && IsSwingHigh(rates, i, strength, n)) { outValue = rates[i].high; return(i); }
      if(!wantHigh && IsSwingLow(rates, i, strength, n)) { outValue = rates[i].low;  return(i); }
   }
   outValue = 0.0;
   return(-1);
}

//+------------------------------------------------------------------+
//| Structure of any timeframe's series: UP / DOWN / RANGE           |
//+------------------------------------------------------------------+
int SeriesStructure(const MqlRates &rates[], const int n, const int strength)
{
   double h[2], l[2];
   int hc = 0, lc = 0;
   int limit = MathMin(n - strength - 1, LookbackBars);
   for(int i = strength + 1; i < limit && (hc < 2 || lc < 2); i++)
   {
      if(hc < 2 && IsSwingHigh(rates, i, strength, n)) { h[hc++] = rates[i].high; }
      if(lc < 2 && IsSwingLow(rates, i, strength, n))  { l[lc++] = rates[i].low;  }
   }
   if(hc < 2 || lc < 2) return(TREND_RANGE);
   if(h[0] > h[1] && l[0] > l[1]) return(TREND_UP);
   if(h[0] < h[1] && l[0] < l[1]) return(TREND_DOWN);
   return(TREND_RANGE);
}

//======================================================================
// SECTION 9 - HIGHER-TIMEFRAME BIAS + PREMIUM/DISCOUNT
//======================================================================
int HTFBias(const string sym)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int c = CopyRates(sym, BiasTF, 0, HTFLookback + 5, r);
   if(c < 20) return(TREND_RANGE);
   return(SeriesStructure(r, c, HTFSwingStrength));
}

//+------------------------------------------------------------------+
int StructureBias(const string sym)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int c = CopyRates(sym, StructureTF, 0, HTFLookback + 5, r);
   if(c < 20) return(TREND_RANGE);
   return(SeriesStructure(r, c, HTFSwingStrength));
}

//+------------------------------------------------------------------+
//| Is current price in discount (lower half) of the HTF dealing range|
//+------------------------------------------------------------------+
bool InDiscount(const string sym, const double price)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int c = CopyRates(sym, BiasTF, 0, HTFLookback, r);
   if(c < 10) return(true);
   double hi = -DBL_MAX, lo = DBL_MAX;
   for(int i = 1; i < c; i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
   if(hi <= lo) return(true);
   double mid = (hi + lo) * 0.5;
   return(price < mid);
}

//======================================================================
// SECTION 10 - LIQUIDITY SWEEP + BREAK OF STRUCTURE
//======================================================================
//| Bullish sweep: within SweepLookback a bar pierced a prior swing   |
//| low then closed back above it (stop-hunt below support).          |
bool LiquiditySwept(const MqlRates &rates[], const int n, const int dir)
{
   double swing;
   if(dir == DIR_BUY)
   {
      int idx = RecentSwing(rates, n, false, SwingStrength, SweepLookback, swing);
      if(idx < 0) return(false);
      for(int k = 1; k <= SweepLookback && k < n; k++)
         if(rates[k].low < swing && rates[k].close > swing) return(true);
   }
   else
   {
      int idx = RecentSwing(rates, n, true, SwingStrength, SweepLookback, swing);
      if(idx < 0) return(false);
      for(int k = 1; k <= SweepLookback && k < n; k++)
         if(rates[k].high > swing && rates[k].close < swing) return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Break of structure on the last closed bar: close beyond the most |
//| recent minor swing in the trade direction (momentum shift).      |
bool BreakOfStructure(const MqlRates &rates[], const int n, const int dir)
{
   double swing;
   if(dir == DIR_BUY)
   {
      int idx = RecentSwing(rates, n, true, SwingStrength, 2, swing);
      if(idx < 0) return(false);
      return(rates[1].close > swing);
   }
   else
   {
      int idx = RecentSwing(rates, n, false, SwingStrength, 2, swing);
      if(idx < 0) return(false);
      return(rates[1].close < swing);
   }
}

//======================================================================
// SECTION 11 - DECIDE: CONFLUENCE-SCORED SETUP
//======================================================================
bool FindSetup(const int s, const MqlRates &rates[], const int n, Setup &out)
{
   int htf   = UseHTFBias ? HTFBias(Symbols[s].name) : TREND_RANGE;
   int mtf   = StructureBias(Symbols[s].name);
   int m15   = SeriesStructure(rates, n, SwingStrength);

   int    sig     = 1;                       // last closed bar
   double sigHigh = rates[sig].high;
   double sigLow  = rates[sig].low;
   double bid     = SymbolInfoDouble(Symbols[s].name, SYMBOL_BID);

   int  bestScore = -1;
   bool found     = false;

   for(int z = 0; z < Symbols[s].zoneCount; z++)
   {
      Zone zone = Symbols[s].zones[z];
      if(!zone.valid) continue;

      double zoneHeight = MathAbs(zone.proximal - zone.distal);
      if(zoneHeight <= 0.0) continue;
      double buffer = zoneHeight * ZoneEntryBufferPct;
      int    dir    = (zone.type == ZONE_DEMAND) ? DIR_BUY : DIR_SELL;

      // --- price must actually be tapping the zone on the signal bar ---
      bool tapped, held;
      if(dir == DIR_BUY)
      {
         tapped = (sigLow  <= zone.proximal + buffer) && (sigLow  >= zone.distal - buffer);
         held   = (rates[sig].close > zone.distal);
      }
      else
      {
         tapped = (sigHigh >= zone.proximal - buffer) && (sigHigh <= zone.distal + buffer);
         held   = (rates[sig].close < zone.distal);
      }
      if(!tapped || !held) continue;

      if(MathAbs(zone.proximal - Symbols[s].lastTradedProx) < buffer) continue; // already fired

      // --- hard filters ---
      if(UseHTFBias && htf != TREND_RANGE)
      {
         if(dir == DIR_BUY  && htf == TREND_DOWN) continue;
         if(dir == DIR_SELL && htf == TREND_UP)   continue;
      }
      if(UsePremiumDiscount)
      {
         bool disc = InDiscount(Symbols[s].name, bid);
         if(dir == DIR_BUY  && !disc) continue;   // only buy in discount
         if(dir == DIR_SELL &&  disc) continue;   // only sell in premium
      }

      // HTF order-block nesting: the M15 zone must live inside an HTF zone.
      bool inHTFZone = false;
      if(UseHTFZoneFilter)
      {
         inHTFZone = InHTFZone(Symbols[s].name, dir, zone.proximal);
         if(HTFZoneHardFilter && !inHTFZone) continue;
      }

      bool swept = LiquiditySwept(rates, n, dir);
      if(RequireLiquiditySweep && !swept) continue;

      bool bos = BreakOfStructure(rates, n, dir);
      if(RequireBOS && !bos) continue;

      if(RequireFVG && !zone.hasFVG) continue;

      bool pa = (dir == DIR_BUY) ? IsBullishConfirm(rates, sig, n)
                                 : IsBearishConfirm(rates, sig, n);
      if(RequirePA && !pa) continue;

      // --- confluence score ---
      int score = 0;
      if(htf != TREND_RANGE &&
         ((dir == DIR_BUY && htf == TREND_UP) || (dir == DIR_SELL && htf == TREND_DOWN))) score += 2;
      if((dir == DIR_BUY && mtf == TREND_UP) || (dir == DIR_SELL && mtf == TREND_DOWN)) score += 1;
      if((dir == DIR_BUY && m15 == TREND_UP) || (dir == DIR_SELL && m15 == TREND_DOWN)) score += 1;
      if(swept)              score += 2;
      if(bos)                score += 2;
      if(zone.hasFVG)        score += 1;
      if(pa)                 score += 1;
      if(zone.touches == 0)  score += 1;                 // pristine zone
      if(zone.strength >= 2.0) score += 1;               // powerful departure
      if(inHTFZone)          score += 2;                 // nested inside an HTF zone

      if(score < MinConfluenceScore) continue;

      if(score > bestScore)
      {
         bestScore = score;
         out.dir   = dir;
         out.zone  = zone;
         out.score = score;
         found     = true;
      }
   }
   return(found);
}

//======================================================================
// SECTION 12 - PRICE ACTION CONFIRMATION
//======================================================================
bool IsBullishConfirm(const MqlRates &rates[], const int i, const int n)
{
   return( IsBullishEngulfing(rates, i, n) || IsHammer(rates[i]) || IsStrongBullClose(rates[i]) );
}
bool IsBearishConfirm(const MqlRates &rates[], const int i, const int n)
{
   return( IsBearishEngulfing(rates, i, n) || IsShootingStar(rates[i]) || IsStrongBearClose(rates[i]) );
}
//+------------------------------------------------------------------+
bool IsBullishEngulfing(const MqlRates &rates[], const int i, const int n)
{
   if(i + 1 >= n) return(false);
   return( rates[i+1].close < rates[i+1].open &&
           rates[i].close   > rates[i].open   &&
           rates[i].close >= rates[i+1].open  &&
           rates[i].open  <= rates[i+1].close );
}
bool IsBearishEngulfing(const MqlRates &rates[], const int i, const int n)
{
   if(i + 1 >= n) return(false);
   return( rates[i+1].close > rates[i+1].open &&
           rates[i].close   < rates[i].open   &&
           rates[i].open  >= rates[i+1].close &&
           rates[i].close <= rates[i+1].open );
}
bool IsHammer(const MqlRates &r)
{
   double range = r.high - r.low;
   if(range <= 0.0) return(false);
   double lower = MathMin(r.open, r.close) - r.low;
   double upper = r.high - MathMax(r.open, r.close);
   double body  = MathAbs(r.close - r.open);
   if(body < range * 0.05) body = range * 0.05;
   return(lower >= PinWickFactor * body && lower > upper);
}
bool IsShootingStar(const MqlRates &r)
{
   double range = r.high - r.low;
   if(range <= 0.0) return(false);
   double upper = r.high - MathMax(r.open, r.close);
   double lower = MathMin(r.open, r.close) - r.low;
   double body  = MathAbs(r.close - r.open);
   if(body < range * 0.05) body = range * 0.05;
   return(upper >= PinWickFactor * body && upper > lower);
}
bool IsStrongBullClose(const MqlRates &r)
{
   double range = r.high - r.low;
   if(range <= 0.0) return(false);
   return( r.close > r.open && (r.close - r.low) >= 0.66 * range );
}
bool IsStrongBearClose(const MqlRates &r)
{
   double range = r.high - r.low;
   if(range <= 0.0) return(false);
   return( r.close < r.open && (r.high - r.close) >= 0.66 * range );
}

//======================================================================
// SECTION 13 - ACT: EXECUTION
//======================================================================
void ExecuteTrade(const int s, Setup &setup)
{
   string sym = Symbols[s].name;
   double pt  = Symbols[s].point;

   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;

   double zoneHeight = MathAbs(setup.zone.proximal - setup.zone.distal);
   double buffer = (SL_BufferPoints > 0.0) ? SL_BufferPoints * pt
                                           : MathMax(zoneHeight * 0.10, 5 * pt);

   if(setup.dir == DIR_BUY)
   {
      setup.entry = ask;
      setup.sl    = setup.zone.distal - buffer;
      setup.risk  = setup.entry - setup.sl;
      if(setup.risk <= 0.0) return;
      setup.tp1   = setup.entry + TP1_R * setup.risk;
      setup.tp2   = setup.entry + TP2_R * setup.risk;
   }
   else
   {
      setup.entry = bid;
      setup.sl    = setup.zone.distal + buffer;
      setup.risk  = setup.sl - setup.entry;
      if(setup.risk <= 0.0) return;
      setup.tp1   = setup.entry - TP1_R * setup.risk;
      setup.tp2   = setup.entry - TP2_R * setup.risk;
   }

   // spread gate
   double spread = (ask - bid) / pt;
   double cap = (MaxSpreadPoints > 0.0) ? MaxSpreadPoints
                                        : MathMax((setup.risk / pt) * SPREAD_ZONE_FRAC, 15.0);
   if(spread > cap) { PrintFormat("%s spread %.1f>cap %.1f skip", sym, spread, cap); return; }

   double lots = CalcLots(s, setup.risk);
   if(lots <= 0.0) return;

   double sl  = NormalizeDouble(setup.sl,  Symbols[s].digits);
   double tp2 = NormalizeDouble(setup.tp2, Symbols[s].digits);   // final target on the order

   Trade.SetExpertMagicNumber(Symbols[s].magic);
   Trade.SetTypeFillingBySymbol(sym);

   string tag = StringFormat("SMC_%s_%d", (setup.zone.type==ZONE_DEMAND?"D":"S"), setup.score);
   bool ok = (setup.dir == DIR_BUY) ? Trade.Buy(lots, sym, ask, sl, tp2, tag)
                                     : Trade.Sell(lots, sym, bid, sl, tp2, tag);

   if(ok)
   {
      Symbols[s].lastTradedProx = setup.zone.proximal;
      PrintFormat("%s %s @%.*f lots=%.2f SL=%.*f TP=%.*f | score=%d strength=%.1f FVG=%s touches=%d",
                  sym, (setup.dir==DIR_BUY?"BUY":"SELL"), Symbols[s].digits, setup.entry, lots,
                  Symbols[s].digits, sl, Symbols[s].digits, tp2,
                  setup.score, setup.zone.strength, (setup.zone.hasFVG?"Y":"N"), setup.zone.touches);
   }
   else
      PrintFormat("%s order failed: %d %s", sym, Trade.ResultRetcode(), Trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
double CalcLots(const int s, const double riskPrice)
{
   string sym = Symbols[s].name;
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   if(riskMoney <= 0.0 || riskPrice <= 0.0) return(0.0);

   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return(0.0);

   double lossPerLot = (riskPrice / tickSize) * tickValue;
   if(lossPerLot <= 0.0) return(0.0);

   double lots = riskMoney / lossPerLot;
   double lo = MathMax(Symbols[s].volMin, MinLot);
   double hi = MathMin(Symbols[s].volMax, MaxLotCap);
   lots = MathMax(lo, MathMin(hi, lots));
   lots = MathFloor(lots / Symbols[s].volStep) * Symbols[s].volStep;
   if(lots < lo) lots = lo;

   double margin = 0.0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, sym, lots, SymbolInfoDouble(sym, SYMBOL_ASK), margin))
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin && margin > 0.0)
      {
         double scaled = lots * (freeMargin / margin) * 0.95;
         scaled = MathFloor(scaled / Symbols[s].volStep) * Symbols[s].volStep;
         if(scaled < lo) return(0.0);
         lots = scaled;
      }
   }
   return(lots);
}

//======================================================================
// SECTION 14 - TRADE MANAGEMENT
//======================================================================
void ManageOpenPositions(const int s)
{
   string sym = Symbols[s].name;
   double pt  = Symbols[s].point;

   MqlRates tr[];
   ArraySetAsSeries(tr, true);
   int tc = CopyRates(sym, EntryTF, 0, 80, tr);   // for structure trailing

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Symbols[s].magic) continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double bid  = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask  = SymbolInfoDouble(sym, SYMBOL_ASK);

      double risk = MathAbs(open - sl);
      if(risk <= 0.0) continue;

      double curPrice = (type == POSITION_TYPE_BUY) ? bid : ask;
      double profitR  = (type == POSITION_TYPE_BUY) ? (bid - open) / risk : (open - ask) / risk;

      // --- partial take-profit at TP1 (once) ---
      if(PartialClosePct > 0.0 && profitR >= TP1_R && !InSet(g_partialDone, ticket))
      {
         double closeVol = NormalizeVolume(s, vol * PartialClosePct / 100.0);
         if(closeVol >= Symbols[s].volMin && closeVol < vol)
         {
            if(Trade.PositionClosePartial(ticket, closeVol))
               AddToSet(g_partialDone, ticket);
         }
      }

      double newSL = sl;

      // --- break-even ---
      if(UseBreakEven && profitR >= BreakEvenTriggerR && !InSet(g_beDone, ticket))
      {
         double be = (type == POSITION_TYPE_BUY) ? open + 2 * pt : open - 2 * pt;
         if((type == POSITION_TYPE_BUY && be > newSL) ||
            (type == POSITION_TYPE_SELL && (be < newSL || sl == 0.0)))
         {
            newSL = be;
            AddToSet(g_beDone, ticket);
         }
      }

      // --- structure trailing ---
      if(UseStructureTrail && profitR >= TrailStartR && tc > 20)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double sw;
            int idx = RecentSwing(tr, tc, false, TrailSwingStrength, 2, sw);
            if(idx > 0 && sw - 3 * pt > newSL && sw - 3 * pt < bid) newSL = sw - 3 * pt;
         }
         else
         {
            double sw;
            int idx = RecentSwing(tr, tc, true, TrailSwingStrength, 2, sw);
            if(idx > 0 && (sw + 3 * pt < newSL || sl == 0.0) && sw + 3 * pt > ask) newSL = sw + 3 * pt;
         }
      }

      if(newSL != sl && newSL > 0.0)
      {
         bool valid = (type == POSITION_TYPE_BUY) ? (newSL < bid) : (newSL > ask);
         if(valid) Trade.PositionModify(ticket, NormalizeDouble(newSL, Symbols[s].digits), tp);
      }
   }
}

//+------------------------------------------------------------------+
double NormalizeVolume(const int s, const double v)
{
   double vv = MathFloor(v / Symbols[s].volStep) * Symbols[s].volStep;
   if(vv < Symbols[s].volMin) vv = 0.0;
   return(vv);
}

//======================================================================
// SECTION 15 - SAFETY / SESSION GATES
//======================================================================
bool TradingAllowed(const int s, const MqlRates &rates[])
{
   if(AccountInfoDouble(ACCOUNT_EQUITY) < MinAccountUSD) return(false);

   long tradeMode = SymbolInfoInteger(Symbols[s].name, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED) return(false);

   if(DailyLossLimitPct > 0.0 && DayStartBalance > 0.0)
   {
      double dd = (DayStartBalance - AccountInfoDouble(ACCOUNT_EQUITY)) / DayStartBalance * 100.0;
      if(dd >= DailyLossLimitPct) return(false);
   }

   if(MaxTradesPerDay > 0 && Symbols[s].tradesToday >= MaxTradesPerDay) return(false);

   // consecutive-loss cooldown
   if(ConsecLossCooldown > 0 && Symbols[s].consecLosses >= ConsecLossCooldown)
   {
      if(rates[0].time < Symbols[s].cooldownUntilBar) return(false);
      Symbols[s].consecLosses = 0;   // cooldown elapsed
   }

   if(!InSession()) return(false);
   if(!VolatilityOK(rates)) return(false);
   return(true);
}

//+------------------------------------------------------------------+
bool InSession()
{
   if(!UseSessionFilter) return(true);
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return(false);    // weekend
   if(!TradeMonday && dt.day_of_week == 1) return(false);
   if(!TradeFriday && dt.day_of_week == 5) return(false);

   int h = dt.hour;
   if(SessionStartHourGMT <= SessionEndHourGMT)
      return(h >= SessionStartHourGMT && h < SessionEndHourGMT);
   return(h >= SessionStartHourGMT || h < SessionEndHourGMT);       // wrap past midnight
}

//+------------------------------------------------------------------+
bool VolatilityOK(const MqlRates &rates[])
{
   if(!UseVolatilityFilter) return(true);
   int cnt = MathMin(RangeSampleBars, ArraySize(rates) - 2);
   if(cnt < 5) return(true);
   double sum = 0.0;
   for(int i = 2; i < 2 + cnt; i++) sum += (rates[i].high - rates[i].low);
   double avg = sum / cnt;
   if(avg <= 0.0) return(true);
   double last = rates[1].high - rates[1].low;
   if(last < MinRangeFactor * avg) return(false);   // dead market
   if(last > MaxRangeFactor * avg) return(false);   // news spike
   return(true);
}

//======================================================================
// SECTION 16 - TRADE-RESULT TRACKING (streaks / daily count)
//======================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   long   magic  = (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   long   entry  = (long)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   for(int s = 0; s < SymbolTotal; s++)
   {
      if(Symbols[s].magic != magic) continue;

      if(entry == DEAL_ENTRY_IN)
         Symbols[s].tradesToday++;
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         if(profit < 0.0)
         {
            Symbols[s].consecLosses++;
            if(Symbols[s].consecLosses >= ConsecLossCooldown && ConsecLossCooldown > 0)
            {
               int secs = CooldownBars * PeriodSeconds(EntryTF);
               Symbols[s].cooldownUntilBar = TimeCurrent() + secs;
            }
         }
         else if(profit > 0.0)
            Symbols[s].consecLosses = 0;
      }
      break;
   }
}

//======================================================================
// SECTION 17 - DAILY / UTILITY
//======================================================================
void RollDailyCounters()
{
   datetime today = DayStart(TimeCurrent());
   if(today != CurrentDay)
   {
      CurrentDay      = today;
      DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      for(int s = 0; s < SymbolTotal; s++) Symbols[s].tradesToday = 0;
   }
}
//+------------------------------------------------------------------+
datetime DayStart(const datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return(StructToTime(dt));
}
//+------------------------------------------------------------------+
bool IsNewBar(const int s)
{
   datetime t = (datetime)SeriesInfoInteger(Symbols[s].name, EntryTF, SERIES_LASTBAR_DATE);
   if(t == 0) return(false);
   if(t != Symbols[s].lastBarTime) { Symbols[s].lastBarTime = t; return(true); }
   return(false);
}
//+------------------------------------------------------------------+
int CountPositions(const int s)
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbols[s].name) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Symbols[s].magic) continue;
      c++;
   }
   return(c);
}
//+------------------------------------------------------------------+
int TotalPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      long m = PositionGetInteger(POSITION_MAGIC);
      for(int s = 0; s < SymbolTotal; s++)
         if(Symbols[s].magic == m) { c++; break; }
   }
   return(c);
}
//+------------------------------------------------------------------+
bool InSet(const ulong &arr[], const ulong v)
{
   for(int i = ArraySize(arr) - 1; i >= 0; i--) if(arr[i] == v) return(true);
   return(false);
}
void AddToSet(ulong &arr[], const ulong v)
{
   if(InSet(arr, v)) return;
   int sz = ArraySize(arr);
   ArrayResize(arr, sz + 1);
   arr[sz] = v;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PrintFormat("SD-SMC EA stopped. reason=%d", reason);
}
//+------------------------------------------------------------------+
