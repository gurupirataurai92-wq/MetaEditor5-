//+------------------------------------------------------------------+
//|                                                 RiskGovernor.mqh |
//|  MODULE 8 -- risk computed in money, never points. State        |
//|  persists across restarts: a VPS reboot must NOT reset a risk   |
//|  limit already hit.                                              |
//+------------------------------------------------------------------+
#property strict
#include "Defines.mqh"

class CRiskGovernor
  {
private:
   string   m_symbol;
   ulong    m_magic;

   double   m_risk_percent;          // 0.25-0.5% per trade
   double   m_daily_dd_cutoff_pct;   // -2.0
   double   m_weekly_dd_cutoff_pct;  // -5.0
   int      m_loss_streak_limit;     // 3
   int      m_cooldown_minutes;      // 60-120
   int      m_max_trades_per_day;
   double   m_profit_lock_trigger_pct;   // +2.0
   double   m_profit_lock_tightened_pct; // -0.5 once triggered
   double   m_dd_scale_factor;       // drawdown-scaled sizing steepness
   double   m_dd_scale_floor;        // minimum size multiplier under drawdown

   RiskState m_state;
   double    m_equity_history[]; // ring buffer, one snapshot per closed trade
   int       m_equity_history_len;
   int       m_equity_history_count;
   int       m_equity_history_pos;
   int       m_trades_today;
   bool      m_profit_locked_today;

   string KeyPrefix() const { return StringFormat("GM_RISK_%s_%I64u_", m_symbol, m_magic); }

   double EquityMA() const
     {
      if(m_equity_history_count == 0) return AccountInfoDouble(ACCOUNT_EQUITY);
      double sum = 0.0;
      for(int i=0; i<m_equity_history_count; i++) sum += m_equity_history[i];
      return sum / m_equity_history_count;
     }

   void PushEquitySnapshot(const double equity)
     {
      m_equity_history[m_equity_history_pos] = equity;
      m_equity_history_pos = (m_equity_history_pos + 1) % m_equity_history_len;
      if(m_equity_history_count < m_equity_history_len) m_equity_history_count++;
     }

   bool CorrelatedSymbolPositionOpen() const
     {
      string up_symbol = m_symbol;
      StringToUpper(up_symbol);
      bool symbolIsGold = (StringFind(up_symbol,"XAU")>=0 || StringFind(up_symbol,"GOLD")>=0);
      if(!symbolIsGold) return false;

      int total = PositionsTotal();
      for(int i=0; i<total; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         string psym = PositionGetString(POSITION_SYMBOL);
         string up = psym;
         StringToUpper(up);
         if(StringFind(up,"XAG") >= 0 || StringFind(up,"SILVER") >= 0)
            return true;
        }
      return false;
     }

public:
                     CRiskGovernor()
     {
      m_equity_history_len = 20;
      m_equity_history_count = 0;
      m_equity_history_pos = 0;
      m_trades_today = 0;
      m_profit_locked_today = false;
     }

   bool Init(const string symbol, const ulong magic, const double risk_percent,
             const double daily_dd_cutoff_pct, const double weekly_dd_cutoff_pct,
             const int loss_streak_limit, const int cooldown_minutes, const int max_trades_per_day,
             const double profit_lock_trigger_pct, const double profit_lock_tightened_pct,
             const double dd_scale_factor, const double dd_scale_floor)
     {
      m_symbol = symbol;
      m_magic = magic;
      m_risk_percent = risk_percent;
      m_daily_dd_cutoff_pct = daily_dd_cutoff_pct;
      m_weekly_dd_cutoff_pct = weekly_dd_cutoff_pct;
      m_loss_streak_limit = loss_streak_limit;
      m_cooldown_minutes = cooldown_minutes;
      m_max_trades_per_day = max_trades_per_day;
      m_profit_lock_trigger_pct = profit_lock_trigger_pct;
      m_profit_lock_tightened_pct = profit_lock_tightened_pct;
      m_dd_scale_factor = dd_scale_factor;
      m_dd_scale_floor = dd_scale_floor;

      ArrayResize(m_equity_history, m_equity_history_len);
      ArrayInitialize(m_equity_history, 0.0);

      LoadState();
      RefreshCalendar();
      return true;
     }

   //--- persist to GlobalVariables so a VPS restart doesn't reset a limit already hit
   void PersistState()
     {
      string p = KeyPrefix();
      GlobalVariableSet(p+"last_day",   (double)m_state.last_reset_day);
      GlobalVariableSet(p+"last_week",  (double)m_state.last_reset_week);
      GlobalVariableSet(p+"day_eq0",    m_state.daily_start_equity);
      GlobalVariableSet(p+"week_eq0",   m_state.weekly_start_equity);
      GlobalVariableSet(p+"losses",     (double)m_state.consecutive_losses);
      GlobalVariableSet(p+"cooldown",   (double)m_state.cooldown_until);
      GlobalVariableSet(p+"hwm",        m_state.equity_high_water_mark);
      GlobalVariableSet(p+"day_halt",   m_state.daily_halted ? 1.0 : 0.0);
      GlobalVariableSet(p+"week_halt",  m_state.weekly_halted ? 1.0 : 0.0);
      GlobalVariableSet(p+"deg_halt",   m_state.degradation_halted ? 1.0 : 0.0);
      GlobalVariableSet(p+"trades_today", (double)m_trades_today);
      GlobalVariableSet(p+"profit_lock", m_profit_locked_today ? 1.0 : 0.0);
     }

   void LoadState()
     {
      string p = KeyPrefix();
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      m_state.last_reset_day   = GlobalVariableCheck(p+"last_day")  ? (datetime)GlobalVariableGet(p+"last_day")  : 0;
      m_state.last_reset_week  = GlobalVariableCheck(p+"last_week") ? (datetime)GlobalVariableGet(p+"last_week") : 0;
      m_state.daily_start_equity  = GlobalVariableCheck(p+"day_eq0")  ? GlobalVariableGet(p+"day_eq0")  : equity;
      m_state.weekly_start_equity = GlobalVariableCheck(p+"week_eq0") ? GlobalVariableGet(p+"week_eq0") : equity;
      m_state.consecutive_losses  = GlobalVariableCheck(p+"losses")   ? (int)GlobalVariableGet(p+"losses") : 0;
      m_state.cooldown_until      = GlobalVariableCheck(p+"cooldown") ? (datetime)GlobalVariableGet(p+"cooldown") : 0;
      m_state.equity_high_water_mark = GlobalVariableCheck(p+"hwm")   ? GlobalVariableGet(p+"hwm") : equity;
      m_state.daily_halted   = GlobalVariableCheck(p+"day_halt")  ? (GlobalVariableGet(p+"day_halt")  > 0.5) : false;
      m_state.weekly_halted  = GlobalVariableCheck(p+"week_halt") ? (GlobalVariableGet(p+"week_halt") > 0.5) : false;
      m_state.degradation_halted = GlobalVariableCheck(p+"deg_halt") ? (GlobalVariableGet(p+"deg_halt") > 0.5) : false;
      m_trades_today = GlobalVariableCheck(p+"trades_today") ? (int)GlobalVariableGet(p+"trades_today") : 0;
      m_profit_locked_today = GlobalVariableCheck(p+"profit_lock") ? (GlobalVariableGet(p+"profit_lock") > 0.5) : false;

      if(m_state.equity_high_water_mark < equity) m_state.equity_high_water_mark = equity;
     }

   //--- roll daily/weekly windows forward if the calendar day/week changed ---
   void RefreshCalendar()
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour=0; dt.min=0; dt.sec=0;
      datetime today = StructToTime(dt);

      if(today != m_state.last_reset_day)
        {
         m_state.last_reset_day = today;
         m_state.daily_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
         m_state.daily_halted = false;
         m_trades_today = 0;
         m_profit_locked_today = false;
        }

      int dow = dt.day_of_week;
      int backToMonday = (dow == 0) ? 6 : (dow - 1);
      datetime weekStart = today - backToMonday*86400;
      if(weekStart != m_state.last_reset_week)
        {
         m_state.last_reset_week = weekStart;
         m_state.weekly_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
         m_state.weekly_halted = false;
        }

      PersistState();
     }

   //--- money-based, ATR-normalized position sizing -- the only broker-portable formula
   double LotsForRisk(const double sl_price_distance, const double tick_size, const double tick_value,
                       const double vol_min, const double vol_max, const double vol_step,
                       const double size_multiplier) const
     {
      if(sl_price_distance <= 0.0 || tick_size <= 0.0 || tick_value <= 0.0) return 0.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double risk_money = equity * (m_risk_percent/100.0) * size_multiplier;
      double ticks = sl_price_distance / tick_size;
      double lots = risk_money / (ticks * tick_value);

      double steps = MathFloor(lots/vol_step + 1e-8);
      lots = steps * vol_step;
      lots = MathMax(vol_min, MathMin(vol_max, lots));
      int stepDigits = (int)MathMax(0, -(int)MathRound(MathLog10(vol_step)));
      return NormalizeDouble(lots, stepDigits);
     }

   //--- equity-curve governor + drawdown-scaled sizing, combined multiplicatively
   double SizeMultiplier() const
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double mult = 1.0;

      double ma = EquityMA();
      if(ma > 0 && equity < ma) mult *= 0.5;

      double hwm = m_state.equity_high_water_mark;
      if(hwm > 0)
        {
         double dd_fraction = (hwm - equity) / hwm;
         if(dd_fraction > 0)
           {
            double dd_mult = MathMax(m_dd_scale_floor, 1.0 - dd_fraction*m_dd_scale_factor);
            mult *= dd_mult;
           }
        }
      return mult;
     }

   //--- recompute daily/weekly P&L into persisted state -- call every tick so the
   //--- Dashboard (and CanTrade's cutoff checks) always see a fresh number, not
   //--- just whatever was last computed when a trade signal happened to fire.
   void RefreshPnL()
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_state.daily_pnl_pct = (m_state.daily_start_equity>0) ?
         (equity - m_state.daily_start_equity)/m_state.daily_start_equity*100.0 : 0.0;
      m_state.weekly_pnl_pct = (m_state.weekly_start_equity>0) ?
         (equity - m_state.weekly_start_equity)/m_state.weekly_start_equity*100.0 : 0.0;
     }

   //--- aggregate gate. Returns REJECT_NONE if trading is allowed, else the reason.
   ENUM_REJECT_REASON CanTrade()
     {
      RefreshPnL();
      double daily_pnl_pct = m_state.daily_pnl_pct;
      double weekly_pnl_pct = m_state.weekly_pnl_pct;

      // NOTE: degradation halting is owned exclusively by CDegradationMonitor
      // (checked separately by the caller) -- this struct's degradation_halted
      // field is not used as a gate here to avoid two sources of truth.

      // profit-lock ratchet: once daily P&L clears the trigger, tighten the daily cutoff
      double effective_daily_cutoff = m_daily_dd_cutoff_pct;
      if(daily_pnl_pct >= m_profit_lock_trigger_pct)
        {
         m_profit_locked_today = true;
         effective_daily_cutoff = m_profit_lock_tightened_pct;
        }

      if(daily_pnl_pct <= effective_daily_cutoff)
        {
         m_state.daily_halted = true;
         PersistState();
        }
      if(m_state.daily_halted) return REJECT_DAILY_DD_HALT;

      if(weekly_pnl_pct <= m_weekly_dd_cutoff_pct)
        {
         m_state.weekly_halted = true;
         PersistState();
        }
      if(m_state.weekly_halted) return REJECT_WEEKLY_DD_HALT;

      if(m_state.consecutive_losses >= m_loss_streak_limit && TimeCurrent() < m_state.cooldown_until)
         return REJECT_LOSS_STREAK_COOLDOWN;

      if(m_trades_today >= m_max_trades_per_day) return REJECT_MAX_TRADES_DAY;

      if(CorrelatedSymbolPositionOpen()) return REJECT_CORRELATION_GUARD;

      return REJECT_NONE;
     }

   //--- update all rolling state when a trade closes ------------------
   void OnTradeClosed(const double r_multiple)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_trades_today++;
      PushEquitySnapshot(equity);

      if(equity > m_state.equity_high_water_mark) m_state.equity_high_water_mark = equity;

      if(r_multiple < 0)
        {
         m_state.consecutive_losses++;
         if(m_state.consecutive_losses >= m_loss_streak_limit)
            m_state.cooldown_until = TimeCurrent() + m_cooldown_minutes*60;
        }
      else
         m_state.consecutive_losses = 0;

      PersistState();
     }

   RiskState GetState() const { return m_state; }
   int       TradesToday() const { return m_trades_today; }
  };
//+------------------------------------------------------------------+
