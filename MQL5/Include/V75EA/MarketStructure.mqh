//+------------------------------------------------------------------+
//|                                             MarketStructure.mqh |
//|  Detects swing highs/lows (fractal style), derives structural    |
//|  bias (HH/HL vs LH/LL), and flags Break of Structure (BOS) and   |
//|  Change of Character (CHoCH). Also exposes nearest swing-based    |
//|  support/resistance for context and stop placement.              |
//+------------------------------------------------------------------+
#ifndef V75EA_MARKET_STRUCTURE_MQH
#define V75EA_MARKET_STRUCTURE_MQH

#property strict

enum ENUM_STRUCTURE_BIAS
  {
   STRUCT_BULLISH = 1,
   STRUCT_BEARISH = -1,
   STRUCT_NEUTRAL = 0
  };

class CMarketStructure
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int             m_fractalStrength;  // bars on each side that define a swing
   int             m_lookback;         // bars scanned for swings

   ENUM_STRUCTURE_BIAS m_bias;
   bool            m_lastEventBOS;
   bool            m_lastEventCHoCH;
   double          m_nearestSupport;
   double          m_nearestResistance;

public:
                     CMarketStructure(void) : m_bias(STRUCT_NEUTRAL), m_lastEventBOS(false),
                                               m_lastEventCHoCH(false), m_nearestSupport(0.0),
                                               m_nearestResistance(0.0) {}

   void              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                           const int fractalStrength, const int lookback)
     {
      m_symbol          = symbol;
      m_tf              = tf;
      m_fractalStrength = MathMax(1, fractalStrength);
      m_lookback        = MathMax(fractalStrength * 4, lookback);
     }

   //--- recompute structure; call once per new bar (or per tick if cheap enough)
   void              Update(void)
     {
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);

      int need = m_lookback + m_fractalStrength * 2 + 1;
      if(CopyHigh(m_symbol, m_tf, 0, need, high) < need) return;
      if(CopyLow(m_symbol, m_tf, 0, need, low)  < need) return;

      double swingHighs[]; double swingLows[];
      int    shIdx[];      int    slIdx[];
      ArrayResize(swingHighs, 0); ArrayResize(swingLows, 0);
      ArrayResize(shIdx, 0);      ArrayResize(slIdx, 0);

      int s = m_fractalStrength;
      for(int i = s; i < need - s; i++)
        {
         if(IsSwingHigh(high, i, s))
           {
            AppendD(swingHighs, high[i]);
            AppendI(shIdx, i);
           }
         if(IsSwingLow(low, i, s))
           {
            AppendD(swingLows, low[i]);
            AppendI(slIdx, i);
           }
        }

      //--- derive bias from the two most recent swing highs and lows
      ENUM_STRUCTURE_BIAS prevBias = m_bias;
      m_lastEventBOS   = false;
      m_lastEventCHoCH = false;

      if(ArraySize(swingHighs) >= 2 && ArraySize(swingLows) >= 2)
        {
         // index 0 is the most recent swing (series-ordered arrays)
         double recentHigh = swingHighs[0];
         double priorHigh  = swingHighs[1];
         double recentLow  = swingLows[0];
         double priorLow   = swingLows[1];

         bool higherHigh = recentHigh > priorHigh;
         bool higherLow  = recentLow  > priorLow;
         bool lowerHigh  = recentHigh < priorHigh;
         bool lowerLow   = recentLow  < priorLow;

         if(higherHigh && higherLow)
            m_bias = STRUCT_BULLISH;
         else if(lowerHigh && lowerLow)
            m_bias = STRUCT_BEARISH;
         // otherwise retain previous bias (structure unclear)

         //--- BOS: continuation break in the direction of bias
         double close0 = iClose(m_symbol, m_tf, 0);
         if(m_bias == STRUCT_BULLISH && close0 > priorHigh)
            m_lastEventBOS = true;
         if(m_bias == STRUCT_BEARISH && close0 < priorLow)
            m_lastEventBOS = true;

         //--- CHoCH: bias flipped versus previous evaluation
         if(prevBias != STRUCT_NEUTRAL && m_bias != STRUCT_NEUTRAL && prevBias != m_bias)
            m_lastEventCHoCH = true;

         //--- nearest S/R from most recent swings
         m_nearestResistance = recentHigh;
         m_nearestSupport    = recentLow;
        }
     }

   ENUM_STRUCTURE_BIAS Bias(void)          const { return m_bias; }
   bool              HadBOS(void)          const { return m_lastEventBOS; }
   bool              HadCHoCH(void)        const { return m_lastEventCHoCH; }
   double            NearestSupport(void)  const { return m_nearestSupport; }
   double            NearestResistance(void) const { return m_nearestResistance; }

private:
   bool              IsSwingHigh(const double &high[], const int idx, const int strength)
     {
      double pivot = high[idx];
      for(int k = 1; k <= strength; k++)
        {
         if(high[idx - k] >= pivot) return false; // more recent bars (lower index)
         if(high[idx + k] >  pivot) return false; // older bars (higher index)
        }
      return true;
     }

   bool              IsSwingLow(const double &low[], const int idx, const int strength)
     {
      double pivot = low[idx];
      for(int k = 1; k <= strength; k++)
        {
         if(low[idx - k] <= pivot) return false;
         if(low[idx + k] <  pivot) return false;
        }
      return true;
     }

   void              AppendD(double &arr[], const double v)
     {
      int n = ArraySize(arr);
      ArrayResize(arr, n + 1);
      arr[n] = v;
     }
   void              AppendI(int &arr[], const int v)
     {
      int n = ArraySize(arr);
      ArrayResize(arr, n + 1);
      arr[n] = v;
     }
  };

#endif // V75EA_MARKET_STRUCTURE_MQH
