//+------------------------------------------------------------------+
//|                                             ConfluenceEngine.mqh |
//|  Aggregates every analysis module into a single scored decision. |
//|  A trade fires only when enough independent confirmations agree  |
//|  on direction (confidence >= threshold). Confidence is a         |
//|  transparent weighted tally so each contribution is auditable.   |
//+------------------------------------------------------------------+
#ifndef V75EA_CONFLUENCE_ENGINE_MQH
#define V75EA_CONFLUENCE_ENGINE_MQH

#property strict

#include <V75EA\Types.mqh>
#include <V75EA\RegimeDetector.mqh>
#include <V75EA\MarketStructure.mqh>
#include <V75EA\MomentumEngine.mqh>
#include <V75EA\TrendStrength.mqh>
#include <V75EA\MultiTimeframe.mqh>

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

#endif // V75EA_CONFLUENCE_ENGINE_MQH
