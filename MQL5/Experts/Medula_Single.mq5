//+------------------------------------------------------------------+
//|                                                Medula_Single.mq5 |
//|  Medula EA v2.00 — single-file, zero-dependency build.           |
//|                                                                  |
//|  v2 CHANGE OF ARITHMETIC (why v1 never traded):                  |
//|  v1 compared confidence to a FIXED threshold (60). Because the    |
//|  weights sum to 1 and each engine score is capped at +/-1, the    |
//|  attainable confidence on real data peaked near 55 AFTER the      |
//|  volatility/spread penalties — so the threshold was unreachable   |
//|  and the EA waited forever. v2 replaces the fixed bar with a      |
//|  SELF-CALIBRATING one: current confidence is ranked against its   |
//|  own rolling distribution, and the EA acts when conviction sits   |
//|  in the top percentile band of what this symbol actually produces.|
//|  A top decile always exists, on any symbol, timeframe or regime,  |
//|  so the arithmetic adapts itself instead of needing hand-tuning.  |
//|                                                                  |
//|  Engines (formula references point to MEDULA_FORMULAS.md):       |
//|    §1-§7   analysis        §8-§9   confidence + decision         |
//|    §10-§14 execution / basket / scaling / exits                  |
//|    §13,§15-§17 risk, allocation, session, correlation            |
//|    §18-§20 analytics, adaptive tuning, logging                   |
//|  Validation (§21) is performed offline in the Strategy Tester.   |
//+------------------------------------------------------------------+
#property copyright "Medula Project"
#property version   "2.00"

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

input group "Confidence (§8)"
input double InpW1 = 0.25;              // Weight: structure
input double InpW2 = 0.25;              // Weight: trend
input double InpW3 = 0.20;              // Weight: momentum
input double InpW4 = 0.15;              // Weight: liquidity
input double InpW5 = 0.15;              // Weight: MTF alignment
input double InpConfGain          = 2.5;  // Confidence tanh gain
input double InpMaxSpreadPoints   = 40.0; // Hard spread limit (points) - blocks entry
input double InpSpreadFreeFrac    = 0.60; // Spread below this fraction of limit is unpenalized

input group "Decision — self-calibrating threshold (§9)"
input bool   InpUsePercentile     = true;  // Rank confidence vs its own distribution
input double InpEntryPercentile   = 85.0;  // Enter in top (100-this)% of recent conviction
input int    InpConfSampleSize    = 500;   // Rolling distribution size (bars)
input int    InpMinSamples        = 60;    // Samples needed before percentile mode engages
input double InpMinAbsConfidence  = 18.0;  // Absolute conviction floor (never trade below)
input double InpBootstrapConf     = 35.0;  // Threshold used while distribution fills
input double InpExitConfFraction  = 0.55;  // Exit when conf falls below this x entry conf
input double InpMtfVetoConfluence = 60.0;  // Block counter-HTF entries above this confluence
input int    InpEntryCooldownSec  = 120;   // Min seconds between entries (anti-churn)

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
input bool   InpMinLotOverride    = true;  // Let a single min-lot trade exceed the risk cap

input group "Position Scaling (§12)"
input int    InpMaxScaleIns     = 3;     // Max add-on positions
input double InpScaleSpacingAtr = 1.0;   // Min spacing between adds (ATR mult)
input double InpScaleDecay      = 0.7;   // Lot decay factor per add
input double InpScaleConfK      = 0.9;   // Min confidence vs entry confidence

input group "Exits (§11, §14)"
input double InpBasketTargetR  = 2.0;    // Basket profit target (R multiples)
input double InpTrailAtrMult   = 3.0;    // Chandelier trail (ATR mult)
input int    InpTrailLookback  = 22;     // Chandelier lookback (bars)
input int    InpMaxBarsInTrade = 96;     // Time stop (bars)
input double InpMinAcceptPL    = 0.0;    // Min P/L to bypass time stop

input group "Capital Allocation (§15)"
input double InpConfGamma     = 0.8;     // Confidence sizing exponent
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
input double InpPctMin       = 70.0;     // Entry percentile lower bound
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
   double            structureScore;   // §2, -100..+100
   double            trendScore;       // §3, -100..+100
   int               trendDir;
   double            momentumScore;    // §4, -100..+100
   double            momentumAccel;    // §4
   double            liquidityScore;   // §6, -100..+100
   double            mtfAlignment;     // §7, -1..+1
   double            mtfConfluence;    // §7, 0..100
   double            mtfValidWeight;   // §7, share of higher TFs with usable data
   bool              bullBos,bearBos;
   bool              bullChoch,bearChoch;
   double            confidenceDir;    // §8, -100..+100 (sign = direction)
   double            confidenceFinal;  // §8, 0..100 after penalties
   double            confPercentile;   // §9, rank within rolling distribution
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
double   g_w1,g_w2,g_w3,g_w4,g_w5;
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
// execution-quality rings (§10)
int      g_fills[];
double   g_slips[];
int      g_execHead=0,g_execCount=0;
// rolling confidence distribution — the self-calibrating threshold (§9)
double   g_confSamples[];
int      g_confHead=0,g_confCount=0;
double   g_entryPct;                   // adaptive entry percentile
// analytics (§18)
double   g_profits[];
double   g_grossWin=0.0,g_grossLoss=0.0;
int      g_wins=0,g_losses=0;
double   g_expAll=0.0,g_expRecent=0.0;
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
long     g_ticks=0;
int      g_entriesTaken=0;

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
            FileWriteString(g_logHandle,"time;symbol;regime;structure;trend;momentum;volPct;liquidity;mtf;confidence;pctile;decision;lots;reason\n");
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
   string line=StringFormat("%s;%s;%s;%.1f;%.1f;%.1f;%.1f;%.1f;%.2f;%.1f;%.1f;%s;%.2f;%s",
                            TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                            _Symbol,RegimeName(g_snap.regime),
                            g_snap.structureScore,g_snap.trendScore,g_snap.momentumScore,
                            g_snap.volPercentile,g_snap.liquidityScore,g_snap.mtfAlignment,
                            g_snap.confidenceFinal,g_snap.confPercentile,decision,lots,reason);
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

//--- Trend score core (§3), shared by chart TF and each higher TF.
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

//--- Momentum Engine (§4)
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
   double rsiDev=rsi-50.0;
   double macdSlope=(m0-s0)-(m1-s1);

   g_snap.momentumScore=100.0*MTanh(0.40*(rsiDev/50.0)
                                   +0.30*MTanh(roc0/2.0)
                                   +0.30*MTanh(macdSlope/(0.1*g_snap.atr)));
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
//    v2: a higher timeframe whose history is not yet loaded no longer
//    counts as "disagreement" — its weight is redistributed across the
//    timeframes that do have data, and the veto stands down if too
//    little of the higher-timeframe picture is available.
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

   UpdateVolatility();   // §1, §5
   UpdateStructure();    // §2
   UpdateTrend();        // §3
   UpdateMomentum();     // §4
   UpdateLiquidity();    // §6
   UpdateMTF();          // §7
   ClassifyRegime();     // §1
   return true;
  }

//================= CONFIDENCE & DECISION (§8-§9) ====================

//--- Confidence Engine (§8): weighted evidence -> gain -> tanh -> penalties.
//    v2 reshapes the spread penalty: a normal dealing spread costs nothing,
//    and the cost only ramps as the spread approaches the hard limit. The
//    v1 linear form silently halved every score at a routine 15-point
//    spread, which is what made the fixed threshold unreachable.
void ComputeConfidence(const double execQuality)
  {
   double raw=g_w1*(g_snap.structureScore/100.0)
             +g_w2*(g_snap.trendScore/100.0)
             +g_w3*(g_snap.momentumScore/100.0)
             +g_w4*(g_snap.liquidityScore/100.0)
             +g_w5*g_snap.mtfAlignment;

   g_snap.confidenceDir=100.0*MTanh(InpConfGain*raw);
   double mag=MathAbs(g_snap.confidenceDir);

   double pVol=g_snap.volSuitability/100.0;

   double pSpread=1.0;
   if(InpMaxSpreadPoints>0.0)
     {
      double freePts=InpSpreadFreeFrac*InpMaxSpreadPoints;
      if(g_snap.spreadPts>freePts)
        {
         double span=MathMax(InpMaxSpreadPoints-freePts,1e-9);
         pSpread=MClamp(1.0-(g_snap.spreadPts-freePts)/span,0.0,1.0);
        }
     }

   double pExec=MClamp(execQuality/100.0,0.0,1.0);

   g_snap.confidenceFinal=mag*pVol*pSpread*pExec;
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
//    This is the self-calibrating threshold: whatever range of confidence
//    this symbol/timeframe actually produces, the top band always exists.
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

bool PercentileModeActive(void)
  {
   return (InpUsePercentile && g_confCount>=InpMinSamples);
  }

//--- Decision Engine (§9)
ENUM_DECISION Decide(const bool inTrade,const int basketDir)
  {
   int dir=MSign(g_snap.confidenceDir);

   if(!inTrade)
     {
      if(dir==0)
        {
         Block("no directional edge (confidence sign is zero)");
         return DECISION_WAIT;
        }
      if(g_snap.confidenceFinal<InpMinAbsConfidence)
        {
         Block(StringFormat("conviction %.1f below absolute floor %.1f",
                            g_snap.confidenceFinal,InpMinAbsConfidence));
         return DECISION_WAIT;
        }
      if(PercentileModeActive())
        {
         if(g_snap.confPercentile<g_entryPct)
           {
            Block(StringFormat("conviction %.1f ranks at %.0f pct, needs %.0f pct",
                               g_snap.confidenceFinal,g_snap.confPercentile,g_entryPct));
            return DECISION_WAIT;
           }
        }
      else if(g_snap.confidenceFinal<InpBootstrapConf)
        {
         Block(StringFormat("bootstrapping distribution (%d/%d samples), conviction %.1f < %.1f",
                            g_confCount,InpMinSamples,g_snap.confidenceFinal,InpBootstrapConf));
         return DECISION_WAIT;
        }
      // MTF veto (§7): only when enough higher-timeframe data is actually loaded
      if(g_snap.mtfValidWeight>=0.5 &&
         MSign(g_snap.mtfAlignment)!=dir && g_snap.mtfConfluence>InpMtfVetoConfluence)
        {
         Block(StringFormat("higher timeframes disagree (alignment %.2f, confluence %.0f)",
                            g_snap.mtfAlignment,g_snap.mtfConfluence));
         return DECISION_WAIT;
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
double SessionMultiplier(void)
  {
   if(!InpUseSessions)
      return 1.0;
   MqlDateTime g;
   TimeToStruct(TimeGMT(),g);
   int h=g.hour;
   if(h>=7  && h<12) return InpSessLondon;
   if(h>=12 && h<16) return InpSessOverlap;
   if(h>=16 && h<21) return InpSessNewYork;
   if(h>=21)         return InpSessDead;
   return InpSessAsian;                // 0..6
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

//--- broker-constraint normalization; min-lot override keeps small
//    accounts tradable (explicit opt-in because it raises risk above plan)
double NormalizeLots(double lots)
  {
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minL=MinLot();
   double maxL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0.0)
      step=0.01;
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

//--- Correlation Engine (§17): soft dampener on confidence.
//    Scans open positions on OTHER symbols carrying our magic number.
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

//--- pick a filling mode the broker actually supports
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

// §10 circuit breaker: suspend entries once the window is full and degraded
bool ExecutionHealthy(void)
  {
   if(g_execCount<ArraySize(g_fills))
      return true;
   return ExecutionQuality()>=InpExecSuspendBelow;
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
     }
  }

// after a terminal restart the in-memory basket state is gone; rebuild
// conservative estimates from what is recoverable
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
   LogEvent(StringFormat("%s %.2f @ %.5f sl=%.5f tp=%.5f conf=%.1f (pct %.0f) slip=%.1fpts",
                         dir>0?"BUY":"SELL",lots,res.price,sl,tp,conf,
                         g_snap.confPercentile,slip));
   return true;
  }

bool ClosePositionByTicket(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   string sym=PositionGetString(POSITION_SYMBOL);
   double vol=PositionGetDouble(POSITION_VOLUME);
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
   req.volume      =vol;
   req.position    =ticket;
   req.type        =(ptype==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   req.price       =(ptype==POSITION_TYPE_BUY ? t.bid : t.ask);
   req.deviation   =(ulong)InpDeviationPts;
   req.magic       =(ulong)InpMagic;
   req.type_filling=FillingMode();
   return SendRequest(req,res);
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

//--- close every position in the basket (§11)
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

//--- Scaling preconditions (§12); risk caps are checked by the caller
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

//--- currency risk committed by open positions (§13)
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

//--- Chandelier trailing stop per position (§14)
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

//--- Exit Engine (§14): target, invalidation, time stop, trailing
void ManageExits(const SBasket &b)
  {
   if(b.count==0)
      return;

   // 1) basket profit target in R multiples (§11)
   if(g_initialRiskAmt>0.0)
     {
      double rMult=b.floatPL/g_initialRiskAmt;
      if(rMult>=InpBasketTargetR)
        {
         CloseBasket(StringFormat("basket target %.1fR reached",rMult));
         return;
        }
     }

   // 2) structure invalidation: CHoCH against the basket (§2, §14)
   if((b.dir>0 && g_snap.bearChoch) || (b.dir<0 && g_snap.bullChoch))
     {
      CloseBasket("structure invalidation (CHoCH)");
      return;
     }

   // 3) time stop (§14)
   int barsIn=(int)((TimeCurrent()-b.firstEntryTime)/MathMax(PeriodSeconds(PERIOD_CURRENT),1));
   if(barsIn>InpMaxBarsInTrade && b.floatPL<InpMinAcceptPL)
     {
      CloseBasket(StringFormat("time stop after %d bars",barsIn));
      return;
     }

   // 4) momentum exhaustion tightens the trail rather than hard-exiting (§14)
   if(g_peakMomAbs>70.0 &&
      MSign(g_snap.momentumAccel)!=0 && MSign(g_snap.momentumScore)!=0 &&
      MSign(g_snap.momentumAccel)!=MSign(g_snap.momentumScore))
      g_trailMultEff=MathMin(g_trailMultEff,InpTrailAtrMult*0.6);

   // 5) chandelier trailing per position (§14)
   TrailPositions(b);
  }

//=============== ANALYTICS & ADAPTIVE (§18-§19) =====================

//--- rebuild statistics from the account's deal history (§18)
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
  }

int    TradesCount(void)  { return ArraySize(g_profits); }
double WinRate(void)      { int n=TradesCount(); return (n>0 ? (double)g_wins/n : 0.0); }
double ProfitFactor(void) { return (g_grossLoss>0.0 ? g_grossWin/g_grossLoss : (g_grossWin>0.0 ? 999.0 : 0.0)); }
double AvgWin(void)       { return (g_wins>0   ? g_grossWin/g_wins    : 0.0); }
double AvgLoss(void)      { return (g_losses>0 ? g_grossLoss/g_losses : 0.0); }

//--- fractional Kelly sizing cap (§15): f = (W*b - (1-W)) / b
double KellyFraction(const double frac,const double capFrac)
  {
   if(g_wins==0 || g_losses==0)
      return capFrac;                 // not enough evidence; fall back to cap
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

//--- Adaptive Parameter Engine (§19): bounded, EMA-smoothed selectivity.
//    Recent underperformance raises the entry percentile (be pickier);
//    outperformance lowers it (participate more).
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
   return StringFormat("trades=%d winRate=%.1f%% PF=%.2f expAll=%.2f expRecent=%.2f entryPct=%.1f",
                       TradesCount(),WinRate()*100.0,ProfitFactor(),g_expAll,g_expRecent,g_entryPct);
  }

//========================= ENTRY PIPELINE ===========================

//--- §10, §12, §13, §15: sizing, gating, execution.
//    Every rejection path reports its reason — v1's silent returns are
//    what made a non-trading EA impossible to diagnose from the outside.
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
   if(g_snap.spreadPts>InpMaxSpreadPoints)
     {
      Block(StringFormat("spread %.0f pts exceeds limit %.0f",
                         g_snap.spreadPts,InpMaxSpreadPoints));
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
      // §13 base risk, scaled by session (§16) and regime (§1)
      riskAmt=eq*InpRiskPct/100.0*sessMult*RegimeRiskMult(g_snap.regime);
      double baseLot=LotForRisk(riskAmt,slDist);
      // §15 confidence + inverse-volatility allocation
      double confAdj=MathPow(MClamp(g_snap.confidenceFinal/100.0,0.01,1.0),InpConfGamma);
      double volAdj=MClamp(1.0/MathMax(g_snap.vr,0.1),0.5,2.0);
      lots=baseLot*confAdj*volAdj;
      // §15 quarter-Kelly cap once there is enough trade history
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
      // §12 decaying scale-in size: initial lot * decay^(adds so far + 1)
      lots=g_initialLot*MathPow(InpScaleDecay,b.count);
      riskAmt=RiskOfLots(lots,slDist);
     }

   double rawLots=lots;
   lots=NormalizeLots(lots);
   if(lots<=0.0)
     {
      Block(StringFormat("computed size %.4f below broker minimum %.2f (enable min-lot rounding)",
                         rawLots,MinLot()));
      return;
     }

   // §13 exposure caps: basket risk and total account risk
   double newRisk=RiskOfLots(lots,slDist);
   double basketCap=eq*InpMaxBasketRiskPct/100.0;
   double acctCap  =eq*InpMaxAccountRiskPct/100.0;
   double basketUsed=BasketRiskUsed();
   double acctUsed  =AccountRiskUsed();

   bool atMinLot=(MathAbs(lots-MinLot())<1e-9);
   if(basketUsed+newRisk>basketCap)
     {
      // a single minimum-size position may exceed the plan on a small
      // account; allowed only explicitly, and the true cost is logged
      if(!(atMinLot && b.count==0 && InpMinLotOverride))
        {
         Block(StringFormat("basket risk cap: %.2f used + %.2f new > %.2f cap",
                            basketUsed,newRisk,basketCap));
         return;
        }
      LogEvent(StringFormat("min-lot override: taking %.2f risk (%.2f%% of equity) vs %.2f%% plan",
                            newRisk,100.0*newRisk/MathMax(eq,1.0),InpMaxBasketRiskPct));
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

   string reason=StringFormat("regime=%s conf=%.0f pct=%.0f trend=%.0f mom=%.0f struct=%.0f mtf=%.2f",
                              RegimeName(g_snap.regime),g_snap.confidenceFinal,
                              g_snap.confPercentile,g_snap.trendScore,
                              g_snap.momentumScore,g_snap.structureScore,g_snap.mtfAlignment);
   if(OpenMarket(dir,lots,g_snap.atr,g_snap.confidenceFinal,riskAmt,isInitial,b.count))
     {
      string action=(dir>0 ? (isInitial ? "BUY" : "BUY_SCALE")
                           : (isInitial ? "SELL" : "SELL_SCALE"));
      LogDecision(action,lots,reason);
      g_blockReason="—";
     }
  }

//============================ CHART PANEL ===========================

void DrawPanel(const SBasket &b)
  {
   if(!InpShowPanel)
      return;
   string mode=(PercentileModeActive()
                ? StringFormat("percentile (need %.0f)",g_entryPct)
                : StringFormat("bootstrap (need %.0f, %d/%d samples)",
                               InpBootstrapConf,g_confCount,InpMinSamples));
   string txt=StringFormat(
      "MEDULA v2.00  |  %s %s\n"
      "──────────────────────────────\n"
      "regime        %s\n"
      "structure     %+7.1f\n"
      "trend         %+7.1f\n"
      "momentum      %+7.1f\n"
      "liquidity     %+7.1f\n"
      "MTF align     %+7.2f  (confluence %.0f)\n"
      "volatility    pct %.0f   suitability %.0f\n"
      "spread        %.0f pts   exec quality %.0f\n"
      "──────────────────────────────\n"
      "CONVICTION    %6.1f  %s\n"
      "rank          %6.0f pct\n"
      "mode          %s\n"
      "──────────────────────────────\n"
      "positions     %d   floating %.2f\n"
      "entries taken %d\n"
      "status        %s",
      _Symbol,EnumToString(_Period),
      RegimeName(g_snap.regime),
      g_snap.structureScore,g_snap.trendScore,g_snap.momentumScore,
      g_snap.liquidityScore,g_snap.mtfAlignment,g_snap.mtfConfluence,
      g_snap.volPercentile,g_snap.volSuitability,
      g_snap.spreadPts,ExecutionQuality(),
      g_snap.confidenceFinal,(MSign(g_snap.confidenceDir)>0?"LONG":
                              (MSign(g_snap.confidenceDir)<0?"SHORT":"flat")),
      g_snap.confPercentile,mode,
      b.count,b.floatPL,g_entriesTaken,
      g_blockReason);
   Comment(txt);
  }

//========================= EVENT HANDLERS ===========================

int OnInit(void)
  {
   // normalize confidence weights so they always sum to 1 (§8)
   double ws=InpW1+InpW2+InpW3+InpW4+InpW5;
   if(ws<=0.0) ws=1.0;
   g_w1=InpW1/ws; g_w2=InpW2/ws; g_w3=InpW3/ws;
   g_w4=InpW4/ws; g_w5=InpW5/ws;

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
   g_ticks=0;
   g_blockReason="warming up";

   AnalyticsRefresh();

   LogEvent(StringFormat("v2.00 initialized on %s %s — self-calibrating entry at %.0f percentile, floor %.1f",
                         _Symbol,EnumToString(_Period),g_entryPct,InpMinAbsConfidence));
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

//--- core event loop (§ "Engine Data Flow Summary")
void OnTick(void)
  {
   g_ticks++;
   RiskUpdate();

   SBasket b;
   GetBasket(b);
   ResetBasketStateIfFlat(b);

   // §13 account circuit breaker: flatten and stand down
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

   // analysis refresh: every tick, or on new bar with light tick updates
   datetime curBar=iTime(_Symbol,_Period,0);
   bool newBar=(curBar!=g_lastBar && curBar>0);
   if(newBar)
      g_lastBar=curBar;

   if(InpAnalyzeEveryTick || newBar || !g_haveSnap)
     {
      if(!AnalysisUpdate())
        {
         DrawPanel(b);
         return;                       // history not ready yet (reason logged)
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

   // §8 confidence, with execution-quality penalty
   ComputeConfidence(ExecutionQuality());

   // §17 correlation soft dampener on the would-be trade direction
   int cDir=MSign(g_snap.confidenceDir);
   if(InpUseCorrelation && cDir!=0)
      g_snap.confidenceFinal*=CorrelationDampener(cDir);

   // §9 self-calibrating threshold: sample once per bar, rank every tick
   if(newBar)
      PushConfidenceSample(g_snap.confidenceFinal);
   g_snap.confPercentile=ConfidencePercentile(g_snap.confidenceFinal);

   RecoverIfNeeded(b,g_snap.confidenceFinal,AccountInfoDouble(ACCOUNT_EQUITY));

   // §14 exit engine runs every tick, before any new-entry logic
   if(b.count>0)
     {
      ManageExits(b);
      GetBasket(b);
      ResetBasketStateIfFlat(b);
     }

   // §9 decision
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

//--- post-trade feedback: analytics refresh + adaptive selectivity (§18-§19)
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
