//+------------------------------------------------------------------+
//|                                            GoldPortfolioEA.mq5   |
//|                       Adaptive multi-symbol portfolio EA         |
//|         Gold-anchored volatility-ranked M1 scalping system       |
//+------------------------------------------------------------------+
#property copyright "Quant Systems"
#property version   "1.00"
#property description "Multi-symbol volatility-ranked M1 portfolio EA. "
#property description "Gold (XAUUSD) receives a guaranteed trading slot; "
#property description "remaining slots are filled by ATR/spread ranking "
#property description "across the configured watchlist. Native MQL5 "
#property description "neural-net signal filter, SQLite trade logging, "
#property description "tiered risk sizing, and multi-layer circuit "
#property description "breakers. No external files, DLLs, or ONNX."

#include <Trade\Trade.mqh>

//======================================================================
// SECTION 16 — INPUT PARAMETERS
//======================================================================
input string Watchlist          = "EURUSD,GBPUSD,USDJPY,USDCHF,AUDUSD,NZDUSD,USDCAD,XAUUSD,XAGUSD,BTCUSD,ETHUSD,USOIL,UKOIL";
input double RiskPercent        = 1.0;     // fallback risk% if tier engine cannot resolve a tier
input double MinAccountUSD      = 2.0;
input int    MagicBase          = 20260614;
input bool   TradeAsian         = true;
input bool   TradeLondon        = true;
input bool   TradeNewYork       = true;
input bool   TradeOffHours      = true;  // 17:00-00:00 UTC - thinner liquidity, gated by a stricter NN threshold
input double SpreadMultiplier   = 3.0;
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
// NAMED CONSTANTS (no magic numbers in logic)
//======================================================================
#define WEIGHTS_FILENAME            "EAWeights.bin"
#define DB_FILENAME                 "QuantTickStorage.sqlite"
#define ATR_PERIOD                  14
#define ROLLING_HISTORY_SIZE        20
#define NN_INPUTS                   5
#define NN_HIDDEN                   8
#define MAX_PYRAMID_LEVELS          3        // index 0=base,1=L1,2=L2
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
#define FORCED_EXIT_SECONDS         120
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
#define THRESH_OVERLAP               0.89
#define THRESH_OFFHOURS              0.95  // stricter than London/NY - thin post-NY/pre-Asian liquidity

//======================================================================
// SECTION 2 — VOLATILITY RANK STRUCT
//======================================================================
struct VolatilityRank
{
   string Symbol;
   double VolScore;
   double SpreadScore;
   bool   BookAvailable;
   double FinalRank;
   bool   Selected;
};

//======================================================================
// SECTION 3 — SYMBOL CONFIGURATION MATRIX
//======================================================================
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
   double   PyramidAddedVolume; // sum of add-on lots merged into the base position (netting accounts)
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
};

//======================================================================
// Per-open-trade side table (MT5 positions carry no custom payload)
//======================================================================
struct OpenTradeState
{
   ulong  Ticket;
   int    Idx;          // index into g_cfg / g_rank
   double RiskAmt;       // 1R in account currency
   double SlDistance;    // price distance from entry to SL
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

// Plain arrays rather than matrix/vector types: the network is 5x8x1, so the
// matrix class buys nothing here and its element-access syntax has varied
// between MetaEditor builds. File layout on disk is unchanged: W1, W2, B1, B2.
double            g_W1[NN_INPUTS][NN_HIDDEN];
double            g_W2[NN_HIDDEN];
double            g_B1[NN_HIDDEN];
double            g_B2;

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
enum ENUM_CORR_GROUP { GROUP_NONE, GROUP_A, GROUP_B, GROUP_C };

//======================================================================
// FORWARD UTILITY: sigmoid
//======================================================================
double Sigmoid(double x) { return 1.0 / (1.0 + MathExp(-x)); }

//======================================================================
// SECTION 4 — GetATR (series-ordered, index 0 = most recent)
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

//======================================================================
// SECTION 3 — Spread ceiling (30% of M15 ATR)
//======================================================================
double GetSpreadCeiling(string symbol)
{
   double atr = GetATR(symbol, PERIOD_M15, ATR_PERIOD);
   if(atr <= 0.0)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      return point * 100.0; // safety fallback so ceiling is never zero
   }
   return atr * SPREAD_CEILING_ATR_FACTOR;
}

//======================================================================
// Helpers: index lookups
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
// SECTION 1 — ACCOUNT INTELLIGENCE & TIER ENGINE
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

void CloseWorstPositionForSymbolExcess(int excessCount)
{
   // Close the least-profitable of our managed positions until within cap.
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
      Print("Tier demotion: closed excess position ticket=", worstTicket);
   }
}

void RecalculateTier()
{
   double effBalance = GetEffectiveBalance();
   int newTier; int newMax; double newRisk;
   EvaluateTier(effBalance, newTier, newMax, newRisk);

   if(newTier != g_currentTier)
   {
      PrintFormat("TIER CHANGE @ %s: TIER%d -> TIER%d | EffBalance=%.2f MaxTrades=%d RiskPct=%.2f",
                  TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                  g_currentTier, newTier, effBalance, newMax, newRisk);
   }

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

//======================================================================
// SECTION 7 — NATIVE NEURAL NETWORK
//======================================================================
void InitializeWeights()
{
   MathSrand((int)TimeLocal());
   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++)
         g_W1[i][j] = ((MathRand() / 32767.0) * 2.0 - 1.0) * WEIGHT_INIT_RANGE;
   for(int j = 0; j < NN_HIDDEN; j++)
      g_W2[j] = ((MathRand() / 32767.0) * 2.0 - 1.0) * WEIGHT_INIT_RANGE;
   ArrayInitialize(g_B1, 0.0);
   g_B2 = 0.0;
   Print("Neural network initialized with random weights - learning begins");
}

bool LoadWeights()
{
   if(!FileIsExist(WEIGHTS_FILENAME)) return false;
   int fh = FileOpen(WEIGHTS_FILENAME, FILE_READ | FILE_BIN);
   if(fh == INVALID_HANDLE)
   {
      PrintFormat("WARN: could not open %s for reading, err=%d", WEIGHTS_FILENAME, GetLastError());
      return false;
   }
   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++)
         g_W1[i][j] = FileReadDouble(fh);
   for(int j = 0; j < NN_HIDDEN; j++)
      g_W2[j] = FileReadDouble(fh);
   for(int j = 0; j < NN_HIDDEN; j++)
      g_B1[j] = FileReadDouble(fh);
   g_B2 = FileReadDouble(fh);
   FileClose(fh);
   Print("Neural network weights loaded from ", WEIGHTS_FILENAME);
   return true;
}

void SaveWeights()
{
   int fh = FileOpen(WEIGHTS_FILENAME, FILE_WRITE | FILE_BIN);
   if(fh == INVALID_HANDLE)
   {
      PrintFormat("ERROR: could not open %s for writing, err=%d", WEIGHTS_FILENAME, GetLastError());
      return;
   }
   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++)
         FileWriteDouble(fh, g_W1[i][j]);
   for(int j = 0; j < NN_HIDDEN; j++)
      FileWriteDouble(fh, g_W2[j]);
   for(int j = 0; j < NN_HIDDEN; j++)
      FileWriteDouble(fh, g_B1[j]);
   FileWriteDouble(fh, g_B2);
   FileClose(fh);
}

// Forward pass. Section 5 DOM-derived pressureScore is replaced by a
// candle-body pressure proxy (see GetCandlePressure) since order-book
// depth is unavailable on most retail CFD/FX feeds - see brief.
double GetNNConfidence(SymbolConfig &cfg, double deltaScore, double pressureProxy,
                        double velocityScore, double htfBias, double spreadRatio)
{
   // 'input' is a reserved MQL5 keyword - the feature vector must not use it.
   double nnInput[NN_INPUTS];
   nnInput[0] = deltaScore;
   nnInput[1] = pressureProxy;
   nnInput[2] = velocityScore;
   nnInput[3] = htfBias;
   nnInput[4] = spreadRatio;

   double hidden[NN_HIDDEN];
   for(int j = 0; j < NN_HIDDEN; j++)
   {
      double sum = g_B1[j];
      for(int i = 0; i < NN_INPUTS; i++)
         sum += nnInput[i] * g_W1[i][j];
      hidden[j] = Sigmoid(sum);
   }

   double outSum = g_B2;
   for(int j = 0; j < NN_HIDDEN; j++)
      outSum += hidden[j] * g_W2[j];
   double output = Sigmoid(outSum);

   for(int i = 0; i < NN_INPUTS; i++) cfg.LastInput[i] = nnInput[i];
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
      dHidden[j] = dOut * g_W2[j] * h * (1.0 - h);
   }

   for(int j = 0; j < NN_HIDDEN; j++)
      g_W2[j] += LearningRate * cfg.LastHidden[j] * dOut;
   g_B2 += LearningRate * dOut;

   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++)
         g_W1[i][j] += LearningRate * cfg.LastInput[i] * dHidden[j];
   for(int j = 0; j < NN_HIDDEN; j++)
      g_B1[j] += LearningRate * dHidden[j];

   SaveWeights();
   g_nnTotalTrades++;
   if(tradePnL > 0) g_nnWins++;
   PrintFormat("NN updated [%s] target=%.1f output=%.4f error=%.4f", cfg.Name, target, output, err);
}

//======================================================================
// SECTION 4 — MULTI-TIMEFRAME TREND CASCADE
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
// SECTION 5 — M1 MICROSTRUCTURE ENGINE (DOM/spoofing/iceberg dropped;
// see brief - replaced with candle-body pressure proxy)
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
      else if(i > 0)
      {
         if(ticks[i].bid > ticks[i - 1].bid) buyVol++;
         else if(ticks[i].bid < ticks[i - 1].bid) sellVol++;
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
   double pressure = (r[1].close - r[1].open) / range;
   return MathMax(-1.0, MathMin(1.0, pressure));
}

bool M1CandleConfirmation(string symbol, int direction)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(symbol, PERIOD_M1, 0, 2, r) < 2) return false;
   double range = r[1].high - r[1].low;
   if(range <= 0.0) return false;
   double body = MathAbs(r[1].close - r[1].open);
   if(body / range <= 0.30) return false; // doji/indecision rejected

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
// SECTION 6 — CORRELATION BLOCKER
//======================================================================
ENUM_CORR_GROUP GetCorrelationGroup(string symbol)
{
   if(symbol == "EURUSD" || symbol == "GBPUSD" || symbol == "AUDUSD" || symbol == "NZDUSD") return GROUP_A;
   if(symbol == "USOIL" || symbol == "UKOIL") return GROUP_C;
   if(symbol == GOLD_SYMBOL) return GROUP_B;
   return GROUP_NONE;
}

bool CorrelationBlocked(string sym, int direction)
{
   ENUM_CORR_GROUP grp = GetCorrelationGroup(sym);
   bool goldEurModerate = (sym == GOLD_SYMBOL || sym == "EURUSD");

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic < MagicBase || magic >= MagicBase + g_symbolCount) continue;

      string posSym = PositionGetString(POSITION_SYMBOL);
      if(posSym == sym) continue;
      int posDir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      if(posDir != direction) continue;

      if(grp != GROUP_NONE && GetCorrelationGroup(posSym) == grp) return true;
      if(goldEurModerate && (posSym == GOLD_SYMBOL || posSym == "EURUSD")) return true;
   }
   return false;
}

//======================================================================
// SECTION 12 — NEWS BLACKOUT (native Economic Calendar API)
//======================================================================
bool IsAlgorithmicNFPWindow()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(dt.day_of_week != 5) return false; // Friday
   if(dt.day > 7) return false;          // first Friday of month
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
      default:              return THRESH_OFFHOURS; // SESSION_OFFHOURS
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
      default:              return TradeOffHours; // SESSION_OFFHOURS
   }
}

//======================================================================
// SECTION 13/14 — Win-rate & circuit breaker helpers
//======================================================================
double GetRollingWinRate(SymbolConfig &cfg, int &count)
{
   count = MathMin(cfg.HistoryIndex, ROLLING_HISTORY_SIZE);
   if(count <= 0) return 1.0; // no history yet -> do not block
   int wins = 0;
   for(int i = 0; i < count; i++) wins += cfg.RollingHistory[i];
   return (double)wins / (double)count;
}

void ClearExpiredCircuitBreakers()
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
      if(g_cfg[i].SpreadEmergencyActive && TimeCurrent() >= g_cfg[i].SpreadEmergencyExpiry)
         g_cfg[i].SpreadEmergencyActive = false;
   }
}

double ComputePortfolioRisk()
{
   double totalRisk = 0.0;
   for(int i = 0; i < ArraySize(g_openTrades); i++)
      totalRisk += g_openTrades[i].RiskAmt;
   return totalRisk;
}

// Hysteresis per Section 14: trip at 5% equity, hold the block until back under 3%.
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

//======================================================================
// SECTION 3 — IsSymbolTradeable
//======================================================================
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
      PrintFormat("Spread emergency - [%s]", cfg.Name);
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

   if(cfg.WinRateGuardCooldown > 0) return false; // guard active - authoritatively managed in ProcessTradeClose

   if(InNewsBlackout()) return false;

   return true;
}

//======================================================================
// Money-per-point helper (shared by lot sizing, breakeven, risk sums)
//======================================================================
double GetPointValueMoney(int idx)
{
   SymbolConfig cfg = g_cfg[idx];
   if(cfg.TickSize <= 0.0 || cfg.TickValue <= 0.0) return 0.0;
   return (cfg.TickValue / cfg.TickSize) * cfg.PointValue; // money per 1 point per 1.0 lot
}

double PriceDistanceToMoney(int idx, double priceDist, double volume)
{
   double point = g_cfg[idx].PointValue;
   if(point <= 0.0) return 0.0;
   double ptVal = GetPointValueMoney(idx);
   return (priceDist / point) * ptVal * volume;
}

//======================================================================
// SECTION 8 — Lot sizing / SL / TP
//======================================================================
double CalculateLotSize(int idx, double activeRiskPct, double slDist, double &riskAmtOut)
{
   SymbolConfig cfg = g_cfg[idx];
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt = equity * (activeRiskPct / 100.0);
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

//======================================================================
// SECTION 9 — Dynamic risk escalation
//======================================================================
double GetActiveRiskPct()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0) return g_tierRiskPct;
   double pnlFrac = g_globalSessionPnL / balance;

   double activeRisk = g_tierRiskPct;
   if(pnlFrac > RISK_ESCALATION_LOCK_FRAC)      activeRisk = g_tierRiskPct * 0.5;  // profit lock
   else if(pnlFrac > RISK_ESCALATION_L2_FRAC)   activeRisk = g_tierRiskPct * 2.0;
   else if(pnlFrac > RISK_ESCALATION_L1_FRAC)   activeRisk = g_tierRiskPct * 1.5;

   return MathMin(activeRisk, RISK_HARD_CAP_PCT);
}

//======================================================================
// SECTION 15 — SQLITE LOGGING
//======================================================================
bool OpenDatabase()
{
   if(!EnableSQLite) return true;
   g_dbHandle = DatabaseOpen(DB_FILENAME, DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE);
   if(g_dbHandle == INVALID_HANDLE)
   {
      PrintFormat("ERROR: DatabaseOpen failed err=%d", GetLastError());
      return false;
   }

   bool ok = true;
   ok &= DatabaseExecute(g_dbHandle,
      "CREATE TABLE IF NOT EXISTS ticks("
      "id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, symbol TEXT, delta REAL,"
      "pressure REAL, velocity REAL, nn_conf REAL, spread REAL, latency INTEGER)");
   ok &= DatabaseExecute(g_dbHandle,
      "CREATE TABLE IF NOT EXISTS trades("
      "id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, symbol TEXT, dir TEXT, lots REAL,"
      "entry REAL, sl REAL, tp REAL, close_price REAL, pnl REAL, tier INTEGER, pyramid_lvl INTEGER)");
   ok &= DatabaseExecute(g_dbHandle,
      "CREATE TABLE IF NOT EXISTS equity_curve("
      "id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, balance REAL, equity REAL,"
      "dd REAL, tier INTEGER, global_pnl REAL)");
   ok &= DatabaseExecute(g_dbHandle,
      "CREATE TABLE IF NOT EXISTS nn_weights("
      "id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, w1_checksum REAL, w2_checksum REAL,"
      "total_trades INTEGER, win_rate REAL)");

   if(!ok) PrintFormat("WARN: one or more CREATE TABLE statements failed err=%d", GetLastError());
   return ok;
}

void LogTick(string symbol, double delta, double pressure, double velocity,
             double nnConf, double spread, ulong latency)
{
   if(!EnableSQLite || g_dbHandle == INVALID_HANDLE) return;
   if(g_tickLogCounter == 0) DatabaseExecute(g_dbHandle, "BEGIN TRANSACTION");

   string sql = StringFormat(
      "INSERT INTO ticks(ts,symbol,delta,pressure,velocity,nn_conf,spread,latency) VALUES(%d,'%s',%.6f,%.6f,%.6f,%.6f,%.6f,%d)",
      (int)TimeCurrent(), symbol, delta, pressure, velocity, nnConf, spread, (int)latency);
   if(!DatabaseExecute(g_dbHandle, sql))
      PrintFormat("WARN: tick insert failed err=%d", GetLastError());

   g_tickLogCounter++;
   if(g_tickLogCounter >= TICK_LOG_BATCH_SIZE)
   {
      DatabaseExecute(g_dbHandle, "COMMIT");
      g_tickLogCounter = 0;
   }
}

void FlushTickLog()
{
   if(g_dbHandle == INVALID_HANDLE) return;
   if(g_tickLogCounter > 0)
   {
      DatabaseExecute(g_dbHandle, "COMMIT");
      g_tickLogCounter = 0;
   }
}

void LogTradeOpen(int idx, string dir, double lots, double entry, double sl, double tp, int pyramidLvl)
{
   if(!EnableSQLite || g_dbHandle == INVALID_HANDLE) return;
   string sql = StringFormat(
      "INSERT INTO trades(ts,symbol,dir,lots,entry,sl,tp,close_price,pnl,tier,pyramid_lvl) VALUES(%d,'%s','%s',%.4f,%.6f,%.6f,%.6f,0,0,%d,%d)",
      (int)TimeCurrent(), g_cfg[idx].Name, dir, lots, entry, sl, tp, g_currentTier, pyramidLvl);
   if(!DatabaseExecute(g_dbHandle, sql))
      PrintFormat("WARN: trade-open insert failed err=%d", GetLastError());
}

void LogTradeClose(string symbol, double closePrice, double pnl)
{
   if(!EnableSQLite || g_dbHandle == INVALID_HANDLE) return;
   // SQLite via MQL5 does not support UPDATE ... ORDER BY/LIMIT reliably,
   // so closures are logged as their own row rather than patching the open row.
   string sql = StringFormat(
      "INSERT INTO trades(ts,symbol,dir,lots,entry,sl,tp,close_price,pnl,tier,pyramid_lvl) VALUES(%d,'%s','CLOSE',0,0,0,0,%.6f,%.2f,%d,0)",
      (int)TimeCurrent(), symbol, closePrice, pnl, g_currentTier);
   if(!DatabaseExecute(g_dbHandle, sql))
      PrintFormat("WARN: trade-close insert failed err=%d", GetLastError());
}

void LogEquitySnapshot()
{
   if(!EnableSQLite || g_dbHandle == INVALID_HANDLE) return;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (g_globalPeakEquity > 0.0) ? (g_globalPeakEquity - equity) / g_globalPeakEquity : 0.0;
   string sql = StringFormat(
      "INSERT INTO equity_curve(ts,balance,equity,dd,tier,global_pnl) VALUES(%d,%.2f,%.2f,%.6f,%d,%.2f)",
      (int)TimeCurrent(), balance, equity, dd, g_currentTier, g_globalSessionPnL);
   DatabaseExecute(g_dbHandle, sql);
}

void LogEquitySnapshotIfDue()
{
   if(TimeCurrent() - g_lastEquityLogTime < EQUITY_LOG_INTERVAL_SEC) return;
   g_lastEquityLogTime = TimeCurrent();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_globalPeakEquity) g_globalPeakEquity = equity;
   LogEquitySnapshot();
}

double W1Checksum()
{
   double sum = 0.0;
   for(int i = 0; i < NN_INPUTS; i++)
      for(int j = 0; j < NN_HIDDEN; j++)
         sum += g_W1[i][j];
   return sum;
}

double W2Checksum()
{
   double sum = 0.0;
   for(int j = 0; j < NN_HIDDEN; j++)
      sum += g_W2[j];
   return sum;
}

void LogNNCheckpointIfDue()
{
   if(!EnableSQLite || g_dbHandle == INVALID_HANDLE) return;
   if(g_nnTotalTrades == 0 || g_nnTotalTrades % NN_CHECKPOINT_TRADE_INTERVAL != 0) return;
   double wr = (g_nnTotalTrades > 0) ? (double)g_nnWins / (double)g_nnTotalTrades : 0.0;
   string sql = StringFormat(
      "INSERT INTO nn_weights(ts,w1_checksum,w2_checksum,total_trades,win_rate) VALUES(%d,%.6f,%.6f,%d,%.4f)",
      (int)TimeCurrent(), W1Checksum(), W2Checksum(), g_nnTotalTrades, wr);
   DatabaseExecute(g_dbHandle, sql);
}

//======================================================================
// SECTION 8/9 — Order execution
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
      // Netting accounts merge pyramid legs into the single base position,
      // so "closing" them means shrinking that position back to its base size.
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
      // Netting: same-direction order merges volume into the existing position automatically.
      ok = (baseType == POSITION_TYPE_BUY) ? trade.Buy(addLot, sym, price, 0, 0, "PyramidL" + IntegerToString(level))
                                            : trade.Sell(addLot, sym, price, 0, 0, "PyramidL" + IntegerToString(level));

   if(!ok)
   {
      PrintFormat("WARN: pyramid addon failed [%s] retcode=%d", sym, trade.ResultRetcode());
      return;
   }

   g_cfg[idx].PyramidLevel = level;
   if(g_hedgingMode)
   {
      ulong newTicket = trade.ResultOrder();
      g_cfg[idx].PyramidTickets[level] = newTicket;
      OpenTradeState st;
      st.Ticket = newTicket; st.Idx = idx;
      st.RiskAmt = PriceDistanceToMoney(idx, MathAbs(price - baseEntry), addLot); // SL = baseEntry, so this leg's real risk
      st.SlDistance = MathAbs(price - baseEntry); st.EntryPrice = price; st.IsPyramidLeg = true;
      st.PartialDone = false; st.BreakevenSet = false; st.TpExtended = false;
      PushOpenTradeState(st);
   }
   else
   {
      g_cfg[idx].PyramidTickets[level] = baseTicket;
      g_cfg[idx].PyramidAddedVolume += addLot; // tracked so CollapsePyramid can shrink the merged position back down
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
   bool ok = (direction > 0) ? trade.Buy(lot, sym, price, sl, tp, "M1-Signal")
                              : trade.Sell(lot, sym, price, sl, tp, "M1-Signal");
   ulong latency = GetMicrosecondCount() - t0;

   if(latency > LATENCY_WARN_MICROSECONDS)
   {
      g_cfg[idx].LatencyFlag = true;
      g_cfg[idx].LatencySkipCount = 5;
      PrintFormat("Latency flag [%s]: %d us", sym, (int)latency);
   }

   if(!ok)
   {
      PrintFormat("WARN: order failed [%s] retcode=%d", sym, trade.ResultRetcode());
      return false;
   }

   ulong ticket = trade.ResultOrder();
   OpenTradeState st;
   st.Ticket = ticket; st.Idx = idx; st.RiskAmt = riskAmt;
   st.SlDistance = MathAbs(price - sl); st.EntryPrice = price;
   st.IsPyramidLeg = false; st.PartialDone = false; st.BreakevenSet = false; st.TpExtended = false;
   PushOpenTradeState(st);

   g_cfg[idx].PyramidTickets[0] = ticket;
   g_cfg[idx].PyramidLevel = 0;

   LogTradeOpen(idx, direction > 0 ? "BUY" : "SELL", lot, price, sl, tp, 0);
   PrintFormat("Entry [%s] dir=%s lot=%.2f price=%.5f sl=%.5f tp=%.5f conf=%.3f",
               sym, direction > 0 ? "BUY" : "SELL", lot, price, sl, tp, cfg.LastOutput);
   return true;
}

//======================================================================
// SECTION 4/5/7/8 — Per-symbol signal pipeline
//======================================================================
void ProcessSymbol(int idx)
{
   SymbolConfig cfgSnap = g_cfg[idx];
   string sym = cfgSnap.Name;
   if(!cfgSnap.Available || !cfgSnap.Selected) return;

   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(bid <= 0.0) return;
   UpdateTickVelocity(g_cfg[idx], bid); // cheap, kept on every call for an accurate velocity ring buffer

   // Everything below is stateful/expensive and must fire at most once per
   // M1 candle - gating it here (rather than after spike/latency checks)
   // stops OnTimer's 1Hz cadence from burning through latency-skip counts
   // in seconds instead of candles, and from re-logging spike pauses every tick.
   datetime m1Time = iTime(sym, PERIOD_M1, 0);
   if(m1Time == 0 || m1Time == g_cfg[idx].LastM1CandleTime) return; // already processed this candle
   g_cfg[idx].LastM1CandleTime = m1Time;

   double m1ATR = GetATR(sym, PERIOD_M1, ATR_PERIOD);
   double h1ATR = GetATR(sym, PERIOD_H1, ATR_PERIOD);
   if(h1ATR > 0.0 && m1ATR > h1ATR * M1_ATR_SPIKE_FACTOR)
   {
      g_cfg[idx].SpikePauseActive = true;
      g_cfg[idx].SpikePauseExpiry = TimeCurrent() + VOL_SPIKE_PAUSE_SEC;
      PrintFormat("Unscheduled volatility spike - pause [%s]", sym);
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

   int htfBias = GetHTFBias(sym);
   if(htfBias == 0) return;

   if(!M1CandleConfirmation(sym, htfBias)) return;

   double deltaScore   = GetTickDeltaScore(sym);
   double pressureProxy = GetCandlePressure(sym);
   double velocityScore = GetTickVelocityScore(g_cfg[idx], sym);
   double spreadRatio   = GetSpreadRatio(sym);

   double confidence = GetNNConfidence(g_cfg[idx], deltaScore, pressureProxy, velocityScore, (double)htfBias, spreadRatio);

   double spread = SymbolInfoInteger(sym, SYMBOL_SPREAD) * g_cfg[idx].PointValue;
   LogTick(sym, deltaScore, pressureProxy, velocityScore, confidence, spread, 0);

   double threshold = GetSignalThreshold(session);
   if(confidence < threshold) return;

   if(!IsSymbolTradeable(idx)) return;
   if(CorrelationBlocked(sym, htfBias)) return;
   if(CountOpenManagedPositions() >= g_maxTrades) return;
   if(g_portfolioRiskBlocked) return; // governor tripped at 5%, held until back under 3%

   double slDist = MathMax(m1ATR * 1.5, SL_MIN_POINTS * g_cfg[idx].PointValue);
   double riskAmt;
   double activeRisk = GetActiveRiskPct();
   double lot = CalculateLotSize(idx, activeRisk, slDist, riskAmt);
   if(lot <= 0.0)
   {
      PrintFormat("Lot below minimum - skip [%s]", sym);
      return;
   }

   if(ComputePortfolioRisk() + riskAmt > AccountInfoDouble(ACCOUNT_EQUITY) * PORTFOLIO_RISK_CAP_FRACTION)
      return;

   double tpDist = MathMax(spread * 3.0, h1ATR * 0.50);
   double entryPrice = (htfBias > 0) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   double sl = (htfBias > 0) ? entryPrice - slDist : entryPrice + slDist;
   double tp = (htfBias > 0) ? entryPrice + tpDist : entryPrice - tpDist;

   OpenPosition(idx, htfBias, lot, sl, tp, riskAmt);
}

//======================================================================
// SECTION 10 — Position management
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

      // C. 2-minute forced exit
      if(TimeCurrent() - openTime >= FORCED_EXIT_SECONDS)
      {
         trade.PositionClose(ticket);
         RemoveOpenTradeState(ticket);
         PrintFormat("2-min timeout - [%s]", sym);
         continue;
      }

      double curPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      double spread = SymbolInfoInteger(sym, SYMBOL_SPREAD) * point;

      // D. Breakeven floor
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

      // A. Partial close at 1R
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
            PrintFormat("Partial close 50%% at 1R - [%s]", sym);
         }
      }

      // B. Trailing stop at 2R
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
            Print("TP extended - high conviction [", sym, "]");
         }
      }

      // Win-streak pyramid (base positions only)
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
// SECTION 11/13/14 — Trade-close bookkeeping (fires on every closing deal)
//======================================================================
void ProcessTradeClose(int idx, double profit, ulong dealTicket)
{
   SymbolConfig cfg = g_cfg[idx];
   string sym = cfg.Name;

   ulong posTicket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   RemoveOpenTradeState(posTicket);

   // Rolling win-rate ring buffer
   int result = (profit > 0.0) ? 1 : 0;
   g_cfg[idx].RollingHistory[g_cfg[idx].HistoryIndex % ROLLING_HISTORY_SIZE] = result;
   g_cfg[idx].HistoryIndex++;
   g_cfg[idx].RollingTradeCount++;
   if(g_cfg[idx].WinRateGuardCooldown > 0) g_cfg[idx].WinRateGuardCooldown--;

   int count;
   double wr = GetRollingWinRate(g_cfg[idx], count);
   if(count >= WinRateMinTrades && wr < (WinRateFloor / 100.0) && g_cfg[idx].WinRateGuardCooldown <= 0)
   {
      g_cfg[idx].WinRateGuardCooldown = WIN_RATE_UNBLOCK_TRADES;
      PrintFormat("Win rate guard active [%s] winRate=%.2f", sym, wr);
   }

   // Circuit breaker
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
         PrintFormat("Circuit breaker engaged [%s] - 3 consecutive losses", sym);
      }
      if(g_cfg[idx].PyramidLevel > 0)
      {
         CollapsePyramid(idx, "loss");
      }
   }

   // Compounding / drawdown recovery
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

   g_cfg[idx].SessionPnL += profit;
   g_cfg[idx].NetPnL += profit;
   g_cfg[idx].TotalTrades++;
   if(profit > 0) g_cfg[idx].TotalWins++;
   g_globalSessionPnL += profit;

   double closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   LogTradeClose(sym, closePrice, profit);

   UpdateWeights(g_cfg[idx], profit);
   LogNNCheckpointIfDue();

   g_totalClosedTrades++;
   if(g_totalClosedTrades % TIER_REEVAL_TRADE_INTERVAL == 0)
      RecalculateTier();
}

//======================================================================
// SESSION / DAILY RESET
//======================================================================
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
      g_sessionStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("Daily session reset (00:00 UTC)");
   }
}

//======================================================================
// SECTION 2 — RankSymbols
//======================================================================
void RankSymbols()
{
   g_lastRankTime = TimeCurrent();

   for(int i = 0; i < g_symbolCount; i++)
   {
      g_rank[i].Symbol = g_cfg[i].Name;
      g_rank[i].Selected = false;
      g_rank[i].BookAvailable = false; // DOM dropped by design decision

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

   // insertion sort descending by FinalRank (small n, no library dependency)
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

   // Guarantee gold a slot when available, per configured design decision.
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

   string selectedList = "";
   for(int i = 0; i < g_symbolCount; i++)
   {
      int ci = FindCfgIndex(g_rank[i].Symbol);
      if(ci >= 0) g_cfg[ci].Selected = g_rank[i].Selected;
      if(g_rank[i].Selected)
      {
         PrintFormat("Ranked [%s] Vol=%.4f Spread=%.4f Final=%.4f -> SELECTED",
                     g_rank[i].Symbol, g_rank[i].VolScore, g_rank[i].SpreadScore, g_rank[i].FinalRank);
         selectedList += g_rank[i].Symbol + " ";
      }
   }
   PrintFormat("RankSymbols complete - active symbols: %s", selectedList);
}

//======================================================================
// STARTUP / SYMBOL CONFIG POPULATION
//======================================================================
bool InitSymbolConfig(int idx, string sym)
{
   ZeroMemory(g_cfg[idx]);
   g_cfg[idx].Name = sym;
   g_cfg[idx].PeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(!SymbolSelect(sym, true))
   {
      PrintFormat("WARN: symbol %s not available on this broker - skipped", sym);
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
      PrintFormat("WARN: symbol %s returned invalid specs - skipped", sym);
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
// SECTION 18 — STARTUP CHECKLIST + OnInit
//======================================================================
int OnInit()
{
   bool okAccount = false, okNN = false, okDB = false, okScan = false;

   double effBalance = GetEffectiveBalance();
   PrintFormat("Account currency=%s effective_balance=%.2f leverage=%d margin_level=%.2f",
               AccountInfoString(ACCOUNT_CURRENCY), effBalance,
               (int)AccountInfoInteger(ACCOUNT_LEVERAGE), AccountInfoDouble(ACCOUNT_MARGIN_LEVEL));

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
   PrintFormat("Account margin mode: %s", g_hedgingMode ? "HEDGING" : "NETTING (pyramid uses volume-add)");

   ParseWatchlist();
   int availableCount = 0;
   for(int i = 0; i < g_symbolCount; i++)
      if(InitSymbolConfig(i, g_watchSymbols[i])) availableCount++;
   okScan = (availableCount > 0);

   if(!LoadWeights())
      InitializeWeights();
   okNN = true;

   okDB = OpenDatabase();

   RankSymbols();

   EventSetTimer(1);

   string selectedList = "";
   for(int i = 0; i < g_symbolCount; i++)
      if(g_cfg[i].Selected) selectedList += g_cfg[i].Name + " ";

   ENUM_SESSION sess = GetCurrentSession();
   string sessName = (sess == SESSION_ASIAN) ? "ASIAN" : (sess == SESSION_LONDON) ? "LONDON" :
                      (sess == SESSION_NY) ? "NEW YORK" : (sess == SESSION_OVERLAP) ? "OVERLAP" : "OFF-HOURS";

   Print("=========== STARTUP CHECKLIST ===========");
   PrintFormat("[%s] Account tier: TIER %d (MaxTrades=%d RiskPct=%.2f)", okAccount ? "OK" : "FAIL", g_currentTier, g_maxTrades, g_tierRiskPct);
   PrintFormat("[%s] NN weights: %s", okNN ? "OK" : "FAIL", FileIsExist(WEIGHTS_FILENAME) ? "loaded/initialized" : "initialized");
   PrintFormat("[%s] SQLite database: ready", okDB ? "OK" : "FAIL");
   PrintFormat("[%s] Volatility scan: %d symbols ranked", okScan ? "OK" : "FAIL", availableCount);
   PrintFormat("[%s] Active symbols: %s", (selectedList != "") ? "OK" : "FAIL", selectedList);
   PrintFormat("[%s] Session: %s", "OK", sessName);
   PrintFormat("[%s] All systems nominal", (okAccount && okNN && okDB && okScan) ? "OK" : "FAIL");
   Print("==========================================");

   return INIT_SUCCEEDED;
}

//======================================================================
// OnDeinit
//======================================================================
void OnDeinit(const int reason)
{
   EventKillTimer();
   FlushTickLog();
   SaveWeights();
   if(g_dbHandle != INVALID_HANDLE) DatabaseClose(g_dbHandle);

   Print("=========== SESSION SUMMARY ===========");
   double totalPnL = 0.0;
   double maxDD = 0.0;
   for(int i = 0; i < g_symbolCount; i++)
   {
      if(!g_cfg[i].Available) continue;
      double wr = (g_cfg[i].TotalTrades > 0) ? (double)g_cfg[i].TotalWins / (double)g_cfg[i].TotalTrades * 100.0 : 0.0;
      PrintFormat("[%s] trades=%d winrate=%.1f%% netPnL=%.2f peakEquity=%.2f",
                  g_cfg[i].Name, g_cfg[i].TotalTrades, wr, g_cfg[i].NetPnL, g_cfg[i].PeakEquity);
      totalPnL += g_cfg[i].NetPnL;
      if(g_cfg[i].PeakEquity > 0.0)
      {
         double dd = (g_cfg[i].PeakEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / g_cfg[i].PeakEquity;
         if(dd > maxDD) maxDD = dd;
      }
   }
   double nnWinRate = (g_nnTotalTrades > 0) ? (double)g_nnWins / (double)g_nnTotalTrades * 100.0 : 0.0;
   PrintFormat("Net PnL: %.2f | Peak equity: %.2f | Max DD: %.2f%%", totalPnL, g_globalPeakEquity, maxDD * 100.0);
   PrintFormat("NN trades processed: %d | NN-era win rate: %.1f%%", g_nnTotalTrades, nnWinRate);
   PrintFormat("Final active tier: TIER %d", g_currentTier);
   Print("========================================");
}

//======================================================================
// OnTick
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

   LogEquitySnapshotIfDue();
}

//======================================================================
// OnTimer — ensures every selected symbol is processed even when the
// chart's own symbol is quiet.
//======================================================================
void OnTimer()
{
   UpdateSessionResetIfNeeded();
   ClearExpiredCircuitBreakers();

   for(int i = 0; i < g_symbolCount; i++)
      if(g_cfg[i].Selected)
         ProcessSymbol(i);

   ManageOpenPositions();
   LogEquitySnapshotIfDue();
}

//======================================================================
// OnTradeTransaction — authoritative trade-close detection
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
