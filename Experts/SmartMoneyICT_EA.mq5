//+------------------------------------------------------------------+
//|                                            SmartMoneyICT_EA.mq5   |
//|            Pure price-action EA — Smart Money Concepts / ICT      |
//|                        No indicators. M5 timeframe.               |
//+------------------------------------------------------------------+
#property copyright "Quant Systems"
#property version   "1.00"
#property description "Smart Money Concepts / ICT expert advisor. Trades on"
#property description "raw price action only — NO indicators of any kind."
#property description "Engine: market structure (BOS/CHoCH), order blocks,"
#property description "fair value gaps (imbalance), liquidity sweeps (stop"
#property description "hunts), supply/demand zones and premium/discount"
#property description "equilibrium. Designed for the M5 timeframe."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//======================================================================
// INPUT PARAMETERS
//======================================================================
input group             "=== General ==="
input ENUM_TIMEFRAMES   InpTimeframe        = PERIOD_M5;   // Trading timeframe
input long              InpMagic            = 20260801;    // Magic number
input int               InpMaxSpreadPoints  = 40;          // Max spread (points) to allow entry
input int               InpMaxOpenPositions = 1;           // Max simultaneous positions
input string            InpTradeComment     = "SMC-ICT";   // Order comment

input group             "=== Risk ==="
input double            InpRiskPercent      = 1.0;         // Risk per trade (% of equity)
input double            InpFixedLot         = 0.0;         // Fixed lot (0 = use risk %)
input double            InpMinRR            = 2.0;         // Minimum reward:risk to take a trade
input double            InpSL_BufferPct     = 0.15;        // SL buffer beyond zone (% of avg range)
input bool              InpUseBreakeven     = true;        // Move SL to breakeven at +1R
input bool              InpUseTrailing      = true;        // Trail SL after breakeven
input double            InpTrailStartR      = 1.5;         // Start trailing at this R multiple

input group             "=== Market Structure ==="
input int               InpSwingLookback    = 2;           // Fractal strength (bars each side)
input int               InpStructureDepth   = 300;         // Bars to scan for structure
input bool              InpUseHTFBias        = true;        // Use higher-timeframe bias filter
input ENUM_TIMEFRAMES   InpHTF              = PERIOD_H1;    // Higher timeframe for bias

input group             "=== Smart Money Zones ==="
input bool              InpUseOrderBlocks   = true;         // Require order-block confluence
input bool              InpUseFVG           = true;         // Require fair-value-gap confluence
input bool              InpRequireSweep     = true;         // Require liquidity sweep before entry
input bool              InpUsePremiumDiscount = true;       // Only buy discount / sell premium
input int               InpZoneMaxAgeBars   = 60;           // Max age of a zone to remain valid

input group             "=== Sessions (server time) ==="
input bool              InpUseSessionFilter = false;        // Restrict trading to a window
input int               InpSessionStartHour = 7;            // Session start hour
input int               InpSessionEndHour   = 20;           // Session end hour

//======================================================================
// CONSTANTS
//======================================================================
#define AVG_RANGE_PERIOD    20      // bars used for the average candle range (SL buffer)
#define MAX_SWINGS          64      // ring buffer for detected swings
#define MAX_ZONES           32      // stored order blocks / FVGs

enum ENUM_BIAS { BIAS_NONE=0, BIAS_BULL=1, BIAS_BEAR=-1 };

//======================================================================
// STRUCTS
//======================================================================
struct SwingPoint
{
   datetime time;
   double   price;
   int      type;   // +1 = swing high, -1 = swing low
};

struct Zone
{
   bool     valid;
   int      dir;      // +1 bullish (demand), -1 bearish (supply)
   double   top;
   double   bottom;
   datetime time;     // formation time
   bool     mitigated;
};

//======================================================================
// GLOBAL STATE
//======================================================================
CTrade         trade;
CPositionInfo  posinfo;

SwingPoint     g_swings[MAX_SWINGS];
int            g_swingCount = 0;

Zone           g_orderBlocks[MAX_ZONES];
Zone           g_fvgs[MAX_ZONES];

datetime       g_lastBarTime = 0;
int            g_structureBias = BIAS_NONE;   // internal M5 structure bias

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(20);

   if(InpRiskPercent <= 0 && InpFixedLot <= 0)
   {
      Print("ERROR: set either InpRiskPercent or InpFixedLot > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }

   PrintFormat("SmartMoneyICT_EA initialised on %s / %s",
               _Symbol, EnumToString(InpTimeframe));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Main tick handler — logic runs once per closed bar               |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageOpenPositions();

   datetime barTime = iTime(_Symbol, InpTimeframe, 0);
   if(barTime == g_lastBarTime)
      return;                 // only act on a new bar
   g_lastBarTime = barTime;

   if(!IsTradingAllowed())
      return;

   // --- rebuild the market picture on the closed bar ---
   MqlRates rates[];
   int copied = CopyRates(_Symbol, InpTimeframe, 0, InpStructureDepth, rates);
   if(copied < 50)
      return;
   ArraySetAsSeries(rates, true);

   DetectSwings(rates, copied);
   UpdateStructureBias(rates);
   DetectOrderBlocks(rates, copied);
   DetectFVGs(rates, copied);

   if(CountOwnPositions() >= InpMaxOpenPositions)
      return;

   EvaluateEntry(rates, copied);
}

//+------------------------------------------------------------------+
//| Trading permission checks                                        |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))     return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)            return false;

   if(InpUseSessionFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      if(InpSessionStartHour <= InpSessionEndHour)
      {
         if(h < InpSessionStartHour || h >= InpSessionEndHour) return false;
      }
      else // overnight window
      {
         if(h < InpSessionStartHour && h >= InpSessionEndHour) return false;
      }
   }
   return true;
}

//======================================================================
// MARKET STRUCTURE — swing detection (fractals, pure price action)
//======================================================================
void DetectSwings(const MqlRates &rates[], int n)
{
   g_swingCount = 0;
   int k = InpSwingLookback;

   // walk from oldest to newest so g_swings is chronological
   for(int i = n - 1 - k; i >= k; i--)
   {
      bool isHigh = true, isLow = true;
      for(int j = 1; j <= k; j++)
      {
         if(rates[i].high <= rates[i+j].high || rates[i].high <= rates[i-j].high) isHigh = false;
         if(rates[i].low  >= rates[i+j].low  || rates[i].low  >= rates[i-j].low ) isLow  = false;
      }
      if(isHigh) PushSwing(rates[i].time, rates[i].high,  +1);
      if(isLow)  PushSwing(rates[i].time, rates[i].low,   -1);
   }
}

void PushSwing(datetime t, double p, int type)
{
   if(g_swingCount < MAX_SWINGS)
   {
      g_swings[g_swingCount].time  = t;
      g_swings[g_swingCount].price = p;
      g_swings[g_swingCount].type  = type;
      g_swingCount++;
   }
   else
   {
      for(int i = 0; i < MAX_SWINGS - 1; i++)
         g_swings[i] = g_swings[i+1];
      g_swings[MAX_SWINGS-1].time  = t;
      g_swings[MAX_SWINGS-1].price = p;
      g_swings[MAX_SWINGS-1].type  = type;
   }
}

// most recent swing of a given type; occurrence=0 newest, 1 previous ...
bool GetSwing(int type, int occurrence, SwingPoint &out)
{
   int found = 0;
   for(int i = g_swingCount - 1; i >= 0; i--)
   {
      if(g_swings[i].type == type)
      {
         if(found == occurrence) { out = g_swings[i]; return true; }
         found++;
      }
   }
   return false;
}

//======================================================================
// MARKET STRUCTURE — BOS / CHoCH bias on the trading timeframe
//======================================================================
void UpdateStructureBias(const MqlRates &rates[])
{
   double close = rates[1].close;   // last closed bar

   SwingPoint hi0, hi1, lo0, lo1;
   bool hasHi0 = GetSwing(+1, 0, hi0);
   bool hasHi1 = GetSwing(+1, 1, hi1);
   bool hasLo0 = GetSwing(-1, 0, lo0);
   bool hasLo1 = GetSwing(-1, 1, lo1);

   // Break of structure to the upside: close above last confirmed swing high
   if(hasHi0 && close > hi0.price)
      g_structureBias = BIAS_BULL;
   // Break of structure to the downside: close below last confirmed swing low
   else if(hasLo0 && close < lo0.price)
      g_structureBias = BIAS_BEAR;

   // Change of character refinement: higher-high/higher-low => bull; opposite => bear
   if(hasHi0 && hasHi1 && hasLo0 && hasLo1)
   {
      bool HH = hi0.price > hi1.price;
      bool HL = lo0.price > lo1.price;
      bool LH = hi0.price < hi1.price;
      bool LL = lo0.price < lo1.price;
      if(HH && HL) g_structureBias = BIAS_BULL;
      if(LH && LL) g_structureBias = BIAS_BEAR;
   }
}

//======================================================================
// HIGHER-TIMEFRAME BIAS (still pure price action)
//======================================================================
int HTFBias()
{
   if(!InpUseHTFBias) return BIAS_NONE;

   MqlRates htf[];
   int n = CopyRates(_Symbol, InpHTF, 0, 60, htf);
   if(n < 20) return BIAS_NONE;
   ArraySetAsSeries(htf, true);

   int k = InpSwingLookback;
   double lastHigh = 0, prevHigh = 0, lastLow = 0, prevLow = 0;
   int hiCnt = 0, loCnt = 0;

   for(int i = k; i < n - k; i++)
   {
      bool isHigh = true, isLow = true;
      for(int j = 1; j <= k; j++)
      {
         if(htf[i].high <= htf[i+j].high || htf[i].high <= htf[i-j].high) isHigh = false;
         if(htf[i].low  >= htf[i+j].low  || htf[i].low  >= htf[i-j].low ) isLow  = false;
      }
      if(isHigh) { if(hiCnt==0) lastHigh=htf[i].high; else if(hiCnt==1) prevHigh=htf[i].high; hiCnt++; }
      if(isLow ) { if(loCnt==0) lastLow =htf[i].low;  else if(loCnt==1) prevLow =htf[i].low;  loCnt++; }
      if(hiCnt>=2 && loCnt>=2) break;
   }

   if(hiCnt>=2 && loCnt>=2)
   {
      if(lastHigh > prevHigh && lastLow > prevLow) return BIAS_BULL;
      if(lastHigh < prevHigh && lastLow < prevLow) return BIAS_BEAR;
   }
   return BIAS_NONE;
}

//======================================================================
// ORDER BLOCKS — last opposite candle before a structure-breaking move
//======================================================================
void DetectOrderBlocks(const MqlRates &rates[], int n)
{
   for(int i = 0; i < MAX_ZONES; i++) g_orderBlocks[i].valid = false;
   int stored = 0;

   double avgRange = AvgRange(rates, n);
   if(avgRange <= 0) return;

   // scan recent bars (index 3..InpZoneMaxAgeBars) for impulsive displacement
   int maxScan = MathMin(n - 3, InpZoneMaxAgeBars + 3);
   for(int i = 3; i < maxScan && stored < MAX_ZONES; i++)
   {
      double body = MathAbs(rates[i-1].close - rates[i-1].open);

      // Bullish OB: a down candle at [i], followed by strong up displacement
      if(rates[i].close < rates[i].open)
      {
         double move = rates[i-1].close - rates[i].high;
         if(rates[i-1].close > rates[i-1].open && move > avgRange * 1.0 &&
            body > avgRange * 0.8)
         {
            g_orderBlocks[stored].valid     = true;
            g_orderBlocks[stored].dir       = +1;
            g_orderBlocks[stored].top       = rates[i].high;
            g_orderBlocks[stored].bottom    = rates[i].low;
            g_orderBlocks[stored].time      = rates[i].time;
            g_orderBlocks[stored].mitigated = false;
            stored++;
            continue;
         }
      }
      // Bearish OB: an up candle at [i], followed by strong down displacement
      if(rates[i].close > rates[i].open)
      {
         double move = rates[i].low - rates[i-1].close;
         if(rates[i-1].close < rates[i-1].open && move > avgRange * 1.0 &&
            body > avgRange * 0.8)
         {
            g_orderBlocks[stored].valid     = true;
            g_orderBlocks[stored].dir       = -1;
            g_orderBlocks[stored].top       = rates[i].high;
            g_orderBlocks[stored].bottom    = rates[i].low;
            g_orderBlocks[stored].time      = rates[i].time;
            g_orderBlocks[stored].mitigated = false;
            stored++;
         }
      }
   }
}

//======================================================================
// FAIR VALUE GAPS — 3-candle imbalance (ICT FVG)
//======================================================================
void DetectFVGs(const MqlRates &rates[], int n)
{
   for(int i = 0; i < MAX_ZONES; i++) g_fvgs[i].valid = false;
   int stored = 0;

   double avgRange = AvgRange(rates, n);
   if(avgRange <= 0) return;

   int maxScan = MathMin(n - 2, InpZoneMaxAgeBars + 2);
   for(int i = 2; i < maxScan && stored < MAX_ZONES; i++)
   {
      // Bullish FVG: gap between candle[i+1].high and candle[i-1].low
      double bullGap = rates[i-1].low - rates[i+1].high;
      if(bullGap > avgRange * 0.15)
      {
         g_fvgs[stored].valid     = true;
         g_fvgs[stored].dir       = +1;
         g_fvgs[stored].top       = rates[i-1].low;
         g_fvgs[stored].bottom    = rates[i+1].high;
         g_fvgs[stored].time      = rates[i].time;
         g_fvgs[stored].mitigated = false;
         stored++;
         continue;
      }
      // Bearish FVG: gap between candle[i+1].low and candle[i-1].high
      double bearGap = rates[i+1].low - rates[i-1].high;
      if(bearGap > avgRange * 0.15)
      {
         g_fvgs[stored].valid     = true;
         g_fvgs[stored].dir       = -1;
         g_fvgs[stored].top       = rates[i+1].low;
         g_fvgs[stored].bottom    = rates[i-1].high;
         g_fvgs[stored].time      = rates[i].time;
         g_fvgs[stored].mitigated = false;
         stored++;
      }
   }
}

//======================================================================
// LIQUIDITY SWEEP — did price run a prior swing then reject? (stop hunt)
//======================================================================
bool DetectLiquiditySweep(const MqlRates &rates[], int dir)
{
   // dir +1: sell-side liquidity below a swing low was swept, price rejected up
   // dir -1: buy-side  liquidity above a swing high was swept, price rejected down
   SwingPoint sw;
   double c = rates[1].close;
   double o = rates[1].open;

   if(dir == +1)
   {
      if(!GetSwing(-1, 0, sw)) return false;
      // last closed bar wicked below the swing low but closed back above it
      return (rates[1].low < sw.price && c > sw.price && c > o);
   }
   else
   {
      if(!GetSwing(+1, 0, sw)) return false;
      return (rates[1].high > sw.price && c < sw.price && c < o);
   }
}

//======================================================================
// PREMIUM / DISCOUNT — equilibrium of the current dealing range
//======================================================================
bool InDiscount(const MqlRates &rates[])
{
   SwingPoint hi, lo;
   if(!GetSwing(+1,0,hi) || !GetSwing(-1,0,lo)) return true;
   double eq = (hi.price + lo.price) / 2.0;
   return (rates[1].close < eq);        // below 50% = discount => buy zone
}

bool InPremium(const MqlRates &rates[])
{
   SwingPoint hi, lo;
   if(!GetSwing(+1,0,hi) || !GetSwing(-1,0,lo)) return true;
   double eq = (hi.price + lo.price) / 2.0;
   return (rates[1].close > eq);        // above 50% = premium => sell zone
}

//======================================================================
// ENTRY EVALUATION — combine all confluences
//======================================================================
void EvaluateEntry(const MqlRates &rates[], int n)
{
   int htf = HTFBias();
   int bias = g_structureBias;

   // If HTF filter is active it must agree with (or set) the bias
   if(InpUseHTFBias && htf != BIAS_NONE)
   {
      if(bias == BIAS_NONE) bias = htf;
      else if(bias != htf)  return;      // conflict — stand aside
   }
   if(bias == BIAS_NONE) return;

   double price = (bias == BIAS_BULL) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                      : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(bias == BIAS_BULL)
   {
      if(InpRequireSweep && !DetectLiquiditySweep(rates, +1)) return;
      if(InpUsePremiumDiscount && !InDiscount(rates))         return;

      Zone z;
      if(!PriceInZone(+1, rates[1].low, rates[1].high, z))    return;

      double sl = ZoneStop(z, +1, rates, n);
      double tp = TakeProfit(+1, price, sl, rates);
      if(!RRAcceptable(price, sl, tp)) return;
      OpenTrade(ORDER_TYPE_BUY, price, sl, tp);
   }
   else // BIAS_BEAR
   {
      if(InpRequireSweep && !DetectLiquiditySweep(rates, -1)) return;
      if(InpUsePremiumDiscount && !InPremium(rates))          return;

      Zone z;
      if(!PriceInZone(-1, rates[1].low, rates[1].high, z))    return;

      double sl = ZoneStop(z, -1, rates, n);
      double tp = TakeProfit(-1, price, sl, rates);
      if(!RRAcceptable(price, sl, tp)) return;
      OpenTrade(ORDER_TYPE_SELL, price, sl, tp);
   }
}

//======================================================================
// Confluence: has the last bar tapped a valid OB / FVG in our direction?
//======================================================================
bool PriceInZone(int dir, double barLow, double barHigh, Zone &chosen)
{
   bool needOB  = InpUseOrderBlocks;
   bool needFVG = InpUseFVG;

   // If neither confluence required, accept a synthetic zone at current swing.
   if(!needOB && !needFVG)
   {
      SwingPoint sw;
      int t = (dir==+1) ? -1 : +1;
      if(GetSwing(t,0,sw))
      {
         chosen.valid  = true;
         chosen.dir    = dir;
         chosen.top    = sw.price;
         chosen.bottom = sw.price;
         chosen.time   = sw.time;
         return true;
      }
      return false;
   }

   bool obHit = false, fvgHit = false;
   Zone obZone, fvgZone;

   if(needOB)
   {
      for(int i = 0; i < MAX_ZONES; i++)
      {
         if(!g_orderBlocks[i].valid || g_orderBlocks[i].dir != dir) continue;
         if(RangesOverlap(barLow, barHigh, g_orderBlocks[i].bottom, g_orderBlocks[i].top))
         { obHit = true; obZone = g_orderBlocks[i]; break; }
      }
   }
   if(needFVG)
   {
      for(int i = 0; i < MAX_ZONES; i++)
      {
         if(!g_fvgs[i].valid || g_fvgs[i].dir != dir) continue;
         if(RangesOverlap(barLow, barHigh, g_fvgs[i].bottom, g_fvgs[i].top))
         { fvgHit = true; fvgZone = g_fvgs[i]; break; }
      }
   }

   if(needOB && needFVG)
   {
      if(obHit && fvgHit)   // both — strongest confluence, prefer the OB for the stop
      { chosen = obZone; return true; }
      return false;
   }
   if(needOB  && obHit)  { chosen = obZone;  return true; }
   if(needFVG && fvgHit) { chosen = fvgZone; return true; }
   return false;
}

bool RangesOverlap(double aLow, double aHigh, double bLow, double bHigh)
{
   return (aLow <= bHigh && aHigh >= bLow);
}

//======================================================================
// RISK — stops, targets, sizing
//======================================================================
double AvgRange(const MqlRates &rates[], int n)
{
   int cnt = MathMin(AVG_RANGE_PERIOD, n - 1);
   if(cnt <= 0) return 0;
   double sum = 0;
   for(int i = 1; i <= cnt; i++)
      sum += (rates[i].high - rates[i].low);
   return sum / cnt;
}

double ZoneStop(const Zone &z, int dir, const MqlRates &rates[], int n)
{
   double buffer = AvgRange(rates, n) * InpSL_BufferPct;
   if(dir == +1)
      return z.bottom - buffer;    // below demand zone
   else
      return z.top + buffer;       // above supply zone
}

double TakeProfit(int dir, double entry, double sl, const MqlRates &rates[])
{
   // Primary target: opposing liquidity (nearest opposite swing).
   SwingPoint sw;
   double risk = MathAbs(entry - sl);
   double tp;

   if(dir == +1)
   {
      if(GetSwing(+1, 0, sw) && sw.price > entry)
         tp = sw.price;
      else
         tp = entry + risk * InpMinRR;
      // ensure at least the minimum RR
      if(tp < entry + risk * InpMinRR) tp = entry + risk * InpMinRR;
   }
   else
   {
      if(GetSwing(-1, 0, sw) && sw.price < entry)
         tp = sw.price;
      else
         tp = entry - risk * InpMinRR;
      if(tp > entry - risk * InpMinRR) tp = entry - risk * InpMinRR;
   }
   return tp;
}

bool RRAcceptable(double entry, double sl, double tp)
{
   double risk   = MathAbs(entry - sl);
   double reward = MathAbs(tp - entry);
   if(risk <= 0) return false;
   return (reward / risk >= InpMinRR);
}

double CalcLot(double entry, double sl)
{
   if(InpFixedLot > 0) return NormalizeLot(InpFixedLot);

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskCash = equity * InpRiskPercent / 100.0;

   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0) return NormalizeLot(0);

   double slDist   = MathAbs(entry - sl);
   double ticks    = slDist / tickSize;
   double lossPerLot = ticks * tickVal;
   if(lossPerLot <= 0) return NormalizeLot(0);

   double lot = riskCash / lossPerLot;
   return NormalizeLot(lot);
}

double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;

   lot = MathFloor(lot / step) * step;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return NormalizeDouble(lot, 2);
}

//======================================================================
// ORDER EXECUTION
//======================================================================
void OpenTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp)
{
   double lot = CalcLot(price, sl);
   if(lot <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // respect broker minimum stop distance
   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(MathAbs(price - sl) < stopLevel || MathAbs(tp - price) < stopLevel)
      return;

   bool ok;
   if(type == ORDER_TYPE_BUY)
      ok = trade.Buy(lot, _Symbol, price, sl, tp, InpTradeComment);
   else
      ok = trade.Sell(lot, _Symbol, price, sl, tp, InpTradeComment);

   if(ok)
      PrintFormat("%s %.2f lots @ %.5f  SL %.5f  TP %.5f",
                  EnumToString(type), lot, price, sl, tp);
   else
      PrintFormat("Order failed: %d %s", trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
}

//======================================================================
// POSITION MANAGEMENT — breakeven & trailing (price-action based)
//======================================================================
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!posinfo.SelectByTicket(ticket)) continue;
      if(posinfo.Magic() != InpMagic)      continue;
      if(posinfo.Symbol() != _Symbol)      continue;

      double entry = posinfo.PriceOpen();
      double sl    = posinfo.StopLoss();
      double tp    = posinfo.TakeProfit();
      long   type  = posinfo.PositionType();

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double cur = (type == POSITION_TYPE_BUY) ? bid : ask;

      double risk = MathAbs(entry - sl);
      if(risk <= 0) continue;
      double rMultiple = (type == POSITION_TYPE_BUY) ? (cur - entry) / risk
                                                     : (entry - cur) / risk;

      double newSL = sl;

      // breakeven at +1R
      if(InpUseBreakeven && rMultiple >= 1.0)
      {
         if(type == POSITION_TYPE_BUY  && sl < entry) newSL = entry;
         if(type == POSITION_TYPE_SELL && sl > entry) newSL = entry;
      }

      // trailing after threshold — trail behind the current bar structure
      if(InpUseTrailing && rMultiple >= InpTrailStartR)
      {
         double lockDist = risk * (rMultiple - 1.0);
         if(type == POSITION_TYPE_BUY)
         {
            double t = entry + lockDist;
            if(t > newSL) newSL = t;
         }
         else
         {
            double t = entry - lockDist;
            if(t < newSL) newSL = t;
         }
      }

      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      newSL = NormalizeDouble(newSL, digits);
      if(MathAbs(newSL - sl) > _Point)
         trade.PositionModify(ticket, newSL, tp);
   }
}

//======================================================================
// HELPERS
//======================================================================
int CountOwnPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!posinfo.SelectByTicket(ticket)) continue;
      if(posinfo.Magic() == InpMagic && posinfo.Symbol() == _Symbol) c++;
   }
   return c;
}
//+------------------------------------------------------------------+
