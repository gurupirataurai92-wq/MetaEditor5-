//+------------------------------------------------------------------+
//|                                                  MedulaTypes.mqh |
//|  Shared enums, structs, config, math helpers and logger.         |
//|  Formula references point to MEDULA_FORMULAS.md sections.        |
//+------------------------------------------------------------------+
#ifndef MEDULA_TYPES_MQH
#define MEDULA_TYPES_MQH

//--- Market regimes (§1)
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

//--- Decision outcomes (§9)
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

string DecisionName(const ENUM_DECISION d)
  {
   switch(d)
     {
      case DECISION_BUY:  return "BUY";
      case DECISION_SELL: return "SELL";
      case DECISION_HOLD: return "HOLD";
      case DECISION_EXIT: return "EXIT";
     }
   return "WAIT";
  }

//--- Math helpers
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

//--- Full runtime configuration (mirrors EA inputs)
struct SMedulaConfig
  {
   // general
   long              magic;
   int               deviationPts;
   bool              analyzeEveryTick;
   // analysis (§1-§7)
   int               erLen;
   int               atrPeriod;
   int               adxPeriod;
   int               rsiPeriod;
   int               slopeBars;
   int               structLookback;
   int               swingK;
   int               structEvents;
   int               volRefBars;
   int               volPctBars;
   double            liqRangeAtr;
   int               bbPeriod;
   double            bbDev;
   int               rocLen;
   // confidence / decision (§8-§9)
   double            w1,w2,w3,w4,w5;
   double            maxSpreadPoints;
   double            confThreshold;
   double            hysteresis;
   double            mtfVetoConfluence;
   // risk (§13)
   double            riskPct;
   double            slAtrMult;
   double            tpAtrMult;
   double            dailyLossPct;
   double            maxDDPct;
   double            marginSafety;
   double            maxAccountRiskPct;
   double            maxBasketRiskPct;
   bool              allowMinLot;
   // scaling (§12)
   int               maxScaleIns;
   double            scaleSpacingAtr;
   double            scaleDecay;
   double            scaleConfK;
   // exits (§11, §14)
   double            basketTargetR;
   double            trailAtrMult;
   int               trailLookback;
   int               maxBarsInTrade;
   double            minAcceptPL;
   // capital allocation (§15)
   double            confGamma;
   bool              useKellyCap;
   double            kellyFraction;
   // session (§16)
   bool              useSessions;
   double            sessAsian;
   double            sessLondon;
   double            sessOverlap;
   double            sessNewYork;
   double            sessDead;
   // correlation (§17)
   bool              useCorrelation;
   int               corrBars;
   double            corrThreshold;
   int               maxCorrelated;
   // execution quality (§10)
   double            maxSlippagePts;
   int               execWindow;
   double            execSuspendBelow;
   // adaptive (§19)
   bool              adaptive;
   double            adaptEta;
   double            adaptAlpha;
   double            thrMin;
   double            thrMax;
   int               adaptRecentN;
   // logging (§20)
   bool              verboseLog;
   bool              csvLog;
  };

//--- Snapshot of all engine outputs for the current tick
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
   bool              bullBos,bearBos;
   bool              bullChoch,bearChoch;
   double            confidenceDir;    // §8, -100..+100 (sign = direction)
   double            confidenceFinal;  // §8, 0..100 after penalties
   double            bid,ask,close;
   double            spreadPts;
  };

//--- Aggregated basket metrics (§11)
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

//+------------------------------------------------------------------+
//| Logging & Diagnostics Engine (§20)                               |
//+------------------------------------------------------------------+
class CLogger
  {
private:
   bool              m_verbose;
   int               m_h;
public:
                     CLogger(void):m_verbose(true),m_h(INVALID_HANDLE){}

   void Init(const bool verbose,const bool csv)
     {
      m_verbose=verbose;
      m_h=INVALID_HANDLE;
      if(csv)
        {
         m_h=FileOpen("MedulaLog.csv",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
         if(m_h!=INVALID_HANDLE)
           {
            if(FileSize(m_h)==0)
               FileWriteString(m_h,"time;symbol;regime;structure;trend;momentum;volPct;liquidity;mtf;confidence;decision;lots;reason\n");
            FileSeek(m_h,0,SEEK_END);
           }
        }
     }

   void Close(void)
     {
      if(m_h!=INVALID_HANDLE)
        {
         FileClose(m_h);
         m_h=INVALID_HANDLE;
        }
     }

   void Event(const string msg)
     {
      if(m_verbose)
         Print("[Medula] ",msg);
     }

   // structured decision record: full input vector that produced the action
   void Decision(const SMarketSnapshot &snap,const string decision,const double lots,const string reason)
     {
      string line=StringFormat("%s;%s;%s;%.1f;%.1f;%.1f;%.1f;%.1f;%.2f;%.1f;%s;%.2f;%s",
                               TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                               _Symbol,RegimeName(snap.regime),
                               snap.structureScore,snap.trendScore,snap.momentumScore,
                               snap.volPercentile,snap.liquidityScore,snap.mtfAlignment,
                               snap.confidenceFinal,decision,lots,reason);
      if(m_verbose)
         Print("[Medula] ",line);
      if(m_h!=INVALID_HANDLE)
        {
         FileWriteString(m_h,line+"\n");
         FileFlush(m_h);
        }
     }
  };

#endif // MEDULA_TYPES_MQH
