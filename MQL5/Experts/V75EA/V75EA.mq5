//+------------------------------------------------------------------+
//|                                                        V75EA.mq5 |
//|  Confluence-based EA for Deriv Volatility 75 Index, driven by an |
//|  OODA decision cycle with an optional adaptive "God mode".      |
//|                                                                  |
//|  OBSERVE   RegimeDetector + ATR/spread snapshot                  |
//|  ORIENT    MultiTimeframe, MarketStructure, TrendStrength,       |
//|            MomentumEngine -> ConfluenceEngine score under an      |
//|            adaptive threshold                                     |
//|  DECIDE    OodaEngine -> signal, risk %, SL/TP, trailing          |
//|  ACT       RiskManager sizing -> TradeManager execution,          |
//|            breakeven, partial close, ATR trailing                 |
//|  FEEDBACK  realized results adapt threshold/risk (bounded) and    |
//|            feed SafetyGuard + PerformanceTracker                  |
//|                                                                  |
//|  God mode = adaptive-aggressive, NOT risk-free: every adaptive   |
//|  request is still clamped by RiskManager's hard cap and gated    |
//|  by SafetyGuard's circuit breakers.                              |
//+------------------------------------------------------------------+
#property copyright "V75EA"
#property version   "3.00"
#property strict

#include <V75EA\Types.mqh>
#include <V75EA\RegimeDetector.mqh>
#include <V75EA\MarketStructure.mqh>
#include <V75EA\MomentumEngine.mqh>
#include <V75EA\TrendStrength.mqh>
#include <V75EA\MultiTimeframe.mqh>
#include <V75EA\ConfluenceEngine.mqh>
#include <V75EA\OodaEngine.mqh>
#include <V75EA\RiskManager.mqh>
#include <V75EA\SafetyGuard.mqh>
#include <V75EA\TradeManager.mqh>
#include <V75EA\PerformanceTracker.mqh>

//--- General
input ulong           InpMagicNumber       = 750001;
input ENUM_TIMEFRAMES InpTimeframe         = PERIOD_M5;   // trade-setup timeframe
input ENUM_TIMEFRAMES InpHtf1              = PERIOD_M15;  // intermediate bias
input ENUM_TIMEFRAMES InpHtf2              = PERIOD_H1;   // overall bias
input bool            InpTradeOnNewBarOnly = true;

//--- Indicator periods (shared where sensible)
input int    InpEmaFast            = 20;
input int    InpEmaSlow            = 50;
input int    InpAdxPeriod          = 14;
input int    InpRsiPeriod          = 14;
input int    InpBandsPeriod        = 20;
input double InpBandsDeviation     = 2.0;
input int    InpAtrPeriod          = 14;

//--- Regime detection
input double InpAdxTrendThreshold  = 22.0;
input double InpAdxStrongThreshold = 30.0;
input double InpAtrExpansionRatio  = 1.5;   // ATR vs 50-bar avg to call a breakout
input double InpBbCompressionRatio = 0.7;   // BB width vs 50-bar avg to call compression
input double InpRsiOverbought      = 70.0;
input double InpRsiOversold        = 30.0;

//--- Market structure
input int    InpFractalStrength    = 2;
input int    InpStructureLookback  = 120;

//--- Momentum / trend strength
input int    InpRocPeriod          = 10;
input int    InpMomentumMaxRun     = 5;
input double InpAdxNormalizer      = 50.0;
input int    InpSlopeLookback      = 5;

//--- Confluence
input double InpMinConfidence      = 0.60;  // base threshold; OODA adapts around it

//--- God mode (adaptive-aggressive OODA loop)
input bool   InpGodMode            = true;
input double InpGodMinConfidence   = 0.50;  // most aggressive adaptive threshold
input double InpGodMaxConfidence   = 0.75;  // most defensive adaptive threshold
input double InpGodRiskBoostMax    = 1.5;   // risk multiplier ceiling on hot streaks
input int    InpMaxPositions       = 3;     // pyramiding cap, same-direction only (1 = off)
input double InpTrailAtrMult       = 2.0;   // ATR trailing distance (god mode)

//--- Risk management
input double InpRiskPercent        = 1.0;   // base risk per trade, % equity
input double InpMaxRiskPercent     = 2.0;   // hard cap, adaptive requests cannot exceed
input double InpAtrStopMultiplier  = 1.5;
input double InpAtrTakeProfitMult  = 3.0;

//--- Safety guard
input double InpMaxDailyLossPercent = 5.0;
input double InpMaxDrawdownPercent  = 15.0;
input int    InpMaxConsecutiveLoss  = 4;
input double InpMaxSpreadPoints     = 500;

//--- Trade management
input int    InpSlippagePoints      = 30;
input double InpBreakevenAtrMult    = 1.0;
input double InpPartialCloseAtrMult = 2.0;
input double InpPartialClosePercent = 50.0;

CRegimeDetector     g_regime;
CMarketStructure    g_structure;
CMomentumEngine     g_momentum;
CTrendStrength      g_trend;
CMultiTimeframe     g_mtf;
CConfluenceEngine   g_confluence;
COodaEngine         g_ooda;
CRiskManager        g_risk;
CSafetyGuard        g_safety;
CTradeManager       g_trades;
CPerformanceTracker g_perf;

datetime    g_lastBarTime   = 0;
ENUM_REGIME g_regimeAtEntry = REGIME_RANGE;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_regime.Init(_Symbol, InpTimeframe, InpAdxPeriod, InpAdxTrendThreshold, InpAdxStrongThreshold,
                     InpEmaFast, InpEmaSlow, InpAtrPeriod, InpBandsPeriod, InpBandsDeviation,
                     InpAtrExpansionRatio, InpBbCompressionRatio))
      return INIT_FAILED;

   g_structure.Init(_Symbol, InpTimeframe, InpFractalStrength, InpStructureLookback);

   if(!g_momentum.Init(_Symbol, InpTimeframe, InpAtrPeriod, InpRocPeriod, InpMomentumMaxRun))
      return INIT_FAILED;

   if(!g_trend.Init(_Symbol, InpTimeframe, InpAdxPeriod, InpEmaFast, InpEmaSlow, InpAtrPeriod,
                    InpAdxNormalizer, InpSlopeLookback))
      return INIT_FAILED;

   if(!g_mtf.Init(_Symbol, InpHtf1, InpHtf2, InpEmaFast, InpEmaSlow))
      return INIT_FAILED;

   if(!g_confluence.Init(_Symbol, InpTimeframe,
                         GetPointer(g_regime), GetPointer(g_structure), GetPointer(g_momentum),
                         GetPointer(g_trend), GetPointer(g_mtf),
                         InpEmaFast, InpEmaSlow, InpAtrPeriod,
                         InpRsiPeriod, InpRsiOverbought, InpRsiOversold,
                         InpBandsPeriod, InpBandsDeviation, InpMinConfidence))
      return INIT_FAILED;

   if(!g_ooda.Init(_Symbol, GetPointer(g_regime), GetPointer(g_confluence),
                   InpGodMode, InpMinConfidence,
                   InpGodMinConfidence, InpGodMaxConfidence, InpGodRiskBoostMax))
      return INIT_FAILED;

   g_risk.Init(_Symbol, InpRiskPercent, InpMaxRiskPercent);
   g_safety.Init(_Symbol, InpMaxDailyLossPercent, InpMaxDrawdownPercent,
                 InpMaxConsecutiveLoss, InpMaxSpreadPoints);
   g_trades.Init(_Symbol, InpMagicNumber, InpSlippagePoints,
                 InpBreakevenAtrMult, InpPartialCloseAtrMult, InpPartialClosePercent);
   g_trades.SetTrailing(InpGodMode, InpTrailAtrMult);
   g_perf.Reset();

   Print("V75EA v3 initialized on ", _Symbol,
         " setup TF=", EnumToString(InpTimeframe),
         " godMode=", (InpGodMode ? "ON" : "OFF"));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_perf.PrintSummary();
   g_regime.Deinit();
   g_momentum.Deinit();
   g_trend.Deinit();
   g_mtf.Deinit();
   g_confluence.Deinit();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   g_safety.OnNewTick();
   g_perf.UpdateDrawdown();

   //--- OBSERVE
   SObservation obs;
   if(!g_ooda.Observe(obs))
      return;

   //--- ACT (management): breakeven / partial / trailing on every tick
   g_trades.ManageOpenPositions(obs.atr);

   bool newBar = IsNewBar();
   if(InpTradeOnNewBarOnly && !newBar)
      return;
   if(newBar)
      g_structure.Update();

   if(!g_safety.IsTradingAllowed())
      return;

   int maxPositions = MathMax(1, InpMaxPositions);
   int openCount    = g_trades.CountOpenPositions();
   if(openCount >= maxPositions)
      return;

   //--- ORIENT + DECIDE
   SDecision decision;
   if(!g_ooda.Decide(obs, decision, InpAtrStopMultiplier, InpAtrTakeProfitMult, InpRiskPercent))
      return;

   //--- pyramiding: additional entries only in the direction of existing exposure
   if(openCount > 0)
     {
      int haveDir = g_trades.OpenDirection();
      int wantDir = (decision.signal == SIGNAL_BUY) ? 1 : -1;
      if(haveDir == 0 || haveDir != wantDir)
         return;
     }

   //--- ACT (entry)
   g_risk.SetRiskPercent(decision.riskPercent); // hard-capped inside RiskManager
   double lots = g_risk.CalculateLotSize(decision.slDistance);

   if(g_trades.OpenTrade(decision.signal, lots, decision.slDistance, decision.tpDistance))
     {
      g_regimeAtEntry = obs.regime;
      PrintFormat("V75EA entry: %s lots=%.2f conf=%.2f | %s",
                  (decision.signal == SIGNAL_BUY ? "BUY" : "SELL"),
                  lots, decision.confidence, decision.reason);
     }
  }

//+------------------------------------------------------------------+
//| FEEDBACK: realized results close the OODA loop and feed the      |
//| safety and performance modules                                   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
     {
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      bool win = (profit >= 0.0);
      g_safety.RegisterTradeResult(win);
      g_ooda.RegisterTradeResult(win);
      g_perf.RecordClosedTrade(profit, g_regimeAtEntry);
     }
  }

//+------------------------------------------------------------------+
bool IsNewBar(void)
  {
   datetime t = iTime(_Symbol, InpTimeframe, 0);
   if(t != g_lastBarTime)
     {
      g_lastBarTime = t;
      return true;
     }
   return false;
  }
