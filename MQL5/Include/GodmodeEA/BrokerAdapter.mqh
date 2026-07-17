//+------------------------------------------------------------------+
//|                                                BrokerAdapter.mqh |
//|  MODULE 1 -- build first. Auto-detect everything at OnInit().   |
//|  Hardcode nothing. Refuse loudly rather than fail silently.     |
//+------------------------------------------------------------------+
#property strict

class CBrokerAdapter
  {
private:
   string            m_symbol;
   int               m_digits;
   double            m_point;
   double            m_contract_size;
   double            m_tick_value;
   double            m_tick_size;
   double            m_vol_min;
   double            m_vol_max;
   double            m_vol_step;
   int               m_stops_level_points;
   int               m_freeze_level_points;
   ENUM_SYMBOL_TRADE_EXECUTION m_exec_mode;
   ENUM_ORDER_TYPE_FILLING     m_filling_mode;
   int               m_gmt_offset_seconds;
   double            m_commission_per_lot; // user input, API doesn't expose reliably
   string            m_last_error;
   bool              m_ready;

   //--- scan Market Watch for XAUUSD/GOLD under any prefix/suffix
   string FindGoldSymbol()
     {
      string candidates[6] = {"XAUUSD","GOLD","XAUUSD.","XAUUSDm","XAUUSD_i","GOLDm"};
      int total = SymbolsTotal(false);
      for(int i=0; i<total; i++)
        {
         string s = SymbolName(i,false);
         string up = s;
         StringToUpper(up);
         if(StringFind(up,"XAU") >= 0 || StringFind(up,"GOLD") >= 0)
           {
            // exclude obvious non-spot derivatives if broker lists them oddly
            if(StringFind(up,"MICRO") < 0)
               return s;
           }
        }
      return "";
     }

public:
                     CBrokerAdapter() { m_ready=false; m_commission_per_lot=0.0; }

   string            Symbol() const { return m_symbol; }
   int               Digits() const { return m_digits; }
   double            Point() const { return m_point; }
   double            ContractSize() const { return m_contract_size; }
   double            TickValue() const { return m_tick_value; }
   double            TickSize() const { return m_tick_size; }
   double            VolMin() const { return m_vol_min; }
   double            VolMax() const { return m_vol_max; }
   double            VolStep() const { return m_vol_step; }
   int               StopsLevelPoints() const { return m_stops_level_points; }
   int               FreezeLevelPoints() const { return m_freeze_level_points; }
   ENUM_SYMBOL_TRADE_EXECUTION ExecMode() const { return m_exec_mode; }
   ENUM_ORDER_TYPE_FILLING     FillingMode() const { return m_filling_mode; }
   int               GmtOffsetSeconds() const { return m_gmt_offset_seconds; }
   double            CommissionPerLot() const { return m_commission_per_lot; }
   string            LastError() const { return m_last_error; }
   bool              IsReady() const { return m_ready; }

   //--- normalize a raw lot size to the broker's min/max/step -----
   double NormalizeVolume(double vol) const
     {
      if(m_vol_step <= 0.0)
         return vol;
      double steps = MathFloor(vol / m_vol_step + 1e-8);
      double normalized = steps * m_vol_step;
      normalized = MathMax(m_vol_min, MathMin(m_vol_max, normalized));
      int stepDigits = (int)MathMax(0, -(int)MathRound(MathLog10(m_vol_step)));
      return NormalizeDouble(normalized, stepDigits);
     }

   //--- Module 1 core: resolve everything, refuse loudly on failure
   bool Init(const double commission_per_lot_input)
     {
      m_ready = false;
      m_commission_per_lot = commission_per_lot_input;

      m_symbol = FindGoldSymbol();
      if(m_symbol == "")
        {
         m_last_error = "BrokerAdapter: no XAUUSD/GOLD symbol found in Market Watch. Cannot trade.";
         Print(m_last_error);
         return false;
        }
      if(!SymbolSelect(m_symbol, true))
        {
         m_last_error = StringFormat("BrokerAdapter: SymbolSelect(%s) failed.", m_symbol);
         Print(m_last_error);
         return false;
        }

      m_digits        = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_point         = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_contract_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      m_tick_value    = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_tick_size     = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_vol_min       = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_vol_max       = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_vol_step      = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      m_stops_level_points  = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      m_freeze_level_points = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      m_exec_mode     = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_EXEMODE);

      //--- filling mode: never hardcode, query what the symbol supports
      long fillFlags = SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);
      if((fillFlags & SYMBOL_FILLING_FOK) != 0)
         m_filling_mode = ORDER_FILLING_FOK;
      else if((fillFlags & SYMBOL_FILLING_IOC) != 0)
         m_filling_mode = ORDER_FILLING_IOC;
      else
         m_filling_mode = ORDER_FILLING_RETURN;

      //--- server time offset vs GMT, sessions defined in GMT internally
      m_gmt_offset_seconds = (int)(TimeCurrent() - TimeGMT());

      if(m_contract_size <= 0.0 || m_tick_value <= 0.0 || m_tick_size <= 0.0)
        {
         m_last_error = StringFormat(
            "BrokerAdapter: contract spec unusable for %s (contract_size=%.4f tick_value=%.4f tick_size=%.4f).",
            m_symbol, m_contract_size, m_tick_value, m_tick_size);
         Print(m_last_error);
         return false;
        }

      m_ready = true;
      PrintFormat("BrokerAdapter: resolved %s | digits=%d point=%.5f contract=%.2f tickValue=%.5f "
                  "tickSize=%.5f volMin=%.2f volMax=%.2f volStep=%.2f stopsLevel=%dpt freezeLevel=%dpt "
                  "execMode=%d filling=%d gmtOffset=%ds",
                  m_symbol, m_digits, m_point, m_contract_size, m_tick_value, m_tick_size,
                  m_vol_min, m_vol_max, m_vol_step, m_stops_level_points, m_freeze_level_points,
                  (int)m_exec_mode, (int)m_filling_mode, m_gmt_offset_seconds);
      return true;
     }

   //--- Broker quality gate: refuse loudly, never fail silently ---
   // Returns "" if OK, otherwise the human-readable reason (also logged).
   string QualityGate(const double risk_percent, const double structural_stop_points,
                       const int median_spread_warn_points)
     {
      int spread_points = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      if(spread_points > median_spread_warn_points)
         PrintFormat("BrokerAdapter WARNING: current spread %d pts exceeds warn threshold %d pts.",
                     spread_points, median_spread_warn_points);

      if(structural_stop_points > 0 && m_stops_level_points > 0 &&
         m_stops_level_points >= structural_stop_points)
        {
         string reason = StringFormat(
            "BrokerAdapter REFUSE: broker stop level (%d pts) is not tighter than the structural "
            "stop distance we need (%d pts). Cannot place a valid structural SL on this account.",
            m_stops_level_points, structural_stop_points);
         Print(reason);
         return reason;
        }

      //--- account-too-small guard: does the minimum lot already imply
      //--- more risk than RiskPercent of equity, given the current stop?
      if(structural_stop_points > 0)
        {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double min_lot_risk_money = m_vol_min * m_contract_size * structural_stop_points * m_point;
         // convert price-distance risk to money via tick value/tick size ratio
         double ticks = (structural_stop_points * m_point) / m_tick_size;
         min_lot_risk_money = m_vol_min * ticks * m_tick_value;
         double allowed_risk_money = equity * (risk_percent / 100.0);

         if(min_lot_risk_money > allowed_risk_money)
           {
            string reason = StringFormat(
               "BrokerAdapter REFUSE: minimum lot (%.2f) at structural stop (%d pts = %d ticks) "
               "risks $%.2f, which exceeds RiskPercent=%.2f%% of equity $%.2f (=$%.2f allowed). "
               "Arithmetic: %.2f lots x %d ticks x $%.4f/tick = $%.2f > $%.2f. "
               "This account is mechanically too small for this stop distance. Refusing to trade.",
               m_vol_min, structural_stop_points, (int)ticks, min_lot_risk_money,
               risk_percent, equity, allowed_risk_money,
               m_vol_min, (int)ticks, m_tick_value, min_lot_risk_money, allowed_risk_money);
            Print(reason);
            return reason;
           }
        }

      return "";
     }
  };
//+------------------------------------------------------------------+
