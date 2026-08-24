//+------------------------------------------------------------------+
//|                                                Medula_Single.mq5 |
//|  Medula EA v2.70 — single-file, zero-dependency build.           |
//|                                                                  |
//|  DESIGN NOTE — why this EA does not sit idle:                    |
//|  v1 compared conviction to a FIXED threshold (60). Because the    |
//|  engine weights sum to 1 and each score is capped at +/-1, the    |
//|  attainable conviction on real data peaked near 55 after the      |
//|  volatility/spread penalties, so the bar was unreachable and the  |
//|  EA never traded. v2 replaced it with a SELF-CALIBRATING bar:     |
//|  conviction is ranked against its own rolling distribution.       |
//|  v2.50 removes the remaining ways to stall:                      |
//|    - the distribution is SEEDED FROM HISTORY at startup, so       |
//|      percentile mode is live on the first tick instead of after   |
//|      60 bars of waiting;                                          |
//|    - a PARTICIPATION WATCHDOG (§26) relaxes selectivity (never    |
//|      the safety floor or risk caps) if the EA has been idle for   |
//|      an unreasonable stretch;                                     |
//|    - a STARTUP SELF-TEST reports, before a single tick, whether   |
//|      anything would structurally prevent trading.                 |
//|                                                                  |
//|  Engines (see MEDULA_FORMULAS.md):                               |
//|    §1-§7   market state, structure, trend, momentum, volatility,  |
//|            liquidity, multi-timeframe                             |
//|    §8-§9   confidence + self-calibrating decision                 |
//|    §10-§14 execution, basket, scaling, exits                     |
//|    §13,§15-§17 risk, allocation, session, correlation            |
//|    §18-§20 analytics, adaptive selectivity, logging              |
//|    §22 order flow    §23 volatility forecast                     |
//|    §24 trade quality §25 equity curve  §26 participation         |
//|  Validation (§21) is performed offline in the Strategy Tester.   |
//+------------------------------------------------------------------+
#property copyright "Medula Project"
#property version   "2.70"

//============================== INPUTS ==============================

input group "General"
input long   InpMagic            = 770015;   // Magic number
input int    InpDeviationPts     = 20;       // Max price deviation (points)
input bool   InpAnalyzeEveryTick = true;     // Full analysis every tick (false = per bar)
input bool   InpVerboseLog       = true;     // Print decisions to Experts log
input bool   InpCsvLog           = true;     // Write MedulaLog.csv (Files folder)
input bool   InpShowPanel        = true;     // Live diagnostic panel on chart
input bool   InpDiagnostics      = true;     // Log WHY an entry was skipped
input int    InpDiagThrottleSec  = 300;      // Min seconds between repeats of same reason
input bool   InpSelfTest         = true;     // Print readiness report on attach

input group "Analysis"
input int    InpErLen          = 20;    // Efficiency ratio length
input int    InpAtrPeriod      = 14;    // ATR period
input int    InpAdxPeriod      = 14;    // ADX period
input int    InpRsiPeriod      = 14;    // RSI period
input int    InpSlopeBars      = 10;    // EMA slope lookback (bars)
input int    InpStructLookback = 300;   // Structure window (bars)
input int    InpSwingK         = 2;     // Fractal wing size k
input int    InpStructEvents   = 10;    // BOS events for structure score
input int    InpVolRefBars     = 100;   // ATR reference SMA length
input int    InpVolPctBars     = 250;   // ATR percentile window
input double InpLiqRangeAtr    = 3.0;   // Liquidity scan range (ATR mult)
input int    InpBbPeriod       = 20;    // Bollinger period
input double InpBbDev          = 2.0;   // Bollinger deviation
input int    InpRocLen         = 10;    // ROC length

input group "Order Flow Engine (§22)"
input bool   InpUseOrderFlow   = true;  // Enable tick-pressure analysis
input int    InpFlowBars       = 20;    // Bars in the pressure window
input double InpFlowGain       = 2.0;   // Sensitivity of the pressure score

input group "Volatility Forecast Engine (§23)"
input bool   InpUseVolForecast = true;  // Enable EWMA volatility forecasting
input double InpEwmaLambda     = 0.94;  // RiskMetrics decay factor
input int    InpVolFcBars      = 100;   // Return history for the forecast

input group "Confidence (§8)"
input double InpW1 = 0.22;              // Weight: structure
input double InpW2 = 0.22;              // Weight: trend
input double InpW3 = 0.18;              // Weight: momentum
input double InpW4 = 0.12;              // Weight: liquidity
input double InpW5 = 0.13;              // Weight: MTF alignment
input double InpW6 = 0.13;              // Weight: order flow
input double InpConfGain          = 2.5;  // Confidence tanh gain
input double InpMaxSpreadPoints   = 40.0; // Absolute spread floor limit (points)
input double InpMaxSpreadAtr      = 0.50; // Spread limit as a fraction of ATR (self-calibrating backstop)

input group "Decision — self-calibrating threshold (§9)"
input bool   InpUsePercentile     = true;  // Rank conviction vs its own distribution
input double InpEntryPercentile   = 82.0;  // Enter in top (100-this)% of recent conviction
input int    InpConfSampleSize    = 500;   // Rolling distribution size (bars)
input bool   InpSeedFromHistory   = true;  // Seed distribution at startup (trade immediately)
input int    InpMinSamples        = 40;    // Samples needed before percentile mode engages
input double InpMinAbsConfidence  = 15.0;  // Absolute conviction floor (safety, never relaxed)
input double InpBootstrapConf     = 30.0;  // Threshold used while distribution fills
input double InpExitConfFraction  = 0.55;  // Exit when conviction falls below this x entry
input double InpMtfVetoConfluence = 65.0;  // Block counter-HTF entries above this confluence
input int    InpEntryCooldownSec  = 120;   // Min seconds between entries (anti-churn)

input group "Participation Watchdog (§26)"
input bool   InpUseWatchdog      = true;  // Relax selectivity if idle too long
input int    InpIdleBarsRelax    = 40;    // Idle bars before relaxation begins
input int    InpRelaxEveryBars   = 10;    // Relax one step per this many further bars
input double InpRelaxStepPct     = 2.0;   // Percentile points released per step
input double InpRelaxFloorPct    = 60.0;  // Never relax selectivity below this percentile

input group "Trade Quality Score (§24)"
input bool   InpUseQuality       = true;  // Score every setup before taking it
input double InpMinTradeQuality  = 40.0;  // Minimum quality to trade (0-100)
input bool   InpQualitySizing    = true;  // Let quality scale position size

input group "Risk (§13)"
input double InpRiskPct           = 0.75;  // Risk per trade (% equity)
input double InpSlAtrMult         = 1.5;   // SL distance (ATR mult)
input double InpTpAtrMult         = 3.0;   // TP distance (ATR mult)
input double InpDailyLossPct      = 3.0;   // Daily loss limit (%)
input double InpMaxDDPct          = 10.0;  // Max drawdown from peak (%)
input double InpMarginSafety      = 1.5;   // Free-margin safety factor
input double InpMaxAccountRiskPct = 4.0;   // Max total open risk (% equity)
input double InpMaxBasketRiskPct  = 2.5;   // Max basket risk (% equity)
input bool   InpAllowMinLot       = true;  // Round up to broker min lot (small accounts)
input bool   InpMinLotOverride    = true;  // Let a single min-lot trade exceed the planned cap
input double InpMaxRiskPctHard    = 20.0;  // ABSOLUTE ceiling on one trade's risk (% equity)

input group "Equity Curve Engine (§25)"
input bool   InpUseEquityCurve   = true;  // Size down when own equity curve is weak
input int    InpEquityCurveN     = 10;    // Trades in the equity-curve average
input double InpEquityCurveCut   = 0.60;  // Size multiplier while curve is below its average

input group "Position Scaling (§12)"
input int    InpMaxScaleIns     = 3;     // Max add-on positions
input double InpScaleSpacingAtr = 1.0;   // Min spacing between adds (ATR mult)
input double InpScaleDecay      = 0.7;   // Lot decay factor per add
input double InpScaleConfK      = 0.9;   // Min conviction vs entry conviction

input group "Exits (§11, §14)"
input double InpBasketTargetR  = 2.0;    // Basket profit target (R multiples)
input double InpTrailAtrMult   = 3.0;    // Chandelier trail (ATR mult)
input int    InpTrailLookback  = 22;     // Chandelier lookback (bars)
input int    InpMaxBarsInTrade = 96;     // Time stop (bars)
input double InpMinAcceptPL    = 0.0;    // Min P/L to bypass time stop

input group "Profit Protection (§14)"
input bool   InpUsePartialTP   = true;   // Scale out part of the position at target
input double InpPartialAtR     = 1.0;    // Take partial profit at this R multiple
input double InpPartialPct     = 50.0;   // Percent of volume to close
input bool   InpUseBreakEven   = true;   // Move stop to entry once in profit
input double InpBreakEvenAtR   = 1.0;    // R multiple that triggers break-even
input double InpBreakEvenBuf   = 0.10;   // Break-even buffer (ATR mult)

input group "Capital Allocation (§15)"
input double InpConfGamma     = 0.8;     // Conviction sizing exponent
input bool   InpUseKellyCap   = true;    // Apply fractional-Kelly cap
input double InpKellyFraction = 0.25;    // Kelly fraction (quarter-Kelly)

input group "Sessions (§16, GMT)"
input bool   InpUseSessions = true;      // Enable session multipliers
input double InpSessAsian   = 0.6;       // Asian (00-07 GMT)
input double InpSessLondon  = 1.0;       // London (07-12 GMT)
input double InpSessOverlap = 1.2;       // London/NY overlap (12-16 GMT)
input double InpSessNewYork = 1.0;       // New York (16-21 GMT)
input double InpSessDead    = 0.3;       // Dead zone (21-24 GMT)

input group "Correlation (§17)"
input bool   InpUseCorrelation = true;   // Enable correlation gating
input int    InpCorrBars       = 100;    // Correlation lookback (bars)
input double InpCorrThreshold  = 0.70;   // |r| threshold
input int    InpMaxCorrelated  = 2;      // Veto at this many correlated legs

input group "Execution Quality (§10)"
input double InpMaxSlippagePts   = 30.0; // Max acceptable avg slippage (points)
input int    InpExecWindow       = 20;   // Rolling attempts window
input double InpExecSuspendBelow = 40.0; // Suspend entries below this score

input group "Performance Feedback (§19)"
input bool   InpAdaptive     = true;     // Adapt entry percentile on performance
input double InpAdaptEta     = 2.0;      // Learning rate
input double InpAdaptAlpha   = 0.1;      // EMA smoothing
input double InpPctMin       = 65.0;     // Entry percentile lower bound
input double InpPctMax       = 95.0;     // Entry percentile upper bound
input int    InpAdaptRecentN = 20;       // Recent-trades window

//========================= TYPES & HELPERS ==========================

enum ENUM_REGIME
  {
   REGIME_NEUTRAL=0,
   REGIME_TRENDING,
   REGIME_RANGING,
   REGIME_BREAKOUT,
   REGIME_REVERSAL,
   REGIME_HIGH_VOL,
   REGIME_LOW_VOL
  };

enum ENUM_DECISION
  {
   DECISION_WAIT=0,
   DECISION_BUY,
   DECISION_SELL,
   DECISION_HOLD,
   DECISION_EXIT
  };

string RegimeName(const ENUM_REGIME r)
  {
   switch(r)
     {
      case REGIME_TRENDING: return "TRENDING";
      case REGIME_RANGING:  return "RANGING";
      case REGIME_BREAKOUT: return "BREAKOUT";
      case REGIME_REVERSAL: return "REVERSAL";
      case REGIME_HIGH_VOL: return "HIGH_VOL";
      case REGIME_LOW_VOL:  return "LOW_VOL";
     }
   return "NEUTRAL";
  }

double MTanh(const double x)
  {
   if(x>20.0)  return 1.0;
   if(x<-20.0) return -1.0;
   double e=MathExp(2.0*x);
   return (e-1.0)/(e+1.0);
  }

double MClamp(const double x,const double lo,const double hi)
  {
   return MathMin(MathMax(x,lo),hi);
  }

int MSign(const double x)
  {
   if(x>0.0) return 1;
   if(x<0.0) return -1;
   return 0;
  }

void PushInt(int &arr[],const int v)
  {
   int n=ArraySize(arr);
   ArrayResize(arr,n+1);
   arr[n]=v;
  }

//--- forward declarations (functions referenced before their definition)
double SessionMultiplierRaw(void);
void   UpdateEquityCurveMultiplier(void);
double MaxSpreadPointsEffective(void);

//--- snapshot of all engine outputs for the current tick
struct SMarketSnapshot
  {
   ENUM_REGIME       regime;
   double            er;               // Kaufman efficiency ratio (§1)
   double            adx;
   double            atr;
   double            vr;               // volatility ratio (§1)
   double            volPercentile;    // §1
   double            volSuitability;   // §5, 0..100
   double            volForecastRatio; // §23, >1 = expansion expected
   double            structureScore;   // §2, -100..+100
   double            trendScore;       // §3, -100..+100
   int               trendDir;
   double            momentumScore;    // §4, -100..+100
   double            momentumAccel;    // §4
   double            liquidityScore;   // §6, -100..+100
   double            orderFlowScore;   // §22, -100..+100
   double            mtfAlignment;     // §7, -1..+1
   double            mtfConfluence;    // §7, 0..100
   double            mtfValidWeight;   // §7, share of higher TFs with usable data
   bool              bullBos,bearBos;
   bool              bullChoch,bearChoch;
   double            confidenceDir;    // §8, -100..+100 (sign = direction)
   double            confidenceFinal;  // §8, 0..100 after penalties
   double            confPercentile;   // §9, rank within rolling distribution
   double            tradeQuality;     // §24, 0..100
   double            bid,ask,close;
   double            spreadPts;
  };

//--- aggregated basket metrics (§11)
struct SBasket
  {
   int               count;
   double            totalVolume;
   double            avgEntry;
   double            floatPL;          // currency, incl. swap
   int               dir;              // +1 long basket, -1 short
   datetime          firstEntryTime;
   datetime          lastEntryTime;
   double            lastEntryPrice;
   double            firstEntryVolume;
  };

//=========================== GLOBAL STATE ===========================

// normalized confidence weights (§8)
double   g_w1,g_w2,g_w3,g_w4,g_w5,g_w6;
// chart-timeframe indicator handles
int      g_hATR=INVALID_HANDLE,g_hADX=INVALID_HANDLE,g_hRSI=INVALID_HANDLE;
int      g_hMACD=INVALID_HANDLE,g_hEMA20=INVALID_HANDLE,g_hEMA50=INVALID_HANDLE;
int      g_hBands=INVALID_HANDLE;
// higher-timeframe handles for the MTF engine (§7): D1, H4, H1
ENUM_TIMEFRAMES g_mtfTf[3];
int      g_hAdxTF[3],g_hEma20TF[3],g_hEma50TF[3],g_hAtrTF[3];
// structure engine state (§2, §6)
double   g_swPrice[];
bool     g_swIsHigh[];
int      g_structDir=0;
double   g_peakMomAbs=0.0;
// basket persistent state (§11, §12)
double   g_entryConfidence=0.0;
double   g_initialRiskAmt=0.0;
double   g_initialLot=0.0;
double   g_trailMultEff=0.0;
ulong    g_partialDone[];              // tickets already scaled out (§14)
ulong    g_beDone[];                   // tickets already moved to break-even
// execution-quality rings (§10)
int      g_fills[];
double   g_slips[];
int      g_execHead=0,g_execCount=0;
// rolling confidence distribution — the self-calibrating threshold (§9)
double   g_confSamples[];
int      g_confHead=0,g_confCount=0;
double   g_entryPct;                   // adaptive base entry percentile
double   g_effectivePct;               // after watchdog relaxation (§26)
int      g_barsSinceEntry=0;           // §26
// analytics (§18)
double   g_profits[];
double   g_grossWin=0.0,g_grossLoss=0.0;
int      g_wins=0,g_losses=0;
double   g_expAll=0.0,g_expRecent=0.0;
double   g_equityCurveMult=1.0;        // §25
// risk engine state (§13)
double   g_dayStartEquity=0.0;
int      g_dayKey=-1;
double   g_peakEquity=0.0;
bool     g_breakerLatched=false;
// core loop state
SMarketSnapshot g_snap;
bool     g_haveSnap=false;
datetime g_lastBar=0;
bool     g_breakerLogged=false;
datetime g_lastEntryTime=0;
// diagnostics (§20)
int      g_logHandle=INVALID_HANDLE;
string   g_blockReason="waiting for data";
string   g_lastLoggedReason="";
datetime g_lastReasonLog=0;
int      g_entriesTaken=0;
bool     g_seeded=false;

//======================= LOGGING & DIAGNOSTICS (§20) ================

void LogInit(void)
  {
   g_logHandle=INVALID_HANDLE;
   if(InpCsvLog)
     {
      g_logHandle=FileOpen("MedulaLog.csv",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(g_logHandle!=INVALID_HANDLE)
        {
         if(FileSize(g_logHandle)==0)
            FileWriteString(g_logHandle,"time;symbol;regime;structure;trend;momentum;flow;volPct;liquidity;mtf;confidence;pctile;quality;decision;lots;reason\n");
         FileSeek(g_logHandle,0,SEEK_END);
        }
     }
  }

void LogClose(void)
  {
   if(g_logHandle!=INVALID_HANDLE)
     {
      FileClose(g_logHandle);
      g_logHandle=INVALID_HANDLE;
     }
  }

void LogEvent(const string msg)
  {
   if(InpVerboseLog)
      Print("[Medula] ",msg);
  }

// structured decision record: full input vector that produced the action
void LogDecision(const string decision,const double lots,const string reason)
  {
   string line=StringFormat("%s;%s;%s;%.1f;%.1f;%.1f;%.1f;%.1f;%.1f;%.2f;%.1f;%.1f;%.1f;%s;%.2f;%s",
                            TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                            _Symbol,RegimeName(g_snap.regime),
                            g_snap.structureScore,g_snap.trendScore,g_snap.momentumScore,
                            g_snap.orderFlowScore,g_snap.volPercentile,g_snap.liquidityScore,
                            g_snap.mtfAlignment,g_snap.confidenceFinal,g_snap.confPercentile,
                            g_snap.tradeQuality,decision,lots,reason);
   if(InpVerboseLog)
      Print("[Medula] ",line);
   if(g_logHandle!=INVALID_HANDLE)
     {
      FileWriteString(g_logHandle,line+"\n");
      FileFlush(g_logHandle);
     }
  }

// records why no entry was taken; throttled so one persistent cause
// cannot flood the log, but never silent the way v1 was
void Block(const string reason)
  {
   g_blockReason=reason;
   if(!InpDiagnostics)
      return;
   datetime now=TimeCurrent();
   if(reason==g_lastLoggedReason && (now-g_lastReasonLog)<InpDiagThrottleSec)
      return;
   g_lastLoggedReason=reason;
   g_lastReasonLog=now;
   LogEvent("no entry — "+reason);
  }

//============================ INDICATORS ============================

bool IndInit(void)
  {
   g_mtfTf[0]=PERIOD_D1;
   g_mtfTf[1]=PERIOD_H4;
   g_mtfTf[2]=PERIOD_H1;

   g_hATR  =iATR(_Symbol,_Period,InpAtrPeriod);
   g_hADX  =iADX(_Symbol,_Period,InpAdxPeriod);
   g_hRSI  =iRSI(_Symbol,_Period,InpRsiPeriod,PRICE_CLOSE);
   g_hMACD =iMACD(_Symbol,_Period,12,26,9,PRICE_CLOSE);
   g_hEMA20=iMA(_Symbol,_Period,20,0,MODE_EMA,PRICE_CLOSE);
   g_hEMA50=iMA(_Symbol,_Period,50,0,MODE_EMA,PRICE_CLOSE);
   g_hBands=iBands(_Symbol,_Period,InpBbPeriod,0,InpBbDev,PRICE_CLOSE);
   if(g_hATR==INVALID_HANDLE || g_hADX==INVALID_HANDLE || g_hRSI==INVALID_HANDLE ||
      g_hMACD==INVALID_HANDLE || g_hEMA20==INVALID_HANDLE || g_hEMA50==INVALID_HANDLE ||
      g_hBands==INVALID_HANDLE)
      return false;

   for(int i=0;i<3;i++)
     {
      g_hAdxTF[i]  =iADX(_Symbol,g_mtfTf[i],InpAdxPeriod);
      g_hEma20TF[i]=iMA(_Symbol,g_mtfTf[i],20,0,MODE_EMA,PRICE_CLOSE);
      g_hEma50TF[i]=iMA(_Symbol,g_mtfTf[i],50,0,MODE_EMA,PRICE_CLOSE);
      g_hAtrTF[i]  =iATR(_Symbol,g_mtfTf[i],InpAtrPeriod);
      if(g_hAdxTF[i]==INVALID_HANDLE || g_hEma20TF[i]==INVALID_HANDLE ||
         g_hEma50TF[i]==INVALID_HANDLE || g_hAtrTF[i]==INVALID_HANDLE)
         return false;
     }
   return true;
  }

void IndRelease(void)
  {
   if(g_hATR!=INVALID_HANDLE)   IndicatorRelease(g_hATR);
   if(g_hADX!=INVALID_HANDLE)   IndicatorRelease(g_hADX);
   if(g_hRSI!=INVALID_HANDLE)   IndicatorRelease(g_hRSI);
   if(g_hMACD!=INVALID_HANDLE)  IndicatorRelease(g_hMACD);
   if(g_hEMA20!=INVALID_HANDLE) IndicatorRelease(g_hEMA20);
   if(g_hEMA50!=INVALID_HANDLE) IndicatorRelease(g_hEMA50);
   if(g_hBands!=INVALID_HANDLE) IndicatorRelease(g_hBands);
   for(int i=0;i<3;i++)
     {
      if(g_hAdxTF[i]!=INVALID_HANDLE)   IndicatorRelease(g_hAdxTF[i]);
      if(g_hEma20TF[i]!=INVALID_HANDLE) IndicatorRelease(g_hEma20TF[i]);
      if(g_hEma50TF[i]!=INVALID_HANDLE) IndicatorRelease(g_hEma50TF[i]);
      if(g_hAtrTF[i]!=INVALID_HANDLE)   IndicatorRelease(g_hAtrTF[i]);
     }
  }

// single-value fetch; EMPTY_VALUE on failure so callers can guard
double IndVal(const int handle,const int buffer,const int shift)
  {
   double tmp[1];
   if(CopyBuffer(handle,buffer,shift,1,tmp)!=1)
      return EMPTY_VALUE;
   return tmp[0];
  }

//===================== ANALYSIS ENGINES (§1-§7) =====================

//--- Kaufman Efficiency Ratio (§1): net move / path length
double EfficiencyRatio(const string sym,const ENUM_TIMEFRAMES tf,const int n)
  {
   double c[];
   ArraySetAsSeries(c,true);
   if(CopyClose(sym,tf,0,n+1,c)<n+1)
      return 0.0;
   double num=MathAbs(c[0]-c[n]);
   double den=0.0;
   for(int i=1;i<=n;i++)
      den+=MathAbs(c[i-1]-c[i]);
   return (den>0.0 ? num/den : 0.0);
  }

//--- Volatility Ratio, Percentile and Suitability (§1, §5)
void UpdateVolatility(void)
  {
   int n=InpVolPctBars;
   double a[];
   ArraySetAsSeries(a,true);
   if(CopyBuffer(g_hATR,0,0,n+1,a)<n+1)
     {
      g_snap.vr=1.0;
      g_snap.volPercentile=50.0;
      g_snap.volSuitability=100.0;
      return;
     }
   int below=0;
   for(int i=1;i<=n;i++)
      if(a[i]<a[0])
         below++;
   g_snap.volPercentile=100.0*(double)below/(double)n;

   int ref=MathMin(InpVolRefBars,n);
   double s=0.0;
   for(int i=0;i<ref;i++)
      s+=a[i];
   double atrRef=s/(double)ref;
   g_snap.vr=(atrRef>0.0 ? a[0]/atrRef : 1.0);

   // Gaussian suitability centered at the 55th percentile, sigma 30 (§5)
   double z=(g_snap.volPercentile-55.0)/30.0;
   g_snap.volSuitability=100.0*MathExp(-0.5*z*z);
  }

//--- Volatility Forecast Engine (§23): RiskMetrics EWMA variance.
//    sigma^2_t = lambda*sigma^2_{t-1} + (1-lambda)*r^2_{t-1}
//    Ratio of the one-step forecast to realized volatility tells us whether
//    the market is about to expand or contract, rather than only what it
//    just did — used to pre-emptively size down into expansions.
void UpdateVolForecast(void)
  {
   g_snap.volForecastRatio=1.0;
   if(!InpUseVolForecast)
      return;
   int n=InpVolFcBars;
   double c[];
   ArraySetAsSeries(c,true);
   if(CopyClose(_Symbol,_Period,0,n+2,c)<n+2)
      return;

   double var=0.0;
   int cnt=0;
   for(int i=n;i>=1;i--)                       // oldest -> newest
     {
      if(c[i]<=0.0) continue;
      double r=(c[i-1]-c[i])/c[i];
      if(cnt==0) var=r*r;
      else       var=InpEwmaLambda*var+(1.0-InpEwmaLambda)*r*r;
      cnt++;
     }
   if(cnt<10 || var<=0.0)
      return;

   double sigmaFc=MathSqrt(var);
   // realized volatility over the same window, as the comparison baseline
   double mean=0.0,sum2=0.0;
   int m=0;
   for(int i=n;i>=1;i--)
     {
      if(c[i]<=0.0) continue;
      double r=(c[i-1]-c[i])/c[i];
      mean+=r; m++;
     }
   if(m<10) return;
   mean/=m;
   for(int i=n;i>=1;i--)
     {
      if(c[i]<=0.0) continue;
      double r=(c[i-1]-c[i])/c[i];
      sum2+=(r-mean)*(r-mean);
     }
   double sigmaReal=MathSqrt(sum2/m);
   if(sigmaReal<=0.0) return;
   g_snap.volForecastRatio=MClamp(sigmaFc/sigmaReal,0.25,4.0);
  }

//--- Order Flow Engine (§22): tick-volume weighted close location.
//    CLV = ((C-L)-(H-C))/(H-L) puts each bar's close on a -1..+1 axis
//    between its own extremes; weighting by tick volume approximates where
//    participation actually occurred. Positive = buyers closing strong.
void UpdateOrderFlow(void)
  {
   g_snap.orderFlowScore=0.0;
   if(!InpUseOrderFlow)
      return;
   int n=InpFlowBars;
   double hi[],lo[],cl[];
   long tv[];
   ArraySetAsSeries(hi,true);
   ArraySetAsSeries(lo,true);
   ArraySetAsSeries(cl,true);
   ArraySetAsSeries(tv,true);
   if(CopyHigh(_Symbol,_Period,0,n,hi)<n)        return;
   if(CopyLow(_Symbol,_Period,0,n,lo)<n)         return;
   if(CopyClose(_Symbol,_Period,0,n,cl)<n)       return;
   if(CopyTickVolume(_Symbol,_Period,0,n,tv)<n)  return;

   double num=0.0,den=0.0;
   for(int i=0;i<n;i++)
     {
      double rng=hi[i]-lo[i];
      if(rng<=0.0) continue;
      double clv=((cl[i]-lo[i])-(hi[i]-cl[i]))/rng;   // -1..+1
      double w=(double)tv[i];
      if(w<=0.0) w=1.0;
      num+=clv*w;
      den+=w;
     }
   if(den<=0.0)
      return;
   g_snap.orderFlowScore=100.0*MTanh(InpFlowGain*(num/den));
  }

bool IsSwingHigh(const double &hi[],const int j,const int k)
  {
   for(int m=1;m<=k;m++)
      if(hi[j]<=hi[j+m] || hi[j]<=hi[j-m])
         return false;
   return true;
  }

bool IsSwingLow(const double &lo[],const int j,const int k)
  {
   for(int m=1;m<=k;m++)
      if(lo[j]>=lo[j+m] || lo[j]>=lo[j-m])
         return false;
   return true;
  }

void PushSwing(const double price,const bool isHigh)
  {
   int n=ArraySize(g_swPrice);
   ArrayResize(g_swPrice,n+1);
   ArrayResize(g_swIsHigh,n+1);
   g_swPrice[n]=price;
   g_swIsHigh[n]=isHigh;
  }

//--- Market Structure Engine (§2): swings, BOS, CHoCH, structure score.
//    Replays the lookback window chronologically; a fractal only becomes
//    tradable information k bars after it forms (causal confirmation).
void UpdateStructure(void)
  {
   g_snap.bullBos=false;   g_snap.bearBos=false;
   g_snap.bullChoch=false; g_snap.bearChoch=false;

   int bars=InpStructLookback;
   double hi[],lo[],cl[];
   ArraySetAsSeries(hi,true);
   ArraySetAsSeries(lo,true);
   ArraySetAsSeries(cl,true);
   if(CopyHigh(_Symbol,_Period,0,bars,hi)<bars)  return;
   if(CopyLow(_Symbol,_Period,0,bars,lo)<bars)   return;
   if(CopyClose(_Symbol,_Period,0,bars,cl)<bars) return;

   int k=InpSwingK;
   ArrayResize(g_swPrice,0);
   ArrayResize(g_swIsHigh,0);
   int events[];
   ArrayResize(events,0);

   double lastSH=0.0,lastSL=0.0;
   int trendDir=0;

   for(int b=bars-1-k;b>=0;b--)
     {
      int j=b+k;                    // swing at j confirms k bars later = bar b
      if(j<=bars-1-k)
        {
         if(IsSwingHigh(hi,j,k)) { PushSwing(hi[j],true);  lastSH=hi[j]; }
         if(IsSwingLow(lo,j,k))  { PushSwing(lo[j],false); lastSL=lo[j]; }
        }
      if(lastSH>0.0 && cl[b]>lastSH)
        {
         bool choch=(trendDir==-1);
         trendDir=1;
         if(choch) { if(b==0) g_snap.bullChoch=true; }
         else      { PushInt(events,1); if(b==0) g_snap.bullBos=true; }
         lastSH=0.0;                // consume the level until a new swing confirms
        }
      if(lastSL>0.0 && cl[b]<lastSL)
        {
         bool choch=(trendDir==1);
         trendDir=-1;
         if(choch) { if(b==0) g_snap.bearChoch=true; }
         else      { PushInt(events,-1); if(b==0) g_snap.bearBos=true; }
         lastSL=0.0;
        }
     }

   int total=ArraySize(events);
   int nEv=MathMin(total,InpStructEvents);
   int bull=0,bear=0;
   for(int i=total-nEv;i<total;i++)
     {
      if(events[i]>0) bull++;
      else            bear++;
     }
   g_snap.structureScore=100.0*(double)(bull-bear)/(double)(bull+bear+1);
   g_structDir=trendDir;
  }

//--- Trend score core (§3), shared by chart TF, higher TFs and the seeder.
//    ADX (c1) and efficiency (c3) are strength-only, so they are signed
//    by the EMA direction to keep the composite score directional.
double TrendScoreCore(const double adx,const double e50_0,const double e50_n,
                      const double e20_0,const double atr,const double er,bool &valid)
  {
   valid=false;
   if(atr<=0.0 || atr==EMPTY_VALUE || adx==EMPTY_VALUE || e50_0==EMPTY_VALUE ||
      e50_n==EMPTY_VALUE || e20_0==EMPTY_VALUE)
      return 0.0;
   valid=true;
   double slope=(e50_0-e50_n)/((double)InpSlopeBars*atr);
   double c1=MTanh(adx/25.0-1.0);
   double c2=MTanh(slope*10.0);
   double c3=MTanh((er-0.2)*5.0);
   double c4=(double)MSign(e20_0-e50_0);
   int dirSign=MSign(e20_0-e50_0);
   if(dirSign==0)
      dirSign=MSign(slope);
   return 100.0*(0.35*c1*dirSign+0.30*c2+0.20*c3*dirSign+0.15*c4);
  }

void UpdateTrend(void)
  {
   bool v;
   g_snap.trendScore=TrendScoreCore(g_snap.adx,
                                    IndVal(g_hEMA50,0,0),
                                    IndVal(g_hEMA50,0,InpSlopeBars),
                                    IndVal(g_hEMA20,0,0),
                                    g_snap.atr,
                                    g_snap.er,v);
   g_snap.trendDir=MSign(g_snap.trendScore);
  }

//--- Momentum score core (§4), shared by live path and the seeder
double MomentumScoreCore(const double rsi,const double roc0,
                         const double macdSlope,const double atr)
  {
   if(atr<=0.0 || rsi==EMPTY_VALUE)
      return 0.0;
   return 100.0*MTanh(0.40*((rsi-50.0)/50.0)
                     +0.30*MTanh(roc0/2.0)
                     +0.30*MTanh(macdSlope/(0.1*atr)));
  }

void UpdateMomentum(void)
  {
   g_snap.momentumScore=0.0;
   g_snap.momentumAccel=0.0;
   int n=InpRocLen;
   double c[];
   ArraySetAsSeries(c,true);
   if(CopyClose(_Symbol,_Period,0,n+2,c)<n+2)
      return;
   if(c[n]<=0.0 || c[n+1]<=0.0 || g_snap.atr<=0.0)
      return;
   double roc0=(c[0]-c[n])/c[n]*100.0;
   double roc1=(c[1]-c[n+1])/c[n+1]*100.0;

   double rsi=IndVal(g_hRSI,0,0);
   double m0=IndVal(g_hMACD,0,0),s0=IndVal(g_hMACD,1,0);
   double m1=IndVal(g_hMACD,0,1),s1=IndVal(g_hMACD,1,1);
   if(rsi==EMPTY_VALUE || m0==EMPTY_VALUE || s0==EMPTY_VALUE ||
      m1==EMPTY_VALUE || s1==EMPTY_VALUE)
      return;

   g_snap.momentumScore=MomentumScoreCore(rsi,roc0,(m0-s0)-(m1-s1),g_snap.atr);
   g_snap.momentumAccel=roc0-roc1;

   // rolling peak with slow decay, used by the exhaustion rule (§14)
   g_peakMomAbs=MathMax(MathAbs(g_snap.momentumScore),g_peakMomAbs*0.995);
  }

//--- Liquidity Engine (§6): swing-point pools within 3*ATR of price
void UpdateLiquidity(void)
  {
   double d=InpLiqRangeAtr*g_snap.atr;
   double above=0.0,below=0.0;
   int n=ArraySize(g_swPrice);
   for(int i=0;i<n;i++)
     {
      double p=g_swPrice[i];
      if(p>g_snap.close && p-g_snap.close<=d)
         above+=1.0;
      else if(p<g_snap.close && g_snap.close-p<=d)
         below+=1.0;
     }
   g_snap.liquidityScore=100.0*MTanh((below-above)/(below+above+1.0));
  }

//--- Multi-Timeframe Engine (§7): D1 0.40, H4 0.30, H1 0.20, chart 0.10.
//    A higher timeframe whose history is not yet loaded does not count as
//    "disagreement" — its weight is redistributed across the timeframes
//    that do have data, and the veto stands down if too little is available.
void UpdateMTF(void)
  {
   double w[4]={0.40,0.30,0.20,0.10};
   double align=0.0,validW=0.0;
   for(int i=0;i<3;i++)
     {
      bool valid=false;
      double er=EfficiencyRatio(_Symbol,g_mtfTf[i],InpErLen);
      double ts=TrendScoreCore(IndVal(g_hAdxTF[i],0,0),
                               IndVal(g_hEma50TF[i],0,0),
                               IndVal(g_hEma50TF[i],0,InpSlopeBars),
                               IndVal(g_hEma20TF[i],0,0),
                               IndVal(g_hAtrTF[i],0,0),
                               er,valid);
      if(valid)
        {
         align+=w[i]*(double)MSign(ts);
         validW+=w[i];
        }
     }
   align+=w[3]*(double)g_snap.trendDir;
   validW+=w[3];

   if(validW>0.0)
      align/=validW;                 // renormalize onto -1..+1
   g_snap.mtfAlignment=align;
   g_snap.mtfConfluence=MathAbs(align)*100.0;
   g_snap.mtfValidWeight=validW;
  }

//--- Market State Engine (§1) with the spec's priority ordering
void ClassifyRegime(void)
  {
   bool trending=(g_snap.adx>25.0 && g_snap.er>0.30);
   bool ranging =(g_snap.adx<20.0 && g_snap.er<0.20);
   bool hiVol   =(g_snap.volPercentile>90.0);
   bool loVol   =(g_snap.volPercentile<10.0);

   double bu=IndVal(g_hBands,1,0),bl=IndVal(g_hBands,2,0);
   bool breakout=false;
   if(bu!=EMPTY_VALUE && bl!=EMPTY_VALUE)
      breakout=(g_snap.vr>1.5 &&
                ((g_snap.close>bu && g_snap.momentumScore>0.0) ||
                 (g_snap.close<bl && g_snap.momentumScore<0.0)));

   bool reversal=(g_snap.bullChoch && g_snap.momentumScore>0.0) ||
                 (g_snap.bearChoch && g_snap.momentumScore<0.0);

   if(reversal)      g_snap.regime=REGIME_REVERSAL;
   else if(breakout) g_snap.regime=REGIME_BREAKOUT;
   else if(hiVol)    g_snap.regime=REGIME_HIGH_VOL;
   else if(trending) g_snap.regime=REGIME_TRENDING;
   else if(ranging)  g_snap.regime=REGIME_RANGING;
   else if(loVol)    g_snap.regime=REGIME_LOW_VOL;
   else              g_snap.regime=REGIME_NEUTRAL;
  }

//--- run all analysis engines and fill the snapshot
bool AnalysisUpdate(void)
  {
   double atr=IndVal(g_hATR,0,0);
   if(atr==EMPTY_VALUE || atr<=0.0)
     {
      Block("indicator history not ready (ATR)");
      return false;
     }
   double adx=IndVal(g_hADX,0,0);
   if(adx==EMPTY_VALUE)
     {
      Block("indicator history not ready (ADX)");
      return false;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
     {
      Block("no tick data from broker");
      return false;
     }

   g_snap.atr=atr;
   g_snap.adx=adx;
   g_snap.bid=tick.bid;
   g_snap.ask=tick.ask;
   g_snap.close=tick.bid;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   g_snap.spreadPts=(pt>0.0 ? (tick.ask-tick.bid)/pt : 0.0);

   g_snap.er=EfficiencyRatio(_Symbol,_Period,InpErLen);   // §1

   UpdateVolatility();    // §1, §5
   UpdateVolForecast();   // §23
   UpdateStructure();     // §2
   UpdateTrend();         // §3
   UpdateMomentum();      // §4
   UpdateLiquidity();     // §6
   UpdateOrderFlow();     // §22
   UpdateMTF();           // §7
   ClassifyRegime();      // §1
   return true;
  }

//================= CONFIDENCE & DECISION (§8-§9) ====================

//--- shared confidence core so the live path and the history seeder
//    cannot drift apart
//    v2.60: conviction measures the MARKET ONLY. Spread and execution
//    quality are trading costs, not evidence about direction -- they gate
//    entries (§10) and shape the quality score (§24). In v2.50 they were
//    multiplied into conviction, and because the spread factor reaches
//    exactly 0 at the limit, a single mis-scaled spread setting pinned
//    conviction at 0.0 on every bar and silenced the whole EA.
double ConfidenceCore(const double structS,const double trendS,const double momS,
                      const double liqS,const double mtfA,const double flowS,
                      const double volSuit)
  {
   double raw=g_w1*(structS/100.0)
             +g_w2*(trendS/100.0)
             +g_w3*(momS/100.0)
             +g_w4*(liqS/100.0)
             +g_w5*mtfA
             +g_w6*(flowS/100.0);
   double cdir=100.0*MTanh(InpConfGain*raw);
   return MathAbs(cdir)*MClamp(volSuit/100.0,0.0,1.0);
  }

//--- Effective spread limit (§10). An absolute point limit cannot travel
//    between instruments: 40 points is generous on EURUSD and impossible
//    on 3-digit gold. Scaling by ATR self-calibrates to the symbol's own
//    bar range, with the point value as a floor.
//    This gate is deliberately PERMISSIVE — it is a backstop against
//    genuinely broken conditions (news spikes, rollover, illiquidity),
//    not a cost filter. The economics of spread are priced properly by
//    the Trade Quality Score (§24), which measures the edge remaining
//    after round-turn cost against the actual profit target. Making this
//    gate strict duplicates that job badly and silences the EA.
double MaxSpreadPointsEffective(void)
  {
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double byAtr=0.0;
   if(pt>0.0 && g_snap.atr>0.0)
      byAtr=InpMaxSpreadAtr*(g_snap.atr/pt);
   return MathMax(byAtr,MathMax(InpMaxSpreadPoints,1.0));
  }

//--- Confidence Engine (§8). A routine dealing spread costs nothing; the
//    penalty only ramps as spread approaches the hard limit.
void ComputeConfidence(void)
  {
   double raw=g_w1*(g_snap.structureScore/100.0)
             +g_w2*(g_snap.trendScore/100.0)
             +g_w3*(g_snap.momentumScore/100.0)
             +g_w4*(g_snap.liquidityScore/100.0)
             +g_w5*g_snap.mtfAlignment
             +g_w6*(g_snap.orderFlowScore/100.0);

   g_snap.confidenceDir=100.0*MTanh(InpConfGain*raw);
   g_snap.confidenceFinal=ConfidenceCore(g_snap.structureScore,g_snap.trendScore,
                                         g_snap.momentumScore,g_snap.liquidityScore,
                                         g_snap.mtfAlignment,g_snap.orderFlowScore,
                                         g_snap.volSuitability);
  }

//--- rolling confidence distribution: one sample per closed bar (§9)
void PushConfidenceSample(const double conf)
  {
   int w=ArraySize(g_confSamples);
   if(w<=0) return;
   g_confSamples[g_confHead]=conf;
   g_confHead=(g_confHead+1)%w;
   if(g_confCount<w)
      g_confCount++;
  }

//--- percentile rank of the current conviction within its own history.
//    This is the self-calibrating threshold: whatever range of conviction
//    this symbol/timeframe produces, the top band always exists.
double ConfidencePercentile(const double conf)
  {
   if(g_confCount<=0)
      return 50.0;
   int below=0;
   for(int i=0;i<g_confCount;i++)
      if(g_confSamples[i]<conf)
         below++;
   return 100.0*(double)below/(double)g_confCount;
  }

//--- distribution shape, for the panel and the self-test
double DistributionPercentile(const double p)
  {
   if(g_confCount<=0)
      return 0.0;
   double tmp[];
   ArrayResize(tmp,g_confCount);
   for(int i=0;i<g_confCount;i++)
      tmp[i]=g_confSamples[i];
   ArraySort(tmp);
   int idx=(int)MClamp(MathRound(p/100.0*(g_confCount-1)),0,g_confCount-1);
   return tmp[idx];
  }

bool PercentileModeActive(void)
  {
   return (InpUsePercentile && g_confCount>=InpMinSamples);
  }

//--- Seed the distribution from history (§9) so percentile mode is live on
//    the first tick rather than after InpMinSamples bars of real time.
//    Structure/liquidity/MTF are held at their current values because a
//    per-bar structural replay is O(n^2); trend, momentum, order flow and
//    volatility — which carry most of the variance — are recomputed per bar.
//    Seeds are overwritten by live samples as the ring cycles.
int SeedDistributionFromHistory(void)
  {
   if(!InpSeedFromHistory)
      return 0;

   int want=ArraySize(g_confSamples);
   if(want<=0) return 0;
   int pad=InpSlopeBars+InpRocLen+InpVolPctBars+2;
   int need=want+pad;
   // accept a shorter seed rather than none at all

   double atrB[],adxB[],rsiB[],macdM[],macdS[],e20B[],e50B[],cl[],hi[],lo[];
   long tv[];
   ArraySetAsSeries(atrB,true);  ArraySetAsSeries(adxB,true);
   ArraySetAsSeries(rsiB,true);  ArraySetAsSeries(macdM,true);
   ArraySetAsSeries(macdS,true); ArraySetAsSeries(e20B,true);
   ArraySetAsSeries(e50B,true);  ArraySetAsSeries(cl,true);
   ArraySetAsSeries(hi,true);    ArraySetAsSeries(lo,true);
   ArraySetAsSeries(tv,true);

   int got=CopyBuffer(g_hATR,0,0,need,atrB);
   if(got<pad+20)
     {
      got=CopyBuffer(g_hATR,0,0,pad+60,atrB);   // minimal viable seed
      if(got<pad+20)
         return 0;
     }                             // not enough history to seed
   need=got;
   if(CopyBuffer(g_hADX,0,0,need,adxB)<need)   return 0;
   if(CopyBuffer(g_hRSI,0,0,need,rsiB)<need)   return 0;
   if(CopyBuffer(g_hMACD,0,0,need,macdM)<need) return 0;
   if(CopyBuffer(g_hMACD,1,0,need,macdS)<need) return 0;
   if(CopyBuffer(g_hEMA20,0,0,need,e20B)<need) return 0;
   if(CopyBuffer(g_hEMA50,0,0,need,e50B)<need) return 0;
   if(CopyClose(_Symbol,_Period,0,need,cl)<need) return 0;
   if(CopyHigh(_Symbol,_Period,0,need,hi)<need)  return 0;
   if(CopyLow(_Symbol,_Period,0,need,lo)<need)   return 0;
   bool haveVol=(CopyTickVolume(_Symbol,_Period,0,need,tv)>=need);

   int last=need-pad-1;
   if(last<10) return 0;

   int seeded=0;
   for(int s=last;s>=0;s--)                 // oldest -> newest
     {
      double atr=atrB[s];
      if(atr<=0.0) continue;

      // efficiency ratio at shift s
      double num=MathAbs(cl[s]-cl[s+InpErLen]);
      double den=0.0;
      for(int i=1;i<=InpErLen;i++)
         den+=MathAbs(cl[s+i-1]-cl[s+i]);
      double er=(den>0.0 ? num/den : 0.0);

      bool v=false;
      double trendS=TrendScoreCore(adxB[s],e50B[s],e50B[s+InpSlopeBars],
                                   e20B[s],atr,er,v);

      double roc0=0.0;
      if(cl[s+InpRocLen]>0.0)
         roc0=(cl[s]-cl[s+InpRocLen])/cl[s+InpRocLen]*100.0;
      double macdSlope=(macdM[s]-macdS[s])-(macdM[s+1]-macdS[s+1]);
      double momS=MomentumScoreCore(rsiB[s],roc0,macdSlope,atr);

      // ATR percentile at shift s -> volatility suitability
      int below=0;
      for(int i=1;i<=InpVolPctBars;i++)
         if(atrB[s+i]<atr)
            below++;
      double volPct=100.0*(double)below/(double)InpVolPctBars;
      double z=(volPct-55.0)/30.0;
      double volSuit=100.0*MathExp(-0.5*z*z);

      // order flow at shift s
      double flowS=0.0;
      if(InpUseOrderFlow)
        {
         double fnum=0.0,fden=0.0;
         for(int i=0;i<InpFlowBars && (s+i)<need;i++)
           {
            double rng=hi[s+i]-lo[s+i];
            if(rng<=0.0) continue;
            double clv=((cl[s+i]-lo[s+i])-(hi[s+i]-cl[s+i]))/rng;
            double w=(haveVol ? (double)tv[s+i] : 1.0);
            if(w<=0.0) w=1.0;
            fnum+=clv*w; fden+=w;
           }
         if(fden>0.0)
            flowS=100.0*MTanh(InpFlowGain*(fnum/fden));
        }

      double conf=ConfidenceCore(g_snap.structureScore,trendS,momS,
                                 g_snap.liquidityScore,g_snap.mtfAlignment,flowS,
                                 volSuit);
      PushConfidenceSample(conf);
      seeded++;
     }
   return seeded;
  }

//--- Participation Watchdog (§26). If the EA has been flat for an
//    unreasonable stretch, selectivity is released one step at a time down
//    to a hard floor. This relaxes only HOW PICKY the EA is — the absolute
//    conviction floor, the risk caps, the spread limit and the circuit
//    breaker are never touched. Resets the moment a trade is taken.
double EffectiveEntryPercentile(void)
  {
   double pct=g_entryPct;
   if(!InpUseWatchdog)
      return pct;
   if(g_barsSinceEntry<=InpIdleBarsRelax)
      return pct;
   int steps=1+(g_barsSinceEntry-InpIdleBarsRelax)/MathMax(InpRelaxEveryBars,1);
   pct-=steps*InpRelaxStepPct;
   return MathMax(pct,InpRelaxFloorPct);
  }

//--- Trade Quality Score (§24): a pre-trade scorecard independent of the
//    conviction ranking. Conviction says "the evidence agrees"; quality
//    asks "is this a setup worth the cost of trading right now" — spread
//    relative to target, regime fit, session, higher-timeframe backing.
double ComputeTradeQuality(const int dir)
  {
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double tpDist=InpTpAtrMult*g_snap.atr;
   double costPts=g_snap.spreadPts*2.0;                 // round turn
   double costPrice=costPts*pt;
   double edgeAfterCost=(tpDist>0.0 ? MClamp(1.0-costPrice/tpDist,0.0,1.0) : 0.0);

   double regimeFit=0.5;
   switch(g_snap.regime)
     {
      case REGIME_TRENDING: regimeFit=1.0;  break;
      case REGIME_BREAKOUT: regimeFit=0.9;  break;
      case REGIME_NEUTRAL:  regimeFit=0.6;  break;
      case REGIME_RANGING:  regimeFit=0.45; break;
      case REGIME_REVERSAL: regimeFit=0.5;  break;
      case REGIME_HIGH_VOL: regimeFit=0.4;  break;
      case REGIME_LOW_VOL:  regimeFit=0.4;  break;
     }

   double htfBacking=(MSign(g_snap.mtfAlignment)==dir
                      ? MClamp(g_snap.mtfConfluence/100.0,0.0,1.0)
                      : 0.15);
   double flowBacking=(InpUseOrderFlow
                       ? MClamp(0.5+0.5*(dir*g_snap.orderFlowScore/100.0),0.0,1.0)
                       : 0.6);
   double sessQ=MClamp(SessionMultiplierRaw()/1.2,0.0,1.0);
   double volQ=MClamp(g_snap.volSuitability/100.0,0.0,1.0);
   // an expected volatility expansion is a headwind for a fixed-ATR stop
   double fcQ=MClamp(1.0-0.4*MathMax(g_snap.volForecastRatio-1.0,0.0),0.4,1.0);

   double q=100.0*(0.24*edgeAfterCost
                  +0.20*regimeFit
                  +0.18*htfBacking
                  +0.14*flowBacking
                  +0.12*volQ
                  +0.07*sessQ
                  +0.05*fcQ);
   return MClamp(q,0.0,100.0);
  }

//--- Decision Engine (§9)
ENUM_DECISION Decide(const bool inTrade,const int basketDir)
  {
   int dir=MSign(g_snap.confidenceDir);

   if(!inTrade)
     {
      if(dir==0)
        {
         Block("no directional edge (conviction sign is zero)");
         return DECISION_WAIT;
        }
      if(g_snap.confidenceFinal<InpMinAbsConfidence)
        {
         Block(StringFormat("conviction %.1f below absolute floor %.1f (market offers nothing)",
                            g_snap.confidenceFinal,InpMinAbsConfidence));
         return DECISION_WAIT;
        }
      if(PercentileModeActive())
        {
         if(g_snap.confPercentile<g_effectivePct)
           {
            Block(StringFormat("conviction %.1f ranks %.0f pct, needs %.0f (idle %d bars)",
                               g_snap.confidenceFinal,g_snap.confPercentile,
                               g_effectivePct,g_barsSinceEntry));
            return DECISION_WAIT;
           }
        }
      else if(g_snap.confidenceFinal<InpBootstrapConf)
        {
         Block(StringFormat("bootstrapping (%d/%d samples), conviction %.1f < %.1f",
                            g_confCount,InpMinSamples,g_snap.confidenceFinal,InpBootstrapConf));
         return DECISION_WAIT;
        }
      // MTF veto (§7): only when enough higher-timeframe data is loaded
      if(g_snap.mtfValidWeight>=0.5 &&
         MSign(g_snap.mtfAlignment)!=dir && g_snap.mtfConfluence>InpMtfVetoConfluence)
        {
         Block(StringFormat("higher timeframes disagree (alignment %.2f, confluence %.0f)",
                            g_snap.mtfAlignment,g_snap.mtfConfluence));
         return DECISION_WAIT;
        }
      // §24 quality gate, relaxed alongside selectivity when idle
      if(InpUseQuality)
        {
         double qGate=InpMinTradeQuality;
         if(InpUseWatchdog && g_barsSinceEntry>InpIdleBarsRelax)
            qGate*=MClamp(g_effectivePct/MathMax(g_entryPct,1.0),0.6,1.0);
         if(g_snap.tradeQuality<qGate)
           {
            Block(StringFormat("trade quality %.0f below %.0f",g_snap.tradeQuality,qGate));
            return DECISION_WAIT;
           }
        }
      return (dir>0 ? DECISION_BUY : DECISION_SELL);
     }

   // in trade: exit on conviction collapse relative to entry, or a flip
   double exitFloor=MathMax(InpExitConfFraction*g_entryConfidence,InpMinAbsConfidence*0.5);
   if(g_snap.confidenceFinal<exitFloor)
      return DECISION_EXIT;
   if(dir!=0 && basketDir!=0 && dir!=basketDir &&
      g_snap.confidenceFinal>=InpMinAbsConfidence)
      return DECISION_EXIT;
   return DECISION_HOLD;
  }

//========== RISK / SESSION / CORRELATION (§13, §15-§17) =============

//--- track day boundary and equity peak (§13)
void RiskUpdate(void)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   int key=dt.year*1000+dt.day_of_year;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(key!=g_dayKey)
     {
      g_dayKey=key;
      g_dayStartEquity=eq;
      g_breakerLatched=false;          // daily-loss breaker resets each day
     }
   if(eq>g_peakEquity)
      g_peakEquity=eq;
  }

//--- circuit breaker (§13): daily loss limit OR max drawdown from peak
bool CircuitBreaker(void)
  {
   if(g_breakerLatched)
      return true;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   bool daily=(g_dayStartEquity-eq)>=g_dayStartEquity*InpDailyLossPct/100.0;
   bool dd   =(g_peakEquity-eq)>=g_peakEquity*InpMaxDDPct/100.0;
   if(daily || dd)
      g_breakerLatched=true;
   return g_breakerLatched;
  }

//--- Session Intelligence (§16), hours in GMT
double SessionMultiplierRaw(void)
  {
   MqlDateTime g;
   TimeToStruct(TimeGMT(),g);
   int h=g.hour;
   if(h>=7  && h<12) return InpSessLondon;
   if(h>=12 && h<16) return InpSessOverlap;
   if(h>=16 && h<21) return InpSessNewYork;
   if(h>=21)         return InpSessDead;
   return InpSessAsian;                // 0..6
  }

double SessionMultiplier(void)
  {
   return (InpUseSessions ? SessionMultiplierRaw() : 1.0);
  }

//--- regime-based risk modulation (spec §1 behavior table)
double RegimeRiskMult(const ENUM_REGIME r)
  {
   switch(r)
     {
      case REGIME_TRENDING: return 1.0;
      case REGIME_BREAKOUT: return 1.0;
      case REGIME_NEUTRAL:  return 0.8;
      case REGIME_RANGING:  return 0.7;
      case REGIME_LOW_VOL:  return 0.6;
      case REGIME_HIGH_VOL: return 0.5;
      case REGIME_REVERSAL: return 0.5;
     }
   return 0.8;
  }

//--- §13: LotSize = RiskAmount / (SL distance in ticks * tick value)
double LotForRisk(const double riskAmount,const double slDistPrice)
  {
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSz =SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickVal<=0.0 || tickSz<=0.0 || slDistPrice<=0.0 || riskAmount<=0.0)
      return 0.0;
   double riskPerLot=slDistPrice/tickSz*tickVal;
   if(riskPerLot<=0.0)
      return 0.0;
   return riskAmount/riskPerLot;
  }

//--- currency risk implied by a lot size at a given SL distance
double RiskOfLots(const double lots,const double slDistPrice)
  {
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSz =SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickVal<=0.0 || tickSz<=0.0)
      return 0.0;
   return slDistPrice/tickSz*tickVal*lots;
  }

double MinLot(void)
  {
   double m=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   return (m>0.0 ? m : 0.01);
  }

double LotStep(void)
  {
   double s=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   return (s>0.0 ? s : 0.01);
  }

//--- broker-constraint normalization; min-lot override keeps small
//    accounts tradable (explicit opt-in because it raises risk above plan)
double NormalizeLots(double lots)
  {
   double step=LotStep();
   double minL=MinLot();
   double maxL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   lots=MathFloor(lots/step+1e-9)*step;
   if(lots<minL)
      return (InpAllowMinLot ? minL : 0.0);
   if(maxL>0.0)
      lots=MathMin(lots,maxL);
   return lots;
  }

//--- §10 pre-trade margin validation with safety factor
bool MarginOK(const int dir,const double lots)
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t))
      return false;
   double price=(dir>0 ? t.ask : t.bid);
   double margin=0.0;
   if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,lots,price,margin))
      return false;
   return AccountInfoDouble(ACCOUNT_MARGIN_FREE)>=margin*InpMarginSafety;
  }

//--- rolling Pearson correlation of close-to-close returns (§17)
double PearsonReturns(const string a,const string b,const int n,const ENUM_TIMEFRAMES tf)
  {
   double ca[],cb[];
   ArraySetAsSeries(ca,true);
   ArraySetAsSeries(cb,true);
   if(CopyClose(a,tf,0,n+1,ca)<n+1) return 0.0;
   if(CopyClose(b,tf,0,n+1,cb)<n+1) return 0.0;

   double ra[],rb[];
   ArrayResize(ra,n);
   ArrayResize(rb,n);
   double ma=0.0,mb=0.0;
   for(int i=0;i<n;i++)
     {
      if(ca[i+1]<=0.0 || cb[i+1]<=0.0) return 0.0;
      ra[i]=(ca[i]-ca[i+1])/ca[i+1];
      rb[i]=(cb[i]-cb[i+1])/cb[i+1];
      ma+=ra[i];
      mb+=rb[i];
     }
   ma/=n; mb/=n;
   double cov=0.0,va=0.0,vb=0.0;
   for(int i=0;i<n;i++)
     {
      cov+=(ra[i]-ma)*(rb[i]-mb);
      va +=(ra[i]-ma)*(ra[i]-ma);
      vb +=(rb[i]-mb)*(rb[i]-mb);
     }
   if(va<=0.0 || vb<=0.0)
      return 0.0;
   return cov/MathSqrt(va*vb);
  }

//--- Correlation Engine (§17): soft dampener on conviction
double CorrelationDampener(const int dir)
  {
   if(!InpUseCorrelation)
      return 1.0;
   double damp=1.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      string ps=PositionGetString(POSITION_SYMBOL);
      if(ps==_Symbol) continue;
      double r=PearsonReturns(_Symbol,ps,InpCorrBars,(ENUM_TIMEFRAMES)_Period);
      if(MathAbs(r)<=InpCorrThreshold) continue;
      int pdir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
      if(pdir*MSign(r)==dir)
        {
         double x=MClamp((MathAbs(r)-InpCorrThreshold)/(1.0-InpCorrThreshold),0.0,1.0);
         damp=MathMin(damp,1.0-0.3*x);
        }
     }
   return damp;
  }

//--- correlation hard veto (§17): too many same-direction correlated legs
bool CorrelationVeto(const int dir)
  {
   if(!InpUseCorrelation)
      return false;
   int correlated=0;
   string counted="";
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      string ps=PositionGetString(POSITION_SYMBOL);
      if(ps==_Symbol) continue;
      if(StringFind(counted,"|"+ps+"|")>=0) continue;      // one count per symbol
      double r=PearsonReturns(_Symbol,ps,InpCorrBars,(ENUM_TIMEFRAMES)_Period);
      if(MathAbs(r)<=InpCorrThreshold) continue;
      int pdir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
      if(pdir*MSign(r)==dir)
        {
         correlated++;
         counted+="|"+ps+"|";
        }
     }
   return (correlated>=InpMaxCorrelated);
  }

//====== EXECUTION / BASKET / SCALING / EXITS (§10-§14) ==============

ENUM_ORDER_TYPE_FILLING FillingMode(void)
  {
   long flags=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((flags&SYMBOL_FILLING_FOK)!=0) return ORDER_FILLING_FOK;
   if((flags&SYMBOL_FILLING_IOC)!=0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

bool SendRequest(MqlTradeRequest &req,MqlTradeResult &res)
  {
   if(!OrderSend(req,res))
      return false;
   return (res.retcode==TRADE_RETCODE_DONE ||
           res.retcode==TRADE_RETCODE_DONE_PARTIAL ||
           res.retcode==TRADE_RETCODE_PLACED);
  }

//--- Execution Quality (§10)
void RecordExecution(const bool filled,const double slipPts)
  {
   int w=ArraySize(g_fills);
   if(w<=0) return;
   g_fills[g_execHead]=(filled ? 1 : 0);
   g_slips[g_execHead]=(filled ? slipPts : 0.0);
   g_execHead=(g_execHead+1)%w;
   if(g_execCount<w)
      g_execCount++;
  }

double ExecutionQuality(void)
  {
   if(g_execCount==0)
      return 100.0;
   int filled=0;
   double slipSum=0.0;
   for(int i=0;i<g_execCount;i++)
     {
      if(g_fills[i]==1)
        {
         filled++;
         slipSum+=g_slips[i];
        }
     }
   double fillRatio=(double)filled/(double)g_execCount;
   double avgSlip=(filled>0 ? slipSum/filled : 0.0);
   double slipPen=(InpMaxSlippagePts>0.0
                   ? MClamp(1.0-avgSlip/InpMaxSlippagePts,0.0,1.0)
                   : 1.0);
   return 100.0*fillRatio*slipPen;
  }

bool ExecutionHealthy(void)
  {
   if(g_execCount<ArraySize(g_fills))
      return true;
   return ExecutionQuality()>=InpExecSuspendBelow;
  }

//--- ticket bookkeeping for partial close / break-even (§14)
bool TicketSeen(const ulong &arr[],const ulong tk)
  {
   for(int i=ArraySize(arr)-1;i>=0;i--)
      if(arr[i]==tk)
         return true;
   return false;
  }

void TicketMark(ulong &arr[],const ulong tk)
  {
   int n=ArraySize(arr);
   ArrayResize(arr,n+1);
   arr[n]=tk;
  }

//--- Basket metrics (§11)
void GetBasket(SBasket &b)
  {
   b.count=0; b.totalVolume=0.0; b.avgEntry=0.0; b.floatPL=0.0;
   b.dir=0; b.firstEntryTime=0; b.lastEntryTime=0;
   b.lastEntryPrice=0.0; b.firstEntryVolume=0.0;
   double pv=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double op =PositionGetDouble(POSITION_PRICE_OPEN);
      datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
      b.count++;
      b.totalVolume+=vol;
      pv+=vol*op;
      b.floatPL+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      b.dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
      if(b.firstEntryTime==0 || ot<b.firstEntryTime)
        {
         b.firstEntryTime=ot;
         b.firstEntryVolume=vol;
        }
      if(ot>=b.lastEntryTime)
        {
         b.lastEntryTime=ot;
         b.lastEntryPrice=op;
        }
     }
   if(b.totalVolume>0.0)
      b.avgEntry=pv/b.totalVolume;
  }

void ResetBasketStateIfFlat(const SBasket &b)
  {
   if(b.count==0)
     {
      g_entryConfidence=0.0;
      g_initialRiskAmt=0.0;
      g_initialLot=0.0;
      g_trailMultEff=InpTrailAtrMult;
      ArrayResize(g_partialDone,0);
      ArrayResize(g_beDone,0);
     }
  }

void RecoverIfNeeded(const SBasket &b,const double conf,const double equity)
  {
   if(b.count>0 && g_initialRiskAmt<=0.0)
     {
      g_initialLot=(b.firstEntryVolume>0.0 ? b.firstEntryVolume
                                           : b.totalVolume/MathMax(b.count,1));
      g_initialRiskAmt=equity*InpRiskPct/100.0;
      g_entryConfidence=(conf>0.0 ? conf : InpBootstrapConf);
      g_trailMultEff=InpTrailAtrMult;
     }
  }

//--- open a market position with ATR-based SL/TP (§10, §14)
bool OpenMarket(const int dir,const double lots,const double atr,const double conf,
                const double riskAmt,const bool isInitial,const int basketCount)
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t))
      return false;
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double stopsLevel=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*pt;
   double price=(dir>0 ? t.ask : t.bid);

   double slDist=MathMax(InpSlAtrMult*atr,stopsLevel+pt);
   double tpDist=MathMax(InpTpAtrMult*atr,stopsLevel+pt);
   double sl=NormalizeDouble(dir>0 ? price-slDist : price+slDist,digits);
   double tp=NormalizeDouble(dir>0 ? price+tpDist : price-tpDist,digits);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action      =TRADE_ACTION_DEAL;
   req.symbol      =_Symbol;
   req.volume      =lots;
   req.type        =(dir>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   req.price       =price;
   req.sl          =sl;
   req.tp          =tp;
   req.deviation   =(ulong)InpDeviationPts;
   req.magic       =(ulong)InpMagic;
   req.comment     =StringFormat("MDL|%d|%.0f",basketCount,conf);
   req.type_filling=FillingMode();

   bool filled=SendRequest(req,res);
   double slip=0.0;
   if(filled && pt>0.0 && res.price>0.0)
      slip=MathAbs(res.price-price)/pt;
   RecordExecution(filled,slip);

   if(!filled)
     {
      LogEvent(StringFormat("ORDER REJECTED by broker: dir=%d lots=%.2f retcode=%u (%s)",
                            dir,lots,res.retcode,res.comment));
      Block(StringFormat("broker rejected order, retcode %u",res.retcode));
      return false;
     }

   if(isInitial)
     {
      g_entryConfidence=conf;
      g_initialRiskAmt=riskAmt;
      g_initialLot=lots;
      g_trailMultEff=InpTrailAtrMult;
     }
   g_lastEntryTime=TimeCurrent();
   g_entriesTaken++;
   g_barsSinceEntry=0;                       // §26 watchdog reset
   LogEvent(StringFormat("%s %.2f @ %.5f sl=%.5f tp=%.5f conv=%.1f (pct %.0f) qual=%.0f slip=%.1fpts",
                         dir>0?"BUY":"SELL",lots,res.price,sl,tp,conf,
                         g_snap.confPercentile,g_snap.tradeQuality,slip));
   return true;
  }

bool ClosePartial(const ulong ticket,const double volume)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   string sym=PositionGetString(POSITION_SYMBOL);
   long ptype=PositionGetInteger(POSITION_TYPE);
   MqlTick t;
   if(!SymbolInfoTick(sym,t))
      return false;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action      =TRADE_ACTION_DEAL;
   req.symbol      =sym;
   req.volume      =volume;
   req.position    =ticket;
   req.type        =(ptype==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   req.price       =(ptype==POSITION_TYPE_BUY ? t.bid : t.ask);
   req.deviation   =(ulong)InpDeviationPts;
   req.magic       =(ulong)InpMagic;
   req.type_filling=FillingMode();
   return SendRequest(req,res);
  }

bool ClosePositionByTicket(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   return ClosePartial(ticket,PositionGetDouble(POSITION_VOLUME));
  }

bool ModifySLTP(const ulong ticket,const double sl,const double tp)
  {
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action  =TRADE_ACTION_SLTP;
   req.symbol  =_Symbol;
   req.position=ticket;
   req.sl      =sl;
   req.tp      =tp;
   return SendRequest(req,res);
  }

void CloseBasket(const string reason)
  {
   bool any=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      ClosePositionByTicket(tk);
      any=true;
     }
   if(any)
      LogEvent("basket closed: "+reason);
  }

bool ScaleInAllowed(const SBasket &b)
  {
   if(b.count==0)
      return false;
   if(b.count-1>=InpMaxScaleIns)
      return false;
   int dir=MSign(g_snap.confidenceDir);
   if(dir!=b.dir)
      return false;                                    // thesis no longer valid
   if(g_entryConfidence>0.0 &&
      g_snap.confidenceFinal<InpScaleConfK*g_entryConfidence)
      return false;                                    // conviction has weakened
   double px=(b.dir>0 ? g_snap.ask : g_snap.bid);
   if(MathAbs(px-b.lastEntryPrice)<InpScaleSpacingAtr*g_snap.atr)
      return false;                                    // spacing not reached
   return true;
  }

double RiskUsedFiltered(const bool thisSymbolOnly)
  {
   double used=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      string ps=PositionGetString(POSITION_SYMBOL);
      if(thisSymbolOnly && ps!=_Symbol) continue;
      double sl =PositionGetDouble(POSITION_SL);
      double op =PositionGetDouble(POSITION_PRICE_OPEN);
      double vol=PositionGetDouble(POSITION_VOLUME);
      if(sl>0.0)
        {
         double tv=SymbolInfoDouble(ps,SYMBOL_TRADE_TICK_VALUE);
         double ts=SymbolInfoDouble(ps,SYMBOL_TRADE_TICK_SIZE);
         if(tv>0.0 && ts>0.0)
            used+=MathAbs(op-sl)/ts*tv*vol;
        }
      else
         used+=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPct/100.0;
     }
   return used;
  }

double BasketRiskUsed(void)  { return RiskUsedFiltered(true);  }
double AccountRiskUsed(void) { return RiskUsedFiltered(false); }

//--- Profit protection (§14): scale out part of the position at +R and
//    move the remainder to break-even, so a winner cannot become a loser.
void ProtectProfits(const SBasket &b)
  {
   if(!InpUsePartialTP && !InpUseBreakEven)
      return;
   if(g_initialRiskAmt<=0.0 || b.count==0)
      return;

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double stopsLevel=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*pt;
   double rMult=b.floatPL/g_initialRiskAmt;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;

      double vol=PositionGetDouble(POSITION_VOLUME);
      double op =PositionGetDouble(POSITION_PRICE_OPEN);
      double sl =PositionGetDouble(POSITION_SL);
      double tp =PositionGetDouble(POSITION_TP);
      int pdir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);

      // partial take-profit
      if(InpUsePartialTP && rMult>=InpPartialAtR && !TicketSeen(g_partialDone,tk))
        {
         double step=LotStep();
         double part=MathFloor(vol*InpPartialPct/100.0/step+1e-9)*step;
         if(part>=MinLot() && (vol-part)>=MinLot())
           {
            if(ClosePartial(tk,part))
              {
               TicketMark(g_partialDone,tk);
               LogEvent(StringFormat("partial take-profit: closed %.2f of %.2f at %.2fR",
                                     part,vol,rMult));
              }
           }
         else
            TicketMark(g_partialDone,tk);      // too small to split; don't retry
        }

      // break-even
      if(InpUseBreakEven && rMult>=InpBreakEvenAtR && !TicketSeen(g_beDone,tk))
        {
         double buf=InpBreakEvenBuf*g_snap.atr;
         double be=NormalizeDouble(op+pdir*buf,digits);
         bool improves=(pdir>0 ? (sl<=0.0 || be>sl+pt) : (sl<=0.0 || be<sl-pt));
         bool legal=(pdir>0 ? be<g_snap.bid-stopsLevel : be>g_snap.ask+stopsLevel);
         if(improves && legal && ModifySLTP(tk,be,tp))
           {
            TicketMark(g_beDone,tk);
            LogEvent(StringFormat("break-even: stop moved to %.5f at %.2fR",be,rMult));
           }
        }
     }
  }

void TrailPositions(const SBasket &b)
  {
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double stopsLevel=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*pt;
   double newSL=0.0;

   if(b.dir>0)
     {
      int idx=iHighest(_Symbol,PERIOD_CURRENT,MODE_HIGH,InpTrailLookback,0);
      if(idx<0) return;
      double hh=iHigh(_Symbol,PERIOD_CURRENT,idx);
      newSL=NormalizeDouble(hh-g_trailMultEff*g_snap.atr,digits);
      if(newSL>=g_snap.bid-stopsLevel)
         return;
     }
   else
     {
      int idx=iLowest(_Symbol,PERIOD_CURRENT,MODE_LOW,InpTrailLookback,0);
      if(idx<0) return;
      double ll=iLow(_Symbol,PERIOD_CURRENT,idx);
      newSL=NormalizeDouble(ll+g_trailMultEff*g_snap.atr,digits);
      if(newSL<=g_snap.ask+stopsLevel)
         return;
     }

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double curSL=PositionGetDouble(POSITION_SL);
      double curTP=PositionGetDouble(POSITION_TP);
      bool improve=(b.dir>0 ? (curSL<=0.0 || newSL>curSL+pt)
                            : (curSL<=0.0 || newSL<curSL-pt));
      if(improve)
         ModifySLTP(tk,newSL,curTP);
     }
  }

//--- Exit Engine (§14)
void ManageExits(const SBasket &b)
  {
   if(b.count==0)
      return;

   ProtectProfits(b);                          // partial TP + break-even first

   if(g_initialRiskAmt>0.0)
     {
      double rMult=b.floatPL/g_initialRiskAmt;
      if(rMult>=InpBasketTargetR)
        {
         CloseBasket(StringFormat("basket target %.1fR reached",rMult));
         return;
        }
     }

   if((b.dir>0 && g_snap.bearChoch) || (b.dir<0 && g_snap.bullChoch))
     {
      CloseBasket("structure invalidation (CHoCH)");
      return;
     }

   int barsIn=(int)((TimeCurrent()-b.firstEntryTime)/MathMax(PeriodSeconds(PERIOD_CURRENT),1));
   if(barsIn>InpMaxBarsInTrade && b.floatPL<InpMinAcceptPL)
     {
      CloseBasket(StringFormat("time stop after %d bars",barsIn));
      return;
     }

   if(g_peakMomAbs>70.0 &&
      MSign(g_snap.momentumAccel)!=0 && MSign(g_snap.momentumScore)!=0 &&
      MSign(g_snap.momentumAccel)!=MSign(g_snap.momentumScore))
      g_trailMultEff=MathMin(g_trailMultEff,InpTrailAtrMult*0.6);

   TrailPositions(b);
  }

//=============== ANALYTICS & ADAPTIVE (§18-§19, §25) ================

void AnalyticsRefresh(void)
  {
   ArrayResize(g_profits,0);
   g_grossWin=0.0; g_grossLoss=0.0;
   g_wins=0; g_losses=0;
   if(!HistorySelect(0,TimeCurrent()+60))
      return;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagic) continue;
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=_Symbol) continue;
      long entry=HistoryDealGetInteger(tk,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
      double p=HistoryDealGetDouble(tk,DEAL_PROFIT)
              +HistoryDealGetDouble(tk,DEAL_SWAP)
              +HistoryDealGetDouble(tk,DEAL_COMMISSION);
      int n=ArraySize(g_profits);
      ArrayResize(g_profits,n+1);
      g_profits[n]=p;
      if(p>=0.0) { g_wins++;   g_grossWin+=p; }
      else       { g_losses++; g_grossLoss+=-p; }
     }
   int n=ArraySize(g_profits);
   double s=0.0;
   for(int i=0;i<n;i++)
      s+=g_profits[i];
   g_expAll=(n>0 ? s/n : 0.0);
   int rN=MathMin(InpAdaptRecentN,n);
   double sr=0.0;
   for(int i=n-rN;i<n;i++)
      sr+=g_profits[i];
   g_expRecent=(rN>0 ? sr/rN : 0.0);

   UpdateEquityCurveMultiplier();
  }

//--- Equity Curve Engine (§25): trade the EA's own equity curve. When the
//    cumulative curve of closed trades sits below its own moving average,
//    the system is out of sync with the market — participate smaller until
//    it recovers. Never stops trading outright, which would prevent the
//    recovery from ever being observed.
void UpdateEquityCurveMultiplier(void)
  {
   g_equityCurveMult=1.0;
   if(!InpUseEquityCurve)
      return;
   int n=ArraySize(g_profits);
   if(n<InpEquityCurveN+1)
      return;
   double curve[];
   ArrayResize(curve,n);
   double run=0.0;
   for(int i=0;i<n;i++)
     {
      run+=g_profits[i];
      curve[i]=run;
     }
   double sma=0.0;
   for(int i=n-InpEquityCurveN;i<n;i++)
      sma+=curve[i];
   sma/=InpEquityCurveN;
   if(curve[n-1]<sma)
      g_equityCurveMult=MClamp(InpEquityCurveCut,0.1,1.0);
  }

int    TradesCount(void)  { return ArraySize(g_profits); }
double WinRate(void)      { int n=TradesCount(); return (n>0 ? (double)g_wins/n : 0.0); }
double ProfitFactor(void) { return (g_grossLoss>0.0 ? g_grossWin/g_grossLoss : (g_grossWin>0.0 ? 999.0 : 0.0)); }
double AvgWin(void)       { return (g_wins>0   ? g_grossWin/g_wins    : 0.0); }
double AvgLoss(void)      { return (g_losses>0 ? g_grossLoss/g_losses : 0.0); }

double KellyFraction(const double frac,const double capFrac)
  {
   if(g_wins==0 || g_losses==0)
      return capFrac;
   double W=WinRate();
   double loss=AvgLoss();
   if(loss<=0.0)
      return capFrac;
   double b=AvgWin()/loss;
   if(b<=0.0)
      return 0.0;
   double f=(W*b-(1.0-W))/b;
   return MClamp(frac*f,0.0,capFrac);
  }

void AdaptSelectivity(const double riskUnit)
  {
   if(TradesCount()<2*InpAdaptRecentN)
      return;
   double g=g_expAll-g_expRecent;                  // >0 means recent is worse
   double unit=(riskUnit>0.0 ? riskUnit : 1.0);
   double target=MClamp(g_entryPct+InpAdaptEta*MTanh(g/unit),InpPctMin,InpPctMax);
   g_entryPct=MClamp(InpAdaptAlpha*target+(1.0-InpAdaptAlpha)*g_entryPct,
                     InpPctMin,InpPctMax);
  }

string AnalyticsSummary(void)
  {
   return StringFormat("trades=%d winRate=%.1f%% PF=%.2f expAll=%.2f expRecent=%.2f entryPct=%.1f curveMult=%.2f",
                       TradesCount(),WinRate()*100.0,ProfitFactor(),g_expAll,g_expRecent,
                       g_entryPct,g_equityCurveMult);
  }

//========================= ENTRY PIPELINE ===========================

void TryEnter(const int dir,const bool isInitial,const SBasket &b)
  {
   if(InpEntryCooldownSec>0 && g_lastEntryTime>0 &&
      (TimeCurrent()-g_lastEntryTime)<InpEntryCooldownSec)
     {
      Block("entry cooldown active");
      return;
     }
   if(!ExecutionHealthy())
     {
      Block(StringFormat("execution quality %.0f below %.0f — entries suspended",
                         ExecutionQuality(),InpExecSuspendBelow));
      return;
     }
   double sessMult=SessionMultiplier();
   if(sessMult<=0.0)
     {
      Block("session multiplier is zero (no-trade window)");
      return;
     }
   double sprLimit=MaxSpreadPointsEffective();
   if(g_snap.spreadPts>sprLimit)
     {
      Block(StringFormat("spread %.0f pts exceeds limit %.0f (%.0f%% of ATR)",
                         g_snap.spreadPts,sprLimit,
                         (g_snap.atr>0.0 ? 100.0*g_snap.spreadPts*SymbolInfoDouble(_Symbol,SYMBOL_POINT)/g_snap.atr : 0.0)));
      return;
     }
   if(CorrelationVeto(dir))
     {
      Block("correlated exposure limit reached on other symbols");
      return;
     }

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double slDist=InpSlAtrMult*g_snap.atr;
   double lots,riskAmt;

   if(isInitial)
     {
      riskAmt=eq*InpRiskPct/100.0*sessMult*RegimeRiskMult(g_snap.regime);
      riskAmt*=g_equityCurveMult;                              // §25
      // §23 size down when volatility is forecast to expand into our stop
      if(InpUseVolForecast)
         riskAmt*=MClamp(1.0/MathMax(g_snap.volForecastRatio,0.5),0.6,1.15);
      double baseLot=LotForRisk(riskAmt,slDist);
      double confAdj=MathPow(MClamp(g_snap.confidenceFinal/100.0,0.01,1.0),InpConfGamma);
      double volAdj=MClamp(1.0/MathMax(g_snap.vr,0.1),0.5,2.0);
      double qualAdj=(InpUseQuality && InpQualitySizing
                      ? MClamp(0.5+0.5*g_snap.tradeQuality/100.0,0.5,1.0)
                      : 1.0);                                  // §24
      lots=baseLot*confAdj*volAdj*qualAdj;
      if(InpUseKellyCap && TradesCount()>=30)
        {
         double f=KellyFraction(InpKellyFraction,InpRiskPct/100.0*2.0);
         double maxLot=LotForRisk(f*eq,slDist);
         if(maxLot>0.0)
            lots=MathMin(lots,maxLot);
        }
     }
   else
     {
      lots=g_initialLot*MathPow(InpScaleDecay,b.count);
      riskAmt=RiskOfLots(lots,slDist);
     }

   double rawLots=lots;
   lots=NormalizeLots(lots);
   if(lots<=0.0)
     {
      Block(StringFormat("computed size %.4f below broker minimum %.2f",rawLots,MinLot()));
      return;
     }

   double newRisk=RiskOfLots(lots,slDist);

   // The risk actually carried by the position we are about to open. When the
   // broker minimum forces a bigger size than planned these differ by orders
   // of magnitude, and EVERY R-based exit (basket target, break-even, partial
   // take-profit, time stop) is measured in R -- so the stored figure must be
   // the real one. Storing the plan instead made a 2R target fire on a few
   // cents of profit and closed trades within seconds of opening them.
   riskAmt=newRisk;

   // Absolute ceiling. The min-lot override exists so a small account can
   // still trade slightly above its planned cap -- not so it can stake the
   // whole account on one position. Without this, a $10 account took 172%
   // of equity per trade and latched the circuit breaker on the first loss.
   double hardCap=eq*InpMaxRiskPctHard/100.0;
   if(newRisk>hardCap)
     {
      Block(StringFormat("risk %.2f = %.0f%% of equity exceeds hard ceiling %.0f%% "
                         "(min lot %.2f is too large for this account on %s; "
                         "need about %.0f deposit at this ATR)",
                         newRisk,100.0*newRisk/MathMax(eq,0.01),InpMaxRiskPctHard,
                         MinLot(),_Symbol,newRisk/(InpMaxRiskPctHard/100.0)));
      return;
     }

   double basketCap=eq*InpMaxBasketRiskPct/100.0;
   double acctCap  =eq*InpMaxAccountRiskPct/100.0;
   double basketUsed=BasketRiskUsed();
   double acctUsed  =AccountRiskUsed();

   bool atMinLot=(MathAbs(lots-MinLot())<1e-9);
   if(basketUsed+newRisk>basketCap)
     {
      if(!(atMinLot && b.count==0 && InpMinLotOverride))
        {
         Block(StringFormat("basket risk cap: %.2f used + %.2f new > %.2f cap",
                            basketUsed,newRisk,basketCap));
         return;
        }
      LogEvent(StringFormat("min-lot override: taking %.2f risk (%.1f%% of equity) vs %.1f%% plan, "
                            "ceiling %.0f%% — R multiples are measured against this real figure",
                            newRisk,100.0*newRisk/MathMax(eq,0.01),InpMaxBasketRiskPct,
                            InpMaxRiskPctHard));
     }
   if(acctUsed+newRisk>acctCap)
     {
      if(!(atMinLot && InpMinLotOverride && acctUsed<=0.0))
        {
         Block(StringFormat("account risk cap: %.2f used + %.2f new > %.2f cap",
                            acctUsed,newRisk,acctCap));
         return;
        }
     }
   if(!MarginOK(dir,lots))
     {
      Block(StringFormat("insufficient free margin for %.2f lots",lots));
      return;
     }

   string reason=StringFormat("regime=%s conv=%.0f pct=%.0f qual=%.0f trend=%.0f mom=%.0f flow=%.0f mtf=%.2f",
                              RegimeName(g_snap.regime),g_snap.confidenceFinal,
                              g_snap.confPercentile,g_snap.tradeQuality,g_snap.trendScore,
                              g_snap.momentumScore,g_snap.orderFlowScore,g_snap.mtfAlignment);
   if(OpenMarket(dir,lots,g_snap.atr,g_snap.confidenceFinal,riskAmt,isInitial,b.count))
     {
      string action=(dir>0 ? (isInitial ? "BUY" : "BUY_SCALE")
                           : (isInitial ? "SELL" : "SELL_SCALE"));
      LogDecision(action,lots,reason);
      g_blockReason="—";
     }
  }

//====================== SELF-TEST & CHART PANEL =====================

//--- readiness report printed on attach, so a configuration that could
//    never trade is visible immediately instead of after days of silence
void SelfTest(void)
  {
   if(!InpSelfTest)
      return;
   int bars=Bars(_Symbol,_Period);
   LogEvent("──────── STARTUP SELF-TEST ────────");
   LogEvent(StringFormat("symbol %s  timeframe %s  bars available %d",
                         _Symbol,EnumToString(_Period),bars));
   LogEvent(StringFormat("bars needed: structure %d, vol percentile %d  -> %s",
                         InpStructLookback,InpVolPctBars,
                         (bars>=MathMax(InpStructLookback,InpVolPctBars)+50 ? "OK"
                          : "SHORT (load more history: scroll the chart back)")));
   double sprLimit=MaxSpreadPointsEffective();
   LogEvent(StringFormat("broker: min lot %.2f  step %.2f  contract %.0f  digits %d  stops level %d pts",
                         MinLot(),LotStep(),
                         SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),
                         (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS),
                         (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)));
   LogEvent(StringFormat("spread now %.0f pts  |  effective limit %.0f pts (%.0f%% of ATR, ATR=%.0f pts)",
                         g_snap.spreadPts,sprLimit,InpMaxSpreadAtr*100.0,
                         (SymbolInfoDouble(_Symbol,SYMBOL_POINT)>0.0
                          ? g_snap.atr/SymbolInfoDouble(_Symbol,SYMBOL_POINT) : 0.0)));

   double eqNow=AccountInfoDouble(ACCOUNT_EQUITY);
   double freeNow=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   LogEvent(StringFormat("account: equity %.2f  free margin %.2f  leverage 1:%d  algo trading %s",
                         eqNow,freeNow,(int)AccountInfoInteger(ACCOUNT_LEVERAGE),
                         (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "ENABLED" : "DISABLED — enable it")));

   // AFFORDABILITY: can this account hold even the smallest allowed position?
   // No amount of signal quality can overcome a margin shortfall, so say it
   // plainly here rather than letting every order fail silently later.
   MqlTick tk0;
   if(SymbolInfoTick(_Symbol,tk0) && tk0.ask>0.0)
     {
      double marginMin=0.0;
      if(OrderCalcMargin(ORDER_TYPE_BUY,_Symbol,MinLot(),tk0.ask,marginMin))
        {
         double needed=marginMin*InpMarginSafety;
         LogEvent(StringFormat("affordability: min lot %.2f needs %.2f margin (%.2f with safety %.1fx) vs %.2f free",
                               MinLot(),marginMin,needed,InpMarginSafety,freeNow));
         if(needed>freeNow)
            LogEvent(StringFormat("*** BLOCKING: this account CANNOT AFFORD one minimum lot of %s. ***  "
                                  "Every order will be refused for insufficient margin regardless of signal. "
                                  "Deposit at least %.2f, lower InpMarginSafety, or trade a smaller-contract symbol.",
                                  _Symbol,needed));
        }

      // Minimum viable deposit: margin is only the entry ticket -- the binding
      // constraint is that one stop-out must stay inside the risk ceiling.
      double slDist0=InpSlAtrMult*g_snap.atr;
      double minLotRisk=RiskOfLots(MinLot(),slDist0);
      if(minLotRisk>0.0)
        {
         double needPlan=minLotRisk/(InpMaxBasketRiskPct/100.0);
         double needHard=minLotRisk/(InpMaxRiskPctHard/100.0);
         LogEvent(StringFormat("risk floor: one min-lot stop-out costs %.2f (= %.0f%% of current equity)",
                               minLotRisk,100.0*minLotRisk/MathMax(eqNow,0.01)));
         LogEvent(StringFormat("minimum viable deposit at this volatility: %.0f to stay under the %.0f%% hard "
                               "ceiling, %.0f to honour the %.1f%% risk plan",
                               needHard,InpMaxRiskPctHard,needPlan,InpMaxBasketRiskPct));
         if(minLotRisk>eqNow*InpMaxRiskPctHard/100.0)
            LogEvent(StringFormat("*** BLOCKING: one minimum-lot stop-out (%.2f) exceeds the %.0f%% ceiling "
                                  "on %.2f equity. No risk setting can make this survivable — the broker "
                                  "minimum is simply too large for the account on this symbol. ***",
                                  minLotRisk,InpMaxRiskPctHard,eqNow));
        }
     }

   if(g_confCount>0)
     {
      double p50=DistributionPercentile(50);
      double p85=DistributionPercentile(85);
      double p95=DistributionPercentile(95);
      LogEvent(StringFormat("conviction distribution seeded from %d bars: p50=%.1f p85=%.1f p95=%.1f",
                            g_confCount,p50,p85,p95));
      if(p95<InpMinAbsConfidence)
         LogEvent(StringFormat("WARNING: even the best recent conviction (%.1f) is below the floor %.1f — "
                               "this symbol/timeframe offers little directional agreement; "
                               "lower InpMinAbsConfidence or pick a more directional market",
                               p95,InpMinAbsConfidence));
      else
         LogEvent(StringFormat("entry needs rank %.0f pct (~conviction %.1f) AND floor %.1f -> reachable",
                               g_entryPct,DistributionPercentile(g_entryPct),InpMinAbsConfidence));
     }
   else
      LogEvent("conviction distribution NOT seeded (insufficient history) — "
               "bootstrap threshold applies until samples accumulate");

   double sess=SessionMultiplier();
   LogEvent(StringFormat("session multiplier now %.2f  |  watchdog %s  |  quality gate %.0f",
                         sess,(InpUseWatchdog?"on":"off"),
                         (InpUseQuality?InpMinTradeQuality:0.0)));
   LogEvent("───────────────────────────────────");
  }

void DrawPanel(const SBasket &b)
  {
   if(!InpShowPanel)
      return;
   string mode=(PercentileModeActive()
                ? StringFormat("rank>=%.0f%s",g_effectivePct,
                               (g_effectivePct<g_entryPct-0.01?" (relaxed)":""))
                : StringFormat("bootstrap %.0f (%d/%d)",InpBootstrapConf,g_confCount,InpMinSamples));
   string p50="-",p85="-";
   if(g_confCount>0)
     {
      p50=StringFormat("%.0f",DistributionPercentile(50));
      p85=StringFormat("%.0f",DistributionPercentile(85));
     }
   string txt=StringFormat(
      "MEDULA v2.70  |  %s %s\n"
      "──────────────────────────────\n"
      "regime        %s\n"
      "structure     %+7.1f     trend    %+7.1f\n"
      "momentum      %+7.1f     flow     %+7.1f\n"
      "liquidity     %+7.1f     MTF      %+7.2f\n"
      "vol pct %.0f  suit %.0f  forecast x%.2f\n"
      "spread %.0f/%.0f pts  exec %.0f  session x%.2f\n"
      "──────────────────────────────\n"
      "CONVICTION    %6.1f  %s\n"
      "rank          %6.0f pct   gate: %s\n"
      "distribution  p50=%s  p85=%s\n"
      "quality       %6.0f\n"
      "──────────────────────────────\n"
      "positions %d  floating %.2f  R %.2f\n"
      "entries %d   idle %d bars   curve x%.2f\n"
      "status  %s",
      _Symbol,EnumToString(_Period),
      RegimeName(g_snap.regime),
      g_snap.structureScore,g_snap.trendScore,
      g_snap.momentumScore,g_snap.orderFlowScore,
      g_snap.liquidityScore,g_snap.mtfAlignment,
      g_snap.volPercentile,g_snap.volSuitability,g_snap.volForecastRatio,
      g_snap.spreadPts,MaxSpreadPointsEffective(),ExecutionQuality(),SessionMultiplier(),
      g_snap.confidenceFinal,(MSign(g_snap.confidenceDir)>0?"LONG":
                              (MSign(g_snap.confidenceDir)<0?"SHORT":"flat")),
      g_snap.confPercentile,mode,p50,p85,
      g_snap.tradeQuality,
      b.count,b.floatPL,
      (g_initialRiskAmt>0.0 ? b.floatPL/g_initialRiskAmt : 0.0),
      g_entriesTaken,g_barsSinceEntry,g_equityCurveMult,
      g_blockReason);
   Comment(txt);
  }

//========================= EVENT HANDLERS ===========================

int OnInit(void)
  {
   double ws=InpW1+InpW2+InpW3+InpW4+InpW5+InpW6;
   if(ws<=0.0) ws=1.0;
   g_w1=InpW1/ws; g_w2=InpW2/ws; g_w3=InpW3/ws;
   g_w4=InpW4/ws; g_w5=InpW5/ws; g_w6=InpW6/ws;

   LogInit();

   if(!IndInit())
     {
      Print("[Medula] indicator initialization failed");
      return INIT_FAILED;
     }

   int w=MathMax(InpExecWindow,1);
   ArrayResize(g_fills,w);
   ArrayResize(g_slips,w);
   ArrayInitialize(g_fills,0);
   ArrayInitialize(g_slips,0.0);
   g_execHead=0;
   g_execCount=0;

   int cs=MathMax(InpConfSampleSize,10);
   ArrayResize(g_confSamples,cs);
   ArrayInitialize(g_confSamples,0.0);
   g_confHead=0;
   g_confCount=0;
   g_entryPct=MClamp(InpEntryPercentile,InpPctMin,InpPctMax);
   g_effectivePct=g_entryPct;
   g_barsSinceEntry=0;

   ArrayResize(g_partialDone,0);
   ArrayResize(g_beDone,0);

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEquity=eq;
   g_peakEquity=eq;
   g_dayKey=-1;
   g_breakerLatched=false;
   RiskUpdate();

   g_trailMultEff=InpTrailAtrMult;
   g_haveSnap=false;
   g_lastBar=0;
   g_peakMomAbs=0.0;
   g_lastEntryTime=0;
   g_entriesTaken=0;
   g_blockReason="warming up";
   g_seeded=false;

   AnalyticsRefresh();

   // prime the snapshot, then seed the distribution from history so
   // percentile mode is live immediately rather than after InpMinSamples bars
   if(AnalysisUpdate())
     {
      g_haveSnap=true;
      int n=SeedDistributionFromHistory();
      g_seeded=(n>0);
      if(n>0)
         LogEvent(StringFormat("conviction distribution seeded with %d historical bars",n));
     }

   SelfTest();

   LogEvent(StringFormat("v2.70 ready on %s %s — entry at rank %.0f pct, floor %.1f, quality %.0f",
                         _Symbol,EnumToString(_Period),g_entryPct,
                         InpMinAbsConfidence,(InpUseQuality?InpMinTradeQuality:0.0)));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   IndRelease();
   Comment("");
   LogEvent(StringFormat("deinitialized (reason %d) — entries taken this run: %d",
                         reason,g_entriesTaken));
   LogClose();
  }

void OnTick(void)
  {
   RiskUpdate();

   SBasket b;
   GetBasket(b);
   ResetBasketStateIfFlat(b);

   if(CircuitBreaker())
     {
      if(b.count>0)
         CloseBasket("risk circuit breaker");
      if(!g_breakerLogged)
        {
         LogEvent("CIRCUIT BREAKER ACTIVE — trading suspended until reset");
         g_breakerLogged=true;
        }
      g_blockReason="circuit breaker latched";
      DrawPanel(b);
      return;
     }
   g_breakerLogged=false;

   datetime curBar=iTime(_Symbol,_Period,0);
   bool newBar=(curBar!=g_lastBar && curBar>0);
   if(newBar)
     {
      g_lastBar=curBar;
      g_barsSinceEntry++;                      // §26
     }

   if(InpAnalyzeEveryTick || newBar || !g_haveSnap)
     {
      if(!AnalysisUpdate())
        {
         DrawPanel(b);
         return;
        }
      g_haveSnap=true;
     }
   else
     {
      MqlTick t;
      if(!SymbolInfoTick(_Symbol,t))
         return;
      g_snap.bid=t.bid;
      g_snap.ask=t.ask;
      g_snap.close=t.bid;
      double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      g_snap.spreadPts=(pt>0.0 ? (t.ask-t.bid)/pt : 0.0);
     }

   // late seeding if history only became available after attach
   if(!g_seeded && InpSeedFromHistory && newBar)
     {
      int n=SeedDistributionFromHistory();
      if(n>0)
        {
         g_seeded=true;
         LogEvent(StringFormat("conviction distribution seeded (late) with %d bars",n));
        }
     }

   ComputeConfidence();

   int cDir=MSign(g_snap.confidenceDir);
   if(InpUseCorrelation && cDir!=0)
      g_snap.confidenceFinal*=CorrelationDampener(cDir);

   if(newBar)
      PushConfidenceSample(g_snap.confidenceFinal);
   g_snap.confPercentile=ConfidencePercentile(g_snap.confidenceFinal);
   g_effectivePct=EffectiveEntryPercentile();                   // §26
   g_snap.tradeQuality=(cDir!=0 ? ComputeTradeQuality(cDir) : 0.0);  // §24

   RecoverIfNeeded(b,g_snap.confidenceFinal,AccountInfoDouble(ACCOUNT_EQUITY));

   if(b.count>0)
     {
      ManageExits(b);
      GetBasket(b);
      ResetBasketStateIfFlat(b);
     }

   ENUM_DECISION d=Decide(b.count>0,b.dir);

   if(d==DECISION_EXIT)
     {
      CloseBasket("conviction collapse / direction flip");
      LogDecision("EXIT",0.0,"conviction collapse / direction flip");
      DrawPanel(b);
      return;
     }
   if(d==DECISION_BUY || d==DECISION_SELL)
      TryEnter(d==DECISION_BUY ? 1 : -1,true,b);
   else if(d==DECISION_HOLD && b.count>0)
     {
      if(ScaleInAllowed(b))
         TryEnter(b.dir,false,b);
      else
         g_blockReason="holding basket";
     }

   DrawPanel(b);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic)
      return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol)
      return;
   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY)
      return;

   AnalyticsRefresh();
   if(InpAdaptive)
     {
      double riskUnit=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPct/100.0;
      double before=g_entryPct;
      AdaptSelectivity(riskUnit);
      if(MathAbs(g_entryPct-before)>0.01)
         LogEvent(StringFormat("selectivity %.1f -> %.1f percentile",before,g_entryPct));
     }
   LogEvent(AnalyticsSummary());
  }
//+------------------------------------------------------------------+
