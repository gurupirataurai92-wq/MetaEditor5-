//+------------------------------------------------------------------+
//|                                                        V75EA.mq5 |
//|  Regime-switching EA (EMA-crossover trend / RSI+Bollinger mean-  |
//|  reversion) for Deriv Volatility 75 Index, with ATR-based        |
//|  position sizing and layered risk controls.                     |
//+------------------------------------------------------------------+
#property copyright "V75EA"
#property version   "1.00"
#property strict

#include <V75EA\SignalEngine.mqh>
#include <V75EA\RiskManager.mqh>
#include <V75EA\SafetyGuard.mqh>
#include <V75EA\TradeManager.mqh>

//--- General
input ulong            InpMagicNumber        = 750001;
input ENUM_TIMEFRAMES  InpTimeframe          = PERIOD_M15;

//--- Signal engine
input int    InpEmaFast              = 20;
input int    InpEmaSlow              = 50;
input int    InpAdxPeriod            = 14;
input double InpAdxTrendThreshold    = 25.0;
input int    InpRsiPeriod            = 14;
input double InpRsiOverbought        = 70.0;
input double InpRsiOversold          = 30.0;
input int    InpBandsPeriod          = 20;
input double InpBandsDeviation       = 2.0;
input int    InpAtrPeriod            = 14;

//--- Risk management
input double InpRiskPercent          = 1.0;  // risk per trade, % of equity
input double InpMaxRiskPercent       = 2.0;  // hard cap regardless of InpRiskPercent
input double InpAtrStopMultiplier    = 1.5;
input double InpAtrTakeProfitMult    = 3.0;

//--- Safety guard
input double InpMaxDailyLossPercent  = 5.0;
input double InpMaxDrawdownPercent   = 15.0;
input int    InpMaxConsecutiveLosses = 4;
input double InpMaxSpreadPoints      = 500;

//--- Trade management
input int    InpSlippagePoints       = 30;
input double InpBreakevenAtrMult     = 1.0;
input double InpPartialCloseAtrMult  = 2.0;
input double InpPartialClosePercent  = 50.0;

CSignalEngine g_signalEngine;
CRiskManager  g_riskManager;
CSafetyGuard  g_safetyGuard;
CTradeManager g_tradeManager;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_signalEngine.Init(_Symbol, InpTimeframe,
                            InpEmaFast, InpEmaSlow, InpAdxPeriod, InpAdxTrendThreshold,
                            InpRsiPeriod, InpRsiOverbought, InpRsiOversold,
                            InpBandsPeriod, InpBandsDeviation, InpAtrPeriod))
     {
      Print("V75EA: signal engine init failed");
      return INIT_FAILED;
     }

   g_riskManager.Init(_Symbol, InpRiskPercent, InpMaxRiskPercent);

   g_safetyGuard.Init(_Symbol, InpMaxDailyLossPercent, InpMaxDrawdownPercent,
                       InpMaxConsecutiveLosses, InpMaxSpreadPoints);

   g_tradeManager.Init(_Symbol, InpMagicNumber, InpSlippagePoints,
                        InpBreakevenAtrMult, InpPartialCloseAtrMult, InpPartialClosePercent);

   Print("V75EA initialized on ", _Symbol, " / ", EnumToString(InpTimeframe));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_signalEngine.Deinit();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   g_safetyGuard.OnNewTick();

   double atr = g_signalEngine.GetAtr();
   if(atr <= 0.0)
      return;

   //--- manage existing positions regardless of whether new trades are currently allowed
   g_tradeManager.ManageOpenPositions(atr);

   if(!g_safetyGuard.IsTradingAllowed())
      return;

   if(g_tradeManager.HasOpenPosition())
      return;

   ENUM_SIGNAL signal = g_signalEngine.GetSignal();
   if(signal == SIGNAL_NONE)
      return;

   double slDistance = atr * InpAtrStopMultiplier;
   double tpDistance = atr * InpAtrTakeProfitMult;
   double lots       = g_riskManager.CalculateLotSize(slDistance);

   g_tradeManager.OpenTrade(signal, lots, slDistance, tpDistance);
  }

//+------------------------------------------------------------------+
//| Feed closed-trade results into the safety guard's consecutive-   |
//| loss counter                                                     |
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
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      g_safetyGuard.RegisterTradeResult(profit >= 0.0);
     }
  }
