//+------------------------------------------------------------------+
//|                                 SupplyDemandPriceActionEA.mq5     |
//|              Supply & Demand + Price Action engine (no indicators)|
//|                     Gold (XAUUSD) & EURUSD - M15 timeframe        |
//+------------------------------------------------------------------+
#property copyright "Quant Systems"
#property version   "1.00"
#property description "Pure price-action Supply & Demand EA. Trades Gold "
#property description "(XAUUSD) and EURUSD on M15. Detects fresh demand/"
#property description "supply zones from raw OHLC candle structure "
#property description "(Rally-Base-Rally, Drop-Base-Drop and reversal "
#property description "bases), confirms entries with price-action signals "
#property description "(engulfing, pin-bar, rejection), and manages risk "
#property description "with zone-based stops. Uses NO indicators, DLLs, "
#property description "or external files - only candle data (OODA loop: "
#property description "Observe -> Orient -> Decide -> Act)."

#include <Trade\Trade.mqh>

//======================================================================
// SECTION 1 - INPUT PARAMETERS
//======================================================================
input group    "=== Symbols & Timeframe ==="
input string   GoldSymbol          = "XAUUSD";   // Gold symbol name (as shown by your broker)
input string   ForexSymbol         = "EURUSD";   // Forex symbol name
input ENUM_TIMEFRAMES  TradeTF      = PERIOD_M15; // Working timeframe

input group    "=== Risk Management ==="
input double   RiskPercent         = 1.0;    // Risk per trade (% of account balance)
input double   RewardRiskRatio     = 2.0;    // Take-profit as multiple of risk (R)
input double   MinLot              = 0.01;   // Absolute minimum lot floor
input double   MaxLotCap           = 5.0;    // Absolute maximum lot ceiling
input double   MaxSpreadPoints     = 0.0;    // Max allowed spread in points (0 = auto = 40% of zone-buffer)
input int      MaxOpenPerSymbol    = 1;      // Max simultaneous positions per symbol
input int      MagicBase           = 20260726;

input group    "=== Zone Detection ==="
input int      LookbackBars        = 300;    // Bars scanned when mapping zones
input int      MaxBaseCandles      = 3;      // Max consolidation candles inside a base
input double   BasingBodyFactor    = 0.50;   // Body <= factor*range  => "base"/boring candle
input double   ImpulseBodyFactor   = 0.60;   // Body >= factor*range  => "impulse"/explosive candle
input double   ImpulseLegFactor    = 1.30;   // Leg-out range >= factor*avg range of base
input double   ZoneEntryBufferPct  = 0.10;   // Extra tolerance (% of zone height) around proximal line
input int      MaxZoneAgeBars      = 200;    // Ignore zones older than this (bars)
input int      MaxZoneTouches      = 2;      // Skip zones already retested this many times (freshness)

input group    "=== Structure & Confirmation ==="
input bool     UseTrendFilter      = true;   // Require market structure to align with the trade
input int      SwingStrength       = 2;      // Bars on each side that define a swing point
input int      StructureSwings     = 4;      // Recent swing points used to judge structure
input bool     RequirePinOrEngulf  = true;   // Require an explicit PA confirmation candle
input double   PinWickFactor       = 2.0;    // Pin-bar: rejection wick >= factor * body

input group    "=== Trade Management ==="
input double   SL_BufferPoints     = 0.0;    // Extra SL distance beyond distal line in points (0 = auto)
input bool     UseBreakEven        = true;   // Move SL to break-even after +1R
input double   BreakEvenTriggerR   = 1.0;    // Profit in R that arms break-even
input bool     UseTrailing         = true;   // Trail SL once in profit
input double   TrailStartR         = 1.5;    // Start trailing after this many R
input double   TrailStepPoints     = 0.0;    // Trailing step in points (0 = auto)
input bool     CloseOnOppositeZone = true;   // Exit early if price enters an opposing fresh zone

input group    "=== Session / Safety ==="
input double   DailyLossLimitPct   = 5.0;    // Halt new trades after this daily loss (% balance, 0 = off)
input double   MinAccountUSD       = 5.0;    // Do not trade below this equity

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
#define MAX_ZONES          64      // per symbol
#define SPREAD_ZONE_FRAC   0.40    // auto max-spread as fraction of zone buffer
#define MIN_RATES_BARS     50      // minimum bars required to operate

//======================================================================
// SECTION 3 - DATA STRUCTURES
//======================================================================
struct Zone
{
   int      type;        // ZONE_DEMAND or ZONE_SUPPLY
   double   proximal;    // line price first touches on return
   double   distal;      // far edge (stop goes beyond this)
   datetime formed;      // bar time the zone's base formed
   int      touches;     // how many times price has revisited
   bool     valid;
};

struct SymbolState
{
   string    name;
   bool      ready;
   long      magic;
   double    point;
   int       digits;
   double    volMin;
   double    volMax;
   double    volStep;
   datetime  lastBarTime;
   double    lastTradedZoneProx;   // avoid re-firing the same zone
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
      Print("ERROR: no tradable symbols configured. Check GoldSymbol / ForexSymbol names.");
      return(INIT_FAILED);
   }

   Trade.SetTypeFillingBySymbol(Symbols[0].name);
   Trade.SetDeviationInPoints(10);
   Trade.SetAsyncMode(false);

   CurrentDay      = DayStart(TimeCurrent());
   DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   PrintFormat("SupplyDemandPriceActionEA started | symbols=%d | TF=%s | risk=%.2f%% | RR=%.1f",
               SymbolTotal, EnumToString(TradeTF), RiskPercent, RewardRiskRatio);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
bool SetupSymbol(const string sym, const long magicOffset)
{
   if(sym == "" ) return(false);
   if(!SymbolSelect(sym, true))
   {
      Print("Symbol not available in Market Watch: ", sym);
      return(false);
   }

   SymbolState st;
   st.name    = sym;
   st.magic   = MagicBase + magicOffset;
   st.point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   st.digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   st.volMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   st.volMax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   st.volStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(st.volStep <= 0.0) st.volStep = 0.01;
   st.lastBarTime          = 0;
   st.lastTradedZoneProx   = 0.0;
   st.zoneCount            = 0;
   st.ready                = true;

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
      ManageOpenPositions(s);      // trail / break-even / opposite-zone exit run every tick

      if(IsNewBar(s))              // decision logic runs once per closed bar
         ProcessSymbol(s);
   }
}

//+------------------------------------------------------------------+
//| Per-symbol OODA cycle on each new closed bar                     |
//+------------------------------------------------------------------+
void ProcessSymbol(const int s)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbols[s].name, TradeTF, 0, LookbackBars + 5, rates);
   if(copied < MIN_RATES_BARS) return;

   // --- OBSERVE + ORIENT: rebuild the zone map from raw candles ---
   BuildZones(s, rates, copied);

   // --- Safety gates ---
   if(!TradingAllowed(s)) return;
   if(CountPositions(s) >= MaxOpenPerSymbol) return;

   // --- DECIDE: look for a valid setup on the just-closed bar ---
   int      dir  = DIR_NONE;
   Zone     zone;
   if(!FindSetup(s, rates, copied, dir, zone)) return;

   // --- ACT ---
   ExecuteTrade(s, dir, zone, rates);
}

//======================================================================
// SECTION 7 - OBSERVE/ORIENT: ZONE CONSTRUCTION
//======================================================================
void BuildZones(const int s, const MqlRates &rates[], const int n)
{
   Symbols[s].zoneCount = 0;

   int scan = MathMin(n - 2, LookbackBars);
   // legOut candle sits at index i (newer); base at i+1..; leg-in older still.
   for(int i = 2; i < scan && Symbols[s].zoneCount < MAX_ZONES; i++)
   {
      if(!IsImpulse(rates[i])) continue;

      bool bullLeg = (rates[i].close > rates[i].open);

      // collect consecutive base candles immediately older than the impulse
      int baseStart = i + 1;
      int baseCount = 0;
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
      if(legRange < ImpulseLegFactor * avgBaseRange) continue;   // leg-out must dwarf the base

      // impulse must actually leave the base (breakout close)
      if(bullLeg && rates[i].close <= baseHigh) continue;
      if(!bullLeg && rates[i].close >= baseLow)  continue;

      Zone z;
      z.formed  = rates[baseStart].time;
      z.touches = 0;
      z.valid   = true;

      if(bullLeg)   // Demand zone (buy interest below price)
      {
         z.type     = ZONE_DEMAND;
         z.proximal = baseHigh;
         z.distal   = baseLow;
      }
      else          // Supply zone (sell interest above price)
      {
         z.type     = ZONE_SUPPLY;
         z.proximal = baseLow;
         z.distal   = baseHigh;
      }

      // age filter
      int ageBars = i;   // impulse index approximates bars since formation
      if(ageBars > MaxZoneAgeBars) continue;

      // count how many candles since formation have retested the zone (freshness)
      z.touches = CountTouches(rates, i, z);
      if(z.touches > MaxZoneTouches) continue;

      // de-duplicate overlapping zones of the same type
      if(ZoneOverlaps(s, z)) continue;

      Symbols[s].zones[Symbols[s].zoneCount] = z;
      Symbols[s].zoneCount++;
   }
}

//+------------------------------------------------------------------+
bool IsBase(const MqlRates &r)
{
   double range = r.high - r.low;
   if(range <= 0.0) return(false);
   double body = MathAbs(r.close - r.open);
   return(body <= BasingBodyFactor * range);
}

//+------------------------------------------------------------------+
bool IsImpulse(const MqlRates &r)
{
   double range = r.high - r.low;
   if(range <= 0.0) return(false);
   double body = MathAbs(r.close - r.open);
   return(body >= ImpulseBodyFactor * range);
}

//+------------------------------------------------------------------+
//| Count retests of a zone between its formation and the newest bar |
//| idxFrom is the impulse index (older = higher). We walk toward 0. |
//+------------------------------------------------------------------+
int CountTouches(const MqlRates &rates[], const int idxFrom, const Zone &z)
{
   int touches = 0;
   for(int k = idxFrom - 1; k >= 1; k--)
   {
      bool hit = false;
      if(z.type == ZONE_DEMAND)
         hit = (rates[k].low <= z.proximal && rates[k].low >= z.distal);
      else
         hit = (rates[k].high >= z.proximal && rates[k].high <= z.distal);
      if(hit) touches++;
   }
   return(touches);
}

//+------------------------------------------------------------------+
bool ZoneOverlaps(const int s, const Zone &z)
{
   for(int i = 0; i < Symbols[s].zoneCount; i++)
   {
      Zone e = Symbols[s].zones[i];
      if(e.type != z.type) continue;
      double aLo = MathMin(z.proximal, z.distal);
      double aHi = MathMax(z.proximal, z.distal);
      double bLo = MathMin(e.proximal, e.distal);
      double bHi = MathMax(e.proximal, e.distal);
      if(aHi >= bLo && bHi >= aLo) return(true);   // ranges intersect
   }
   return(false);
}

//======================================================================
// SECTION 8 - ORIENT: MARKET STRUCTURE (SWINGS)
//======================================================================
int MarketStructure(const MqlRates &rates[], const int n)
{
   double swingHighs[]; double swingLows[];
   ArrayResize(swingHighs, 0);
   ArrayResize(swingLows,  0);

   int limit = MathMin(n - SwingStrength - 1, LookbackBars);
   for(int i = SwingStrength + 1; i < limit; i++)
   {
      if(IsSwingHigh(rates, i) && ArraySize(swingHighs) < StructureSwings)
      {
         int sz = ArraySize(swingHighs);
         ArrayResize(swingHighs, sz + 1);
         swingHighs[sz] = rates[i].high;
      }
      if(IsSwingLow(rates, i) && ArraySize(swingLows) < StructureSwings)
      {
         int sz = ArraySize(swingLows);
         ArrayResize(swingLows, sz + 1);
         swingLows[sz] = rates[i].low;
      }
      if(ArraySize(swingHighs) >= StructureSwings && ArraySize(swingLows) >= StructureSwings)
         break;
   }

   if(ArraySize(swingHighs) < 2 || ArraySize(swingLows) < 2) return(TREND_RANGE);

   // index 0 = most recent swing (nearest to the current bar)
   bool higherHighs = (swingHighs[0] > swingHighs[1]);
   bool higherLows  = (swingLows[0]  > swingLows[1]);
   bool lowerHighs  = (swingHighs[0] < swingHighs[1]);
   bool lowerLows   = (swingLows[0]  < swingLows[1]);

   if(higherHighs && higherLows) return(TREND_UP);
   if(lowerHighs  && lowerLows)  return(TREND_DOWN);
   return(TREND_RANGE);
}

//+------------------------------------------------------------------+
bool IsSwingHigh(const MqlRates &rates[], const int i)
{
   for(int k = 1; k <= SwingStrength; k++)
   {
      if(rates[i].high <= rates[i - k].high) return(false);
      if(rates[i].high <= rates[i + k].high) return(false);
   }
   return(true);
}

//+------------------------------------------------------------------+
bool IsSwingLow(const MqlRates &rates[], const int i)
{
   for(int k = 1; k <= SwingStrength; k++)
   {
      if(rates[i].low >= rates[i - k].low) return(false);
      if(rates[i].low >= rates[i + k].low) return(false);
   }
   return(true);
}

//======================================================================
// SECTION 9 - DECIDE: SETUP DETECTION
//======================================================================
bool FindSetup(const int s, const MqlRates &rates[], const int n, int &dir, Zone &outZone)
{
   dir = DIR_NONE;
   int structure = UseTrendFilter ? MarketStructure(rates, n) : TREND_RANGE;

   // The signal candle is the last CLOSED bar (index 1). Index 0 is forming.
   int sig = 1;
   double sigHigh = rates[sig].high;
   double sigLow  = rates[sig].low;

   double bestScore = -DBL_MAX;
   bool   found     = false;

   for(int z = 0; z < Symbols[s].zoneCount; z++)
   {
      Zone zone = Symbols[s].zones[z];
      if(!zone.valid) continue;

      double zoneHeight = MathAbs(zone.proximal - zone.distal);
      if(zoneHeight <= 0.0) continue;
      double buffer = zoneHeight * ZoneEntryBufferPct;

      if(zone.type == ZONE_DEMAND)
      {
         if(UseTrendFilter && structure == TREND_DOWN) continue;   // don't buy demand in a downtrend

         // price must dip into the zone but close back above the distal line
         bool tapped = (sigLow <= zone.proximal + buffer) && (sigLow >= zone.distal - buffer);
         bool held   = (rates[sig].close > zone.distal);
         if(!tapped || !held) continue;

         if(RequirePinOrEngulf && !IsBullishConfirm(rates, sig)) continue;
         if(MathAbs(zone.proximal - Symbols[s].lastTradedZoneProx) < buffer) continue; // already fired

         // prefer fresher, closer zones
         double score = -zone.touches * 10.0 - (double)ZoneBarsAway(rates, n, zone);
         if(score > bestScore)
         {
            bestScore = score;
            outZone   = zone;
            dir       = DIR_BUY;
            found     = true;
         }
      }
      else // ZONE_SUPPLY
      {
         if(UseTrendFilter && structure == TREND_UP) continue;     // don't sell supply in an uptrend

         bool tapped = (sigHigh >= zone.proximal - buffer) && (sigHigh <= zone.distal + buffer);
         bool held   = (rates[sig].close < zone.distal);
         if(!tapped || !held) continue;

         if(RequirePinOrEngulf && !IsBearishConfirm(rates, sig)) continue;
         if(MathAbs(zone.proximal - Symbols[s].lastTradedZoneProx) < buffer) continue;

         double score = -zone.touches * 10.0 - (double)ZoneBarsAway(rates, n, zone);
         if(score > bestScore)
         {
            bestScore = score;
            outZone   = zone;
            dir       = DIR_SELL;
            found     = true;
         }
      }
   }
   return(found);
}

//+------------------------------------------------------------------+
int ZoneBarsAway(const MqlRates &rates[], const int n, const Zone &z)
{
   for(int i = 1; i < n; i++)
      if(rates[i].time <= z.formed) return(i);
   return(n);
}

//======================================================================
// SECTION 10 - PRICE ACTION CONFIRMATION
//======================================================================
bool IsBullishConfirm(const MqlRates &rates[], const int i)
{
   return( IsBullishEngulfing(rates, i) || IsHammer(rates[i]) || IsStrongBullClose(rates[i]) );
}

bool IsBearishConfirm(const MqlRates &rates[], const int i)
{
   return( IsBearishEngulfing(rates, i) || IsShootingStar(rates[i]) || IsStrongBearClose(rates[i]) );
}

//+------------------------------------------------------------------+
bool IsBullishEngulfing(const MqlRates &rates[], const int i)
{
   if(i + 1 >= ArraySize(rates)) return(false);
   bool prevBear = (rates[i+1].close < rates[i+1].open);
   bool currBull = (rates[i].close   > rates[i].open);
   bool engulfs  = (rates[i].close >= rates[i+1].open) && (rates[i].open <= rates[i+1].close);
   return(prevBear && currBull && engulfs);
}

//+------------------------------------------------------------------+
bool IsBearishEngulfing(const MqlRates &rates[], const int i)
{
   if(i + 1 >= ArraySize(rates)) return(false);
   bool prevBull = (rates[i+1].close > rates[i+1].open);
   bool currBear = (rates[i].close   < rates[i].open);
   bool engulfs  = (rates[i].open >= rates[i+1].close) && (rates[i].close <= rates[i+1].open);
   return(prevBull && currBear && engulfs);
}

//+------------------------------------------------------------------+
bool IsHammer(const MqlRates &r)   // long lower wick = demand rejection
{
   double lowerWick = MathMin(r.open, r.close) - r.low;
   double upperWick = r.high - MathMax(r.open, r.close);
   double realBody  = MathAbs(r.close - r.open);
   double range     = r.high - r.low;
   if(range <= 0.0) return(false);
   // treat a doji-ish body as a small non-zero value so the wick ratio still resolves
   if(realBody < range * 0.05) realBody = range * 0.05;
   return(lowerWick >= PinWickFactor * realBody && lowerWick > upperWick);
}

//+------------------------------------------------------------------+
bool IsShootingStar(const MqlRates &r)   // long upper wick = supply rejection
{
   double upperWick = r.high - MathMax(r.open, r.close);
   double lowerWick = MathMin(r.open, r.close) - r.low;
   double realBody  = MathAbs(r.close - r.open);
   double range     = r.high - r.low;
   if(range <= 0.0) return(false);
   if(realBody < range * 0.05) realBody = range * 0.05;
   return(upperWick >= PinWickFactor * realBody && upperWick > lowerWick);
}

//+------------------------------------------------------------------+
bool IsStrongBullClose(const MqlRates &r)
{
   double range = r.high - r.low;
   if(range <= 0.0) return(false);
   return( (r.close > r.open) && ((r.close - r.low) >= 0.66 * range) );
}

//+------------------------------------------------------------------+
bool IsStrongBearClose(const MqlRates &r)
{
   double range = r.high - r.low;
   if(range <= 0.0) return(false);
   return( (r.close < r.open) && ((r.high - r.close) >= 0.66 * range) );
}

//======================================================================
// SECTION 11 - ACT: TRADE EXECUTION
//======================================================================
void ExecuteTrade(const int s, const int dir, const Zone &zone, const MqlRates &rates[])
{
   string sym = Symbols[s].name;
   double pt  = Symbols[s].point;

   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;

   double zoneHeight = MathAbs(zone.proximal - zone.distal);
   double buffer = (SL_BufferPoints > 0.0) ? SL_BufferPoints * pt
                                           : MathMax(zoneHeight * 0.10, 5 * pt);

   double entry, sl, tp, riskPrice;

   if(dir == DIR_BUY)
   {
      entry     = ask;
      sl        = zone.distal - buffer;
      riskPrice = entry - sl;
      if(riskPrice <= 0.0) return;
      tp        = entry + RewardRiskRatio * riskPrice;
   }
   else
   {
      entry     = bid;
      sl        = zone.distal + buffer;
      riskPrice = sl - entry;
      if(riskPrice <= 0.0) return;
      tp        = entry - RewardRiskRatio * riskPrice;
   }

   // spread gate
   double spread   = (ask - bid) / pt;
   double spreadCap = (MaxSpreadPoints > 0.0) ? MaxSpreadPoints
                                              : MathMax(buffer / pt * SPREAD_ZONE_FRAC, 10.0);
   if(spread > spreadCap)
   {
      PrintFormat("%s: spread %.1f > cap %.1f - skip", sym, spread, spreadCap);
      return;
   }

   double lots = CalcLots(s, riskPrice);
   if(lots <= 0.0) return;

   sl = NormalizeDouble(sl, Symbols[s].digits);
   tp = NormalizeDouble(tp, Symbols[s].digits);

   Trade.SetExpertMagicNumber(Symbols[s].magic);
   Trade.SetTypeFillingBySymbol(sym);

   bool ok;
   string tag = (zone.type == ZONE_DEMAND ? "Demand" : "Supply");
   if(dir == DIR_BUY)
      ok = Trade.Buy(lots, sym, ask, sl, tp, "SD_" + tag);
   else
      ok = Trade.Sell(lots, sym, bid, sl, tp, "SD_" + tag);

   if(ok)
   {
      Symbols[s].lastTradedZoneProx = zone.proximal;
      PrintFormat("%s %s @ %.*f | lots=%.2f SL=%.*f TP=%.*f | zone[%s prox=%.*f distal=%.*f touches=%d]",
                  sym, (dir==DIR_BUY?"BUY":"SELL"), Symbols[s].digits, entry, lots,
                  Symbols[s].digits, sl, Symbols[s].digits, tp,
                  tag, Symbols[s].digits, zone.proximal, Symbols[s].digits, zone.distal, zone.touches);
   }
   else
   {
      PrintFormat("%s order failed: retcode=%d %s", sym, Trade.ResultRetcode(),
                  Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Position sizing from money risk / price risk                     |
//+------------------------------------------------------------------+
double CalcLots(const int s, const double riskPrice)
{
   string sym = Symbols[s].name;
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;
   if(riskMoney <= 0.0 || riskPrice <= 0.0) return(0.0);

   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return(0.0);

   // money lost per 1.0 lot if price moves by riskPrice against us
   double lossPerLot = (riskPrice / tickSize) * tickValue;
   if(lossPerLot <= 0.0) return(0.0);

   double lots = riskMoney / lossPerLot;

   // clamp to broker + user limits, snap to volume step
   double lo = MathMax(Symbols[s].volMin, MinLot);
   double hi = MathMin(Symbols[s].volMax, MaxLotCap);
   lots = MathMax(lo, MathMin(hi, lots));
   lots = MathFloor(lots / Symbols[s].volStep) * Symbols[s].volStep;
   if(lots < lo) lots = lo;

   // final margin sanity check
   double marginNeeded = 0.0;
   ENUM_ORDER_TYPE ot = ORDER_TYPE_BUY;
   double price = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(OrderCalcMargin(ot, sym, lots, price, marginNeeded))
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(marginNeeded > freeMargin)
      {
         double scaled = lots * (freeMargin / marginNeeded) * 0.95;
         scaled = MathFloor(scaled / Symbols[s].volStep) * Symbols[s].volStep;
         if(scaled < lo) return(0.0);
         lots = scaled;
      }
   }
   return(lots);
}

//======================================================================
// SECTION 12 - TRADE MANAGEMENT (break-even / trailing / exits)
//======================================================================
void ManageOpenPositions(const int s)
{
   string sym = Symbols[s].name;
   double pt  = Symbols[s].point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Symbols[s].magic) continue;

      long   type   = PositionGetInteger(POSITION_TYPE);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double bid    = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask    = SymbolInfoDouble(sym, SYMBOL_ASK);

      double riskPrice = MathAbs(open - sl);
      if(riskPrice <= 0.0) continue;

      double newSL = sl;

      if(type == POSITION_TYPE_BUY)
      {
         double profitR = (bid - open) / riskPrice;

         if(UseBreakEven && profitR >= BreakEvenTriggerR && sl < open)
            newSL = MathMax(newSL, open + 2 * pt);

         if(UseTrailing && profitR >= TrailStartR)
         {
            double step = (TrailStepPoints > 0.0) ? TrailStepPoints * pt : riskPrice * 0.5;
            double candidate = bid - step;
            if(candidate > newSL) newSL = candidate;
         }

         if(CloseOnOppositeZone && PriceInFreshZone(s, ZONE_SUPPLY, bid))
         { Trade.PositionClose(ticket); continue; }

         if(newSL > sl && newSL < bid)
            Trade.PositionModify(ticket, NormalizeDouble(newSL, Symbols[s].digits), tp);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profitR = (open - ask) / riskPrice;

         if(UseBreakEven && profitR >= BreakEvenTriggerR && (sl > open || sl == 0.0))
            newSL = (sl == 0.0) ? open - 2 * pt : MathMin(newSL, open - 2 * pt);

         if(UseTrailing && profitR >= TrailStartR)
         {
            double step = (TrailStepPoints > 0.0) ? TrailStepPoints * pt : riskPrice * 0.5;
            double candidate = ask + step;
            if(candidate < newSL || sl == 0.0) newSL = candidate;
         }

         if(CloseOnOppositeZone && PriceInFreshZone(s, ZONE_DEMAND, ask))
         { Trade.PositionClose(ticket); continue; }

         if((newSL < sl || sl == 0.0) && newSL > ask)
            Trade.PositionModify(ticket, NormalizeDouble(newSL, Symbols[s].digits), tp);
      }
   }
}

//+------------------------------------------------------------------+
bool PriceInFreshZone(const int s, const int zoneType, const double price)
{
   for(int z = 0; z < Symbols[s].zoneCount; z++)
   {
      Zone e = Symbols[s].zones[z];
      if(e.type != zoneType) continue;
      if(e.touches > MaxZoneTouches) continue;
      double lo = MathMin(e.proximal, e.distal);
      double hi = MathMax(e.proximal, e.distal);
      if(price >= lo && price <= hi) return(true);
   }
   return(false);
}

//======================================================================
// SECTION 13 - SAFETY / SESSION GATES
//======================================================================
bool TradingAllowed(const int s)
{
   if(AccountInfoDouble(ACCOUNT_EQUITY) < MinAccountUSD) return(false);

   long tradeMode = SymbolInfoInteger(Symbols[s].name, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED) return(false);

   if(DailyLossLimitPct > 0.0)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dd = (DayStartBalance - equity) / DayStartBalance * 100.0;
      if(dd >= DailyLossLimitPct) return(false);
   }
   return(true);
}

//+------------------------------------------------------------------+
void RollDailyCounters()
{
   datetime today = DayStart(TimeCurrent());
   if(today != CurrentDay)
   {
      CurrentDay      = today;
      DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   }
}

//+------------------------------------------------------------------+
datetime DayStart(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return(StructToTime(dt));
}

//======================================================================
// SECTION 14 - UTILITIES
//======================================================================
bool IsNewBar(const int s)
{
   datetime t = (datetime)SeriesInfoInteger(Symbols[s].name, TradeTF, SERIES_LASTBAR_DATE);
   if(t == 0) return(false);
   if(t != Symbols[s].lastBarTime)
   {
      Symbols[s].lastBarTime = t;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
int CountPositions(const int s)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbols[s].name) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Symbols[s].magic) continue;
      count++;
   }
   return(count);
}

//======================================================================
// SECTION 15 - SHUTDOWN
//======================================================================
void OnDeinit(const int reason)
{
   PrintFormat("SupplyDemandPriceActionEA stopped. reason=%d", reason);
}
//+------------------------------------------------------------------+
