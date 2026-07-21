//+------------------------------------------------------------------+
//|                                                 SafetyGuard.mqh |
//|  Circuit breakers: daily loss limit, overall drawdown kill      |
//|  switch, consecutive-loss halt, spread and margin-buffer guard. |
//+------------------------------------------------------------------+
#ifndef V75EA_SAFETY_GUARD_MQH
#define V75EA_SAFETY_GUARD_MQH

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

   //--- session filter + daily profit target
   bool     m_useSession;
   int      m_sessionStartHour;   // broker/server time, 0-23
   int      m_sessionEndHour;     // exclusive; wraps past midnight if end < start
   double   m_dailyProfitTarget;  // % of day-start equity; 0 disables
   bool     m_profitTargetHit;

public:
                     CSafetyGuard(void) : m_consecutiveLosses(0), m_tradingHalted(false),
                                          m_useSession(false), m_sessionStartHour(0),
                                          m_sessionEndHour(24), m_dailyProfitTarget(0.0),
                                          m_profitTargetHit(false) {}

   void              Init(const string symbol, const double maxDailyLossPercent,
                           const double maxDrawdownPercent, const int maxConsecutiveLosses,
                           const double maxSpreadPoints,
                           const bool useSession, const int sessionStartHour, const int sessionEndHour,
                           const double dailyProfitTarget)
     {
      m_symbol               = symbol;
      m_maxDailyLossPercent  = maxDailyLossPercent;
      m_maxDrawdownPercent   = maxDrawdownPercent;
      m_maxConsecutiveLosses = maxConsecutiveLosses;
      m_maxSpreadPoints      = maxSpreadPoints;
      m_useSession           = useSession;
      m_sessionStartHour     = sessionStartHour;
      m_sessionEndHour       = sessionEndHour;
      m_dailyProfitTarget    = dailyProfitTarget;

      m_startEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dayStartEquity = m_startEquity;
      m_currentDay     = TimeCurrent() - (TimeCurrent() % 86400);
      m_consecutiveLosses = 0;
      m_tradingHalted     = false;
      m_profitTargetHit   = false;
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
         m_profitTargetHit   = false;
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

      //--- daily profit target: lock in gains, stop opening for the day
      if(DailyProfitReached())
         return false;

      //--- session/time filter
      if(!IsWithinSession())
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

   //--- true once the day's profit target is reached (main EA may flatten on this)
   bool              DailyProfitReached(void)
     {
      if(m_dailyProfitTarget <= 0.0)
         return false;
      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double gainPct  = (equity - m_dayStartEquity) / m_dayStartEquity * 100.0;
      if(gainPct >= m_dailyProfitTarget)
        {
         if(!m_profitTargetHit)
           {
            m_profitTargetHit = true;
            Print("SafetyGuard: daily profit target hit (", DoubleToString(gainPct, 2), "%). Locking in for the day.");
           }
         return true;
        }
      return false;
     }

   bool              IsWithinSession(void)
     {
      if(!m_useSession)
         return true;
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      if(m_sessionStartHour == m_sessionEndHour)
         return true; // 24h
      if(m_sessionStartHour < m_sessionEndHour)
         return (h >= m_sessionStartHour && h < m_sessionEndHour);
      //--- wraps past midnight (e.g. 22 -> 6)
      return (h >= m_sessionStartHour || h < m_sessionEndHour);
     }

   double            DailyPnlPercent(void)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_dayStartEquity <= 0.0)
         return 0.0;
      return (equity - m_dayStartEquity) / m_dayStartEquity * 100.0;
     }

   bool              IsHalted(void) const { return m_tradingHalted; }
  };

#endif // V75EA_SAFETY_GUARD_MQH
