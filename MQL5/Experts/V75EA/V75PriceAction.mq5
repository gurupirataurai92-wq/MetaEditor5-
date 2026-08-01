//+------------------------------------------------------------------+
//|                                                V75PriceAction.mq5 |
//|  Supply & demand + price action EA for Deriv Volatility 75.      |
//|                                                                  |
//|  NO INDICATORS. Nothing here waits on a moving average, ADX,     |
//|  RSI, Bollinger band or ATR handle. Every decision is made from  |
//|  raw OHLC: institutional supply/demand zones (impulse-base-      |
//|  impulse), live candle anatomy, and swing structure.             |
//|                                                                  |
//|  It acts ON EVERY TICK, reading the forming bar, so a rejection  |
//|  is traded while it happens instead of one bar later. It buys    |
//|  when price rejects demand or breaks up with pressure behind it, |
//|  and sells on the mirror image — the "feel" is a pressure score  |
//|  computed from body dominance, wick asymmetry and close location.|
//|                                                                  |
//|  Risk caps remain (they gate size, never entries).               |
//+------------------------------------------------------------------+
#property copyright "V75EA"
#property version   "6.00"
#property strict

#include <V75EA\Types.mqh>
#include <V75EA\PriceEngine.mqh>
#include <V75EA\SupplyDemand.mqh>
#include <V75EA\PriceActionSignals.mqh>
#include <V75EA\RiskManager.mqh>
#include <V75EA\SafetyGuard.mqh>
#include <V75EA\Dashboard.mqh>
#include <V75EA\TradeManager.mqh>
#include <V75EA\PerformanceTracker.mqh>

//--- General
input ulong           InpMagicNumber      = 750006;
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_M5;

//--- Supply & demand zone detection
input int    InpZoneLookback      = 300;   // bars scanned for zones
input int    InpMaxBaseBars       = 3;     // max candles allowed in a base
input double InpImpulseFactor     = 1.2;   // leg body >= factor x avg range
input double InpBaseFactor        = 0.45;  // base body <= factor x avg range
input int    InpMaxZoneTouches    = 2;     // zone dies after this many tests
input double InpZoneTolerance     = 0.15;  // entry tolerance, x avg range

//--- Price action triggers
input double InpWickRatio         = 0.35;  // rejection wick share of bar range
input double InpEngulfFactor      = 1.1;   // engulfing body vs previous body
input double InpMomentumFactor    = 1.0;   // burst body vs avg range
input int    InpSwingStrength     = 2;     // bars each side defining a swing
input int    InpSwingLookback     = 60;

//--- "Feel": pressure gate
input int    InpPressureBars      = 5;     // bars feeding the pressure score
input double InpMinPressure       = 0.12;  // |pressure| needed to act
input bool   InpRequirePressure   = true;  // pressure must agree with the trade

//--- Which setups may fire
input bool   InpTradeZoneReject   = true;
input bool   InpTradeEngulfing    = true;
input bool   InpTradeMomentum     = true;
input bool   InpTradeBOS          = true;
input bool   InpAggressive        = true;  // allow non-zone setups anywhere

//--- Stops / targets (raw price range, not ATR)
input int    InpRangeBars         = 20;    // bars for the average-range measure
input double InpStopRangeMult     = 1.2;   // stop distance = mult x avg range
input double InpZoneStopBuffer    = 0.30;  // extra beyond zone distal, x avg range
input double InpRewardRatio       = 2.0;   // target = RR x stop distance

//--- Trade control
input int    InpMaxPositions      = 2;
input int    InpCooldownSeconds   = 60;    // min seconds between entries
input bool   InpOnePerZone        = true;  // don't re-enter the same zone twice

//--- Risk management
input double InpRiskPercent       = 1.0;
input double InpMaxRiskPercent    = 2.0;

//--- Safety
input double InpMaxDailyLossPercent = 5.0;
input double InpMaxDrawdownPercent  = 15.0;
input int    InpMaxConsecutiveLoss  = 5;
input double InpMaxSpreadPoints     = 800;
input bool   InpUseSession          = false;
input int    InpSessionStartHour    = 0;
input int    InpSessionEndHour      = 24;
input double InpDailyProfitTarget   = 0.0;

//--- Trade management
input int    InpSlippagePoints      = 40;
input double InpBreakevenRangeMult  = 1.0;
input double InpPartialRangeMult    = 1.5;
input double InpPartialClosePercent = 50.0;
input bool   InpUseTrailing         = true;
input double InpTrailRangeMult      = 1.5;

//--- UX
input bool   InpShowDashboard       = true;
input bool   InpUseNotifications    = false;

CPriceEngine        g_px;
CSupplyDemand       g_zones;
CPriceActionSignals g_pa;
CRiskManager        g_risk;
CSafetyGuard        g_safety;
CDashboard          g_dashboard;
CTradeManager       g_trades;
CPerformanceTracker g_perf;

datetime g_lastBarTime  = 0;
datetime g_lastEntryTime = 0;
bool     g_paused        = false;
int      g_lastBucket    = 0;
double   g_lastPressure  = 0.0;
string   g_lastSetup     = "-";
double   g_usedZoneProximal[16];
int      g_usedZoneCount = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_px.Init(_Symbol, InpTimeframe);
   g_zones.Init(_Symbol, InpTimeframe, GetPointer(g_px),
                InpZoneLookback, InpMaxBaseBars, InpImpulseFactor,
                InpBaseFactor, InpMaxZoneTouches);
   g_pa.Init(GetPointer(g_px), InpWickRatio, InpEngulfFactor, InpMomentumFactor);

   g_risk.Init(_Symbol, InpRiskPercent, InpMaxRiskPercent);
   g_safety.Init(_Symbol, InpMaxDailyLossPercent, InpMaxDrawdownPercent,
                 InpMaxConsecutiveLoss, InpMaxSpreadPoints,
                 InpUseSession, InpSessionStartHour, InpSessionEndHour, InpDailyProfitTarget);
   g_trades.Init(_Symbol, InpMagicNumber, InpSlippagePoints,
                 InpBreakevenRangeMult, InpPartialRangeMult, InpPartialClosePercent);
   g_trades.SetTrailing(InpUseTrailing, InpTrailRangeMult);
   g_dashboard.Init("v75pa_", InpShowDashboard);
   g_perf.Reset();

   g_zones.Rebuild();

   Print("V75 PriceAction EA v6 on ", _Symbol, " TF=", EnumToString(InpTimeframe),
         " | zones=", g_zones.Count(), " | NO INDICATORS");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_perf.PrintSummary();
   g_dashboard.Deinit();
  }

//+------------------------------------------------------------------+
//| Every tick: manage, then look for a reason to act immediately.   |
//+------------------------------------------------------------------+
void OnTick()
  {
   g_safety.OnNewTick();
   g_perf.UpdateDrawdown();

   double avgRange = g_px.AvgRange(InpRangeBars, 1);
   if(avgRange <= 0.0)
      return;

   //--- manage open trades on every tick (breakeven / partial / trail)
   g_trades.ManageOpenPositions(avgRange);

   //--- lock in the day if the profit target is reached
   if(g_safety.DailyProfitReached() && g_trades.HasOpenPosition())
     {
      g_trades.CloseAll();
      Notify("V75PA: daily profit target reached — flat.");
     }

   //--- refresh the zone map once per bar (zones are structural, not tick data)
   if(IsNewBar())
     {
      g_zones.Rebuild();
      g_usedZoneCount = 0;   // zones re-derived, allow fresh entries
     }

   g_lastPressure = g_px.Pressure(InpPressureBars);
   UpdateDashboard(avgRange);

   if(g_paused)                    return;
   if(!g_safety.IsTradingAllowed()) return;
   if(g_trades.CountOpenPositions() >= MathMax(1, InpMaxPositions)) return;
   if(TimeCurrent() - g_lastEntryTime < InpCooldownSeconds) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   int    dir        = 0;          // +1 buy, -1 sell
   double stopPrice  = 0.0;        // structural stop level, if the setup defines one
   string setup      = "";
   int    bucket     = 0;

   //--- 1) ZONE REACTION — the highest-quality read: price is in a zone and
   //       has already rejected out of it on the live bar.
   if(InpTradeZoneReject && dir == 0)
     {
      int zi = g_zones.ZoneAtPrice(bid, avgRange * InpZoneTolerance);
      if(zi >= 0)
        {
         SZone z = g_zones.Get(zi);
         if(z.active && !ZoneAlreadyUsed(z.proximal) && g_pa.ZoneRejection(z, bid, ask))
           {
            dir       = z.isDemand ? 1 : -1;
            stopPrice = z.isDemand ? (z.distal - avgRange * InpZoneStopBuffer)
                                   : (z.distal + avgRange * InpZoneStopBuffer);
            setup     = z.isDemand ? "DEMAND REJECT" : "SUPPLY REJECT";
            bucket    = z.isDemand ? 1 : 2;
            g_zones.RegisterTouch(zi);
            MarkZoneUsed(z.proximal);
           }
        }
     }

   //--- 2) ENGULFING — decisive reversal candle just completed
   if(InpTradeEngulfing && dir == 0 && InpAggressive)
     {
      int e = g_pa.Engulfing();
      if(e != 0)
        {
         dir    = e;
         setup  = (e > 0) ? "BULL ENGULF" : "BEAR ENGULF";
         bucket = 3;
        }
     }

   //--- 3) MOMENTUM BURST — the forming bar is running hard with intent
   if(InpTradeMomentum && dir == 0 && InpAggressive)
     {
      int m = g_pa.MomentumBurst(avgRange);
      if(m != 0)
        {
         dir    = m;
         setup  = (m > 0) ? "MOMENTUM UP" : "MOMENTUM DOWN";
         bucket = 4;
        }
     }

   //--- 4) BREAK OF STRUCTURE — price took out the last swing with follow-through
   if(InpTradeBOS && dir == 0 && InpAggressive)
     {
      int b = g_pa.BreakOfStructure(InpSwingStrength, InpSwingLookback, bid, avgRange);
      if(b != 0)
        {
         dir    = b;
         setup  = (b > 0) ? "BOS UP" : "BOS DOWN";
         bucket = 5;
        }
      }

   if(dir == 0)
      return;

   //--- "feels like buying / selling": pressure must agree with the trade
   if(InpRequirePressure)
     {
      if(MathAbs(g_lastPressure) < InpMinPressure) return;
      if((g_lastPressure > 0.0 ? 1 : -1) != dir)   return;
     }

   //--- structural stop where the setup gives one, otherwise range-based
   double slDistance;
   if(stopPrice > 0.0)
     {
      slDistance = MathAbs(bid - stopPrice);
      double minStop = avgRange * 0.5;
      if(slDistance < minStop) slDistance = minStop;
     }
   else
      slDistance = avgRange * InpStopRangeMult;

   double tpDistance = slDistance * InpRewardRatio;

   g_risk.SetRiskPercent(InpRiskPercent);
   double lots = g_risk.CalculateLotSize(slDistance);

   ENUM_SIGNAL sig = (dir > 0) ? SIGNAL_BUY : SIGNAL_SELL;
   if(g_trades.OpenTrade(sig, lots, slDistance, tpDistance))
     {
      g_lastEntryTime = TimeCurrent();
      g_lastBucket    = bucket;
      g_lastSetup     = setup;
      string msg = StringFormat("V75PA %s | %s lots=%.2f SL=%.1f TP=%.1f pressure=%+.2f zones=%d",
                                (dir > 0 ? "BUY" : "SELL"), setup, lots,
                                slDistance, tpDistance, g_lastPressure, g_zones.Count());
      Print(msg);
      Notify(msg);
     }
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   ENUM_PANEL_ACTION action = g_dashboard.HandleEvent(id, lparam, dparam, sparam);
   if(action == PANEL_TOGGLE_PAUSE)
     {
      g_paused = !g_paused;
      Print("V75PA: ", (g_paused ? "PAUSED" : "RESUMED"), " by user.");
     }
   else if(action == PANEL_CLOSE_ALL)
     {
      g_trades.CloseAll();
      Print("V75PA: CLOSE ALL by user.");
     }
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal))           return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
     {
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      bool win = (profit >= 0.0);
      g_safety.RegisterTradeResult(win);
      g_perf.RecordClosedTrade(profit, g_lastBucket);
     }
  }

//+------------------------------------------------------------------+
void UpdateDashboard(const double avgRange)
  {
   if(!InpShowDashboard) return;

   SDashboardState st;
   st.godMode         = InpAggressive;
   st.paused          = g_paused;
   st.regime          = g_lastSetup;
   st.confidence      = MathAbs(g_lastPressure);
   st.threshold       = InpMinPressure;
   st.riskMult        = 1.0;
   st.recoveryStep    = 0;
   st.volRatio        = (double)g_zones.Count();
   st.openPositions   = g_trades.CountOpenPositions();
   st.dailyPnlPercent = g_safety.DailyPnlPercent();
   st.equity          = AccountInfoDouble(ACCOUNT_EQUITY);
   st.balance         = AccountInfoDouble(ACCOUNT_BALANCE);
   st.status          = g_safety.IsHalted()
                        ? "HALTED"
                        : StringFormat("LIVE  P%+.2f", g_lastPressure);
   g_dashboard.Update(st);
  }

//+------------------------------------------------------------------+
bool ZoneAlreadyUsed(const double proximal)
  {
   if(!InpOnePerZone) return false;
   for(int i = 0; i < g_usedZoneCount; i++)
      if(MathAbs(g_usedZoneProximal[i] - proximal) < _Point)
         return true;
   return false;
  }

void MarkZoneUsed(const double proximal)
  {
   if(g_usedZoneCount < 16)
     {
      g_usedZoneProximal[g_usedZoneCount] = proximal;
      g_usedZoneCount++;
     }
  }

//+------------------------------------------------------------------+
void Notify(const string msg)
  {
   if(InpUseNotifications) SendNotification(msg);
  }

//+------------------------------------------------------------------+
bool IsNewBar(void)
  {
   datetime t = iTime(_Symbol, InpTimeframe, 0);
   if(t != g_lastBarTime) { g_lastBarTime = t; return true; }
   return false;
  }
