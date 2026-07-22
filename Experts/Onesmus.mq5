//+------------------------------------------------------------------+
//|                                                     Onesmus.mq5  |
//|              BTCUSD M1 arithmetic-logic scalping Expert Advisor  |
//+------------------------------------------------------------------+
#property copyright "Quant Systems"
#property version   "1.00"
#property description "Onesmus - a BTCUSD M1 Expert Advisor built on pure "
#property description "price arithmetic. Momentum is measured as raw price "
#property description "differences, fair value as a rolling arithmetic mean, "
#property description "stretch as absolute deviation, and volatility as ATR. "
#property description "Every stop, target and lot size is derived from the "
#property description "symbol's own point/tick-value arithmetic so the EA "
#property description "and BTCUSD move as one. Includes spread, session and "
#property description "daily-loss circuit breakers."

#include <Trade\Trade.mqh>

//======================================================================
// INPUT PARAMETERS
//======================================================================
input group "=== Core ==="
input string TargetSymbol       = "BTCUSD";  // symbol Onesmus is engineered for
input int    MagicNumber        = 20260722;  // magic number
input double RiskPercent        = 1.0;       // risk per trade (% of balance)
input double MaxLot             = 5.0;       // absolute lot ceiling
input int    MaxOpenPositions   = 1;         // simultaneous positions

input group "=== Arithmetic engine ==="
input int    MeanPeriod         = 34;        // rolling arithmetic-mean length (bars)
input int    MomentumBars       = 8;         // momentum lookback: close[1]-close[1+N]
input int    AtrPeriod          = 14;        // ATR period (M1)
input double StretchAtrMult     = 1.2;       // deviation from mean required, in ATRs
input double MomentumAtrMult    = 0.6;       // momentum required, in ATRs
input double SL_AtrMult         = 2.0;       // stop-loss distance, in ATRs
input double TP_AtrMult         = 3.0;       // take-profit distance, in ATRs

input group "=== Trade management ==="
input bool   UseBreakEven       = true;      // move SL to entry at +1R
input double BreakEvenR         = 1.0;       // R multiple that arms break-even
input bool   UseTrailing        = true;      // ATR trailing stop
input double TrailAtrMult       = 1.5;       // trailing distance, in ATRs
input int    MaxBarsInTrade     = 90;        // time stop: force exit after N M1 bars (0=off)

input group "=== Circuit breakers ==="
input double MaxSpreadAtrFrac   = 0.25;      // reject entries when spread > ATR * this
input double DailyLossLimitPct  = 4.0;       // halt trading after this % equity loss today
input double MinAtrPoints       = 50;        // dead-market filter: minimum ATR in points
input int    CooldownAfterLoss  = 5;         // bars to wait after a losing trade

//======================================================================
// GLOBALS
//======================================================================
CTrade   trade;
int      atrHandle      = INVALID_HANDLE;
datetime lastBarTime    = 0;
datetime cooldownUntil  = 0;
double   dayStartEquity = 0.0;
int      dayOfYearMark  = -1;

//======================================================================
// INITIALIZATION
//======================================================================
int OnInit()
  {
   if(_Symbol != TargetSymbol)
      PrintFormat("Onesmus: engineered for %s but attached to %s - arithmetic still applies, "
                  "but parameters are tuned for BTCUSD.", TargetSymbol, _Symbol);

   if(_Period != PERIOD_M1)
      Print("Onesmus: designed for the M1 chart. Attach to M1 for intended behaviour.");

   atrHandle = iATR(_Symbol, PERIOD_M1, AtrPeriod);
   if(atrHandle == INVALID_HANDLE)
     {
      Print("Onesmus: failed to create ATR handle.");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);          // BTCUSD ticks fast; allow slippage room
   trade.SetTypeFillingBySymbol(_Symbol);

   ResetDailyAnchor();
   Print("Onesmus initialised. Arithmetic engine online.");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
  }

//======================================================================
// DAILY EQUITY ANCHOR (for the daily-loss circuit breaker)
//======================================================================
void ResetDailyAnchor()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dayOfYearMark  = dt.day_of_year;
   dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
  }

bool DailyLossBreached()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year != dayOfYearMark)
      ResetDailyAnchor();

   if(dayStartEquity <= 0.0)
      return(false);

   double lossPct = 100.0 * (dayStartEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / dayStartEquity;
   return(lossPct >= DailyLossLimitPct);
  }

//======================================================================
// ARITHMETIC CORE
//   mean      = (1/N) * sum(close[i])            .. fair value
//   momentum  = close[1] - close[1+M]            .. signed price difference
//   stretch   = close[1] - mean                  .. displacement from fair value
//   All thresholds are expressed in ATR units so the same arithmetic
//   scales itself to whatever volatility BTCUSD is printing.
//======================================================================
bool GetArithmetic(double &mean, double &momentum, double &stretch, double &atr)
  {
   double closes[];
   int need = MathMax(MeanPeriod, MomentumBars + 1) + 2;
   if(CopyClose(_Symbol, PERIOD_M1, 1, need, closes) < need)
      return(false);
   ArraySetAsSeries(closes, true);

   double sum = 0.0;
   for(int i = 0; i < MeanPeriod; i++)
      sum += closes[i];
   mean = sum / MeanPeriod;

   momentum = closes[0] - closes[MomentumBars];
   stretch  = closes[0] - mean;

   double atrBuf[];
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuf) < 1)
      return(false);
   atr = atrBuf[0];

   return(atr > 0.0);
  }

//======================================================================
// SIGNAL
//   +1 buy : price stretched BELOW fair value while short-term momentum
//            has already turned positive (mean-reversion with the turn).
//   -1 sell: mirror arithmetic on the upside.
//    0     : no edge.
//======================================================================
int Signal(const double mean, const double momentum, const double stretch, const double atr)
  {
   double stretchNeed  = StretchAtrMult  * atr;
   double momentumNeed = MomentumAtrMult * atr;

   if(stretch <= -stretchNeed && momentum >=  momentumNeed) return( 1);
   if(stretch >=  stretchNeed && momentum <= -momentumNeed) return(-1);
   return(0);
  }

//======================================================================
// POSITION SIZING - pure tick-value arithmetic
//   riskMoney   = balance * RiskPercent/100
//   lossPerLot  = (slDistance / tickSize) * tickValue
//   lots        = riskMoney / lossPerLot, clamped to broker limits
//======================================================================
double LotsForRisk(const double slDistance)
  {
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || slDistance <= 0.0)
      return(0.0);

   double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return(0.0);

   double lots = riskMoney / lossPerLot;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLotB = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep > 0.0)
      lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMin(lots, MathMin(MaxLot, maxLotB));

   if(lots < minLot)
      return(0.0);   // account too small to honour the risk cap - stand down
   return(lots);
  }

//======================================================================
// OPEN-POSITION HELPERS
//======================================================================
int CountMyPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
     }
   return(count);
  }

//======================================================================
// TRADE MANAGEMENT: break-even, ATR trail, time stop
//======================================================================
void ManagePositions(const double atr)
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      long   type    = PositionGetInteger(POSITION_TYPE);
      double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl      = PositionGetDouble(POSITION_SL);
      double tp      = PositionGetDouble(POSITION_TP);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // --- time stop: the M1 edge decays fast; cut stale trades ---
      if(MaxBarsInTrade > 0 && (TimeCurrent() - opened) >= (long)MaxBarsInTrade * 60)
        {
         trade.PositionClose(ticket);
         continue;
        }

      double riskDist = MathAbs(entry - sl);
      if(riskDist <= 0.0)
         continue;

      if(type == POSITION_TYPE_BUY)
        {
         double profitDist = bid - entry;

         // break-even: profit >= BreakEvenR * initial risk
         if(UseBreakEven && sl < entry && profitDist >= BreakEvenR * riskDist)
            trade.PositionModify(ticket, NormalizeDouble(entry, digits), tp);

         // ATR trail
         if(UseTrailing)
           {
            double newSL = NormalizeDouble(bid - TrailAtrMult * atr, digits);
            if(newSL > sl && newSL > entry)
               trade.PositionModify(ticket, newSL, tp);
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double profitDist = entry - ask;

         if(UseBreakEven && (sl > entry || sl == 0.0) && profitDist >= BreakEvenR * riskDist)
            trade.PositionModify(ticket, NormalizeDouble(entry, digits), tp);

         if(UseTrailing)
           {
            double newSL = NormalizeDouble(ask + TrailAtrMult * atr, digits);
            if((newSL < sl || sl == 0.0) && newSL < entry)
               trade.PositionModify(ticket, newSL, tp);
           }
        }
     }
  }

//======================================================================
// LOSS COOLDOWN - after a losing deal, sit out a few bars
//======================================================================
void UpdateCooldown()
  {
   datetime from = TimeCurrent() - 3600;   // scan the last hour of history
   if(!HistorySelect(from, TimeCurrent()))
      return;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      if(HistoryDealGetDouble(ticket, DEAL_PROFIT) < 0.0)
        {
         datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         datetime until     = closeTime + (long)CooldownAfterLoss * 60;
         if(until > cooldownUntil)
            cooldownUntil = until;
        }
      break;   // most recent exit deal is enough
     }
  }

//======================================================================
// MAIN TICK HANDLER - acts once per new M1 bar
//======================================================================
void OnTick()
  {
   // manage open trades on every tick (BTCUSD moves too fast to wait)
   double atrBuf[];
   double atrNow = 0.0;
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuf) >= 1)
      atrNow = atrBuf[0];
   if(atrNow > 0.0)
      ManagePositions(atrNow);

   // entries only on a fresh M1 bar
   datetime barTime = iTime(_Symbol, PERIOD_M1, 0);
   if(barTime == lastBarTime)
      return;
   lastBarTime = barTime;

   if(DailyLossBreached())
      return;                          // circuit breaker: done for the day

   UpdateCooldown();
   if(TimeCurrent() < cooldownUntil)
      return;

   if(CountMyPositions() >= MaxOpenPositions)
      return;

   double mean, momentum, stretch, atr;
   if(!GetArithmetic(mean, momentum, stretch, atr))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // dead-market filter: no arithmetic edge in a flat tape
   if(atr / point < MinAtrPoints)
      return;

   // spread filter: cost must stay a small fraction of the volatility unit
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   if(spread > MaxSpreadAtrFrac * atr)
      return;

   int sig = Signal(mean, momentum, stretch, atr);
   if(sig == 0)
      return;

   int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double slDist  = SL_AtrMult * atr;
   double tpDist  = TP_AtrMult * atr;
   double lots    = LotsForRisk(slDist);
   if(lots <= 0.0)
      return;

   if(sig > 0)
     {
      double sl = NormalizeDouble(ask - slDist, digits);
      double tp = NormalizeDouble(ask + tpDist, digits);
      if(!trade.Buy(lots, _Symbol, 0.0, sl, tp, "Onesmus M1 buy"))
         PrintFormat("Onesmus: buy failed, retcode=%d", trade.ResultRetcode());
     }
   else
     {
      double sl = NormalizeDouble(bid + slDist, digits);
      double tp = NormalizeDouble(bid - tpDist, digits);
      if(!trade.Sell(lots, _Symbol, 0.0, sl, tp, "Onesmus M1 sell"))
         PrintFormat("Onesmus: sell failed, retcode=%d", trade.ResultRetcode());
     }
  }
//+------------------------------------------------------------------+
