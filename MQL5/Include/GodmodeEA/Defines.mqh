//+------------------------------------------------------------------+
//|                                                     Defines.mqh |
//|              XAUUSD Adaptive Scalper -- GODMODE build           |
//|  Shared enums / structs used by every module. No trading logic  |
//|  lives here -- this is the vocabulary the modules share.        |
//+------------------------------------------------------------------+
#property strict

//--- Module 2: MarketState regime. Gold only ever gets two states --
//--- by design: a range-fade branch is explicitly forbidden.       |
enum ENUM_REGIME
  {
   REGIME_STAND_DOWN = 0,
   REGIME_TREND      = 1
  };

//--- Module 3: the four thesis archetypes. Each is scored,        |
//--- thresholded and expectancy-tracked independently.             |
enum ENUM_ARCHETYPE
  {
   ARCH_NONE = 0,
   ARCH_LIQUIDITY_SWEEP,
   ARCH_OR_BREAK,
   ARCH_TRAP_REVERSAL,
   ARCH_PULLBACK_CONTINUATION,
   ARCH_COUNT // sentinel, keep last
  };

//--- Direction of a candidate/armed/open trade -------------------
enum ENUM_TRADE_DIR
  {
   DIR_NONE = 0,
   DIR_BUY  = 1,
   DIR_SELL = -1
  };

//--- Why a position/pending order was closed or cancelled --------
enum ENUM_EXIT_REASON
  {
   EXIT_NONE = 0,
   EXIT_STOP_LOSS,
   EXIT_TAKE_PROFIT,
   EXIT_INVALIDATION,
   EXIT_TIME_STOP,
   EXIT_MOMENTUM_DECAY,
   EXIT_VOLATILITY_COLLAPSE,
   EXIT_PARTIAL_TP1,
   EXIT_TRAIL_STOP,
   EXIT_WEEKEND_FLAT,
   EXIT_MANUAL,
   EXIT_DEGRADATION_HALT
  };

//--- Why the EA declined to trade a given bar/setup. Logged --     |
//--- verbatim so "no silent blocking" is enforced.                 |
enum ENUM_REJECT_REASON
  {
   REJECT_NONE = 0,
   REJECT_REGIME_STANDDOWN,
   REJECT_NO_SETUP,
   REJECT_SCORE_BELOW_THRESHOLD,
   REJECT_COST_GATE,
   REJECT_SPREAD_SPIKE,
   REJECT_NEWS_BLACKOUT,
   REJECT_ROLLOVER_BLACKOUT,
   REJECT_SESSION_CLOSED,
   REJECT_GAP_GUARD,
   REJECT_RISK_GOVERNOR,
   REJECT_DAILY_DD_HALT,
   REJECT_WEEKLY_DD_HALT,
   REJECT_LOSS_STREAK_COOLDOWN,
   REJECT_MAX_TRADES_DAY,
   REJECT_CORRELATION_GUARD,
   REJECT_POSITION_ALREADY_OPEN,
   REJECT_DEGRADATION_HALT,
   REJECT_BROKER_QUALITY_GATE,
   REJECT_ACCOUNT_TOO_SMALL
  };

//--- A trade thesis: a falsifiable claim plus its exact           |
//--- invalidation condition. NOT a bare confidence number.         |
struct ThesisSignal
  {
   ENUM_ARCHETYPE archetype;
   ENUM_TRADE_DIR direction;
   double         trigger_price;     // pending order trigger level
   double         invalidation_price;// where the IDEA is dead (often < |1R|)
   double         structural_sl;     // where you are financially out
   datetime       armed_time;
   bool           requires_m1_confirm; // reversal archetypes: yes: momentum archetypes: no

   // Component scores (0..1), filled by ConfidenceEngine
   double         comp_htf_bias;
   double         comp_structural_pos;
   double         comp_momentum;
   double         comp_candle;
   double         comp_vol_expansion;
   double         comp_liquidity_sweep;
   double         comp_cost_headroom;
   double         confidence;        // final weighted score
   double         spread_at_signal;  // spread (points) at the moment this thesis was scored
  };

//--- Per-archetype rolling expectancy bookkeeping ------------------
struct ArchetypeStats
  {
   int    trade_count;
   double sum_r;
   double sum_r_sq;
   bool   killed; // true once flagged as a persistent bleeder
  };

//--- Confidence component weights (Module 4 starting weights) ----
struct ConfidenceWeights
  {
   double htf_bias;
   double structural_pos;
   double momentum;
   double candle;
   double vol_expansion;
   double liquidity_sweep;
   double cost_headroom;
  };

//--- One row of the Journal CSV (Module 11) -----------------------
struct JournalRow
  {
   datetime       timestamp;
   ENUM_ARCHETYPE archetype;
   double         confidence_score;
   ConfidenceWeights component_scores;
   ENUM_REGIME    regime;
   string         session;
   double         spread_at_signal;
   double         spread_at_fill;
   double         slippage_points;
   double         entry;
   double         sl;
   double         tp;
   double         invalidation_level;
   ENUM_EXIT_REASON exit_reason;
   double         mfe_r;
   double         mae_r;
   double         r_multiple;
   int            duration_bars;
  };

//--- Risk / account state persisted across restarts (Module 8) ---
struct RiskState
  {
   datetime last_reset_day;
   datetime last_reset_week;
   double   daily_start_equity;
   double   weekly_start_equity;
   double   daily_pnl_pct;
   double   weekly_pnl_pct;
   int      consecutive_losses;
   datetime cooldown_until;
   double   equity_high_water_mark;
   bool     daily_halted;
   bool     weekly_halted;
   bool     degradation_halted;
  };

//--- Small helpers shared across modules --------------------------
string ArchetypeToString(const ENUM_ARCHETYPE a)
  {
   switch(a)
     {
      case ARCH_LIQUIDITY_SWEEP:        return "SWEEP";
      case ARCH_OR_BREAK:                return "OR_BREAK";
      case ARCH_TRAP_REVERSAL:           return "TRAP";
      case ARCH_PULLBACK_CONTINUATION:   return "PULLBACK";
      default:                           return "NONE";
     }
  }

string RegimeToString(const ENUM_REGIME r)
  {
   return (r == REGIME_TREND) ? "TREND" : "STAND_DOWN";
  }

string RejectReasonToString(const ENUM_REJECT_REASON r)
  {
   switch(r)
     {
      case REJECT_REGIME_STANDDOWN:        return "regime_standdown";
      case REJECT_NO_SETUP:                return "no_setup";
      case REJECT_SCORE_BELOW_THRESHOLD:   return "score_below_threshold";
      case REJECT_COST_GATE:               return "cost_gate";
      case REJECT_SPREAD_SPIKE:            return "spread_spike_circuit_breaker";
      case REJECT_NEWS_BLACKOUT:           return "news_blackout";
      case REJECT_ROLLOVER_BLACKOUT:       return "rollover_blackout";
      case REJECT_SESSION_CLOSED:          return "session_closed";
      case REJECT_GAP_GUARD:               return "gap_guard";
      case REJECT_RISK_GOVERNOR:           return "risk_governor";
      case REJECT_DAILY_DD_HALT:           return "daily_dd_halt";
      case REJECT_WEEKLY_DD_HALT:          return "weekly_dd_halt";
      case REJECT_LOSS_STREAK_COOLDOWN:    return "loss_streak_cooldown";
      case REJECT_MAX_TRADES_DAY:          return "max_trades_day";
      case REJECT_CORRELATION_GUARD:       return "correlation_guard";
      case REJECT_POSITION_ALREADY_OPEN:   return "position_already_open";
      case REJECT_DEGRADATION_HALT:        return "degradation_halt";
      case REJECT_BROKER_QUALITY_GATE:     return "broker_quality_gate";
      case REJECT_ACCOUNT_TOO_SMALL:       return "account_too_small";
      default:                             return "none";
     }
  }

string ExitReasonToString(const ENUM_EXIT_REASON r)
  {
   switch(r)
     {
      case EXIT_STOP_LOSS:            return "stop_loss";
      case EXIT_TAKE_PROFIT:          return "take_profit";
      case EXIT_INVALIDATION:         return "invalidation";
      case EXIT_TIME_STOP:            return "time_stop";
      case EXIT_MOMENTUM_DECAY:       return "momentum_decay";
      case EXIT_VOLATILITY_COLLAPSE:  return "volatility_collapse";
      case EXIT_PARTIAL_TP1:          return "partial_tp1";
      case EXIT_TRAIL_STOP:           return "trail_stop";
      case EXIT_WEEKEND_FLAT:         return "weekend_flat";
      case EXIT_MANUAL:               return "manual";
      case EXIT_DEGRADATION_HALT:     return "degradation_halt";
      default:                        return "none";
     }
  }
//+------------------------------------------------------------------+
