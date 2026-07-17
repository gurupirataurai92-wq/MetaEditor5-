//+------------------------------------------------------------------+
//|                                                     Dashboard.mqh |
//|  MODULE 13 -- on-chart status + dry-run/shadow mode. Shadow mode |
//|  logs every signal it would take, sends no orders -- validate    |
//|  logic before risking a cent.                                    |
//+------------------------------------------------------------------+
#property strict
#include "Defines.mqh"

class CDashboard
  {
public:
   void Render(const bool shadow_mode, const ENUM_REGIME regime, const ENUM_ARCHETYPE active_archetype,
               const double confidence, const double threshold, const double spread_pts,
               const double cost_ratio, const double cost_gate_ratio, const int trades_today,
               const double daily_pnl_pct, const double weekly_pnl_pct, const int consecutive_losses,
               const bool daily_halted, const bool weekly_halted, const bool degradation_halted,
               const double rolling_expectancy_r, const string last_block_reason)
     {
      string mode = shadow_mode ? "SHADOW (no orders sent)" : "LIVE";
      string txt = "";
      txt += StringFormat("=== XAUUSD GODMODE EA [%s] ===\n", mode);
      txt += StringFormat("Regime: %s   Active archetype: %s\n", RegimeToString(regime), ArchetypeToString(active_archetype));
      txt += StringFormat("Confidence: %.3f  (threshold %.3f, distance %.3f)\n", confidence, threshold, confidence-threshold);
      txt += StringFormat("Spread: %.1f pts   Cost ratio: %.1f%% (gate %.1f%%)\n", spread_pts, cost_ratio*100.0, cost_gate_ratio*100.0);
      txt += StringFormat("Trades today: %d   Daily P&L: %.2f%%   Weekly P&L: %.2f%%\n", trades_today, daily_pnl_pct, weekly_pnl_pct);
      txt += StringFormat("Loss streak: %d   Daily halt: %s   Weekly halt: %s\n",
                          consecutive_losses, daily_halted?"YES":"no", weekly_halted?"YES":"no");
      txt += StringFormat("Degradation halt: %s   Rolling 50-trade expectancy: %.3fR\n",
                          degradation_halted?"YES":"no", rolling_expectancy_r);
      txt += StringFormat("Last block reason: %s\n", last_block_reason);
      Comment(txt);
     }

   void Clear() { Comment(""); }
  };
//+------------------------------------------------------------------+
