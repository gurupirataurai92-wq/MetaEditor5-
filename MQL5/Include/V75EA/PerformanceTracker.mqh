//+------------------------------------------------------------------+
//|                                           PerformanceTracker.mqh |
//|  Accumulates realized-trade statistics for evaluation/refinement |
//|  win rate, profit factor, avg win/loss, peak-equity drawdown,    |
//|  and a per-regime breakdown of net profit and trade count.       |
//+------------------------------------------------------------------+
#ifndef V75EA_PERFORMANCE_TRACKER_MQH
#define V75EA_PERFORMANCE_TRACKER_MQH

#property strict

//--- Bucket index is caller-defined (market regime, setup type, ...) so this
//--- tracker carries no dependency on any particular analysis module.
#define PERF_BUCKETS 8

class CPerformanceTracker
  {
private:
   int      m_wins;
   int      m_losses;
   double   m_grossProfit;
   double   m_grossLoss;      // stored as a positive magnitude
   double   m_peakEquity;
   double   m_maxDrawdown;    // in account currency

   //--- per-regime net profit and count (indexed by ENUM_REGIME 0..6)
   double   m_regimeProfit[PERF_BUCKETS];
   int      m_regimeCount[PERF_BUCKETS];

public:
                     CPerformanceTracker(void) { Reset(); }

   void              Reset(void)
     {
      m_wins = 0; m_losses = 0;
      m_grossProfit = 0.0; m_grossLoss = 0.0;
      m_peakEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      m_maxDrawdown = 0.0;
      for(int i = 0; i < PERF_BUCKETS; i++) { m_regimeProfit[i] = 0.0; m_regimeCount[i] = 0; }
     }

   //--- call whenever a position closes
   void              RecordClosedTrade(const double profit, const int bucketAtEntry)
     {
      if(profit >= 0.0) { m_wins++;   m_grossProfit += profit; }
      else              { m_losses++; m_grossLoss   += -profit; }

      int idx = bucketAtEntry;
      if(idx >= 0 && idx < PERF_BUCKETS)
        {
         m_regimeProfit[idx] += profit;
         m_regimeCount[idx]++;
        }

      UpdateDrawdown();
     }

   //--- call on each tick to track equity peak/drawdown even mid-trade
   void              UpdateDrawdown(void)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > m_peakEquity) m_peakEquity = equity;
      double dd = m_peakEquity - equity;
      if(dd > m_maxDrawdown) m_maxDrawdown = dd;
     }

   int               TotalTrades(void)  const { return m_wins + m_losses; }
   double            WinRate(void)      const { int t = m_wins + m_losses; return (t > 0) ? (double)m_wins / t * 100.0 : 0.0; }
   double            ProfitFactor(void) const { return (m_grossLoss > 0.0) ? m_grossProfit / m_grossLoss : 0.0; }
   double            AvgWin(void)       const { return (m_wins   > 0) ? m_grossProfit / m_wins   : 0.0; }
   double            AvgLoss(void)      const { return (m_losses > 0) ? m_grossLoss   / m_losses : 0.0; }
   double            MaxDrawdown(void)  const { return m_maxDrawdown; }

   void              PrintSummary(void)
     {
      Print("=== V75EA performance ===");
      PrintFormat("Trades=%d  WinRate=%.1f%%  ProfitFactor=%.2f  AvgWin=%.2f  AvgLoss=%.2f  MaxDD=%.2f",
                  TotalTrades(), WinRate(), ProfitFactor(), AvgWin(), AvgLoss(), MaxDrawdown());
      for(int i = 0; i < PERF_BUCKETS; i++)
         if(m_regimeCount[i] > 0)
            PrintFormat("  bucket[%d]: trades=%d  netProfit=%.2f", i, m_regimeCount[i], m_regimeProfit[i]);
     }
  };

#endif // V75EA_PERFORMANCE_TRACKER_MQH
