//+------------------------------------------------------------------+
//|                                             WeltradeSynthEA.mq5   |
//|            Weltrade GainX / FlipX adaptive synthetic-index EA     |
//|          Entity-aware: drift-rider for GainX, mean-reversion      |
//|          for FlipX. Native MQL5, no DLLs / ONNX / external files. |
//+------------------------------------------------------------------+
#property copyright "Quant Systems"
#property version   "1.00"
#property description "Adaptive EA for Weltrade synthetic indices (GainX / PainX / FlipX)."
#property description "Auto-classifies each symbol and applies the technique that suits the"
#property description "entity: a trend/pullback drift-rider for the drifting GainX/PainX"
#property description "families, and a z-score mean-reversion fader for the oscillating FlipX"
#property description "family. Harvests proven modules from the Gold portfolio EA - tiered"
#property description "low-balance sizing, ATR risk model, native neural-net confidence filter,"
#property description "circuit breakers, drawdown recovery, partial/breakeven/trailing/pyramid"
#property description "management and a portfolio risk governor. Synthetics trade 24/7, so the"
#property description "session and news-blackout gating from FX/gold systems is deliberately"
#property description "removed - it does not suit these instruments."
//
// Design doctrine (OODA):
//   OBSERVE  - per-symbol ATR, EMA/SMA/StdDev/RSI, drift bias, spread ratio.
//   ORIENT   - classify the instrument (GainX / PainX / FlipX / generic) and its
//              current regime; pick the engine that suits that entity.
//   DECIDE   - rule trigger AND (optional) online neural-net confidence gate.
//   ACT      - size by tier + risk%, execute, then manage with partial / breakeven /
//              trailing / pyramid and multi-layer circuit breakers.

#include <Trade\Trade.mqh>

//======================================================================
// INPUT PARAMETERS
//======================================================================
input string          InpWatchlist        = "GainX 800,GainX 999,GainX 1200,FlipX 1,FlipX 2,FlipX 3"; // comma list; broker names kept verbatim
input ENUM_TIMEFRAMES InpSignalTF         = PERIOD_M5;   // engine timeframe
input ENUM_TIMEFRAMES InpTrendTF          = PERIOD_M30;  // higher-TF trend filter (GainX/PainX)
input double          InpRiskPercent      = 1.0;         // fallback risk% when tier engine is off
input double          InpMinAccountUSD    = 2.0;         // operational floor (cent accounts scaled x100)
input int             InpMagicBase        = 20260720;
input int             InpMaxOpenTrades    = 4;           // hard portfolio cap (tier may lower it)
input bool            InpUseTierEngine    = true;        // scale risk & slots by balance
input double          InpMaxDrawdownPct   = 20.0;        // equity kill-switch (hysteresis)
input int             InpTimerSeconds     = 2;

// --- signal / neural filter ---
input bool            InpUseNNFilter      = true;
input double          InpNNThreshold      = 0.55;        // min NN confidence to trade
input double          InpLearningRate     = 0.01;

// --- GainX / PainX drift-rider engine ---
input int             InpFastMA           = 21;
input int             InpSlowMA           = 50;
input int             InpRSIPeriod        = 14;
input bool            InpAllowCounterDrift = false;      // trade against the family's drift on strong reversals

// --- FlipX mean-reversion engine ---
input int             InpMeanPeriod       = 34;
input double          InpZEntry           = 2.0;         // std-devs from mean to fade
input double          InpZMaxChase        = 3.5;         // beyond this = runaway, stand aside

// --- risk / trade management ---
input double          InpSL_ATR_Mult      = 2.0;
input double          InpTrendTP_R        = 3.0;         // GainX TP as R multiple (0 = trail only)
input double          InpSpreadATRcap     = 0.35;        // skip if spread > cap * signalATR
input bool            InpEnablePartial    = true;
input bool            InpEnableTrailing   = true;
input bool            InpEnablePyramid    = true;        // win-streak add-ons (trend entities only)
input bool            InpEnableSQLite     = false;

// --- guards ---
input int             InpCircuitLossCount = 4;           // consecutive losses -> pause symbol
input int             InpCircuitPauseMin  = 120;
input int             InpWinRateMinTrades = 25;
input double          InpWinRateFloor     = 38.0;        // % rolling win-rate floor

// --- Medula-style grid / basket recovery ---
// When on, entries carry no hard per-trade SL; the basket is defended by
// martingale grid adds and exited as a whole on a basket profit target, with
// a hard basket max-loss cut + the global DD kill-switch as the safety net.
input bool            InpEnableRecovery   = true;        // grid/basket recovery mode (Medula trait)
input double          InpGridStepATR      = 1.0;         // adverse move (in signal ATR) before adding a grid level
input double          InpGridLotFactor    = 1.6;         // lot multiplier per grid level (martingale)
input int             InpMaxGridLevels    = 4;           // max recovery adds per symbol basket
input double          InpBasketTP_R       = 1.0;         // basket take-profit as R of the initial risk
input double          InpBasketTrailFrac  = 0.50;        // once past target, lock this fraction of peak basket profit
input bool            InpBasketTrailing   = true;        // trail the basket profit instead of flat-closing at target
input double          InpMaxBasketLossPct = 8.0;         // hard cut: close the whole basket if its loss exceeds this % of equity

//======================================================================
// NAMED CONSTANTS
//======================================================================
#define WEIGHTS_FILENAME            "WeltradeSynthWeights.bin"
#define DB_FILENAME                 "WeltradeSynth.sqlite"
#define ATR_PERIOD                  14
#define ROLLING_HISTORY_SIZE        20
#define NN_INPUTS                   5
#define NN_HIDDEN                   8
#define MAX_PYRAMID_LEVELS          3
#define TICK_BUFFER_SIZE            400
#define TRADE_DEVIATION_POINTS      20
#define WEIGHT_INIT_RANGE           0.5
#define SL_MIN_POINTS               10
#define M1_ATR_SPIKE_FACTOR         4.0     // runaway-volatility pause trigger
#define VOL_SPIKE_PAUSE_SEC         60
#define MARGIN_USAGE_CAP_FRACTION   0.25
#define PORTFOLIO_RISK_CAP_FRACTION 0.06
#define PORTFOLIO_RISK_RESUME_FRAC  0.03
#define WIN_RATE_UNBLOCK_TRADES     5
#define DD_RECOVERY_TRIGGER_FRAC    0.10
#define DD_RECOVERY_CLEAR_FRAC      0.95
#define PARTIAL_CLOSE_R_MULT        1.0
#define PARTIAL_CLOSE_FRACTION      0.50
#define BREAKEVEN_R_MULT            0.80
#define BREAKEVEN_BUFFER_POINTS     2
#define TRAIL_START_R_MULT          1.5
#define TRAIL_PROFIT_LOCK_FRACTION  0.50
#define PYRAMID_L1_MULT             0.50
#define PYRAMID_L2_MULT             0.25
#define TIER_REEVAL_TRADE_INTERVAL  10
#define EQUITY_LOG_INTERVAL_SEC     60

//======================================================================
// ENUMS
//======================================================================
enum ENUM_SYNTH_TYPE { SYNTH_GAINX, SYNTH_PAINX, SYNTH_FLIPX, SYNTH_GENERIC };
enum ENUM_ENGINE     { ENGINE_TREND, ENGINE_MEANREV };

//======================================================================
// PER-SYMBOL CONFIG
//======================================================================
struct SymbolConfig
{
   string           Name;
   bool             Available;
   ENUM_SYNTH_TYPE  Type;
   ENUM_ENGINE      Engine;
   int              DriftBias;        // +1 GainX, -1 PainX, 0 FlipX/generic
   int              IndexMagnitude;   // e.g. 800 / 999 / 1200 (informational)

   double           MinLot, LotStep, MaxLot;
   double           PointValue, TickSize, TickValue;

   // guards / stats
   int              ConsecutiveLosses;
   int              ConsecutiveWins;
   int              RollingHistory[ROLLING_HISTORY_SIZE];
   int              HistoryIndex;
   bool             CircuitBreakerActive;
   datetime         CircuitBreakerExpiry;
   bool             SpikePauseActive;
   datetime         SpikePauseExpiry;
   int              WinRateGuardCooldown;
   bool             InDrawdownRecovery;
   double           PeakEquity;

   // pyramid
   int              PyramidLevel;
   ulong            PyramidTickets[MAX_PYRAMID_LEVELS];
   double           PyramidAddedVolume;

   // grid / basket recovery (Medula trait)
   bool             BasketActive;
   bool             BasketClosing;
   int              BasketDir;          // +1 / -1, fixed for the life of the basket
   int              BasketLevel;        // number of grid adds so far
   double           BasketBaseLot;      // lot of the initial entry
   double           BasketLastAddPrice; // price of the most recent add (grid-step reference)
   double           BasketInitRisk;     // 1R of the initial entry (money) -> basket target base
   double           BasketRealizedPnL;  // realized PnL accumulated as legs close out
   double           BasketPeakProfit;   // peak floating profit once past target (for trailing)

   // NN last-forward cache (for online update)
   double           LastInput[NN_INPUTS];
   double           LastHidden[NN_HIDDEN];
   double           LastOutput;

   // bookkeeping
   int              TotalTrades;
   int              TotalWins;
   double           NetPnL;
   datetime         LastBarTime;
};

//======================================================================
// PER-OPEN-TRADE SIDE TABLE
//======================================================================
struct OpenTradeState
{
   ulong  Ticket;
   int    Idx;
   double RiskAmt;      // 1R in account currency
   double SlDistance;   // price distance entry->SL
   double EntryPrice;
   bool   IsPyramidLeg;
   bool   PartialDone;
   bool   BreakevenSet;
};

//======================================================================
// GLOBALS
//======================================================================
CTrade         trade;
SymbolConfig   g_cfg[];
OpenTradeState g_openTrades[];
int            g_symbolCount = 0;

int            g_currentTier = 0;
int            g_maxTrades   = 0;
double         g_tierRiskPct = 0.0;

matrix         g_W1(NN_INPUTS, NN_HIDDEN);
matrix         g_W2(NN_HIDDEN, 1);
vector         g_B1(NN_HIDDEN);
vector         g_B2(1);

int            g_dbHandle = INVALID_HANDLE;
bool           g_hedgingMode = false;

double         g_globalPeakEquity = 0.0;
bool           g_portfolioRiskBlocked = false;
bool           g_ddKillSwitch = false;
int            g_totalClosedTrades = 0;
datetime       g_lastEquityLogTime = 0;

//======================================================================
// UTILITIES
//======================================================================
double Sigmoid(double x) { return 1.0 / (1.0 + MathExp(-x)); }
double Clamp(double v, double lo, double hi) { return MathMax(lo, MathMin(hi, v)); }

int FindCfgIndex(string symbol)
{
   for(int i = 0; i < g_symbolCount; i++)
      if(g_cfg[i].Name == symbol) return i;
   return -1;
}

int FindOpenTradeState(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_openTrades); i++)
      if(g_openTrades[i].Ticket == ticket) return i;
   return -1;
}

void RemoveOpenTradeState(ulong ticket)
{
   int idx = FindOpenTradeState(ticket);
   if(idx < 0) return;
   int last = ArraySize(g_openTrades) - 1;
   g_openTrades[idx] = g_openTrades[last];
   ArrayResize(g_openTrades, last);
}

void PushOpenTradeState(OpenTradeState &st)
{
   int n = ArraySize(g_openTrades);
   ArrayResize(g_openTrades, n + 1);
   g_openTrades[n] = st;
}

// Drop every side-table row for a symbol (netting merges grid legs into one
// position id, so per-ticket removal can leave orphan rows behind).
void PurgeOpenTradeStates(int idx)
{
   for(int i = ArraySize(g_openTrades) - 1; i >= 0; i--)
      if(g_openTrades[i].Idx == idx)
      {
         int last = ArraySize(g_openTrades) - 1;
         g_openTrades[i] = g_openTrades[last];
         ArrayResize(g_openTrades, last);
      }
}

//======================================================================
// OBSERVE — native indicator math (no handles, multi-symbol friendly)
//======================================================================
double GetATR(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   int need = period + 1;
   if(CopyRates(symbol, tf, 0, need, bars) < need) return 0.0;
   double sum = 0.0;
   for(int i = 0; i < period; i++)
   {
      double tr = MathMax(bars[i].high - bars[i].low,
                  MathMax(MathAbs(bars[i].high - bars[i + 1].close),
                          MathAbs(bars[i].low - bars[i + 1].close)));
      sum += tr;
   }
   return sum / period;
}

double GetEMA(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   if(period < 1) return 0.0;
   double c[];
   ArraySetAsSeries(c, true);
   int need = period * 3 + 10;
   int copied = CopyClose(symbol, tf, 0, need, c);
   if(copied < period + 1) return 0.0;
   double k = 2.0 / (period + 1.0);
   double sum = 0.0;
   for(int i = copied - 1; i >= copied - period; i--) sum += c[i];
   double ema = sum / period;                       // SMA seed over oldest 'period' bars
   for(int i = copied - period - 1; i >= 0; i--)     // walk forward to the newest bar
      ema = c[i] * k + ema * (1.0 - k);
   return ema;
}

double GetSMA(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   double c[];
   ArraySetAsSeries(c, true);
   if(CopyClose(symbol, tf, 0, period, c) < period) return 0.0;
   double sum = 0.0;
   for(int i = 0; i < period; i++) sum += c[i];
   return sum / period;
}

double GetStdDev(string symbol, ENUM_TIMEFRAMES tf, int period, double mean)
{
   double c[];
   ArraySetAsSeries(c, true);
   if(CopyClose(symbol, tf, 0, period, c) < period) return 0.0;
   double ss = 0.0;
   for(int i = 0; i < period; i++) { double d = c[i] - mean; ss += d * d; }
   return MathSqrt(ss / period);
}

// Normalised momentum in [0,100] (average-gain style, robust and monotonic).
double GetRSI(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   double c[];
   ArraySetAsSeries(c, true);
   if(CopyClose(symbol, tf, 0, period + 1, c) < period + 1) return 50.0;
   double gain = 0.0, loss = 0.0;
   for(int i = 0; i < period; i++)
   {
      double d = c[i] - c[i + 1];
      if(d > 0) gain += d; else loss += -d;
   }
   if(gain + loss <= 0.0) return 50.0;
   return 100.0 * gain / (gain + loss);
}

double GetSpreadRatio(string symbol, double signalATR)
{
   if(signalATR <= 0.0) return 0.0;
   double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
   return spread / signalATR;
}

//======================================================================
// ORIENT — instrument classification
//======================================================================
ENUM_SYNTH_TYPE ClassifySymbol(string sym)
{
   string u = sym;
   StringToUpper(u);
   if(StringFind(u, "GAIN") >= 0) return SYNTH_GAINX;
   if(StringFind(u, "PAIN") >= 0) return SYNTH_PAINX;
   if(StringFind(u, "FLIP") >= 0) return SYNTH_FLIPX;
   return SYNTH_GENERIC;
}

int ExtractMagnitude(string sym)
{
   int val = 0; bool seen = false;
   int len = StringLen(sym);
   for(int i = 0; i < len; i++)
   {
      ushort ch = StringGetCharacter(sym, i);
      if(ch >= '0' && ch <= '9') { val = val * 10 + (int)(ch - '0'); seen = true; }
      else if(seen) break;   // first contiguous number block only
   }
   return val;
}

string TypeName(ENUM_SYNTH_TYPE t)
{
   switch(t)
   {
      case SYNTH_GAINX: return "GainX(drift-up)";
      case SYNTH_PAINX: return "PainX(drift-down)";
      case SYNTH_FLIPX: return "FlipX(mean-revert)";
      default:          return "Generic";
   }
}

//======================================================================
// ACCOUNT INTELLIGENCE & TIER ENGINE
//======================================================================
double GetEffectiveBalance()
{
   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   bool isCent     = (currency == "USC" || currency == "USDC" || StringFind(currency, "Cent") >= 0);
   return isCent ? balance * 100.0 : balance;
}

void EvaluateTier(double effBalance, int &tier, int &maxTrades, double &riskPct)
{
   if(!InpUseTierEngine)
   {
      tier = 5; maxTrades = InpMaxOpenTrades; riskPct = InpRiskPercent;
      return;
   }
   if(effBalance < InpMinAccountUSD) { tier = 0; maxTrades = 0; riskPct = 0.0; }
   else if(effBalance <= 4.99)       { tier = 1; maxTrades = 1; riskPct = 0.5; }
   else if(effBalance <= 9.99)       { tier = 2; maxTrades = 2; riskPct = 0.75; }
   else if(effBalance <= 49.99)      { tier = 3; maxTrades = 3; riskPct = 1.0; }
   else if(effBalance <= 199.99)     { tier = 4; maxTrades = 4; riskPct = 1.0; }
   else                              { tier = 5; maxTrades = 5; riskPct = 1.0; }
   maxTrades = MathMin(maxTrades, InpMaxOpenTrades);
}

int CountOpenManagedPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic >= InpMagicBase && magic < InpMagicBase + g_symbolCount) count++;
   }
   return count;
}

bool HasOpenPosition(int idx)
{
   long wantMagic = InpMagicBase + idx;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) == wantMagic) return true;
   }
   return false;
}

// In recovery mode a symbol can hold several grid legs; the portfolio cap must
// count symbols with an open basket, not individual legs.
int CountActiveSymbols()
{
   int n = 0;
   for(int i = 0; i < g_symbolCount; i++)
      if(HasOpenPosition(i)) n++;
   return n;
}

// Floating profit (incl. swap) of every managed leg on a symbol's basket.
double ComputeBasketProfit(int idx)
{
   long wantMagic = InpMagicBase + idx;
   double p = 0.0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != wantMagic) continue;
      p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return p;
}

void CloseWorstExcessPositions(int excessCount)
{
   for(int c = 0; c < excessCount; c++)
   {
      ulong worstTicket = 0; double worstProfit = DBL_MAX;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic < InpMagicBase || magic >= InpMagicBase + g_symbolCount) continue;
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit < worstProfit) { worstProfit = profit; worstTicket = ticket; }
      }
      if(worstTicket == 0) break;
      trade.PositionClose(worstTicket);
      Print("Tier demotion: closed excess position ticket=", worstTicket);
   }
}

void RecalculateTier()
{
   double effBalance = GetEffectiveBalance();
   int newTier, newMax; double newRisk;
   EvaluateTier(effBalance, newTier, newMax, newRisk);

   if(newTier != g_currentTier)
      PrintFormat("TIER CHANGE: TIER%d -> TIER%d | EffBalance=%.2f MaxTrades=%d RiskPct=%.2f",
                  g_currentTier, newTier, effBalance, newMax, newRisk);

   if(newMax < g_maxTrades)
   {
      int openCount = CountOpenManagedPositions();
      if(openCount > newMax) CloseWorstExcessPositions(openCount - newMax);
   }
   g_currentTier = newTier; g_maxTrades = newMax; g_tierRiskPct = newRisk;
}

//======================================================================
// NATIVE NEURAL NETWORK (online-trained confidence filter)
//======================================================================
void InitializeWeights()
{
   MathSrand((int)TimeLocal());
   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++)
         g_W1[i, j] = ((MathRand() / 32767.0) * 2.0 - 1.0) * WEIGHT_INIT_RANGE;
   for(int j = 0; j < NN_HIDDEN; j++)
      g_W2[j, 0] = ((MathRand() / 32767.0) * 2.0 - 1.0) * WEIGHT_INIT_RANGE;
   g_B1.Fill(0.0);
   g_B2.Fill(0.0);
   Print("Neural filter initialized with random weights - learning begins");
}

bool LoadWeights()
{
   if(!FileIsExist(WEIGHTS_FILENAME)) return false;
   int fh = FileOpen(WEIGHTS_FILENAME, FILE_READ | FILE_BIN);
   if(fh == INVALID_HANDLE) return false;
   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++) g_W1[i, j] = FileReadDouble(fh);
   for(int j = 0; j < NN_HIDDEN; j++) g_W2[j, 0] = FileReadDouble(fh);
   for(int j = 0; j < NN_HIDDEN; j++) g_B1[j] = FileReadDouble(fh);
   g_B2[0] = FileReadDouble(fh);
   FileClose(fh);
   Print("Neural filter weights loaded from ", WEIGHTS_FILENAME);
   return true;
}

void SaveWeights()
{
   int fh = FileOpen(WEIGHTS_FILENAME, FILE_WRITE | FILE_BIN);
   if(fh == INVALID_HANDLE) return;
   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++) FileWriteDouble(fh, g_W1[i, j]);
   for(int j = 0; j < NN_HIDDEN; j++) FileWriteDouble(fh, g_W2[j, 0]);
   for(int j = 0; j < NN_HIDDEN; j++) FileWriteDouble(fh, g_B1[j]);
   FileWriteDouble(fh, g_B2[0]);
   FileClose(fh);
}

double GetNNConfidence(int idx, double f0, double f1, double f2, double f3, double f4)
{
   double input[NN_INPUTS];
   input[0] = f0; input[1] = f1; input[2] = f2; input[3] = f3; input[4] = f4;

   double hidden[NN_HIDDEN];
   for(int j = 0; j < NN_HIDDEN; j++)
   {
      double sum = g_B1[j];
      for(int i = 0; i < NN_INPUTS; i++) sum += input[i] * g_W1[i, j];
      hidden[j] = Sigmoid(sum);
   }
   double outSum = g_B2[0];
   for(int j = 0; j < NN_HIDDEN; j++) outSum += hidden[j] * g_W2[j, 0];
   double output = Sigmoid(outSum);

   for(int i = 0; i < NN_INPUTS; i++) g_cfg[idx].LastInput[i] = input[i];
   for(int j = 0; j < NN_HIDDEN; j++) g_cfg[idx].LastHidden[j] = hidden[j];
   g_cfg[idx].LastOutput = output;
   return output;
}

void UpdateWeights(int idx, double tradePnL)
{
   if(!InpUseNNFilter) return;
   double target = (tradePnL > 0.0) ? 1.0 : 0.0;
   double output = g_cfg[idx].LastOutput;
   double dOut   = (target - output) * output * (1.0 - output);

   double dHidden[NN_HIDDEN];
   for(int j = 0; j < NN_HIDDEN; j++)
   {
      double h = g_cfg[idx].LastHidden[j];
      dHidden[j] = dOut * g_W2[j, 0] * h * (1.0 - h);
   }
   for(int j = 0; j < NN_HIDDEN; j++)
      g_W2[j, 0] += InpLearningRate * g_cfg[idx].LastHidden[j] * dOut;
   g_B2[0] += InpLearningRate * dOut;
   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++)
         g_W1[i, j] += InpLearningRate * g_cfg[idx].LastInput[i] * dHidden[j];
   for(int j = 0; j < NN_HIDDEN; j++)
      g_B1[j] += InpLearningRate * dHidden[j];
   SaveWeights();
}

//======================================================================
// MONEY / LOT SIZING
//======================================================================
double GetPointValueMoney(int idx)
{
   if(g_cfg[idx].TickSize <= 0.0 || g_cfg[idx].TickValue <= 0.0) return 0.0;
   return (g_cfg[idx].TickValue / g_cfg[idx].TickSize) * g_cfg[idx].PointValue;
}

double PriceDistanceToMoney(int idx, double priceDist, double volume)
{
   double point = g_cfg[idx].PointValue;
   if(point <= 0.0) return 0.0;
   return (priceDist / point) * GetPointValueMoney(idx) * volume;
}

double GetActiveRiskPct()
{
   return InpUseTierEngine ? g_tierRiskPct : InpRiskPercent;
}

double CalculateLotSize(int idx, double slDist, double &riskAmtOut)
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt = equity * (GetActiveRiskPct() / 100.0);
   riskAmtOut     = riskAmt;

   double ptVal = GetPointValueMoney(idx);
   if(ptVal <= 0.0 || slDist <= 0.0) return 0.0;

   double rawLot  = riskAmt / (slDist / g_cfg[idx].PointValue * ptVal);
   double lotStep = g_cfg[idx].LotStep;
   if(lotStep <= 0.0) return 0.0;

   double finalLot = MathFloor(rawLot / lotStep) * lotStep;
   finalLot = MathMax(finalLot, g_cfg[idx].MinLot);
   finalLot = MathMin(finalLot, g_cfg[idx].MaxLot);
   if(g_cfg[idx].InDrawdownRecovery)
      finalLot = MathMax(finalLot * 0.5, g_cfg[idx].MinLot);
   if(finalLot < g_cfg[idx].MinLot) return 0.0;
   return finalLot;
}

//======================================================================
// GUARDS
//======================================================================
double GetRollingWinRate(int idx, int &count)
{
   count = MathMin(g_cfg[idx].HistoryIndex, ROLLING_HISTORY_SIZE);
   if(count <= 0) return 1.0;
   int wins = 0;
   for(int i = 0; i < count; i++) wins += g_cfg[idx].RollingHistory[i];
   return (double)wins / (double)count;
}

void ClearExpiredGuards()
{
   for(int i = 0; i < g_symbolCount; i++)
   {
      if(g_cfg[i].CircuitBreakerActive && TimeCurrent() >= g_cfg[i].CircuitBreakerExpiry)
      {
         g_cfg[i].CircuitBreakerActive = false;
         g_cfg[i].ConsecutiveLosses = 0;
         PrintFormat("Circuit breaker cleared [%s]", g_cfg[i].Name);
      }
      if(g_cfg[i].SpikePauseActive && TimeCurrent() >= g_cfg[i].SpikePauseExpiry)
         g_cfg[i].SpikePauseActive = false;
   }
}

double ComputePortfolioRisk()
{
   double total = 0.0;
   for(int i = 0; i < ArraySize(g_openTrades); i++) total += g_openTrades[i].RiskAmt;
   return total;
}

void UpdatePortfolioRiskState()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0) return;
   double risk = ComputePortfolioRisk();
   if(!g_portfolioRiskBlocked && risk > equity * PORTFOLIO_RISK_CAP_FRACTION)
   {
      g_portfolioRiskBlocked = true;
      PrintFormat("Portfolio risk governor: entries blocked (risk=%.2f > %.1f%% equity)",
                  risk, PORTFOLIO_RISK_CAP_FRACTION * 100.0);
   }
   else if(g_portfolioRiskBlocked && risk < equity * PORTFOLIO_RISK_RESUME_FRAC)
   {
      g_portfolioRiskBlocked = false;
      Print("Portfolio risk governor: resumed");
   }
}

void UpdateDrawdownKillSwitch()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_globalPeakEquity) g_globalPeakEquity = equity;
   if(g_globalPeakEquity <= 0.0) return;
   double dd = (g_globalPeakEquity - equity) / g_globalPeakEquity;
   if(!g_ddKillSwitch && dd >= InpMaxDrawdownPct / 100.0)
   {
      g_ddKillSwitch = true;
      PrintFormat("DRAWDOWN KILL-SWITCH: new entries halted (DD=%.2f%%)", dd * 100.0);
   }
   else if(g_ddKillSwitch && equity >= g_globalPeakEquity * DD_RECOVERY_CLEAR_FRAC)
   {
      g_ddKillSwitch = false;
      Print("Drawdown kill-switch cleared - entries resumed");
   }
}

bool IsSymbolTradeable(int idx)
{
   SymbolConfig cfg = g_cfg[idx];
   if(!cfg.Available) return false;
   if(cfg.CircuitBreakerActive) return false;
   if(cfg.SpikePauseActive) return false;
   if(cfg.WinRateGuardCooldown > 0) return false;

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginReq = 0.0;
   if(freeMargin > 0.0 &&
      OrderCalcMargin(ORDER_TYPE_BUY, cfg.Name, cfg.MinLot,
                      SymbolInfoDouble(cfg.Name, SYMBOL_ASK), marginReq))
   {
      if(marginReq > freeMargin * MARGIN_USAGE_CAP_FRACTION) return false;
   }
   return true;
}

//======================================================================
// DECIDE — entity-aware signal engines
//======================================================================
// Fills dir(+1/-1), slDist, tpDist (price distances) and NN feature vector.
bool BuildSignal(int idx, int &dir, double &slDist, double &tpDist,
                 double &f0, double &f1, double &f2, double &f3, double &f4)
{
   string sym = g_cfg[idx].Name;
   double atr = GetATR(sym, InpSignalTF, ATR_PERIOD);
   if(atr <= 0.0) return false;

   // Runaway-volatility pause (spike protection - suits synthetic spike indices).
   double h1atr = GetATR(sym, PERIOD_H1, ATR_PERIOD);
   if(h1atr > 0.0 && atr > h1atr * M1_ATR_SPIKE_FACTOR)
   {
      g_cfg[idx].SpikePauseActive = true;
      g_cfg[idx].SpikePauseExpiry = TimeCurrent() + VOL_SPIKE_PAUSE_SEC;
      return false;
   }

   // Spread filter relative to volatility.
   if(GetSpreadRatio(sym, atr) > InpSpreadATRcap) return false;

   double rsi   = GetRSI(sym, InpSignalTF, InpRSIPeriod);
   double bias  = (double)g_cfg[idx].DriftBias;
   double volRt = (h1atr > 0.0) ? Clamp(atr / h1atr, 0.0, 3.0) / 3.0 : 0.5;

   dir = 0; slDist = 0.0; tpDist = 0.0;

   if(g_cfg[idx].Engine == ENGINE_TREND)
   {
      // ---- GainX / PainX / generic : trend-with-drift pullback rider ----
      double fastMA = GetEMA(sym, InpSignalTF, InpFastMA);
      double slowMA = GetEMA(sym, InpSignalTF, InpSlowMA);
      if(fastMA <= 0.0 || slowMA <= 0.0) return false;

      int localTrend = (fastMA > slowMA) ? 1 : (fastMA < slowMA ? -1 : 0);
      int htfTrend = 0;
      double htfFast = GetEMA(sym, InpTrendTF, InpFastMA);
      double htfSlow = GetEMA(sym, InpTrendTF, InpSlowMA);
      if(htfFast > 0.0 && htfSlow > 0.0) htfTrend = (htfFast > htfSlow) ? 1 : -1;

      // Candidate direction: family drift bias wins; else follow the trend.
      int cand = (g_cfg[idx].DriftBias != 0) ? g_cfg[idx].DriftBias : localTrend;
      if(cand == 0) return false;

      // Counter-drift entries only when explicitly allowed.
      if(g_cfg[idx].DriftBias != 0 && cand != g_cfg[idx].DriftBias && !InpAllowCounterDrift)
         return false;
      // Trend alignment: require the HTF not to oppose us.
      if(htfTrend != 0 && htfTrend != cand && !InpAllowCounterDrift) return false;

      // Pullback-then-resume trigger on the signal TF.
      MqlRates r[];
      ArraySetAsSeries(r, true);
      if(CopyRates(sym, InpSignalTF, 0, 3, r) < 3) return false;
      bool bounceUp   = (r[0].close > r[1].close) && (r[1].close <= r[2].close);
      bool bounceDown = (r[0].close < r[1].close) && (r[1].close >= r[2].close);

      if(cand > 0)
      {
         bool pulledBack = (r[1].low <= fastMA) || (rsi < 55.0);
         if(!(bounceUp && pulledBack && rsi >= 40.0 && rsi <= 72.0)) return false;
         dir = 1;
      }
      else
      {
         bool pulledBack = (r[1].high >= fastMA) || (rsi > 45.0);
         if(!(bounceDown && pulledBack && rsi <= 60.0 && rsi >= 28.0)) return false;
         dir = -1;
      }

      slDist = MathMax(atr * InpSL_ATR_Mult, SL_MIN_POINTS * g_cfg[idx].PointValue);
      tpDist = (InpTrendTP_R > 0.0) ? slDist * InpTrendTP_R : 0.0; // 0 => trail only

      double price = SymbolInfoDouble(sym, SYMBOL_BID);
      f0 = Clamp((double)(localTrend + htfTrend) / 2.0, -1.0, 1.0);
      f1 = (rsi - 50.0) / 50.0;
      f2 = Clamp((price - fastMA) / atr, -3.0, 3.0) / 3.0;
      f3 = bias;
      f4 = volRt;
      return true;
   }
   else
   {
      // ---- FlipX : z-score mean-reversion fader ----
      double mean = GetSMA(sym, InpSignalTF, InpMeanPeriod);
      if(mean <= 0.0) return false;
      double sd = GetStdDev(sym, InpSignalTF, InpMeanPeriod, mean);
      if(sd <= 0.0) return false;

      double price = SymbolInfoDouble(sym, SYMBOL_BID);
      double z = (price - mean) / sd;

      if(MathAbs(z) < InpZEntry) return false;       // not stretched enough
      if(MathAbs(z) > InpZMaxChase) return false;     // runaway - stand aside

      dir = (z <= -InpZEntry) ? 1 : -1;               // fade the deviation

      slDist = MathMax(atr * InpSL_ATR_Mult, SL_MIN_POINTS * g_cfg[idx].PointValue);
      tpDist = MathMax(MathAbs(price - mean), atr * 0.75); // target the mean

      f0 = 0.0;                                        // no persistent trend for FlipX
      f1 = (rsi - 50.0) / 50.0;
      f2 = Clamp(z, -3.0, 3.0) / 3.0;
      f3 = bias;
      f4 = volRt;
      return true;
   }
}

//======================================================================
// ACT — order execution
//======================================================================
bool OpenPosition(int idx, int direction, double lot, double sl, double tp, double slDist, double riskAmt, string tag)
{
   string sym = g_cfg[idx].Name;
   trade.SetExpertMagicNumber((ulong)(InpMagicBase + idx));
   trade.SetDeviationInPoints(TRADE_DEVIATION_POINTS);

   double price = (direction > 0) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   if(price <= 0.0) return false;

   bool ok = (direction > 0) ? trade.Buy(lot, sym, price, sl, tp, tag)
                             : trade.Sell(lot, sym, price, sl, tp, tag);
   if(!ok)
   {
      PrintFormat("WARN: order failed [%s] retcode=%d", sym, trade.ResultRetcode());
      return false;
   }

   ulong ticket = trade.ResultOrder();
   OpenTradeState st;
   st.Ticket = ticket; st.Idx = idx; st.RiskAmt = riskAmt;
   st.SlDistance = slDist; st.EntryPrice = price;
   st.IsPyramidLeg = false; st.PartialDone = false; st.BreakevenSet = false;
   PushOpenTradeState(st);

   g_cfg[idx].PyramidTickets[0] = ticket;
   g_cfg[idx].PyramidLevel = 0;

   if(InpEnableRecovery)
   {
      g_cfg[idx].BasketActive       = true;
      g_cfg[idx].BasketClosing      = false;
      g_cfg[idx].BasketDir          = direction;
      g_cfg[idx].BasketLevel        = 0;
      g_cfg[idx].BasketBaseLot      = lot;
      g_cfg[idx].BasketLastAddPrice = price;
      g_cfg[idx].BasketInitRisk     = riskAmt;
      g_cfg[idx].BasketRealizedPnL  = 0.0;
      g_cfg[idx].BasketPeakProfit   = 0.0;
   }

   PrintFormat("ENTRY [%s|%s] dir=%s lot=%.2f price=%.5f sl=%.5f tp=%.5f conf=%.3f",
               sym, TypeName(g_cfg[idx].Type), direction > 0 ? "BUY" : "SELL",
               lot, price, sl, tp, g_cfg[idx].LastOutput);
   return true;
}

void OpenPyramidAddon(int idx, ulong baseTicket, double addLotMult, int level)
{
   if(!InpEnablePyramid) return;
   if(g_cfg[idx].Engine != ENGINE_TREND) return; // pyramiding suits drift-riders, not mean-reversion
   if(!PositionSelectByTicket(baseTicket)) return;

   string sym = g_cfg[idx].Name;
   ENUM_POSITION_TYPE baseType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double baseVolume = PositionGetDouble(POSITION_VOLUME);
   double baseEntry  = PositionGetDouble(POSITION_PRICE_OPEN);
   double baseTP     = PositionGetDouble(POSITION_TP);

   double addLot = MathMax(baseVolume * addLotMult, g_cfg[idx].MinLot);
   addLot = MathFloor(addLot / g_cfg[idx].LotStep) * g_cfg[idx].LotStep;
   if(addLot < g_cfg[idx].MinLot) return;

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginReq = 0.0;
   double price = (baseType == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   ENUM_ORDER_TYPE ot = (baseType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(ot, sym, addLot, price, marginReq)) return;
   if(marginReq > freeMargin * MARGIN_USAGE_CAP_FRACTION) return;

   trade.SetExpertMagicNumber((ulong)(InpMagicBase + idx));
   trade.SetDeviationInPoints(TRADE_DEVIATION_POINTS);

   bool ok;
   if(g_hedgingMode)
      ok = (baseType == POSITION_TYPE_BUY) ? trade.Buy(addLot, sym, price, baseEntry, baseTP, "PyrL" + IntegerToString(level))
                                           : trade.Sell(addLot, sym, price, baseEntry, baseTP, "PyrL" + IntegerToString(level));
   else // netting: same-direction order merges into the base position
      ok = (baseType == POSITION_TYPE_BUY) ? trade.Buy(addLot, sym, price, 0, 0, "PyrL" + IntegerToString(level))
                                           : trade.Sell(addLot, sym, price, 0, 0, "PyrL" + IntegerToString(level));
   if(!ok) return;

   g_cfg[idx].PyramidLevel = level;
   if(g_hedgingMode)
   {
      ulong newTicket = trade.ResultOrder();
      g_cfg[idx].PyramidTickets[level] = newTicket;
      OpenTradeState st;
      st.Ticket = newTicket; st.Idx = idx;
      st.RiskAmt = PriceDistanceToMoney(idx, MathAbs(price - baseEntry), addLot);
      st.SlDistance = MathAbs(price - baseEntry); st.EntryPrice = price;
      st.IsPyramidLeg = true; st.PartialDone = false; st.BreakevenSet = false;
      PushOpenTradeState(st);
   }
   else
   {
      g_cfg[idx].PyramidTickets[level] = baseTicket;
      g_cfg[idx].PyramidAddedVolume += addLot;
   }
   PrintFormat("Pyramid L%d added [%s]", level, sym);
}

void CollapsePyramid(int idx, string reason)
{
   if(g_hedgingMode)
   {
      for(int lvl = 1; lvl < MAX_PYRAMID_LEVELS; lvl++)
      {
         ulong tk = g_cfg[idx].PyramidTickets[lvl];
         if(tk == 0) continue;
         if(PositionSelectByTicket(tk)) { trade.PositionClose(tk); RemoveOpenTradeState(tk); }
         g_cfg[idx].PyramidTickets[lvl] = 0;
      }
   }
   else if(g_cfg[idx].PyramidAddedVolume > 0.0)
   {
      ulong baseTicket = g_cfg[idx].PyramidTickets[0];
      if(baseTicket != 0 && PositionSelectByTicket(baseTicket))
      {
         double curVolume = PositionGetDouble(POSITION_VOLUME);
         double closeVol = MathMin(g_cfg[idx].PyramidAddedVolume, curVolume - g_cfg[idx].MinLot);
         closeVol = MathFloor(closeVol / g_cfg[idx].LotStep) * g_cfg[idx].LotStep;
         if(closeVol >= g_cfg[idx].MinLot) trade.PositionClosePartial(baseTicket, closeVol);
      }
      g_cfg[idx].PyramidAddedVolume = 0.0;
   }
   g_cfg[idx].PyramidLevel = 0;
   PrintFormat("Pyramid collapsed [%s] (%s)", g_cfg[idx].Name, reason);
}

//======================================================================
// GRID / BASKET RECOVERY (Medula trait)
//======================================================================
void ResetBasket(int idx)
{
   g_cfg[idx].BasketActive       = false;
   g_cfg[idx].BasketClosing      = false;
   g_cfg[idx].BasketDir          = 0;
   g_cfg[idx].BasketLevel        = 0;
   g_cfg[idx].BasketBaseLot      = 0.0;
   g_cfg[idx].BasketLastAddPrice = 0.0;
   g_cfg[idx].BasketInitRisk     = 0.0;
   g_cfg[idx].BasketRealizedPnL  = 0.0;
   g_cfg[idx].BasketPeakProfit   = 0.0;
}

void CloseBasket(int idx, string reason)
{
   long wantMagic = InpMagicBase + idx;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != wantMagic) continue;
      trade.PositionClose(ticket);
   }
   g_cfg[idx].BasketClosing = true; // finalized in ProcessTradeClose when flat
   PrintFormat("Basket close [%s] (%s) profit=%.2f level=%d",
               g_cfg[idx].Name, reason, ComputeBasketProfit(idx), g_cfg[idx].BasketLevel);
}

void AddGridLevel(int idx, int dir, double atr)
{
   string sym = g_cfg[idx].Name;
   int newLevel = g_cfg[idx].BasketLevel + 1;
   double lot = g_cfg[idx].BasketBaseLot * MathPow(InpGridLotFactor, newLevel);
   lot = MathFloor(lot / g_cfg[idx].LotStep) * g_cfg[idx].LotStep;
   lot = MathMin(lot, g_cfg[idx].MaxLot);
   if(lot < g_cfg[idx].MinLot) return;

   double price = (dir > 0) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginReq = 0.0;
   ENUM_ORDER_TYPE ot = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(ot, sym, lot, price, marginReq)) return;
   if(marginReq > freeMargin * MARGIN_USAGE_CAP_FRACTION) return; // out of margin - hold and let basket stops handle it

   trade.SetExpertMagicNumber((ulong)(InpMagicBase + idx));
   trade.SetDeviationInPoints(TRADE_DEVIATION_POINTS);
   bool ok = (dir > 0) ? trade.Buy(lot, sym, price, 0, 0, "GridL" + IntegerToString(newLevel))
                       : trade.Sell(lot, sym, price, 0, 0, "GridL" + IntegerToString(newLevel));
   if(!ok) { PrintFormat("WARN: grid add failed [%s] retcode=%d", sym, trade.ResultRetcode()); return; }

   ulong ticket = trade.ResultOrder();
   OpenTradeState st;
   st.Ticket = ticket; st.Idx = idx;
   st.RiskAmt = PriceDistanceToMoney(idx, atr * InpSL_ATR_Mult, lot); // notional risk for the portfolio governor
   st.SlDistance = atr * InpSL_ATR_Mult; st.EntryPrice = price;
   st.IsPyramidLeg = true; st.PartialDone = false; st.BreakevenSet = false;
   PushOpenTradeState(st);

   g_cfg[idx].BasketLevel = newLevel;
   g_cfg[idx].BasketLastAddPrice = price;
   PrintFormat("Grid L%d added [%s] lot=%.2f price=%.5f", newLevel, sym, lot, price);
}

void ManageBasket(int idx)
{
   if(!g_cfg[idx].Available) return;
   if(!HasOpenPosition(idx)) { if(g_cfg[idx].BasketActive) ResetBasket(idx); return; }
   if(g_cfg[idx].BasketClosing) return;          // waiting for async closes to complete
   if(!g_cfg[idx].BasketActive) return;          // basket state not established yet

   string sym = g_cfg[idx].Name;
   int dir = g_cfg[idx].BasketDir;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = ComputeBasketProfit(idx);

   // Basket take-profit / trailing.
   double target = g_cfg[idx].BasketInitRisk * InpBasketTP_R;
   if(target <= 0.0) target = equity * 0.01;
   if(profit >= target)
   {
      if(InpBasketTrailing)
      {
         if(profit > g_cfg[idx].BasketPeakProfit) g_cfg[idx].BasketPeakProfit = profit;
         if(profit <= g_cfg[idx].BasketPeakProfit * InpBasketTrailFrac) { CloseBasket(idx, "basket trail"); return; }
      }
      else { CloseBasket(idx, "basket TP"); return; }
   }

   // Hard basket max-loss cut (the safety net that replaces per-trade SLs).
   if(profit <= -equity * (InpMaxBasketLossPct / 100.0)) { CloseBasket(idx, "basket max-loss"); return; }

   // Martingale grid add on adverse excursion.
   if(g_cfg[idx].BasketLevel < InpMaxGridLevels)
   {
      double atr = GetATR(sym, InpSignalTF, ATR_PERIOD);
      if(atr <= 0.0) return;
      double price = (dir > 0) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      double adverse = (dir > 0) ? (g_cfg[idx].BasketLastAddPrice - price)
                                 : (price - g_cfg[idx].BasketLastAddPrice);
      if(adverse >= InpGridStepATR * atr) AddGridLevel(idx, dir, atr);
   }
}

//======================================================================
// DECIDE+ACT pipeline per symbol
//======================================================================
void ProcessSymbol(int idx)
{
   if(!g_cfg[idx].Available) return;
   string sym = g_cfg[idx].Name;

   // Once per new signal-TF bar.
   datetime bt = iTime(sym, InpSignalTF, 0);
   if(bt == 0 || bt == g_cfg[idx].LastBarTime) return;
   g_cfg[idx].LastBarTime = bt;

   if(g_ddKillSwitch) return;
   if(g_portfolioRiskBlocked) return;
   if(HasOpenPosition(idx)) return;                 // one basket per symbol; grid adds happen in management
   int activeCount = InpEnableRecovery ? CountActiveSymbols() : CountOpenManagedPositions();
   if(activeCount >= g_maxTrades) return;
   if(!IsSymbolTradeable(idx)) return;

   int dir; double slDist, tpDist, f0, f1, f2, f3, f4;
   if(!BuildSignal(idx, dir, slDist, tpDist, f0, f1, f2, f3, f4)) return;
   if(dir == 0 || slDist <= 0.0) return;

   // Neural confidence gate.
   double conf = 1.0;
   if(InpUseNNFilter)
   {
      conf = GetNNConfidence(idx, f0, f1, f2, f3, f4);
      if(conf < InpNNThreshold) return;
   }

   double riskAmt;
   double lot = CalculateLotSize(idx, slDist, riskAmt);
   if(lot <= 0.0) { PrintFormat("Lot below minimum - skip [%s]", sym); return; }

   if(ComputePortfolioRisk() + riskAmt > AccountInfoDouble(ACCOUNT_EQUITY) * PORTFOLIO_RISK_CAP_FRACTION)
      return;

   double entry = (dir > 0) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   // Recovery mode defends the basket instead of a hard per-trade SL, so the
   // initial leg carries no SL/TP; otherwise use the ATR stop and R-target.
   double sl = 0.0, tp = 0.0;
   if(!InpEnableRecovery)
   {
      sl = (dir > 0) ? entry - slDist : entry + slDist;
      if(tpDist > 0.0) tp = (dir > 0) ? entry + tpDist : entry - tpDist;
   }

   string tag = (g_cfg[idx].Engine == ENGINE_TREND) ? "Drift" : "Revert";
   OpenPosition(idx, dir, lot, sl, tp, slDist, riskAmt, tag);
}

//======================================================================
// POSITION MANAGEMENT
//======================================================================
void ManageOpenPositions()
{
   UpdatePortfolioRiskState();

   if(InpEnableRecovery)
   {
      for(int i = 0; i < g_symbolCount; i++) ManageBasket(i);
      return;
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic < InpMagicBase || magic >= InpMagicBase + g_symbolCount) continue;
      int idx = (int)(magic - InpMagicBase);

      string sym = PositionGetString(POSITION_SYMBOL);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double point = g_cfg[idx].PointValue;

      int stIdx = FindOpenTradeState(ticket);
      double riskAmt = (stIdx >= 0) ? g_openTrades[stIdx].RiskAmt : 0.0;
      double curPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID)
                                                     : SymbolInfoDouble(sym, SYMBOL_ASK);

      // Breakeven at 0.8R.
      if(riskAmt > 0.0 && profit >= riskAmt * BREAKEVEN_R_MULT &&
         stIdx >= 0 && !g_openTrades[stIdx].BreakevenSet)
      {
         double beSL = (type == POSITION_TYPE_BUY) ? entry + BREAKEVEN_BUFFER_POINTS * point
                                                    : entry - BREAKEVEN_BUFFER_POINTS * point;
         bool improves = (type == POSITION_TYPE_BUY) ? (beSL > curSL) : (curSL == 0.0 || beSL < curSL);
         if(improves) { trade.PositionModify(ticket, beSL, curTP); g_openTrades[stIdx].BreakevenSet = true; }
      }

      // Partial close at 1R.
      if(InpEnablePartial && riskAmt > 0.0 && profit >= riskAmt * PARTIAL_CLOSE_R_MULT &&
         stIdx >= 0 && !g_openTrades[stIdx].PartialDone)
      {
         double closeVol = MathFloor((volume * PARTIAL_CLOSE_FRACTION) / g_cfg[idx].LotStep) * g_cfg[idx].LotStep;
         closeVol = MathMax(closeVol, g_cfg[idx].MinLot);
         if(closeVol < volume)
         {
            trade.PositionClosePartial(ticket, closeVol);
            double beSL = (type == POSITION_TYPE_BUY) ? entry + BREAKEVEN_BUFFER_POINTS * point
                                                       : entry - BREAKEVEN_BUFFER_POINTS * point;
            trade.PositionModify(ticket, beSL, curTP);
            g_openTrades[stIdx].PartialDone = true;
            g_openTrades[stIdx].BreakevenSet = true;
            PrintFormat("Partial 50%% at 1R [%s]", sym);
         }
      }

      // Trailing beyond 1.5R (lock 50% of open profit distance).
      if(InpEnableTrailing && riskAmt > 0.0 && profit >= riskAmt * TRAIL_START_R_MULT)
      {
         double profitDist = MathAbs(curPrice - entry);
         double trailSL = (type == POSITION_TYPE_BUY) ? curPrice - profitDist * TRAIL_PROFIT_LOCK_FRACTION
                                                       : curPrice + profitDist * TRAIL_PROFIT_LOCK_FRACTION;
         bool improves = (type == POSITION_TYPE_BUY) ? (trailSL > curSL) : (curSL == 0.0 || trailSL < curSL);
         if(improves) trade.PositionModify(ticket, trailSL, curTP);
      }

      // Win-streak pyramiding (base legs of trend entities only).
      if(InpEnablePyramid && g_cfg[idx].Engine == ENGINE_TREND &&
         stIdx >= 0 && !g_openTrades[stIdx].IsPyramidLeg && profit > 0.0)
      {
         if(g_cfg[idx].ConsecutiveWins >= 2 && g_cfg[idx].PyramidLevel == 0)
            OpenPyramidAddon(idx, ticket, PYRAMID_L1_MULT, 1);
         else if(g_cfg[idx].ConsecutiveWins >= 3 && g_cfg[idx].PyramidLevel == 1)
            OpenPyramidAddon(idx, ticket, PYRAMID_L2_MULT, 2);
      }
   }
}

//======================================================================
// TRADE-CLOSE BOOKKEEPING
//======================================================================
// Records one outcome (single trade, or one whole basket in recovery mode):
// rolling win-rate, circuit breaker, drawdown recovery, NN update, tier reeval.
void RecordOutcome(int idx, double profit)
{
   string sym = g_cfg[idx].Name;

   int result = (profit > 0.0) ? 1 : 0;
   g_cfg[idx].RollingHistory[g_cfg[idx].HistoryIndex % ROLLING_HISTORY_SIZE] = result;
   g_cfg[idx].HistoryIndex++;
   if(g_cfg[idx].WinRateGuardCooldown > 0) g_cfg[idx].WinRateGuardCooldown--;

   int count;
   double wr = GetRollingWinRate(idx, count);
   if(count >= InpWinRateMinTrades && wr < (InpWinRateFloor / 100.0) && g_cfg[idx].WinRateGuardCooldown <= 0)
   {
      g_cfg[idx].WinRateGuardCooldown = WIN_RATE_UNBLOCK_TRADES;
      PrintFormat("Win-rate guard active [%s] wr=%.2f", sym, wr);
   }

   if(profit > 0.0)
   {
      g_cfg[idx].ConsecutiveLosses = 0;
      g_cfg[idx].ConsecutiveWins++;
   }
   else
   {
      g_cfg[idx].ConsecutiveWins = 0;
      g_cfg[idx].ConsecutiveLosses++;
      if(g_cfg[idx].ConsecutiveLosses >= InpCircuitLossCount)
      {
         g_cfg[idx].CircuitBreakerActive = true;
         g_cfg[idx].CircuitBreakerExpiry = TimeCurrent() + InpCircuitPauseMin * 60;
         PrintFormat("Circuit breaker engaged [%s] (%d consecutive losses)", sym, g_cfg[idx].ConsecutiveLosses);
      }
      if(g_cfg[idx].PyramidLevel > 0) CollapsePyramid(idx, "loss");
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_cfg[idx].PeakEquity) g_cfg[idx].PeakEquity = equity;
   if(g_cfg[idx].PeakEquity > 0.0)
   {
      double dd = (g_cfg[idx].PeakEquity - equity) / g_cfg[idx].PeakEquity;
      if(dd > DD_RECOVERY_TRIGGER_FRAC && !g_cfg[idx].InDrawdownRecovery)
      {
         g_cfg[idx].InDrawdownRecovery = true;
         PrintFormat("[%s] recovery mode - lots halved", sym);
      }
      else if(g_cfg[idx].InDrawdownRecovery && equity >= g_cfg[idx].PeakEquity * DD_RECOVERY_CLEAR_FRAC)
      {
         g_cfg[idx].InDrawdownRecovery = false;
         PrintFormat("[%s] recovery complete", sym);
      }
   }

   g_cfg[idx].TotalTrades++;
   if(profit > 0) g_cfg[idx].TotalWins++;
   UpdateWeights(idx, profit);

   g_totalClosedTrades++;
   if(g_totalClosedTrades % TIER_REEVAL_TRADE_INTERVAL == 0) RecalculateTier();
}

void ProcessTradeClose(int idx, double profit, ulong dealTicket)
{
   string sym = g_cfg[idx].Name;
   ulong posTicket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   RemoveOpenTradeState(posTicket);

   double closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   LogTradeClose(sym, closePrice, profit);
   g_cfg[idx].NetPnL += profit;

   if(InpEnableRecovery)
   {
      // Aggregate legs; score the basket once, when the symbol is flat again.
      g_cfg[idx].BasketRealizedPnL += profit;
      if(!HasOpenPosition(idx))
      {
         double basketPnL = g_cfg[idx].BasketRealizedPnL;
         PurgeOpenTradeStates(idx);   // clear any orphan grid-leg rows (netting)
         RecordOutcome(idx, basketPnL);
         ResetBasket(idx);
      }
      return;
   }

   RecordOutcome(idx, profit);
}

//======================================================================
// OPTIONAL SQLITE LOGGING
//======================================================================
bool OpenDatabase()
{
   if(!InpEnableSQLite) return true;
   g_dbHandle = DatabaseOpen(DB_FILENAME, DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE);
   if(g_dbHandle == INVALID_HANDLE) { PrintFormat("ERROR: DatabaseOpen failed err=%d", GetLastError()); return false; }
   bool ok = true;
   ok &= DatabaseExecute(g_dbHandle,
      "CREATE TABLE IF NOT EXISTS trades(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER,"
      " symbol TEXT, close_price REAL, pnl REAL, tier INTEGER)");
   ok &= DatabaseExecute(g_dbHandle,
      "CREATE TABLE IF NOT EXISTS equity_curve(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER,"
      " balance REAL, equity REAL, dd REAL, tier INTEGER)");
   return ok;
}

void LogTradeClose(string symbol, double closePrice, double pnl)
{
   if(!InpEnableSQLite || g_dbHandle == INVALID_HANDLE) return;
   string sql = StringFormat(
      "INSERT INTO trades(ts,symbol,close_price,pnl,tier) VALUES(%d,'%s',%.6f,%.2f,%d)",
      (int)TimeCurrent(), symbol, closePrice, pnl, g_currentTier);
   DatabaseExecute(g_dbHandle, sql);
}

void LogEquitySnapshotIfDue()
{
   if(!InpEnableSQLite || g_dbHandle == INVALID_HANDLE) return;
   if(TimeCurrent() - g_lastEquityLogTime < EQUITY_LOG_INTERVAL_SEC) return;
   g_lastEquityLogTime = TimeCurrent();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (g_globalPeakEquity > 0.0) ? (g_globalPeakEquity - equity) / g_globalPeakEquity : 0.0;
   string sql = StringFormat(
      "INSERT INTO equity_curve(ts,balance,equity,dd,tier) VALUES(%d,%.2f,%.2f,%.6f,%d)",
      (int)TimeCurrent(), balance, equity, dd, g_currentTier);
   DatabaseExecute(g_dbHandle, sql);
}

//======================================================================
// STARTUP
//======================================================================
bool InitSymbolConfig(int idx, string sym)
{
   ZeroMemory(g_cfg[idx]);
   g_cfg[idx].Name = sym;
   g_cfg[idx].PeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_cfg[idx].Type = ClassifySymbol(sym);
   g_cfg[idx].IndexMagnitude = ExtractMagnitude(sym);

   switch(g_cfg[idx].Type)
   {
      case SYNTH_GAINX: g_cfg[idx].Engine = ENGINE_TREND;   g_cfg[idx].DriftBias =  1; break;
      case SYNTH_PAINX: g_cfg[idx].Engine = ENGINE_TREND;   g_cfg[idx].DriftBias = -1; break;
      case SYNTH_FLIPX: g_cfg[idx].Engine = ENGINE_MEANREV; g_cfg[idx].DriftBias =  0; break;
      default:          g_cfg[idx].Engine = ENGINE_TREND;   g_cfg[idx].DriftBias =  0; break;
   }

   if(!SymbolSelect(sym, true))
   {
      PrintFormat("WARN: symbol %s not available on this broker - skipped", sym);
      g_cfg[idx].Available = false;
      return false;
   }
   double minLot   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotStep  = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double maxLot   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double point    = SymbolInfoDouble(sym, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue= SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   if(minLot <= 0.0 || lotStep <= 0.0 || point <= 0.0)
   {
      PrintFormat("WARN: symbol %s invalid specs - skipped", sym);
      g_cfg[idx].Available = false;
      return false;
   }
   g_cfg[idx].Available = true;
   g_cfg[idx].MinLot = minLot; g_cfg[idx].LotStep = lotStep; g_cfg[idx].MaxLot = maxLot;
   g_cfg[idx].PointValue = point; g_cfg[idx].TickSize = tickSize; g_cfg[idx].TickValue = tickValue;
   return true;
}

void ParseWatchlist()
{
   string parts[];
   ushort sep = StringGetCharacter(",", 0);
   int n = StringSplit(InpWatchlist, sep, parts);
   if(n <= 0) { g_symbolCount = 0; return; }

   ArrayResize(g_cfg, n);
   int keep = 0;
   for(int i = 0; i < n; i++)
   {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(StringLen(s) == 0) continue;
      g_cfg[keep].Name = s;      // provisional; InitSymbolConfig re-zeros & fills
      keep++;
   }
   g_symbolCount = keep;
   ArrayResize(g_cfg, g_symbolCount);
}

int OnInit()
{
   double effBalance = GetEffectiveBalance();
   PrintFormat("Account currency=%s effective_balance=%.2f leverage=%d",
               AccountInfoString(ACCOUNT_CURRENCY), effBalance, (int)AccountInfoInteger(ACCOUNT_LEVERAGE));
   if(effBalance < InpMinAccountUSD)
   {
      Print("CRITICAL: below minimum operational floor");
      return INIT_FAILED;
   }

   EvaluateTier(effBalance, g_currentTier, g_maxTrades, g_tierRiskPct);
   g_globalPeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_hedgingMode = ((int)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   ParseWatchlist();
   if(g_symbolCount <= 0) { Print("CRITICAL: watchlist empty"); return INIT_FAILED; }

   // Capture provisional names, then fully initialize each symbol.
   string names[];
   ArrayResize(names, g_symbolCount);
   for(int i = 0; i < g_symbolCount; i++) names[i] = g_cfg[i].Name;

   int available = 0;
   for(int i = 0; i < g_symbolCount; i++)
      if(InitSymbolConfig(i, names[i])) available++;

   ArrayResize(g_openTrades, 0);

   if(!LoadWeights()) InitializeWeights();
   OpenDatabase();

   EventSetTimer(InpTimerSeconds < 1 ? 1 : InpTimerSeconds);

   Print("=========== WeltradeSynthEA STARTUP ===========");
   PrintFormat("Tier %d | MaxTrades=%d RiskPct=%.2f | Margin=%s | NN=%s",
               g_currentTier, g_maxTrades, GetActiveRiskPct(),
               g_hedgingMode ? "HEDGING" : "NETTING", InpUseNNFilter ? "on" : "off");
   if(InpEnableRecovery)
      PrintFormat("Recovery (Medula) ON: gridStep=%.2fxATR lotFactor=%.2f maxLevels=%d basketTP=%.2fR maxBasketLoss=%.1f%%",
                  InpGridStepATR, InpGridLotFactor, InpMaxGridLevels, InpBasketTP_R, InpMaxBasketLossPct);
   else
      Print("Recovery (Medula) OFF: per-trade SL/TP with partial/breakeven/trailing/pyramid");
   for(int i = 0; i < g_symbolCount; i++)
      PrintFormat("  [%s] %s -> %s bias=%+d mag=%d %s",
                  g_cfg[i].Name, TypeName(g_cfg[i].Type),
                  g_cfg[i].Engine == ENGINE_TREND ? "TREND/drift-rider" : "MEAN-REVERSION",
                  g_cfg[i].DriftBias, g_cfg[i].IndexMagnitude,
                  g_cfg[i].Available ? "OK" : "UNAVAILABLE");
   PrintFormat("Symbols available: %d / %d | 24/7 (no session/news gating)", available, g_symbolCount);
   Print("===============================================");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   SaveWeights();
   if(g_dbHandle != INVALID_HANDLE) DatabaseClose(g_dbHandle);

   Print("=========== SESSION SUMMARY ===========");
   double totalPnL = 0.0;
   for(int i = 0; i < g_symbolCount; i++)
   {
      if(!g_cfg[i].Available) continue;
      double wr = (g_cfg[i].TotalTrades > 0) ? (double)g_cfg[i].TotalWins / g_cfg[i].TotalTrades * 100.0 : 0.0;
      PrintFormat("[%s|%s] trades=%d winrate=%.1f%% netPnL=%.2f",
                  g_cfg[i].Name, TypeName(g_cfg[i].Type), g_cfg[i].TotalTrades, wr, g_cfg[i].NetPnL);
      totalPnL += g_cfg[i].NetPnL;
   }
   PrintFormat("Net PnL: %.2f | Peak equity: %.2f | Final tier: %d", totalPnL, g_globalPeakEquity, g_currentTier);
   Print("=======================================");
}

//======================================================================
// EVENT HANDLERS — synthetics stream ticks 24/7; OnTimer drives every
// watchlist symbol regardless of which chart the EA is attached to.
//======================================================================
void RunCycle()
{
   RecalculateTier();
   UpdateDrawdownKillSwitch();
   ClearExpiredGuards();
   ManageOpenPositions();
   for(int i = 0; i < g_symbolCount; i++)
      ProcessSymbol(i);
   LogEquitySnapshotIfDue();
}

void OnTick()
{
   int idx = FindCfgIndex(_Symbol);
   if(idx >= 0) ProcessSymbol(idx);   // fast path for the attached chart symbol
   ManageOpenPositions();
}

void OnTimer()
{
   RunCycle();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY) return;

   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(magic < InpMagicBase || magic >= InpMagicBase + g_symbolCount) return;
   int idx = (int)(magic - InpMagicBase);

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   ProcessTradeClose(idx, profit, trans.deal);
}
//+------------------------------------------------------------------+
