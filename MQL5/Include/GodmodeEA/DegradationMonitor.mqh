//+------------------------------------------------------------------+
//|                                            DegradationMonitor.mqh |
//|  MODULE 12 -- the module that saves your capital. You cannot    |
//|  build a system that never decays. You can build one that knows |
//|  when it's decaying. Not immortality -- early detection and     |
//|  graceful shutdown.                                              |
//+------------------------------------------------------------------+
#property strict
#include "Defines.mqh"

enum ENUM_DEGRADATION_STATE
  {
   DEGRADATION_NORMAL = 0,
   DEGRADATION_HALVED = 1,
   DEGRADATION_HALTED = 2
  };

class CDegradationMonitor
  {
private:
   string   m_key_prefix;
   double   m_r_history[];
   int      m_capacity;
   int      m_count;      // total trades ever recorded (monotonic)
   int      m_write_pos;  // ring buffer write cursor

   double   m_expected_avg_r;     // from the user's own backtest -- required input
   double   m_sigma_threshold;    // 2.0 per spec

   ENUM_DEGRADATION_STATE m_state;
   int      m_halved_at_count;

   void PersistState()
     {
      GlobalVariableSet(m_key_prefix+"count", (double)m_count);
      GlobalVariableSet(m_key_prefix+"state", (double)m_state);
      GlobalVariableSet(m_key_prefix+"halved_at", (double)m_halved_at_count);
     }

   //--- mean and stdev of the most recent `window` trades in the ring buffer
   bool WindowStats(const int window, double &mean_r, double &stdev_r) const
     {
      int n = MathMin(window, m_count);
      if(n < window) return false;
      double sum = 0.0;
      for(int i=0; i<n; i++)
        {
         int idx = (m_write_pos - 1 - i + m_capacity*2) % m_capacity;
         sum += m_r_history[idx];
        }
      mean_r = sum / n;

      double sqsum = 0.0;
      for(int i=0; i<n; i++)
        {
         int idx = (m_write_pos - 1 - i + m_capacity*2) % m_capacity;
         double d = m_r_history[idx] - mean_r;
         sqsum += d*d;
        }
      stdev_r = (n>1) ? MathSqrt(sqsum/(n-1)) : 0.0;
      return true;
     }

public:
                     CDegradationMonitor() { m_count=0; m_write_pos=0; m_state=DEGRADATION_NORMAL; m_halved_at_count=0; }

   bool Init(const string symbol, const ulong magic, const double expected_avg_r,
             const double sigma_threshold, const bool reset_halt)
     {
      m_key_prefix = StringFormat("GM_DEG_%s_%I64u_", symbol, magic);
      m_capacity = 500;
      ArrayResize(m_r_history, m_capacity);
      ArrayInitialize(m_r_history, 0.0);
      m_expected_avg_r = expected_avg_r;
      m_sigma_threshold = sigma_threshold;

      // The rolling R-history ring buffer is NOT persisted (only the
      // halt/halve state is) -- so the in-memory trade count always
      // restarts at 0 on init. Restoring a stale non-zero count here
      // would make WindowStats() score a 50-trade window against an
      // empty (zero-filled) buffer and misfire immediately after restart.
      m_count = 0;
      m_write_pos = 0;
      m_state = GlobalVariableCheck(m_key_prefix+"state") ? (ENUM_DEGRADATION_STATE)(int)GlobalVariableGet(m_key_prefix+"state") : DEGRADATION_NORMAL;
      m_halved_at_count = 0; // relative to the fresh in-memory count above

      if(reset_halt)
        {
         m_state = DEGRADATION_NORMAL;
         m_halved_at_count = 0;
         m_count = 0;
         PersistState();
         PrintFormat("DegradationMonitor: reset requested -- state cleared to NORMAL.");
        }
      return true;
     }

   ENUM_DEGRADATION_STATE State() const { return m_state; }
   bool IsHalted() const { return m_state == DEGRADATION_HALTED; }
   bool ShouldHalveSize() const { return m_state == DEGRADATION_HALVED; }

   double RollingExpectancy50() const
     {
      double mean, sd;
      if(!WindowStats(50, mean, sd)) return 0.0;
      return mean;
     }

   //--- call once per closed trade -------------------------------------
   void RecordTrade(const double r_multiple)
     {
      m_r_history[m_write_pos] = r_multiple;
      m_write_pos = (m_write_pos + 1) % m_capacity;
      m_count++;

      double mean50, sd50;
      if(!WindowStats(50, mean50, sd50)) { PersistState(); return; }

      double se = (sd50 > 0) ? sd50/MathSqrt(50.0) : 0.0001;
      double z = (mean50 - m_expected_avg_r) / se;

      if(m_state == DEGRADATION_NORMAL)
        {
         if(z <= -m_sigma_threshold)
           {
            m_state = DEGRADATION_HALVED;
            m_halved_at_count = m_count;
            PrintFormat("DegradationMonitor: ALERT drift %.2fsigma below expected (mean_r=%.3f vs expected=%.3f). "
                        "Halving size.", z, mean50, m_expected_avg_r);
           }
        }
      else if(m_state == DEGRADATION_HALVED)
        {
         if(m_count - m_halved_at_count >= 50)
           {
            if(z <= -m_sigma_threshold)
              {
               m_state = DEGRADATION_HALTED;
               PrintFormat("DegradationMonitor: STILL degraded after another 50 trades (mean_r=%.3f, z=%.2f). "
                           "Halting trading -- awaiting human review.", mean50, z);
              }
            else
              {
               m_state = DEGRADATION_NORMAL;
               PrintFormat("DegradationMonitor: recovered (mean_r=%.3f, z=%.2f). Resuming full size.", mean50, z);
              }
           }
        }
      PersistState();
     }
  };
//+------------------------------------------------------------------+
