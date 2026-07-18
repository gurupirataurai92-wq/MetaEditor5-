//+------------------------------------------------------------------+
//|                                       V75EA_GodMode_AllInOne.mq5 |
//|  Single-file build of V75EA v3.00 for easy compilation:          |
//|  paste into MQL5/Experts, press F7 in MetaEditor 5 — no Include  |
//|  folder setup required. Identical logic to the modular project.  |
//|                                                                  |
//|  Confluence-based EA for Deriv Volatility 75 Index, driven by an |
//|  OODA decision cycle (Observe-Orient-Decide-Act-Feedback) with   |
//|  an optional adaptive "God mode". God mode is adaptive-          |
//|  aggressive, NOT risk-free: every adaptive request is clamped by |
//|  the RiskManager hard cap and gated by SafetyGuard breakers.     |
//+------------------------------------------------------------------+
#property copyright "V75EA"
#property version   "3.00"
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


//+------------------------------------------------------------------+
//|                                             MarketStructure.mqh |
//|  Detects swing highs/lows (fractal style), derives structural    |
//|  bias (HH/HL vs LH/LL), and flags Break of Structure (BOS) and   |
//|  Change of Character (CHoCH). Also exposes nearest swing-based    |
//|  support/resistance for context and stop placement.              |
//+------------------------------------------------------------------+


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


//+------------------------------------------------------------------+
//|                                               MomentumEngine.mqh |
//|  Measures momentum from price action: candle body size relative  |
//|  to ATR, runs of consecutive same-direction candles, and rate    |
//|  of change (with acceleration). Returns a signed score in        |
//|  [-1, +1] where sign is direction and magnitude is conviction.   |
//+------------------------------------------------------------------+


class CMomentumEngine
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int             m_hAtr;
   int             m_rocPeriod;
   int             m_maxRun;       // consecutive-candle run that saturates the run score

public:
                     CMomentumEngine(void) : m_hAtr(INVALID_HANDLE), m_rocPeriod(10), m_maxRun(5) {}

   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                           const int atrPeriod, const int rocPeriod, const int maxRun)
     {
      m_symbol    = symbol;
      m_tf        = tf;
      m_rocPeriod = MathMax(2, rocPeriod);
      m_maxRun    = MathMax(2, maxRun);
      m_hAtr      = iATR(symbol, tf, atrPeriod);
      if(m_hAtr == INVALID_HANDLE)
        {
         Print("CMomentumEngine: failed to create ATR handle");
         return false;
        }
      return true;
     }

   void              Deinit(void)
     {
      if(m_hAtr != INVALID_HANDLE) IndicatorRelease(m_hAtr);
     }

   //--- signed momentum score in [-1, +1]
   double            Score(void)
     {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(m_hAtr, 0, 0, 1, atr) < 1 || atr[0] <= 0.0)
         return 0.0;

      int bars = m_rocPeriod + 2;
      double open[], close[];
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(close, true);
      if(CopyOpen(m_symbol, m_tf, 0, bars, open) < bars) return 0.0;
      if(CopyClose(m_symbol, m_tf, 0, bars, close) < bars) return 0.0;

      //--- 1) body of the last closed candle vs ATR (capped at 1 ATR)
      double body      = close[1] - open[1];
      double bodyScore = MathMax(-1.0, MathMin(1.0, body / atr[0]));

      //--- 2) consecutive same-direction candle run
      int dir = (close[1] > open[1]) ? 1 : ((close[1] < open[1]) ? -1 : 0);
      int run = 0;
      if(dir != 0)
        {
         for(int i = 1; i < bars; i++)
           {
            int d = (close[i] > open[i]) ? 1 : ((close[i] < open[i]) ? -1 : 0);
            if(d == dir) run++;
            else break;
           }
        }
      double runScore = dir * MathMin(1.0, (double)run / m_maxRun);

      //--- 3) rate of change over rocPeriod, normalized by ATR
      double roc      = close[1] - close[1 + m_rocPeriod];
      double rocScore = MathMax(-1.0, MathMin(1.0, roc / (atr[0] * m_rocPeriod)));

      //--- weighted blend
      double score = 0.35 * bodyScore + 0.30 * runScore + 0.35 * rocScore;
      return MathMax(-1.0, MathMin(1.0, score));
     }

   int               Direction(void)
     {
      double s = Score();
      if(s > 0.0) return 1;
      if(s < 0.0) return -1;
      return 0;
     }
  };


//+------------------------------------------------------------------+
//|                                                 TrendStrength.mqh |
//|  Quantifies how strong/persistent the current trend is, so the   |
//|  EA can trade only high-quality trends. Combines ADX level, EMA  |
//|  slope (normalized by ATR), and price distance from equilibrium  |
//|  (the slow EMA). Returns a strength score in [0, 1] plus the      |
//|  trend direction.                                                |
//+------------------------------------------------------------------+


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


//+------------------------------------------------------------------+
//|                                               MultiTimeframe.mqh |
//|  Establishes higher-timeframe directional bias so the EA only    |
//|  takes lower-timeframe setups aligned with the broader context.  |
//|  Bias is the agreement of an EMA-trend read on two higher TFs.   |
//+------------------------------------------------------------------+


class CMultiTimeframe
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_htf1;
   ENUM_TIMEFRAMES m_htf2;
   int             m_hEmaFast1, m_hEmaSlow1;
   int             m_hEmaFast2, m_hEmaSlow2;

public:
                     CMultiTimeframe(void) : m_hEmaFast1(INVALID_HANDLE), m_hEmaSlow1(INVALID_HANDLE),
                                              m_hEmaFast2(INVALID_HANDLE), m_hEmaSlow2(INVALID_HANDLE) {}

   bool              Init(const string symbol, const ENUM_TIMEFRAMES htf1, const ENUM_TIMEFRAMES htf2,
                           const int emaFast, const int emaSlow)
     {
      m_symbol = symbol;
      m_htf1   = htf1;
      m_htf2   = htf2;

      m_hEmaFast1 = iMA(symbol, htf1, emaFast, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaSlow1 = iMA(symbol, htf1, emaSlow, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaFast2 = iMA(symbol, htf2, emaFast, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaSlow2 = iMA(symbol, htf2, emaSlow, 0, MODE_EMA, PRICE_CLOSE);

      if(m_hEmaFast1 == INVALID_HANDLE || m_hEmaSlow1 == INVALID_HANDLE ||
         m_hEmaFast2 == INVALID_HANDLE || m_hEmaSlow2 == INVALID_HANDLE)
        {
         Print("CMultiTimeframe: failed to create indicator handles");
         return false;
        }
      return true;
     }

   void              Deinit(void)
     {
      if(m_hEmaFast1 != INVALID_HANDLE) IndicatorRelease(m_hEmaFast1);
      if(m_hEmaSlow1 != INVALID_HANDLE) IndicatorRelease(m_hEmaSlow1);
      if(m_hEmaFast2 != INVALID_HANDLE) IndicatorRelease(m_hEmaFast2);
      if(m_hEmaSlow2 != INVALID_HANDLE) IndicatorRelease(m_hEmaSlow2);
     }

   //--- +1 bullish (both HTFs agree up), -1 bearish (both agree down), 0 mixed/neutral
   int               Bias(void)
     {
      int b1 = TfBias(m_hEmaFast1, m_hEmaSlow1);
      int b2 = TfBias(m_hEmaFast2, m_hEmaSlow2);
      if(b1 == 1 && b2 == 1)   return 1;
      if(b1 == -1 && b2 == -1) return -1;
      return 0;
     }

private:
   int               TfBias(const int hFast, const int hSlow)
     {
      double fast[], slow[];
      ArraySetAsSeries(fast, true);
      ArraySetAsSeries(slow, true);
      if(CopyBuffer(hFast, 0, 0, 1, fast) < 1) return 0;
      if(CopyBuffer(hSlow, 0, 0, 1, slow) < 1) return 0;
      if(fast[0] > slow[0]) return 1;
      if(fast[0] < slow[0]) return -1;
      return 0;
     }
  };


//+------------------------------------------------------------------+
//|                                             ConfluenceEngine.mqh |
//|  Aggregates every analysis module into a single scored decision. |
//|  A trade fires only when enough independent confirmations agree  |
//|  on direction (confidence >= threshold). Confidence is a         |
//|  transparent weighted tally so each contribution is auditable.   |
//+------------------------------------------------------------------+



class CConfluenceEngine
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;

   //--- references to the analysis modules (owned by the main EA)
   CRegimeDetector  *m_regime;
   CMarketStructure *m_structure;
   CMomentumEngine  *m_momentum;
   CTrendStrength   *m_trend;
   CMultiTimeframe  *m_mtf;

   //--- own handles for raw entry triggers + stop sizing
   int             m_hAtr;
   int             m_hEmaFast;
   int             m_hEmaSlow;
   int             m_hRsi;
   int             m_hBands;
   double          m_rsiOverbought;
   double          m_rsiOversold;

   double          m_minConfidence;

public:
                     CConfluenceEngine(void) : m_regime(NULL), m_structure(NULL), m_momentum(NULL),
                                                m_trend(NULL), m_mtf(NULL), m_hAtr(INVALID_HANDLE),
                                                m_hEmaFast(INVALID_HANDLE), m_hEmaSlow(INVALID_HANDLE),
                                                m_hRsi(INVALID_HANDLE), m_hBands(INVALID_HANDLE) {}

   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                           CRegimeDetector *regime, CMarketStructure *structure,
                           CMomentumEngine *momentum, CTrendStrength *trend, CMultiTimeframe *mtf,
                           const int emaFast, const int emaSlow, const int atrPeriod,
                           const int rsiPeriod, const double rsiOverbought, const double rsiOversold,
                           const int bandsPeriod, const double bandsDeviation,
                           const double minConfidence)
     {
      m_symbol        = symbol;
      m_tf            = tf;
      m_regime        = regime;
      m_structure     = structure;
      m_momentum      = momentum;
      m_trend         = trend;
      m_mtf           = mtf;
      m_rsiOverbought = rsiOverbought;
      m_rsiOversold   = rsiOversold;
      m_minConfidence = minConfidence;

      m_hAtr     = iATR(symbol, tf, atrPeriod);
      m_hEmaFast = iMA(symbol, tf, emaFast, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaSlow = iMA(symbol, tf, emaSlow, 0, MODE_EMA, PRICE_CLOSE);
      m_hRsi     = iRSI(symbol, tf, rsiPeriod, PRICE_CLOSE);
      m_hBands   = iBands(symbol, tf, bandsPeriod, 0, bandsDeviation, PRICE_CLOSE);

      if(m_hAtr == INVALID_HANDLE || m_hEmaFast == INVALID_HANDLE || m_hEmaSlow == INVALID_HANDLE ||
         m_hRsi == INVALID_HANDLE || m_hBands == INVALID_HANDLE)
        {
         Print("CConfluenceEngine: failed to create indicator handles");
         return false;
        }
      if(m_regime == NULL || m_structure == NULL || m_momentum == NULL || m_trend == NULL || m_mtf == NULL)
        {
         Print("CConfluenceEngine: one or more module references are NULL");
         return false;
        }
      return true;
     }

   void              Deinit(void)
     {
      if(m_hAtr     != INVALID_HANDLE) IndicatorRelease(m_hAtr);
      if(m_hEmaFast != INVALID_HANDLE) IndicatorRelease(m_hEmaFast);
      if(m_hEmaSlow != INVALID_HANDLE) IndicatorRelease(m_hEmaSlow);
      if(m_hRsi     != INVALID_HANDLE) IndicatorRelease(m_hRsi);
      if(m_hBands   != INVALID_HANDLE) IndicatorRelease(m_hBands);
     }

   double            GetAtr(void)
     {
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_hAtr, 0, 0, 1, buf) < 1) return 0.0;
      return buf[0];
     }

   //--- adaptive callers (e.g. the OODA feedback loop) may move the threshold
   void              SetMinConfidence(const double c) { m_minConfidence = MathMax(0.0, MathMin(1.0, c)); }
   double            MinConfidence(void) const        { return m_minConfidence; }

   //--- the full confluence decision
   SConfluenceResult Evaluate(void)
     {
      SConfluenceResult res;
      res.signal     = SIGNAL_NONE;
      res.confidence = 0.0;
      res.reason     = "";
      res.atr        = GetAtr();
      if(res.atr <= 0.0)
        {
         res.reason = "no ATR";
         return res;
        }

      ENUM_REGIME regime = m_regime.Classify();
      int         htf    = m_mtf.Bias();

      int    tDir = 0;
      double tStr = m_trend.Strength(tDir);

      double mom  = m_momentum.Score();
      int    mDir = (mom > 0.0) ? 1 : ((mom < 0.0) ? -1 : 0);

      ENUM_STRUCTURE_BIAS sBias = m_structure.Bias();
      bool   bos   = m_structure.HadBOS();
      bool   choch = m_structure.HadCHoCH();

      bool trendTrade = CRegimeDetector::IsTrendRegime(regime);

      //--- choose a candidate direction
      int candidate = 0;
      if(trendTrade)
        {
         int rd = CRegimeDetector::RegimeDirection(regime);
         candidate = (rd != 0) ? rd : mDir; // breakout has no fixed dir => use momentum
        }
      else
        {
         candidate = RawMeanReversionSignal(); // range/compression => mean reversion
        }

      if(candidate == 0)
        {
         res.reason = "no candidate direction";
         return res;
        }

      //--- veto: a change of character against the candidate signals reversal risk
      if(choch && sBias != STRUCT_NEUTRAL && (int)sBias != candidate)
        {
         res.reason = "CHoCH against candidate";
         return res;
        }

      //--- weighted confirmation tally
      double conf = 0.0;
      string why  = "";

      if(htf == candidate)                         { conf += 0.25; why += "HTF+ "; }
      else if(htf != 0 && htf != candidate)        { conf -= 0.15; why += "HTF- "; }

      if((int)sBias == candidate)                  { conf += 0.20; why += "STR+ "; }

      if(mDir == candidate)                        { conf += 0.20 * MathMin(1.0, MathAbs(mom) / 0.5); why += "MOM+ "; }

      if(trendTrade && tDir == candidate)          { conf += 0.20 * tStr; why += "TRD+ "; }
      else if(!trendTrade)                         { conf += 0.10; why += "MRbase "; }

      int trig = trendTrade ? RawTrendTrigger() : RawMeanReversionSignal();
      if(trig == candidate)                        { conf += 0.15; why += "TRG+ "; }

      if(trendTrade && bos)                        { conf += 0.05; why += "BOS+ "; }

      conf = MathMax(0.0, MathMin(1.0, conf));

      res.confidence = conf;
      res.reason     = StringFormat("regime=%s dir=%d conf=%.2f [%s]",
                                    RegimeName(regime), candidate, conf, why);

      if(conf >= m_minConfidence)
         res.signal = (candidate == 1) ? SIGNAL_BUY : SIGNAL_SELL;

      return res;
     }

private:
   //--- EMA-crossover trigger for trend regimes
   int               RawTrendTrigger(void)
     {
      double fast[], slow[];
      ArraySetAsSeries(fast, true);
      ArraySetAsSeries(slow, true);
      if(CopyBuffer(m_hEmaFast, 0, 0, 3, fast) < 3) return 0;
      if(CopyBuffer(m_hEmaSlow, 0, 0, 3, slow) < 3) return 0;

      if(fast[2] < slow[2] && fast[1] > slow[1]) return 1;
      if(fast[2] > slow[2] && fast[1] < slow[1]) return -1;
      //--- also treat a sustained separation as a soft trigger in the trend direction
      if(fast[1] > slow[1]) return 1;
      if(fast[1] < slow[1]) return -1;
      return 0;
     }

   //--- RSI + Bollinger extreme trigger for range/compression regimes
   int               RawMeanReversionSignal(void)
     {
      double rsi[], upper[], lower[];
      ArraySetAsSeries(rsi, true);
      ArraySetAsSeries(upper, true);
      ArraySetAsSeries(lower, true);
      if(CopyBuffer(m_hRsi, 0, 0, 1, rsi) < 1) return 0;
      if(CopyBuffer(m_hBands, 1, 0, 1, upper) < 1) return 0;
      if(CopyBuffer(m_hBands, 2, 0, 1, lower) < 1) return 0;

      double close0 = iClose(m_symbol, m_tf, 0);
      if(close0 <= lower[0] && rsi[0] <= m_rsiOversold)   return 1;
      if(close0 >= upper[0] && rsi[0] >= m_rsiOverbought) return -1;
      return 0;
     }

   string            RegimeName(const ENUM_REGIME r)
     {
      switch(r)
        {
         case REGIME_STRONG_UPTREND:   return "STRONG_UP";
         case REGIME_WEAK_UPTREND:     return "WEAK_UP";
         case REGIME_STRONG_DOWNTREND: return "STRONG_DN";
         case REGIME_WEAK_DOWNTREND:   return "WEAK_DN";
         case REGIME_RANGE:            return "RANGE";
         case REGIME_BREAKOUT:         return "BREAKOUT";
         case REGIME_COMPRESSION:      return "COMPRESSION";
        }
      return "UNKNOWN";
     }
  };


//+------------------------------------------------------------------+
//|                                                   OodaEngine.mqh |
//|  OODA decision cycle: Observe -> Orient -> Decide (Act happens   |
//|  in the main EA via CTradeManager), plus the Feedback stage that |
//|  makes God mode adaptive: a rolling win/loss buffer eases the    |
//|  confluence threshold and boosts risk on hot streaks, and        |
//|  tightens/cuts them faster on cold streaks. All adaptation is    |
//|  bounded — the SafetyGuard and RiskManager hard caps still rule. |
//+------------------------------------------------------------------+



//--- snapshot of market state gathered in the Observe stage
struct SObservation
  {
   double      atr;
   ENUM_REGIME regime;
   long        spreadPoints;
  };

//--- output of the Decide stage
struct SDecision
  {
   ENUM_SIGNAL signal;
   double      confidence;
   double      riskPercent;   // requested risk; RiskManager still hard-caps it
   double      slDistance;
   double      tpDistance;
   bool        useTrailing;
   string      reason;
  };

#define OODA_RESULT_CAPACITY 32

class COodaEngine
  {
private:
   string             m_symbol;
   CRegimeDetector   *m_regime;
   CConfluenceEngine *m_confluence;

   //--- adaptive state
   bool     m_godMode;
   double   m_baseConfidence;     // threshold when there is no streak evidence
   double   m_minConfidence;      // most aggressive threshold adaptation may reach
   double   m_maxConfidence;      // most defensive threshold after losses
   double   m_dynamicConfidence;
   double   m_riskBoostMax;       // risk multiplier ceiling on winning streaks
   double   m_riskMultiplier;

   int      m_results[OODA_RESULT_CAPACITY]; // ring buffer: 1 = win, -1 = loss
   int      m_resultCount;
   int      m_resultHead;

public:
                     COodaEngine(void) : m_regime(NULL), m_confluence(NULL), m_godMode(false),
                                          m_dynamicConfidence(0.6), m_riskMultiplier(1.0),
                                          m_resultCount(0), m_resultHead(0) {}

   bool              Init(const string symbol, CRegimeDetector *regime, CConfluenceEngine *confluence,
                           const bool godMode, const double baseConfidence,
                           const double minConfidence, const double maxConfidence,
                           const double riskBoostMax)
     {
      m_symbol            = symbol;
      m_regime            = regime;
      m_confluence        = confluence;
      m_godMode           = godMode;
      m_baseConfidence    = baseConfidence;
      m_minConfidence     = MathMin(minConfidence, baseConfidence);
      m_maxConfidence     = MathMax(maxConfidence, baseConfidence);
      m_dynamicConfidence = baseConfidence;
      m_riskBoostMax      = MathMax(1.0, riskBoostMax);
      m_riskMultiplier    = 1.0;
      m_resultCount       = 0;
      m_resultHead        = 0;
      ArrayInitialize(m_results, 0);

      if(m_regime == NULL || m_confluence == NULL)
        {
         Print("COodaEngine: NULL module reference");
         return false;
        }
      return true;
     }

   //--- OBSERVE: gather the market snapshot the rest of the cycle runs on
   bool              Observe(SObservation &obs)
     {
      obs.atr          = m_confluence.GetAtr();
      obs.regime       = m_regime.Classify();
      obs.spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      return (obs.atr > 0.0);
     }

   //--- ORIENT + DECIDE: confluence evaluation under the adaptive threshold,
   //    then translate the verdict into concrete trade parameters
   bool              Decide(const SObservation &obs, SDecision &out,
                             const double atrStopMult, const double atrTpMult,
                             const double baseRiskPercent)
     {
      m_confluence.SetMinConfidence(m_dynamicConfidence);
      SConfluenceResult c = m_confluence.Evaluate();

      out.signal      = c.signal;
      out.confidence  = c.confidence;
      out.slDistance  = obs.atr * atrStopMult;

      //--- in god mode, stretch targets and trail when the regime is hot
      double tpMult = atrTpMult;
      bool hotRegime = (obs.regime == REGIME_BREAKOUT ||
                        obs.regime == REGIME_STRONG_UPTREND ||
                        obs.regime == REGIME_STRONG_DOWNTREND);
      if(m_godMode && hotRegime)
         tpMult *= 1.5;
      out.tpDistance  = obs.atr * tpMult;
      out.useTrailing = m_godMode;

      //--- risk request: base * streak multiplier * confidence scaling.
      //    RiskManager clamps this to its hard cap regardless.
      out.riskPercent = baseRiskPercent * m_riskMultiplier * (0.5 + 0.5 * c.confidence);

      out.reason = c.reason + StringFormat(" | ooda: thr=%.2f riskX=%.2f",
                                           m_dynamicConfidence, m_riskMultiplier);
      return (out.signal != SIGNAL_NONE);
     }

   //--- FEEDBACK: closes the loop; call on every realized trade result
   void              RegisterTradeResult(const bool win)
     {
      m_results[m_resultHead] = win ? 1 : -1;
      m_resultHead = (m_resultHead + 1) % OODA_RESULT_CAPACITY;
      if(m_resultCount < OODA_RESULT_CAPACITY)
         m_resultCount++;
      Adapt();
     }

   double            DynamicConfidence(void) const { return m_dynamicConfidence; }
   double            RiskMultiplier(void)    const { return m_riskMultiplier; }

private:
   //--- asymmetric adaptation: loosen slowly on evidence of edge,
   //    tighten and de-risk fast when the edge fades
   void              Adapt(void)
     {
      if(!m_godMode)
         return;
      if(m_resultCount < 8) // not enough evidence to adapt yet
         return;

      int wins = 0;
      for(int i = 0; i < m_resultCount; i++)
         if(m_results[i] == 1)
            wins++;
      double winRate = (double)wins / m_resultCount;

      if(winRate >= 0.55)
        {
         m_dynamicConfidence = MathMax(m_minConfidence, m_dynamicConfidence - 0.02);
         m_riskMultiplier    = MathMin(m_riskBoostMax, m_riskMultiplier + 0.05);
        }
      else if(winRate <= 0.45)
        {
         m_dynamicConfidence = MathMin(m_maxConfidence, m_dynamicConfidence + 0.03);
         m_riskMultiplier    = MathMax(0.5, m_riskMultiplier - 0.10);
        }
      else
        {
         //--- drift back toward neutral in the dead zone
         if(m_dynamicConfidence < m_baseConfidence) m_dynamicConfidence = MathMin(m_baseConfidence, m_dynamicConfidence + 0.01);
         if(m_dynamicConfidence > m_baseConfidence) m_dynamicConfidence = MathMax(m_baseConfidence, m_dynamicConfidence - 0.01);
         if(m_riskMultiplier > 1.0) m_riskMultiplier = MathMax(1.0, m_riskMultiplier - 0.05);
         if(m_riskMultiplier < 1.0) m_riskMultiplier = MathMin(1.0, m_riskMultiplier + 0.05);
        }
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

public:
                     CSafetyGuard(void) : m_consecutiveLosses(0), m_tradingHalted(false) {}

   void              Init(const string symbol, const double maxDailyLossPercent,
                           const double maxDrawdownPercent, const int maxConsecutiveLosses,
                           const double maxSpreadPoints)
     {
      m_symbol               = symbol;
      m_maxDailyLossPercent  = maxDailyLossPercent;
      m_maxDrawdownPercent   = maxDrawdownPercent;
      m_maxConsecutiveLosses = maxConsecutiveLosses;
      m_maxSpreadPoints      = maxSpreadPoints;

      m_startEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dayStartEquity = m_startEquity;
      m_currentDay     = TimeCurrent() - (TimeCurrent() % 86400);
      m_consecutiveLosses = 0;
      m_tradingHalted     = false;
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

   bool              IsHalted(void) const { return m_tradingHalted; }
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
   double   m_regimeProfit[7];
   int      m_regimeCount[7];

public:
                     CPerformanceTracker(void) { Reset(); }

   void              Reset(void)
     {
      m_wins = 0; m_losses = 0;
      m_grossProfit = 0.0; m_grossLoss = 0.0;
      m_peakEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      m_maxDrawdown = 0.0;
      for(int i = 0; i < 7; i++) { m_regimeProfit[i] = 0.0; m_regimeCount[i] = 0; }
     }

   //--- call whenever a position closes
   void              RecordClosedTrade(const double profit, const ENUM_REGIME regimeAtEntry)
     {
      if(profit >= 0.0) { m_wins++;   m_grossProfit += profit; }
      else              { m_losses++; m_grossLoss   += -profit; }

      int idx = (int)regimeAtEntry;
      if(idx >= 0 && idx < 7)
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
      for(int i = 0; i < 7; i++)
         if(m_regimeCount[i] > 0)
            PrintFormat("  regime[%d]: trades=%d  netProfit=%.2f", i, m_regimeCount[i], m_regimeProfit[i]);
     }
  };


//--- General
input ulong           InpMagicNumber       = 750001;
input ENUM_TIMEFRAMES InpTimeframe         = PERIOD_M5;   // trade-setup timeframe
input ENUM_TIMEFRAMES InpHtf1              = PERIOD_M15;  // intermediate bias
input ENUM_TIMEFRAMES InpHtf2              = PERIOD_H1;   // overall bias
input bool            InpTradeOnNewBarOnly = true;

//--- Indicator periods (shared where sensible)
input int    InpEmaFast            = 20;
input int    InpEmaSlow            = 50;
input int    InpAdxPeriod          = 14;
input int    InpRsiPeriod          = 14;
input int    InpBandsPeriod        = 20;
input double InpBandsDeviation     = 2.0;
input int    InpAtrPeriod          = 14;

//--- Regime detection
input double InpAdxTrendThreshold  = 22.0;
input double InpAdxStrongThreshold = 30.0;
input double InpAtrExpansionRatio  = 1.5;   // ATR vs 50-bar avg to call a breakout
input double InpBbCompressionRatio = 0.7;   // BB width vs 50-bar avg to call compression
input double InpRsiOverbought      = 70.0;
input double InpRsiOversold        = 30.0;

//--- Market structure
input int    InpFractalStrength    = 2;
input int    InpStructureLookback  = 120;

//--- Momentum / trend strength
input int    InpRocPeriod          = 10;
input int    InpMomentumMaxRun     = 5;
input double InpAdxNormalizer      = 50.0;
input int    InpSlopeLookback      = 5;

//--- Confluence
input double InpMinConfidence      = 0.60;  // base threshold; OODA adapts around it

//--- God mode (adaptive-aggressive OODA loop)
input bool   InpGodMode            = true;
input double InpGodMinConfidence   = 0.50;  // most aggressive adaptive threshold
input double InpGodMaxConfidence   = 0.75;  // most defensive adaptive threshold
input double InpGodRiskBoostMax    = 1.5;   // risk multiplier ceiling on hot streaks
input int    InpMaxPositions       = 3;     // pyramiding cap, same-direction only (1 = off)
input double InpTrailAtrMult       = 2.0;   // ATR trailing distance (god mode)

//--- Risk management
input double InpRiskPercent        = 1.0;   // base risk per trade, % equity
input double InpMaxRiskPercent     = 2.0;   // hard cap, adaptive requests cannot exceed
input double InpAtrStopMultiplier  = 1.5;
input double InpAtrTakeProfitMult  = 3.0;

//--- Safety guard
input double InpMaxDailyLossPercent = 5.0;
input double InpMaxDrawdownPercent  = 15.0;
input int    InpMaxConsecutiveLoss  = 4;
input double InpMaxSpreadPoints     = 500;

//--- Trade management
input int    InpSlippagePoints      = 30;
input double InpBreakevenAtrMult    = 1.0;
input double InpPartialCloseAtrMult = 2.0;
input double InpPartialClosePercent = 50.0;

CRegimeDetector     g_regime;
CMarketStructure    g_structure;
CMomentumEngine     g_momentum;
CTrendStrength      g_trend;
CMultiTimeframe     g_mtf;
CConfluenceEngine   g_confluence;
COodaEngine         g_ooda;
CRiskManager        g_risk;
CSafetyGuard        g_safety;
CTradeManager       g_trades;
CPerformanceTracker g_perf;

datetime    g_lastBarTime   = 0;
ENUM_REGIME g_regimeAtEntry = REGIME_RANGE;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_regime.Init(_Symbol, InpTimeframe, InpAdxPeriod, InpAdxTrendThreshold, InpAdxStrongThreshold,
                     InpEmaFast, InpEmaSlow, InpAtrPeriod, InpBandsPeriod, InpBandsDeviation,
                     InpAtrExpansionRatio, InpBbCompressionRatio))
      return INIT_FAILED;

   g_structure.Init(_Symbol, InpTimeframe, InpFractalStrength, InpStructureLookback);

   if(!g_momentum.Init(_Symbol, InpTimeframe, InpAtrPeriod, InpRocPeriod, InpMomentumMaxRun))
      return INIT_FAILED;

   if(!g_trend.Init(_Symbol, InpTimeframe, InpAdxPeriod, InpEmaFast, InpEmaSlow, InpAtrPeriod,
                    InpAdxNormalizer, InpSlopeLookback))
      return INIT_FAILED;

   if(!g_mtf.Init(_Symbol, InpHtf1, InpHtf2, InpEmaFast, InpEmaSlow))
      return INIT_FAILED;

   if(!g_confluence.Init(_Symbol, InpTimeframe,
                         GetPointer(g_regime), GetPointer(g_structure), GetPointer(g_momentum),
                         GetPointer(g_trend), GetPointer(g_mtf),
                         InpEmaFast, InpEmaSlow, InpAtrPeriod,
                         InpRsiPeriod, InpRsiOverbought, InpRsiOversold,
                         InpBandsPeriod, InpBandsDeviation, InpMinConfidence))
      return INIT_FAILED;

   if(!g_ooda.Init(_Symbol, GetPointer(g_regime), GetPointer(g_confluence),
                   InpGodMode, InpMinConfidence,
                   InpGodMinConfidence, InpGodMaxConfidence, InpGodRiskBoostMax))
      return INIT_FAILED;

   g_risk.Init(_Symbol, InpRiskPercent, InpMaxRiskPercent);
   g_safety.Init(_Symbol, InpMaxDailyLossPercent, InpMaxDrawdownPercent,
                 InpMaxConsecutiveLoss, InpMaxSpreadPoints);
   g_trades.Init(_Symbol, InpMagicNumber, InpSlippagePoints,
                 InpBreakevenAtrMult, InpPartialCloseAtrMult, InpPartialClosePercent);
   g_trades.SetTrailing(InpGodMode, InpTrailAtrMult);
   g_perf.Reset();

   Print("V75EA v3 initialized on ", _Symbol,
         " setup TF=", EnumToString(InpTimeframe),
         " godMode=", (InpGodMode ? "ON" : "OFF"));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_perf.PrintSummary();
   g_regime.Deinit();
   g_momentum.Deinit();
   g_trend.Deinit();
   g_mtf.Deinit();
   g_confluence.Deinit();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   g_safety.OnNewTick();
   g_perf.UpdateDrawdown();

   //--- OBSERVE
   SObservation obs;
   if(!g_ooda.Observe(obs))
      return;

   //--- ACT (management): breakeven / partial / trailing on every tick
   g_trades.ManageOpenPositions(obs.atr);

   bool newBar = IsNewBar();
   if(InpTradeOnNewBarOnly && !newBar)
      return;
   if(newBar)
      g_structure.Update();

   if(!g_safety.IsTradingAllowed())
      return;

   int maxPositions = MathMax(1, InpMaxPositions);
   int openCount    = g_trades.CountOpenPositions();
   if(openCount >= maxPositions)
      return;

   //--- ORIENT + DECIDE
   SDecision decision;
   if(!g_ooda.Decide(obs, decision, InpAtrStopMultiplier, InpAtrTakeProfitMult, InpRiskPercent))
      return;

   //--- pyramiding: additional entries only in the direction of existing exposure
   if(openCount > 0)
     {
      int haveDir = g_trades.OpenDirection();
      int wantDir = (decision.signal == SIGNAL_BUY) ? 1 : -1;
      if(haveDir == 0 || haveDir != wantDir)
         return;
     }

   //--- ACT (entry)
   g_risk.SetRiskPercent(decision.riskPercent); // hard-capped inside RiskManager
   double lots = g_risk.CalculateLotSize(decision.slDistance);

   if(g_trades.OpenTrade(decision.signal, lots, decision.slDistance, decision.tpDistance))
     {
      g_regimeAtEntry = obs.regime;
      PrintFormat("V75EA entry: %s lots=%.2f conf=%.2f | %s",
                  (decision.signal == SIGNAL_BUY ? "BUY" : "SELL"),
                  lots, decision.confidence, decision.reason);
     }
  }

//+------------------------------------------------------------------+
//| FEEDBACK: realized results close the OODA loop and feed the      |
//| safety and performance modules                                   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
     {
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      bool win = (profit >= 0.0);
      g_safety.RegisterTradeResult(win);
      g_ooda.RegisterTradeResult(win);
      g_perf.RecordClosedTrade(profit, g_regimeAtEntry);
     }
  }

//+------------------------------------------------------------------+
bool IsNewBar(void)
  {
   datetime t = iTime(_Symbol, InpTimeframe, 0);
   if(t != g_lastBarTime)
     {
      g_lastBarTime = t;
      return true;
     }
   return false;
  }
