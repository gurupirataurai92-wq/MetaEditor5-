//+------------------------------------------------------------------+
//|                                       ExecutionQualityMonitor.mqh |
//|  MODULE 10 -- real execution cost is almost always worse than   |
//|  quoted spread. This module measures the truth and feeds it     |
//|  back into the cost gate.                                        |
//+------------------------------------------------------------------+
#property strict
#include "Defines.mqh"

class CExecutionQualityMonitor
  {
private:
   double   m_avg_slippage_points;
   double   m_avg_latency_ms;
   int      m_total_attempts;
   int      m_total_rejections;
   double   m_max_acceptable_slippage_points;
   double   m_max_acceptable_rejection_rate;

public:
                     CExecutionQualityMonitor()
     {
      m_avg_slippage_points = 0.0;
      m_avg_latency_ms = 0.0;
      m_total_attempts = 0;
      m_total_rejections = 0;
     }

   void Init(const double max_acceptable_slippage_points, const double max_acceptable_rejection_rate)
     {
      m_max_acceptable_slippage_points = max_acceptable_slippage_points;
      m_max_acceptable_rejection_rate = max_acceptable_rejection_rate;
     }

   //--- requested vs fill price, converted to points -------------------
   void RecordFill(const double requested_price, const double fill_price, const double point)
     {
      if(point <= 0.0) return;
      double slip = MathAbs(fill_price - requested_price) / point;
      m_avg_slippage_points = (m_avg_slippage_points*0.9) + (slip*0.1);
      m_total_attempts++;
     }

   void RecordRejection()
     {
      m_total_attempts++;
      m_total_rejections++;
     }

   void RecordLatency(const double ms)
     {
      m_avg_latency_ms = (m_avg_latency_ms*0.9) + (ms*0.1);
     }

   double AvgSlippagePoints() const { return m_avg_slippage_points; }
   double AvgLatencyMs() const { return m_avg_latency_ms; }
   double RejectionRate() const
     {
      return (m_total_attempts > 0) ? (double)m_total_rejections/(double)m_total_attempts : 0.0;
     }

   //--- if execution quality degrades, caller should reduce size or stand down
   bool IsDegraded() const
     {
      return (m_avg_slippage_points > m_max_acceptable_slippage_points) ||
             (RejectionRate() > m_max_acceptable_rejection_rate);
     }
  };
//+------------------------------------------------------------------+
