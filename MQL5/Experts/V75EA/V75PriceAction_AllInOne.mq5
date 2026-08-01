//+------------------------------------------------------------------+
//|                                     V75PriceAction_AllInOne.mq5 |
//|  Single-file build — paste into MQL5/Experts, press F7.          |
//|                                                                  |
//|  Supply & demand + price action EA for Deriv Volatility 75.      |
//|  NO INDICATORS OF ANY KIND. No moving average, ADX, RSI,         |
//|  Bollinger or ATR handle exists in this file. Every decision is  |
//|  computed from raw OHLC: institutional supply/demand zones       |
//|  (impulse-base-impulse), live candle anatomy, swing structure.   |
//|                                                                  |
//|  Runs on EVERY TICK against the forming bar, so a rejection is   |
//|  traded while it is happening rather than one bar late.          |
//+------------------------------------------------------------------+
#property copyright "V75EA"
#property version   "6.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//|                                                        Types.mqh |
//|  Shared enums/structs used across the V75EA modules.            |
//+------------------------------------------------------------------+


enum ENUM_SIGNAL
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

//--- result of a confluence evaluation
struct SConfluenceResult
  {
   ENUM_SIGNAL signal;      // final decision (NONE unless confidence >= threshold)
   double      confidence;  // 0..1
   double      atr;         // current ATR, for stop/target sizing
   string      reason;      // human-readable breakdown for logging
  };

//--- live status pushed to the on-chart dashboard
struct SDashboardState
  {
   bool     godMode;
   bool     paused;
   string   regime;
   double   confidence;
   double   threshold;
   double   riskMult;
   int      recoveryStep;
   double   volRatio;
   int      openPositions;
   double   dailyPnlPercent;
   double   equity;
   double   balance;
   string   status;        // short state line (e.g. "SCANNING", "HALTED: daily loss")
  };


//+------------------------------------------------------------------+
//|                                                  PriceEngine.mqh |
//|  Raw price mathematics — NO INDICATORS ANYWHERE. Every value is  |
//|  computed directly from OHLC bars, so nothing lags behind price. |
//|                                                                  |
//|  Provides: true-range statistics (for stop sizing, replacing     |
//|  ATR), swing highs/lows, and a "pressure" read of who is winning |
//|  right now (body dominance, wick asymmetry, close location,      |
//|  higher-high/higher-low structure) — the EA's sense of whether   |
//|  it feels like buying or selling.                                |
//+------------------------------------------------------------------+


class CPriceEngine
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;

public:
   void              Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      m_symbol = symbol;
      m_tf     = tf;
     }

   //--- live values of the currently forming bar (index 0)
   double            H(const int i) { return iHigh (m_symbol, m_tf, i); }
   double            L(const int i) { return iLow  (m_symbol, m_tf, i); }
   double            O(const int i) { return iOpen (m_symbol, m_tf, i); }
   double            C(const int i) { return iClose(m_symbol, m_tf, i); }

   double            Body(const int i)      { return MathAbs(C(i) - O(i)); }
   double            Range(const int i)     { return H(i) - L(i); }
   double            UpperWick(const int i) { return H(i) - MathMax(O(i), C(i)); }
   double            LowerWick(const int i) { return MathMin(O(i), C(i)) - L(i); }
   bool              IsBull(const int i)    { return C(i) > O(i); }
   bool              IsBear(const int i)    { return C(i) < O(i); }

   //--- average true range computed from raw bars (NOT the ATR indicator)
   double            AvgRange(const int bars, const int startBar = 1)
     {
      int n = MathMax(1, bars);
      double high[], low[], close[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);

      int need = startBar + n + 1;
      if(CopyHigh (m_symbol, m_tf, 0, need, high)  < need) return 0.0;
      if(CopyLow  (m_symbol, m_tf, 0, need, low)   < need) return 0.0;
      if(CopyClose(m_symbol, m_tf, 0, need, close) < need) return 0.0;

      double sum = 0.0;
      for(int i = startBar; i < startBar + n; i++)
        {
         double tr = MathMax(high[i] - low[i],
                     MathMax(MathAbs(high[i] - close[i + 1]),
                             MathAbs(low[i]  - close[i + 1])));
         sum += tr;
        }
      return sum / n;
     }

   double            AvgBody(const int bars, const int startBar = 1)
     {
      int n = MathMax(1, bars);
      double open[], close[];
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(close, true);
      int need = startBar + n;
      if(CopyOpen (m_symbol, m_tf, 0, need, open)  < need) return 0.0;
      if(CopyClose(m_symbol, m_tf, 0, need, close) < need) return 0.0;

      double sum = 0.0;
      for(int i = startBar; i < need; i++)
         sum += MathAbs(close[i] - open[i]);
      return sum / n;
     }

   //--- most recent swing high/low (fractal: `strength` bars each side)
   bool              LastSwingHigh(const int strength, const int lookback, double &price, int &barIndex)
     {
      double high[];
      ArraySetAsSeries(high, true);
      int need = lookback + strength * 2 + 2;
      if(CopyHigh(m_symbol, m_tf, 0, need, high) < need) return false;

      for(int i = strength + 1; i < need - strength; i++)
        {
         bool ok = true;
         for(int k = 1; k <= strength && ok; k++)
            if(high[i - k] >= high[i] || high[i + k] > high[i]) ok = false;
         if(ok) { price = high[i]; barIndex = i; return true; }
        }
      return false;
     }

   bool              LastSwingLow(const int strength, const int lookback, double &price, int &barIndex)
     {
      double low[];
      ArraySetAsSeries(low, true);
      int need = lookback + strength * 2 + 2;
      if(CopyLow(m_symbol, m_tf, 0, need, low) < need) return false;

      for(int i = strength + 1; i < need - strength; i++)
        {
         bool ok = true;
         for(int k = 1; k <= strength && ok; k++)
            if(low[i - k] <= low[i] || low[i + k] < low[i]) ok = false;
         if(ok) { price = low[i]; barIndex = i; return true; }
        }
      return false;
     }

   //--- Who is winning right now? Signed score in [-1,+1] from pure candle
   //    anatomy: body direction/dominance, wick rejection asymmetry, and
   //    where each bar closed inside its own range.
   double            Pressure(const int bars)
     {
      int n = MathMax(2, bars);
      double open[], high[], low[], close[];
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);
      if(CopyOpen (m_symbol, m_tf, 0, n + 1, open)  < n + 1) return 0.0;
      if(CopyHigh (m_symbol, m_tf, 0, n + 1, high)  < n + 1) return 0.0;
      if(CopyLow  (m_symbol, m_tf, 0, n + 1, low)   < n + 1) return 0.0;
      if(CopyClose(m_symbol, m_tf, 0, n + 1, close) < n + 1) return 0.0;

      double score = 0.0, weightSum = 0.0;
      for(int i = 0; i < n; i++)
        {
         double rng = high[i] - low[i];
         if(rng <= 0.0) continue;

         //--- recency weighting: the newest bars carry the most say
         double w = 1.0 / (1.0 + i * 0.35);

         //--- close location inside the bar: +1 at the high, -1 at the low
         double closeLoc = ((close[i] - low[i]) / rng) * 2.0 - 1.0;

         //--- body dominance, signed
         double bodyDom = (close[i] - open[i]) / rng;

         //--- wick asymmetry: long lower wick = buyers defended, and vice versa
         double upWick  = high[i] - MathMax(open[i], close[i]);
         double dnWick  = MathMin(open[i], close[i]) - low[i];
         double wickAsym = (dnWick - upWick) / rng;

         score     += w * (0.40 * closeLoc + 0.40 * bodyDom + 0.20 * wickAsym);
         weightSum += w;
        }
      if(weightSum <= 0.0) return 0.0;
      return MathMax(-1.0, MathMin(1.0, score / weightSum));
     }

   //--- swing structure: +1 higher highs & higher lows, -1 lower highs & lows, 0 unclear
   int               StructureBias(const int strength, const int lookback)
     {
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      int need = lookback + strength * 2 + 2;
      if(CopyHigh(m_symbol, m_tf, 0, need, high) < need) return 0;
      if(CopyLow (m_symbol, m_tf, 0, need, low)  < need) return 0;

      double sh[2]; double sl[2];
      int nh = 0, nl = 0;
      for(int i = strength + 1; i < need - strength && (nh < 2 || nl < 2); i++)
        {
         if(nh < 2)
           {
            bool ok = true;
            for(int k = 1; k <= strength && ok; k++)
               if(high[i - k] >= high[i] || high[i + k] > high[i]) ok = false;
            if(ok) { sh[nh] = high[i]; nh++; }
           }
         if(nl < 2)
           {
            bool ok = true;
            for(int k = 1; k <= strength && ok; k++)
               if(low[i - k] <= low[i] || low[i + k] < low[i]) ok = false;
            if(ok) { sl[nl] = low[i]; nl++; }
           }
        }
      if(nh < 2 || nl < 2) return 0;
      if(sh[0] > sh[1] && sl[0] > sl[1]) return  1;
      if(sh[0] < sh[1] && sl[0] < sl[1]) return -1;
      return 0;
     }
  };


//+------------------------------------------------------------------+
//|                                                 SupplyDemand.mqh |
//|  Supply & demand zone engine built purely from price structure.  |
//|  NO INDICATORS — zones come from the classic institutional       |
//|  footprint: an impulsive leg IN, a tight BASE (consolidation),   |
//|  then an impulsive leg OUT. The base is where orders were left   |
//|  unfilled, so price returning there tends to react.              |
//|                                                                  |
//|    Drop-Base-Rally / Rally-Base-Rally -> DEMAND (buy zone)       |
//|    Rally-Base-Drop / Drop-Base-Drop   -> SUPPLY (sell zone)      |
//|                                                                  |
//|  Zones carry a proximal edge (first touched on return), a distal |
//|  edge (stop goes beyond it), freshness (untested = strongest),   |
//|  and a strength score from impulse size and base tightness.      |
//+------------------------------------------------------------------+



#define SD_MAX_ZONES 64

struct SZone
  {
   bool     active;
   bool     isDemand;     // true = demand (buy), false = supply (sell)
   double   proximal;     // edge price meets first on return
   double   distal;       // far edge — stop placed beyond this
   datetime formed;
   int      touches;      // times price has traded into the zone
   double   strength;     // 0..1 (impulse size + base tightness + freshness)
   int      baseBars;
  };

class CSupplyDemand
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   CPriceEngine   *m_px;

   SZone           m_zones[SD_MAX_ZONES];
   int             m_count;

   int             m_lookback;
   int             m_maxBaseBars;
   double          m_impulseFactor;   // leg body >= factor * avg range
   double          m_baseFactor;      // base body <= factor * avg range
   int             m_maxTouches;      // zone dies after this many touches

public:
                     CSupplyDemand(void) : m_px(NULL), m_count(0) {}

   void              Init(const string symbol, const ENUM_TIMEFRAMES tf, CPriceEngine *px,
                           const int lookback, const int maxBaseBars,
                           const double impulseFactor, const double baseFactor,
                           const int maxTouches)
     {
      m_symbol        = symbol;
      m_tf            = tf;
      m_px            = px;
      m_lookback      = MathMax(50, lookback);
      m_maxBaseBars   = MathMax(1, maxBaseBars);
      m_impulseFactor = MathMax(0.5, impulseFactor);
      m_baseFactor    = MathMax(0.05, baseFactor);
      m_maxTouches    = MathMax(1, maxTouches);
      m_count         = 0;
     }

   int               Count(void) const { return m_count; }
   SZone             Get(const int i)  { return m_zones[i]; }

   //--- rebuild the zone map from raw bars (call on each new bar)
   void              Rebuild(void)
     {
      m_count = 0;
      if(m_px == NULL) return;

      double avgRange = m_px.AvgRange(50, 1);
      if(avgRange <= 0.0) return;

      int need = m_lookback + m_maxBaseBars + 4;
      double open[], high[], low[], close[];
      datetime time[];
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(time, true);
      if(CopyOpen (m_symbol, m_tf, 0, need, open)  < need) return;
      if(CopyHigh (m_symbol, m_tf, 0, need, high)  < need) return;
      if(CopyLow  (m_symbol, m_tf, 0, need, low)   < need) return;
      if(CopyClose(m_symbol, m_tf, 0, need, close) < need) return;
      if(CopyTime (m_symbol, m_tf, 0, need, time)  < need) return;

      //--- walk back through closed bars looking for leg-out / base / leg-in
      for(int i = 1; i < m_lookback && m_count < SD_MAX_ZONES; i++)
        {
         double outBody  = MathAbs(close[i] - open[i]);
         double outRange = high[i] - low[i];
         if(outRange <= 0.0) continue;

         //--- leg OUT must be a decisive, body-dominant move
         if(outBody < m_impulseFactor * avgRange) continue;
         if(outBody / outRange < 0.5)             continue;

         bool outBull = (close[i] > open[i]);

         //--- collect the base immediately behind it
         for(int nb = 1; nb <= m_maxBaseBars; nb++)
           {
            int legInIdx = i + nb + 1;
            if(legInIdx >= need - 1) break;

            //--- every base bar must be small-bodied (indecision)
            bool baseOk = true;
            double baseHigh = -DBL_MAX, baseLow = DBL_MAX;
            for(int b = i + 1; b <= i + nb && baseOk; b++)
              {
               double bBody = MathAbs(close[b] - open[b]);
               if(bBody > m_baseFactor * avgRange) { baseOk = false; break; }
               if(high[b] > baseHigh) baseHigh = high[b];
               if(low[b]  < baseLow)  baseLow  = low[b];
              }
            if(!baseOk) continue;

            //--- leg IN must also be impulsive
            double inBody  = MathAbs(close[legInIdx] - open[legInIdx]);
            double inRange = high[legInIdx] - low[legInIdx];
            if(inRange <= 0.0) continue;
            if(inBody < m_impulseFactor * avgRange) continue;
            if(inBody / inRange < 0.5)              continue;

            //--- build the zone
            SZone z;
            z.active   = true;
            z.isDemand = outBull;              // left upward => demand
            z.formed   = time[i];
            z.touches  = 0;
            z.baseBars = nb;

            if(z.isDemand) { z.proximal = baseHigh; z.distal = baseLow;  }
            else           { z.proximal = baseLow;  z.distal = baseHigh; }

            //--- strength: bigger impulse and tighter base = stronger
            double impulseScore = MathMin(1.0, (outBody / avgRange) / 3.0);
            double baseWidth    = baseHigh - baseLow;
            double tightScore   = (baseWidth > 0.0)
                                  ? MathMax(0.0, 1.0 - (baseWidth / (avgRange * 2.0)))
                                  : 1.0;
            double barsScore    = 1.0 - ((nb - 1.0) / MathMax(1.0, (double)m_maxBaseBars));
            z.strength = MathMax(0.0, MathMin(1.0,
                          0.45 * impulseScore + 0.35 * tightScore + 0.20 * barsScore));

            //--- validate against everything that happened AFTER it formed
            if(ValidateZone(z, close, high, low, i))
              {
               if(!IsDuplicate(z, avgRange))
                 {
                  m_zones[m_count] = z;
                  m_count++;
                 }
              }
            break; // one zone per leg-out
           }
        }
     }

   //--- nearest live zone price is currently trading into; -1 if none
   int               ZoneAtPrice(const double price, const double tolerance)
     {
      int    best = -1;
      double bestDist = DBL_MAX;

      for(int i = 0; i < m_count; i++)
        {
         if(!m_zones[i].active) continue;

         double lo = MathMin(m_zones[i].proximal, m_zones[i].distal) - tolerance;
         double hi = MathMax(m_zones[i].proximal, m_zones[i].distal) + tolerance;
         if(price < lo || price > hi) continue;

         double d = MathAbs(price - m_zones[i].proximal);
         if(d < bestDist) { bestDist = d; best = i; }
        }
      return best;
     }

   void              RegisterTouch(const int idx)
     {
      if(idx < 0 || idx >= m_count) return;
      m_zones[idx].touches++;
      if(m_zones[idx].touches > m_maxTouches)
         m_zones[idx].active = false;
     }

private:
   //--- a zone dies if price has closed through its distal edge since forming
   bool              ValidateZone(SZone &z, const double &close[], const double &high[],
                                   const double &low[], const int formedIdx)
     {
      int touches = 0;
      for(int j = formedIdx - 1; j >= 0; j--)
        {
         if(z.isDemand)
           {
            if(close[j] < z.distal) return false;          // broken
            if(low[j] <= z.proximal) touches++;            // tested
           }
         else
           {
            if(close[j] > z.distal) return false;
            if(high[j] >= z.proximal) touches++;
           }
        }
      z.touches = touches;
      if(touches > m_maxTouches) return false;

      //--- freshness bonus: untested zones react hardest
      if(touches == 0) z.strength = MathMin(1.0, z.strength + 0.15);
      return true;
     }

   bool              IsDuplicate(const SZone &z, const double avgRange)
     {
      for(int i = 0; i < m_count; i++)
        {
         if(m_zones[i].isDemand != z.isDemand) continue;
         if(MathAbs(m_zones[i].proximal - z.proximal) < avgRange * 0.5)
            return true;
        }
      return false;
     }
  };


//+------------------------------------------------------------------+
//|                                            PriceActionSignals.mqh |
//|  Pure price-action triggers, read LIVE off the forming bar so    |
//|  entries happen while the reaction is happening — not one bar    |
//|  late. NO INDICATORS.                                            |
//|                                                                  |
//|  Triggers: zone rejection (wick stabbed into the zone and price  |
//|  is already back out), engulfing, momentum burst, and break of   |
//|  structure with follow-through.                                  |
//+------------------------------------------------------------------+



enum ENUM_PA_TRIGGER
  {
   PA_NONE          = 0,
   PA_ZONE_REJECT   = 1,
   PA_ENGULF        = 2,
   PA_MOMENTUM      = 3,
   PA_BOS           = 4
  };

class CPriceActionSignals
  {
private:
   CPriceEngine *m_px;
   double        m_wickRatio;      // wick must be >= this share of the bar's range
   double        m_engulfFactor;   // engulfing body vs previous body
   double        m_momentumFactor; // burst body vs average range

public:
                     CPriceActionSignals(void) : m_px(NULL) {}

   void              Init(CPriceEngine *px, const double wickRatio,
                           const double engulfFactor, const double momentumFactor)
     {
      m_px             = px;
      m_wickRatio      = wickRatio;
      m_engulfFactor   = engulfFactor;
      m_momentumFactor = momentumFactor;
     }

   //--- LIVE rejection off a zone, judged on the forming bar (index 0).
   //    Demand: price dipped into the zone and is already back above proximal
   //    with a meaningful lower wick. Supply: mirror image.
   bool              ZoneRejection(const SZone &z, const double bid, const double ask)
     {
      if(m_px == NULL) return false;

      double h = m_px.H(0), l = m_px.L(0), o = m_px.O(0), c = m_px.C(0);
      double rng = h - l;
      if(rng <= 0.0) return false;

      if(z.isDemand)
        {
         bool stabbed   = (l <= z.proximal);            // wick entered the zone
         bool backAbove = (bid > z.proximal);           // price already rejected out
         bool held      = (l >= z.distal);              // zone not broken
         double lowerWick = MathMin(o, c) - l;
         bool wickOk    = (lowerWick >= m_wickRatio * rng);
         return (stabbed && backAbove && held && wickOk);
        }
      else
        {
         bool stabbed   = (h >= z.proximal);
         bool backBelow = (bid < z.proximal);
         bool held      = (h <= z.distal);
         double upperWick = h - MathMax(o, c);
         bool wickOk    = (upperWick >= m_wickRatio * rng);
         return (stabbed && backBelow && held && wickOk);
        }
     }

   //--- engulfing on the last closed bar (1) versus the one before it (2)
   int               Engulfing(void)
     {
      if(m_px == NULL) return 0;
      double b1 = m_px.Body(1), b2 = m_px.Body(2);
      if(b2 <= 0.0 || b1 < m_engulfFactor * b2) return 0;

      if(m_px.IsBull(1) && m_px.IsBear(2) &&
         m_px.C(1) > m_px.O(2) && m_px.O(1) < m_px.C(2)) return 1;

      if(m_px.IsBear(1) && m_px.IsBull(2) &&
         m_px.C(1) < m_px.O(2) && m_px.O(1) > m_px.C(2)) return -1;

      return 0;
     }

   //--- momentum burst on the FORMING bar: decisive body, closing at its extreme
   int               MomentumBurst(const double avgRange)
     {
      if(m_px == NULL || avgRange <= 0.0) return 0;
      double o = m_px.O(0), c = m_px.C(0), h = m_px.H(0), l = m_px.L(0);
      double rng = h - l;
      if(rng <= 0.0) return 0;

      double body = MathAbs(c - o);
      if(body < m_momentumFactor * avgRange) return 0;
      if(body / rng < 0.6)                   return 0;

      double closeLoc = (c - l) / rng;
      if(c > o && closeLoc > 0.70) return  1;
      if(c < o && closeLoc < 0.30) return -1;
      return 0;
     }

   //--- break of structure: price trading through the last swing with intent
   int               BreakOfStructure(const int swingStrength, const int lookback,
                                       const double bid, const double avgRange)
     {
      if(m_px == NULL) return 0;

      double swingHigh = 0.0, swingLow = 0.0;
      int    hi = 0, li = 0;
      bool   haveH = m_px.LastSwingHigh(swingStrength, lookback, swingHigh, hi);
      bool   haveL = m_px.LastSwingLow (swingStrength, lookback, swingLow,  li);

      //--- require the break to clear the level by a real margin, not a tick
      double buffer = avgRange * 0.10;

      if(haveH && bid > swingHigh + buffer && m_px.C(0) > m_px.O(0)) return  1;
      if(haveL && bid < swingLow  - buffer && m_px.C(0) < m_px.O(0)) return -1;
      return 0;
     }
  };


//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh |
//|  Converts a stop-loss distance into a position size that risks  |
//|  a fixed percentage of current equity, clamped to broker limits.|
//+------------------------------------------------------------------+


class CRiskManager
  {
private:
   string m_symbol;
   double m_riskPercent;
   double m_maxRiskPercent;
   double m_minLot;
   double m_maxLot;
   double m_lotStep;

public:
                     CRiskManager(void) : m_riskPercent(1.0), m_maxRiskPercent(2.0), m_minLot(0.01), m_maxLot(100.0), m_lotStep(0.01) {}

   void              Init(const string symbol, const double riskPercent, const double maxRiskPercent)
     {
      m_symbol         = symbol;
      m_maxRiskPercent = maxRiskPercent;
      m_riskPercent    = MathMax(0.0, MathMin(riskPercent, maxRiskPercent));
      m_minLot         = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      m_maxLot         = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      m_lotStep        = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
     }

   //--- adaptive risk requests are always clamped to the hard cap set at Init
   void              SetRiskPercent(const double p)
     {
      m_riskPercent = MathMax(0.0, MathMin(p, m_maxRiskPercent));
     }

   //--- Position size that risks m_riskPercent of equity given a stop-loss distance in price units
   double            CalculateLotSize(const double stopLossDistance)
     {
      if(stopLossDistance <= 0.0)
         return m_minLot;

      double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmount = equity * (m_riskPercent / 100.0);

      double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0 || tickValue <= 0.0)
         return m_minLot;

      double valuePerPoint = tickValue / tickSize;
      double lossPerLot    = stopLossDistance * valuePerPoint;
      if(lossPerLot <= 0.0)
         return m_minLot;

      double lots = riskAmount / lossPerLot;

      //--- normalize to broker lot step and clamp to min/max
      lots = MathFloor(lots / m_lotStep) * m_lotStep;
      lots = MathMax(m_minLot, MathMin(m_maxLot, lots));
      return NormalizeDouble(lots, 2);
     }

   double            RiskPercent(void) const { return m_riskPercent; }
  };


//+------------------------------------------------------------------+
//|                                                 SafetyGuard.mqh |
//|  Circuit breakers: daily loss limit, overall drawdown kill      |
//|  switch, consecutive-loss halt, spread and margin-buffer guard. |
//+------------------------------------------------------------------+


class CSafetyGuard
  {
private:
   string   m_symbol;
   double   m_startEquity;
   double   m_dayStartEquity;
   datetime m_currentDay;
   double   m_maxDailyLossPercent;
   double   m_maxDrawdownPercent;
   int      m_maxConsecutiveLosses;
   int      m_consecutiveLosses;
   bool     m_tradingHalted;
   double   m_maxSpreadPoints;

   //--- session filter + daily profit target
   bool     m_useSession;
   int      m_sessionStartHour;   // broker/server time, 0-23
   int      m_sessionEndHour;     // exclusive; wraps past midnight if end < start
   double   m_dailyProfitTarget;  // % of day-start equity; 0 disables
   bool     m_profitTargetHit;

public:
                     CSafetyGuard(void) : m_consecutiveLosses(0), m_tradingHalted(false),
                                          m_useSession(false), m_sessionStartHour(0),
                                          m_sessionEndHour(24), m_dailyProfitTarget(0.0),
                                          m_profitTargetHit(false) {}

   void              Init(const string symbol, const double maxDailyLossPercent,
                           const double maxDrawdownPercent, const int maxConsecutiveLosses,
                           const double maxSpreadPoints,
                           const bool useSession, const int sessionStartHour, const int sessionEndHour,
                           const double dailyProfitTarget)
     {
      m_symbol               = symbol;
      m_maxDailyLossPercent  = maxDailyLossPercent;
      m_maxDrawdownPercent   = maxDrawdownPercent;
      m_maxConsecutiveLosses = maxConsecutiveLosses;
      m_maxSpreadPoints      = maxSpreadPoints;
      m_useSession           = useSession;
      m_sessionStartHour     = sessionStartHour;
      m_sessionEndHour       = sessionEndHour;
      m_dailyProfitTarget    = dailyProfitTarget;

      m_startEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dayStartEquity = m_startEquity;
      m_currentDay     = TimeCurrent() - (TimeCurrent() % 86400);
      m_consecutiveLosses = 0;
      m_tradingHalted     = false;
      m_profitTargetHit   = false;
     }

   //--- Call once per tick: resets daily counters when a new trading day starts
   void              OnNewTick(void)
     {
      datetime today = TimeCurrent() - (TimeCurrent() % 86400);
      if(today != m_currentDay)
        {
         m_currentDay        = today;
         m_dayStartEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
         m_tradingHalted     = false;
         m_consecutiveLosses = 0;
         m_profitTargetHit   = false;
         Print("SafetyGuard: new trading day, counters reset. Equity=", m_dayStartEquity);
        }
     }

   //--- Call when a position closes, so consecutive-loss tracking stays current
   void              RegisterTradeResult(const bool wasWin)
     {
      if(wasWin)
         m_consecutiveLosses = 0;
      else
         m_consecutiveLosses++;

      if(m_consecutiveLosses >= m_maxConsecutiveLosses)
        {
         m_tradingHalted = true;
         Print("SafetyGuard: max consecutive losses (", m_consecutiveLosses, ") reached. Halting trading for today.");
        }
     }

   bool              IsTradingAllowed(void)
     {
      if(m_tradingHalted)
         return false;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      //--- daily loss limit
      double dailyLossPercent = (m_dayStartEquity - equity) / m_dayStartEquity * 100.0;
      if(dailyLossPercent >= m_maxDailyLossPercent)
        {
         Print("SafetyGuard: daily loss limit hit (", DoubleToString(dailyLossPercent, 2), "%). Halting for today.");
         m_tradingHalted = true;
         return false;
        }

      //--- overall drawdown kill-switch (requires manual re-enable, i.e. EA restart with reset inputs)
      double drawdownPercent = (m_startEquity - equity) / m_startEquity * 100.0;
      if(drawdownPercent >= m_maxDrawdownPercent)
        {
         Print("SafetyGuard: overall drawdown limit hit (", DoubleToString(drawdownPercent, 2), "%). EA disabled.");
         m_tradingHalted = true;
         return false;
        }

      //--- spread guard: skip trading while spread is abnormally wide
      long spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      if(spreadPoints > (long)m_maxSpreadPoints)
         return false;

      //--- daily profit target: lock in gains, stop opening for the day
      if(DailyProfitReached())
         return false;

      //--- session/time filter
      if(!IsWithinSession())
         return false;

      //--- margin buffer: refuse new trades if margin level is too tight
      double marginUsed = AccountInfoDouble(ACCOUNT_MARGIN);
      if(marginUsed > 0.0)
        {
         double marginLevel = equity / marginUsed * 100.0;
         if(marginLevel < 200.0)
            return false;
        }

      return true;
     }

   //--- true once the day's profit target is reached (main EA may flatten on this)
   bool              DailyProfitReached(void)
     {
      if(m_dailyProfitTarget <= 0.0)
         return false;
      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double gainPct  = (equity - m_dayStartEquity) / m_dayStartEquity * 100.0;
      if(gainPct >= m_dailyProfitTarget)
        {
         if(!m_profitTargetHit)
           {
            m_profitTargetHit = true;
            Print("SafetyGuard: daily profit target hit (", DoubleToString(gainPct, 2), "%). Locking in for the day.");
           }
         return true;
        }
      return false;
     }

   bool              IsWithinSession(void)
     {
      if(!m_useSession)
         return true;
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      if(m_sessionStartHour == m_sessionEndHour)
         return true; // 24h
      if(m_sessionStartHour < m_sessionEndHour)
         return (h >= m_sessionStartHour && h < m_sessionEndHour);
      //--- wraps past midnight (e.g. 22 -> 6)
      return (h >= m_sessionStartHour || h < m_sessionEndHour);
     }

   double            DailyPnlPercent(void)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_dayStartEquity <= 0.0)
         return 0.0;
      return (equity - m_dayStartEquity) / m_dayStartEquity * 100.0;
     }

   bool              IsHalted(void) const { return m_tradingHalted; }
  };


//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|  On-chart status panel + control buttons ("Godmode" EA trait).   |
//|  Renders a live readout of the OODA/God-mode state and exposes   |
//|  PAUSE/RESUME and CLOSE ALL buttons. HandleEvent() is called     |
//|  from the EA's OnChartEvent and returns the action to perform.   |
//+------------------------------------------------------------------+



enum ENUM_PANEL_ACTION
  {
   PANEL_NONE         = 0,
   PANEL_TOGGLE_PAUSE = 1,
   PANEL_CLOSE_ALL    = 2
  };

class CDashboard
  {
private:
   string   m_prefix;
   bool     m_enabled;
   int      m_x;
   int      m_y;
   int      m_w;
   int      m_rowH;

   string   m_bg, m_title, m_btnPause, m_btnClose;
   string   m_rows[10];
   int      m_rowCount;

   //--- palette (V75EA gold-on-charcoal identity)
   color    m_cBg, m_cText, m_cMuted, m_cGold, m_cUp, m_cDown;

public:
                     CDashboard(void) : m_enabled(false), m_x(14), m_y(28), m_w(240), m_rowH(20), m_rowCount(0) {}

   void              Init(const string prefix, const bool enabled)
     {
      m_prefix  = prefix;
      m_enabled = enabled;
      m_cBg   = (color)C'20,25,36';
      m_cText = (color)C'232,236,244';
      m_cMuted= (color)C'140,149,168';
      m_cGold = (color)C'217,160,63';
      m_cUp   = (color)C'63,182,139';
      m_cDown = (color)C'224,92,92';

      m_bg       = m_prefix + "bg";
      m_title    = m_prefix + "title";
      m_btnPause = m_prefix + "btnPause";
      m_btnClose = m_prefix + "btnClose";

      if(!m_enabled)
         return;

      CreatePanel();
     }

   void              Deinit(void)
     {
      if(!m_enabled)
         return;
      ObjectsDeleteAll(0, m_prefix);
     }

   //--- returns the action a button click requests (PANEL_NONE otherwise)
   ENUM_PANEL_ACTION HandleEvent(const int id, const long &lparam,
                                  const double &dparam, const string &sparam)
     {
      if(!m_enabled || id != CHARTEVENT_OBJECT_CLICK)
         return PANEL_NONE;

      if(sparam == m_btnPause)
        {
         ObjectSetInteger(0, m_btnPause, OBJPROP_STATE, false);
         return PANEL_TOGGLE_PAUSE;
        }
      if(sparam == m_btnClose)
        {
         ObjectSetInteger(0, m_btnClose, OBJPROP_STATE, false);
         return PANEL_CLOSE_ALL;
        }
      return PANEL_NONE;
     }

   void              Update(const SDashboardState &s)
     {
      if(!m_enabled)
         return;

      color pnlColor = (s.dailyPnlPercent >= 0.0) ? m_cUp : m_cDown;

      SetTitle(StringFormat("V75EA  %s", s.godMode ? "GOD MODE" : "STANDARD"));

      SetRow(0, "State",       s.paused ? "PAUSED" : s.status, s.paused ? m_cDown : m_cGold);
      SetRow(1, "Regime",      s.regime, m_cText);
      SetRow(2, "Confidence",  StringFormat("%.2f / thr %.2f", s.confidence, s.threshold), m_cText);
      SetRow(3, "Vol ratio",   StringFormat("%.2f x", s.volRatio),
             (s.volRatio >= 1.0) ? m_cUp : m_cMuted);
      SetRow(4, "Risk mult",   StringFormat("%.2f x", s.riskMult), m_cText);
      SetRow(5, "Recovery",    (s.recoveryStep > 0) ? StringFormat("step %d", s.recoveryStep) : "-",
             (s.recoveryStep > 0) ? m_cDown : m_cMuted);
      SetRow(6, "Positions",   StringFormat("%d", s.openPositions), m_cText);
      SetRow(7, "Day P/L",     StringFormat("%+.2f%%", s.dailyPnlPercent), pnlColor);
      SetRow(8, "Equity",      StringFormat("%.2f", s.equity), m_cText);

      //--- keep pause button label in sync
      ObjectSetString(0, m_btnPause, OBJPROP_TEXT, s.paused ? "RESUME" : "PAUSE");
     }

private:
   void              CreatePanel(void)
     {
      int rows   = 9;
      int height = 34 + rows * m_rowH + 34;

      //--- background
      ObjectCreate(0, m_bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, m_bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, m_bg, OBJPROP_XDISTANCE, m_x);
      ObjectSetInteger(0, m_bg, OBJPROP_YDISTANCE, m_y);
      ObjectSetInteger(0, m_bg, OBJPROP_XSIZE, m_w);
      ObjectSetInteger(0, m_bg, OBJPROP_YSIZE, height);
      ObjectSetInteger(0, m_bg, OBJPROP_BGCOLOR, m_cBg);
      ObjectSetInteger(0, m_bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, m_bg, OBJPROP_COLOR, m_cGold);
      ObjectSetInteger(0, m_bg, OBJPROP_BACK, false);
      ObjectSetInteger(0, m_bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, m_bg, OBJPROP_HIDDEN, true);

      //--- title
      CreateLabel(m_title, m_x + 12, m_y + 10, "V75EA", m_cGold, 11, true);

      //--- rows
      for(int i = 0; i < rows; i++)
        {
         string keyName = m_prefix + "k" + (string)i;
         string valName = m_prefix + "v" + (string)i;
         int yy = m_y + 34 + i * m_rowH;
         CreateLabel(keyName, m_x + 12, yy, "", m_cMuted, 9, false);
         CreateLabel(valName, m_x + m_w - 12, yy, "", m_cText, 9, false, ANCHOR_RIGHT_UPPER);
         m_rows[i] = valName;
        }
      m_rowCount = rows;

      //--- buttons
      int by = m_y + 34 + rows * m_rowH + 4;
      CreateButton(m_btnPause, m_x + 12, by, 100, 24, "PAUSE", m_cGold);
      CreateButton(m_btnClose, m_x + m_w - 112, by, 100, 24, "CLOSE ALL", m_cDown);
     }

   void              CreateLabel(const string name, const int x, const int y, const string text,
                                  const color clr, const int fontSize, const bool bold,
                                  const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }

   void              CreateButton(const string name, const int x, const int y, const int w, const int h,
                                   const string text, const color clr)
     {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_COLOR, (color)C'232,236,244');
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, (color)C'32,40,56');
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }

   void              SetTitle(const string text)
     {
      ObjectSetString(0, m_title, OBJPROP_TEXT, text);
     }

   void              SetRow(const int i, const string key, const string val, const color valColor)
     {
      if(i < 0 || i >= m_rowCount)
         return;
      ObjectSetString(0, m_prefix + "k" + (string)i, OBJPROP_TEXT, key);
      ObjectSetString(0, m_rows[i], OBJPROP_TEXT, val);
      ObjectSetInteger(0, m_rows[i], OBJPROP_COLOR, valColor);
     }
  };


//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh |
//|  Order execution and open-position management: entry with       |
//|  retry-on-requote, breakeven stop, and partial profit-taking.    |
//+------------------------------------------------------------------+


class CTradeManager
  {
private:
   CTrade m_trade;
   string m_symbol;
   int    m_maxRetries;
   double m_breakevenTriggerAtr;
   double m_partialCloseAtr;
   double m_partialClosePercent;
   bool   m_useTrailing;
   double m_trailAtrMult;

public:
                     CTradeManager(void) : m_maxRetries(3), m_useTrailing(false), m_trailAtrMult(2.0) {}

   //--- ATR trailing stop; only ever tightens, never widens
   void              SetTrailing(const bool useTrailing, const double trailAtrMult)
     {
      m_useTrailing  = useTrailing;
      m_trailAtrMult = MathMax(0.5, trailAtrMult);
     }

   void              Init(const string symbol, const ulong magicNumber, const int slippagePoints,
                           const double breakevenTriggerAtr, const double partialCloseAtr,
                           const double partialClosePercent)
     {
      m_symbol               = symbol;
      m_breakevenTriggerAtr  = breakevenTriggerAtr;
      m_partialCloseAtr      = partialCloseAtr;
      m_partialClosePercent  = partialClosePercent;

      m_trade.SetExpertMagicNumber(magicNumber);
      m_trade.SetDeviationInPoints(slippagePoints);
      m_trade.SetTypeFillingBySymbol(symbol);
     }

   bool              HasOpenPosition(void)
     {
      return (CountOpenPositions() > 0);
     }

   int               CountOpenPositions(void)
     {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) == m_symbol)
            count++;
        }
      return count;
     }

   //--- close every position this EA owns on the symbol (panel button / profit target)
   void              CloseAll(void)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         m_trade.PositionClose(ticket);
        }
     }

   //--- +1 when all open positions are long, -1 all short, 0 flat or mixed
   int               OpenDirection(void)
     {
      int dir = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;

         int d = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         if(dir == 0)
            dir = d;
         else if(dir != d)
            return 0;
        }
      return dir;
     }

   bool              OpenTrade(const ENUM_SIGNAL signal, const double lots,
                                const double slDistance, const double tpDistance)
     {
      if(signal == SIGNAL_NONE || lots <= 0.0)
         return false;

      double price = (signal == SIGNAL_BUY)
                      ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                      : SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double sl = (signal == SIGNAL_BUY) ? price - slDistance : price + slDistance;
      double tp = (signal == SIGNAL_BUY) ? price + tpDistance : price - tpDistance;

      bool result = false;
      for(int attempt = 0; attempt < m_maxRetries && !result; attempt++)
        {
         if(signal == SIGNAL_BUY)
            result = m_trade.Buy(lots, m_symbol, price, sl, tp);
         else
            result = m_trade.Sell(lots, m_symbol, price, sl, tp);

         if(!result)
           {
            uint code = m_trade.ResultRetcode();
            Print("CTradeManager: order attempt ", attempt + 1, " failed, retcode=", code);
            if(code != TRADE_RETCODE_REQUOTE && code != TRADE_RETCODE_PRICE_CHANGED)
               break; // non-transient error, don't retry
           }
        }
      return result;
     }

   //--- Breakeven stop and partial close once price has moved favorably by a multiple of ATR
   void              ManageOpenPositions(const double currentAtr)
     {
      if(currentAtr <= 0.0)
         return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;

         long   type      = PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSl = PositionGetDouble(POSITION_SL);
         double currentTp = PositionGetDouble(POSITION_TP);
         double volume    = PositionGetDouble(POSITION_VOLUME);
         double price     = (type == POSITION_TYPE_BUY)
                             ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                             : SymbolInfoDouble(m_symbol, SYMBOL_ASK);

         double favorableMove = (type == POSITION_TYPE_BUY) ? (price - openPrice) : (openPrice - price);

         //--- breakeven
         if(favorableMove >= m_breakevenTriggerAtr * currentAtr)
           {
            bool needsUpdate = (type == POSITION_TYPE_BUY)
                                ? (currentSl < openPrice)
                                : (currentSl > openPrice || currentSl == 0.0);
            if(needsUpdate)
               m_trade.PositionModify(ticket, openPrice, currentTp);
           }

         //--- partial close
         double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
         if(favorableMove >= m_partialCloseAtr * currentAtr && volume > minLot)
           {
            double closeVolume = NormalizeDouble(volume * m_partialClosePercent / 100.0, 2);
            if(closeVolume >= minLot && closeVolume < volume)
               m_trade.PositionClosePartial(ticket, closeVolume);
           }

         //--- ATR trailing stop: follows price at trailAtrMult ATRs, tighten-only
         if(m_useTrailing && favorableMove >= m_trailAtrMult * currentAtr)
           {
            double trailSl = (type == POSITION_TYPE_BUY)
                              ? price - m_trailAtrMult * currentAtr
                              : price + m_trailAtrMult * currentAtr;
            bool tighter = (type == POSITION_TYPE_BUY)
                            ? (trailSl > currentSl)
                            : (trailSl < currentSl || currentSl == 0.0);
            if(tighter)
               m_trade.PositionModify(ticket, trailSl, currentTp);
           }
        }
     }
  };


//+------------------------------------------------------------------+
//|                                           PerformanceTracker.mqh |
//|  Accumulates realized-trade statistics for evaluation/refinement |
//|  win rate, profit factor, avg win/loss, peak-equity drawdown,    |
//|  and a per-regime breakdown of net profit and trade count.       |
//+------------------------------------------------------------------+


//--- Bucket index is caller-defined (market regime, setup type, ...) so this
//--- tracker carries no dependency on any particular analysis module.
#define PERF_BUCKETS 8

class CPerformanceTracker
  {
private:
   int      m_wins;
   int      m_losses;
   double   m_grossProfit;
   double   m_grossLoss;      // stored as a positive magnitude
   double   m_peakEquity;
   double   m_maxDrawdown;    // in account currency

   //--- per-regime net profit and count (indexed by ENUM_REGIME 0..6)
   double   m_regimeProfit[PERF_BUCKETS];
   int      m_regimeCount[PERF_BUCKETS];

public:
                     CPerformanceTracker(void) { Reset(); }

   void              Reset(void)
     {
      m_wins = 0; m_losses = 0;
      m_grossProfit = 0.0; m_grossLoss = 0.0;
      m_peakEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      m_maxDrawdown = 0.0;
      for(int i = 0; i < PERF_BUCKETS; i++) { m_regimeProfit[i] = 0.0; m_regimeCount[i] = 0; }
     }

   //--- call whenever a position closes
   void              RecordClosedTrade(const double profit, const int bucketAtEntry)
     {
      if(profit >= 0.0) { m_wins++;   m_grossProfit += profit; }
      else              { m_losses++; m_grossLoss   += -profit; }

      int idx = bucketAtEntry;
      if(idx >= 0 && idx < PERF_BUCKETS)
        {
         m_regimeProfit[idx] += profit;
         m_regimeCount[idx]++;
        }

      UpdateDrawdown();
     }

   //--- call on each tick to track equity peak/drawdown even mid-trade
   void              UpdateDrawdown(void)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > m_peakEquity) m_peakEquity = equity;
      double dd = m_peakEquity - equity;
      if(dd > m_maxDrawdown) m_maxDrawdown = dd;
     }

   int               TotalTrades(void)  const { return m_wins + m_losses; }
   double            WinRate(void)      const { int t = m_wins + m_losses; return (t > 0) ? (double)m_wins / t * 100.0 : 0.0; }
   double            ProfitFactor(void) const { return (m_grossLoss > 0.0) ? m_grossProfit / m_grossLoss : 0.0; }
   double            AvgWin(void)       const { return (m_wins   > 0) ? m_grossProfit / m_wins   : 0.0; }
   double            AvgLoss(void)      const { return (m_losses > 0) ? m_grossLoss   / m_losses : 0.0; }
   double            MaxDrawdown(void)  const { return m_maxDrawdown; }

   void              PrintSummary(void)
     {
      Print("=== V75EA performance ===");
      PrintFormat("Trades=%d  WinRate=%.1f%%  ProfitFactor=%.2f  AvgWin=%.2f  AvgLoss=%.2f  MaxDD=%.2f",
                  TotalTrades(), WinRate(), ProfitFactor(), AvgWin(), AvgLoss(), MaxDrawdown());
      for(int i = 0; i < PERF_BUCKETS; i++)
         if(m_regimeCount[i] > 0)
            PrintFormat("  bucket[%d]: trades=%d  netProfit=%.2f", i, m_regimeCount[i], m_regimeProfit[i]);
     }
  };


//--- General
input ulong           InpMagicNumber      = 750006;
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_M5;

//--- Supply & demand zone detection
input int    InpZoneLookback      = 300;   // bars scanned for zones
input int    InpMaxBaseBars       = 3;     // max candles allowed in a base
input double InpImpulseFactor     = 1.2;   // leg body >= factor x avg range
input double InpBaseFactor        = 0.45;  // base body <= factor x avg range
input int    InpMaxZoneTouches    = 2;     // zone dies after this many tests
input double InpZoneTolerance     = 0.15;  // entry tolerance, x avg range

//--- Price action triggers
input double InpWickRatio         = 0.35;  // rejection wick share of bar range
input double InpEngulfFactor      = 1.1;   // engulfing body vs previous body
input double InpMomentumFactor    = 1.0;   // burst body vs avg range
input int    InpSwingStrength     = 2;     // bars each side defining a swing
input int    InpSwingLookback     = 60;

//--- "Feel": pressure gate
input int    InpPressureBars      = 5;     // bars feeding the pressure score
input double InpMinPressure       = 0.12;  // |pressure| needed to act
input bool   InpRequirePressure   = true;  // pressure must agree with the trade

//--- Which setups may fire
input bool   InpTradeZoneReject   = true;
input bool   InpTradeEngulfing    = true;
input bool   InpTradeMomentum     = true;
input bool   InpTradeBOS          = true;
input bool   InpAggressive        = true;  // allow non-zone setups anywhere

//--- Stops / targets (raw price range, not ATR)
input int    InpRangeBars         = 20;    // bars for the average-range measure
input double InpStopRangeMult     = 1.2;   // stop distance = mult x avg range
input double InpZoneStopBuffer    = 0.30;  // extra beyond zone distal, x avg range
input double InpRewardRatio       = 2.0;   // target = RR x stop distance

//--- Trade control
input int    InpMaxPositions      = 2;
input int    InpCooldownSeconds   = 60;    // min seconds between entries
input bool   InpOnePerZone        = true;  // don't re-enter the same zone twice

//--- Risk management
input double InpRiskPercent       = 1.0;
input double InpMaxRiskPercent    = 2.0;

//--- Safety
input double InpMaxDailyLossPercent = 5.0;
input double InpMaxDrawdownPercent  = 15.0;
input int    InpMaxConsecutiveLoss  = 5;
input double InpMaxSpreadPoints     = 800;
input bool   InpUseSession          = false;
input int    InpSessionStartHour    = 0;
input int    InpSessionEndHour      = 24;
input double InpDailyProfitTarget   = 0.0;

//--- Trade management
input int    InpSlippagePoints      = 40;
input double InpBreakevenRangeMult  = 1.0;
input double InpPartialRangeMult    = 1.5;
input double InpPartialClosePercent = 50.0;
input bool   InpUseTrailing         = true;
input double InpTrailRangeMult      = 1.5;

//--- UX
input bool   InpShowDashboard       = true;
input bool   InpUseNotifications    = false;

CPriceEngine        g_px;
CSupplyDemand       g_zones;
CPriceActionSignals g_pa;
CRiskManager        g_risk;
CSafetyGuard        g_safety;
CDashboard          g_dashboard;
CTradeManager       g_trades;
CPerformanceTracker g_perf;

datetime g_lastBarTime  = 0;
datetime g_lastEntryTime = 0;
bool     g_paused        = false;
int      g_lastBucket    = 0;
double   g_lastPressure  = 0.0;
string   g_lastSetup     = "-";
double   g_usedZoneProximal[16];
int      g_usedZoneCount = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_px.Init(_Symbol, InpTimeframe);
   g_zones.Init(_Symbol, InpTimeframe, GetPointer(g_px),
                InpZoneLookback, InpMaxBaseBars, InpImpulseFactor,
                InpBaseFactor, InpMaxZoneTouches);
   g_pa.Init(GetPointer(g_px), InpWickRatio, InpEngulfFactor, InpMomentumFactor);

   g_risk.Init(_Symbol, InpRiskPercent, InpMaxRiskPercent);
   g_safety.Init(_Symbol, InpMaxDailyLossPercent, InpMaxDrawdownPercent,
                 InpMaxConsecutiveLoss, InpMaxSpreadPoints,
                 InpUseSession, InpSessionStartHour, InpSessionEndHour, InpDailyProfitTarget);
   g_trades.Init(_Symbol, InpMagicNumber, InpSlippagePoints,
                 InpBreakevenRangeMult, InpPartialRangeMult, InpPartialClosePercent);
   g_trades.SetTrailing(InpUseTrailing, InpTrailRangeMult);
   g_dashboard.Init("v75pa_", InpShowDashboard);
   g_perf.Reset();

   g_zones.Rebuild();

   Print("V75 PriceAction EA v6 on ", _Symbol, " TF=", EnumToString(InpTimeframe),
         " | zones=", g_zones.Count(), " | NO INDICATORS");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_perf.PrintSummary();
   g_dashboard.Deinit();
  }

//+------------------------------------------------------------------+
//| Every tick: manage, then look for a reason to act immediately.   |
//+------------------------------------------------------------------+
void OnTick()
  {
   g_safety.OnNewTick();
   g_perf.UpdateDrawdown();

   double avgRange = g_px.AvgRange(InpRangeBars, 1);
   if(avgRange <= 0.0)
      return;

   //--- manage open trades on every tick (breakeven / partial / trail)
   g_trades.ManageOpenPositions(avgRange);

   //--- lock in the day if the profit target is reached
   if(g_safety.DailyProfitReached() && g_trades.HasOpenPosition())
     {
      g_trades.CloseAll();
      Notify("V75PA: daily profit target reached — flat.");
     }

   //--- refresh the zone map once per bar (zones are structural, not tick data)
   if(IsNewBar())
     {
      g_zones.Rebuild();
      g_usedZoneCount = 0;   // zones re-derived, allow fresh entries
     }

   g_lastPressure = g_px.Pressure(InpPressureBars);
   UpdateDashboard(avgRange);

   if(g_paused)                    return;
   if(!g_safety.IsTradingAllowed()) return;
   if(g_trades.CountOpenPositions() >= MathMax(1, InpMaxPositions)) return;
   if(TimeCurrent() - g_lastEntryTime < InpCooldownSeconds) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   int    dir        = 0;          // +1 buy, -1 sell
   double stopPrice  = 0.0;        // structural stop level, if the setup defines one
   string setup      = "";
   int    bucket     = 0;

   //--- 1) ZONE REACTION — the highest-quality read: price is in a zone and
   //       has already rejected out of it on the live bar.
   if(InpTradeZoneReject && dir == 0)
     {
      int zi = g_zones.ZoneAtPrice(bid, avgRange * InpZoneTolerance);
      if(zi >= 0)
        {
         SZone z = g_zones.Get(zi);
         if(z.active && !ZoneAlreadyUsed(z.proximal) && g_pa.ZoneRejection(z, bid, ask))
           {
            dir       = z.isDemand ? 1 : -1;
            stopPrice = z.isDemand ? (z.distal - avgRange * InpZoneStopBuffer)
                                   : (z.distal + avgRange * InpZoneStopBuffer);
            setup     = z.isDemand ? "DEMAND REJECT" : "SUPPLY REJECT";
            bucket    = z.isDemand ? 1 : 2;
            g_zones.RegisterTouch(zi);
            MarkZoneUsed(z.proximal);
           }
        }
     }

   //--- 2) ENGULFING — decisive reversal candle just completed
   if(InpTradeEngulfing && dir == 0 && InpAggressive)
     {
      int e = g_pa.Engulfing();
      if(e != 0)
        {
         dir    = e;
         setup  = (e > 0) ? "BULL ENGULF" : "BEAR ENGULF";
         bucket = 3;
        }
     }

   //--- 3) MOMENTUM BURST — the forming bar is running hard with intent
   if(InpTradeMomentum && dir == 0 && InpAggressive)
     {
      int m = g_pa.MomentumBurst(avgRange);
      if(m != 0)
        {
         dir    = m;
         setup  = (m > 0) ? "MOMENTUM UP" : "MOMENTUM DOWN";
         bucket = 4;
        }
     }

   //--- 4) BREAK OF STRUCTURE — price took out the last swing with follow-through
   if(InpTradeBOS && dir == 0 && InpAggressive)
     {
      int b = g_pa.BreakOfStructure(InpSwingStrength, InpSwingLookback, bid, avgRange);
      if(b != 0)
        {
         dir    = b;
         setup  = (b > 0) ? "BOS UP" : "BOS DOWN";
         bucket = 5;
        }
      }

   if(dir == 0)
      return;

   //--- "feels like buying / selling": pressure must agree with the trade
   if(InpRequirePressure)
     {
      if(MathAbs(g_lastPressure) < InpMinPressure) return;
      if((g_lastPressure > 0.0 ? 1 : -1) != dir)   return;
     }

   //--- structural stop where the setup gives one, otherwise range-based
   double slDistance;
   if(stopPrice > 0.0)
     {
      slDistance = MathAbs(bid - stopPrice);
      double minStop = avgRange * 0.5;
      if(slDistance < minStop) slDistance = minStop;
     }
   else
      slDistance = avgRange * InpStopRangeMult;

   double tpDistance = slDistance * InpRewardRatio;

   g_risk.SetRiskPercent(InpRiskPercent);
   double lots = g_risk.CalculateLotSize(slDistance);

   ENUM_SIGNAL sig = (dir > 0) ? SIGNAL_BUY : SIGNAL_SELL;
   if(g_trades.OpenTrade(sig, lots, slDistance, tpDistance))
     {
      g_lastEntryTime = TimeCurrent();
      g_lastBucket    = bucket;
      g_lastSetup     = setup;
      string msg = StringFormat("V75PA %s | %s lots=%.2f SL=%.1f TP=%.1f pressure=%+.2f zones=%d",
                                (dir > 0 ? "BUY" : "SELL"), setup, lots,
                                slDistance, tpDistance, g_lastPressure, g_zones.Count());
      Print(msg);
      Notify(msg);
     }
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   ENUM_PANEL_ACTION action = g_dashboard.HandleEvent(id, lparam, dparam, sparam);
   if(action == PANEL_TOGGLE_PAUSE)
     {
      g_paused = !g_paused;
      Print("V75PA: ", (g_paused ? "PAUSED" : "RESUMED"), " by user.");
     }
   else if(action == PANEL_CLOSE_ALL)
     {
      g_trades.CloseAll();
      Print("V75PA: CLOSE ALL by user.");
     }
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal))           return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
     {
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      bool win = (profit >= 0.0);
      g_safety.RegisterTradeResult(win);
      g_perf.RecordClosedTrade(profit, g_lastBucket);
     }
  }

//+------------------------------------------------------------------+
void UpdateDashboard(const double avgRange)
  {
   if(!InpShowDashboard) return;

   SDashboardState st;
   st.godMode         = InpAggressive;
   st.paused          = g_paused;
   st.regime          = g_lastSetup;
   st.confidence      = MathAbs(g_lastPressure);
   st.threshold       = InpMinPressure;
   st.riskMult        = 1.0;
   st.recoveryStep    = 0;
   st.volRatio        = (double)g_zones.Count();
   st.openPositions   = g_trades.CountOpenPositions();
   st.dailyPnlPercent = g_safety.DailyPnlPercent();
   st.equity          = AccountInfoDouble(ACCOUNT_EQUITY);
   st.balance         = AccountInfoDouble(ACCOUNT_BALANCE);
   st.status          = g_safety.IsHalted()
                        ? "HALTED"
                        : StringFormat("LIVE  P%+.2f", g_lastPressure);
   g_dashboard.Update(st);
  }

//+------------------------------------------------------------------+
bool ZoneAlreadyUsed(const double proximal)
  {
   if(!InpOnePerZone) return false;
   for(int i = 0; i < g_usedZoneCount; i++)
      if(MathAbs(g_usedZoneProximal[i] - proximal) < _Point)
         return true;
   return false;
  }

void MarkZoneUsed(const double proximal)
  {
   if(g_usedZoneCount < 16)
     {
      g_usedZoneProximal[g_usedZoneCount] = proximal;
      g_usedZoneCount++;
     }
  }

//+------------------------------------------------------------------+
void Notify(const string msg)
  {
   if(InpUseNotifications) SendNotification(msg);
  }

//+------------------------------------------------------------------+
bool IsNewBar(void)
  {
   datetime t = iTime(_Symbol, InpTimeframe, 0);
   if(t != g_lastBarTime) { g_lastBarTime = t; return true; }
   return false;
  }
