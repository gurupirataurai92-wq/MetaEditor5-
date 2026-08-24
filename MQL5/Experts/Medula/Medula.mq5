//+------------------------------------------------------------------+
//|                                                       Medula.mq5 |
//|  Medula EA — modular, event-driven, confidence-based trading.    |
//|  Implements the engines specified in MEDULA_FORMULAS.md:         |
//|    §1-§7  analysis engines   §8-§9  confidence + decision        |
//|    §10-§14 execution/basket/scaling/exit                         |
//|    §13,§15-§17 risk, allocation, session, correlation            |
//|    §18-§20 analytics, adaptive tuning, logging                   |
//|  Validation (§21) is performed offline in the Strategy Tester.   |
//+------------------------------------------------------------------+
#property copyright "Medula Project"
#property version   "1.00"

#include "MedulaTypes.mqh"
#include "MedulaIndicators.mqh"
#include "MedulaAnalysis.mqh"
#include "MedulaConfidence.mqh"
#include "MedulaAnalytics.mqh"
#include "MedulaRisk.mqh"
#include "MedulaTrade.mqh"

//--- General
input group "General"
input long   InpMagic            = 770015;   // Magic number
input int    InpDeviationPts     = 10;       // Max price deviation (points)
input bool   InpAnalyzeEveryTick = true;     // Full analysis every tick (false = per bar)
input bool   InpVerboseLog       = true;     // Print decisions to Experts log
input bool   InpCsvLog           = true;     // Write MedulaLog.csv (Files folder)

//--- Analysis (§1-§7)
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

//--- Confidence & Decision (§8-§9)
input group "Confidence & Decision"
input double InpW1 = 0.25;              // Weight: structure
input double InpW2 = 0.25;              // Weight: trend
input double InpW3 = 0.20;              // Weight: momentum
input double InpW4 = 0.15;              // Weight: liquidity
input double InpW5 = 0.15;              // Weight: MTF alignment
input double InpConfGain          = 2.5;  // Confidence tanh gain (§8)
input double InpMaxSpreadPoints   = 30.0; // Max acceptable spread (points)
input double InpConfThreshold     = 60.0; // Initial confidence threshold
input double InpHysteresis        = 8.0;  // Exit hysteresis band
input double InpMtfVetoConfluence = 50.0; // MTF veto confluence level

//--- Risk (§13)
input group "Risk"
input double InpRiskPct           = 0.75;  // Risk per trade (% equity)
input double InpSlAtrMult         = 1.5;   // SL distance (ATR mult)
input double InpTpAtrMult         = 3.0;   // TP distance (ATR mult)
input double InpDailyLossPct      = 3.0;   // Daily loss limit (%)
input double InpMaxDDPct          = 10.0;  // Max drawdown from peak (%)
input double InpMarginSafety      = 1.5;   // Free-margin safety factor
input double InpMaxAccountRiskPct = 4.0;   // Max total open risk (% equity)
input double InpMaxBasketRiskPct  = 2.5;   // Max basket risk (% equity)
input bool   InpAllowMinLot       = true;  // Round up to broker min lot (small accounts)

//--- Scaling (§12)
input group "Position Scaling"
input int    InpMaxScaleIns     = 3;     // Max add-on positions
input double InpScaleSpacingAtr = 1.0;   // Min spacing between adds (ATR mult)
input double InpScaleDecay      = 0.7;   // Lot decay factor per add
input double InpScaleConfK      = 0.9;   // Min confidence vs entry confidence

//--- Exits (§11, §14)
input group "Exits"
input double InpBasketTargetR  = 2.0;    // Basket profit target (R multiples)
input double InpTrailAtrMult   = 3.0;    // Chandelier trail (ATR mult)
input int    InpTrailLookback  = 22;     // Chandelier lookback (bars)
input int    InpMaxBarsInTrade = 96;     // Time stop (bars)
input double InpMinAcceptPL    = 0.0;    // Min P/L to bypass time stop

//--- Capital Allocation (§15)
input group "Capital Allocation"
input double InpConfGamma     = 1.5;     // Confidence sizing exponent
input bool   InpUseKellyCap   = true;    // Apply fractional-Kelly cap
input double InpKellyFraction = 0.25;    // Kelly fraction (quarter-Kelly)

//--- Session Intelligence (§16), hours in GMT
input group "Sessions"
input bool   InpUseSessions = true;      // Enable session multipliers
input double InpSessAsian   = 0.6;       // Asian (00-07 GMT)
input double InpSessLondon  = 1.0;       // London (07-12 GMT)
input double InpSessOverlap = 1.2;       // London/NY overlap (12-16 GMT)
input double InpSessNewYork = 1.0;       // New York (16-21 GMT)
input double InpSessDead    = 0.3;       // Dead zone (21-24 GMT)

//--- Correlation (§17)
input group "Correlation"
input bool   InpUseCorrelation = true;   // Enable correlation gating
input int    InpCorrBars       = 100;    // Correlation lookback (bars)
input double InpCorrThreshold  = 0.70;   // |r| threshold
input int    InpMaxCorrelated  = 2;      // Veto at this many correlated legs

//--- Execution Quality (§10)
input group "Execution Quality"
input double InpMaxSlippagePts   = 20.0; // Max acceptable avg slippage (points)
input int    InpExecWindow       = 20;   // Rolling attempts window
input double InpExecSuspendBelow = 50.0; // Suspend entries below this score

//--- Adaptive Parameter Engine (§19)
input group "Adaptive"
input bool   InpAdaptive     = true;     // Enable threshold adaptation
input double InpAdaptEta     = 2.0;      // Learning rate
input double InpAdaptAlpha   = 0.1;      // EMA smoothing
input double InpThrMin       = 50.0;     // Threshold lower bound
input double InpThrMax       = 85.0;     // Threshold upper bound
input int    InpAdaptRecentN = 20;       // Recent-trades window

//--- globals
SMedulaConfig    g_cfg;
CIndicators      g_ind;
CAnalysis        g_analysis;
CRisk            g_risk;
CTradeManager    g_tm;
CAnalytics       g_analytics;
CLogger          g_log;
SMarketSnapshot  g_snap;
double           g_thr;                  // adaptive confidence threshold
bool             g_haveSnap=false;
datetime         g_lastBar=0;
bool             g_breakerLogged=false;

//+------------------------------------------------------------------+
void FillConfig(void)
  {
   g_cfg.magic=InpMagic;
   g_cfg.deviationPts=InpDeviationPts;
   g_cfg.analyzeEveryTick=InpAnalyzeEveryTick;

   g_cfg.erLen=InpErLen;
   g_cfg.atrPeriod=InpAtrPeriod;
   g_cfg.adxPeriod=InpAdxPeriod;
   g_cfg.rsiPeriod=InpRsiPeriod;
   g_cfg.slopeBars=InpSlopeBars;
   g_cfg.structLookback=InpStructLookback;
   g_cfg.swingK=InpSwingK;
   g_cfg.structEvents=InpStructEvents;
   g_cfg.volRefBars=InpVolRefBars;
   g_cfg.volPctBars=InpVolPctBars;
   g_cfg.liqRangeAtr=InpLiqRangeAtr;
   g_cfg.bbPeriod=InpBbPeriod;
   g_cfg.bbDev=InpBbDev;
   g_cfg.rocLen=InpRocLen;

   // normalize confidence weights so they always sum to 1 (§8)
   double ws=InpW1+InpW2+InpW3+InpW4+InpW5;
   if(ws<=0.0) ws=1.0;
   g_cfg.w1=InpW1/ws; g_cfg.w2=InpW2/ws; g_cfg.w3=InpW3/ws;
   g_cfg.w4=InpW4/ws; g_cfg.w5=InpW5/ws;

   g_cfg.confGain=InpConfGain;
   g_cfg.maxSpreadPoints=InpMaxSpreadPoints;
   g_cfg.confThreshold=InpConfThreshold;
   g_cfg.hysteresis=InpHysteresis;
   g_cfg.mtfVetoConfluence=InpMtfVetoConfluence;

   g_cfg.riskPct=InpRiskPct;
   g_cfg.slAtrMult=InpSlAtrMult;
   g_cfg.tpAtrMult=InpTpAtrMult;
   g_cfg.dailyLossPct=InpDailyLossPct;
   g_cfg.maxDDPct=InpMaxDDPct;
   g_cfg.marginSafety=InpMarginSafety;
   g_cfg.maxAccountRiskPct=InpMaxAccountRiskPct;
   g_cfg.maxBasketRiskPct=InpMaxBasketRiskPct;
   g_cfg.allowMinLot=InpAllowMinLot;

   g_cfg.maxScaleIns=InpMaxScaleIns;
   g_cfg.scaleSpacingAtr=InpScaleSpacingAtr;
   g_cfg.scaleDecay=InpScaleDecay;
   g_cfg.scaleConfK=InpScaleConfK;

   g_cfg.basketTargetR=InpBasketTargetR;
   g_cfg.trailAtrMult=InpTrailAtrMult;
   g_cfg.trailLookback=InpTrailLookback;
   g_cfg.maxBarsInTrade=InpMaxBarsInTrade;
   g_cfg.minAcceptPL=InpMinAcceptPL;

   g_cfg.confGamma=InpConfGamma;
   g_cfg.useKellyCap=InpUseKellyCap;
   g_cfg.kellyFraction=InpKellyFraction;

   g_cfg.useSessions=InpUseSessions;
   g_cfg.sessAsian=InpSessAsian;
   g_cfg.sessLondon=InpSessLondon;
   g_cfg.sessOverlap=InpSessOverlap;
   g_cfg.sessNewYork=InpSessNewYork;
   g_cfg.sessDead=InpSessDead;

   g_cfg.useCorrelation=InpUseCorrelation;
   g_cfg.corrBars=InpCorrBars;
   g_cfg.corrThreshold=InpCorrThreshold;
   g_cfg.maxCorrelated=InpMaxCorrelated;

   g_cfg.maxSlippagePts=InpMaxSlippagePts;
   g_cfg.execWindow=InpExecWindow;
   g_cfg.execSuspendBelow=InpExecSuspendBelow;

   g_cfg.adaptive=InpAdaptive;
   g_cfg.adaptEta=InpAdaptEta;
   g_cfg.adaptAlpha=InpAdaptAlpha;
   g_cfg.thrMin=InpThrMin;
   g_cfg.thrMax=InpThrMax;
   g_cfg.adaptRecentN=InpAdaptRecentN;

   g_cfg.verboseLog=InpVerboseLog;
   g_cfg.csvLog=InpCsvLog;
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   FillConfig();
   g_log.Init(g_cfg.verboseLog,g_cfg.csvLog);

   if(!g_ind.Init(_Symbol,_Period,g_cfg))
     {
      Print("[Medula] indicator initialization failed");
      return INIT_FAILED;
     }
   if(!g_analysis.Init(_Symbol,_Period,g_cfg,g_ind))
      return INIT_FAILED;
   g_risk.Init(_Symbol,g_cfg);
   g_tm.Init(_Symbol,g_cfg,g_log);
   g_analytics.Init(_Symbol,g_cfg.magic,g_cfg.adaptRecentN);
   g_analytics.Refresh();

   g_thr=g_cfg.confThreshold;
   g_haveSnap=false;
   g_lastBar=0;

   g_log.Event(StringFormat("initialized on %s %s, threshold=%.1f",
                            _Symbol,EnumToString(_Period),g_thr));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_ind.Release();
   g_log.Event("deinitialized, reason="+IntegerToString(reason));
   g_log.Close();
  }

//+------------------------------------------------------------------+
//| Entry pipeline (§10, §12, §13, §15): sizing, gating, execution   |
//+------------------------------------------------------------------+
void TryEnter(const int dir,const bool isInitial,const SBasket &b)
  {
   // §10 execution circuit breaker
   if(!g_tm.ExecutionHealthy())
      return;
   // §16 session gate (a zero multiplier means "do not trade")
   double sessMult=g_risk.SessionMultiplier();
   if(sessMult<=0.0)
      return;
   // hard spread gate (§10) — the soft penalty already reduced confidence
   if(g_snap.spreadPts>g_cfg.maxSpreadPoints)
      return;
   // §17 correlation hard veto
   if(g_risk.CorrelationVeto(dir,g_cfg.magic))
     {
      g_log.Event("entry vetoed: correlated exposure limit");
      return;
     }

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double slDist=g_cfg.slAtrMult*g_snap.atr;
   double lots,riskAmt;

   if(isInitial)
     {
      // §13 base risk, scaled by session (§16) and regime (§1)
      riskAmt=eq*g_cfg.riskPct/100.0*sessMult*g_risk.RegimeRiskMult(g_snap.regime);
      double baseLot=g_risk.LotForRisk(riskAmt,slDist);
      // §15 confidence + inverse-volatility allocation
      double confAdj=MathPow(MClamp(g_snap.confidenceFinal/100.0,0.0,1.0),g_cfg.confGamma);
      double volAdj=MClamp(1.0/MathMax(g_snap.vr,0.1),0.5,2.0);
      lots=baseLot*confAdj*volAdj;
      // §15 quarter-Kelly cap once there is enough trade history
      if(g_cfg.useKellyCap && g_analytics.Trades()>=30)
        {
         double f=g_analytics.KellyFraction(g_cfg.kellyFraction,
                                            g_cfg.riskPct/100.0*2.0);
         double maxLot=g_risk.LotForRisk(f*eq,slDist);
         if(maxLot>0.0)
            lots=MathMin(lots,maxLot);
        }
     }
   else
     {
      // §12 decaying scale-in size: initial lot * decay^(adds so far + 1)
      lots=g_tm.InitialLot()*MathPow(g_cfg.scaleDecay,b.count);
      riskAmt=g_risk.RiskOfLots(lots,slDist);
     }

   lots=g_risk.NormalizeLots(lots);
   if(lots<=0.0)
      return;

   // §13 exposure caps: basket risk and total account risk
   double newRisk=g_risk.RiskOfLots(lots,slDist);
   if(g_tm.BasketRiskUsed()+newRisk>eq*g_cfg.maxBasketRiskPct/100.0)
      return;
   if(g_tm.AccountRiskUsed()+newRisk>eq*g_cfg.maxAccountRiskPct/100.0)
      return;
   // §10 margin validation
   if(!g_risk.MarginOK(dir,lots))
     {
      g_log.Event("entry skipped: insufficient free margin");
      return;
     }

   string reason=StringFormat("regime=%s conf=%.0f trend=%.0f mom=%.0f struct=%.0f mtf=%.2f",
                              RegimeName(g_snap.regime),g_snap.confidenceFinal,
                              g_snap.trendScore,g_snap.momentumScore,
                              g_snap.structureScore,g_snap.mtfAlignment);
   if(g_tm.Open(dir,lots,g_snap.atr,g_snap.confidenceFinal,riskAmt,isInitial,b.count))
     {
      string action=(dir>0 ? (isInitial ? "BUY" : "BUY_SCALE")
                           : (isInitial ? "SELL" : "SELL_SCALE"));
      g_log.Decision(g_snap,action,lots,reason);
     }
  }

//+------------------------------------------------------------------+
//| Core event loop (§ "Engine Data Flow Summary")                   |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   g_risk.Update();

   SBasket b;
   g_tm.GetBasket(b);
   g_tm.ResetBasketStateIfFlat(b);

   // §13 account circuit breaker: flatten and stand down
   if(g_risk.CircuitBreaker())
     {
      if(b.count>0)
         g_tm.CloseBasket("risk circuit breaker");
      if(!g_breakerLogged)
        {
         g_log.Event("circuit breaker active: trading suspended");
         g_breakerLogged=true;
        }
      return;
     }
   g_breakerLogged=false;

   // analysis refresh: every tick, or on new bar with light tick updates
   datetime curBar=iTime(_Symbol,_Period,0);
   bool newBar=(curBar!=g_lastBar);
   if(newBar)
      g_lastBar=curBar;
   if(g_cfg.analyzeEveryTick || newBar || !g_haveSnap)
     {
      if(!g_analysis.Update(g_snap))
         return;                       // history not ready yet
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
   ComputeConfidence(g_snap,g_tm.ExecutionQuality(),g_cfg);

   // §17 correlation soft dampener on the would-be trade direction
   int cDir=MSign(g_snap.confidenceDir);
   if(g_cfg.useCorrelation && cDir!=0)
      g_snap.confidenceFinal*=g_risk.CorrelationDampener(cDir,g_cfg.magic);

   g_tm.RecoverIfNeeded(b,g_snap.confidenceFinal,AccountInfoDouble(ACCOUNT_EQUITY));

   // §14 exit engine runs every tick, before any new-entry logic
   if(b.count>0)
     {
      g_tm.ManageExits(g_snap,b,g_analysis.PeakMomAbs());
      g_tm.GetBasket(b);
      g_tm.ResetBasketStateIfFlat(b);
     }

   // §9 decision
   ENUM_DECISION d=Decide(g_snap,b.count>0,b.dir,g_thr,g_cfg);

   if(d==DECISION_EXIT)
     {
      g_tm.CloseBasket("confidence collapse / direction flip");
      g_log.Decision(g_snap,"EXIT",0.0,"confidence collapse / direction flip");
      return;
     }
   if(d==DECISION_BUY || d==DECISION_SELL)
      TryEnter(d==DECISION_BUY ? 1 : -1,true,b);
   else if(d==DECISION_HOLD && b.count>0 && g_tm.ScaleInAllowed(b,g_snap))
      TryEnter(b.dir,false,b);
  }

//+------------------------------------------------------------------+
//| Post-trade feedback: analytics refresh + adaptive tuning (§18-19)|
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=g_cfg.magic)
      return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol)
      return;
   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY)
      return;

   g_analytics.Refresh();
   if(g_cfg.adaptive)
     {
      double riskUnit=AccountInfoDouble(ACCOUNT_EQUITY)*g_cfg.riskPct/100.0;
      double before=g_thr;
      g_analytics.AdaptThreshold(g_thr,riskUnit,g_cfg);
      if(MathAbs(g_thr-before)>0.01)
         g_log.Event(StringFormat("adaptive threshold %.1f -> %.1f",before,g_thr));
     }
   g_log.Event(g_analytics.Summary());
  }
//+------------------------------------------------------------------+
