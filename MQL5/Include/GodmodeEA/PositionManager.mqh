//+------------------------------------------------------------------+
//|                                               PositionManager.mqh |
//|  MODULE 7 -- one position per symbol per magic, no stacking.    |
//|  Structural SL, partial-at-1R, chandelier trail, time stop,     |
//|  momentum-decay / volatility-collapse exits, weekend flat.      |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
#include "Defines.mqh"

struct OpenTradeState
  {
   ulong          ticket;
   ThesisSignal   signal;            // full thesis: archetype, direction, component scores, invalidation
   double         entry_price;
   double         initial_sl;
   double         risk_distance;     // |entry - initial_sl|, price units
   double         atr_at_entry;
   datetime       open_time;
   int            bars_since_open;
   bool           partial_done;
   double         mfe_r;
   double         mae_r;
   double         spread_at_signal;
  };

class CPositionManager
  {
private:
   string         m_symbol;
   ulong          m_magic;
   CTrade         m_trade;
   OpenTradeState m_state;
   bool           m_has_position;

   double         m_sl_atr_mult;       // 1.5x structural SL buffer
   double         m_chandelier_mult;   // 3.5-4x ATR trail
   int            m_time_stop_bars;    // 15-20 M5 bars
   double         m_time_stop_r;       // 0.5R
   double         m_vol_collapse_ratio;// e.g. 0.5 -- ATR contracted to this fraction of entry ATR

   int            m_atr_handle;
   int            m_rsi_handle;

   double AtrNow() const
     {
      double buf[];
      if(CopyBuffer(m_atr_handle, 0, 1, 1, buf) < 1) return 0.0;
      return buf[0];
     }

   double RMultiple(const double price) const
     {
      if(m_state.risk_distance <= 0.0) return 0.0;
      if(m_state.signal.direction == DIR_BUY)  return (price - m_state.entry_price) / m_state.risk_distance;
      return (m_state.entry_price - price) / m_state.risk_distance;
     }

   bool MomentumAgainst() const
     {
      double buf[];
      if(CopyBuffer(m_rsi_handle, 0, 1, 1, buf) < 1) return false;
      double rsi = buf[0];
      if(m_state.signal.direction == DIR_BUY)  return (rsi < 40.0);
      return (rsi > 60.0);
     }

public:
                     CPositionManager() { m_has_position = false; }

   bool Init(const string symbol, const ulong magic, const double sl_atr_mult,
             const double chandelier_mult, const int time_stop_bars, const double time_stop_r,
             const double vol_collapse_ratio)
     {
      m_symbol = symbol;
      m_magic = magic;
      m_sl_atr_mult = sl_atr_mult;
      m_chandelier_mult = chandelier_mult;
      m_time_stop_bars = time_stop_bars;
      m_time_stop_r = time_stop_r;
      m_vol_collapse_ratio = vol_collapse_ratio;

      m_trade.SetExpertMagicNumber(magic);

      m_atr_handle = iATR(m_symbol, PERIOD_M5, 14);
      m_rsi_handle = iRSI(m_symbol, PERIOD_M5, 14, PRICE_CLOSE);
      if(m_atr_handle == INVALID_HANDLE || m_rsi_handle == INVALID_HANDLE)
        {
         Print("PositionManager: failed to create indicator handle(s).");
         return false;
        }
      return true;
     }

   void Release()
     {
      if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
      if(m_rsi_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_handle);
     }

   bool HasPosition() const { return m_has_position; }
   OpenTradeState GetState() const { return m_state; }

   //--- structural SL: last swing +/- 1.5xATR, floored at broker/spread minimum
   double CalcStructuralSL(const ENUM_TRADE_DIR dir, const double swing_level, const double atr,
                            const int stops_level_points, const double spread_price_distance,
                            const double point, const int digits) const
     {
      double buffer = m_sl_atr_mult * atr;
      double raw_sl = (dir == DIR_BUY) ? (swing_level - buffer) : (swing_level + buffer);

      double floor_distance = MathMax((double)stops_level_points * point, 3.0 * spread_price_distance);
      double entry_ref = (dir == DIR_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(dir == DIR_BUY && (entry_ref - raw_sl) < floor_distance)
         raw_sl = entry_ref - floor_distance;
      if(dir == DIR_SELL && (raw_sl - entry_ref) < floor_distance)
         raw_sl = entry_ref + floor_distance;

      return NormalizeDouble(raw_sl, digits);
     }

   //--- called from OnTradeTransaction once the armed pending order fills
   void RegisterOpenPosition(const ulong ticket, const ThesisSignal &sig, const double fill_price,
                              const double sl_price)
     {
      m_state.ticket = ticket;
      m_state.signal = sig;
      m_state.entry_price = fill_price;
      m_state.initial_sl = sl_price;
      m_state.risk_distance = MathAbs(fill_price - sl_price);
      m_state.atr_at_entry = AtrNow();
      m_state.open_time = TimeCurrent();
      m_state.bars_since_open = 0;
      m_state.partial_done = false;
      m_state.mfe_r = 0.0;
      m_state.mae_r = 0.0;
      m_state.spread_at_signal = sig.spread_at_signal;
      m_has_position = true;
      PrintFormat("PositionManager: registered open %s %s @ %.2f SL %.2f risk=%.2fpts",
                  ArchetypeToString(sig.archetype), sig.direction==DIR_BUY?"BUY":"SELL",
                  fill_price, sl_price, m_state.risk_distance/SymbolInfoDouble(m_symbol,SYMBOL_POINT));
     }

   void ClearPosition() { m_has_position = false; }

   void OnNewM5Bar()
     {
      if(!m_has_position) return;
      m_state.bars_since_open++;
     }

   //--- returns the exit reason if the position should be closed now, else EXIT_NONE.
   //--- IMPORTANT: this never clears m_has_position itself, even when it submits a
   //--- close. OnTradeTransaction is the sole place that calls ClearPosition(), once
   //--- the closing deal actually arrives -- otherwise there is a race where this
   //--- function's own optimistic "closed" flip beats OnTradeTransaction's handler,
   //--- and the Journal/RiskGovernor/ThesisEngine/DegradationMonitor/weight-adaptation
   //--- finalize path (gated on HasPosition()) gets silently skipped for every trade.
   //---
   //--- continuous re-evaluation: invalidation_price is the "is the reason I entered
   //--- still true?" check -- much earlier than the stop, per the spec's core lever.
   ENUM_EXIT_REASON Manage()
     {
      if(!m_has_position) return EXIT_NONE;
      if(!PositionSelectByTicket(m_state.ticket))
         return EXIT_NONE; // closed (server SL/TP or our own prior close) -- awaiting OnTradeTransaction

      double price = (m_state.signal.direction == DIR_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                                                      : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double r = RMultiple(price);
      m_state.mfe_r = MathMax(m_state.mfe_r, r);
      m_state.mae_r = MathMin(m_state.mae_r, r);

      bool invalidated = (m_state.signal.direction == DIR_BUY) ? (price <= m_state.signal.invalidation_price)
                                                          : (price >= m_state.signal.invalidation_price);
      if(invalidated && !m_state.partial_done)
        {
         m_trade.PositionClose(m_state.ticket);
         return EXIT_INVALIDATION;
        }

      // weekend flat: close all before Friday close (server time)
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == FRIDAY && dt.hour >= 21)
        {
         m_trade.PositionClose(m_state.ticket);
         return EXIT_WEEKEND_FLAT;
        }

      // time stop: not at +0.5R within N M5 bars -- stale thesis
      if(!m_state.partial_done && m_state.bars_since_open >= m_time_stop_bars && r < m_time_stop_r)
        {
         m_trade.PositionClose(m_state.ticket);
         return EXIT_TIME_STOP;
        }

      // momentum-decay exit
      if(!m_state.partial_done && MomentumAgainst())
        {
         m_trade.PositionClose(m_state.ticket);
         return EXIT_MOMENTUM_DECAY;
        }

      // volatility-collapse exit
      double atr_now = AtrNow();
      if(m_state.atr_at_entry > 0 && atr_now < m_state.atr_at_entry * m_vol_collapse_ratio)
        {
         m_trade.PositionClose(m_state.ticket);
         return EXIT_VOLATILITY_COLLAPSE;
        }

      // partial close 50% at 1R, remainder to breakeven + cost
      if(!m_state.partial_done && r >= 1.0)
        {
         double volume = PositionGetDouble(POSITION_VOLUME);
         double half = volume / 2.0;
         double volStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
         double volMin  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
         half = MathFloor(half/volStep)*volStep;
         if(half >= volMin && (volume-half) >= volMin)
           {
            m_trade.PositionClosePartial(m_state.ticket, half);
            double spread_dist = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            double be_plus_cost = (m_state.signal.direction == DIR_BUY) ? m_state.entry_price + spread_dist
                                                                   : m_state.entry_price - spread_dist;
            m_trade.PositionModify(m_state.ticket, be_plus_cost, 0);
            m_state.partial_done = true;
            PrintFormat("PositionManager: partial close 50%% at 1R, remainder BE+cost @ %.2f", be_plus_cost);
           }
        }

      // ATR-chandelier trail on the runner (only after partial taken)
      if(m_state.partial_done && atr_now > 0)
        {
         double trail_distance = m_chandelier_mult * atr_now;
         double currentSl = PositionGetDouble(POSITION_SL);
         if(m_state.signal.direction == DIR_BUY)
           {
            double newSl = price - trail_distance;
            if(newSl > currentSl) m_trade.PositionModify(m_state.ticket, newSl, 0);
           }
         else
           {
            double newSl = price + trail_distance;
            if(currentSl == 0 || newSl < currentSl) m_trade.PositionModify(m_state.ticket, newSl, 0);
           }
        }

      return EXIT_NONE;
     }
  };
//+------------------------------------------------------------------+
