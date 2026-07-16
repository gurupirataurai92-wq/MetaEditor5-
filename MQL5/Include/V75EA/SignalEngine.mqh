//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh |
//|  Regime-switching signal generator: ADX decides whether the      |
//|  market is trending or ranging, then routes to EMA-crossover     |
//|  (trend) or RSI/Bollinger extremes (mean-reversion) logic.       |
//+------------------------------------------------------------------+
#property strict

enum ENUM_SIGNAL
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

enum ENUM_MARKET_REGIME
  {
   REGIME_TREND = 0,
   REGIME_RANGE = 1
  };

class CSignalEngine
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;

   int             m_hEmaFast;
   int             m_hEmaSlow;
   int             m_hAdx;
   int             m_hRsi;
   int             m_hBands;
   int             m_hAtr;

   double          m_adxTrendThreshold;
   double          m_rsiOverbought;
   double          m_rsiOversold;

public:
                     CSignalEngine(void) : m_hEmaFast(INVALID_HANDLE), m_hEmaSlow(INVALID_HANDLE),
                                            m_hAdx(INVALID_HANDLE), m_hRsi(INVALID_HANDLE),
                                            m_hBands(INVALID_HANDLE), m_hAtr(INVALID_HANDLE) {}

   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                           const int emaFast, const int emaSlow,
                           const int adxPeriod, const double adxThreshold,
                           const int rsiPeriod, const double rsiOverbought, const double rsiOversold,
                           const int bandsPeriod, const double bandsDeviation,
                           const int atrPeriod)
     {
      m_symbol            = symbol;
      m_tf                = tf;
      m_adxTrendThreshold = adxThreshold;
      m_rsiOverbought     = rsiOverbought;
      m_rsiOversold       = rsiOversold;

      m_hEmaFast = iMA(m_symbol, m_tf, emaFast, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaSlow = iMA(m_symbol, m_tf, emaSlow, 0, MODE_EMA, PRICE_CLOSE);
      m_hAdx     = iADX(m_symbol, m_tf, adxPeriod);
      m_hRsi     = iRSI(m_symbol, m_tf, rsiPeriod, PRICE_CLOSE);
      m_hBands   = iBands(m_symbol, m_tf, bandsPeriod, 0, bandsDeviation, PRICE_CLOSE);
      m_hAtr     = iATR(m_symbol, m_tf, atrPeriod);

      if(m_hEmaFast == INVALID_HANDLE || m_hEmaSlow == INVALID_HANDLE ||
         m_hAdx == INVALID_HANDLE || m_hRsi == INVALID_HANDLE ||
         m_hBands == INVALID_HANDLE || m_hAtr == INVALID_HANDLE)
        {
         Print("CSignalEngine: failed to create one or more indicator handles");
         return false;
        }
      return true;
     }

   void              Deinit(void)
     {
      if(m_hEmaFast != INVALID_HANDLE) IndicatorRelease(m_hEmaFast);
      if(m_hEmaSlow != INVALID_HANDLE) IndicatorRelease(m_hEmaSlow);
      if(m_hAdx     != INVALID_HANDLE) IndicatorRelease(m_hAdx);
      if(m_hRsi     != INVALID_HANDLE) IndicatorRelease(m_hRsi);
      if(m_hBands   != INVALID_HANDLE) IndicatorRelease(m_hBands);
      if(m_hAtr     != INVALID_HANDLE) IndicatorRelease(m_hAtr);
     }

   //--- Current ATR value, used for stop-loss/take-profit distance and trade management
   double            GetAtr(void)
     {
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_hAtr, 0, 0, 1, buf) < 1)
         return 0.0;
      return buf[0];
     }

   ENUM_MARKET_REGIME GetRegime(void)
     {
      double adxBuf[];
      ArraySetAsSeries(adxBuf, true);
      if(CopyBuffer(m_hAdx, 0, 0, 1, adxBuf) < 1)
         return REGIME_RANGE;

      return (adxBuf[0] >= m_adxTrendThreshold) ? REGIME_TREND : REGIME_RANGE;
     }

   ENUM_SIGNAL       GetSignal(void)
     {
      return (GetRegime() == REGIME_TREND) ? GetTrendSignal() : GetMeanReversionSignal();
     }

private:
   ENUM_SIGNAL       GetTrendSignal(void)
     {
      double fastBuf[], slowBuf[];
      ArraySetAsSeries(fastBuf, true);
      ArraySetAsSeries(slowBuf, true);

      if(CopyBuffer(m_hEmaFast, 0, 0, 3, fastBuf) < 3) return SIGNAL_NONE;
      if(CopyBuffer(m_hEmaSlow, 0, 0, 3, slowBuf) < 3) return SIGNAL_NONE;

      bool wasBelow = fastBuf[2] < slowBuf[2];
      bool isAbove  = fastBuf[1] > slowBuf[1];
      bool wasAbove = fastBuf[2] > slowBuf[2];
      bool isBelow  = fastBuf[1] < slowBuf[1];

      if(wasBelow && isAbove)
         return SIGNAL_BUY;
      if(wasAbove && isBelow)
         return SIGNAL_SELL;

      return SIGNAL_NONE;
     }

   ENUM_SIGNAL       GetMeanReversionSignal(void)
     {
      double rsiBuf[], upperBuf[], lowerBuf[];
      ArraySetAsSeries(rsiBuf, true);
      ArraySetAsSeries(upperBuf, true);
      ArraySetAsSeries(lowerBuf, true);

      if(CopyBuffer(m_hRsi, 0, 0, 1, rsiBuf) < 1) return SIGNAL_NONE;
      if(CopyBuffer(m_hBands, 1, 0, 1, upperBuf) < 1) return SIGNAL_NONE; // upper band buffer
      if(CopyBuffer(m_hBands, 2, 0, 1, lowerBuf) < 1) return SIGNAL_NONE; // lower band buffer

      double closePrice = iClose(m_symbol, m_tf, 0);

      if(closePrice <= lowerBuf[0] && rsiBuf[0] <= m_rsiOversold)
         return SIGNAL_BUY;

      if(closePrice >= upperBuf[0] && rsiBuf[0] >= m_rsiOverbought)
         return SIGNAL_SELL;

      return SIGNAL_NONE;
     }
  };
