//+------------------------------------------------------------------+
//|                                                 SafetyGuard.mqh |
//|  Circuit breakers: daily loss limit, overall drawdown kill      |
//|  switch, consecutive-loss halt, spread and margin-buffer guard. |
//+------------------------------------------------------------------+
#property strict

class CSafetyGuard
  {
private:
   string   m_symbol;
   double   m_startEquity;
   double   m_dayStartEquity;
   datetime m_currentDay;
   double   m_maxDailyLossPercent;
   double   m_maxDrawdownPercent;
   int      m_maxConsecutiveLosses;
   int      m_consecutiveLosses;
   bool     m_tradingHalted;
   double   m_maxSpreadPoints;

public:
                     CSafetyGuard(void) : m_consecutiveLosses(0), m_tradingHalted(false) {}

   void              Init(const string symbol, const double maxDailyLossPercent,
                           const double maxDrawdownPercent, const int maxConsecutiveLosses,
                           const double maxSpreadPoints)
     {
      m_symbol               = symbol;
      m_maxDailyLossPercent  = maxDailyLossPercent;
      m_maxDrawdownPercent   = maxDrawdownPercent;
      m_maxConsecutiveLosses = maxConsecutiveLosses;
      m_maxSpreadPoints      = maxSpreadPoints;

      m_startEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dayStartEquity = m_startEquity;
      m_currentDay     = TimeCurrent() - (TimeCurrent() % 86400);
      m_consecutiveLosses = 0;
      m_tradingHalted     = false;
     }

   //--- Call once per tick: resets daily counters when a new trading day starts
   void              OnNewTick(void)
     {
      datetime today = TimeCurrent() - (TimeCurrent() % 86400);
      if(today != m_currentDay)
        {
         m_currentDay        = today;
         m_dayStartEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
         m_tradingHalted     = false;
         m_consecutiveLosses = 0;
         Print("SafetyGuard: new trading day, counters reset. Equity=", m_dayStartEquity);
        }
     }

   //--- Call when a position closes, so consecutive-loss tracking stays current
   void              RegisterTradeResult(const bool wasWin)
     {
      if(wasWin)
         m_consecutiveLosses = 0;
      else
         m_consecutiveLosses++;

      if(m_consecutiveLosses >= m_maxConsecutiveLosses)
        {
         m_tradingHalted = true;
         Print("SafetyGuard: max consecutive losses (", m_consecutiveLosses, ") reached. Halting trading for today.");
        }
     }

   bool              IsTradingAllowed(void)
     {
      if(m_tradingHalted)
         return false;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      //--- daily loss limit
      double dailyLossPercent = (m_dayStartEquity - equity) / m_dayStartEquity * 100.0;
      if(dailyLossPercent >= m_maxDailyLossPercent)
        {
         Print("SafetyGuard: daily loss limit hit (", DoubleToString(dailyLossPercent, 2), "%). Halting for today.");
         m_tradingHalted = true;
         return false;
        }

      //--- overall drawdown kill-switch (requires manual re-enable, i.e. EA restart with reset inputs)
      double drawdownPercent = (m_startEquity - equity) / m_startEquity * 100.0;
      if(drawdownPercent >= m_maxDrawdownPercent)
        {
         Print("SafetyGuard: overall drawdown limit hit (", DoubleToString(drawdownPercent, 2), "%). EA disabled.");
         m_tradingHalted = true;
         return false;
        }

      //--- spread guard: skip trading while spread is abnormally wide
      long spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      if(spreadPoints > (long)m_maxSpreadPoints)
         return false;

      //--- margin buffer: refuse new trades if margin level is too tight
      double marginUsed = AccountInfoDouble(ACCOUNT_MARGIN);
      if(marginUsed > 0.0)
        {
         double marginLevel = equity / marginUsed * 100.0;
         if(marginLevel < 200.0)
            return false;
        }

      return true;
     }

   bool              IsHalted(void) const { return m_tradingHalted; }
  };
