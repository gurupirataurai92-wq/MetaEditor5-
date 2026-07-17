//+------------------------------------------------------------------+
//|                                                     CostGate.mqh |
//|  MODULE 5 -- the make-or-break. On XAUUSD, ATR 120-250 pts vs   |
//|  18-35 pts cost puts you at ~12-20%, the workable edge. This    |
//|  gate is why gold works here and EURUSD does not.               |
//+------------------------------------------------------------------+
#property strict
#include "Defines.mqh"

class CCostGate
  {
private:
   string   m_symbol;
   double   m_cost_gate_ratio;     // default 0.20
   double   m_commission_points;   // commission expressed in points, precomputed by caller
   int      m_spike_lookback;      // 20-bar median window
   double   m_spike_multiplier;    // 3x median triggers circuit breaker
   double   m_spread_history[];
   int      m_spread_history_count;

   double   m_realized_slippage_avg; // fed back from ExecutionQualityMonitor

public:
                     CCostGate() { m_spread_history_count=0; m_realized_slippage_avg=0.0; }

   void Init(const string symbol, const double cost_gate_ratio, const double commission_points,
             const int spike_lookback, const double spike_multiplier)
     {
      m_symbol = symbol;
      m_cost_gate_ratio = cost_gate_ratio;
      m_commission_points = commission_points;
      m_spike_lookback = spike_lookback;
      m_spike_multiplier = spike_multiplier;
      ArrayResize(m_spread_history, m_spike_lookback);
      ArrayInitialize(m_spread_history, 0.0);
     }

   //--- feed realized slippage telemetry back into the gate ---------
   //--- real cost is always worse than quoted spread                 |
   void UpdateRealizedSlippage(const double slippage_points)
     {
      m_realized_slippage_avg = (m_realized_slippage_avg*0.9) + (slippage_points*0.1);
     }

   //--- call once per M5 bar close to maintain the spread median ----
   void SampleSpread()
     {
      double spread_points = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      for(int i=m_spike_lookback-1; i>0; i--)
         m_spread_history[i] = m_spread_history[i-1];
      m_spread_history[0] = spread_points;
      if(m_spread_history_count < m_spike_lookback) m_spread_history_count++;
     }

   double MedianSpread() const
     {
      if(m_spread_history_count == 0) return 0.0;
      double tmp[];
      ArrayResize(tmp, m_spread_history_count);
      for(int i=0; i<m_spread_history_count; i++) tmp[i] = m_spread_history[i];
      ArraySort(tmp);
      int mid = m_spread_history_count/2;
      return (m_spread_history_count % 2 == 0 && m_spread_history_count>1) ?
             (tmp[mid-1]+tmp[mid])/2.0 : tmp[mid];
     }

   //--- spread-spike circuit breaker: freeze all activity -----------
   bool IsSpreadSpiking() const
     {
      double median = MedianSpread();
      if(median <= 0.0) return false;
      double current = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      return (current > median * m_spike_multiplier);
     }

   double CurrentCostRatio(const double atr_points) const
     {
      if(atr_points <= 0.0) return 999.0;
      double spread_points = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      double cost_pts = spread_points + m_commission_points + m_realized_slippage_avg;
      return cost_pts / atr_points;
     }

   double GateRatio() const { return m_cost_gate_ratio; }

   //--- re-check immediately before OrderSend(), not just at signal time
   bool Passes(const double atr_points, double &out_cost_ratio) const
     {
      out_cost_ratio = CurrentCostRatio(atr_points);
      return (out_cost_ratio <= m_cost_gate_ratio);
     }
  };
//+------------------------------------------------------------------+
