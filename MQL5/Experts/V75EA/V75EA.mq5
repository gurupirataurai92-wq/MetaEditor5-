//+------------------------------------------------------------------+
//|                                                        V75EA.mq5 |
//|  Confluence-based EA for Deriv Volatility 75 Index.             |
//|                                                                  |
//|  Pipeline per bar:                                               |
//|    RegimeDetector  -> what kind of market are we in?             |
//|    MultiTimeframe  -> higher-timeframe directional bias          |
//|    MarketStructure -> HH/HL vs LH/LL, BOS / CHoCH, S&R           |
//|    TrendStrength   -> is the trend worth trading?                |
//|    MomentumEngine  -> is price action confirming?                |
//|    ConfluenceEngine-> scores the above into one decision         |
//|    RiskManager     -> ATR/%-equity position sizing               |
//|    SafetyGuard     -> daily loss, drawdown, streak, spread caps  |
//|    TradeManager    -> execution, breakeven, partial close        |
//|    PerformanceTracker -> realized stats, incl. per-regime        |
//|                                                                  |
//|  ML (blueprint item 12) is intentionally out of scope for this  |
//|  baseline; the confluence score is the extension point for it.   |
//+------------------------------------------------------------------+
#property copyright "V75EA"
#property version   "2.00"
#property strict

#include <V75EA\Types.mqh>
#include <V75EA\RegimeDetector.mqh>
#include <V75EA\MarketStructure.mqh>
#include <V75EA\MomentumEngine.mqh>
#include <V75EA\TrendStrength.mqh>
#include <V75EA\MultiTimeframe.mqh>
#include <V75EA\ConfluenceEngine.mqh>
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
input int    InpMomentumMaxRun      = 5;
input double InpAdxNormalizer       = 50.0;
input int    InpSlopeLookback       = 5;

//--- Confluence
input double InpMinConfidence       = 0.60;  // 0..1; higher => fewer, higher-quality trades

//--- Risk management
input double InpRiskPercent         = 1.0;   // base risk per trade, % equity
input double InpMaxRiskPercent      = 2.0;   // hard cap
input bool   InpScaleRiskByConf     = true;  // scale risk with confidence
input double InpAtrStopMultiplier   = 1.5;
input double InpAtrTakeProfitMult   = 3.0;

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
CRiskManager        g_risk;
CSafetyGuard        g_safety;
CTradeManager       g_trades;
CPerformanceTracker g_perf;

datetime    g_lastBarTime = 0;
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

   g_risk.Init(_Symbol, InpRiskPercent, InpMaxRiskPercent);
   g_safety.Init(_Symbol, InpMaxDailyLossPercent, InpMaxDrawdownPercent,
                 InpMaxConsecutiveLoss, InpMaxSpreadPoints);
   g_trades.Init(_Symbol, InpMagicNumber, InpSlippagePoints,
                 InpBreakevenAtrMult, InpPartialCloseAtrMult, InpPartialClosePercent);
   g_perf.Reset();

   Print("V75EA v2 initialized on ", _Symbol, " setup TF=", EnumToString(InpTimeframe));
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

   double atr = g_confluence.GetAtr();
   if(atr <= 0.0)
      return;

   //--- manage open positions on every tick (fast reaction on V75)
   g_trades.ManageOpenPositions(atr);

   //--- heavier analysis only once per new bar unless configured otherwise
   bool newBar = IsNewBar();
   if(InpTradeOnNewBarOnly && !newBar)
      return;

   if(newBar)
      g_structure.Update();

   if(!g_safety.IsTradingAllowed())
      return;

   if(g_trades.HasOpenPosition())
      return;

   SConfluenceResult decision = g_confluence.Evaluate();
   if(decision.signal == SIGNAL_NONE)
      return;

   double slDistance = decision.atr * InpAtrStopMultiplier;
   double tpDistance = decision.atr * InpAtrTakeProfitMult;

   //--- optionally scale risk by confidence (0.5x at threshold -> 1x at full confidence)
   double effRisk = InpRiskPercent;
   if(InpScaleRiskByConf)
      effRisk = InpRiskPercent * (0.5 + 0.5 * decision.confidence);
   g_risk.Init(_Symbol, effRisk, InpMaxRiskPercent);

   double lots = g_risk.CalculateLotSize(slDistance);

   if(g_trades.OpenTrade(decision.signal, lots, slDistance, tpDistance))
     {
      g_regimeAtEntry = g_regime.Classify();
      PrintFormat("V75EA entry: %s lots=%.2f conf=%.2f | %s",
                  (decision.signal == SIGNAL_BUY ? "BUY" : "SELL"),
                  lots, decision.confidence, decision.reason);
     }
  }

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
      g_safety.RegisterTradeResult(profit >= 0.0);
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
