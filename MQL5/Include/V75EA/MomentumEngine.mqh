//+------------------------------------------------------------------+
//|                                               MomentumEngine.mqh |
//|  Measures momentum from price action: candle body size relative  |
//|  to ATR, runs of consecutive same-direction candles, and rate    |
//|  of change (with acceleration). Returns a signed score in        |
//|  [-1, +1] where sign is direction and magnitude is conviction.   |
//+------------------------------------------------------------------+
#ifndef V75EA_MOMENTUM_ENGINE_MQH
#define V75EA_MOMENTUM_ENGINE_MQH

#property strict

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

#endif // V75EA_MOMENTUM_ENGINE_MQH
