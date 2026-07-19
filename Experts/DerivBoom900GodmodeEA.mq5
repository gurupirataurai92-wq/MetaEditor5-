//+------------------------------------------------------------------+
//|                                   DerivBoom900GodmodeEA.mq5      |
//|            "Godmode" spike-aware short-the-drift system          |
//|                     for the Deriv Boom 900 Index                 |
//+------------------------------------------------------------------+
#property copyright "Quant Systems"
#property version   "1.00"
#property description "Godmode EA for Deriv's Boom 900 synthetic index. "
#property description "Boom indices grind lower between rare, very large "
#property description "upward spikes. This EA sells the drift with an "
#property description "EMA/candle trend filter, detects spikes from raw "
#property description "tick deltas to pause entries and trigger emergency "
#property description "exits, trails profit as price drifts down, and "
#property description "runs a tiered fixed-fractional risk engine sized "
#property description "for very small accounts. No martingale/grid - lot "
#property description "size never increases after a loss."

#include <Trade\Trade.mqh>

//======================================================================
// INPUT PARAMETERS
//======================================================================
input string InpSymbol              = "Boom 900 Index"; // exact name varies by broker; auto-detected if not found
input long   MagicNumber            = 90020260719;

// --- Risk / account tiering (fixed-fractional only, no martingale) ---
input double RiskPercent            = 1.0;    // % equity risked per trade (fallback / base tier)
input double MinAccountUSD          = 2.0;    // below this effective balance, EA stays flat
input double MaxAccountDrawdownPct  = 15.0;   // peak-to-equity DD -> hard halt, manual restart required
input double MaxDailyDrawdownPct    = 8.0;    // balance DD since day-open -> entries blocked until next day
input int    MaxConsecutiveLosses   = 4;      // trips a cooldown, does not change lot size
input int    LossCooldownMinutes    = 60;

// --- Spike detection (Boom spikes are large, sudden, one-tick upward jumps) ---
input int    SpikeLookbackTicks     = 300;    // rolling window used for the "average tick move" baseline
input double SpikeMultiplier        = 8.0;    // a tick jump beyond avg*mult is classified as a spike
input int    SpikeCooldownSeconds   = 45;     // no new entries for this long after a spike
input int    SpikeDueWarnTicks      = 650;    // heuristic caution zone as ticks-since-spike approaches ~900
input double DueWindowRiskCutFactor = 0.5;    // risk multiplier applied while inside the caution zone
input double EmergencyLossRMultiple = 2.5;    // if a spike fires while in a losing trade beyond this many R, close now

// --- Trend filter (M1) ---
input int    EmaFastPeriod          = 20;
input int    EmaSlowPeriod          = 60;
input int    TrendLookbackBars      = 5;

// --- Stops / targets / trailing (ATR-based) ---
input int    AtrPeriod              = 14;
input double SlAtrMultiplier        = 3.0;    // wide by design - spikes are large, tight stops just get chopped
input double TpAtrMultiplier        = 1.5;
input double TrailAtrMultiplier     = 1.2;
input double BreakevenTriggerR      = 0.6;    // R-multiple profit that moves SL to breakeven
input double BreakevenBufferPoints  = 5;
input int    MaxHoldMinutes         = 240;    // force-exit stagnant trades

// --- Execution filters ---
input double MaxSpreadPoints        = 300;    // synthetic-index price scale differs from FX - tune on demo first
input int    TradeDeviationPoints   = 20;

//======================================================================
// GLOBALS
//======================================================================
CTrade   trade;
string   g_symbol;
int      g_hEmaFast = INVALID_HANDLE;
int      g_hEmaSlow = INVALID_HANDLE;
int      g_hAtr     = INVALID_HANDLE;

// --- spike detection rolling buffer ---
double   g_tickBuf[];
int      g_tickBufIdx   = 0;
int      g_tickBufCount = 0;
double   g_tickBufSum   = 0.0;
double   g_lastBid      = 0.0;
bool     g_haveLastBid  = false;
datetime g_spikeCooldownUntil = 0;
int      g_ticksSinceSpike    = 0;

// --- open position tracking ---
ulong    g_posTicket      = 0;
double   g_posRiskAmt     = 0.0;
double   g_posSlDistance  = 0.0;
double   g_posEntryPrice  = 0.0;
bool     g_posBreakevenSet = false;
datetime g_posOpenTime    = 0;

// --- circuit breakers ---
int      g_consecutiveLosses  = 0;
datetime g_lossCooldownUntil  = 0;
double   g_dayStartBalance    = 0.0;
datetime g_currentDay         = 0;
double   g_peakEquity         = 0.0;
bool     g_haltedForDrawdown  = false;

//======================================================================
// Symbol auto-detection (broker naming for synthetics varies, e.g.
// "Boom 900 Index" vs "BOOM900" vs "Boom 900 Index_z")
//======================================================================
string FindBoomSymbol(string configured)
{
   if(SymbolSelect(configured, true)) return configured;

   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, false);
      bool hasBoom = (StringFind(name, "Boom") >= 0 || StringFind(name, "BOOM") >= 0);
      bool has900  = (StringFind(name, "900") >= 0);
      if(hasBoom && has900 && SymbolSelect(name, true)) return name;
   }
   return "";
}

//======================================================================
// OnInit / OnDeinit
//======================================================================
int OnInit()
{
   g_symbol = FindBoomSymbol(InpSymbol);
   if(g_symbol == "")
   {
      PrintFormat("ERROR: could not find/select a Boom 900 symbol (configured=\"%s\")", InpSymbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber((ulong)MagicNumber);
   trade.SetDeviationInPoints(TradeDeviationPoints);

   g_hEmaFast = iMA(g_symbol, PERIOD_M1, EmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hEmaSlow = iMA(g_symbol, PERIOD_M1, EmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hAtr     = iATR(g_symbol, PERIOD_M1, AtrPeriod);
   if(g_hEmaFast == INVALID_HANDLE || g_hEmaSlow == INVALID_HANDLE || g_hAtr == INVALID_HANDLE)
   {
      Print("ERROR: indicator handle creation failed");
      return INIT_FAILED;
   }

   ArrayResize(g_tickBuf, SpikeLookbackTicks);
   ArrayInitialize(g_tickBuf, 0.0);

   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peakEquity       = AccountInfoDouble(ACCOUNT_EQUITY);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   g_currentDay = StructToTime(dt);

   PrintFormat("Godmode Boom900 EA initialized on %s", g_symbol);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_hEmaFast != INVALID_HANDLE) IndicatorRelease(g_hEmaFast);
   if(g_hEmaSlow != INVALID_HANDLE) IndicatorRelease(g_hEmaSlow);
   if(g_hAtr     != INVALID_HANDLE) IndicatorRelease(g_hAtr);
}

//======================================================================
// Spike detection - rolling average of |tick delta|, spike = an upward
// jump many multiples of that average. Boom spikes are one-directional
// (up), so only upward jumps are classified as spikes.
//======================================================================
bool UpdateSpikeDetection(double bid)
{
   if(!g_haveLastBid)
   {
      g_lastBid = bid;
      g_haveLastBid = true;
      return false;
   }

   double delta    = bid - g_lastBid;
   double absDelta = MathAbs(delta);
   g_lastBid = bid;

   double avg = (g_tickBufCount > 0) ? g_tickBufSum / g_tickBufCount : 0.0;
   bool isSpike = (avg > 0.0 && g_tickBufCount >= SpikeLookbackTicks && delta > avg * SpikeMultiplier);

   g_tickBufSum -= g_tickBuf[g_tickBufIdx];
   g_tickBuf[g_tickBufIdx] = absDelta;
   g_tickBufSum += absDelta;
   g_tickBufIdx = (g_tickBufIdx + 1) % SpikeLookbackTicks;
   if(g_tickBufCount < SpikeLookbackTicks) g_tickBufCount++;

   if(isSpike)
   {
      g_spikeCooldownUntil = TimeCurrent() + SpikeCooldownSeconds;
      g_ticksSinceSpike = 0;
      PrintFormat("SPIKE detected [%s]: delta=%.5f avg=%.5f ratio=%.1fx", g_symbol, delta, avg, delta / avg);
   }
   else
   {
      g_ticksSinceSpike++;
   }
   return isSpike;
}

bool IsInSpikeCooldown() { return TimeCurrent() < g_spikeCooldownUntil; }
bool IsInDueWindow()     { return g_ticksSinceSpike >= SpikeDueWarnTicks; }

//======================================================================
// Trend filter - require EMA-fast below EMA-slow, net-down drift over
// the lookback window, and a bearish confirming M1 candle.
//======================================================================
double GetAtrValue()
{
   double buf[];
   if(CopyBuffer(g_hAtr, 0, 0, 1, buf) != 1) return 0.0;
   return buf[0];
}

bool IsDowntrendConfirmed()
{
   double fast[], slow[];
   if(CopyBuffer(g_hEmaFast, 0, 0, 1, fast) != 1) return false;
   if(CopyBuffer(g_hEmaSlow, 0, 0, 1, slow) != 1) return false;
   if(fast[0] >= slow[0]) return false;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(g_symbol, PERIOD_M1, 0, TrendLookbackBars + 1, r) < TrendLookbackBars + 1) return false;

   bool netDown    = r[1].close < r[TrendLookbackBars].close;
   bool lastBearish = r[1].close < r[1].open;
   return netDown && lastBearish;
}

//======================================================================
// Lot sizing - fixed-fractional, tiered by effective account balance.
// No martingale: lot size never scales with prior losses.
//======================================================================
double GetPointValueMoney()
{
   double tickSize  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   double point     = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(tickSize <= 0.0 || tickValue <= 0.0) return 0.0;
   return (tickValue / tickSize) * point;
}

double GetTierRiskPercent(double effBalance)
{
   // Small accounts get a lighter fraction so a single bad exit can't
   // wipe a $2-$10 balance; risk% ramps up only once there's a cushion.
   if(effBalance < MinAccountUSD) return 0.0;
   if(effBalance <= 9.99)         return MathMin(RiskPercent, 0.5);
   if(effBalance <= 49.99)        return MathMin(RiskPercent, 0.75);
   return RiskPercent;
}

double CalculateLotSize(double riskPct, double slDist, double &riskAmtOut)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt = equity * (riskPct / 100.0);
   riskAmtOut = riskAmt;

   double ptVal = GetPointValueMoney();
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(ptVal <= 0.0 || point <= 0.0 || slDist <= 0.0) return 0.0;

   double rawLot = riskAmt / (slDist / point * ptVal);

   double minLot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0.0) return 0.0;

   double finalLot = MathFloor(rawLot / lotStep) * lotStep;
   finalLot = MathMax(finalLot, minLot);
   finalLot = MathMin(finalLot, maxLot);

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginReq = 0.0;
   if(OrderCalcMargin(ORDER_TYPE_SELL, g_symbol, finalLot, SymbolInfoDouble(g_symbol, SYMBOL_BID), marginReq))
   {
      if(marginReq > freeMargin * 0.5) return 0.0; // never overcommit margin on a small account
   }

   if(finalLot < minLot) return 0.0;
   return finalLot;
}

//======================================================================
// Entry
//======================================================================
bool CanEnterNewTrade()
{
   if(g_posTicket != 0) return false;
   if(g_haltedForDrawdown) return false;
   if(TimeCurrent() < g_lossCooldownUntil) return false;
   if(IsInSpikeCooldown()) return false;
   if(g_tickBufCount < SpikeLookbackTicks) return false; // spike baseline not warmed up yet

   double spread = (double)SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPoints) return false;

   double effBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(effBalance < MinAccountUSD) return false;

   return true;
}

void TryEnter(const MqlTick &tick)
{
   if(!CanEnterNewTrade()) return;
   if(!IsDowntrendConfirmed()) return;

   double atr = GetAtrValue();
   if(atr <= 0.0) return;

   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   double minStopDist = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   double slDist = MathMax(atr * SlAtrMultiplier, minStopDist);
   double tpDist = MathMax(atr * TpAtrMultiplier, minStopDist);
   if(slDist <= 0.0) return;

   double effBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskPct = GetTierRiskPercent(effBalance);
   if(riskPct <= 0.0) return;
   if(IsInDueWindow()) riskPct *= DueWindowRiskCutFactor; // heuristic caution, not a real prediction

   double riskAmt = 0.0;
   double lot = CalculateLotSize(riskPct, slDist, riskAmt);
   if(lot <= 0.0) return;

   double price = tick.bid; // SELL executes at Bid
   double sl = price + slDist;
   double tp = price - tpDist;

   if(!trade.Sell(lot, g_symbol, price, sl, tp, "Godmode-Boom900"))
   {
      PrintFormat("WARN: sell failed [%s] retcode=%d", g_symbol, trade.ResultRetcode());
      return;
   }

   g_posTicket       = trade.ResultOrder();
   g_posRiskAmt      = riskAmt;
   g_posSlDistance   = slDist;
   g_posEntryPrice   = price;
   g_posBreakevenSet = false;
   g_posOpenTime     = TimeCurrent();

   PrintFormat("ENTRY SELL [%s] lot=%.2f price=%.5f sl=%.5f tp=%.5f atr=%.5f risk%%=%.2f",
               g_symbol, lot, price, sl, tp, atr, riskPct);
}

//======================================================================
// Position management - breakeven, ATR trailing, time-stop.
// SELL positions are triggered/closed against Ask, so trailing math
// uses tick.ask to match what the broker will actually use.
//======================================================================
void ManagePosition(const MqlTick &tick)
{
   if(g_posTicket == 0) return;
   if(!PositionSelectByTicket(g_posTicket))
   {
      g_posTicket = 0; // closed by SL/TP/manual - stats handled in OnTradeTransaction
      return;
   }

   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSl = PositionGetDouble(POSITION_SL);
   double curTp = PositionGetDouble(POSITION_TP);
   double price = tick.ask;
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);

   double profitDist = entry - price; // positive = favorable for a short
   double rMultiple = (g_posSlDistance > 0.0) ? profitDist / g_posSlDistance : 0.0;

   if(!g_posBreakevenSet && rMultiple >= BreakevenTriggerR)
   {
      double newSl = entry - BreakevenBufferPoints * point;
      if(newSl < curSl && newSl > price)
      {
         if(trade.PositionModify(g_posTicket, newSl, curTp))
         {
            g_posBreakevenSet = true;
            PrintFormat("Breakeven set [%s] sl=%.5f", g_symbol, newSl);
         }
      }
   }
   else if(g_posBreakevenSet)
   {
      double atr = GetAtrValue();
      if(atr > 0.0)
      {
         double trailDist = atr * TrailAtrMultiplier;
         double candidateSl = price + trailDist;
         if(candidateSl < curSl - point)
            trade.PositionModify(g_posTicket, candidateSl, curTp);
      }
   }

   if(MaxHoldMinutes > 0 && TimeCurrent() - g_posOpenTime > MaxHoldMinutes * 60)
   {
      trade.PositionClose(g_posTicket);
      PrintFormat("Time-stop exit [%s] after %d minutes", g_symbol, MaxHoldMinutes);
   }
}

// If a spike fires while sitting in a trade that's already deep in the
// red, don't wait for the (deliberately wide) ATR stop - cut it now.
void CheckEmergencyStopOnSpike()
{
   if(g_posTicket == 0) return;
   if(!PositionSelectByTicket(g_posTicket)) return;
   if(g_posRiskAmt <= 0.0) return;

   double profit = PositionGetDouble(POSITION_PROFIT);
   if(profit < -g_posRiskAmt * EmergencyLossRMultiple)
   {
      trade.PositionClose(g_posTicket);
      PrintFormat("EMERGENCY spike close [%s] profit=%.2f", g_symbol, profit);
   }
}

//======================================================================
// Circuit breakers
//======================================================================
void CloseAllManaged(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      trade.PositionClose(ticket);
      PrintFormat("Closed [%s] ticket=%d (%s)", g_symbol, (int)ticket, reason);
   }
   g_posTicket = 0;
}

void UpdateDayRollover()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today = StructToTime(dt);
   if(today != g_currentDay)
   {
      g_currentDay = today;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      // Daily-loss cooldown clears with the new day; account-level
      // drawdown halt is intentionally NOT auto-cleared here - that's a
      // hard stop requiring the operator to review and restart the EA.
   }
}

void UpdateAccountGuards()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_peakEquity) g_peakEquity = equity;

   double ddPct = (g_peakEquity > 0.0) ? (g_peakEquity - equity) / g_peakEquity * 100.0 : 0.0;
   if(!g_haltedForDrawdown && ddPct >= MaxAccountDrawdownPct)
   {
      g_haltedForDrawdown = true;
      CloseAllManaged("account drawdown guard");
      PrintFormat("HALT: account drawdown %.2f%% >= cap %.2f%% - manual restart required", ddPct, MaxAccountDrawdownPct);
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyDdPct = (g_dayStartBalance > 0.0) ? (g_dayStartBalance - balance) / g_dayStartBalance * 100.0 : 0.0;
   if(dailyDdPct >= MaxDailyDrawdownPct)
   {
      datetime endOfDay = g_currentDay + 86400;
      if(g_lossCooldownUntil < endOfDay) g_lossCooldownUntil = endOfDay;
   }
}

//======================================================================
// OnTradeTransaction - track realized results for the consecutive-loss
// breaker. Lot size is never changed here (no martingale).
//======================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)MagicNumber) return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                  + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                  + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(profit < 0.0)
   {
      g_consecutiveLosses++;
      if(g_consecutiveLosses >= MaxConsecutiveLosses)
      {
         g_lossCooldownUntil = TimeCurrent() + LossCooldownMinutes * 60;
         PrintFormat("Circuit breaker: %d consecutive losses -> cooldown %d min", g_consecutiveLosses, LossCooldownMinutes);
         g_consecutiveLosses = 0;
      }
   }
   else if(profit > 0.0)
   {
      g_consecutiveLosses = 0;
   }

   g_posTicket = 0;
   PrintFormat("Trade closed [%s] profit=%.2f", g_symbol, profit);
}

//======================================================================
// OnTick
//======================================================================
void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick)) return;

   UpdateDayRollover();

   bool spikeJustFired = UpdateSpikeDetection(tick.bid);
   if(spikeJustFired) CheckEmergencyStopOnSpike();

   UpdateAccountGuards();
   ManagePosition(tick);

   if(g_posTicket == 0) TryEnter(tick);
}
