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
#ifndef V75EA_PRICE_ACTION_SIGNALS_MQH
#define V75EA_PRICE_ACTION_SIGNALS_MQH

#property strict

#include <V75EA\PriceEngine.mqh>
#include <V75EA\SupplyDemand.mqh>

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

#endif // V75EA_PRICE_ACTION_SIGNALS_MQH
