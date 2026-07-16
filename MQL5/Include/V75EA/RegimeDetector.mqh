//+------------------------------------------------------------------+
//|                                              RegimeDetector.mqh |
//|  Classifies the current market into a trading regime using ADX   |
//|  (trend strength/direction), EMA slope, ATR dynamics (volatility |
//|  expansion/contraction) and Bollinger-band width (compression).  |
//|                                                                  |
//|  Note: trend-exhaustion and trend-reversal from the blueprint    |
//|  are surfaced in the ConfluenceEngine, which combines this       |
//|  regime with MarketStructure (CHoCH) and momentum deceleration.  |
//+------------------------------------------------------------------+
#ifndef V75EA_REGIME_DETECTOR_MQH
#define V75EA_REGIME_DETECTOR_MQH

#property strict

enum ENUM_REGIME
  {
   REGIME_STRONG_UPTREND   = 0,
   REGIME_WEAK_UPTREND     = 1,
   REGIME_STRONG_DOWNTREND = 2,
   REGIME_WEAK_DOWNTREND   = 3,
   REGIME_RANGE            = 4,
   REGIME_BREAKOUT         = 5,
   REGIME_COMPRESSION      = 6
  };

class CRegimeDetector
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;

   int             m_hAdx;
   int             m_hEmaFast;
   int             m_hEmaSlow;
   int             m_hAtr;
   int             m_hBands;

   double          m_adxTrendThreshold;   // ADX above this => trending
   double          m_adxStrongThreshold;  // ADX above this => strong trend
   double          m_atrExpansionRatio;   // current ATR / avg ATR above this => volatility burst
   double          m_bbCompressionRatio;  // current BB width / avg width below this => compression

public:
                     CRegimeDetector(void) : m_hAdx(INVALID_HANDLE), m_hEmaFast(INVALID_HANDLE),
                                              m_hEmaSlow(INVALID_HANDLE), m_hAtr(INVALID_HANDLE),
                                              m_hBands(INVALID_HANDLE) {}

   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                           const int adxPeriod, const double adxTrendThreshold, const double adxStrongThreshold,
                           const int emaFast, const int emaSlow, const int atrPeriod,
                           const int bandsPeriod, const double bandsDeviation,
                           const double atrExpansionRatio, const double bbCompressionRatio)
     {
      m_symbol             = symbol;
      m_tf                 = tf;
      m_adxTrendThreshold  = adxTrendThreshold;
      m_adxStrongThreshold = adxStrongThreshold;
      m_atrExpansionRatio  = atrExpansionRatio;
      m_bbCompressionRatio = bbCompressionRatio;

      m_hAdx     = iADX(symbol, tf, adxPeriod);
      m_hEmaFast = iMA(symbol, tf, emaFast, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaSlow = iMA(symbol, tf, emaSlow, 0, MODE_EMA, PRICE_CLOSE);
      m_hAtr     = iATR(symbol, tf, atrPeriod);
      m_hBands   = iBands(symbol, tf, bandsPeriod, 0, bandsDeviation, PRICE_CLOSE);

      if(m_hAdx == INVALID_HANDLE || m_hEmaFast == INVALID_HANDLE || m_hEmaSlow == INVALID_HANDLE ||
         m_hAtr == INVALID_HANDLE || m_hBands == INVALID_HANDLE)
        {
         Print("CRegimeDetector: failed to create indicator handles");
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
      if(m_hBands   != INVALID_HANDLE) IndicatorRelease(m_hBands);
     }

   double            GetAdx(void)
     {
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_hAdx, 0, 0, 1, buf) < 1) return 0.0;
      return buf[0];
     }

   ENUM_REGIME       Classify(void)
     {
      double adx[];
      ArraySetAsSeries(adx, true);
      if(CopyBuffer(m_hAdx, 0, 0, 1, adx) < 1)
         return REGIME_RANGE;

      double fast[], slow[];
      ArraySetAsSeries(fast, true);
      ArraySetAsSeries(slow, true);
      if(CopyBuffer(m_hEmaFast, 0, 0, 3, fast) < 3) return REGIME_RANGE;
      if(CopyBuffer(m_hEmaSlow, 0, 0, 3, slow) < 3) return REGIME_RANGE;

      //--- volatility context
      double atr[];
      ArraySetAsSeries(atr, true);
      int atrCount = CopyBuffer(m_hAtr, 0, 0, 50, atr);
      double atrNow = (atrCount > 0) ? atr[0] : 0.0;
      double atrAvg = Average(atr, atrCount);
      bool   volBurst = (atrAvg > 0.0 && atrNow >= atrAvg * m_atrExpansionRatio);

      //--- Bollinger width compression context
      double upper[], lower[], base[];
      ArraySetAsSeries(upper, true);
      ArraySetAsSeries(lower, true);
      ArraySetAsSeries(base, true);
      bool compression = false;
      if(CopyBuffer(m_hBands, 1, 0, 50, upper) > 0 &&
         CopyBuffer(m_hBands, 2, 0, 50, lower) > 0 &&
         CopyBuffer(m_hBands, 0, 0, 50, base)  > 0)
        {
         int n = MathMin(ArraySize(upper), ArraySize(lower));
         double widthNow = upper[0] - lower[0];
         double widthSum = 0.0; int widthCnt = 0;
         for(int i = 0; i < n; i++)
           {
            widthSum += (upper[i] - lower[i]);
            widthCnt++;
           }
         double widthAvg = (widthCnt > 0) ? widthSum / widthCnt : 0.0;
         compression = (widthAvg > 0.0 && widthNow <= widthAvg * m_bbCompressionRatio);
        }

      bool trending    = adx[0] >= m_adxTrendThreshold;
      bool strongTrend = adx[0] >= m_adxStrongThreshold;
      bool emaUp       = fast[0] > slow[0];
      double slope     = fast[0] - fast[2];

      //--- priority-ordered classification
      if(volBurst && trending)
         return REGIME_BREAKOUT;

      if(compression && !trending)
         return REGIME_COMPRESSION;

      if(trending && emaUp && slope > 0.0)
         return strongTrend ? REGIME_STRONG_UPTREND : REGIME_WEAK_UPTREND;

      if(trending && !emaUp && slope < 0.0)
         return strongTrend ? REGIME_STRONG_DOWNTREND : REGIME_WEAK_DOWNTREND;

      return REGIME_RANGE;
     }

   //--- true when the regime is one we want to trade with a trend-continuation bias
   static bool       IsTrendRegime(const ENUM_REGIME r)
     {
      return (r == REGIME_STRONG_UPTREND || r == REGIME_WEAK_UPTREND ||
              r == REGIME_STRONG_DOWNTREND || r == REGIME_WEAK_DOWNTREND ||
              r == REGIME_BREAKOUT);
     }

   static int        RegimeDirection(const ENUM_REGIME r)
     {
      if(r == REGIME_STRONG_UPTREND || r == REGIME_WEAK_UPTREND)   return  1;
      if(r == REGIME_STRONG_DOWNTREND || r == REGIME_WEAK_DOWNTREND) return -1;
      return 0; // breakout/range/compression have no fixed direction here
     }

private:
   double            Average(const double &arr[], const int count)
     {
      if(count <= 0) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < count; i++) sum += arr[i];
      return sum / count;
     }
  };

#endif // V75EA_REGIME_DETECTOR_MQH
