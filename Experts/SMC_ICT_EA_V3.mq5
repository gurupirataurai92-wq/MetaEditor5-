//+------------------------------------------------------------------+
//|                                                 SMC_ICT_EA_V3.mq5 |
//|         Smart Money Concepts / ICT price-action Expert Advisor    |
//|      Zero indicators. Structure, order blocks, FVG, liquidity.    |
//+------------------------------------------------------------------+
#property copyright "Quant Systems"
#property version   "3.00"
#property description "Pure price-action EA built on Smart Money Concepts and ICT."
#property description "No indicators of any kind - every decision derives from raw"
#property description "candle geometry: market structure (BOS/CHoCH), order blocks,"
#property description "fair value gaps, liquidity sweeps, premium/discount dealing"
#property description "ranges, and ICT killzones. Entries on M5. Includes a basket"
#property description "manager for portfolio-level profit/loss control."

#include <Trade\Trade.mqh>

//======================================================================
// INPUTS
//======================================================================
input group "=== Symbols & Account ==="
input string Watchlist           = "XAUUSD";       // comma separated; broker suffix auto-detected
input double RiskPercent         = 1.0;            // risk per trade, % of equity
input double MinAccountUSD       = 2.0;
input int    MagicBase           = 20260801;
input int    MaxConcurrentTrades = 3;

input group "=== Structure (SMC) ==="
input ENUM_TIMEFRAMES EntryTF    = PERIOD_M5;      // entry timeframe
input ENUM_TIMEFRAMES BiasTF     = PERIOD_H1;      // higher-timeframe bias
input int    SwingStrength       = 2;              // bars each side required to confirm a swing
input int    StructureLookback   = 300;            // entry-TF bars scanned for structure
input bool   RequireHTFBias      = true;           // only trade with the HTF structural trend
input bool   RequireBOS          = true;           // require a break of structure before entry

input group "=== Points of Interest ==="
input bool   UseOrderBlocks      = true;           // enter on mitigation of an order block
input bool   UseFairValueGaps    = true;           // enter on a fair value gap retrace
input int    POILookback         = 60;             // entry-TF bars scanned for OB / FVG
input bool   RequireUnmitigated  = true;           // ignore POIs price has already traded back through

input group "=== Liquidity & Premium/Discount ==="
input bool   UseLiquiditySweep   = true;           // require a stop-hunt wick before entry
input bool   UsePremiumDiscount  = true;           // buy only in discount, sell only in premium
input double EquilibriumBuffer   = 0.0;            // shift equilibrium, fraction of range (0 = midpoint)

input group "=== ICT Killzones (UTC) ==="
input bool   UseKillzones        = false;          // restrict entries to killzone windows
input int    LondonKZStart       = 7;
input int    LondonKZEnd         = 10;
input int    NewYorkKZStart      = 12;
input int    NewYorkKZEnd        = 15;

input group "=== Trade Placement ==="
input double SLBufferPoints      = 20;             // extra points beyond the structural stop
input double MinRRRatio          = 1.5;            // 0 = disabled
input bool   TargetOppositeLiq   = true;           // TP at the opposing liquidity pool
input double FallbackRR          = 2.0;            // TP = this x risk when no liquidity target exists

input group "=== Position Management ==="
input bool   UseBreakeven        = true;
input double BreakevenAtR        = 1.0;            // move SL to entry once this many R in profit
input bool   UsePartialClose     = true;
input double PartialAtR          = 1.0;
input double PartialPercent      = 50.0;
input bool   UseTrailing         = true;
input double TrailStartR         = 2.0;
input double TrailGivebackPct    = 50.0;           // give back this % of open profit

input group "=== Basket Manager ==="
input bool   UseBasketManager    = true;
input double BasketTPPercent     = 2.0;            // close ALL at +% of equity (0 = off)
input double BasketSLPercent     = 3.0;            // close ALL at -% of equity (0 = off)
input double BasketTrailStartPct = 1.5;            // arm basket trailing at +% of equity (0 = off)
input double BasketTrailGiveback = 40.0;           // close ALL after giving back % of peak basket profit
input int    BasketMaxPositions  = 10;             // hard ceiling on open managed positions

input group "=== Safety ==="
input bool   UseSpreadFilter     = true;
input double MaxSpreadRangePct   = 25.0;           // reject when spread > % of average entry-TF range
input int    DiagnosticMins      = 5;              // rejection tally interval (0 = off)

//======================================================================
// CONSTANTS
//======================================================================
#define MAX_SYMBOLS            32
#define AVG_RANGE_BARS         20
#define MIN_BARS_REQUIRED      50
#define BASKET_RESET_EPSILON   0.0000001

//======================================================================
// STRUCTS
//======================================================================
struct MarketStructure
{
   bool     Valid;
   double   SwingHigh1, SwingHigh2;   // 1 = most recent
   double   SwingLow1,  SwingLow2;
   int      SwingHigh1Idx, SwingLow1Idx;
   double   RangeHigh, RangeLow, Equilibrium;
   int      Trend;                    // 1 bullish, -1 bearish, 0 undefined
   bool     BOS;                      // break of structure in trend direction
   bool     CHOCH;                    // change of character (structure flip)
};

struct POI                            // point of interest: order block or FVG
{
   bool     Valid;
   double   Top, Bottom;
   int      Direction;                // 1 bullish, -1 bearish
   int      BarIndex;
   string   Kind;                     // "OB" or "FVG"
};

struct SymbolConfig
{
   string   Name;                     // broker-resolved, e.g. XAUUSD.m
   string   BaseName;                 // canonical, e.g. XAUUSD
   bool     Available;
   double   MinLot, LotStep, MaxLot;
   double   Point, TickSize, TickValue;
   int      Digits;
   datetime LastBarTime;
   int      TotalTrades, TotalWins;
   double   NetPnL;
};

struct OpenTradeState
{
   ulong    Ticket;
   int      Idx;
   double   RiskAmt;
   double   EntryPrice;
   double   SLDistance;
   bool     PartialDone;
   bool     BreakevenSet;
};

//======================================================================
// GLOBALS
//======================================================================
CTrade         trade;
SymbolConfig   g_cfg[];
OpenTradeState g_openTrades[];
string         g_watchSymbols[];
int            g_symbolCount = 0;

double         g_basketPeakProfit = 0.0;
datetime       g_lastDiagTime = 0;
int            g_entriesTaken = 0;
int            g_totalClosed  = 0;

enum ENUM_REJECT
{
   REJ_NO_BARS, REJ_STRUCTURE, REJ_NO_BOS, REJ_HTF_BIAS, REJ_KILLZONE,
   REJ_PREMIUM_DISCOUNT, REJ_NO_POI, REJ_NO_SWEEP, REJ_RR, REJ_SPREAD,
   REJ_MAXTRADES, REJ_BASKET_FULL, REJ_LOT, REJ_COUNT
};
int g_reject[REJ_COUNT];

string RejectName(int r)
{
   switch(r)
   {
      case REJ_NO_BARS:           return "insufficient bars";
      case REJ_STRUCTURE:         return "no valid structure";
      case REJ_NO_BOS:            return "no break of structure";
      case REJ_HTF_BIAS:          return "against HTF bias";
      case REJ_KILLZONE:          return "outside killzone";
      case REJ_PREMIUM_DISCOUNT:  return "wrong side of equilibrium";
      case REJ_NO_POI:            return "no unmitigated OB/FVG at price";
      case REJ_NO_SWEEP:          return "no liquidity sweep";
      case REJ_RR:                return "risk/reward too low";
      case REJ_SPREAD:            return "spread too wide";
      case REJ_MAXTRADES:         return "max concurrent trades";
      case REJ_BASKET_FULL:       return "basket position ceiling";
      case REJ_LOT:               return "lot below broker minimum";
   }
   return "unknown";
}

//======================================================================
// SYMBOL RESOLUTION
//======================================================================
string DetectBrokerSuffix()
{
   string chartSym = _Symbol;
   for(int i = 0; i < g_symbolCount; i++)
   {
      string base = g_watchSymbols[i];
      int baseLen = StringLen(base);
      if(StringLen(chartSym) > baseLen && StringFind(chartSym, base) == 0)
         return StringSubstr(chartSym, baseLen);
   }
   return "";
}

bool ResolveSymbolName(string base, string suffix, string &resolved)
{
   if(SymbolSelect(base, true)) { resolved = base; return true; }
   if(suffix != "")
   {
      string withSuffix = base + suffix;
      if(SymbolSelect(withSuffix, true)) { resolved = withSuffix; return true; }
   }
   resolved = base;
   return false;
}

int FindCfgIndex(string symbol)
{
   for(int i = 0; i < g_symbolCount; i++)
      if(g_cfg[i].Name == symbol) return i;
   return -1;
}

int FindOpenTradeState(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_openTrades); i++)
      if(g_openTrades[i].Ticket == ticket) return i;
   return -1;
}

void RemoveOpenTradeState(ulong ticket)
{
   int idx = FindOpenTradeState(ticket);
   if(idx < 0) return;
   int last = ArraySize(g_openTrades) - 1;
   g_openTrades[idx] = g_openTrades[last];
   ArrayResize(g_openTrades, last);
}

void PushOpenTradeState(OpenTradeState &st)
{
   int n = ArraySize(g_openTrades);
   ArrayResize(g_openTrades, n + 1);
   g_openTrades[n] = st;
}

//======================================================================
// PRICE ACTION PRIMITIVES (no indicators - candle geometry only)
//======================================================================

// Average high-low range over recent bars. Used only for spread sanity
// and minimum-distance checks - it is a direct candle measurement, not
// a smoothed indicator.
double AverageRange(string symbol, ENUM_TIMEFRAMES tf, int bars)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(symbol, tf, 0, bars, r) < bars) return 0.0;
   double sum = 0.0;
   for(int i = 0; i < bars; i++) sum += (r[i].high - r[i].low);
   return sum / bars;
}

// Fractal swing high: bars[i].high strictly greater than `strength` highs
// on both sides. Series-indexed, so i-k is newer and i+k is older.
bool IsSwingHigh(const MqlRates &r[], int total, int i, int strength)
{
   if(i - strength < 0 || i + strength >= total) return false;
   double h = r[i].high;
   for(int k = 1; k <= strength; k++)
      if(h <= r[i - k].high || h <= r[i + k].high) return false;
   return true;
}

bool IsSwingLow(const MqlRates &r[], int total, int i, int strength)
{
   if(i - strength < 0 || i + strength >= total) return false;
   double l = r[i].low;
   for(int k = 1; k <= strength; k++)
      if(l >= r[i - k].low || l >= r[i + k].low) return false;
   return true;
}

// Collect the N most recent confirmed swings, newest first.
int CollectSwingHighs(const MqlRates &r[], int total, int strength, int wanted,
                      double &prices[], int &indices[])
{
   ArrayResize(prices, wanted);
   ArrayResize(indices, wanted);
   int found = 0;
   for(int i = strength; i < total - strength && found < wanted; i++)
   {
      if(IsSwingHigh(r, total, i, strength))
      {
         prices[found]  = r[i].high;
         indices[found] = i;
         found++;
      }
   }
   return found;
}

int CollectSwingLows(const MqlRates &r[], int total, int strength, int wanted,
                     double &prices[], int &indices[])
{
   ArrayResize(prices, wanted);
   ArrayResize(indices, wanted);
   int found = 0;
   for(int i = strength; i < total - strength && found < wanted; i++)
   {
      if(IsSwingLow(r, total, i, strength))
      {
         prices[found]  = r[i].low;
         indices[found] = i;
         found++;
      }
   }
   return found;
}

//======================================================================
// MARKET STRUCTURE: BOS / CHoCH / dealing range
//======================================================================
MarketStructure BuildStructure(string symbol, ENUM_TIMEFRAMES tf, int lookback)
{
   MarketStructure ms;
   ZeroMemory(ms);
   ms.Valid = false;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(symbol, tf, 0, lookback, r);
   if(copied < MIN_BARS_REQUIRED) return ms;

   double sh[], sl[];
   int shIdx[], slIdx[];
   int nHighs = CollectSwingHighs(r, copied, SwingStrength, 2, sh, shIdx);
   int nLows  = CollectSwingLows(r, copied, SwingStrength, 2, sl, slIdx);
   if(nHighs < 2 || nLows < 2) return ms;

   ms.SwingHigh1 = sh[0]; ms.SwingHigh2 = sh[1];
   ms.SwingLow1  = sl[0]; ms.SwingLow2  = sl[1];
   ms.SwingHigh1Idx = shIdx[0];
   ms.SwingLow1Idx  = slIdx[0];

   // Dealing range spans the most recent opposing swings.
   ms.RangeHigh = MathMax(sh[0], sh[1]);
   ms.RangeLow  = MathMin(sl[0], sl[1]);
   double range = ms.RangeHigh - ms.RangeLow;
   if(range <= 0.0) return ms;
   ms.Equilibrium = ms.RangeLow + range * (0.5 + EquilibriumBuffer);

   // Structural trend from swing sequencing: HH+HL bullish, LH+LL bearish.
   bool higherHigh = (sh[0] > sh[1]);
   bool higherLow  = (sl[0] > sl[1]);
   bool lowerHigh  = (sh[0] < sh[1]);
   bool lowerLow   = (sl[0] < sl[1]);

   if(higherHigh && higherLow)      ms.Trend = 1;
   else if(lowerHigh && lowerLow)   ms.Trend = -1;
   else                              ms.Trend = 0;

   // BOS: most recent closed candle closed beyond the last swing in the
   // direction of trend. CHoCH: closed beyond the opposing swing, flipping
   // character. Index 1 is the last CLOSED bar (0 is still forming).
   double lastClose = r[1].close;
   if(lastClose > ms.SwingHigh1)
   {
      if(ms.Trend >= 0) ms.BOS = true;
      else { ms.CHOCH = true; ms.Trend = 1; }
   }
   else if(lastClose < ms.SwingLow1)
   {
      if(ms.Trend <= 0) ms.BOS = true;
      else { ms.CHOCH = true; ms.Trend = -1; }
   }

   ms.Valid = true;
   return ms;
}

// Higher-timeframe directional bias from the same structural rules.
int GetHTFBias(string symbol)
{
   MarketStructure hs = BuildStructure(symbol, BiasTF, StructureLookback);
   if(!hs.Valid) return 0;
   return hs.Trend;
}

//======================================================================
// ORDER BLOCKS
// The last opposing candle before the displacement leg that broke
// structure. Bullish OB = last down-candle before the up-move.
//======================================================================
POI FindOrderBlock(const MqlRates &r[], int total, int direction, int searchFrom, int lookback)
{
   POI p;
   ZeroMemory(p);
   p.Valid = false;
   p.Kind = "OB";
   p.Direction = direction;

   int limit = MathMin(searchFrom + lookback, total - 1);
   for(int i = searchFrom; i <= limit; i++)
   {
      bool isOpposing = (direction > 0) ? (r[i].close < r[i].open)   // down-candle before up-move
                                        : (r[i].close > r[i].open);  // up-candle before down-move
      if(!isOpposing) continue;

      p.Top    = r[i].high;
      p.Bottom = r[i].low;
      p.BarIndex = i;
      p.Valid = true;
      return p;
   }
   return p;
}

//======================================================================
// FAIR VALUE GAPS (imbalance)
// Bullish FVG: candle1.high < candle3.low, leaving an untraded gap.
// Series indexing: c3 = r[i] (newest), c2 = r[i+1], c1 = r[i+2].
//======================================================================
POI FindFVG(const MqlRates &r[], int total, int direction, int lookback)
{
   POI p;
   ZeroMemory(p);
   p.Valid = false;
   p.Kind = "FVG";
   p.Direction = direction;

   int limit = MathMin(lookback, total - 3);
   for(int i = 1; i <= limit; i++)
   {
      if(direction > 0)
      {
         if(r[i + 2].high < r[i].low)
         {
            p.Bottom = r[i + 2].high;
            p.Top    = r[i].low;
            p.BarIndex = i;
            p.Valid = true;
            return p;
         }
      }
      else
      {
         if(r[i + 2].low > r[i].high)
         {
            p.Top    = r[i + 2].low;
            p.Bottom = r[i].high;
            p.BarIndex = i;
            p.Valid = true;
            return p;
         }
      }
   }
   return p;
}

// A POI is mitigated once price has traded back through its far edge
// since it formed.
bool IsPOIMitigated(const MqlRates &r[], int total, const POI &p)
{
   if(!p.Valid) return true;
   for(int i = p.BarIndex - 1; i >= 1; i--)
   {
      if(i < 0 || i >= total) continue;
      if(p.Direction > 0 && r[i].low  < p.Bottom) return true;
      if(p.Direction < 0 && r[i].high > p.Top)    return true;
   }
   return false;
}

bool PriceInPOI(double price, const POI &p)
{
   if(!p.Valid) return false;
   return (price >= p.Bottom && price <= p.Top);
}

//======================================================================
// LIQUIDITY SWEEP (stop hunt)
// Wick takes out a prior swing then the candle closes back inside -
// engineered liquidity taken before the real move.
//======================================================================
bool DetectLiquiditySweep(const MqlRates &r[], int total, int direction,
                          double swingHigh, double swingLow, int barsBack)
{
   int limit = MathMin(barsBack, total - 1);
   for(int i = 1; i <= limit; i++)
   {
      if(direction > 0)
      {
         // Sell-side liquidity swept below a swing low, then reclaimed.
         if(r[i].low < swingLow && r[i].close > swingLow) return true;
      }
      else
      {
         // Buy-side liquidity swept above a swing high, then rejected.
         if(r[i].high > swingHigh && r[i].close < swingHigh) return true;
      }
   }
   return false;
}

//======================================================================
// ICT KILLZONES
//======================================================================
bool InKillzone()
{
   if(!UseKillzones) return true;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   if(h >= LondonKZStart && h < LondonKZEnd) return true;
   if(h >= NewYorkKZStart && h < NewYorkKZEnd) return true;
   return false;
}

//======================================================================
// MONEY / SIZING
//======================================================================
double PointValueMoney(int idx)
{
   if(g_cfg[idx].TickSize <= 0.0 || g_cfg[idx].TickValue <= 0.0) return 0.0;
   return (g_cfg[idx].TickValue / g_cfg[idx].TickSize) * g_cfg[idx].Point;
}

double PriceDistanceToMoney(int idx, double priceDist, double volume)
{
   double pt = g_cfg[idx].Point;
   if(pt <= 0.0) return 0.0;
   return (priceDist / pt) * PointValueMoney(idx) * volume;
}

double CalculateLot(int idx, double slDistance, double &riskAmtOut)
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt = equity * (RiskPercent / 100.0);
   riskAmtOut = riskAmt;

   double ptVal = PointValueMoney(idx);
   if(ptVal <= 0.0 || slDistance <= 0.0) return 0.0;

   double moneyPerLot = (slDistance / g_cfg[idx].Point) * ptVal;
   if(moneyPerLot <= 0.0) return 0.0;

   double rawLot = riskAmt / moneyPerLot;
   double step   = g_cfg[idx].LotStep;
   if(step <= 0.0) return 0.0;

   double lot = MathFloor(rawLot / step) * step;
   lot = MathMax(lot, g_cfg[idx].MinLot);
   lot = MathMin(lot, g_cfg[idx].MaxLot);
   if(lot < g_cfg[idx].MinLot) return 0.0;
   return lot;
}

int CountManagedPositions()
{
   int c = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      long m = PositionGetInteger(POSITION_MAGIC);
      if(m >= MagicBase && m < MagicBase + g_symbolCount) c++;
   }
   return c;
}

//======================================================================
// SIGNAL ENGINE
//======================================================================
bool BuildSignal(int idx, int &outDir, double &outSL, double &outTP, string &outReason)
{
   string sym = g_cfg[idx].Name;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(sym, EntryTF, 0, StructureLookback, r);
   if(copied < MIN_BARS_REQUIRED) { g_reject[REJ_NO_BARS]++; return false; }

   MarketStructure ms = BuildStructure(sym, EntryTF, StructureLookback);
   if(!ms.Valid) { g_reject[REJ_STRUCTURE]++; return false; }

   int dir = ms.Trend;
   if(dir == 0) { g_reject[REJ_STRUCTURE]++; return false; }

   if(RequireBOS && !ms.BOS && !ms.CHOCH) { g_reject[REJ_NO_BOS]++; return false; }

   if(RequireHTFBias)
   {
      int htf = GetHTFBias(sym);
      if(htf == 0 || htf != dir) { g_reject[REJ_HTF_BIAS]++; return false; }
   }

   if(!InKillzone()) { g_reject[REJ_KILLZONE]++; return false; }

   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;
   double entryPrice = (dir > 0) ? ask : bid;

   // Premium / discount: buy only below equilibrium, sell only above.
   if(UsePremiumDiscount)
   {
      if(dir > 0 && entryPrice > ms.Equilibrium) { g_reject[REJ_PREMIUM_DISCOUNT]++; return false; }
      if(dir < 0 && entryPrice < ms.Equilibrium) { g_reject[REJ_PREMIUM_DISCOUNT]++; return false; }
   }

   // Point of interest: order block first, then fair value gap.
   POI poi;
   ZeroMemory(poi);
   poi.Valid = false;

   if(UseOrderBlocks)
   {
      int searchFrom = (dir > 0) ? ms.SwingLow1Idx : ms.SwingHigh1Idx;
      if(searchFrom < 1) searchFrom = 1;
      POI ob = FindOrderBlock(r, copied, dir, searchFrom, POILookback);
      if(ob.Valid && (!RequireUnmitigated || !IsPOIMitigated(r, copied, ob)))
         poi = ob;
   }

   if(!poi.Valid && UseFairValueGaps)
   {
      POI fvg = FindFVG(r, copied, dir, POILookback);
      if(fvg.Valid && (!RequireUnmitigated || !IsPOIMitigated(r, copied, fvg)))
         poi = fvg;
   }

   if(!poi.Valid) { g_reject[REJ_NO_POI]++; return false; }

   // Entry requires price to be trading inside the POI (mitigation tap).
   if(!PriceInPOI(entryPrice, poi)) { g_reject[REJ_NO_POI]++; return false; }

   // Liquidity sweep confirmation.
   if(UseLiquiditySweep &&
      !DetectLiquiditySweep(r, copied, dir, ms.SwingHigh1, ms.SwingLow1, POILookback))
   {
      g_reject[REJ_NO_SWEEP]++;
      return false;
   }

   // Stop beyond the POI's far edge, plus buffer. This is the structural
   // invalidation: if price trades through the block, the idea is wrong.
   double buffer = SLBufferPoints * g_cfg[idx].Point;
   double sl = (dir > 0) ? (poi.Bottom - buffer) : (poi.Top + buffer);
   double riskDist = MathAbs(entryPrice - sl);
   if(riskDist <= 0.0) return false;

   // Target the opposing liquidity pool, else a fixed R multiple.
   double tp;
   if(TargetOppositeLiq)
      tp = (dir > 0) ? ms.RangeHigh : ms.RangeLow;
   else
      tp = (dir > 0) ? entryPrice + riskDist * FallbackRR : entryPrice - riskDist * FallbackRR;

   double rewardDist = MathAbs(tp - entryPrice);
   if(rewardDist <= 0.0 || (dir > 0 && tp <= entryPrice) || (dir < 0 && tp >= entryPrice))
      tp = (dir > 0) ? entryPrice + riskDist * FallbackRR : entryPrice - riskDist * FallbackRR;

   rewardDist = MathAbs(tp - entryPrice);
   if(MinRRRatio > 0.0 && (rewardDist / riskDist) < MinRRRatio)
   {
      g_reject[REJ_RR]++;
      return false;
   }

   outDir = dir;
   outSL = sl;
   outTP = tp;
   outReason = poi.Kind + (ms.CHOCH ? "+CHoCH" : "+BOS");
   return true;
}

//======================================================================
// EXECUTION
//======================================================================
// Brokers reject orders whose SL/TP sits closer to price than the stops
// level. Structural SMC stops are often tight enough to trip this, so push
// them out to the minimum and let lot sizing absorb the wider stop - that
// keeps the money risked per trade constant instead of silently inflating it.
void EnforceStopsLevel(int idx, int dir, double price, double &sl, double &tp)
{
   string sym = g_cfg[idx].Name;
   double pt = g_cfg[idx].Point;
   long stopsPts = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsPts <= 0) return;

   double minDist = stopsPts * pt;

   if(dir > 0)
   {
      if(price - sl < minDist) sl = price - minDist;
      if(tp - price < minDist) tp = price + minDist;
   }
   else
   {
      if(sl - price < minDist) sl = price + minDist;
      if(price - tp < minDist) tp = price - minDist;
   }
}

bool OpenTrade(int idx, int dir, double sl, double tp, string reason)
{
   string sym = g_cfg[idx].Name;
   trade.SetExpertMagicNumber((ulong)(MagicBase + idx));
   trade.SetDeviationInPoints(20);

   double price = (dir > 0) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   if(price <= 0.0) return false;

   EnforceStopsLevel(idx, dir, price, sl, tp);

   double slDist = MathAbs(price - sl);
   if(slDist <= 0.0) return false;

   // Re-check R:R after any stops-level adjustment widened the stop.
   if(MinRRRatio > 0.0 && (MathAbs(tp - price) / slDist) < MinRRRatio)
   {
      g_reject[REJ_RR]++;
      return false;
   }

   double riskAmt;
   double lot = CalculateLot(idx, slDist, riskAmt);
   if(lot <= 0.0) { g_reject[REJ_LOT]++; return false; }

   int digits = g_cfg[idx].Digits;
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   bool ok = (dir > 0) ? trade.Buy(lot, sym, price, sl, tp, "SMC " + reason)
                       : trade.Sell(lot, sym, price, sl, tp, "SMC " + reason);
   if(!ok)
   {
      PrintFormat("Order failed [%s] retcode=%d %s", sym, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
   }

   ulong ticket = trade.ResultOrder();
   OpenTradeState st;
   st.Ticket = ticket;
   st.Idx = idx;
   st.RiskAmt = riskAmt;
   st.EntryPrice = price;
   st.SLDistance = slDist;
   st.PartialDone = false;
   st.BreakevenSet = false;
   PushOpenTradeState(st);

   PrintFormat("ENTRY [%s] %s lot=%.2f @ %.*f SL=%.*f TP=%.*f RR=%.2f (%s)",
               sym, dir > 0 ? "BUY" : "SELL", lot, digits, price, digits, sl, digits, tp,
               MathAbs(tp - price) / slDist, reason);
   return true;
}

//======================================================================
// POSITION MANAGEMENT
//======================================================================
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic < MagicBase || magic >= MagicBase + g_symbolCount) continue;
      int idx = (int)(magic - MagicBase);
      if(idx < 0 || idx >= g_symbolCount) continue;

      string sym  = PositionGetString(POSITION_SYMBOL);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double pt = g_cfg[idx].Point;
      int digits = g_cfg[idx].Digits;

      int stIdx = FindOpenTradeState(ticket);
      if(stIdx < 0) continue;
      double riskAmt = g_openTrades[stIdx].RiskAmt;
      if(riskAmt <= 0.0) continue;

      double curPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID)
                                                    : SymbolInfoDouble(sym, SYMBOL_ASK);

      // Partial close at target R
      if(UsePartialClose && !g_openTrades[stIdx].PartialDone && profit >= riskAmt * PartialAtR)
      {
         double closeVol = MathFloor((volume * PartialPercent / 100.0) / g_cfg[idx].LotStep) * g_cfg[idx].LotStep;
         if(closeVol >= g_cfg[idx].MinLot && closeVol < volume)
         {
            if(trade.PositionClosePartial(ticket, closeVol))
            {
               g_openTrades[stIdx].PartialDone = true;
               PrintFormat("Partial close %.0f%% at %.1fR [%s]", PartialPercent, PartialAtR, sym);
            }
         }
      }

      // Breakeven
      if(UseBreakeven && !g_openTrades[stIdx].BreakevenSet && profit >= riskAmt * BreakevenAtR)
      {
         double beSL = (type == POSITION_TYPE_BUY) ? entry + pt : entry - pt;
         bool improves = (type == POSITION_TYPE_BUY) ? (beSL > curSL) : (curSL == 0.0 || beSL < curSL);
         if(improves && trade.PositionModify(ticket, NormalizeDouble(beSL, digits), curTP))
         {
            g_openTrades[stIdx].BreakevenSet = true;
            PrintFormat("Breakeven set [%s]", sym);
         }
      }

      // Trailing stop
      if(UseTrailing && profit >= riskAmt * TrailStartR)
      {
         double profitDist = MathAbs(curPrice - entry);
         double giveback   = profitDist * (TrailGivebackPct / 100.0);
         double trailSL = (type == POSITION_TYPE_BUY) ? curPrice - giveback : curPrice + giveback;
         bool improves = (type == POSITION_TYPE_BUY) ? (trailSL > curSL) : (curSL == 0.0 || trailSL < curSL);
         if(improves) trade.PositionModify(ticket, NormalizeDouble(trailSL, digits), curTP);
      }
   }
}

//======================================================================
// BASKET MANAGER
// Treats every open managed position as one portfolio-level trade.
//======================================================================
double BasketProfit(int &countOut)
{
   double total = 0.0;
   countOut = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      long m = PositionGetInteger(POSITION_MAGIC);
      if(m < MagicBase || m >= MagicBase + g_symbolCount) continue;
      total += PositionGetDouble(POSITION_PROFIT)
             + PositionGetDouble(POSITION_SWAP);
      countOut++;
   }
   return total;
}

void CloseAllManaged(string reason)
{
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      long m = PositionGetInteger(POSITION_MAGIC);
      if(m < MagicBase || m >= MagicBase + g_symbolCount) continue;
      if(trade.PositionClose(t))
      {
         RemoveOpenTradeState(t);
         closed++;
      }
   }
   if(closed > 0)
      PrintFormat("BASKET: closed %d position(s) - %s", closed, reason);
}

void ManageBasket()
{
   if(!UseBasketManager) return;

   int count;
   double profit = BasketProfit(count);

   if(count == 0)
   {
      g_basketPeakProfit = 0.0;
      return;
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0) return;

   // Hard take profit on the basket
   if(BasketTPPercent > 0.0 && profit >= equity * (BasketTPPercent / 100.0))
   {
      CloseAllManaged(StringFormat("take profit %.2f >= %.2f%% equity", profit, BasketTPPercent));
      g_basketPeakProfit = 0.0;
      return;
   }

   // Hard stop loss on the basket
   if(BasketSLPercent > 0.0 && profit <= -equity * (BasketSLPercent / 100.0))
   {
      CloseAllManaged(StringFormat("stop loss %.2f <= -%.2f%% equity", profit, BasketSLPercent));
      g_basketPeakProfit = 0.0;
      return;
   }

   // Trailing on aggregate basket profit
   if(profit > g_basketPeakProfit) g_basketPeakProfit = profit;

   if(BasketTrailStartPct > 0.0 && BasketTrailGiveback > 0.0 &&
      g_basketPeakProfit >= equity * (BasketTrailStartPct / 100.0))
   {
      double giveback = g_basketPeakProfit * (BasketTrailGiveback / 100.0);
      if(profit <= g_basketPeakProfit - giveback)
      {
         CloseAllManaged(StringFormat("trail: peak %.2f, now %.2f", g_basketPeakProfit, profit));
         g_basketPeakProfit = 0.0;
      }
   }
}

//======================================================================
// SPREAD FILTER (measured against candle range, not an indicator)
//======================================================================
bool SpreadAcceptable(int idx)
{
   if(!UseSpreadFilter) return true;
   string sym = g_cfg[idx].Name;
   double spread = SymbolInfoInteger(sym, SYMBOL_SPREAD) * g_cfg[idx].Point;
   double avgRange = AverageRange(sym, EntryTF, AVG_RANGE_BARS);
   if(avgRange <= 0.0) return true;
   return (spread <= avgRange * (MaxSpreadRangePct / 100.0));
}

//======================================================================
// PER-SYMBOL PROCESSING
//======================================================================
void ProcessSymbol(int idx)
{
   if(!g_cfg[idx].Available) return;
   string sym = g_cfg[idx].Name;

   // One evaluation per closed entry-TF bar.
   datetime barTime = iTime(sym, EntryTF, 0);
   if(barTime == 0 || barTime == g_cfg[idx].LastBarTime) return;
   g_cfg[idx].LastBarTime = barTime;

   if(CountManagedPositions() >= MaxConcurrentTrades) { g_reject[REJ_MAXTRADES]++; return; }
   if(UseBasketManager && CountManagedPositions() >= BasketMaxPositions)
   {
      g_reject[REJ_BASKET_FULL]++;
      return;
   }
   if(!SpreadAcceptable(idx)) { g_reject[REJ_SPREAD]++; return; }

   int dir; double sl, tp; string reason;
   if(!BuildSignal(idx, dir, sl, tp, reason)) return;

   if(OpenTrade(idx, dir, sl, tp, reason))
      g_entriesTaken++;
}

//======================================================================
// DIAGNOSTICS
//======================================================================
void LogDiagnosticsIfDue()
{
   if(DiagnosticMins <= 0) return;
   if(TimeCurrent() - g_lastDiagTime < DiagnosticMins * 60) return;
   g_lastDiagTime = TimeCurrent();

   int total = 0;
   for(int r = 0; r < REJ_COUNT; r++) total += g_reject[r];

   string line = "";
   for(int r = 0; r < REJ_COUNT; r++)
      if(g_reject[r] > 0) line += StringFormat("%s=%d  ", RejectName(r), g_reject[r]);

   int openCount;
   double basket = BasketProfit(openCount);

   PrintFormat("DIAG (%d min): entries=%d rejections=%d open=%d basketPnL=%.2f | %s",
               DiagnosticMins, g_entriesTaken, total, openCount, basket,
               line == "" ? "(none)" : line);

   ArrayInitialize(g_reject, 0);
   g_entriesTaken = 0;
}

//======================================================================
// INIT
//======================================================================
void ParseWatchlist()
{
   string raw = Watchlist;
   StringReplace(raw, " ", "");
   StringReplace(raw, "\n", "");
   StringReplace(raw, "\t", "");
   ushort sep = StringGetCharacter(",", 0);
   g_symbolCount = StringSplit(raw, sep, g_watchSymbols);
   if(g_symbolCount > MAX_SYMBOLS) g_symbolCount = MAX_SYMBOLS;
   ArrayResize(g_cfg, g_symbolCount);
}

bool InitSymbol(int idx, string baseSym, string suffix)
{
   ZeroMemory(g_cfg[idx]);
   g_cfg[idx].BaseName = baseSym;

   string resolved;
   if(!ResolveSymbolName(baseSym, suffix, resolved))
   {
      g_cfg[idx].Name = baseSym;
      g_cfg[idx].Available = false;
      PrintFormat("Symbol unavailable: %s - skipped", baseSym);
      return false;
   }

   double minLot = SymbolInfoDouble(resolved, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(resolved, SYMBOL_VOLUME_STEP);
   double maxLot = SymbolInfoDouble(resolved, SYMBOL_VOLUME_MAX);
   double pt     = SymbolInfoDouble(resolved, SYMBOL_POINT);
   double tickSz = SymbolInfoDouble(resolved, SYMBOL_TRADE_TICK_SIZE);
   double tickVl = SymbolInfoDouble(resolved, SYMBOL_TRADE_TICK_VALUE);

   if(minLot <= 0.0 || step <= 0.0 || pt <= 0.0)
   {
      g_cfg[idx].Name = resolved;
      g_cfg[idx].Available = false;
      PrintFormat("Symbol %s returned invalid specs - skipped", resolved);
      return false;
   }

   g_cfg[idx].Name      = resolved;
   g_cfg[idx].Available = true;
   g_cfg[idx].MinLot    = minLot;
   g_cfg[idx].LotStep   = step;
   g_cfg[idx].MaxLot    = maxLot;
   g_cfg[idx].Point     = pt;
   g_cfg[idx].TickSize  = tickSz;
   g_cfg[idx].TickValue = tickVl;
   g_cfg[idx].Digits    = (int)SymbolInfoInteger(resolved, SYMBOL_DIGITS);
   return true;
}

int OnInit()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinAccountUSD)
   {
      PrintFormat("CRITICAL: balance %.2f below minimum %.2f", balance, MinAccountUSD);
      return INIT_FAILED;
   }

   if(SwingStrength < 1)
   {
      Print("CRITICAL: SwingStrength must be at least 1");
      return INIT_FAILED;
   }
   if(StructureLookback < MIN_BARS_REQUIRED)
   {
      PrintFormat("CRITICAL: StructureLookback must be at least %d", MIN_BARS_REQUIRED);
      return INIT_FAILED;
   }

   ParseWatchlist();
   if(g_symbolCount <= 0)
   {
      Print("CRITICAL: Watchlist is empty");
      return INIT_FAILED;
   }

   string suffix = DetectBrokerSuffix();
   if(suffix != "")
      PrintFormat("Broker suffix detected from '%s': '%s'", _Symbol, suffix);

   int available = 0;
   for(int i = 0; i < g_symbolCount; i++)
      if(InitSymbol(i, g_watchSymbols[i], suffix)) available++;

   if(available == 0)
   {
      Print("CRITICAL: no watchlist symbol could be resolved on this broker.");
      Print("Check Market Watch for the exact names your broker uses.");
      return INIT_FAILED;
   }

   EventSetTimer(1);

   Print("========== SMC / ICT EA v3.00 ==========");
   Print("  Indicators used ..... NONE (pure price action)");
   PrintFormat("  Entry timeframe ..... %s", EnumToString(EntryTF));
   PrintFormat("  Bias timeframe ...... %s", EnumToString(BiasTF));
   PrintFormat("  Symbols ............. %d of %d available", available, g_symbolCount);
   Print("  ---- Concepts ----");
   PrintFormat("  Break of structure .. %s", RequireBOS ? "REQUIRED" : "off");
   PrintFormat("  HTF bias filter ..... %s", RequireHTFBias ? "REQUIRED" : "off");
   PrintFormat("  Order blocks ........ %s", UseOrderBlocks ? "ON" : "off");
   PrintFormat("  Fair value gaps ..... %s", UseFairValueGaps ? "ON" : "off");
   PrintFormat("  Liquidity sweep ..... %s", UseLiquiditySweep ? "REQUIRED" : "off");
   PrintFormat("  Premium/discount .... %s", UsePremiumDiscount ? "ON" : "off");
   PrintFormat("  Killzones ........... %s", UseKillzones ? "ON" : "off");
   Print("  ---- Risk ----");
   PrintFormat("  Risk per trade ...... %.2f%%", RiskPercent);
   PrintFormat("  Minimum R:R ......... %s", MinRRRatio > 0.0 ? DoubleToString(MinRRRatio, 2) + ":1" : "off");
   PrintFormat("  Max concurrent ...... %d", MaxConcurrentTrades);
   Print("  ---- Basket ----");
   PrintFormat("  Basket manager ...... %s", UseBasketManager ? "ON" : "off");
   if(UseBasketManager)
   {
      PrintFormat("    take profit ....... %.2f%% equity", BasketTPPercent);
      PrintFormat("    stop loss ......... %.2f%% equity", BasketSLPercent);
      PrintFormat("    trail start ....... %.2f%% equity", BasketTrailStartPct);
      PrintFormat("    trail giveback .... %.2f%% of peak", BasketTrailGiveback);
      PrintFormat("    max positions ..... %d", BasketMaxPositions);
   }
   Print("========================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("========== SESSION SUMMARY ==========");
   for(int i = 0; i < g_symbolCount; i++)
   {
      if(!g_cfg[i].Available) continue;
      double wr = (g_cfg[i].TotalTrades > 0)
                  ? (double)g_cfg[i].TotalWins / (double)g_cfg[i].TotalTrades * 100.0 : 0.0;
      PrintFormat("[%s] trades=%d winrate=%.1f%% netPnL=%.2f",
                  g_cfg[i].Name, g_cfg[i].TotalTrades, wr, g_cfg[i].NetPnL);
   }
   PrintFormat("Total closed trades: %d", g_totalClosed);
   Print("=====================================");
}

//======================================================================
// EVENT HANDLERS
//======================================================================
void OnTick()
{
   ManageBasket();
   ManagePositions();

   int idx = FindCfgIndex(_Symbol);
   if(idx >= 0) ProcessSymbol(idx);
}

void OnTimer()
{
   ManageBasket();
   ManagePositions();

   for(int i = 0; i < g_symbolCount; i++)
      if(g_cfg[i].Available)
         ProcessSymbol(i);

   LogDiagnosticsIfDue();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY) return;

   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(magic < MagicBase || magic >= MagicBase + g_symbolCount) return;
   int idx = (int)(magic - MagicBase);
   if(idx < 0 || idx >= g_symbolCount) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   ulong posId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   RemoveOpenTradeState(posId);

   g_cfg[idx].TotalTrades++;
   if(profit > 0.0) g_cfg[idx].TotalWins++;
   g_cfg[idx].NetPnL += profit;
   g_totalClosed++;

   PrintFormat("CLOSED [%s] pnl=%.2f (total trades=%d)", g_cfg[idx].Name, profit, g_cfg[idx].TotalTrades);
}
//+------------------------------------------------------------------+
