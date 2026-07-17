//+------------------------------------------------------------------+
//|                                                 ThesisEngine.mqh |
//|  MODULE 3 -- the core innovation. A trade thesis is a           |
//|  falsifiable claim about why price should move, plus the exact  |
//|  condition that proves it wrong. Confidence=0.71 is NOT a       |
//|  thesis -- it has no causal story.                               |
//|                                                                    |
//|  Four archetypes, each separately detected/scored/tracked.       |
//|  Swing points are confirmed fractals (k bars either side), so    |
//|  they lag the live edge by k bars -- fine for structural levels, |
//|  wrong tool if you need zero-lag pivots.                         |
//+------------------------------------------------------------------+
#property strict
#include "Defines.mqh"

class CThesisEngine
  {
private:
   string          m_symbol;
   int             m_swing_lookback;
   int             m_fractal_k;
   int             m_or_bars;
   int             m_london_open_hour_gmt;

   double          m_or_range_high;
   double          m_or_range_low;
   datetime        m_or_date;
   int             m_or_bars_seen;
   bool            m_or_formed;

   ArchetypeStats  m_stats[ARCH_COUNT];

   bool FindLastSwingHigh(double &level, datetime &out_time, const int max_bars)
     {
      int k = m_fractal_k;
      int need = max_bars + 2*k;
      double high[]; datetime time[];
      if(CopyHigh(m_symbol, PERIOD_M5, 1, need, high) < need) return false;
      if(CopyTime(m_symbol, PERIOD_M5, 1, need, time) < need) return false;
      int n = ArraySize(high);
      for(int i = n-1-k; i >= k; i--)
        {
         bool isHigh = true;
         for(int j=1; j<=k; j++)
           {
            if(high[i-j] > high[i] || high[i+j] > high[i]) { isHigh = false; break; }
           }
         if(isHigh)
           {
            level = high[i];
            out_time = time[i];
            return true;
           }
        }
      return false;
     }

   bool FindLastSwingLow(double &level, datetime &out_time, const int max_bars)
     {
      int k = m_fractal_k;
      int need = max_bars + 2*k;
      double low[]; datetime time[];
      if(CopyLow(m_symbol, PERIOD_M5, 1, need, low) < need) return false;
      if(CopyTime(m_symbol, PERIOD_M5, 1, need, time) < need) return false;
      int n = ArraySize(low);
      for(int i = n-1-k; i >= k; i--)
        {
         bool isLow = true;
         for(int j=1; j<=k; j++)
           {
            if(low[i-j] < low[i] || low[i+j] < low[i]) { isLow = false; break; }
           }
         if(isLow)
           {
            level = low[i];
            out_time = time[i];
            return true;
           }
        }
      return false;
     }

   bool DetectSweep(ThesisSignal &sig)
     {
      double low1[], high1[], close1[];
      if(CopyLow(m_symbol, PERIOD_M5, 1, 1, low1) < 1) return false;
      if(CopyHigh(m_symbol, PERIOD_M5, 1, 1, high1) < 1) return false;
      if(CopyClose(m_symbol, PERIOD_M5, 1, 1, close1) < 1) return false;
      double lastLow = low1[0], lastHigh = high1[0], lastClose = close1[0];

      double swingLow, swingHigh; datetime t;
      if(FindLastSwingLow(swingLow, t, m_swing_lookback))
        {
         if(lastLow < swingLow && lastClose > swingLow)
           {
            sig.archetype = ARCH_LIQUIDITY_SWEEP;
            sig.direction = DIR_BUY;
            sig.trigger_price = lastHigh;
            sig.invalidation_price = swingLow;
            sig.requires_m1_confirm = true;
            return true;
           }
        }
      if(FindLastSwingHigh(swingHigh, t, m_swing_lookback))
        {
         if(lastHigh > swingHigh && lastClose < swingHigh)
           {
            sig.archetype = ARCH_LIQUIDITY_SWEEP;
            sig.direction = DIR_SELL;
            sig.trigger_price = lastLow;
            sig.invalidation_price = swingHigh;
            sig.requires_m1_confirm = true;
            return true;
           }
        }
      return false;
     }

   bool DetectORBreak(ThesisSignal &sig)
     {
      if(!m_or_formed) return false;
      double close1[];
      if(CopyClose(m_symbol, PERIOD_M5, 1, 1, close1) < 1) return false;
      double c = close1[0];
      if(c > m_or_range_high)
        {
         sig.archetype = ARCH_OR_BREAK;
         sig.direction = DIR_BUY;
         sig.trigger_price = c;
         sig.invalidation_price = m_or_range_high;
         sig.requires_m1_confirm = false;
         return true;
        }
      if(c < m_or_range_low)
        {
         sig.archetype = ARCH_OR_BREAK;
         sig.direction = DIR_SELL;
         sig.trigger_price = c;
         sig.invalidation_price = m_or_range_low;
         sig.requires_m1_confirm = false;
         return true;
        }
      return false;
     }

   bool DetectTrapReversal(ThesisSignal &sig)
     {
      int lookback = 6;
      double close_arr[];
      if(CopyClose(m_symbol, PERIOD_M5, 1, lookback+1, close_arr) < lookback+1) return false;
      double lastClose = close_arr[ArraySize(close_arr)-1];

      double swingHigh, swingLow; datetime t;
      if(FindLastSwingHigh(swingHigh, t, m_swing_lookback))
        {
         bool brokeAbove = false;
         for(int i=0; i<lookback; i++) if(close_arr[i] > swingHigh) { brokeAbove = true; break; }
         if(brokeAbove && lastClose < swingHigh)
           {
            sig.archetype = ARCH_TRAP_REVERSAL;
            sig.direction = DIR_SELL;
            sig.trigger_price = lastClose;
            sig.invalidation_price = swingHigh;
            sig.requires_m1_confirm = true;
            return true;
           }
        }
      if(FindLastSwingLow(swingLow, t, m_swing_lookback))
        {
         bool brokeBelow = false;
         for(int i=0; i<lookback; i++) if(close_arr[i] < swingLow) { brokeBelow = true; break; }
         if(brokeBelow && lastClose > swingLow)
           {
            sig.archetype = ARCH_TRAP_REVERSAL;
            sig.direction = DIR_BUY;
            sig.trigger_price = lastClose;
            sig.invalidation_price = swingLow;
            sig.requires_m1_confirm = true;
            return true;
           }
        }
      return false;
     }

   bool DetectPullback(ThesisSignal &sig, const ENUM_TRADE_DIR regimeDir, const double m15_ema_value)
     {
      if(regimeDir == DIR_NONE) return false;
      double close1[], low1[], high1[];
      if(CopyClose(m_symbol, PERIOD_M5, 1, 1, close1) < 1) return false;
      if(CopyLow(m_symbol, PERIOD_M5, 1, 1, low1) < 1) return false;
      if(CopyHigh(m_symbol, PERIOD_M5, 1, 1, high1) < 1) return false;
      double c = close1[0];

      double swingLevel; datetime t;
      if(regimeDir == DIR_BUY)
        {
         if(!FindLastSwingLow(swingLevel, t, m_swing_lookback)) return false;
         bool touchedValue = (low1[0] <= m15_ema_value);
         bool structureIntact = (c > swingLevel);
         if(touchedValue && structureIntact && c > m15_ema_value)
           {
            sig.archetype = ARCH_PULLBACK_CONTINUATION;
            sig.direction = DIR_BUY;
            sig.trigger_price = high1[0];
            sig.invalidation_price = swingLevel;
            sig.requires_m1_confirm = false;
            return true;
           }
        }
      else
        {
         if(!FindLastSwingHigh(swingLevel, t, m_swing_lookback)) return false;
         bool touchedValue = (high1[0] >= m15_ema_value);
         bool structureIntact = (c < swingLevel);
         if(touchedValue && structureIntact && c < m15_ema_value)
           {
            sig.archetype = ARCH_PULLBACK_CONTINUATION;
            sig.direction = DIR_SELL;
            sig.trigger_price = low1[0];
            sig.invalidation_price = swingLevel;
            sig.requires_m1_confirm = false;
            return true;
           }
        }
      return false;
     }

public:
                     CThesisEngine()
     {
      m_or_formed = false;
      m_or_date = 0;
      m_or_bars_seen = 0;
      m_or_range_high = -DBL_MAX;
      m_or_range_low  = DBL_MAX;
      for(int i=0; i<ARCH_COUNT; i++)
        {
         m_stats[i].trade_count = 0;
         m_stats[i].sum_r = 0.0;
         m_stats[i].sum_r_sq = 0.0;
         m_stats[i].killed = false;
        }
     }

   void Init(const string symbol, const int swing_lookback, const int fractal_k,
             const int or_bars, const int london_open_hour_gmt)
     {
      m_symbol = symbol;
      m_swing_lookback = swing_lookback;
      m_fractal_k = fractal_k;
      m_or_bars = or_bars;
      m_london_open_hour_gmt = london_open_hour_gmt;
     }

   //--- call once per new M5 bar close, maintains the opening-range state
   void UpdateOpeningRange()
     {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime today = StructToTime(dt);

      if(today != m_or_date)
        {
         m_or_date = today;
         m_or_formed = false;
         m_or_bars_seen = 0;
         m_or_range_high = -DBL_MAX;
         m_or_range_low  = DBL_MAX;
        }
      if(m_or_formed) return;

      TimeToStruct(TimeGMT(), dt);
      if(dt.hour < m_london_open_hour_gmt) return;
      if(m_or_bars_seen >= m_or_bars) { m_or_formed = true; return; }

      double high1[], low1[];
      if(CopyHigh(m_symbol, PERIOD_M5, 1, 1, high1) < 1) return;
      if(CopyLow(m_symbol, PERIOD_M5, 1, 1, low1) < 1) return;

      m_or_range_high = MathMax(m_or_range_high, high1[0]);
      m_or_range_low  = MathMin(m_or_range_low, low1[0]);
      m_or_bars_seen++;
      if(m_or_bars_seen >= m_or_bars) m_or_formed = true;
     }

   //--- run all four detectors (skipping killed archetypes), return count found
   int Evaluate(const ENUM_REGIME regime, const ENUM_TRADE_DIR regimeDir,
                const double m15_ema_value, ThesisSignal &out_signals[])
     {
      ArrayResize(out_signals, 0);
      if(regime != REGIME_TREND) return 0;

      ThesisSignal sig;
      ZeroMemory(sig);

      if(!m_stats[ARCH_LIQUIDITY_SWEEP].killed && DetectSweep(sig))
        {
         int n = ArraySize(out_signals);
         ArrayResize(out_signals, n+1);
         out_signals[n] = sig;
        }
      ZeroMemory(sig);
      if(!m_stats[ARCH_OR_BREAK].killed && DetectORBreak(sig))
        {
         int n = ArraySize(out_signals);
         ArrayResize(out_signals, n+1);
         out_signals[n] = sig;
        }
      ZeroMemory(sig);
      if(!m_stats[ARCH_TRAP_REVERSAL].killed && DetectTrapReversal(sig))
        {
         int n = ArraySize(out_signals);
         ArrayResize(out_signals, n+1);
         out_signals[n] = sig;
        }
      ZeroMemory(sig);
      if(!m_stats[ARCH_PULLBACK_CONTINUATION].killed && DetectPullback(sig, regimeDir, m15_ema_value))
        {
         int n = ArraySize(out_signals);
         ArrayResize(out_signals, n+1);
         out_signals[n] = sig;
        }

      return ArraySize(out_signals);
     }

   //--- confluence check usable by ConfidenceEngine for ANY archetype,
   //--- independent of whether SWEEP itself is the chosen archetype or killed
   bool CheckSweepConfluence(const ENUM_TRADE_DIR dir)
     {
      ThesisSignal tmp;
      ZeroMemory(tmp);
      if(!DetectSweep(tmp)) return false;
      return (tmp.direction == dir);
     }

   //--- continuous re-evaluation: is the reason we entered still true? ---
   bool IsInvalidated(const ThesisSignal &sig, const double current_price)
     {
      if(sig.direction == DIR_BUY)  return (current_price <= sig.invalidation_price);
      if(sig.direction == DIR_SELL) return (current_price >= sig.invalidation_price);
      return false;
     }

   //--- per-archetype expectancy tracking -- kill the bleeder after ~100 trades
   void RecordTradeResult(const ENUM_ARCHETYPE arch, const double r_multiple)
     {
      if(arch <= ARCH_NONE || arch >= ARCH_COUNT) return;
      m_stats[arch].trade_count++;
      m_stats[arch].sum_r += r_multiple;
      m_stats[arch].sum_r_sq += r_multiple*r_multiple;

      if(!m_stats[arch].killed && m_stats[arch].trade_count >= 100)
        {
         double mean_r = m_stats[arch].sum_r / m_stats[arch].trade_count;
         if(mean_r <= 0.0)
           {
            m_stats[arch].killed = true;
            PrintFormat("ThesisEngine: archetype %s killed after %d trades, mean R=%.3f <= 0.",
                        ArchetypeToString(arch), m_stats[arch].trade_count, mean_r);
           }
        }
     }

   bool   IsKilled(const ENUM_ARCHETYPE arch) const { return (arch>ARCH_NONE && arch<ARCH_COUNT) ? m_stats[arch].killed : false; }
   int    TradeCount(const ENUM_ARCHETYPE arch) const { return (arch>ARCH_NONE && arch<ARCH_COUNT) ? m_stats[arch].trade_count : 0; }
   double Expectancy(const ENUM_ARCHETYPE arch) const
     {
      if(arch<=ARCH_NONE || arch>=ARCH_COUNT || m_stats[arch].trade_count==0) return 0.0;
      return m_stats[arch].sum_r / m_stats[arch].trade_count;
     }
  };
//+------------------------------------------------------------------+
