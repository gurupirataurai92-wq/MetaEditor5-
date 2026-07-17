//+------------------------------------------------------------------+
//|                                               ExecutionEngine.mqh |
//|  MODULE 6 -- two-stage confirmation cascade (M5 arm -> M1        |
//|  confirm). The pending order IS the confirmation mechanism: if  |
//|  price never reaches the trigger, no unconfirmed trade is taken.|
//|  Reversal archetypes (SWEEP/TRAP) additionally demand M1 proof; |
//|  momentum archetypes (OR_BREAK) skip that extra gate.           |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
#include "Defines.mqh"

class CExecutionEngine
  {
private:
   string         m_symbol;
   CTrade         m_trade;
   int            m_digits;
   double         m_point;
   ENUM_SYMBOL_TRADE_EXECUTION m_exec_mode;
   int            m_deviation_points;
   int            m_watch_window_m1_bars;
   int            m_max_requote_retries;
   int            m_rsi_m1_handle;

   bool           m_armed;
   ulong          m_armed_ticket;
   ThesisSignal   m_armed_signal;
   int            m_m1_bars_since_arm;
   bool           m_m1_confirmed;

   bool IsPendingStillWorking() const
     {
      if(m_armed_ticket == 0) return false;
      if(OrderSelect(m_armed_ticket)) return true;
      return false;
     }

   bool M1MomentumAgainst(const ENUM_TRADE_DIR dir) const
     {
      double buf[];
      if(CopyBuffer(m_rsi_m1_handle, 0, 1, 1, buf) < 1) return false;
      double rsi = buf[0];
      if(dir == DIR_BUY)  return (rsi < 45.0);
      if(dir == DIR_SELL) return (rsi > 55.0);
      return false;
     }

   bool M1MomentumConfirms(const ENUM_TRADE_DIR dir) const
     {
      double buf[];
      if(CopyBuffer(m_rsi_m1_handle, 0, 1, 1, buf) < 1) return false;
      double rsi = buf[0];
      if(dir == DIR_BUY)  return (rsi > 52.0);
      if(dir == DIR_SELL) return (rsi < 48.0);
      return false;
     }

public:
                     CExecutionEngine()
     {
      m_armed = false;
      m_armed_ticket = 0;
      m_m1_bars_since_arm = 0;
      m_m1_confirmed = false;
     }

   bool Init(const string symbol, const int digits, const double point,
             const ENUM_SYMBOL_TRADE_EXECUTION exec_mode, const ENUM_ORDER_TYPE_FILLING filling_mode,
             const ulong magic, const int deviation_points, const int watch_window_m1_bars,
             const int max_requote_retries)
     {
      m_symbol = symbol;
      m_digits = digits;
      m_point = point;
      m_exec_mode = exec_mode;
      m_deviation_points = deviation_points;
      m_watch_window_m1_bars = watch_window_m1_bars;
      m_max_requote_retries = max_requote_retries;

      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(deviation_points);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.SetMarginMode();

      m_rsi_m1_handle = iRSI(m_symbol, PERIOD_M1, 14, PRICE_CLOSE);
      if(m_rsi_m1_handle == INVALID_HANDLE)
        {
         Print("ExecutionEngine: failed to create M1 RSI handle.");
         return false;
        }
      return true;
     }

   void Release()
     {
      if(m_rsi_m1_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_m1_handle);
     }

   bool     IsArmed() const { return m_armed; }
   ThesisSignal ArmedSignal() const { return m_armed_signal; }

   //--- place a pending stop order at the trigger level with SL attached
   bool Arm(const ThesisSignal &sig, const double lots, const string comment)
     {
      if(m_armed) return false;

      double price = sig.trigger_price;
      double sl = sig.structural_sl;
      bool isBuy = (sig.direction == DIR_BUY);

      double current_ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double current_bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      // stop orders must sit beyond the current market in the trigger direction
      if(isBuy && price <= current_ask) price = current_ask + 10*m_point;
      if(!isBuy && price >= current_bid) price = current_bid - 10*m_point;
      price = NormalizeDouble(price, m_digits);
      sl    = NormalizeDouble(sl, m_digits);

      bool instant = (m_exec_mode == SYMBOL_TRADE_EXECUTION_INSTANT ||
                      m_exec_mode == SYMBOL_TRADE_EXECUTION_REQUEST);

      bool sent = false;
      ulong ticket = 0;
      for(int attempt=0; attempt<m_max_requote_retries && !sent; attempt++)
        {
         bool ok;
         if(isBuy)
            ok = instant ? m_trade.BuyStop(lots, price, m_symbol, 0, 0, ORDER_TIME_GTC, 0, comment)
                          : m_trade.BuyStop(lots, price, m_symbol, sl, 0, ORDER_TIME_GTC, 0, comment);
         else
            ok = instant ? m_trade.SellStop(lots, price, m_symbol, 0, 0, ORDER_TIME_GTC, 0, comment)
                          : m_trade.SellStop(lots, price, m_symbol, sl, 0, ORDER_TIME_GTC, 0, comment);

         uint retcode = m_trade.ResultRetcode();
         if(ok && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED))
           {
            ticket = m_trade.ResultOrder();
            sent = true;
           }
         else if(retcode == TRADE_RETCODE_REQUOTE || retcode == TRADE_RETCODE_PRICE_CHANGED)
           {
            PrintFormat("ExecutionEngine: requote on attempt %d/%d, retrying.", attempt+1, m_max_requote_retries);
            Sleep(200);
            current_ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
            current_bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            if(isBuy && price <= current_ask) price = current_ask + 10*m_point;
            if(!isBuy && price >= current_bid) price = current_bid - 10*m_point;
            price = NormalizeDouble(price, m_digits);
           }
         else
           {
            PrintFormat("ExecutionEngine: order failed, retcode=%u, abandoning.", retcode);
            break;
           }
        }

      if(!sent) return false;

      // instant-execution model: bare send, then modify to attach SL
      if(instant)
        {
         if(!m_trade.OrderModify(ticket, price, sl, 0, ORDER_TIME_GTC, 0))
            PrintFormat("ExecutionEngine: WARNING failed to attach SL to instant-mode pending #%I64u", ticket);
        }

      m_armed = true;
      m_armed_ticket = ticket;
      m_armed_signal = sig;
      m_m1_bars_since_arm = 0;
      m_m1_confirmed = false;
      PrintFormat("ExecutionEngine: ARMED %s %s @ %.2f SL %.2f (archetype=%s confirm=%s)",
                  ArchetypeToString(sig.archetype), isBuy?"BUY":"SELL", price, sl,
                  ArchetypeToString(sig.archetype), sig.requires_m1_confirm?"required":"skipped");
      return true;
     }

   //--- the armed pending order filled -- hand off to PositionManager, don't cancel
   void ClearArmedAfterFill()
     {
      m_armed = false;
      m_armed_ticket = 0;
     }

   void CancelArmed(const string reason)
     {
      if(!m_armed) return;
      if(IsPendingStillWorking())
         m_trade.OrderDelete(m_armed_ticket);
      PrintFormat("ExecutionEngine: CANCELLED armed %s order -> %s",
                  ArchetypeToString(m_armed_signal.archetype), reason);
      m_armed = false;
      m_armed_ticket = 0;
     }

   //--- called every new M1 bar while an order is armed ---------------
   void OnNewM1Bar()
     {
      if(!m_armed) return;
      m_m1_bars_since_arm++;

      if(m_armed_signal.requires_m1_confirm && !m_m1_confirmed)
        {
         if(M1MomentumConfirms(m_armed_signal.direction))
            m_m1_confirmed = true;
        }

      if(m_m1_bars_since_arm >= m_watch_window_m1_bars)
        {
         if(m_armed_signal.requires_m1_confirm && !m_m1_confirmed)
           {
            CancelArmed("watch_window_expired_no_m1_confirmation");
            return;
           }
         if(!IsPendingStillWorking())
            return; // filled -- leave m_armed true, OnTradeTransaction clears it after registering
         CancelArmed("watch_window_expired");
        }
     }

   //--- called every tick while an order is armed ----------------------
   void WatchTick(const double current_price, const bool spread_spiking)
     {
      if(!m_armed) return;

      // IMPORTANT: do NOT clear m_armed here just because the pending order is no
      // longer selectable -- that's ambiguous between "it filled" and "it's about
      // to be reported as filled." Only OnTradeTransaction's DEAL_ENTRY_IN handler
      // (via ClearArmedAfterFill(), after RegisterOpenPosition()) may clear it; a
      // premature clear here would make IsArmed() false before that handler runs,
      // causing the fill to be silently dropped and the position to go unmanaged.
      if(!IsPendingStillWorking())
         return;

      if(current_price != 0.0)
        {
         bool invalid = (m_armed_signal.direction == DIR_BUY) ?
                         (current_price <= m_armed_signal.invalidation_price) :
                         (current_price >= m_armed_signal.invalidation_price);
         if(invalid) { CancelArmed("invalidation_level_hit"); return; }
        }

      if(spread_spiking) { CancelArmed("spread_blowout"); return; }

      if(m_armed_signal.requires_m1_confirm && m_m1_confirmed == false && m_m1_bars_since_arm > 0)
        {
         if(M1MomentumAgainst(m_armed_signal.direction))
           {
            CancelArmed("m1_momentum_against_thesis");
            return;
           }
        }
     }
  };
//+------------------------------------------------------------------+
