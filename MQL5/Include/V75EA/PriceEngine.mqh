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
#ifndef V75EA_PRICE_ENGINE_MQH
#define V75EA_PRICE_ENGINE_MQH

#property strict

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

#endif // V75EA_PRICE_ENGINE_MQH
