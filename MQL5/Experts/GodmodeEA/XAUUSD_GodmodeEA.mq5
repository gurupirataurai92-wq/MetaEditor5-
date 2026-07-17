//+------------------------------------------------------------------+
//|                                          XAUUSD_GodmodeEA.mq5    |
//|         XAUUSD Adaptive Scalper -- GODMODE build                |
//|         M5 execution | multi-timeframe context | thesis-driven  |
//|                                                                    |
//|  No EA guarantees profit on any given trade. Win rate is an     |
//|  output, not a setting -- the only meaningful metric is          |
//|  expectancy after real costs. This EA will not martingale, grid,|
//|  average down, or trade without a hard stop. If it does not     |
//|  trade, the Journal states exactly which component blocked it.  |
//+------------------------------------------------------------------+
#property copyright "GODMODE build"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include "..\..\Include\GodmodeEA\Defines.mqh"
#include "..\..\Include\GodmodeEA\BrokerAdapter.mqh"
#include "..\..\Include\GodmodeEA\MarketState.mqh"
#include "..\..\Include\GodmodeEA\ThesisEngine.mqh"
#include "..\..\Include\GodmodeEA\ConfidenceEngine.mqh"
#include "..\..\Include\GodmodeEA\CostGate.mqh"
#include "..\..\Include\GodmodeEA\ExecutionEngine.mqh"
#include "..\..\Include\GodmodeEA\PositionManager.mqh"
#include "..\..\Include\GodmodeEA\RiskGovernor.mqh"
#include "..\..\Include\GodmodeEA\Blackouts.mqh"
#include "..\..\Include\GodmodeEA\ExecutionQualityMonitor.mqh"
#include "..\..\Include\GodmodeEA\Journal.mqh"
#include "..\..\Include\GodmodeEA\DegradationMonitor.mqh"
#include "..\..\Include\GodmodeEA\Dashboard.mqh"

//--- General ---------------------------------------------------------
input group "=== General ==="
input ulong   InpMagic               = 20260715; // Magic number
input bool    InpShadowMode          = true;     // Dry-run: log signals, send no orders
input double  InpCommissionPerLot    = 0.0;      // Commission per lot round-turn, account currency (API can't read this reliably)
input int     InpMedianSpreadWarnPts = 35;       // Warn if current spread exceeds this many points

//--- Module 2: MarketState --------------------------------------------
input group "=== Regime (MarketState) ==="
input double  InpAdxTrendMin       = 22.0;  // ADX(14) floor to call it TREND
input double  InpAtrPercentileMin  = 0.50;  // ATR must rank above this trailing-200-bar percentile
input int     InpEmaSlopeLookback  = 5;     // Bars back for H1/M15 EMA slope

//--- Module 3: ThesisEngine --------------------------------------------
input group "=== Thesis Archetypes ==="
input int     InpSwingLookback     = 100;   // Bars searched for a confirmed swing high/low
input int     InpFractalK          = 3;     // Bars either side to confirm a swing (fractal)
input int     InpORBars            = 4;     // Opening-range bars (3-6 per spec)
input int     InpLondonOpenHourGMT = 7;      // London-session open hour, GMT

//--- Module 4: ConfidenceEngine ----------------------------------------
input group "=== Confidence Scoring ==="
input double  InpScoreFullSize   = 0.75;  // >= this score -> full size
input double  InpScoreHalfSize   = 0.65;  // >= this score -> half size, below -> no trade
input double  InpWeightLearnRate = 0.02;  // v1 adaptive learning rate (small, bounded)
input double  InpWeightFloor     = 0.03;  // hard floor per component weight
input double  InpWeightCeiling   = 0.40;  // hard ceiling per component weight

//--- Module 5: CostGate --------------------------------------------------
input group "=== Cost Gate ==="
input double  InpCostGateRatio        = 0.20; // reject if cost_pts > ratio x ATR(M5,14)
input int     InpSpreadSpikeLookback  = 20;   // bars for spread median
input double  InpSpreadSpikeMultiplier= 3.0;  // circuit breaker: current > median x this

//--- Module 6: ExecutionEngine --------------------------------------------
input group "=== Execution ==="
input int     InpDeviationPoints    = 30; // max slippage tolerance
input int     InpWatchWindowM1Bars  = 5;  // 3-6 M1 bars per spec
input int     InpMaxRequoteRetries  = 3;  // then abandon, never chase

//--- Module 7: PositionManager --------------------------------------------
input group "=== Trade Management ==="
input double  InpSlAtrMult        = 1.5;  // structural SL buffer beyond swing
input double  InpChandelierMult   = 3.75; // 3.5-4x ATR trail on the runner
input int     InpTimeStopBars     = 18;   // 15-20 M5 bars
input double  InpTimeStopR        = 0.5;  // must be at +0.5R by the time-stop bar
input double  InpVolCollapseRatio = 0.5;  // exit if ATR contracts below this fraction of entry ATR

//--- Module 8: RiskGovernor --------------------------------------------
input group "=== Risk Governor ==="
input double  InpRiskPercent           = 0.35; // 0.25-0.5% per trade
input double  InpDailyDDCutoffPct      = -2.0;
input double  InpWeeklyDDCutoffPct     = -5.0;
input int     InpLossStreakLimit       = 3;
input int     InpCooldownMinutes       = 90;   // 60-120 per spec
input int     InpMaxTradesPerDay       = 6;
input double  InpProfitLockTriggerPct  = 2.0;
input double  InpProfitLockTightenedPct= -0.5;
input double  InpDDScaleFactor         = 2.0;
input double  InpDDScaleFloor          = 0.25;

//--- Module 9: Blackouts --------------------------------------------
input group "=== Blackouts & Sessions ==="
input int     InpNewsMinutesBefore     = 30;
input int     InpNewsMinutesAfter      = 30;
input int     InpRolloverHourServer    = 0;
input int     InpRolloverMinutesBuffer = 10;
input int     InpSessionStartHourGMT   = 6;
input int     InpSessionEndHourGMT     = 17;
input int     InpMondayGapGuardMinutes = 15;
input int     InpFridayLateGuardHourGMT= 19;

//--- Module 10: ExecutionQualityMonitor --------------------------------------------
input group "=== Execution Quality ==="
input double  InpMaxAcceptableSlippagePts   = 15.0;
input double  InpMaxAcceptableRejectionRate = 0.20;

//--- Module 12: DegradationMonitor --------------------------------------------
input group "=== Degradation Monitor ==="
input double  InpExpectedAvgR       = 0.15; // MUST come from YOUR OWN backtest -- not a guess
input double  InpDegradationSigma   = 2.0;
input bool    InpResetDegradationHalt = false; // one-shot manual reset after human review

//--- module instances --------------------------------------------------
CBrokerAdapter            g_broker;
CMarketState              g_marketState;
CThesisEngine             g_thesisEngine;
CConfidenceEngine         g_confidenceEngine;
CCostGate                 g_costGate;
CExecutionEngine          g_executionEngine;
CPositionManager          g_positionManager;
CRiskGovernor             g_riskGovernor;
CBlackouts                g_blackouts;
CExecutionQualityMonitor  g_eqm;
CJournal                  g_journal;
CDegradationMonitor       g_degradationMonitor;
CDashboard                g_dashboard;

datetime g_lastM5BarTime = 0;
datetime g_lastM1BarTime = 0;
string   g_lastBlockReason = "none";
ENUM_ARCHETYPE g_lastCandidateArchetype = ARCH_NONE;
double   g_lastCandidateConfidence = 0.0;
ENUM_EXIT_REASON g_lastExitReason = EXIT_NONE; // set by PositionManager.Manage(), consumed in OnTradeTransaction

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_broker.Init(InpCommissionPerLot))
     {
      Print("OnInit FAILED: ", g_broker.LastError());
      return INIT_FAILED;
     }

   // rough structural-stop estimate (1.5xATR) purely to run the quality gate now
   int atrProbeHandle = iATR(g_broker.Symbol(), PERIOD_M5, 14);
   double atrProbe[];
   double probeAtr = 0.0;
   if(atrProbeHandle != INVALID_HANDLE && CopyBuffer(atrProbeHandle, 0, 1, 1, atrProbe) == 1)
      probeAtr = atrProbe[0];
   if(atrProbeHandle != INVALID_HANDLE) IndicatorRelease(atrProbeHandle);

   int probeStopPoints = (probeAtr > 0) ? (int)MathRound(InpSlAtrMult * probeAtr / g_broker.Point()) : 0;
   string qualityReason = g_broker.QualityGate(InpRiskPercent, probeStopPoints, InpMedianSpreadWarnPts);
   if(qualityReason != "")
     {
      Print("OnInit FAILED (broker quality gate): ", qualityReason);
      return INIT_FAILED;
     }

   bool ok = true;
   ok &= g_marketState.Init(g_broker.Symbol(), InpAdxTrendMin, InpAtrPercentileMin, InpEmaSlopeLookback);
   g_thesisEngine.Init(g_broker.Symbol(), InpSwingLookback, InpFractalK, InpORBars, InpLondonOpenHourGMT);
   ok &= g_confidenceEngine.Init(g_broker.Symbol(), InpScoreFullSize, InpScoreHalfSize,
                                  InpWeightLearnRate, InpWeightFloor, InpWeightCeiling);
   // convert commission-per-lot (money) to a points-equivalent so it's directly
   // comparable to spread points and ATR points inside the cost gate ratio
   double moneyPerPointPerLot = (g_broker.TickSize() > 0) ?
      g_broker.TickValue() * (g_broker.Point()/g_broker.TickSize()) : 0.0;
   double commissionPoints = (moneyPerPointPerLot > 0) ? InpCommissionPerLot/moneyPerPointPerLot : 0.0;
   g_costGate.Init(g_broker.Symbol(), InpCostGateRatio, commissionPoints, InpSpreadSpikeLookback, InpSpreadSpikeMultiplier);
   ok &= g_executionEngine.Init(g_broker.Symbol(), g_broker.Digits(), g_broker.Point(), g_broker.ExecMode(),
                                 g_broker.FillingMode(), InpMagic, InpDeviationPoints, InpWatchWindowM1Bars,
                                 InpMaxRequoteRetries);
   ok &= g_positionManager.Init(g_broker.Symbol(), InpMagic, InpSlAtrMult, InpChandelierMult,
                                 InpTimeStopBars, InpTimeStopR, InpVolCollapseRatio);
   g_riskGovernor.Init(g_broker.Symbol(), InpMagic, InpRiskPercent, InpDailyDDCutoffPct, InpWeeklyDDCutoffPct,
                        InpLossStreakLimit, InpCooldownMinutes, InpMaxTradesPerDay,
                        InpProfitLockTriggerPct, InpProfitLockTightenedPct, InpDDScaleFactor, InpDDScaleFloor);
   g_blackouts.Init(g_broker.Symbol(), InpNewsMinutesBefore, InpNewsMinutesAfter,
                     InpRolloverHourServer, InpRolloverMinutesBuffer,
                     InpSessionStartHourGMT, InpSessionEndHourGMT,
                     InpMondayGapGuardMinutes, InpFridayLateGuardHourGMT);
   g_eqm.Init(InpMaxAcceptableSlippagePts, InpMaxAcceptableRejectionRate);
   ok &= g_journal.Init("GodmodeEA_" + g_broker.Symbol(), g_broker.Digits());
   g_degradationMonitor.Init(g_broker.Symbol(), InpMagic, InpExpectedAvgR, InpDegradationSigma, InpResetDegradationHalt);

   if(!ok)
     {
      Print("OnInit FAILED: one or more modules failed to initialize (see log above).");
      return INIT_FAILED;
     }

   PrintFormat("GODMODE EA initialized. Symbol=%s ShadowMode=%s Magic=%I64u",
               g_broker.Symbol(), InpShadowMode?"ON":"off", InpMagic);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_marketState.Release();
   g_confidenceEngine.Release();
   g_executionEngine.Release();
   g_positionManager.Release();
   g_journal.Close();
   g_dashboard.Clear();
  }

//+------------------------------------------------------------------+
//| Evaluate all thesis candidates, arm the best one if it clears    |
//| every gate. Called once per new M5 bar close, only when flat.   |
//+------------------------------------------------------------------+
void EvaluateAndMaybeArm()
  {
   double m15ema = g_marketState.M15EmaValue();
   ThesisSignal signals[];
   int n = g_thesisEngine.Evaluate(g_marketState.Regime(), g_marketState.RegimeDirection(), m15ema, signals);

   datetime barTime = iTime(g_broker.Symbol(), PERIOD_M5, 0);
   double atrPts = g_marketState.LastATR() / g_broker.Point();
   double currentSpreadPts = (double)SymbolInfoInteger(g_broker.Symbol(), SYMBOL_SPREAD);

   if(n == 0)
     {
      ENUM_REJECT_REASON r = (g_marketState.Regime() != REGIME_TREND) ? REJECT_REGIME_STANDDOWN : REJECT_NO_SETUP;
      g_lastBlockReason = RejectReasonToString(r);
      g_journal.LogRejection(barTime, g_marketState.Regime(), ARCH_NONE, 0.0, InpScoreHalfSize,
                              currentSpreadPts, atrPts, r);
      return;
     }

   double costRatio = g_costGate.CurrentCostRatio(atrPts);
   double spreadAtSignal = currentSpreadPts;

   int bestIdx = -1;
   double bestConf = -1.0;
   for(int i=0; i<n; i++)
     {
      signals[i].spread_at_signal = spreadAtSignal;
      signals[i].comp_liquidity_sweep = g_thesisEngine.CheckSweepConfluence(signals[i].direction) ? 1.0 : 0.0;
      double conf = g_confidenceEngine.Score(signals[i], g_marketState.H1Dir(), g_marketState.M15Dir(),
                                              g_marketState.IsATRExpanding(), costRatio, g_costGate.GateRatio());
      if(conf > bestConf) { bestConf = conf; bestIdx = i; }
     }

   ThesisSignal chosen = signals[bestIdx];
   g_lastCandidateArchetype = chosen.archetype;
   g_lastCandidateConfidence = chosen.confidence;

   double tier = g_confidenceEngine.TierSizeMultiplier(chosen.confidence);
   ENUM_REJECT_REASON reason = REJECT_NONE;

   if(tier <= 0.0)                                   reason = REJECT_SCORE_BELOW_THRESHOLD;
   else if(costRatio > g_costGate.GateRatio())        reason = REJECT_COST_GATE;
   else if(g_costGate.IsSpreadSpiking())              reason = REJECT_SPREAD_SPIKE;
   else
     {
      ENUM_REJECT_REASON b = g_blackouts.CheckAll();
      if(b != REJECT_NONE) reason = b;
     }
   if(reason == REJECT_NONE)
     {
      ENUM_REJECT_REASON rg = g_riskGovernor.CanTrade();
      if(rg != REJECT_NONE) reason = rg;
     }
   if(reason == REJECT_NONE && g_degradationMonitor.IsHalted())
      reason = REJECT_DEGRADATION_HALT;

   if(reason != REJECT_NONE)
     {
      g_lastBlockReason = RejectReasonToString(reason);
      g_journal.LogRejection(barTime, g_marketState.Regime(), chosen.archetype, chosen.confidence,
                              InpScoreHalfSize, costRatio*atrPts, atrPts, reason);
      return;
     }

   // passed every gate -- size it and (unless shadow mode) arm the pending order
   double spreadPriceDist = currentSpreadPts * g_broker.Point();
   double sl = g_positionManager.CalcStructuralSL(chosen.direction, chosen.invalidation_price, g_marketState.LastATR(),
                                                   g_broker.StopsLevelPoints(), spreadPriceDist,
                                                   g_broker.Point(), g_broker.Digits());
   chosen.structural_sl = sl;

   double entryRef = (chosen.direction==DIR_BUY) ? SymbolInfoDouble(g_broker.Symbol(), SYMBOL_ASK)
                                                   : SymbolInfoDouble(g_broker.Symbol(), SYMBOL_BID);
   double slDist = MathAbs(entryRef - sl);

   double sizeMult = tier * g_riskGovernor.SizeMultiplier();
   if(g_degradationMonitor.ShouldHalveSize()) sizeMult *= 0.5;
   if(g_eqm.IsDegraded()) sizeMult *= 0.5;

   double lots = g_riskGovernor.LotsForRisk(slDist, g_broker.TickSize(), g_broker.TickValue(),
                                             g_broker.VolMin(), g_broker.VolMax(), g_broker.VolStep(), sizeMult);

   if(lots < g_broker.VolMin())
     {
      g_lastBlockReason = RejectReasonToString(REJECT_ACCOUNT_TOO_SMALL);
      g_journal.LogRejection(barTime, g_marketState.Regime(), chosen.archetype, chosen.confidence,
                              InpScoreHalfSize, costRatio*atrPts, atrPts, REJECT_ACCOUNT_TOO_SMALL);
      return;
     }

   if(InpShadowMode)
     {
      PrintFormat("SHADOW: would ARM %s %s conf=%.3f lots=%.2f entry~%.2f sl=%.2f invalidation=%.2f",
                  ArchetypeToString(chosen.archetype), chosen.direction==DIR_BUY?"BUY":"SELL",
                  chosen.confidence, lots, chosen.trigger_price, sl, chosen.invalidation_price);
      g_lastBlockReason = "shadow_mode_would_trade";
      return;
     }

   string comment = StringFormat("GM_%s", ArchetypeToString(chosen.archetype));
   g_executionEngine.Arm(chosen, lots, comment);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_broker.IsReady()) return;

   g_riskGovernor.RefreshPnL(); // keep the Dashboard's P&L numbers live every tick,
                                 // not just when a trade signal happens to be evaluated

   datetime m5Time = iTime(g_broker.Symbol(), PERIOD_M5, 0);
   datetime m1Time = iTime(g_broker.Symbol(), PERIOD_M1, 0);
   bool newM5 = (m5Time != g_lastM5BarTime);
   bool newM1 = (m1Time != g_lastM1BarTime);

   if(newM1)
     {
      g_lastM1BarTime = m1Time;
      g_executionEngine.OnNewM1Bar();
     }

   if(newM5)
     {
      g_lastM5BarTime = m5Time;
      g_costGate.SampleSpread();
      g_marketState.Update();
      g_thesisEngine.UpdateOpeningRange();
      g_positionManager.OnNewM5Bar();
      g_riskGovernor.RefreshCalendar();

      if(!g_positionManager.HasPosition() && !g_executionEngine.IsArmed())
         EvaluateAndMaybeArm();
     }

   if(g_executionEngine.IsArmed())
     {
      ThesisSignal armed = g_executionEngine.ArmedSignal();
      double checkPrice = (armed.direction==DIR_BUY) ? SymbolInfoDouble(g_broker.Symbol(), SYMBOL_BID)
                                                       : SymbolInfoDouble(g_broker.Symbol(), SYMBOL_ASK);
      g_executionEngine.WatchTick(checkPrice, g_costGate.IsSpreadSpiking());
     }

   if(g_positionManager.HasPosition())
     {
      ENUM_EXIT_REASON er = g_positionManager.Manage();
      if(er != EXIT_NONE) g_lastExitReason = er;
     }

   g_dashboard.Render(InpShadowMode, g_marketState.Regime(), g_lastCandidateArchetype, g_lastCandidateConfidence,
                       InpScoreHalfSize, (double)SymbolInfoInteger(g_broker.Symbol(),SYMBOL_SPREAD),
                       g_costGate.CurrentCostRatio(g_marketState.LastATR()/MathMax(g_broker.Point(),0.00001)),
                       g_costGate.GateRatio(), g_riskGovernor.TradesToday(),
                       g_riskGovernor.GetState().daily_pnl_pct, g_riskGovernor.GetState().weekly_pnl_pct,
                       g_riskGovernor.GetState().consecutive_losses, g_riskGovernor.GetState().daily_halted,
                       g_riskGovernor.GetState().weekly_halted, g_degradationMonitor.IsHalted(),
                       g_degradationMonitor.RollingExpectancy50(), g_lastBlockReason);
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   string dealSymbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long   dealMagic  = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(dealSymbol != g_broker.Symbol() || (ulong)dealMagic != InpMagic) return;

   long   entry     = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   double dealPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   ulong  posTicket  = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

   if(entry == DEAL_ENTRY_IN)
     {
      if(g_executionEngine.IsArmed())
        {
         ThesisSignal sig = g_executionEngine.ArmedSignal();
         g_positionManager.RegisterOpenPosition(posTicket, sig, dealPrice, sig.structural_sl);
         g_eqm.RecordFill(sig.trigger_price, dealPrice, g_broker.Point());
         g_costGate.UpdateRealizedSlippage(MathAbs(dealPrice - sig.trigger_price)/g_broker.Point());
         g_executionEngine.ClearArmedAfterFill();
        }
      return;
     }

   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
     {
      if(!g_positionManager.HasPosition()) return;
      OpenTradeState st = g_positionManager.GetState();
      if(posTicket != st.ticket) return;
      if(PositionSelectByTicket(st.ticket)) return; // still open (partial close only)

      double r = (st.signal.direction == DIR_BUY) ? (dealPrice - st.entry_price)/st.risk_distance
                                                    : (st.entry_price - dealPrice)/st.risk_distance;

      JournalRow row;
      row.timestamp = TimeCurrent();
      row.archetype = st.signal.archetype;
      row.confidence_score = st.signal.confidence;
      row.component_scores.htf_bias        = st.signal.comp_htf_bias;
      row.component_scores.structural_pos  = st.signal.comp_structural_pos;
      row.component_scores.momentum        = st.signal.comp_momentum;
      row.component_scores.candle          = st.signal.comp_candle;
      row.component_scores.vol_expansion   = st.signal.comp_vol_expansion;
      row.component_scores.liquidity_sweep = st.signal.comp_liquidity_sweep;
      row.component_scores.cost_headroom   = st.signal.comp_cost_headroom;
      row.regime = g_marketState.Regime();
      row.session = g_blackouts.IsOutsideSession() ? "outside" : "session";
      row.spread_at_signal = st.spread_at_signal;
      row.spread_at_fill = (double)SymbolInfoInteger(g_broker.Symbol(), SYMBOL_SPREAD);
      row.slippage_points = g_eqm.AvgSlippagePoints();
      row.entry = st.entry_price;
      row.sl = st.initial_sl;
      row.tp = 0.0; // no fixed TP -- managed via partial/trail/time-stop/invalidation
      row.invalidation_level = st.signal.invalidation_price;
      // g_lastExitReason is set by PositionManager.Manage() the moment it closes a
      // position; if the close instead came from the server (SL/TP hit directly,
      // with Manage() never getting a chance to run first) it falls back to STOP_LOSS.
      row.exit_reason = (g_lastExitReason != EXIT_NONE) ? g_lastExitReason : EXIT_STOP_LOSS;
      row.mfe_r = st.mfe_r;
      row.mae_r = st.mae_r;
      row.r_multiple = r;
      row.duration_bars = st.bars_since_open;

      g_journal.LogTrade(row);
      g_riskGovernor.OnTradeClosed(r);
      g_thesisEngine.RecordTradeResult(st.signal.archetype, r);
      g_degradationMonitor.RecordTrade(r);
      g_confidenceEngine.AdaptWeights(st.signal, r);
      g_positionManager.ClearPosition();
      g_lastExitReason = EXIT_NONE;
     }
  }
//+------------------------------------------------------------------+
