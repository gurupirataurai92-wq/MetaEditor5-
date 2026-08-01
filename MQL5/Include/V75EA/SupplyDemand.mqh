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
#ifndef V75EA_SUPPLY_DEMAND_MQH
#define V75EA_SUPPLY_DEMAND_MQH

#property strict

#include <V75EA\PriceEngine.mqh>

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

#endif // V75EA_SUPPLY_DEMAND_MQH
