//+------------------------------------------------------------------+
//|                                             RecoveryManager.mqh |
//|  Bounded loss-recovery ("Godmode" trait) — a SAFE reinterpretation |
//|  of the martingale recovery those EAs are known for. After a loss |
//|  it raises the risk request by a capped multiplier for a limited  |
//|  number of steps, resets fully on any win, and refuses to act     |
//|  once equity falls below a hard floor. The account-level daily-   |
//|  loss and drawdown kill-switches in SafetyGuard still bound it,   |
//|  so a losing run cannot compound without limit. Default: OFF.     |
//+------------------------------------------------------------------+
#ifndef V75EA_RECOVERY_MANAGER_MQH
#define V75EA_RECOVERY_MANAGER_MQH

#property strict

class CRecoveryManager
  {
private:
   bool     m_enabled;
   int      m_step;           // 0 = no recovery in progress
   int      m_maxSteps;
   double   m_stepFactor;     // risk multiplier applied per step
   double   m_maxMultiplier;  // absolute ceiling on the multiplier
   double   m_equityFloor;    // recovery disabled below this equity
   double   m_startEquity;

public:
                     CRecoveryManager(void) : m_enabled(false), m_step(0), m_maxSteps(3),
                                               m_stepFactor(1.5), m_maxMultiplier(3.0),
                                               m_equityFloor(0.0), m_startEquity(0.0) {}

   void              Init(const bool enabled, const int maxSteps, const double stepFactor,
                           const double maxMultiplier, const double equityFloorPercent)
     {
      m_enabled       = enabled;
      m_maxSteps      = MathMax(1, maxSteps);
      m_stepFactor    = MathMax(1.0, stepFactor);
      m_maxMultiplier = MathMax(1.0, maxMultiplier);
      m_step          = 0;
      m_startEquity   = AccountInfoDouble(ACCOUNT_EQUITY);
      m_equityFloor   = m_startEquity * (equityFloorPercent / 100.0);
     }

   //--- feedback: a win clears the ladder, a loss climbs one rung (capped)
   void              RegisterResult(const bool win)
     {
      if(!m_enabled)
         return;
      if(win)
         m_step = 0;
      else
         m_step = MathMin(m_maxSteps, m_step + 1);
     }

   //--- risk multiplier to apply on the next entry
   double            Multiplier(void)
     {
      if(!m_enabled || m_step <= 0)
         return 1.0;

      //--- disable recovery if equity has fallen below the floor (let it heal, don't dig)
      if(AccountInfoDouble(ACCOUNT_EQUITY) < m_equityFloor)
         return 1.0;

      double mult = MathPow(m_stepFactor, m_step);
      return MathMin(m_maxMultiplier, mult);
     }

   bool              IsRecovering(void) const { return (m_enabled && m_step > 0); }
   int               Step(void)         const { return m_step; }
   bool              Enabled(void)      const { return m_enabled; }
  };

#endif // V75EA_RECOVERY_MANAGER_MQH
