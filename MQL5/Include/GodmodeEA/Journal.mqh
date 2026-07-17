//+------------------------------------------------------------------+
//|                                                       Journal.mqh |
//|  MODULE 11 -- this becomes your ML training set. Every trade    |
//|  exported to CSV, every rejected bar logged with a machine-      |
//|  readable reason. "No silent blocking" is enforced here.        |
//+------------------------------------------------------------------+
#property strict
#include "Defines.mqh"

class CJournal
  {
private:
   int      m_trade_handle;
   int      m_reject_handle;
   int      m_digits;

public:
                     CJournal() { m_trade_handle = INVALID_HANDLE; m_reject_handle = INVALID_HANDLE; m_digits = 2; }

   bool Init(const string ea_tag, const int digits)
     {
      m_digits = digits;
      string tradeFile = ea_tag + "_trades.csv";
      string rejectFile = ea_tag + "_rejections.csv";

      bool tradeExisted = FileIsExist(tradeFile);
      m_trade_handle = FileOpen(tradeFile, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
      if(m_trade_handle == INVALID_HANDLE)
        {
         Print("Journal: failed to open trade CSV.");
         return false;
        }
      FileSeek(m_trade_handle, 0, SEEK_END);
      if(!tradeExisted)
        {
         FileWrite(m_trade_handle, "timestamp","archetype","confidence_score",
                   "comp_htf","comp_struct","comp_momentum","comp_candle","comp_vol","comp_sweep","comp_cost",
                   "regime","session","spread_at_signal","spread_at_fill","slippage",
                   "entry","sl","tp","invalidation_level","exit_reason","mfe_r","mae_r","r_multiple","duration_bars");
         FileFlush(m_trade_handle);
        }

      bool rejectExisted = FileIsExist(rejectFile);
      m_reject_handle = FileOpen(rejectFile, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
      if(m_reject_handle == INVALID_HANDLE)
        {
         Print("Journal: failed to open rejection CSV.");
         return false;
        }
      FileSeek(m_reject_handle, 0, SEEK_END);
      if(!rejectExisted)
        {
         FileWrite(m_reject_handle, "bar_time","regime","archetype","score","threshold",
                   "cost_pts","atr_pts","cost_pct_of_atr","reason");
         FileFlush(m_reject_handle);
        }
      return true;
     }

   void LogTrade(const JournalRow &row)
     {
      if(m_trade_handle == INVALID_HANDLE) return;
      FileWrite(m_trade_handle,
                TimeToString(row.timestamp, TIME_DATE|TIME_SECONDS),
                ArchetypeToString(row.archetype),
                DoubleToString(row.confidence_score,3),
                DoubleToString(row.component_scores.htf_bias,3),
                DoubleToString(row.component_scores.structural_pos,3),
                DoubleToString(row.component_scores.momentum,3),
                DoubleToString(row.component_scores.candle,3),
                DoubleToString(row.component_scores.vol_expansion,3),
                DoubleToString(row.component_scores.liquidity_sweep,3),
                DoubleToString(row.component_scores.cost_headroom,3),
                RegimeToString(row.regime),
                row.session,
                DoubleToString(row.spread_at_signal,1),
                DoubleToString(row.spread_at_fill,1),
                DoubleToString(row.slippage_points,1),
                DoubleToString(row.entry,m_digits),
                DoubleToString(row.sl,m_digits),
                DoubleToString(row.tp,m_digits),
                DoubleToString(row.invalidation_level,m_digits),
                ExitReasonToString(row.exit_reason),
                DoubleToString(row.mfe_r,3),
                DoubleToString(row.mae_r,3),
                DoubleToString(row.r_multiple,3),
                (string)row.duration_bars);
      FileFlush(m_trade_handle);
     }

   //--- every bar, a rejection log line: exactly why it isn't trading, quantified
   void LogRejection(const datetime bar_time, const ENUM_REGIME regime, const ENUM_ARCHETYPE archetype,
                      const double score, const double threshold, const double cost_pts,
                      const double atr_pts, const ENUM_REJECT_REASON reason)
     {
      if(m_reject_handle == INVALID_HANDLE) return;
      double cost_pct = (atr_pts>0) ? (cost_pts/atr_pts*100.0) : 0.0;
      FileWrite(m_reject_handle,
                TimeToString(bar_time, TIME_DATE|TIME_MINUTES),
                RegimeToString(regime),
                ArchetypeToString(archetype),
                DoubleToString(score,3),
                DoubleToString(threshold,3),
                DoubleToString(cost_pts,1),
                DoubleToString(atr_pts,1),
                DoubleToString(cost_pct,1),
                RejectReasonToString(reason));
      FileFlush(m_reject_handle);

      PrintFormat("[BAR %s] regime=%s archetype=%s score=%.2f thr=%.2f cost=%.0f/ATR=%.0f (%.0f%% OK) -> SKIP: %s",
                  TimeToString(bar_time,TIME_MINUTES), RegimeToString(regime), ArchetypeToString(archetype),
                  score, threshold, cost_pts, atr_pts, cost_pct, RejectReasonToString(reason));
     }

   void Close()
     {
      if(m_trade_handle != INVALID_HANDLE) FileClose(m_trade_handle);
      if(m_reject_handle != INVALID_HANDLE) FileClose(m_reject_handle);
     }
  };
//+------------------------------------------------------------------+
