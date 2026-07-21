//+------------------------------------------------------------------+
//|                                   DerivBoom900GodmodeEA.mq5      |
//|      "Godmode" v2 — index-arithmetic EV engine for Deriv         |
//|      Boom 900 with GainX-style drift logic and FlipX-style       |
//|      regime-flip handling. Runs on Boom/Crash/GainX/PainX/FlipX. |
//+------------------------------------------------------------------+
#property copyright "Quant Systems"
#property version   "2.00"
#property description "Statistical EA built on the arithmetic of spike-type "
#property description "synthetic indices. Boom N produces ~1 adverse spike "
#property description "per N ticks (memoryless), with per-tick drift d and "
#property description "spike size S constructed so p*S ~= |d| (martingale "
#property description "identity S ~= |d|*N). The EA measures p, d and S "
#property description "live, solves for the hold length that maximizes "
#property description "expected value after spread, and only trades while "
#property description "that EV is positive - otherwise it stands down. "
#property description "Direction is auto-detected from drift sign (GainX "
#property description "trait) and a short-window flip detector exits or "
#property description "reverses on regime change (FlipX trait). Fixed- "
#property description "fractional risk only; no martingale, no grid. "
#property description "NOTE: these indices are RNG-generated; no EA can "
#property description "guarantee profits - this one trades the math and "
#property description "refuses to trade when the math says the edge is gone."

#include <Trade\Trade.mqh>

//======================================================================
// INPUT PARAMETERS
//======================================================================
input string InpSymbol              = "Boom 900 Index"; // broker naming varies; auto-detected/fallback to chart symbol
input long   MagicNumber            = 90020260721;

// --- Index arithmetic ---
input int    SpikeEveryNTicks       = 900;    // the N of the index: Boom 900 -> 900, Boom 500 -> 500, etc.
input int    StatWindowTicks        = 3000;   // rolling tick window for measuring p, d, S
input double SpikeMultiplier        = 6.0;    // |tick delta| beyond avg*mult is classified as a spike
input int    EvRecalcTicks          = 250;    // re-solve the EV plan every this many ticks
input double MinEdgePriceUnits      = 0.0;    // extra EV hurdle (price units) on top of EV > 0
input double MinDriftShare          = 0.10;   // |drift| must be at least this fraction of avg |tick| to trade

// --- FlipX-style regime detection ---
input int    FlipWindowTicks        = 150;    // short window for regime drift
input double FlipConfirmFactor      = 0.60;   // short drift must oppose position by this fraction of |d|
input bool   AllowReverseOnFlip     = true;   // after a flip exit, allow immediate entry the other way

// --- Spike handling ---
input int    SpikeCooldownSeconds   = 30;     // no new entries for this long after any spike
input double SlSpikeFactor          = 1.25;   // SL distance = measured spike size * this factor
input double TrailSpikeFactor       = 1.00;   // trail distance = spike size * this (tighter is pointless: spikes gap through)

// --- Risk / account tiering (fixed-fractional only, no martingale) ---
input double RiskPercent            = 1.0;    // % equity risked per trade (base tier)
input double MinAccountUSD          = 2.0;    // below this balance, EA stays flat
input double MaxAccountDrawdownPct  = 15.0;   // peak-to-equity DD -> hard halt, manual restart required
input double MaxDailyDrawdownPct    = 8.0;    // balance DD since day-open -> entries blocked until next day
input int    MaxConsecutiveLosses   = 4;      // trips a cooldown, never changes lot size
input int    LossCooldownMinutes    = 60;

// --- Exits / execution ---
input double BreakevenTriggerR      = 0.6;    // R-multiple profit that moves SL to breakeven
input double BreakevenBufferPoints  = 5;
input double TimeStopPlanFactor     = 1.5;    // force-exit after planTicks * factor ticks in trade
input double MaxSpreadPoints        = 300;    // tune on demo; synthetic price scales differ per index
input int    TradeDeviationPoints   = 20;

//======================================================================
// NAMED CONSTANTS
//======================================================================
#define WARMUP_FRACTION        0.5    // fraction of StatWindowTicks required before trading
#define MIN_TICKS_FOR_SPIKES   200    // don't classify spikes until baseline has this many ticks
#define EV_SEARCH_STEP         10     // hold-length search granularity (ticks)
#define EV_SEARCH_MAX_MULT     3      // search hold lengths up to N * this
#define DIR_WEIGHT_SHORT       0.65   // direction blend: weight on short-window drift (FlipX responsiveness)
#define DIR_WEIGHT_LONG        0.35   // direction blend: weight on long-window drift (stability)
#define STATS_PRINT_TICKS      1000   // telemetry print interval

//======================================================================
// GLOBALS
//======================================================================
CTrade   trade;
string   g_symbol;

// --- rolling tick-delta window (signed deltas + spike flags) ---
double   g_deltaBuf[];
int      g_spikeFlagBuf[];
int      g_head       = 0;
int      g_count      = 0;
double   g_sumSigned  = 0.0;   // sum of non-spike signed deltas
double   g_sumAbs     = 0.0;   // sum of non-spike |deltas|
int      g_nonSpikeCt = 0;
int      g_spikeCt    = 0;
double   g_sumSpikeMag = 0.0;

// --- short (flip) window: non-spike signed deltas only ---
double   g_flipBuf[];
int      g_flipHead  = 0;
int      g_flipCount = 0;
double   g_flipSum   = 0.0;

// --- measured statistics (refreshed by RecomputePlan) ---
double   g_p       = 0.0;   // per-tick spike probability (Laplace-blended with the 1/N prior)
double   g_drift   = 0.0;   // signed drift per tick (negative on Boom/PainX, positive on Crash/GainX)
double   g_spikeSz = 0.0;   // avg spike magnitude (prior: |d| * N, the martingale identity)

// --- EV plan ---
int      g_planTicks = 0;    // EV-optimal hold length in ticks
double   g_planEV    = -1.0; // expected value (price units) of that plan; <= 0 -> stand down
double   g_tpDist    = 0.0;  // planTicks * |drift|

int      g_ticksSinceRecalc = 0;
int      g_ticksSinceStats  = 0;

double   g_lastBid     = 0.0;
bool     g_haveLastBid = false;
datetime g_spikeCooldownUntil = 0;

// --- open position tracking ---
ulong    g_posTicket       = 0;
int      g_posDir          = 0;     // +1 long, -1 short
double   g_posRiskAmt      = 0.0;
double   g_posSlDistance   = 0.0;
double   g_posEntryPrice   = 0.0;
bool     g_posBreakevenSet = false;
long     g_posTicksHeld    = 0;

// --- circuit breakers ---
int      g_consecutiveLosses = 0;
datetime g_lossCooldownUntil = 0;
double   g_dayStartBalance   = 0.0;
datetime g_currentDay        = 0;
double   g_peakEquity        = 0.0;
bool     g_haltedForDrawdown = false;

//======================================================================
// Symbol resolution - broker naming for synthetics varies
//======================================================================
string ResolveSymbol(string configured)
{
   if(configured != "" && SymbolSelect(configured, true)) return configured;

   // scan for a Boom symbol matching the configured N
   string nStr = IntegerToString(SpikeEveryNTicks);
   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, false);
      bool hasBoom = (StringFind(name, "Boom") >= 0 || StringFind(name, "BOOM") >= 0);
      if(hasBoom && StringFind(name, nStr) >= 0 && SymbolSelect(name, true)) return name;
   }

   // fall back to the chart symbol - the stat engine is index-agnostic
   if(SymbolSelect(_Symbol, true))
   {
      PrintFormat("WARN: \"%s\" not found; running on chart symbol %s. "
                  "Set SpikeEveryNTicks to this index's N.", configured, _Symbol);
      return _Symbol;
   }
   return "";
}

string ClassifySymbolByName(string name)
{
   if(StringFind(name, "Boom")  >= 0 || StringFind(name, "BOOM")  >= 0) return "Boom (expect down-drift, up-spikes -> short bias)";
   if(StringFind(name, "Crash") >= 0 || StringFind(name, "CRASH") >= 0) return "Crash (expect up-drift, down-spikes -> long bias)";
   if(StringFind(name, "GainX") >= 0 || StringFind(name, "Gain")  >= 0) return "GainX (expect up-drift -> long bias)";
   if(StringFind(name, "PainX") >= 0 || StringFind(name, "Pain")  >= 0) return "PainX (expect down-drift -> short bias)";
   if(StringFind(name, "FlipX") >= 0 || StringFind(name, "Flip")  >= 0) return "FlipX (regime-flipping -> adaptive direction)";
   return "Unknown (direction will be measured from drift)";
}

//======================================================================
// STATISTICS ENGINE
// Every tick delta feeds the rolling window. Spikes are deltas far
// outside the non-spike baseline. The window yields:
//   p  = (spikes+1)/(ticks+N)      Laplace blend with the 1/N prior
//   d  = mean non-spike delta      the drift the index grinds at
//   S  = mean spike magnitude      prior |d|*N (martingale identity)
//======================================================================
bool FeedDelta(double delta, double &spikeSignedOut)
{
   spikeSignedOut = 0.0;
   double baseline = (g_nonSpikeCt > 0) ? g_sumAbs / g_nonSpikeCt : 0.0;
   bool isSpike = (baseline > 0.0 && g_count >= MIN_TICKS_FOR_SPIKES &&
                   MathAbs(delta) > baseline * SpikeMultiplier);

   // evict oldest entry once the ring is full
   if(g_count == StatWindowTicks)
   {
      double oldDelta = g_deltaBuf[g_head];
      if(g_spikeFlagBuf[g_head] == 1)
      {
         g_spikeCt--;
         g_sumSpikeMag -= MathAbs(oldDelta);
      }
      else
      {
         g_nonSpikeCt--;
         g_sumSigned -= oldDelta;
         g_sumAbs    -= MathAbs(oldDelta);
      }
   }
   else
      g_count++;

   g_deltaBuf[g_head]     = delta;
   g_spikeFlagBuf[g_head] = isSpike ? 1 : 0;
   g_head = (g_head + 1) % StatWindowTicks;

   if(isSpike)
   {
      g_spikeCt++;
      g_sumSpikeMag += MathAbs(delta);
      spikeSignedOut = delta;
   }
   else
   {
      g_nonSpikeCt++;
      g_sumSigned += delta;
      g_sumAbs    += MathAbs(delta);

      // short flip window takes non-spike deltas only
      if(g_flipCount == FlipWindowTicks)
         g_flipSum -= g_flipBuf[g_flipHead];
      else
         g_flipCount++;
      g_flipBuf[g_flipHead] = delta;
      g_flipSum += delta;
      g_flipHead = (g_flipHead + 1) % FlipWindowTicks;
   }

   g_ticksSinceRecalc++;
   g_ticksSinceStats++;
   return isSpike;
}

double GetLongDrift()  { return (g_nonSpikeCt > 0) ? g_sumSigned / g_nonSpikeCt : 0.0; }
double GetShortDrift() { return (g_flipCount  > 0) ? g_flipSum   / g_flipCount  : 0.0; }
double GetAvgAbsTick() { return (g_nonSpikeCt > 0) ? g_sumAbs    / g_nonSpikeCt : 0.0; }
bool   IsWarmedUp()    { return g_count >= (int)(StatWindowTicks * WARMUP_FRACTION); }

//======================================================================
// EV PLAN
// Holding a with-drift trade for n ticks, closing immediately if a
// spike fires (loss ~ S + spread), taking n*|d| - spread otherwise:
//   EV(n) = (1-p)^n * (n*|d| - spread) - (1 - (1-p)^n) * (S + spread)
// Because spikes are memoryless, n is the only free variable - solve
// for the n that maximizes EV. If even the best n is <= 0 after
// costs, there is no trade to take and the EA stands down. This is
// the entire "Godmode": trade only when the arithmetic is on-side.
//======================================================================
void RecomputePlan()
{
   g_ticksSinceRecalc = 0;
   g_planEV    = -1.0;
   g_planTicks = 0;
   g_tpDist    = 0.0;
   if(!IsWarmedUp()) return;

   int totalTicks = g_nonSpikeCt + g_spikeCt;
   g_p     = (g_spikeCt + 1.0) / (double)(totalTicks + SpikeEveryNTicks);
   g_drift = GetLongDrift();
   double absDrift = MathAbs(g_drift);
   g_spikeSz = (g_spikeCt > 0) ? g_sumSpikeMag / g_spikeCt
                                : absDrift * SpikeEveryNTicks; // S ~= |d|*N until spikes are observed

   if(absDrift <= 0.0 || g_p <= 0.0 || g_p >= 1.0) return;

   double spread = SymbolInfoDouble(g_symbol, SYMBOL_ASK) - SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double loss   = g_spikeSz + spread;
   double q      = 1.0 - g_p;

   double bestEV = -DBL_MAX;
   int    bestN  = 0;
   int    maxN   = SpikeEveryNTicks * EV_SEARCH_MAX_MULT;
   for(int n = EV_SEARCH_STEP; n <= maxN; n += EV_SEARCH_STEP)
   {
      double qn = MathPow(q, n);
      double ev = qn * (n * absDrift - spread) - (1.0 - qn) * loss;
      if(ev > bestEV) { bestEV = ev; bestN = n; }
   }

   g_planEV    = bestEV;
   g_planTicks = bestN;
   g_tpDist    = bestN * absDrift;
}

void PrintStatsIfDue()
{
   if(g_ticksSinceStats < STATS_PRINT_TICKS) return;
   g_ticksSinceStats = 0;
   if(!IsWarmedUp()) return;
   double absDrift = MathAbs(g_drift);
   double impliedN = (absDrift > 0.0) ? g_spikeSz / absDrift : 0.0;
   PrintFormat("[stats %s] p=%.5f (1 per %.0f ticks) drift/tick=%.5f spikeSize=%.5f impliedN=%.0f (config N=%d) | plan: hold=%d ticks tp=%.5f EV=%.5f %s",
               g_symbol, g_p, (g_p > 0 ? 1.0 / g_p : 0), g_drift, g_spikeSz, impliedN,
               SpikeEveryNTicks, g_planTicks, g_tpDist, g_planEV,
               (g_planEV > MinEdgePriceUnits ? "TRADEABLE" : "STAND-DOWN"));
}

//======================================================================
// DIRECTION (GainX/FlipX traits)
// Direction is never hardcoded: it is the sign of a blend of long-
// and short-window drift. Boom/PainX measure negative -> short;
// Crash/GainX measure positive -> long; FlipX flips and the short-
// weighted blend follows the new regime quickly.
//======================================================================
int GetTradeDirection()
{
   double blend = DIR_WEIGHT_SHORT * GetShortDrift() + DIR_WEIGHT_LONG * GetLongDrift();
   double avgAbs = GetAvgAbsTick();
   if(avgAbs <= 0.0) return 0;
   if(MathAbs(blend) < avgAbs * MinDriftShare) return 0; // drift too weak vs noise - no edge to ride
   return (blend > 0.0) ? 1 : -1;
}

// FlipX regime-flip: short-window drift firmly opposing the position
bool RegimeFlippedAgainst(int posDir)
{
   double shortD = GetShortDrift();
   double threshold = MathAbs(g_drift) * FlipConfirmFactor;
   if(threshold <= 0.0) return false;
   if(posDir > 0 && shortD < -threshold) return true;
   if(posDir < 0 && shortD >  threshold) return true;
   return false;
}

//======================================================================
// LOT SIZING - fixed-fractional, tiered by balance. No martingale:
// lot size never scales with prior losses.
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
   if(effBalance < MinAccountUSD) return 0.0;
   if(effBalance <= 9.99)         return MathMin(RiskPercent, 0.5);
   if(effBalance <= 49.99)        return MathMin(RiskPercent, 0.75);
   return RiskPercent;
}

double CalculateLotSize(double riskPct, double slDist, double &riskAmtOut)
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt = equity * (riskPct / 100.0);
   riskAmtOut = riskAmt;

   double ptVal = GetPointValueMoney();
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(ptVal <= 0.0 || point <= 0.0 || slDist <= 0.0) return 0.0;

   double rawLot  = riskAmt / (slDist / point * ptVal);
   double minLot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0.0) return 0.0;

   double finalLot = MathFloor(rawLot / lotStep) * lotStep;
   finalLot = MathMax(finalLot, minLot);
   finalLot = MathMin(finalLot, maxLot);

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginReq  = 0.0;
   ENUM_ORDER_TYPE ot = (g_drift > 0.0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double refPrice = (ot == ORDER_TYPE_BUY) ? SymbolInfoDouble(g_symbol, SYMBOL_ASK)
                                             : SymbolInfoDouble(g_symbol, SYMBOL_BID);
   if(OrderCalcMargin(ot, g_symbol, finalLot, refPrice, marginReq))
      if(marginReq > freeMargin * 0.5) return 0.0; // never overcommit margin on a small account

   if(finalLot < minLot) return 0.0;
   return finalLot;
}

//======================================================================
// ENTRY
//======================================================================
bool CanEnterNewTrade()
{
   if(g_posTicket != 0) return false;
   if(g_haltedForDrawdown) return false;
   if(TimeCurrent() < g_lossCooldownUntil) return false;
   if(TimeCurrent() < g_spikeCooldownUntil) return false;
   if(!IsWarmedUp()) return false;
   if(g_planEV <= MinEdgePriceUnits) return false; // the arithmetic says no edge -> stand down

   double spread = (double)SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPoints) return false;

   if(AccountInfoDouble(ACCOUNT_BALANCE) < MinAccountUSD) return false;
   return true;
}

void TryEnter(const MqlTick &tick)
{
   if(!CanEnterNewTrade()) return;

   int dir = GetTradeDirection();
   if(dir == 0) return;

   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   double minStopDist = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   // SL sits beyond one measured spike: a stop inside spike range is
   // guaranteed to be gapped through, which just converts the modeled
   // spike loss into the same loss plus slippage.
   double slDist = MathMax(g_spikeSz * SlSpikeFactor, minStopDist);
   double tpDist = MathMax(g_tpDist, minStopDist);
   if(slDist <= 0.0 || tpDist <= 0.0) return;

   double riskPct = GetTierRiskPercent(AccountInfoDouble(ACCOUNT_BALANCE));
   if(riskPct <= 0.0) return;

   double riskAmt = 0.0;
   double lot = CalculateLotSize(riskPct, slDist, riskAmt);
   if(lot <= 0.0) return;

   bool ok;
   double price;
   if(dir > 0)
   {
      price = tick.ask;
      ok = trade.Buy(lot, g_symbol, price, price - slDist, price + tpDist, "Godmode-v2");
   }
   else
   {
      price = tick.bid;
      ok = trade.Sell(lot, g_symbol, price, price + slDist, price - tpDist, "Godmode-v2");
   }

   if(!ok)
   {
      PrintFormat("WARN: order failed [%s] retcode=%d", g_symbol, trade.ResultRetcode());
      return;
   }

   g_posTicket       = trade.ResultOrder();
   g_posDir          = dir;
   g_posRiskAmt      = riskAmt;
   g_posSlDistance   = slDist;
   g_posEntryPrice   = price;
   g_posBreakevenSet = false;
   g_posTicksHeld    = 0;

   PrintFormat("ENTRY %s [%s] lot=%.2f price=%.5f slDist=%.5f tpDist=%.5f planHold=%d ticks planEV=%.5f",
               dir > 0 ? "BUY" : "SELL", g_symbol, lot, price, slDist, tpDist, g_planTicks, g_planEV);
}

//======================================================================
// POSITION MANAGEMENT
//======================================================================
void ClosePosition(string reason)
{
   if(g_posTicket == 0) return;
   if(PositionSelectByTicket(g_posTicket))
   {
      trade.PositionClose(g_posTicket);
      PrintFormat("EXIT [%s] (%s)", g_symbol, reason);
   }
   g_posTicket = 0;
}

void ManagePosition(const MqlTick &tick)
{
   if(g_posTicket == 0) return;
   if(!PositionSelectByTicket(g_posTicket))
   {
      g_posTicket = 0; // closed by SL/TP - stats handled in OnTradeTransaction
      return;
   }

   g_posTicksHeld++;

   // FlipX trait: regime turned against us - the EV model's drift
   // assumption no longer holds, so the plan is void. Get out; a
   // reversed entry is allowed on the next tick if enabled.
   if(RegimeFlippedAgainst(g_posDir))
   {
      ClosePosition("regime flip");
      if(!AllowReverseOnFlip)
         g_spikeCooldownUntil = TimeCurrent() + SpikeCooldownSeconds;
      return;
   }

   // Time(tick)-stop: the EV plan priced a hold of planTicks; well past
   // that, realized drift has underperformed the model - stand aside.
   if(g_planTicks > 0 && g_posTicksHeld > (long)(g_planTicks * TimeStopPlanFactor))
   {
      ClosePosition("plan tick budget exhausted");
      return;
   }

   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSl = PositionGetDouble(POSITION_SL);
   double curTp = PositionGetDouble(POSITION_TP);
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);

   // close price for a long is bid, for a short is ask
   double closePrice = (g_posDir > 0) ? tick.bid : tick.ask;
   double profitDist = (g_posDir > 0) ? closePrice - entry : entry - closePrice;
   double rMultiple  = (g_posSlDistance > 0.0) ? profitDist / g_posSlDistance : 0.0;

   if(!g_posBreakevenSet && rMultiple >= BreakevenTriggerR)
   {
      double newSl = (g_posDir > 0) ? entry + BreakevenBufferPoints * point
                                     : entry - BreakevenBufferPoints * point;
      bool improves = (g_posDir > 0) ? (newSl > curSl && newSl < closePrice)
                                      : (newSl < curSl && newSl > closePrice);
      if(improves && trade.PositionModify(g_posTicket, newSl, curTp))
      {
         g_posBreakevenSet = true;
         PrintFormat("Breakeven set [%s] sl=%.5f", g_symbol, newSl);
      }
   }
   else if(g_posBreakevenSet && g_spikeSz > 0.0)
   {
      double trailDist = g_spikeSz * TrailSpikeFactor;
      double candidateSl = (g_posDir > 0) ? closePrice - trailDist : closePrice + trailDist;
      bool improves = (g_posDir > 0) ? (candidateSl > curSl + point)
                                      : (candidateSl < curSl - point);
      if(improves)
         trade.PositionModify(g_posTicket, candidateSl, curTp);
   }
}

// A spike against the position IS the modeled loss event - the EV plan
// priced exactly this outcome. Take it immediately instead of letting
// post-spike noise decide whether it grows.
void OnSpike(double spikeSignedDelta)
{
   g_spikeCooldownUntil = TimeCurrent() + SpikeCooldownSeconds;
   PrintFormat("SPIKE [%s] delta=%.5f (avg spike %.5f)", g_symbol, spikeSignedDelta, g_spikeSz);

   if(g_posTicket == 0) return;
   int spikeDir = (spikeSignedDelta > 0.0) ? 1 : -1;
   if(spikeDir != g_posDir)
      ClosePosition("adverse spike - modeled loss taken");
}

//======================================================================
// ACCOUNT GUARDS
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
      // account-level drawdown halt is deliberately NOT auto-cleared -
      // that hard stop requires the operator to review and restart
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
      PrintFormat("HALT: account drawdown %.2f%% >= cap %.2f%% - manual restart required",
                  ddPct, MaxAccountDrawdownPct);
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
// OnTradeTransaction - realized-result tracking for the consecutive-
// loss breaker. Lot size is never changed here (no martingale).
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
         PrintFormat("Circuit breaker: %d consecutive losses -> cooldown %d min",
                     g_consecutiveLosses, LossCooldownMinutes);
         g_consecutiveLosses = 0;
      }
   }
   else if(profit > 0.0)
      g_consecutiveLosses = 0;

   g_posTicket = 0;
   PrintFormat("Trade closed [%s] profit=%.2f", g_symbol, profit);
}

//======================================================================
// OnInit / OnDeinit
//======================================================================
void WarmupFromTickHistory()
{
   MqlTick hist[];
   int copied = CopyTicks(g_symbol, hist, COPY_TICKS_INFO, 0, StatWindowTicks + 500);
   if(copied <= 1)
   {
      Print("Tick-history warmup unavailable - stats will build from live ticks");
      return;
   }
   double dummy;
   for(int i = 0; i < copied; i++)
   {
      if(hist[i].bid <= 0.0) continue;
      if(!g_haveLastBid) { g_lastBid = hist[i].bid; g_haveLastBid = true; continue; }
      double delta = hist[i].bid - g_lastBid;
      g_lastBid = hist[i].bid;
      if(delta != 0.0) FeedDelta(delta, dummy);
   }
   PrintFormat("Warmed up from %d historical ticks (%d in window, %d spikes)", copied, g_count, g_spikeCt);
}

int OnInit()
{
   if(SpikeEveryNTicks <= 0 || StatWindowTicks <= MIN_TICKS_FOR_SPIKES || FlipWindowTicks <= 0)
   {
      Print("ERROR: invalid window/N inputs");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_symbol = ResolveSymbol(InpSymbol);
   if(g_symbol == "")
   {
      PrintFormat("ERROR: could not resolve a tradeable symbol (configured=\"%s\")", InpSymbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber((ulong)MagicNumber);
   trade.SetDeviationInPoints(TradeDeviationPoints);

   ArrayResize(g_deltaBuf, StatWindowTicks);
   ArrayResize(g_spikeFlagBuf, StatWindowTicks);
   ArrayResize(g_flipBuf, FlipWindowTicks);
   ArrayInitialize(g_deltaBuf, 0.0);
   ArrayInitialize(g_spikeFlagBuf, 0);
   ArrayInitialize(g_flipBuf, 0.0);

   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peakEquity      = AccountInfoDouble(ACCOUNT_EQUITY);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   g_currentDay = StructToTime(dt);

   PrintFormat("Godmode v2 initialized on %s | %s | N=%d", g_symbol, ClassifySymbolByName(g_symbol), SpikeEveryNTicks);

   WarmupFromTickHistory();
   RecomputePlan();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { }

//======================================================================
// OnTick
//======================================================================
void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick)) return;

   if(!g_haveLastBid)
   {
      g_lastBid = tick.bid;
      g_haveLastBid = true;
      return;
   }

   double delta = tick.bid - g_lastBid;
   g_lastBid = tick.bid;

   if(delta != 0.0)
   {
      double spikeSigned = 0.0;
      if(FeedDelta(delta, spikeSigned))
         OnSpike(spikeSigned);
   }

   UpdateDayRollover();
   UpdateAccountGuards();

   if(g_ticksSinceRecalc >= EvRecalcTicks) RecomputePlan();
   PrintStatsIfDue();

   ManagePosition(tick);
   if(g_posTicket == 0) TryEnter(tick);
}
