//+------------------------------------------------------------------+
//|                                                        V75EA.mq5 |
//|  Confluence + OODA EA for Deriv Volatility 75, v4.00.           |
//|                                                                  |
//|  Grounded in the V75 arithmetic (driftless GBM, constant 75%     |
//|  annual vol): VolatilityMath supplies theoretical per-bar sigma, |
//|  realized/theoretical vol ratio (the exploitable clustering      |
//|  signal), first-passage touch probabilities, and sigma-scaled    |
//|  stops so risk is constant in probability terms.                 |
//|                                                                  |
//|  "Godmode"-style traits (as seen on commercial synthetic-index   |
//|  EAs): on-chart dashboard + PAUSE / CLOSE-ALL buttons, bounded    |
//|  loss recovery (opt-in), session filter, daily profit target,    |
//|  push notifications — all under the same hard risk rails.        |
//+------------------------------------------------------------------+
#property copyright "V75EA"
#property version   "5.00"
#property strict

#include <V75EA\Types.mqh>
#include <V75EA\VolatilityMath.mqh>
#include <V75EA\EdgeModel.mqh>
#include <V75EA\RegimeDetector.mqh>
#include <V75EA\MarketStructure.mqh>
#include <V75EA\MomentumEngine.mqh>
#include <V75EA\TrendStrength.mqh>
#include <V75EA\MultiTimeframe.mqh>
#include <V75EA\ConfluenceEngine.mqh>
#include <V75EA\OodaEngine.mqh>
#include <V75EA\RiskManager.mqh>
#include <V75EA\SafetyGuard.mqh>
#include <V75EA\RecoveryManager.mqh>
#include <V75EA\Dashboard.mqh>
#include <V75EA\TradeManager.mqh>
#include <V75EA\PerformanceTracker.mqh>

enum ENUM_STOP_MODE
  {
   STOP_ATR   = 0,   // stop distance from ATR (adaptive to realized range)
   STOP_SIGMA = 1    // stop distance from theoretical V75 sigma (constant probability)
  };

//--- General
input ulong           InpMagicNumber       = 750001;
input ENUM_TIMEFRAMES InpTimeframe         = PERIOD_M5;
input ENUM_TIMEFRAMES InpHtf1              = PERIOD_M15;
input ENUM_TIMEFRAMES InpHtf2              = PERIOD_H1;
input bool            InpTradeOnNewBarOnly = true;

//--- V75 arithmetic
input double          InpAnnualVolPercent  = 75.0;   // 75 for V75; set to match the instrument
input ENUM_STOP_MODE  InpStopMode          = STOP_ATR;
input int             InpSigmaHorizonBars  = 10;     // horizon for sigma stop / touch probability
input double          InpSigmaStopK        = 1.0;    // stop at k theoretical sigmas
input int             InpRealizedVolBars   = 30;     // window for realized-vol estimate
input double          InpMinVolRatio       = 0.60;   // skip dead markets (realized << theoretical)

//--- Edge model (expected-value gate)
input bool            InpUseEvGate         = true;   // only trade measured positive EV after spread
input int             InpEdgeLookback      = 100;    // bars for drift/persistence estimation
input double          InpDriftTStat        = 2.0;    // t-stat needed before drift is credited
input double          InpMinEvR            = 0.05;   // minimum expected value in R to trade

//--- Indicator periods
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
input double InpAtrExpansionRatio  = 1.5;
input double InpBbCompressionRatio = 0.7;
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
input double InpMinConfidence      = 0.60;

//--- God mode (adaptive OODA)
input bool   InpGodMode            = true;
input double InpGodMinConfidence   = 0.50;
input double InpGodMaxConfidence   = 0.75;
input double InpGodRiskBoostMax    = 1.5;
input int    InpMaxPositions       = 3;
input double InpTrailAtrMult       = 2.0;

//--- Bounded recovery (Godmode trait) — OFF by default
input bool   InpUseRecovery        = false;
input int    InpRecoveryMaxSteps   = 3;
input double InpRecoveryStepFactor = 1.5;
input double InpRecoveryMaxMult    = 3.0;
input double InpRecoveryEquityFloorPct = 80.0;   // recovery disabled below this % of start equity

//--- Session filter + daily profit target
input bool   InpUseSession         = false;
input int    InpSessionStartHour   = 6;    // server time
input int    InpSessionEndHour     = 22;
input double InpDailyProfitTarget  = 0.0;  // % of day-start equity; 0 disables

//--- Risk management
input double InpRiskPercent        = 1.0;
input double InpMaxRiskPercent     = 2.0;   // hard ceiling; recovery/OODA cannot exceed it
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

//--- UX
input bool   InpShowDashboard       = true;
input bool   InpUseNotifications    = false;  // requires MetaQuotes ID in MT5 settings

CVolatilityMath     g_vol;
CEdgeModel          g_edge;
CRegimeDetector     g_regime;
CMarketStructure    g_structure;
CMomentumEngine     g_momentum;
CTrendStrength      g_trend;
CMultiTimeframe     g_mtf;
CConfluenceEngine   g_confluence;
COodaEngine         g_ooda;
CRiskManager        g_risk;
CSafetyGuard        g_safety;
CRecoveryManager    g_recovery;
CDashboard          g_dashboard;
CTradeManager       g_trades;
CPerformanceTracker g_perf;

datetime    g_lastBarTime   = 0;
ENUM_REGIME g_regimeAtEntry = REGIME_RANGE;
bool        g_paused        = false;
double      g_lastConfidence = 0.0;
double      g_lastEvR        = 0.0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_vol.Init(_Symbol, InpTimeframe, InpAnnualVolPercent);
   g_edge.Init(_Symbol, InpTimeframe, InpEdgeLookback, InpDriftTStat);

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
                 InpMaxConsecutiveLoss, InpMaxSpreadPoints,
                 InpUseSession, InpSessionStartHour, InpSessionEndHour, InpDailyProfitTarget);
   g_recovery.Init(InpUseRecovery, InpRecoveryMaxSteps, InpRecoveryStepFactor,
                   InpRecoveryMaxMult, InpRecoveryEquityFloorPct);
   g_trades.Init(_Symbol, InpMagicNumber, InpSlippagePoints,
                 InpBreakevenAtrMult, InpPartialCloseAtrMult, InpPartialClosePercent);
   g_trades.SetTrailing(InpGodMode, InpTrailAtrMult);
   g_dashboard.Init("v75ea_", InpShowDashboard);
   g_perf.Reset();

   Print("V75EA v4 on ", _Symbol, " TF=", EnumToString(InpTimeframe),
         " godMode=", (InpGodMode ? "ON" : "OFF"),
         " recovery=", (InpUseRecovery ? "ON" : "OFF"),
         " stopMode=", (InpStopMode == STOP_SIGMA ? "SIGMA" : "ATR"));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_perf.PrintSummary();
   g_dashboard.Deinit();
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

   //--- ACT (management): breakeven / partial / trailing every tick
   g_trades.ManageOpenPositions(obs.atr);

   //--- daily profit target: flatten and lock in
   if(g_safety.DailyProfitReached() && g_trades.HasOpenPosition())
     {
      g_trades.CloseAll();
      Notify("V75EA: daily profit target reached — positions closed.");
     }

   UpdateDashboard(obs);

   bool newBar = IsNewBar();
   if(InpTradeOnNewBarOnly && !newBar)
      return;
   if(newBar)
      g_structure.Update();

   if(g_paused)
      return;
   if(!g_safety.IsTradingAllowed())
      return;

   //--- arithmetic gate: skip dead markets (realized vol far below theoretical)
   double volRatio = g_vol.VolRatio(InpRealizedVolBars);
   if(volRatio < InpMinVolRatio)
      return;

   int maxPositions = MathMax(1, InpMaxPositions);
   int openCount    = g_trades.CountOpenPositions();
   if(openCount >= maxPositions)
      return;

   //--- ORIENT + DECIDE
   SDecision decision;
   if(!g_ooda.Decide(obs, decision, InpAtrStopMultiplier, InpAtrTakeProfitMult, InpRiskPercent))
      return;
   g_lastConfidence = decision.confidence;

   //--- pyramiding: only add in the direction of existing exposure
   if(openCount > 0)
     {
      int haveDir = g_trades.OpenDirection();
      int wantDir = (decision.signal == SIGNAL_BUY) ? 1 : -1;
      if(haveDir == 0 || haveDir != wantDir)
         return;
     }

   //--- stop/target distances: ATR (from OODA) or theoretical sigma
   double slDistance = decision.slDistance;
   double tpDistance = decision.tpDistance;
   if(InpStopMode == STOP_SIGMA)
     {
      slDistance = g_vol.SigmaStopDistance(InpSigmaHorizonBars, InpSigmaStopK);
      double rr  = (InpAtrStopMultiplier > 0.0) ? (InpAtrTakeProfitMult / InpAtrStopMultiplier) : 2.0;
      tpDistance = slDistance * rr;
     }

   //--- ARITHMETIC GATE: measured expected value in R, net of spread.
   //    Driftless GBM gives EV = -spread for ANY geometry; this only passes when
   //    the live series shows statistically real drift in the trade's direction.
   int    dir         = (decision.signal == SIGNAL_BUY) ? 1 : -1;
   double spreadPrice = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)
                        * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double evR = g_edge.ExpectedValueR(dir, slDistance, tpDistance, spreadPrice);
   g_lastEvR  = evR;
   if(InpUseEvGate && evR < InpMinEvR)
     {
      static datetime lastEvLog = 0;
      if(TimeCurrent() - lastEvLog > 300) // log at most every 5 minutes
        {
         PrintFormat("V75EA: EV gate blocked %s (EV=%.3fR < %.2fR) — no measurable edge after spread.",
                     (dir == 1 ? "BUY" : "SELL"), evR, InpMinEvR);
         lastEvLog = TimeCurrent();
        }
      return;
     }

   //--- risk request = base * OODA multiplier * recovery multiplier (all hard-capped)
   double effRisk = decision.riskPercent * g_recovery.Multiplier();
   g_risk.SetRiskPercent(effRisk);
   double lots = g_risk.CalculateLotSize(slDistance);

   if(g_trades.OpenTrade(decision.signal, lots, slDistance, tpDistance))
     {
      g_regimeAtEntry = obs.regime;
      double tstat = 0.0, ac1 = 0.0, vr = 1.0;
      g_edge.Diagnostics(tstat, ac1, vr, 5);
      string msg = StringFormat("V75EA %s lots=%.2f conf=%.2f volR=%.2f EV=%.3fR t=%.2f ac1=%.2f VR5=%.2f | %s",
                                (decision.signal == SIGNAL_BUY ? "BUY" : "SELL"),
                                lots, decision.confidence, volRatio, evR, tstat, ac1, vr, decision.reason);
      Print(msg);
      Notify(msg);
     }
  }

//+------------------------------------------------------------------+
//| Dashboard button clicks                                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   ENUM_PANEL_ACTION action = g_dashboard.HandleEvent(id, lparam, dparam, sparam);
   if(action == PANEL_TOGGLE_PAUSE)
     {
      g_paused = !g_paused;
      Print("V75EA: ", (g_paused ? "PAUSED by user." : "RESUMED by user."));
     }
   else if(action == PANEL_CLOSE_ALL)
     {
      g_trades.CloseAll();
      Print("V75EA: CLOSE ALL by user.");
     }
  }

//+------------------------------------------------------------------+
//| FEEDBACK                                                         |
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
      g_recovery.RegisterResult(win);
      g_perf.RecordClosedTrade(profit, g_regimeAtEntry);
      Notify(StringFormat("V75EA closed: %s %.2f", (win ? "WIN" : "LOSS"), profit));
     }
  }

//+------------------------------------------------------------------+
void UpdateDashboard(const SObservation &obs)
  {
   if(!InpShowDashboard)
      return;

   SDashboardState st;
   st.godMode         = InpGodMode;
   st.paused          = g_paused;
   st.regime          = RegimeName(obs.regime);
   st.confidence      = g_lastConfidence;
   st.threshold       = g_ooda.DynamicConfidence();
   st.riskMult        = g_ooda.RiskMultiplier();
   st.recoveryStep    = g_recovery.Step();
   st.volRatio        = g_vol.VolRatio(InpRealizedVolBars);
   st.openPositions   = g_trades.CountOpenPositions();
   st.dailyPnlPercent = g_safety.DailyPnlPercent();
   st.equity          = AccountInfoDouble(ACCOUNT_EQUITY);
   st.balance         = AccountInfoDouble(ACCOUNT_BALANCE);
   st.status          = g_safety.IsHalted() ? "HALTED"
                        : StringFormat("SCAN  EV %+.2fR", g_lastEvR);
   g_dashboard.Update(st);
  }

//+------------------------------------------------------------------+
void Notify(const string msg)
  {
   if(InpUseNotifications)
      SendNotification(msg);
  }

//+------------------------------------------------------------------+
string RegimeName(const ENUM_REGIME r)
  {
   switch(r)
     {
      case REGIME_STRONG_UPTREND:   return "STRONG UP";
      case REGIME_WEAK_UPTREND:     return "WEAK UP";
      case REGIME_STRONG_DOWNTREND: return "STRONG DOWN";
      case REGIME_WEAK_DOWNTREND:   return "WEAK DOWN";
      case REGIME_RANGE:            return "RANGE";
      case REGIME_BREAKOUT:         return "BREAKOUT";
      case REGIME_COMPRESSION:      return "COMPRESSION";
     }
   return "UNKNOWN";
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
