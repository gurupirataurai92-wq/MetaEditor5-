//+------------------------------------------------------------------+
//|                    GoldPortfolioEA_V2_ArithmeticLogic.mq5         |
//|           Arithmetic-logic-driven volatility portfolio EA         |
//|         Price structure, risk geometry, confluence-based entries  |
//+------------------------------------------------------------------+
#property copyright "Quant Systems"
#property version   "2.00"
#property description "V2: Arithmetic-driven entry logic built on price structure "
#property description "(support/resistance, risk/reward geometry, fibonacci confluence), "
#property description "Kelly-criterion position sizing, and mathematical TP placement. "
#property description "Same multi-symbol tiering, NN signal filtering, and circuit "
#property description "breakers as V1, but entries now respect the mathematical logic "
#property description "of how gold/FX/commodities actually behave."

#include <Trade\Trade.mqh>

//======================================================================
// INPUT PARAMETERS
//======================================================================
input string Watchlist          = "EURUSD,GBPUSD,USDJPY,USDCHF,AUDUSD,NZDUSD,USDCAD,XAUUSD,XAGUSUSD,BTCUSD,ETHUSD,USOIL,UKOIL";
input double RiskPercent        = 1.0;
input double MinAccountUSD      = 2.0;
input int    MagicBase          = 20260714;
input bool   TradeAsian         = true;
input bool   TradeLondon        = true;
input bool   TradeNewYork       = true;
input bool   TradeOffHours      = true;
input double MinRiskRewardRatio = 1.5;      // DO NOT trade unless TP/SL ratio is at least 1.5:1
input bool   RequireConfluence  = true;      // require 2+ confluence signals before entry
input bool   EnableFibonacci    = true;      // trade fibonacci retracements as TP targets
input bool   EnableKellySizing  = true;      // use Kelly Criterion for position sizing
input bool   EnableSQLite       = true;
input bool   EnablePartialClose = true;
input bool   EnablePyramid      = true;
input bool   EnableCompounding  = true;
input double MaxDrawdownPct     = 10.0;
input int    WinRateMinTrades   = 20;
input double WinRateFloor       = 40.0;
input int    NewsBlackoutMins   = 5;
input double LearningRate       = 0.01;
input int    RankIntervalMins   = 15;
input double PyramidL1Mult      = 0.50;
input double PyramidL2Mult      = 0.25;

//======================================================================
// NAMED CONSTANTS
//======================================================================
#define WEIGHTS_FILENAME            "EAWeights.bin"
#define DB_FILENAME                 "QuantTickStorage.sqlite"
#define ATR_PERIOD                  14
#define ROLLING_HISTORY_SIZE        20
#define NN_INPUTS                   5
#define NN_HIDDEN                   8
#define MAX_PYRAMID_LEVELS          3
#define TICK_BUFFER_SIZE            500
#define TICK_VELOCITY_SAMPLES       5
#define TRADE_DEVIATION_POINTS      10
#define LATENCY_WARN_MICROSECONDS   500000
#define SPREAD_CEILING_ATR_FACTOR   0.30
#define M1_ATR_QUIET_FACTOR         0.10
#define M1_ATR_SPIKE_FACTOR         3.50
#define MARGIN_USAGE_CAP_FRACTION   0.20
#define PORTFOLIO_RISK_CAP_FRACTION 0.05
#define PORTFOLIO_RISK_RESUME_FRAC  0.03
#define WIN_RATE_UNBLOCK_TRADES     5
#define CIRCUIT_BREAKER_LOSS_COUNT  3
#define CIRCUIT_BREAKER_DURATION    86400
#define SPREAD_EMERGENCY_MULT       2.0
#define SPREAD_EMERGENCY_PAUSE_SEC  30
#define VOL_SPIKE_PAUSE_SEC         60
#define DD_RECOVERY_TRIGGER_FRAC    0.10
#define DD_RECOVERY_CLEAR_FRAC      0.95
#define TIER_REEVAL_TRADE_INTERVAL  10
#define RISK_ESCALATION_L1_FRAC     0.02
#define RISK_ESCALATION_L2_FRAC     0.05
#define RISK_ESCALATION_LOCK_FRAC   0.03
#define RISK_HARD_CAP_PCT           2.0
#define PARTIAL_CLOSE_R_MULT        1.0
#define PARTIAL_CLOSE_FRACTION      0.50
#define TRAIL_START_R_MULT          2.0
#define TRAIL_PROFIT_LOCK_FRACTION  0.50
#define FORCED_EXIT_TIMEOUT_SEC     600  // upgraded from 120s to 10min (more reasonable for scalp runners)
#define BREAKEVEN_SPREAD_FRACTION   0.50
#define BREAKEVEN_BUFFER_POINTS     1
#define MOMENTUM_TP_R_MULT          1.0
#define MOMENTUM_TP_CONF_MIN        0.80
#define TICK_LOG_BATCH_SIZE         10
#define EQUITY_LOG_INTERVAL_SEC     60
#define NN_CHECKPOINT_TRADE_INTERVAL 100
#define GOLD_SYMBOL                 "XAUUSD"
#define SL_MIN_POINTS               10
#define WEIGHT_INIT_RANGE           0.5
#define THRESH_ASIAN                0.96
#define THRESH_LONDON               0.91
#define THRESH_NY                   0.91
#define THRESH_OVERLAP              0.89
#define THRESH_OFFHOURS             0.95
#define FIBONACCI_236               0.236
#define FIBONACCI_382               0.382
#define FIBONACCI_500               0.500
#define FIBONACCI_618               0.618
#define FIBONACCI_786               0.786

//======================================================================
// STRUCTS
//======================================================================
struct VolatilityRank
{
   string Symbol;
   double VolScore;
   double SpreadScore;
   double FinalRank;
   bool   Selected;
};

struct PriceStructure
{
   double SwingHigh;
   double SwingLow;
   double StructureRange;
   double SupportLevel;
   double ResistanceLevel;
   double MidPoint;
   double Fib236, Fib382, Fib500, Fib618, Fib786;
   int    ConfluenceCount;  // how many signals align on this entry?
   bool   IsStructureValid;
};

struct SymbolConfig
{
   string   Name;
   bool     Available;
   bool     Selected;
   double   MinLot, LotStep, MaxLot;
   double   PointValue, TickSize, TickValue;
   double   SpreadCeiling;
   int      ConsecutiveLosses;
   int      ConsecutiveWins;
   int      RollingHistory[ROLLING_HISTORY_SIZE];
   int      HistoryIndex;
   int      RollingTradeCount;
   bool     CircuitBreakerActive;
   datetime CircuitBreakerExpiry;
   bool     InDrawdownRecovery;
   double   PeakEquity;
   double   DailyPnL;
   double   SessionPnL;
   int      PyramidLevel;
   ulong    PyramidTickets[MAX_PYRAMID_LEVELS];
   double   PyramidAddedVolume;
   datetime LastM1CandleTime;
   bool     LatencyFlag;
   int      LatencySkipCount;
   double   LastInput[NN_INPUTS];
   double   LastHidden[NN_HIDDEN];
   double   LastOutput;
   double   PriceHistory[TICK_VELOCITY_SAMPLES + 1];
   int      PriceHistoryCount;
   int      WinRateGuardCooldown;
   int      TotalTrades;
   int      TotalWins;
   double   NetPnL;
   bool     SpikePauseActive;
   datetime SpikePauseExpiry;
   bool     SpreadEmergencyActive;
   datetime SpreadEmergencyExpiry;
   double   KellyFraction;  // fraction of Kelly to use for sizing
};

struct OpenTradeState
{
   ulong  Ticket;
   int    Idx;
   double RiskAmt;
   double SlDistance;
   double EntryPrice;
   bool   IsPyramidLeg;
   bool   PartialDone;
   bool   BreakevenSet;
   bool   TpExtended;
};

//======================================================================
// GLOBALS
//======================================================================
CTrade            trade;
string            g_watchSymbols[];
SymbolConfig      g_cfg[];
VolatilityRank    g_rank[];
OpenTradeState    g_openTrades[];
int               g_symbolCount = 0;

int               g_currentTier   = 0;
int               g_maxTrades     = 0;
double            g_tierRiskPct   = 0.0;

matrix            g_W1(NN_INPUTS, NN_HIDDEN);
matrix            g_W2(NN_HIDDEN, 1);
vector            g_B1(NN_HIDDEN);
vector            g_B2(1);

int               g_dbHandle = INVALID_HANDLE;
int               g_tickLogCounter = 0;

datetime          g_lastRankTime      = 0;
datetime          g_lastEquityLogTime = 0;
datetime          g_sessionDay        = 0;

double            g_globalSessionPnL     = 0.0;
double            g_sessionStartBalance  = 0.0;
double            g_globalPeakEquity     = 0.0;

bool              g_hedgingMode = false;
int               g_totalClosedTrades = 0;
int               g_nnTotalTrades = 0;
int               g_nnWins = 0;
bool              g_portfolioRiskBlocked = false;

//======================================================================
// ENUMS
//======================================================================
enum ENUM_SESSION { SESSION_ASIAN, SESSION_LONDON, SESSION_NY, SESSION_OVERLAP, SESSION_OFFHOURS };

//======================================================================
// ARITHMETIC LOGIC: Price Structure Detection
//======================================================================

PriceStructure GetPriceStructure(string symbol, ENUM_TIMEFRAMES tf, int lookback)
{
   PriceStructure ps;
   ZeroMemory(ps);

   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   if(CopyRates(symbol, tf, 0, lookback, bars) < lookback)
   {
      ps.IsStructureValid = false;
      return ps;
   }

   // Find swing high and low over the lookback period
   ps.SwingHigh = bars[0].high;
   ps.SwingLow  = bars[0].low;
   for(int i = 0; i < lookback; i++)
   {
      ps.SwingHigh = MathMax(ps.SwingHigh, bars[i].high);
      ps.SwingLow  = MathMin(ps.SwingLow, bars[i].low);
   }

   ps.StructureRange = ps.SwingHigh - ps.SwingLow;
   if(ps.StructureRange <= 0.0)
   {
      ps.IsStructureValid = false;
      return ps;
   }

   ps.MidPoint = (ps.SwingHigh + ps.SwingLow) / 2.0;

   // Fibonacci retracement levels (measured from swing high DOWN to low, so levels are prices not%)
   ps.Fib786 = ps.SwingHigh - ps.StructureRange * FIBONACCI_786;
   ps.Fib618 = ps.SwingHigh - ps.StructureRange * FIBONACCI_618;
   ps.Fib500 = ps.MidPoint;
   ps.Fib382 = ps.SwingHigh - ps.StructureRange * FIBONACCI_382;
   ps.Fib236 = ps.SwingHigh - ps.StructureRange * FIBONACCI_236;

   // Support/Resistance (simple: current level proximity to swing highs/lows)
   double lastPrice = bars[0].close;
   ps.ResistanceLevel = ps.SwingHigh;
   ps.SupportLevel    = ps.SwingLow;

   ps.IsStructureValid = true;
   return ps;
}

// Count how many confluence signals align at this entry
int CountConfluence(string symbol, int htfBias, const PriceStructure &ps, double currentPrice)
{
   int confluence = 0;

   // Signal 1: price is within fib retracement zone (382-618)
   if(currentPrice >= ps.Fib382 && currentPrice <= ps.Fib618) confluence++;

   // Signal 2: HTF trend agrees with entry direction
   if(htfBias != 0) confluence++;

   // Signal 3: price is closer to support (buy) or resistance (sell) than midpoint
   if(htfBias > 0 && currentPrice < ps.MidPoint) confluence++;
   if(htfBias < 0 && currentPrice > ps.MidPoint) confluence++;

   // Signal 4: swing structure is recent and clear (range is meaningful)
   double h1ATR = GetATR(symbol, PERIOD_H1, ATR_PERIOD);
   if(ps.StructureRange > h1ATR * 0.50) confluence++;

   return confluence;
}

//======================================================================
// KELLY CRITERION SIZING
//======================================================================
double CalculateKellyFraction(SymbolConfig &cfg, int count)
{
   if(count < WinRateMinTrades) return 0.25; // conservative during ramp-up

   double wr = (double)cfg.TotalWins / (double)count;
   double lr = 1.0 - wr;

   // Kelly = (wr - lr) / 1.0 (assuming 1:1 risk/reward baseline; we adjust for actual RR)
   // But Kelly can be > 1, so we take a fraction: f = k * 0.25 (fractional Kelly)
   if(lr == 0.0) return 0.25; // protection
   double k = (wr - lr) / 1.0;
   if(k <= 0.0) return 0.10; // negative Kelly, use minimum
   return MathMin(k * 0.25, 0.50); // max 50% of Kelly, capped at 0.5 overall
}

//======================================================================
// RISK/REWARD VALIDATION
//======================================================================
bool ValidateRiskReward(double entry, double sl, double tp, int direction)
{
   if(direction > 0)
   {
      double riskDist   = entry - sl;
      double rewardDist = tp - entry;
      if(riskDist <= 0.0 || rewardDist <= 0.0) return false;
      double ratio = rewardDist / riskDist;
      return (ratio >= MinRiskRewardRatio);
   }
   else if(direction < 0)
   {
      double riskDist   = sl - entry;
      double rewardDist = entry - tp;
      if(riskDist <= 0.0 || rewardDist <= 0.0) return false;
      double ratio = rewardDist / riskDist;
      return (ratio >= MinRiskRewardRatio);
   }
   return false;
}

//======================================================================
// FIBONACCI-BASED TP PLACEMENT
//======================================================================
double GetFibonacciTP(string symbol, int direction, double entry, const PriceStructure &ps)
{
   if(!ps.IsStructureValid) return 0.0;

   if(direction > 0)
   {
      // Buying: target the next fib level above entry, or resistance
      if(entry < ps.Fib236) return ps.Fib236;
      if(entry < ps.Fib382) return ps.Fib382;
      if(entry < ps.Fib500) return ps.Fib500;
      if(entry < ps.Fib618) return ps.Fib618;
      return ps.Fib786; // or resistance
   }
   else
   {
      // Selling: target the next fib level below entry, or support
      if(entry > ps.Fib786) return ps.Fib786;
      if(entry > ps.Fib618) return ps.Fib618;
      if(entry > ps.Fib500) return ps.Fib500;
      if(entry > ps.Fib382) return ps.Fib382;
      return ps.Fib236; // or support
   }
}

//======================================================================
// HELPER: Sigmoid
//======================================================================
double Sigmoid(double x) { return 1.0 / (1.0 + MathExp(-x)); }

//======================================================================
// HELPER: ATR
//======================================================================
double GetATR(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   int need = period + 1;
   int copied = CopyRates(symbol, tf, 0, need, bars);
   if(copied < need) return 0.0;

   double sum = 0.0;
   for(int i = 0; i < period; i++)
   {
      double hi = bars[i].high;
      double lo = bars[i].low;
      double prevClose = bars[i + 1].close;
      double tr = MathMax(hi - lo, MathMax(MathAbs(hi - prevClose), MathAbs(lo - prevClose)));
      sum += tr;
   }
   return sum / period;
}

double GetSpreadCeiling(string symbol)
{
   double atr = GetATR(symbol, PERIOD_M15, ATR_PERIOD);
   if(atr <= 0.0)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      return point * 100.0;
   }
   return atr * SPREAD_CEILING_ATR_FACTOR;
}

//======================================================================
// INDEX LOOKUPS
//======================================================================
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

//======================================================================
// ACCOUNT TIER ENGINE
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
   if(effBalance < MinAccountUSD)         { tier = 0; maxTrades = 0; riskPct = 0.0; }
   else if(effBalance <= 4.99)            { tier = 1; maxTrades = 1; riskPct = 0.5; }
   else if(effBalance <= 9.99)            { tier = 2; maxTrades = 2; riskPct = 0.75; }
   else if(effBalance <= 49.99)           { tier = 3; maxTrades = 3; riskPct = 1.0; }
   else if(effBalance <= 199.99)          { tier = 4; maxTrades = 4; riskPct = 1.0; }
   else                                   { tier = 5; maxTrades = 5; riskPct = 1.0; }
}

void RecalculateTier()
{
   double effBalance = GetEffectiveBalance();
   int newTier; int newMax; double newRisk;
   EvaluateTier(effBalance, newTier, newMax, newRisk);

   if(newTier != g_currentTier)
      PrintFormat("TIER CHANGE: TIER%d -> TIER%d | EffBalance=%.2f", g_currentTier, newTier, effBalance);

   if(newMax < g_maxTrades)
   {
      int openCount = CountOpenManagedPositions();
      if(openCount > newMax)
         CloseWorstPositionForSymbolExcess(openCount - newMax);
   }

   g_currentTier = newTier;
   g_maxTrades   = newMax;
   g_tierRiskPct = newRisk;
}

int CountOpenManagedPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic >= MagicBase && magic < MagicBase + g_symbolCount) count++;
   }
   return count;
}

void CloseWorstPositionForSymbolExcess(int excessCount)
{
   for(int c = 0; c < excessCount; c++)
   {
      ulong worstTicket = 0;
      double worstProfit = DBL_MAX;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic < MagicBase || magic >= MagicBase + g_symbolCount) continue;
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit < worstProfit) { worstProfit = profit; worstTicket = ticket; }
      }
      if(worstTicket == 0) break;
      trade.PositionClose(worstTicket);
   }
}

//======================================================================
// NEURAL NETWORK (unchanged from V1)
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
   Print("Neural network initialized with random weights");
}

bool LoadWeights()
{
   if(!FileIsExist(WEIGHTS_FILENAME)) return false;
   int fh = FileOpen(WEIGHTS_FILENAME, FILE_READ | FILE_BIN);
   if(fh == INVALID_HANDLE) return false;
   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++)
         g_W1[i, j] = FileReadDouble(fh);
   for(int j = 0; j < NN_HIDDEN; j++)
      g_W2[j, 0] = FileReadDouble(fh);
   for(int j = 0; j < NN_HIDDEN; j++)
      g_B1[j] = FileReadDouble(fh);
   g_B2[0] = FileReadDouble(fh);
   FileClose(fh);
   Print("NN weights loaded");
   return true;
}

void SaveWeights()
{
   int fh = FileOpen(WEIGHTS_FILENAME, FILE_WRITE | FILE_BIN);
   if(fh == INVALID_HANDLE) return;
   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++)
         FileWriteDouble(fh, g_W1[i, j]);
   for(int j = 0; j < NN_HIDDEN; j++)
      FileWriteDouble(fh, g_W2[j, 0]);
   for(int j = 0; j < NN_HIDDEN; j++)
      FileWriteDouble(fh, g_B1[j]);
   FileWriteDouble(fh, g_B2[0]);
   FileClose(fh);
}

double GetNNConfidence(SymbolConfig &cfg, double deltaScore, double pressureProxy,
                        double velocityScore, double htfBias, double spreadRatio)
{
   double input[NN_INPUTS];
   input[0] = deltaScore;
   input[1] = pressureProxy;
   input[2] = velocityScore;
   input[3] = htfBias;
   input[4] = spreadRatio;

   double hidden[NN_HIDDEN];
   for(int j = 0; j < NN_HIDDEN; j++)
   {
      double sum = g_B1[j];
      for(int i = 0; i < NN_INPUTS; i++)
         sum += input[i] * g_W1[i, j];
      hidden[j] = Sigmoid(sum);
   }

   double outSum = g_B2[0];
   for(int j = 0; j < NN_HIDDEN; j++)
      outSum += hidden[j] * g_W2[j, 0];
   double output = Sigmoid(outSum);

   for(int i = 0; i < NN_INPUTS; i++) cfg.LastInput[i] = input[i];
   for(int j = 0; j < NN_HIDDEN; j++) cfg.LastHidden[j] = hidden[j];
   cfg.LastOutput = output;

   return output;
}

void UpdateWeights(SymbolConfig &cfg, double tradePnL)
{
   double target = (tradePnL > 0.0) ? 1.0 : 0.0;
   double output  = cfg.LastOutput;
   double err     = target - output;
   double dOut    = err * output * (1.0 - output);

   double dHidden[NN_HIDDEN];
   for(int j = 0; j < NN_HIDDEN; j++)
   {
      double h = cfg.LastHidden[j];
      dHidden[j] = dOut * g_W2[j, 0] * h * (1.0 - h);
   }

   for(int j = 0; j < NN_HIDDEN; j++)
      g_W2[j, 0] += LearningRate * cfg.LastHidden[j] * dOut;
   g_B2[0] += LearningRate * dOut;

   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++)
         g_W1[i, j] += LearningRate * cfg.LastInput[i] * dHidden[j];
   for(int j = 0; j < NN_HIDDEN; j++)
      g_B1[j] += LearningRate * dHidden[j];

   SaveWeights();
   g_nnTotalTrades++;
   if(tradePnL > 0) g_nnWins++;
}

//======================================================================
// TREND & VOLATILITY
//======================================================================
int GetHTFBias(string symbol)
{
   MqlRates h4[], h1[], m15[];
   ArraySetAsSeries(h4, true);
   ArraySetAsSeries(h1, true);
   ArraySetAsSeries(m15, true);

   if(CopyRates(symbol, PERIOD_H4, 0, 3, h4) < 3) return 0;
   if(CopyRates(symbol, PERIOD_H1, 0, 5, h1) < 5) return 0;
   if(CopyRates(symbol, PERIOD_M15, 0, 4, m15) < 4) return 0;

   bool h4Bull = h4[0].close > h4[2].close;
   bool h4Bear = h4[0].close < h4[2].close;

   double hi = h1[0].high, lo = h1[0].low;
   for(int i = 1; i < 5; i++) { hi = MathMax(hi, h1[i].high); lo = MathMin(lo, h1[i].low); }
   double h1Mid = (hi + lo) / 2.0;
   bool h1Bull = h1[0].close > h1Mid;
   bool h1Bear = h1[0].close < h1Mid;

   bool m15Bull = m15[0].close > m15[3].open;
   bool m15Bear = m15[0].close < m15[3].open;

   int bullScore = (h4Bull ? 1 : 0) + (h1Bull ? 1 : 0) + (m15Bull ? 1 : 0);
   int bearScore = (h4Bear ? 1 : 0) + (h1Bear ? 1 : 0) + (m15Bear ? 1 : 0);

   if(bullScore >= 2) return 1;
   if(bearScore >= 2) return -1;
   return 0;
}

bool VolatilityGatePass(string symbol)
{
   double m1ATR = GetATR(symbol, PERIOD_M1, ATR_PERIOD);
   double h1ATR = GetATR(symbol, PERIOD_H1, ATR_PERIOD);
   if(h1ATR <= 0.0 || m1ATR <= 0.0) return false;
   if(m1ATR < h1ATR * M1_ATR_QUIET_FACTOR) return false;
   if(m1ATR > h1ATR * M1_ATR_SPIKE_FACTOR) return false;
   return true;
}

//======================================================================
// M1 MICROSTRUCTURE (simplified from V1)
//======================================================================
double GetTickDeltaScore(string symbol)
{
   MqlTick ticks[];
   int copied = CopyTicks(symbol, ticks, COPY_TICKS_ALL, 0, TICK_BUFFER_SIZE);
   if(copied <= 0) return 0.0;

   int buyVol = 0, sellVol = 0;
   for(int i = 0; i < copied; i++)
   {
      if(ticks[i].last > 0.0)
      {
         if(ticks[i].last >= ticks[i].ask) buyVol++;
         else if(ticks[i].last <= ticks[i].bid) sellVol++;
      }
   }
   return (double)(buyVol - sellVol) / (double)(buyVol + sellVol + 1);
}

double GetCandlePressure(string symbol)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(symbol, PERIOD_M1, 0, 2, r) < 2) return 0.0;
   double range = r[1].high - r[1].low;
   if(range <= 0.0) return 0.0;
   return (r[1].close - r[1].open) / range;
}

bool M1CandleConfirmation(string symbol, int direction)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(symbol, PERIOD_M1, 0, 2, r) < 2) return false;
   double range = r[1].high - r[1].low;
   if(range <= 0.0) return false;
   double body = MathAbs(r[1].close - r[1].open);
   if(body / range <= 0.30) return false;

   if(direction > 0) return r[1].close > r[1].open;
   if(direction < 0) return r[1].close < r[1].open;
   return false;
}

void UpdateTickVelocity(SymbolConfig &cfg, double currentPrice)
{
   int n = TICK_VELOCITY_SAMPLES + 1;
   for(int i = n - 1; i > 0; i--)
      cfg.PriceHistory[i] = cfg.PriceHistory[i - 1];
   cfg.PriceHistory[0] = currentPrice;
   if(cfg.PriceHistoryCount < n) cfg.PriceHistoryCount++;
}

double GetTickVelocityScore(SymbolConfig &cfg, string symbol)
{
   if(cfg.PriceHistoryCount < 2) return 0.0;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0) return 0.0;
   double sum = 0.0;
   int samples = cfg.PriceHistoryCount - 1;
   for(int i = 0; i < samples; i++)
      sum += MathAbs(cfg.PriceHistory[i] - cfg.PriceHistory[i + 1]);
   double avgChange = sum / samples;
   return (avgChange / point) / 100.0;
}

double GetSpreadRatio(string symbol)
{
   long spreadPts = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double spread = spreadPts * point;
   double m1ATR = GetATR(symbol, PERIOD_M1, ATR_PERIOD);
   if(m1ATR <= 0.0) return 0.0;
   return spread / m1ATR;
}

//======================================================================
// NEWS BLACKOUT (Economic Calendar)
//======================================================================
bool IsAlgorithmicNFPWindow()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(dt.day_of_week != 5) return false;
   if(dt.day > 7) return false;
   int minutesOfDay = dt.hour * 60 + dt.min;
   int startMin = 12 * 60 + 25 - NewsBlackoutMins;
   int endMin   = 13 * 60 + NewsBlackoutMins;
   return (minutesOfDay >= startMin && minutesOfDay <= endMin);
}

bool InNewsBlackout()
{
   if(IsAlgorithmicNFPWindow()) return true;

   MqlCalendarValue values[];
   datetime from = TimeCurrent() - 12 * 3600;
   datetime to   = TimeCurrent() + 12 * 3600;
   int total = CalendarValueHistory(values, from, to, NULL, "USD");
   if(total <= 0) return false;

   int windowSec = NewsBlackoutMins * 60;
   for(int i = 0; i < total; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      datetime evTime = values[i].time;
      if(TimeCurrent() >= evTime - windowSec && TimeCurrent() <= evTime + windowSec)
         return true;
   }
   return false;
}

//======================================================================
// SESSIONS
//======================================================================
ENUM_SESSION GetCurrentSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;
   if(hour >= 12 && hour < 14) return SESSION_OVERLAP;
   if(hour >= 0 && hour < 7)   return SESSION_ASIAN;
   if(hour >= 7 && hour < 12)  return SESSION_LONDON;
   if(hour >= 12 && hour < 17) return SESSION_NY;
   return SESSION_OFFHOURS;
}

double GetSignalThreshold(ENUM_SESSION s)
{
   switch(s)
   {
      case SESSION_ASIAN:   return THRESH_ASIAN;
      case SESSION_LONDON:  return THRESH_LONDON;
      case SESSION_NY:      return THRESH_NY;
      case SESSION_OVERLAP: return THRESH_OVERLAP;
      default:              return THRESH_OFFHOURS;
   }
}

bool IsSessionTradingAllowed(ENUM_SESSION s)
{
   switch(s)
   {
      case SESSION_ASIAN:   return TradeAsian;
      case SESSION_LONDON:  return TradeLondon;
      case SESSION_OVERLAP: return (TradeLondon || TradeNewYork);
      case SESSION_NY:      return TradeNewYork;
      default:              return TradeOffHours;
   }
}

//======================================================================
// CIRCUIT BREAKERS & GUARDS
//======================================================================
void ClearExpiredCircuitBreakers()
{
   for(int i = 0; i < g_symbolCount; i++)
   {
      if(g_cfg[i].CircuitBreakerActive && TimeCurrent() >= g_cfg[i].CircuitBreakerExpiry)
      {
         g_cfg[i].CircuitBreakerActive = false;
         g_cfg[i].ConsecutiveLosses = 0;
      }
      if(g_cfg[i].SpikePauseActive && TimeCurrent() >= g_cfg[i].SpikePauseExpiry)
         g_cfg[i].SpikePauseActive = false;
      if(g_cfg[i].SpreadEmergencyActive && TimeCurrent() >= g_cfg[i].SpreadEmergencyExpiry)
         g_cfg[i].SpreadEmergencyActive = false;
   }
}

double GetRollingWinRate(SymbolConfig &cfg, int &count)
{
   count = MathMin(cfg.HistoryIndex, ROLLING_HISTORY_SIZE);
   if(count <= 0) return 1.0;
   int wins = 0;
   for(int i = 0; i < count; i++) wins += cfg.RollingHistory[i];
   return (double)wins / (double)count;
}

double ComputePortfolioRisk()
{
   double totalRisk = 0.0;
   for(int i = 0; i < ArraySize(g_openTrades); i++)
      totalRisk += g_openTrades[i].RiskAmt;
   return totalRisk;
}

void UpdatePortfolioRiskState()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0) return;
   double risk = ComputePortfolioRisk();

   if(!g_portfolioRiskBlocked && risk > equity * PORTFOLIO_RISK_CAP_FRACTION)
   {
      g_portfolioRiskBlocked = true;
      PrintFormat("Portfolio risk governor: new entries blocked (risk=%.2f > %.2f%% equity)",
                  risk, PORTFOLIO_RISK_CAP_FRACTION * 100.0);
   }
   else if(g_portfolioRiskBlocked && risk < equity * PORTFOLIO_RISK_RESUME_FRAC)
   {
      g_portfolioRiskBlocked = false;
      PrintFormat("Portfolio risk governor: resumed (risk=%.2f < %.2f%% equity)",
                  risk, PORTFOLIO_RISK_RESUME_FRAC * 100.0);
   }
}

bool IsSymbolTradeable(int idx)
{
   SymbolConfig cfg = g_cfg[idx];
   if(!cfg.Available) return false;
   if(!cfg.Selected) return false;
   if(cfg.CircuitBreakerActive) return false;
   if(cfg.SpikePauseActive) return false;
   if(cfg.SpreadEmergencyActive) return false;
   if(cfg.LatencyFlag) return false;

   double spread = SymbolInfoInteger(cfg.Name, SYMBOL_SPREAD) * cfg.PointValue;
   if(spread > cfg.SpreadCeiling) return false;
   if(spread > cfg.SpreadCeiling * SPREAD_EMERGENCY_MULT)
   {
      g_cfg[idx].SpreadEmergencyActive = true;
      g_cfg[idx].SpreadEmergencyExpiry = TimeCurrent() + SPREAD_EMERGENCY_PAUSE_SEC;
      return false;
   }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginReq = 0.0;
   if(freeMargin > 0.0 &&
      OrderCalcMargin(ORDER_TYPE_BUY, cfg.Name, cfg.MinLot,
                       SymbolInfoDouble(cfg.Name, SYMBOL_ASK), marginReq))
   {
      if(marginReq > freeMargin * MARGIN_USAGE_CAP_FRACTION) return false;
   }

   if(cfg.WinRateGuardCooldown > 0) return false;
   if(InNewsBlackout()) return false;

   return true;
}

//======================================================================
// MONEY CONVERSION HELPERS
//======================================================================
double GetPointValueMoney(int idx)
{
   SymbolConfig cfg = g_cfg[idx];
   if(cfg.TickSize <= 0.0 || cfg.TickValue <= 0.0) return 0.0;
   return (cfg.TickValue / cfg.TickSize) * cfg.PointValue;
}

double PriceDistanceToMoney(int idx, double priceDist, double volume)
{
   double point = g_cfg[idx].PointValue;
   if(point <= 0.0) return 0.0;
   double ptVal = GetPointValueMoney(idx);
   return (priceDist / point) * ptVal * volume;
}

//======================================================================
// LOT SIZING (now with Kelly Criterion option)
//======================================================================
double CalculateLotSize(int idx, double activeRiskPct, double slDist, double &riskAmtOut)
{
   SymbolConfig cfg = g_cfg[idx];
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt = equity * (activeRiskPct / 100.0);

   // Apply Kelly fraction if enabled
   if(EnableKellySizing)
   {
      int count;
      double wr = GetRollingWinRate(cfg, count);
      cfg.KellyFraction = CalculateKellyFraction(cfg, count);
      riskAmt *= cfg.KellyFraction;
   }

   riskAmtOut = riskAmt;

   double ptVal = GetPointValueMoney(idx);
   if(ptVal <= 0.0 || slDist <= 0.0) return 0.0;

   double rawLot = riskAmt / (slDist / cfg.PointValue * ptVal);
   double lotStep = cfg.LotStep;
   double minLot  = cfg.MinLot;
   double maxLot  = cfg.MaxLot;
   if(lotStep <= 0.0) return 0.0;

   double finalLot = MathFloor(rawLot / lotStep) * lotStep;
   finalLot = MathMax(finalLot, minLot);
   finalLot = MathMin(finalLot, maxLot);

   if(cfg.InDrawdownRecovery)
      finalLot = MathMax(finalLot * 0.5, minLot);

   if(finalLot < minLot) return 0.0;
   return finalLot;
}

double GetActiveRiskPct()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0) return g_tierRiskPct;
   double pnlFrac = g_globalSessionPnL / balance;

   double activeRisk = g_tierRiskPct;
   if(pnlFrac > RISK_ESCALATION_LOCK_FRAC)      activeRisk = g_tierRiskPct * 0.5;
   else if(pnlFrac > RISK_ESCALATION_L2_FRAC)   activeRisk = g_tierRiskPct * 2.0;
   else if(pnlFrac > RISK_ESCALATION_L1_FRAC)   activeRisk = g_tierRiskPct * 1.5;

   return MathMin(activeRisk, RISK_HARD_CAP_PCT);
}

//======================================================================
// PYRAMID COLLAPSE & ADD-ON
//======================================================================
void CollapsePyramid(int idx, string reason)
{
   SymbolConfig cfg = g_cfg[idx];
   if(g_hedgingMode)
   {
      for(int lvl = 1; lvl < MAX_PYRAMID_LEVELS; lvl++)
      {
         ulong tk = cfg.PyramidTickets[lvl];
         if(tk == 0) continue;
         if(PositionSelectByTicket(tk))
         {
            trade.PositionClose(tk);
            RemoveOpenTradeState(tk);
         }
         g_cfg[idx].PyramidTickets[lvl] = 0;
      }
   }
   else if(cfg.PyramidAddedVolume > 0.0)
   {
      ulong baseTicket = cfg.PyramidTickets[0];
      if(baseTicket != 0 && PositionSelectByTicket(baseTicket))
      {
         double curVolume = PositionGetDouble(POSITION_VOLUME);
         double closeVol = MathMin(cfg.PyramidAddedVolume, curVolume - cfg.MinLot);
         closeVol = MathFloor(closeVol / cfg.LotStep) * cfg.LotStep;
         if(closeVol >= cfg.MinLot)
            trade.PositionClosePartial(baseTicket, closeVol);
      }
      g_cfg[idx].PyramidAddedVolume = 0.0;
   }
   g_cfg[idx].PyramidLevel = 0;
   PrintFormat("Pyramid collapsed - [%s] (%s)", cfg.Name, reason);
}

void OpenPyramidAddon(int idx, ulong baseTicket, double addLotMult, int level, double addTPMult)
{
   if(!EnablePyramid) return;
   if(!PositionSelectByTicket(baseTicket)) return;

   SymbolConfig cfg = g_cfg[idx];
   string sym = cfg.Name;
   ENUM_POSITION_TYPE baseType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double baseVolume = PositionGetDouble(POSITION_VOLUME);
   double baseEntry  = PositionGetDouble(POSITION_PRICE_OPEN);
   double baseTP     = PositionGetDouble(POSITION_TP);

   double addLot = MathMax(baseVolume * addLotMult, cfg.MinLot);
   addLot = MathFloor(addLot / cfg.LotStep) * cfg.LotStep;
   if(addLot < cfg.MinLot) return;

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginReq = 0.0;
   double price = (baseType == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   ENUM_ORDER_TYPE ot = (baseType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(ot, sym, addLot, price, marginReq)) return;
   if(marginReq > freeMargin * MARGIN_USAGE_CAP_FRACTION) return;

   trade.SetExpertMagicNumber((ulong)(MagicBase + idx));
   trade.SetDeviationInPoints(TRADE_DEVIATION_POINTS);

   double addTP = (baseTP > 0.0) ? baseTP : 0.0;
   if(addTP > 0.0)
   {
      double dist = MathAbs(addTP - baseEntry) * addTPMult;
      addTP = (baseType == POSITION_TYPE_BUY) ? baseEntry + dist : baseEntry - dist;
   }

   bool ok;
   if(g_hedgingMode)
      ok = (baseType == POSITION_TYPE_BUY) ? trade.Buy(addLot, sym, price, baseEntry, addTP, "PyramidL" + IntegerToString(level))
                                            : trade.Sell(addLot, sym, price, baseEntry, addTP, "PyramidL" + IntegerToString(level));
   else
      ok = (baseType == POSITION_TYPE_BUY) ? trade.Buy(addLot, sym, price, 0, 0, "PyramidL" + IntegerToString(level))
                                            : trade.Sell(addLot, sym, price, 0, 0, "PyramidL" + IntegerToString(level));

   if(!ok) return;

   g_cfg[idx].PyramidLevel = level;
   if(g_hedgingMode)
   {
      ulong newTicket = trade.ResultOrder();
      g_cfg[idx].PyramidTickets[level] = newTicket;
      OpenTradeState st;
      st.Ticket = newTicket; st.Idx = idx;
      st.RiskAmt = PriceDistanceToMoney(idx, MathAbs(price - baseEntry), addLot);
      st.SlDistance = MathAbs(price - baseEntry); st.EntryPrice = price; st.IsPyramidLeg = true;
      st.PartialDone = false; st.BreakevenSet = false; st.TpExtended = false;
      PushOpenTradeState(st);
   }
   else
   {
      g_cfg[idx].PyramidTickets[level] = baseTicket;
      g_cfg[idx].PyramidAddedVolume += addLot;
   }
   PrintFormat("Pyramid L%d opened - [%s]", level, sym);
}

bool OpenPosition(int idx, int direction, double lot, double sl, double tp, double riskAmt)
{
   SymbolConfig cfg = g_cfg[idx];
   string sym = cfg.Name;
   trade.SetExpertMagicNumber((ulong)(MagicBase + idx));
   trade.SetDeviationInPoints(TRADE_DEVIATION_POINTS);

   double price = (direction > 0) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   if(price <= 0.0) return false;

   ulong t0 = GetMicrosecondCount();
   bool ok = (direction > 0) ? trade.Buy(lot, sym, price, sl, tp, "Arithmetic-Entry")
                              : trade.Sell(lot, sym, price, sl, tp, "Arithmetic-Entry");
   ulong latency = GetMicrosecondCount() - t0;

   if(latency > LATENCY_WARN_MICROSECONDS)
   {
      g_cfg[idx].LatencyFlag = true;
      g_cfg[idx].LatencySkipCount = 5;
   }

   if(!ok) return false;

   ulong ticket = trade.ResultOrder();
   OpenTradeState st;
   st.Ticket = ticket; st.Idx = idx; st.RiskAmt = riskAmt;
   st.SlDistance = MathAbs(price - sl); st.EntryPrice = price;
   st.IsPyramidLeg = false; st.PartialDone = false; st.BreakevenSet = false; st.TpExtended = false;
   PushOpenTradeState(st);

   g_cfg[idx].PyramidTickets[0] = ticket;
   g_cfg[idx].PyramidLevel = 0;

   PrintFormat("Entry [%s] dir=%s lot=%.2f price=%.5f sl=%.5f tp=%.5f (RR=%.2f:1)",
               sym, direction > 0 ? "BUY" : "SELL", lot, price, sl, tp,
               MathAbs(tp - price) / MathAbs(price - sl));
   return true;
}

//======================================================================
// CORE: ARITHMETIC-DRIVEN SIGNAL PIPELINE
//======================================================================
void ProcessSymbol(int idx)
{
   SymbolConfig cfgSnap = g_cfg[idx];
   string sym = cfgSnap.Name;
   if(!cfgSnap.Available || !cfgSnap.Selected) return;

   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(bid <= 0.0) return;
   UpdateTickVelocity(g_cfg[idx], bid);

   datetime m1Time = iTime(sym, PERIOD_M1, 0);
   if(m1Time == 0 || m1Time == g_cfg[idx].LastM1CandleTime) return;
   g_cfg[idx].LastM1CandleTime = m1Time;

   double m1ATR = GetATR(sym, PERIOD_M1, ATR_PERIOD);
   double h1ATR = GetATR(sym, PERIOD_H1, ATR_PERIOD);
   if(h1ATR > 0.0 && m1ATR > h1ATR * M1_ATR_SPIKE_FACTOR)
   {
      g_cfg[idx].SpikePauseActive = true;
      g_cfg[idx].SpikePauseExpiry = TimeCurrent() + VOL_SPIKE_PAUSE_SEC;
      return;
   }

   if(g_cfg[idx].LatencySkipCount > 0)
   {
      g_cfg[idx].LatencySkipCount--;
      if(g_cfg[idx].LatencySkipCount == 0) g_cfg[idx].LatencyFlag = false;
      return;
   }

   if(!VolatilityGatePass(sym)) return;

   ENUM_SESSION session = GetCurrentSession();
   if(!IsSessionTradingAllowed(session)) return;

   // ===== ARITHMETIC LOGIC PIPELINE =====
   // 1. Get price structure (swings, fibs, support/resistance)
   PriceStructure ps = GetPriceStructure(sym, PERIOD_H1, 20);
   if(!ps.IsStructureValid) return;

   // 2. Get HTF trend bias
   int htfBias = GetHTFBias(sym);
   if(htfBias == 0) return;

   // 3. Check confluence - multiple signals must align
   int confluence = CountConfluence(sym, htfBias, ps, bid);
   if(RequireConfluence && confluence < 2) return;

   // 4. M1 candle confirmation
   if(!M1CandleConfirmation(sym, htfBias)) return;

   // 5. Microstructure signals (NN input)
   double deltaScore   = GetTickDeltaScore(sym);
   double pressureProxy = GetCandlePressure(sym);
   double velocityScore = GetTickVelocityScore(g_cfg[idx], sym);
   double spreadRatio   = GetSpreadRatio(sym);

   // 6. Neural net confidence gate
   double confidence = GetNNConfidence(g_cfg[idx], deltaScore, pressureProxy, velocityScore, (double)htfBias, spreadRatio);
   double threshold = GetSignalThreshold(session);
   if(confidence < threshold) return;

   // 7. ARITHMETIC: Fibonacci TP (not arbitrary ATR multiple)
   double fib_tp = EnableFibonacci ? GetFibonacciTP(sym, htfBias, bid, ps) : 0.0;
   if(fib_tp <= 0.0 && !EnableFibonacci)
   {
      // Fallback: use structure-based TP
      fib_tp = (htfBias > 0) ? ps.Fib618 : ps.Fib382;
   }

   // 8. SL placement: just beyond the swing that justifies the trade
   double sl = (htfBias > 0) ? (ps.SupportLevel - SL_MIN_POINTS * g_cfg[idx].PointValue)
                              : (ps.ResistanceLevel + SL_MIN_POINTS * g_cfg[idx].PointValue);

   // 9. Validate risk/reward ratio BEFORE entry
   if(!ValidateRiskReward(bid, sl, fib_tp, htfBias))
   {
      PrintFormat("Entry rejected - [%s] RR ratio %.2f:1 < %.2f:1 required",
                  sym, MathAbs(fib_tp - bid) / MathAbs(bid - sl), MinRiskRewardRatio);
      return;
   }

   // 10. Pre-flight checks
   if(!IsSymbolTradeable(idx)) return;
   if(CountOpenManagedPositions() >= g_maxTrades) return;
   if(g_portfolioRiskBlocked) return;

   // 11. Kelly-adjusted lot sizing
   double slDist = MathAbs(bid - sl);
   double riskAmt;
   double activeRisk = GetActiveRiskPct();
   double lot = CalculateLotSize(idx, activeRisk, slDist, riskAmt);
   if(lot <= 0.0) return;

   if(ComputePortfolioRisk() + riskAmt > AccountInfoDouble(ACCOUNT_EQUITY) * PORTFOLIO_RISK_CAP_FRACTION)
      return;

   // 12. OPEN
   OpenPosition(idx, htfBias, lot, sl, fib_tp, riskAmt);
}

//======================================================================
// POSITION MANAGEMENT (largely unchanged from V1)
//======================================================================
void ManageOpenPositions()
{
   UpdatePortfolioRiskState();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic < MagicBase || magic >= MagicBase + g_symbolCount) continue;
      int idx = (int)(magic - MagicBase);
      if(idx < 0 || idx >= g_symbolCount) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double point = g_cfg[idx].PointValue;

      int stIdx = FindOpenTradeState(ticket);
      double riskAmt = (stIdx >= 0) ? g_openTrades[stIdx].RiskAmt : 0.0;

      // UPGRADED: timeout now conditional (close only if losing)
      if(TimeCurrent() - openTime >= FORCED_EXIT_TIMEOUT_SEC)
      {
         if(profit <= 0.0)
         {
            trade.PositionClose(ticket);
            RemoveOpenTradeState(ticket);
            PrintFormat("Timeout exit (losing) - [%s]", sym);
         }
         // else: trade is profitable, let trailing stop / TP handle it
         continue;
      }

      double curPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      double spread = SymbolInfoInteger(sym, SYMBOL_SPREAD) * point;

      // Breakeven floor
      double breakevenTrigger = PriceDistanceToMoney(idx, spread, volume) * BREAKEVEN_SPREAD_FRACTION;
      if(profit >= breakevenTrigger && stIdx >= 0 && !g_openTrades[stIdx].BreakevenSet)
      {
         double beSL = (type == POSITION_TYPE_BUY) ? entry + BREAKEVEN_BUFFER_POINTS * point
                                                     : entry - BREAKEVEN_BUFFER_POINTS * point;
         bool improves = (type == POSITION_TYPE_BUY) ? (beSL > curSL) : (curSL == 0 || beSL < curSL);
         if(improves)
         {
            trade.PositionModify(ticket, beSL, curTP);
            g_openTrades[stIdx].BreakevenSet = true;
         }
      }

      // Partial close at 1R
      if(riskAmt > 0.0 && profit >= riskAmt * PARTIAL_CLOSE_R_MULT && EnablePartialClose &&
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
         }
      }

      // Trailing stop at 2R
      if(riskAmt > 0.0 && profit >= riskAmt * TRAIL_START_R_MULT)
      {
         double profitDist = MathAbs(curPrice - entry);
         double trailSL = (type == POSITION_TYPE_BUY) ? curPrice - profitDist * TRAIL_PROFIT_LOCK_FRACTION
                                                        : curPrice + profitDist * TRAIL_PROFIT_LOCK_FRACTION;
         bool improves = (type == POSITION_TYPE_BUY) ? (trailSL > curSL) : (curSL == 0 || trailSL < curSL);
         if(improves) trade.PositionModify(ticket, trailSL, curTP);
      }

      // Momentum TP extension
      if(riskAmt > 0.0 && profit >= riskAmt && stIdx >= 0 && !g_openTrades[stIdx].TpExtended)
      {
         if(g_cfg[idx].LastOutput > MOMENTUM_TP_CONF_MIN)
         {
            double m1ATR = GetATR(sym, PERIOD_M1, ATR_PERIOD);
            double newTP = (type == POSITION_TYPE_BUY) ? curTP + m1ATR * MOMENTUM_TP_R_MULT
                                                          : curTP - m1ATR * MOMENTUM_TP_R_MULT;
            trade.PositionModify(ticket, curSL, newTP);
            g_openTrades[stIdx].TpExtended = true;
         }
      }

      // Pyramid
      if(EnablePyramid && stIdx >= 0 && !g_openTrades[stIdx].IsPyramidLeg)
      {
         if(g_cfg[idx].ConsecutiveWins >= 2 && g_cfg[idx].PyramidLevel == 0 && profit > 0)
            OpenPyramidAddon(idx, ticket, PyramidL1Mult, 1, 2.0);
         else if(g_cfg[idx].ConsecutiveWins >= 3 && g_cfg[idx].PyramidLevel == 1 && profit > 0)
            OpenPyramidAddon(idx, ticket, PyramidL2Mult, 2, 1.0);
      }
   }
}

//======================================================================
// TRADE CLOSE PROCESSING
//======================================================================
void ProcessTradeClose(int idx, double profit, ulong dealTicket)
{
   SymbolConfig cfg = g_cfg[idx];
   string sym = cfg.Name;

   ulong posTicket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   RemoveOpenTradeState(posTicket);

   g_cfg[idx].RollingHistory[g_cfg[idx].HistoryIndex % ROLLING_HISTORY_SIZE] = (profit > 0.0) ? 1 : 0;
   g_cfg[idx].HistoryIndex++;
   g_cfg[idx].RollingTradeCount++;
   if(g_cfg[idx].WinRateGuardCooldown > 0) g_cfg[idx].WinRateGuardCooldown--;

   int count;
   double wr = GetRollingWinRate(g_cfg[idx], count);
   if(count >= WinRateMinTrades && wr < (WinRateFloor / 100.0) && g_cfg[idx].WinRateGuardCooldown <= 0)
   {
      g_cfg[idx].WinRateGuardCooldown = WIN_RATE_UNBLOCK_TRADES;
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
      if(g_cfg[idx].ConsecutiveLosses >= CIRCUIT_BREAKER_LOSS_COUNT)
      {
         g_cfg[idx].CircuitBreakerActive = true;
         g_cfg[idx].CircuitBreakerExpiry = TimeCurrent() + CIRCUIT_BREAKER_DURATION;
      }
      if(g_cfg[idx].PyramidLevel > 0)
         CollapsePyramid(idx, "loss");
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_cfg[idx].PeakEquity) g_cfg[idx].PeakEquity = equity;
   if(g_cfg[idx].PeakEquity > 0.0)
   {
      double dd = (g_cfg[idx].PeakEquity - equity) / g_cfg[idx].PeakEquity;
      if(dd > DD_RECOVERY_TRIGGER_FRAC && !g_cfg[idx].InDrawdownRecovery)
         g_cfg[idx].InDrawdownRecovery = true;
      else if(g_cfg[idx].InDrawdownRecovery && equity >= g_cfg[idx].PeakEquity * DD_RECOVERY_CLEAR_FRAC)
         g_cfg[idx].InDrawdownRecovery = false;
   }

   g_cfg[idx].SessionPnL += profit;
   g_cfg[idx].NetPnL += profit;
   g_cfg[idx].TotalTrades++;
   if(profit > 0) g_cfg[idx].TotalWins++;
   g_globalSessionPnL += profit;

   UpdateWeights(g_cfg[idx], profit);

   g_totalClosedTrades++;
   if(g_totalClosedTrades % TIER_REEVAL_TRADE_INTERVAL == 0)
      RecalculateTier();
}

//======================================================================
// RANKING & INITIALIZATION
//======================================================================
void RankSymbols()
{
   g_lastRankTime = TimeCurrent();

   for(int i = 0; i < g_symbolCount; i++)
   {
      g_rank[i].Symbol = g_cfg[i].Name;
      g_rank[i].Selected = false;

      if(!g_cfg[i].Available) { g_rank[i].FinalRank = -1.0; continue; }

      double atr = GetATR(g_cfg[i].Name, PERIOD_H1, ATR_PERIOD);
      double price = SymbolInfoDouble(g_cfg[i].Name, SYMBOL_BID);
      if(price <= 0.0 || atr <= 0.0) { g_rank[i].FinalRank = -1.0; continue; }

      long spreadPts = SymbolInfoInteger(g_cfg[i].Name, SYMBOL_SPREAD);
      double spread = spreadPts * g_cfg[i].PointValue;
      double ceiling = g_cfg[i].SpreadCeiling;
      if(ceiling <= 0.0) ceiling = price * 0.001;

      double volScore = (atr / price) * 100.0;
      double spreadScore = MathMax(-1.0, MathMin(1.0, 1.0 - (spread / ceiling)));

      g_rank[i].VolScore = volScore;
      g_rank[i].SpreadScore = spreadScore;
      g_rank[i].FinalRank = (volScore * 0.60) + (spreadScore * 0.30) + (0.0 * 0.10);
   }

   for(int i = 1; i < g_symbolCount; i++)
   {
      VolatilityRank key = g_rank[i];
      int j = i - 1;
      while(j >= 0 && g_rank[j].FinalRank < key.FinalRank)
      {
         g_rank[j + 1] = g_rank[j];
         j--;
      }
      g_rank[j + 1] = key;
   }

   int selectedCount = 0;

   for(int i = 0; i < g_symbolCount; i++)
   {
      if(g_rank[i].Symbol == GOLD_SYMBOL)
      {
         int gi = FindCfgIndex(GOLD_SYMBOL);
         if(gi >= 0 && g_cfg[gi].Available && g_rank[i].FinalRank > -1.0)
         {
            g_rank[i].Selected = true;
            selectedCount++;
         }
         break;
      }
   }

   for(int i = 0; i < g_symbolCount && selectedCount < g_maxTrades; i++)
   {
      if(g_rank[i].Selected) continue;
      if(g_rank[i].FinalRank <= -1.0) continue;
      g_rank[i].Selected = true;
      selectedCount++;
   }

   for(int i = 0; i < g_symbolCount; i++)
   {
      int ci = FindCfgIndex(g_rank[i].Symbol);
      if(ci >= 0) g_cfg[ci].Selected = g_rank[i].Selected;
   }
}

void UpdateSessionResetIfNeeded()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   datetime today = TimeGMT() - (dt.hour * 3600 + dt.min * 60 + dt.sec);
   if(today != g_sessionDay)
   {
      g_sessionDay = today;
      g_globalSessionPnL = 0.0;
      for(int i = 0; i < g_symbolCount; i++) g_cfg[i].SessionPnL = 0.0;
      g_sessionStartBalance = AccountInfoBalance(ACCOUNT_BALANCE);
   }
}

bool InitSymbolConfig(int idx, string sym)
{
   ZeroMemory(g_cfg[idx]);
   g_cfg[idx].Name = sym;
   g_cfg[idx].PeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(!SymbolSelect(sym, true))
   {
      g_cfg[idx].Available = false;
      return false;
   }

   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);

   if(minLot <= 0.0 || lotStep <= 0.0 || point <= 0.0)
   {
      g_cfg[idx].Available = false;
      return false;
   }

   g_cfg[idx].Available = true;
   g_cfg[idx].MinLot = minLot;
   g_cfg[idx].LotStep = lotStep;
   g_cfg[idx].MaxLot = maxLot;
   g_cfg[idx].PointValue = point;
   g_cfg[idx].TickSize = tickSize;
   g_cfg[idx].TickValue = tickValue;
   g_cfg[idx].SpreadCeiling = GetSpreadCeiling(sym);
   return true;
}

void ParseWatchlist()
{
   string raw = Watchlist;
   StringReplace(raw, " ", "");
   StringReplace(raw, "\n", "");
   StringReplace(raw, "\t", "");
   ushort sep = StringGetCharacter(",", 0);
   g_symbolCount = StringSplit(raw, sep, g_watchSymbols);
   ArrayResize(g_cfg, g_symbolCount);
   ArrayResize(g_rank, g_symbolCount);
}

//======================================================================
// OnInit
//======================================================================
int OnInit()
{
   bool okAccount = false, okNN = false, okScan = false;

   double effBalance = GetEffectiveBalance();
   PrintFormat("Account: balance=%.2f leverage=%d", effBalance, (int)AccountInfoInteger(ACCOUNT_LEVERAGE));

   if(effBalance < MinAccountUSD)
   {
      Print("CRITICAL: Below minimum operational floor");
      return INIT_FAILED;
   }

   EvaluateTier(effBalance, g_currentTier, g_maxTrades, g_tierRiskPct);
   okAccount = true;
   g_sessionStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_globalPeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   int marginMode = (int)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_hedgingMode = (marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   ParseWatchlist();
   int availableCount = 0;
   for(int i = 0; i < g_symbolCount; i++)
      if(InitSymbolConfig(i, g_watchSymbols[i])) availableCount++;
   okScan = (availableCount > 0);

   if(!LoadWeights())
      InitializeWeights();
   okNN = true;

   RankSymbols();

   EventSetTimer(1);

   Print("========== V2 ARITHMETIC-LOGIC EA INITIALIZED ==========");
   PrintFormat("[%s] Account: TIER %d (MaxTrades=%d)", okAccount ? "OK" : "FAIL", g_currentTier, g_maxTrades);
   PrintFormat("[%s] NN weights: %s", okNN ? "OK" : "FAIL", FileIsExist(WEIGHTS_FILENAME) ? "loaded" : "initialized");
   PrintFormat("[%s] Symbols scanned: %d available", okScan ? "OK" : "FAIL", availableCount);
   PrintFormat("[%s] Risk/Reward enforcement: MIN %.2f:1", RequireConfluence ? "ON" : "OFF", MinRiskRewardRatio);
   PrintFormat("[%s] Fibonacci TP placement: %s", EnableFibonacci ? "ON" : "OFF");
   PrintFormat("[%s] Kelly Criterion sizing: %s", EnableKellySizing ? "ON" : "OFF");
   PrintFormat("[%s] Confluence required: %d+ signals", RequireConfluence ? "ON" : "OFF", RequireConfluence ? 2 : 0);
   Print("=========================================================");

   return INIT_SUCCEEDED;
}

//======================================================================
// OnDeinit
//======================================================================
void OnDeinit(const int reason)
{
   EventKillTimer();
   SaveWeights();
   Print("EA stopped - session summary:");
   for(int i = 0; i < g_symbolCount; i++)
   {
      if(!g_cfg[i].Available) continue;
      double wr = (g_cfg[i].TotalTrades > 0) ? (double)g_cfg[i].TotalWins / (double)g_cfg[i].TotalTrades * 100.0 : 0.0;
      PrintFormat("[%s] trades=%d wr=%.1f%% netPnL=%.2f", g_cfg[i].Name, g_cfg[i].TotalTrades, wr, g_cfg[i].NetPnL);
   }
}

//======================================================================
// OnTick & OnTimer
//======================================================================
void OnTick()
{
   UpdateSessionResetIfNeeded();
   RecalculateTier();

   if(TimeCurrent() - g_lastRankTime >= RankIntervalMins * 60)
      RankSymbols();

   ManageOpenPositions();

   int idx = FindCfgIndex(_Symbol);
   if(idx >= 0 && g_cfg[idx].Selected)
      ProcessSymbol(idx);
}

void OnTimer()
{
   UpdateSessionResetIfNeeded();
   ClearExpiredCircuitBreakers();

   for(int i = 0; i < g_symbolCount; i++)
      if(g_cfg[i].Selected)
         ProcessSymbol(i);

   ManageOpenPositions();
}

//======================================================================
// OnTradeTransaction
//======================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY) return;

   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(magic < MagicBase || magic >= MagicBase + g_symbolCount) return;
   int idx = (int)(magic - MagicBase);
   if(idx < 0 || idx >= g_symbolCount) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                  + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                  + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   ProcessTradeClose(idx, profit, trans.deal);
}

//+------------------------------------------------------------------+
