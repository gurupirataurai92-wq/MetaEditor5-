//+------------------------------------------------------------------+
//|                                                 TrendStrength.mqh |
//|  Quantifies how strong/persistent the current trend is, so the   |
//|  EA can trade only high-quality trends. Combines ADX level, EMA  |
//|  slope (normalized by ATR), and price distance from equilibrium  |
//|  (the slow EMA). Returns a strength score in [0, 1] plus the      |
//|  trend direction.                                                |
//+------------------------------------------------------------------+
#ifndef V75EA_TREND_STRENGTH_MQH
#define V75EA_TREND_STRENGTH_MQH

#property strict

class CTrendStrength
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int             m_hAdx;
   int             m_hEmaFast;
   int             m_hEmaSlow;
   int             m_hAtr;
   double          m_adxNormalizer;   // ADX value treated as "full strength"
   int             m_slopeLookback;

public:
                     CTrendStrength(void) : m_hAdx(INVALID_HANDLE), m_hEmaFast(INVALID_HANDLE),
                                             m_hEmaSlow(INVALID_HANDLE), m_hAtr(INVALID_HANDLE),
                                             m_adxNormalizer(50.0), m_slopeLookback(5) {}

   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                           const int adxPeriod, const int emaFast, const int emaSlow,
                           const int atrPeriod, const double adxNormalizer, const int slopeLookback)
     {
      m_symbol        = symbol;
      m_tf            = tf;
      m_adxNormalizer = MathMax(1.0, adxNormalizer);
      m_slopeLookback = MathMax(2, slopeLookback);

      m_hAdx     = iADX(symbol, tf, adxPeriod);
      m_hEmaFast = iMA(symbol, tf, emaFast, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaSlow = iMA(symbol, tf, emaSlow, 0, MODE_EMA, PRICE_CLOSE);
      m_hAtr     = iATR(symbol, tf, atrPeriod);

      if(m_hAdx == INVALID_HANDLE || m_hEmaFast == INVALID_HANDLE ||
         m_hEmaSlow == INVALID_HANDLE || m_hAtr == INVALID_HANDLE)
        {
         Print("CTrendStrength: failed to create indicator handles");
         return false;
        }
      return true;
     }

   void              Deinit(void)
     {
      if(m_hAdx     != INVALID_HANDLE) IndicatorRelease(m_hAdx);
      if(m_hEmaFast != INVALID_HANDLE) IndicatorRelease(m_hEmaFast);
      if(m_hEmaSlow != INVALID_HANDLE) IndicatorRelease(m_hEmaSlow);
      if(m_hAtr     != INVALID_HANDLE) IndicatorRelease(m_hAtr);
     }

   //--- strength in [0,1]; direction set via out-parameter (+1/-1/0)
   double            Strength(int &direction)
     {
      direction = 0;

      double adx[], fast[], slow[], atr[];
      ArraySetAsSeries(adx, true);
      ArraySetAsSeries(fast, true);
      ArraySetAsSeries(slow, true);
      ArraySetAsSeries(atr, true);

      if(CopyBuffer(m_hAdx, 0, 0, 1, adx) < 1) return 0.0;
      if(CopyBuffer(m_hEmaFast, 0, 0, m_slopeLookback + 1, fast) < m_slopeLookback + 1) return 0.0;
      if(CopyBuffer(m_hEmaSlow, 0, 0, 1, slow) < 1) return 0.0;
      if(CopyBuffer(m_hAtr, 0, 0, 1, atr) < 1 || atr[0] <= 0.0) return 0.0;

      //--- direction from fast vs slow EMA
      direction = (fast[0] > slow[0]) ? 1 : ((fast[0] < slow[0]) ? -1 : 0);

      //--- 1) ADX component
      double adxScore = MathMin(1.0, adx[0] / m_adxNormalizer);

      //--- 2) slope component: EMA change over lookback, normalized by ATR
      double slope      = MathAbs(fast[0] - fast[m_slopeLookback]);
      double slopeScore = MathMin(1.0, slope / (atr[0] * m_slopeLookback));

      //--- 3) distance-from-equilibrium: how far fast EMA sits from slow EMA, in ATRs (capped)
      double dist      = MathAbs(fast[0] - slow[0]);
      double distScore = MathMin(1.0, dist / (atr[0] * 2.0));

      double strength = 0.45 * adxScore + 0.35 * slopeScore + 0.20 * distScore;
      return MathMax(0.0, MathMin(1.0, strength));
     }
  };

#endif // V75EA_TREND_STRENGTH_MQH
