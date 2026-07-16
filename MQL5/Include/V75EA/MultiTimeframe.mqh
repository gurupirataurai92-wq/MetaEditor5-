//+------------------------------------------------------------------+
//|                                               MultiTimeframe.mqh |
//|  Establishes higher-timeframe directional bias so the EA only    |
//|  takes lower-timeframe setups aligned with the broader context.  |
//|  Bias is the agreement of an EMA-trend read on two higher TFs.   |
//+------------------------------------------------------------------+
#ifndef V75EA_MULTI_TIMEFRAME_MQH
#define V75EA_MULTI_TIMEFRAME_MQH

#property strict

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

#endif // V75EA_MULTI_TIMEFRAME_MQH
