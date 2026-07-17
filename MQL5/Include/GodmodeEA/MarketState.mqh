//+------------------------------------------------------------------+
//|                                                  MarketState.mqh |
//|  MODULE 2 -- Regime Engine. Evaluated on every M5 bar close.    |
//|  Two states only: TREND or STAND_DOWN. No range-fade branch --  |
//|  fading gold extremes is the classic account-killer.            |
//+------------------------------------------------------------------+
#property strict
#include "Defines.mqh"

class CMarketState
  {
private:
   string   m_symbol;
   int      m_adx_handle;
   int      m_atr_handle;
   int      m_ema_h1_handle;
   int      m_ema_m15_handle;

   double   m_atr_history[]; // trailing buffer for percentile rank
   int      m_atr_history_len;

   double   m_adx_trend_min;      // ADX(14) floor to call it TREND
   double   m_atr_percentile_min; // ATR must rank above this percentile
   int      m_ema_slope_lookback;

   ENUM_REGIME m_current_regime;
   double      m_last_adx;
   double      m_last_atr;
   double      m_last_atr_percentile;
   double      m_h1_slope;
   double      m_m15_slope;
   bool        m_atr_expanding;

public:
                     CMarketState()
     {
      m_adx_handle = INVALID_HANDLE;
      m_atr_handle = INVALID_HANDLE;
      m_ema_h1_handle = INVALID_HANDLE;
      m_ema_m15_handle = INVALID_HANDLE;
      m_atr_history_len = 200;
      m_current_regime = REGIME_STAND_DOWN;
     }

   bool Init(const string symbol, const double adx_trend_min, const double atr_percentile_min,
             const int ema_slope_lookback)
     {
      m_symbol = symbol;
      m_adx_trend_min = adx_trend_min;
      m_atr_percentile_min = atr_percentile_min;
      m_ema_slope_lookback = ema_slope_lookback;

      // Indicator handles created once in OnInit, never in OnTick.
      m_adx_handle = iADX(m_symbol, PERIOD_M5, 14);
      m_atr_handle = iATR(m_symbol, PERIOD_M5, 14);
      m_ema_h1_handle  = iMA(m_symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
      m_ema_m15_handle = iMA(m_symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);

      if(m_adx_handle == INVALID_HANDLE || m_atr_handle == INVALID_HANDLE ||
         m_ema_h1_handle == INVALID_HANDLE || m_ema_m15_handle == INVALID_HANDLE)
        {
         Print("MarketState: failed to create one or more indicator handles.");
         return false;
        }

      ArrayResize(m_atr_history, m_atr_history_len);
      ArrayInitialize(m_atr_history, 0.0);
      return true;
     }

   void Release()
     {
      if(m_adx_handle != INVALID_HANDLE) IndicatorRelease(m_adx_handle);
      if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
      if(m_ema_h1_handle != INVALID_HANDLE) IndicatorRelease(m_ema_h1_handle);
      if(m_ema_m15_handle != INVALID_HANDLE) IndicatorRelease(m_ema_m15_handle);
     }

   ENUM_REGIME   Regime() const { return m_current_regime; }
   double        LastADX() const { return m_last_adx; }
   double        LastATR() const { return m_last_atr; }
   double        LastATRPercentile() const { return m_last_atr_percentile; }
   double        H1Slope() const { return m_h1_slope; }
   double        M15Slope() const { return m_m15_slope; }
   bool          IsATRExpanding() const { return m_atr_expanding; }

   double        M15EmaValue() const
     {
      double buf[];
      if(CopyBuffer(m_ema_m15_handle, 0, 1, 1, buf) < 1) return 0.0;
      return buf[0];
     }

   ENUM_TRADE_DIR H1Dir() const
     {
      if(m_h1_slope > 0) return DIR_BUY;
      if(m_h1_slope < 0) return DIR_SELL;
      return DIR_NONE;
     }

   ENUM_TRADE_DIR M15Dir() const
     {
      if(m_m15_slope > 0) return DIR_BUY;
      if(m_m15_slope < 0) return DIR_SELL;
      return DIR_NONE;
     }

   //--- call once per new M5 bar close -----------------------------
   bool Update()
     {
      double adx_buf[];
      double atr_buf[];
      double ema_h1_buf[];
      double ema_m15_buf[];

      // CopyBuffer for a handful of bars only -- never 500.
      if(CopyBuffer(m_adx_handle, 0, 1, 3, adx_buf) < 3) return false;
      if(CopyBuffer(m_atr_handle, 0, 1, m_atr_history_len + 1, atr_buf) < m_atr_history_len + 1)
        {
         // not enough history yet (e.g. fresh chart) -- fall back to what's available
         if(CopyBuffer(m_atr_handle, 0, 1, 3, atr_buf) < 3) return false;
        }
      if(CopyBuffer(m_ema_h1_handle, 0, 1, m_ema_slope_lookback + 1, ema_h1_buf) < m_ema_slope_lookback + 1)
         return false;
      if(CopyBuffer(m_ema_m15_handle, 0, 1, m_ema_slope_lookback + 1, ema_m15_buf) < m_ema_slope_lookback + 1)
         return false;

      m_last_adx = adx_buf[ArraySize(adx_buf) - 1];
      m_last_atr = atr_buf[ArraySize(atr_buf) - 1];

      // ATR percentile rank over trailing bars actually available
      int n = ArraySize(atr_buf);
      int below = 0;
      for(int i = 0; i < n; i++)
         if(atr_buf[i] <= m_last_atr) below++;
      m_last_atr_percentile = (n > 0) ? (double)below / (double)n : 0.0;

      // volatility-of-volatility: recent half vs older half of the ATR window
      int half = n / 2;
      if(half >= 2)
        {
         double recent_avg = 0.0, older_avg = 0.0;
         for(int i = n - half; i < n; i++) recent_avg += atr_buf[i];
         for(int i = 0; i < half; i++) older_avg += atr_buf[i];
         recent_avg /= half;
         older_avg  /= half;
         m_atr_expanding = (recent_avg > older_avg);
        }
      else
         m_atr_expanding = true;

      // EMA slope on M15/H1: normalized by point so it's comparable across symbols
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0.0) point = 0.01;
      m_h1_slope  = (ema_h1_buf[ArraySize(ema_h1_buf)-1]  - ema_h1_buf[0])  / point;
      m_m15_slope = (ema_m15_buf[ArraySize(ema_m15_buf)-1] - ema_m15_buf[0]) / point;

      bool adx_trend    = (m_last_adx >= m_adx_trend_min);
      bool atr_adequate = (m_last_atr_percentile >= m_atr_percentile_min);
      bool slope_aligned = (m_h1_slope > 0 && m_m15_slope > 0) || (m_h1_slope < 0 && m_m15_slope < 0);

      m_current_regime = (adx_trend && atr_adequate && slope_aligned) ? REGIME_TREND : REGIME_STAND_DOWN;
      return true;
     }

   //--- direction implied by the current regime (for pullback/OR-break bias)
   ENUM_TRADE_DIR RegimeDirection() const
     {
      if(m_current_regime != REGIME_TREND) return DIR_NONE;
      if(m_h1_slope > 0 && m_m15_slope > 0) return DIR_BUY;
      if(m_h1_slope < 0 && m_m15_slope < 0) return DIR_SELL;
      return DIR_NONE;
     }
  };
//+------------------------------------------------------------------+
