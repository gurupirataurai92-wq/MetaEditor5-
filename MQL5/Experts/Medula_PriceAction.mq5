//+------------------------------------------------------------------+
//|                                           Medula_PriceAction.mq5 |
//|  Medula v3.00 — pure price action. Single file, zero includes.   |
//|                                                                  |
//|  NO INDICATORS. There is not one iRSI / iMACD / iADX / iBands /  |
//|  iMA handle in this file. Every decision is derived from raw      |
//|  OHLC bars:                                                      |
//|                                                                  |
//|    §A  Swing structure    fractal highs/lows, BOS, CHoCH         |
//|    §B  Supply & demand    base + impulse zones, freshness, tests |
//|    §C  Trend              HH/HL vs LH/LL sequence, not an EMA    |
//|    §D  Momentum           body dominance, displacement, runs     |
//|    §E  Volatility         true range computed directly           |
//|    §F  Liquidity          equal highs/lows, stop clusters        |
//|    §G  Order flow         close location within each bar's range |
//|    §H  Multi-timeframe    higher-TF structure, not higher-TF EMA |
//|                                                                  |
//|  ATR appears only as a distance unit for stops and sizing. It is  |
//|  computed here from true range and never generates a signal.     |
//|                                                                  |
//|  Entries are price-action setups, not score crossings:           |
//|    1. Price returns to a FRESH zone and rejects it, with market   |
//|       structure on that side  -> trade the zone                  |
//|    2. Structure breaks and price retests the broken level        |
//|       -> trade the continuation                                   |
//|                                                                  |
//|  Risk carries the v2.70 corrections: R is measured against the    |
//|  risk actually taken, and a hard ceiling caps any single trade.  |
//+------------------------------------------------------------------+
#property copyright "Medula Project"
#property version   "3.10"

//============================== INPUTS ==============================

input group "General"
input long   InpMagic            = 770030;   // Magic number
input int    InpDeviationPts     = 30;       // Max price deviation (points)
input bool   InpVerboseLog       = true;     // Print decisions to Experts log
input bool   InpCsvLog           = true;     // Write MedulaPA.csv (Files folder)
input bool   InpShowPanel        = true;     // Live panel on chart
input bool   InpDiagnostics      = true;     // Log WHY an entry was skipped
input int    InpDiagThrottleSec  = 600;      // Min seconds between repeats of a reason
input bool   InpSelfTest         = true;     // Print readiness report on attach

input group "Price Structure (§A)"
input int    InpBars           = 400;   // Bars of price history to analyse
input int    InpSwingK         = 2;     // Fractal wing size (bars each side)
input int    InpSwingsTracked  = 12;    // Swings kept for trend/structure
input double InpBosBufferAtr   = 0.05;  // Break must clear the level by this x ATR

input group "Supply & Demand Zones (§B)"
input int    InpZoneMaxBase    = 3;     // Max base candles forming a zone
input double InpImpulseAtr     = 1.20;  // Departure candle range >= this x ATR
input double InpImpulseBody    = 0.55;  // Departure body must be >= this share of range
input double InpBaseMaxAtr     = 0.85;  // Base candle range <= this x ATR
input int    InpMaxZones       = 24;    // Zones tracked per side
input int    InpZoneMaxAgeBars = 400;   // Forget zones older than this
input int    InpZoneMaxTests   = 2;     // Zone is dead after this many touches
input double InpZoneProxAtr    = 0.60;  // Entry considered within this x ATR of a zone

input group "Entry Setups"
input bool   InpUseZoneEntry     = true;  // Trade rejections from fresh zones
input bool   InpUseRetestEntry   = true;  // Trade retests of broken structure
input bool   InpRequireRejection = true;  // Demand a rejection wick before entering
input double InpRejectWickFrac   = 0.30;  // Wick into zone >= this share of bar range
input bool   InpRequireStructure = true;  // Only trade with prevailing structure
input int    InpEntryCooldownSec = 60;    // Min seconds between entries

input group "Conviction & Selectivity"
input double InpWStructure = 0.26;      // Weight: market structure
input double InpWZone      = 0.28;      // Weight: zone quality
input double InpWMomentum  = 0.16;      // Weight: price momentum
input double InpWFlow      = 0.12;      // Weight: order flow
input double InpWMtf       = 0.12;      // Weight: higher-timeframe structure
input double InpWLiquidity = 0.06;      // Weight: liquidity pools
input double InpConvGain          = 2.2;   // Conviction tanh gain
input bool   InpUsePercentile     = true;  // Rank conviction vs its own history
input double InpEntryPercentile   = 68.0;  // Enter in the top (100-this)%
input int    InpConfSampleSize    = 400;   // Rolling distribution size (bars)
input int    InpMinSamples        = 30;    // Samples before percentile mode engages
input double InpMinAbsConviction  = 12.0;  // Absolute floor (safety, never relaxed)
input double InpBootstrapConv     = 25.0;  // Threshold while the distribution fills
input double InpExitConvFraction  = 0.50;  // Exit below this x entry conviction

input group "Participation Watchdog"
input bool   InpUseWatchdog      = true;  // Relax selectivity when idle too long
input int    InpIdleBarsRelax    = 12;    // Idle bars before relaxation starts
input int    InpRelaxEveryBars   = 5;     // Relax a step per this many further bars
input double InpRelaxStepPct     = 2.5;   // Percentile points released per step
input double InpRelaxFloorPct    = 45.0;  // Never relax below this percentile

input group "Risk"
input double InpRiskPct           = 1.0;   // Risk per trade (% equity)
input double InpAtrPeriod         = 14;    // True-range averaging period
input double InpSlAtrMult         = 1.2;   // Stop distance beyond the zone (x ATR)
input double InpTpRMultiple       = 2.5;   // Target as a multiple of risk
input double InpDailyLossPct      = 5.0;   // Daily loss limit (%)
input double InpMaxDDPct          = 20.0;  // Max drawdown from peak (%)
input double InpMarginSafety      = 1.2;   // Free-margin safety factor
input double InpMaxAccountRiskPct = 6.0;   // Max total open risk (% equity)
input double InpMaxBasketRiskPct  = 4.0;   // Max basket risk (% equity)
input double InpMaxRiskPctHard    = 20.0;  // ABSOLUTE ceiling on one trade (% equity)
input bool   InpAllowMinLot       = true;  // Round up to broker min lot
input bool   InpMinLotOverride    = true;  // Min-lot trade may exceed the planned cap
input bool   InpFitStopToAccount  = false; // Tighten the stop so min lot fits the ceiling
input bool   InpSkipUnaffordable  = true;  // Otherwise skip setups whose stop is too wide

input group "Exits"
input bool   InpUseBreakEven   = true;   // Move stop to entry once in profit
input double InpBreakEvenAtR   = 1.0;    // R multiple that triggers break-even
input double InpBreakEvenBuf   = 0.10;   // Break-even buffer (x ATR)
input bool   InpUsePartialTP   = true;   // Scale out part of the position
input double InpPartialAtR     = 1.0;    // Partial take-profit at this R
input double InpPartialPct     = 50.0;   // Percent of volume to close
input bool   InpUseTrail       = true;   // Trail behind swing structure
input double InpTrailAtrMult   = 1.5;    // Trail distance beyond the swing (x ATR)
input int    InpMaxBarsInTrade = 200;    // Time stop (bars)
input bool   InpExitOnOppZone  = true;   // Exit when price reaches an opposing zone

input group "Sessions (GMT)"
input bool   InpUseSessions = false;     // Apply session risk multipliers
input double InpSessAsian   = 0.7;       // Asian (00-07 GMT)
input double InpSessLondon  = 1.0;       // London (07-12 GMT)
input double InpSessOverlap = 1.2;       // London/NY overlap (12-16 GMT)
input double InpSessNewYork = 1.0;       // New York (16-21 GMT)
input double InpSessDead    = 0.5;       // Dead zone (21-24 GMT)

input group "Execution"
input double InpMaxSpreadAtr  = 0.50;    // Spread ceiling as a fraction of ATR
input double InpMinSpreadPts  = 50.0;    // Absolute spread floor allowance (points)

//========================= TYPES & HELPERS ==========================

enum ENUM_DECISION { DEC_WAIT=0, DEC_BUY, DEC_SELL, DEC_HOLD, DEC_EXIT };

double MTanh(const double x)
  {
   if(x>20.0)  return 1.0;
   if(x<-20.0) return -1.0;
   double e=MathExp(2.0*x);
   return (e-1.0)/(e+1.0);
  }
double MClamp(const double x,const double lo,const double hi){ return MathMin(MathMax(x,lo),hi); }
int    MSign(const double x){ if(x>0.0) return 1; if(x<0.0) return -1; return 0; }

//--- a supply or demand zone born from base-then-impulse price action (§B)
struct SZone
  {
   double            top;
   double            bottom;
   int               dir;          // +1 demand (support), -1 supply (resistance)
   datetime          born;
   int               bornShift;    // bar index when created (for ageing)
   double            strength;     // impulse size in ATR units
   int               tests;        // times price has traded into it
   bool              alive;
  };

//--- swing point
struct SSwing
  {
   double            price;
   bool              isHigh;
   int               shift;
  };

//--- everything the engines produce for the current bar
struct SView
  {
   double            atr;
   double            bid,ask,spreadPts;
   // §A structure
   int               structDir;        // +1 up, -1 down, 0 unclear
   double            structScore;      // -100..+100
   bool              bullBos,bearBos,bullChoch,bearChoch;
   double            lastSwingHigh,lastSwingLow;
   double            brokenLevel;      // level broken by the most recent BOS
   int               brokenDir;
   int               brokenAgeBars;
   // §B zones
   double            zoneScore;        // -100..+100 (positive = demand nearby)
   int               activeZoneIdx;    // zone price is currently interacting with
   double            zoneTop,zoneBottom;
   int               zoneDir;
   double            zoneStrength;
   int               zoneTests;
   // §C-§H
   double            trendScore;       // -100..+100
   double            momentumScore;    // -100..+100
   double            flowScore;        // -100..+100
   double            liquidityScore;   // -100..+100
   double            mtfScore;         // -100..+100
   // decision layer
   double            convictionDir;    // -100..+100 (sign = side)
   double            conviction;       // 0..100
   double            convPercentile;
   string            setup;            // human-readable setup name
   int               setupDir;
  };

//--- basket
struct SBasket
  {
   int               count;
   double            totalVolume,avgEntry,floatPL;
   int               dir;
   datetime          firstEntryTime,lastEntryTime;
   double            lastEntryPrice,firstEntryVolume;
  };

//=========================== GLOBAL STATE ===========================

double   g_w[6];                        // normalized conviction weights
// raw price cache — refreshed once per analysis pass, no indicator handles
double   g_h[],g_l[],g_o[],g_c[];
long     g_v[];
int      g_bars=0;
// structure
SSwing   g_swings[];
// zones
SZone    g_zones[];
// view
SView    g_view;
// conviction distribution
double   g_conv[];
int      g_convHead=0,g_convCount=0;
double   g_entryPct,g_effPct;
int      g_barsSinceEntry=0;
// basket state
double   g_entryConviction=0.0,g_initialRiskAmt=0.0,g_initialLot=0.0;
double   g_entryZoneTop=0.0,g_entryZoneBottom=0.0;
ulong    g_partialDone[],g_beDone[];
// risk
double   g_dayStartEquity=0.0,g_peakEquity=0.0;
int      g_dayKey=-1;
bool     g_breakerLatched=false,g_breakerLogged=false;
// housekeeping
datetime g_lastBar=0,g_lastEntryTime=0;
int      g_logHandle=INVALID_HANDLE;
string   g_block="starting up",g_lastBlock="";
datetime g_lastBlockLog=0;
int      g_entries=0;
bool     g_haveView=false;

//============================== LOGGING =============================

void LogInit(void)
  {
   g_logHandle=INVALID_HANDLE;
   if(!InpCsvLog) return;
   g_logHandle=FileOpen("MedulaPA.csv",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(g_logHandle!=INVALID_HANDLE)
     {
      if(FileSize(g_logHandle)==0)
         FileWriteString(g_logHandle,"time;symbol;setup;structure;zone;trend;momentum;flow;mtf;conviction;pctile;decision;lots;entry;sl;tp;reason\n");
      FileSeek(g_logHandle,0,SEEK_END);
     }
  }
void LogClose(void){ if(g_logHandle!=INVALID_HANDLE){ FileClose(g_logHandle); g_logHandle=INVALID_HANDLE; } }
void LogEvent(const string m){ if(InpVerboseLog) Print("[MedulaPA] ",m); }

void LogTrade(const string decision,const double lots,const double entry,
              const double sl,const double tp,const string reason)
  {
   string line=StringFormat("%s;%s;%s;%.1f;%.1f;%.1f;%.1f;%.1f;%.1f;%.1f;%.0f;%s;%.2f;%.5f;%.5f;%.5f;%s",
                            TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),_Symbol,
                            g_view.setup,g_view.structScore,g_view.zoneScore,g_view.trendScore,
                            g_view.momentumScore,g_view.flowScore,g_view.mtfScore,
                            g_view.conviction,g_view.convPercentile,decision,lots,entry,sl,tp,reason);
   if(InpVerboseLog) Print("[MedulaPA] ",line);
   if(g_logHandle!=INVALID_HANDLE){ FileWriteString(g_logHandle,line+"\n"); FileFlush(g_logHandle); }
  }

void Block(const string reason)
  {
   g_block=reason;
   if(!InpDiagnostics) return;
   datetime now=TimeCurrent();
   if(reason==g_lastBlock && (now-g_lastBlockLog)<InpDiagThrottleSec) return;
   g_lastBlock=reason; g_lastBlockLog=now;
   LogEvent("no entry — "+reason);
  }

//===================== §E VOLATILITY FROM RAW PRICE ==================

//--- true range needs no indicator: it is arithmetic on the bars themselves
double TrueRange(const int i)
  {
   if(i+1>=g_bars) return g_h[i]-g_l[i];
   double a=g_h[i]-g_l[i];
   double b=MathAbs(g_h[i]-g_c[i+1]);
   double d=MathAbs(g_l[i]-g_c[i+1]);
   return MathMax(a,MathMax(b,d));
  }

double AverageTrueRange(const int period,const int startShift=0)
  {
   int n=MathMin(period,g_bars-startShift-1);
   if(n<=0) return 0.0;
   double s=0.0;
   for(int i=0;i<n;i++)
      s+=TrueRange(startShift+i);
   return s/n;
  }

//--- refresh the raw price cache; this is the only market data source
bool LoadBars(void)
  {
   int want=InpBars;
   ArraySetAsSeries(g_h,true); ArraySetAsSeries(g_l,true);
   ArraySetAsSeries(g_o,true); ArraySetAsSeries(g_c,true);
   ArraySetAsSeries(g_v,true);
   int got=CopyHigh(_Symbol,_Period,0,want,g_h);
   if(got<60){ Block(StringFormat("only %d bars of history loaded, need 60+",got)); return false; }
   if(CopyLow(_Symbol,_Period,0,got,g_l)<got)   return false;
   if(CopyOpen(_Symbol,_Period,0,got,g_o)<got)  return false;
   if(CopyClose(_Symbol,_Period,0,got,g_c)<got) return false;
   if(CopyTickVolume(_Symbol,_Period,0,got,g_v)<got)
      ArrayInitialize(g_v,1);
   g_bars=got;
   return true;
  }

//======================= §A SWING STRUCTURE =========================

bool IsSwingHigh(const int j,const int k)
  {
   if(j-k<0 || j+k>=g_bars) return false;
   for(int m=1;m<=k;m++)
      if(g_h[j]<=g_h[j+m] || g_h[j]<=g_h[j-m]) return false;
   return true;
  }
bool IsSwingLow(const int j,const int k)
  {
   if(j-k<0 || j+k>=g_bars) return false;
   for(int m=1;m<=k;m++)
      if(g_l[j]>=g_l[j+m] || g_l[j]>=g_l[j-m]) return false;
   return true;
  }

//--- Walk the window oldest -> newest, collecting confirmed swings and the
//    break-of-structure / change-of-character events they produce. A fractal
//    is only knowable k bars after it prints, which is respected here.
void BuildStructure(void)
  {
   ArrayResize(g_swings,0);
   g_view.bullBos=false; g_view.bearBos=false;
   g_view.bullChoch=false; g_view.bearChoch=false;
   g_view.brokenLevel=0.0; g_view.brokenDir=0; g_view.brokenAgeBars=9999;

   int k=InpSwingK;
   double buf=InpBosBufferAtr*g_view.atr;
   double lastSH=0.0,lastSL=0.0;
   int dir=0;
   int hh=0,hl=0,lh=0,ll=0;
   double prevHigh=0.0,prevLow=0.0;

   for(int b=g_bars-1-k;b>=0;b--)
     {
      int j=b+k;
      if(j<=g_bars-1-k)
        {
         if(IsSwingHigh(j,k))
           {
            SSwing s; s.price=g_h[j]; s.isHigh=true; s.shift=j;
            int n=ArraySize(g_swings); ArrayResize(g_swings,n+1); g_swings[n]=s;
            if(prevHigh>0.0){ if(g_h[j]>prevHigh) hh++; else lh++; }
            prevHigh=g_h[j];
            lastSH=g_h[j];
           }
         if(IsSwingLow(j,k))
           {
            SSwing s; s.price=g_l[j]; s.isHigh=false; s.shift=j;
            int n=ArraySize(g_swings); ArrayResize(g_swings,n+1); g_swings[n]=s;
            if(prevLow>0.0){ if(g_l[j]>prevLow) hl++; else ll++; }
            prevLow=g_l[j];
            lastSL=g_l[j];
           }
        }
      if(lastSH>0.0 && g_c[b]>lastSH+buf)
        {
         bool choch=(dir==-1);
         dir=1;
         g_view.brokenLevel=lastSH; g_view.brokenDir=1; g_view.brokenAgeBars=b;
         if(choch){ if(b<=1) g_view.bullChoch=true; }
         else     { if(b<=1) g_view.bullBos=true; }
         lastSH=0.0;
        }
      if(lastSL>0.0 && g_c[b]<lastSL-buf)
        {
         bool choch=(dir==1);
         dir=-1;
         g_view.brokenLevel=lastSL; g_view.brokenDir=-1; g_view.brokenAgeBars=b;
         if(choch){ if(b<=1) g_view.bearChoch=true; }
         else     { if(b<=1) g_view.bearBos=true; }
         lastSL=0.0;
        }
     }

   g_view.structDir=dir;
   g_view.lastSwingHigh=0.0; g_view.lastSwingLow=0.0;
   for(int i=ArraySize(g_swings)-1;i>=0;i--)
     {
      if(g_view.lastSwingHigh<=0.0 && g_swings[i].isHigh) g_view.lastSwingHigh=g_swings[i].price;
      if(g_view.lastSwingLow <=0.0 && !g_swings[i].isHigh) g_view.lastSwingLow =g_swings[i].price;
      if(g_view.lastSwingHigh>0.0 && g_view.lastSwingLow>0.0) break;
     }

   // §C trend read directly from the swing sequence: higher highs and higher
   // lows against lower highs and lower lows. No moving average involved.
   int bull=hh+hl, bear=lh+ll;
   g_view.trendScore=100.0*(double)(bull-bear)/(double)(bull+bear+1);
   g_view.structScore=MClamp(0.6*g_view.trendScore+40.0*dir,-100.0,100.0);
  }

//===================== §B SUPPLY & DEMAND ZONES =====================

void AddZone(const double top,const double bottom,const int dir,
             const int shift,const double strength)
  {
   SZone z;
   z.top=top; z.bottom=bottom; z.dir=dir;
   z.born=(datetime)iTime(_Symbol,_Period,MathMin(shift,g_bars-1));
   z.bornShift=shift; z.strength=strength; z.tests=0; z.alive=true;
   int n=ArraySize(g_zones);
   ArrayResize(g_zones,n+1);
   g_zones[n]=z;
  }

//--- A zone is where price left an area so fast that orders were stranded:
//    one to three quiet "base" candles, then a decisive departure candle.
//    Demand = base then impulse up. Supply = base then impulse down.
//    The zone is the base's range; the departure proves imbalance.
void BuildZones(void)
  {
   ArrayResize(g_zones,0);
   if(g_view.atr<=0.0) return;

   int scanFrom=MathMin(g_bars-3,InpZoneMaxAgeBars);
   for(int i=scanFrom;i>=1;i--)
     {
      double rng=g_h[i]-g_l[i];
      if(rng<=0.0) continue;
      double body=MathAbs(g_c[i]-g_o[i]);
      bool impulseUp  =(rng>=InpImpulseAtr*g_view.atr && body>=InpImpulseBody*rng && g_c[i]>g_o[i]);
      bool impulseDn  =(rng>=InpImpulseAtr*g_view.atr && body>=InpImpulseBody*rng && g_c[i]<g_o[i]);
      if(!impulseUp && !impulseDn) continue;

      // walk back over the quiet candles that formed the base
      double top=-DBL_MAX,bot=DBL_MAX;
      int used=0;
      for(int b=i+1;b<=i+InpZoneMaxBase && b<g_bars;b++)
        {
         double br=g_h[b]-g_l[b];
         if(br>InpBaseMaxAtr*g_view.atr) break;
         top=MathMax(top,g_h[b]);
         bot=MathMin(bot,g_l[b]);
         used++;
        }
      if(used==0) continue;

      double strength=rng/g_view.atr;
      AddZone(top,bot,(impulseUp?1:-1),i,strength);
      if(ArraySize(g_zones)>=InpMaxZones*2) break;
     }

   // count how often price has since traded back into each zone; a zone that
   // has been tested repeatedly has had its stranded orders filled already
   for(int z=ArraySize(g_zones)-1;z>=0;z--)
     {
      int tests=0;
      for(int i=g_zones[z].bornShift-1;i>=0;i--)
        {
         if(g_l[i]<=g_zones[z].top && g_h[i]>=g_zones[z].bottom)
           {
            tests++;
            while(i>0 && g_l[i-1]<=g_zones[z].top && g_h[i-1]>=g_zones[z].bottom) i--;
           }
        }
      g_zones[z].tests=tests;
      if(tests>InpZoneMaxTests) g_zones[z].alive=false;
      // a zone price has closed decisively through is no longer a zone
      if(g_zones[z].dir>0 && g_c[0]<g_zones[z].bottom-0.5*g_view.atr) g_zones[z].alive=false;
      if(g_zones[z].dir<0 && g_c[0]>g_zones[z].top   +0.5*g_view.atr) g_zones[z].alive=false;
     }
  }

//--- score the zone landscape around current price and identify the one
//    price is actually interacting with right now
void EvaluateZones(void)
  {
   g_view.zoneScore=0.0;
   g_view.activeZoneIdx=-1;
   g_view.zoneTop=0.0; g_view.zoneBottom=0.0;
   g_view.zoneDir=0; g_view.zoneStrength=0.0; g_view.zoneTests=0;

   double px=g_view.bid;
   double prox=InpZoneProxAtr*g_view.atr;
   double demandPull=0.0,supplyPull=0.0;
   double bestScore=-1.0;

   for(int z=0;z<ArraySize(g_zones);z++)
     {
      if(!g_zones[z].alive) continue;
      double top=g_zones[z].top,bot=g_zones[z].bottom;
      double dist=0.0;
      if(px>top)      dist=px-top;
      else if(px<bot) dist=bot-px;
      else            dist=0.0;                      // price is inside the zone
      if(dist>3.0*g_view.atr) continue;

      double freshness=MClamp(1.0-(double)g_zones[z].tests/(double)MathMax(InpZoneMaxTests,1),0.0,1.0);
      double nearness =MClamp(1.0-dist/(3.0*g_view.atr),0.0,1.0);
      double strength =MClamp(g_zones[z].strength/3.0,0.0,1.0);
      double quality  =freshness*0.45+nearness*0.35+strength*0.20;

      if(g_zones[z].dir>0) demandPull+=quality;
      else                 supplyPull+=quality;

      // the zone price is touching, or closest to, is the actionable one
      if(dist<=prox && quality>bestScore)
        {
         bestScore=quality;
         g_view.activeZoneIdx=z;
         g_view.zoneTop=top; g_view.zoneBottom=bot;
         g_view.zoneDir=g_zones[z].dir;
         g_view.zoneStrength=g_zones[z].strength;
         g_view.zoneTests=g_zones[z].tests;
        }
     }
   g_view.zoneScore=100.0*MTanh(1.5*(demandPull-supplyPull));
  }

//================= §D MOMENTUM / §G FLOW / §F LIQUIDITY =============

//--- Momentum straight from candle anatomy: how much of the recent range was
//    directional body rather than indecisive wick, plus the run of closes.
void EvaluateMomentum(void)
  {
   int n=MathMin(10,g_bars-1);
   if(n<3){ g_view.momentumScore=0.0; return; }
   double bodySum=0.0,rangeSum=0.0;
   for(int i=0;i<n;i++)
     {
      double rng=g_h[i]-g_l[i];
      if(rng<=0.0) continue;
      bodySum +=(g_c[i]-g_o[i]);
      rangeSum+=rng;
     }
   double dominance=(rangeSum>0.0 ? bodySum/rangeSum : 0.0);       // -1..+1

   int run=0;
   for(int i=0;i<n;i++)
     {
      int d=MSign(g_c[i]-g_o[i]);
      if(d==0) break;
      if(i==0){ run=d; continue; }
      if(MSign(run)==d) run+=d; else break;
     }
   double runScore=MClamp((double)run/5.0,-1.0,1.0);

   // displacement: how far price travelled relative to its own noise
   double net=g_c[0]-g_c[MathMin(n,g_bars-1)];
   double disp=(g_view.atr>0.0 ? MClamp(net/(n*g_view.atr)*3.0,-1.0,1.0) : 0.0);

   g_view.momentumScore=100.0*MTanh(1.4*(0.45*dominance+0.30*runScore+0.25*disp));
  }

//--- Order flow: where each bar closed inside its own range, weighted by
//    tick volume. Closing at the highs repeatedly is buyers in control.
void EvaluateFlow(void)
  {
   int n=MathMin(20,g_bars);
   double num=0.0,den=0.0;
   for(int i=0;i<n;i++)
     {
      double rng=g_h[i]-g_l[i];
      if(rng<=0.0) continue;
      double clv=((g_c[i]-g_l[i])-(g_h[i]-g_c[i]))/rng;
      double w=(double)g_v[i]; if(w<=0.0) w=1.0;
      num+=clv*w; den+=w;
     }
   g_view.flowScore=(den>0.0 ? 100.0*MTanh(2.0*(num/den)) : 0.0);
  }

//--- Liquidity: clusters of equal highs / equal lows are where stops rest.
void EvaluateLiquidity(void)
  {
   double tol=0.15*g_view.atr;
   double px=g_view.bid, reach=3.0*g_view.atr;
   double above=0.0,below=0.0;
   int ns=ArraySize(g_swings);
   for(int i=0;i<ns;i++)
     {
      double p=g_swings[i].price;
      if(p>px && p-px<=reach)      above+=1.0;
      else if(p<px && px-p<=reach) below+=1.0;
     }
   // equal-level clusters count double: more stops stacked at one price
   for(int i=0;i<ns;i++)
      for(int j=i+1;j<ns;j++)
         if(MathAbs(g_swings[i].price-g_swings[j].price)<=tol)
           {
            if(g_swings[i].price>px && g_swings[i].price-px<=reach) above+=0.5;
            if(g_swings[i].price<px && px-g_swings[i].price<=reach) below+=0.5;
           }
   g_view.liquidityScore=100.0*MTanh((below-above)/(below+above+1.0));
  }

//--- §H higher-timeframe structure, again from raw bars only
double HigherTfStructure(const ENUM_TIMEFRAMES tf)
  {
   double hh[],ll[],cc[];
   ArraySetAsSeries(hh,true); ArraySetAsSeries(ll,true); ArraySetAsSeries(cc,true);
   int want=120;
   if(CopyHigh(_Symbol,tf,0,want,hh)<want)  return 0.0;
   if(CopyLow(_Symbol,tf,0,want,ll)<want)   return 0.0;
   if(CopyClose(_Symbol,tf,0,want,cc)<want) return 0.0;

   int k=2,up=0,dn=0;
   double prevH=0.0,prevL=0.0;
   for(int j=want-1-k;j>=k;j--)
     {
      bool sh=true,sl=true;
      for(int m=1;m<=k;m++)
        {
         if(hh[j]<=hh[j+m] || hh[j]<=hh[j-m]) sh=false;
         if(ll[j]>=ll[j+m] || ll[j]>=ll[j-m]) sl=false;
        }
      if(sh){ if(prevH>0.0){ if(hh[j]>prevH) up++; else dn++; } prevH=hh[j]; }
      if(sl){ if(prevL>0.0){ if(ll[j]>prevL) up++; else dn++; } prevL=ll[j]; }
     }
   return 100.0*(double)(up-dn)/(double)(up+dn+1);
  }

void EvaluateMtf(void)
  {
   ENUM_TIMEFRAMES a=PERIOD_M15,b=PERIOD_H1,c=PERIOD_H4;
   if(_Period>=PERIOD_H1){ a=PERIOD_H4; b=PERIOD_D1; c=PERIOD_W1; }
   else if(_Period>=PERIOD_M15){ a=PERIOD_H1; b=PERIOD_H4; c=PERIOD_D1; }
   g_view.mtfScore=MClamp(0.45*HigherTfStructure(a)
                         +0.35*HigherTfStructure(b)
                         +0.20*HigherTfStructure(c),-100.0,100.0);
  }

//====================== CONVICTION & SETUPS =========================

void ComputeConviction(void)
  {
   double raw=g_w[0]*(g_view.structScore/100.0)
             +g_w[1]*(g_view.zoneScore/100.0)
             +g_w[2]*(g_view.momentumScore/100.0)
             +g_w[3]*(g_view.flowScore/100.0)
             +g_w[4]*(g_view.mtfScore/100.0)
             +g_w[5]*(g_view.liquidityScore/100.0);
   g_view.convictionDir=100.0*MTanh(InpConvGain*raw);
   g_view.conviction=MathAbs(g_view.convictionDir);
  }

void PushConv(const double c)
  {
   int w=ArraySize(g_conv); if(w<=0) return;
   g_conv[g_convHead]=c; g_convHead=(g_convHead+1)%w;
   if(g_convCount<w) g_convCount++;
  }
double ConvPercentile(const double c)
  {
   if(g_convCount<=0) return 50.0;
   int below=0;
   for(int i=0;i<g_convCount;i++) if(g_conv[i]<c) below++;
   return 100.0*(double)below/(double)g_convCount;
  }
double DistPct(const double p)
  {
   if(g_convCount<=0) return 0.0;
   double t[]; ArrayResize(t,g_convCount);
   for(int i=0;i<g_convCount;i++) t[i]=g_conv[i];
   ArraySort(t);
   int idx=(int)MClamp(MathRound(p/100.0*(g_convCount-1)),0,g_convCount-1);
   return t[idx];
  }
bool PercentileReady(void){ return (InpUsePercentile && g_convCount>=InpMinSamples); }

double EffectivePercentile(void)
  {
   double p=g_entryPct;
   if(!InpUseWatchdog || g_barsSinceEntry<=InpIdleBarsRelax) return p;
   int steps=1+(g_barsSinceEntry-InpIdleBarsRelax)/MathMax(InpRelaxEveryBars,1);
   return MathMax(p-steps*InpRelaxStepPct,InpRelaxFloorPct);
  }

//--- Identify the actual price-action setup in front of us. This is the part
//    that replaces "an indicator crossed": either price has come back to a
//    zone and rejected it, or structure broke and price retested the break.
void FindSetup(void)
  {
   g_view.setup="none";
   g_view.setupDir=0;

   double rng=g_h[0]-g_l[0];
   double lowerWick=(rng>0.0 ? (MathMin(g_o[0],g_c[0])-g_l[0])/rng : 0.0);
   double upperWick=(rng>0.0 ? (g_h[0]-MathMax(g_o[0],g_c[0]))/rng : 0.0);

   // ---- setup 1: rejection from a fresh zone
   if(InpUseZoneEntry && g_view.activeZoneIdx>=0)
     {
      int zd=g_view.zoneDir;
      bool touched=(g_l[0]<=g_view.zoneTop && g_h[0]>=g_view.zoneBottom) ||
                   (g_l[1]<=g_view.zoneTop && g_h[1]>=g_view.zoneBottom);
      if(touched)
        {
         if(zd>0)                                   // demand: expect a bounce
           {
            bool rejected=(!InpRequireRejection) ||
                          (lowerWick>=InpRejectWickFrac && g_c[0]>g_view.zoneBottom);
            bool structOk=(!InpRequireStructure) || (g_view.structDir>=0) ||
                          (g_view.trendScore>-20.0);
            if(rejected && structOk){ g_view.setup="demand-zone rejection"; g_view.setupDir=1; return; }
           }
         else if(zd<0)                              // supply: expect rejection
           {
            bool rejected=(!InpRequireRejection) ||
                          (upperWick>=InpRejectWickFrac && g_c[0]<g_view.zoneTop);
            bool structOk=(!InpRequireStructure) || (g_view.structDir<=0) ||
                          (g_view.trendScore<20.0);
            if(rejected && structOk){ g_view.setup="supply-zone rejection"; g_view.setupDir=-1; return; }
           }
        }
     }

   // ---- setup 2: retest of a level that structure just broke
   if(InpUseRetestEntry && g_view.brokenLevel>0.0 && g_view.brokenAgeBars<=40)
     {
      double lvl=g_view.brokenLevel;
      double near=0.5*g_view.atr;
      if(g_view.brokenDir>0 && g_l[0]<=lvl+near && g_c[0]>lvl)
        { g_view.setup="bullish BOS retest"; g_view.setupDir=1; return; }
      if(g_view.brokenDir<0 && g_h[0]>=lvl-near && g_c[0]<lvl)
        { g_view.setup="bearish BOS retest"; g_view.setupDir=-1; return; }
     }

   // ---- setup 3: structure break with momentum, no retest offered
   if(g_view.bullBos && g_view.momentumScore>20.0)
     { g_view.setup="bullish break of structure"; g_view.setupDir=1; return; }
   if(g_view.bearBos && g_view.momentumScore<-20.0)
     { g_view.setup="bearish break of structure"; g_view.setupDir=-1; return; }
   if(g_view.bullChoch && g_view.zoneScore>0.0)
     { g_view.setup="bullish change of character"; g_view.setupDir=1; return; }
   if(g_view.bearChoch && g_view.zoneScore<0.0)
     { g_view.setup="bearish change of character"; g_view.setupDir=-1; return; }
  }

//=========================== RISK ENGINE ============================

void RiskUpdate(void)
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int key=dt.year*1000+dt.day_of_year;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(key!=g_dayKey){ g_dayKey=key; g_dayStartEquity=eq; g_breakerLatched=false; }
   if(eq>g_peakEquity) g_peakEquity=eq;
  }

bool CircuitBreaker(void)
  {
   if(g_breakerLatched) return true;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if((g_dayStartEquity-eq)>=g_dayStartEquity*InpDailyLossPct/100.0) g_breakerLatched=true;
   if((g_peakEquity-eq)>=g_peakEquity*InpMaxDDPct/100.0)             g_breakerLatched=true;
   return g_breakerLatched;
  }

double SessionMult(void)
  {
   if(!InpUseSessions) return 1.0;
   MqlDateTime g; TimeToStruct(TimeGMT(),g);
   int h=g.hour;
   if(h>=7 && h<12)  return InpSessLondon;
   if(h>=12 && h<16) return InpSessOverlap;
   if(h>=16 && h<21) return InpSessNewYork;
   if(h>=21)         return InpSessDead;
   return InpSessAsian;
  }

double MinLot(void){ double m=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN); return (m>0.0?m:0.01); }
double LotStep(void){ double s=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP); return (s>0.0?s:0.01); }

double LotForRisk(const double riskAmount,const double slDist)
  {
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0.0 || ts<=0.0 || slDist<=0.0 || riskAmount<=0.0) return 0.0;
   double perLot=slDist/ts*tv;
   return (perLot>0.0 ? riskAmount/perLot : 0.0);
  }
double RiskOfLots(const double lots,const double slDist)
  {
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0.0 || ts<=0.0) return 0.0;
   return slDist/ts*tv*lots;
  }
double NormalizeLots(double lots)
  {
   double step=LotStep(),mn=MinLot(),mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   lots=MathFloor(lots/step+1e-9)*step;
   if(lots<mn) return (InpAllowMinLot ? mn : 0.0);
   if(mx>0.0)  lots=MathMin(lots,mx);
   return lots;
  }
bool MarginOK(const int dir,const double lots)
  {
   MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return false;
   double m=0.0;
   if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,lots,
                       (dir>0?t.ask:t.bid),m)) return false;
   return AccountInfoDouble(ACCOUNT_MARGIN_FREE)>=m*InpMarginSafety;
  }
//--- The widest stop this account can carry at the broker minimum lot while
//    staying inside the hard risk ceiling. On a small account trading a large
//    contract this is the binding constraint on everything: not the signal,
//    not the spread, but how far the stop can be from entry.
double AffordableStopDistance(void)
  {
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double cap=eq*InpMaxRiskPctHard/100.0;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double lot=MinLot();
   if(tv<=0.0 || ts<=0.0 || lot<=0.0) return 0.0;
   return cap/(tv/ts*lot);
  }

double MaxSpreadPts(void)
  {
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double byAtr=(pt>0.0 && g_view.atr>0.0 ? InpMaxSpreadAtr*(g_view.atr/pt) : 0.0);
   return MathMax(byAtr,MathMax(InpMinSpreadPts,1.0));
  }

//========================= TRADE PLUMBING ===========================

ENUM_ORDER_TYPE_FILLING Filling(void)
  {
   long f=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((f&SYMBOL_FILLING_FOK)!=0) return ORDER_FILLING_FOK;
   if((f&SYMBOL_FILLING_IOC)!=0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }
bool Send(MqlTradeRequest &req,MqlTradeResult &res)
  {
   if(!OrderSend(req,res)) return false;
   return (res.retcode==TRADE_RETCODE_DONE || res.retcode==TRADE_RETCODE_DONE_PARTIAL ||
           res.retcode==TRADE_RETCODE_PLACED);
  }

void GetBasket(SBasket &b)
  {
   b.count=0; b.totalVolume=0.0; b.avgEntry=0.0; b.floatPL=0.0; b.dir=0;
   b.firstEntryTime=0; b.lastEntryTime=0; b.lastEntryPrice=0.0; b.firstEntryVolume=0.0;
   double pv=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double op=PositionGetDouble(POSITION_PRICE_OPEN);
      datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
      b.count++; b.totalVolume+=vol; pv+=vol*op;
      b.floatPL+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      b.dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);
      if(b.firstEntryTime==0 || ot<b.firstEntryTime){ b.firstEntryTime=ot; b.firstEntryVolume=vol; }
      if(ot>=b.lastEntryTime){ b.lastEntryTime=ot; b.lastEntryPrice=op; }
     }
   if(b.totalVolume>0.0) b.avgEntry=pv/b.totalVolume;
  }

bool TicketSeen(const ulong &a[],const ulong t)
  { for(int i=ArraySize(a)-1;i>=0;i--) if(a[i]==t) return true; return false; }
void TicketMark(ulong &a[],const ulong t)
  { int n=ArraySize(a); ArrayResize(a,n+1); a[n]=t; }

bool ClosePartial(const ulong ticket,const double volume)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   string sym=PositionGetString(POSITION_SYMBOL);
   long tp=PositionGetInteger(POSITION_TYPE);
   MqlTick t; if(!SymbolInfoTick(sym,t)) return false;
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action=TRADE_ACTION_DEAL; req.symbol=sym; req.volume=volume; req.position=ticket;
   req.type=(tp==POSITION_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY);
   req.price=(tp==POSITION_TYPE_BUY?t.bid:t.ask);
   req.deviation=(ulong)InpDeviationPts; req.magic=(ulong)InpMagic; req.type_filling=Filling();
   return Send(req,res);
  }
bool CloseTicket(const ulong t)
  {
   if(!PositionSelectByTicket(t)) return false;
   return ClosePartial(t,PositionGetDouble(POSITION_VOLUME));
  }
bool ModifySL(const ulong t,const double sl,const double tp)
  {
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action=TRADE_ACTION_SLTP; req.symbol=_Symbol; req.position=t; req.sl=sl; req.tp=tp;
   return Send(req,res);
  }
void CloseAll(const string reason)
  {
   bool any=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      CloseTicket(tk); any=true;
     }
   if(any) LogEvent("closed: "+reason);
  }
double RiskUsed(const bool thisSymbolOnly)
  {
   double used=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      string ps=PositionGetString(POSITION_SYMBOL);
      if(thisSymbolOnly && ps!=_Symbol) continue;
      double sl=PositionGetDouble(POSITION_SL);
      double op=PositionGetDouble(POSITION_PRICE_OPEN);
      double vol=PositionGetDouble(POSITION_VOLUME);
      if(sl>0.0)
        {
         double tv=SymbolInfoDouble(ps,SYMBOL_TRADE_TICK_VALUE);
         double ts=SymbolInfoDouble(ps,SYMBOL_TRADE_TICK_SIZE);
         if(tv>0.0 && ts>0.0) used+=MathAbs(op-sl)/ts*tv*vol;
        }
      else used+=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPct/100.0;
     }
   return used;
  }

//============================== ENTRY ===============================

//--- Stops go where price action says they belong: beyond the zone that
//    produced the setup, or beyond the swing that structure just made.
//    ATR is only the buffer, never the location.
void PlanStop(const int dir,const double entry,double &sl,double &tp)
  {
   double buf=InpSlAtrMult*g_view.atr;
   double anchor=0.0;
   if(g_view.activeZoneIdx>=0 && g_view.zoneDir==dir)
      anchor=(dir>0 ? g_view.zoneBottom : g_view.zoneTop);
   else if(dir>0 && g_view.lastSwingLow>0.0)  anchor=g_view.lastSwingLow;
   else if(dir<0 && g_view.lastSwingHigh>0.0) anchor=g_view.lastSwingHigh;
   else anchor=(dir>0 ? entry-2.0*g_view.atr : entry+2.0*g_view.atr);

   sl=(dir>0 ? anchor-buf : anchor+buf);
   double risk=MathAbs(entry-sl);
   if(risk<0.5*g_view.atr)                       // never let the stop be trivial
     {
      risk=0.5*g_view.atr;
      sl=(dir>0 ? entry-risk : entry+risk);
     }
   tp=(dir>0 ? entry+InpTpRMultiple*risk : entry-InpTpRMultiple*risk);
  }

void TryEnter(const int dir,const SBasket &b)
  {
   if(InpEntryCooldownSec>0 && g_lastEntryTime>0 &&
      (TimeCurrent()-g_lastEntryTime)<InpEntryCooldownSec)
     { Block("entry cooldown"); return; }

   double sprLimit=MaxSpreadPts();
   if(g_view.spreadPts>sprLimit)
     { Block(StringFormat("spread %.0f pts over limit %.0f",g_view.spreadPts,sprLimit)); return; }

   MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return;
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double stops=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*pt;
   double entry=(dir>0?t.ask:t.bid);

   double sl,tp;
   PlanStop(dir,entry,sl,tp);
   // respect the broker's minimum stop distance
   if(dir>0){ if(entry-sl<stops+pt) sl=entry-(stops+pt); if(tp-entry<stops+pt) tp=entry+(stops+pt); }
   else     { if(sl-entry<stops+pt) sl=entry+(stops+pt); if(entry-tp<stops+pt) tp=entry-(stops+pt); }
   sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);

   double slDist=MathAbs(entry-sl);
   if(slDist<=0.0){ Block("stop distance resolved to zero"); return; }

   // Reconcile the structural stop with what the account can actually carry.
   double afford=AffordableStopDistance();
   if(afford>0.0 && slDist>afford)
     {
      if(InpFitStopToAccount)
        {
         // The stop is moved from where price action says the idea fails to
         // where the account can afford it. This is a real degradation: the
         // trade can now be stopped out while the setup is still valid, so
         // expect a lower win rate. It is enabled deliberately, not silently.
         double old=slDist;
         slDist=afford;
         sl=NormalizeDouble(dir>0 ? entry-slDist : entry+slDist,digits);
         tp=NormalizeDouble(dir>0 ? entry+InpTpRMultiple*slDist
                                  : entry-InpTpRMultiple*slDist,digits);
         LogEvent(StringFormat("stop tightened to fit account: %.5f -> %.5f "
                               "(structural level was %.1fx further away)",
                               old,slDist,old/MathMax(slDist,1e-9)));
        }
      else if(InpSkipUnaffordable)
        {
         Block(StringFormat("%s: stop needs %.2f but account can only carry %.2f "
                            "at min lot — deposit ~%.0f to trade this setup, or enable "
                            "InpFitStopToAccount",
                            g_view.setup,slDist,afford,
                            RiskOfLots(MinLot(),slDist)/(InpMaxRiskPctHard/100.0)));
         return;
        }
     }

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double plannedRisk=eq*InpRiskPct/100.0*SessionMult();
   double lots=NormalizeLots(LotForRisk(plannedRisk,slDist));
   if(lots<=0.0){ Block(StringFormat("size below broker minimum %.2f",MinLot())); return; }

   // R is measured against the risk actually carried, never the plan
   double realRisk=RiskOfLots(lots,slDist);
   double hardCap=eq*InpMaxRiskPctHard/100.0;
   if(realRisk>hardCap)
     {
      Block(StringFormat("risk %.2f = %.0f%% of equity over %.0f%% ceiling — "
                         "min lot too large for this account (need ~%.0f deposit)",
                         realRisk,100.0*realRisk/MathMax(eq,0.01),InpMaxRiskPctHard,
                         realRisk/(InpMaxRiskPctHard/100.0)));
      return;
     }
   bool atMin=(MathAbs(lots-MinLot())<1e-9);
   if(RiskUsed(true)+realRisk>eq*InpMaxBasketRiskPct/100.0 &&
      !(atMin && b.count==0 && InpMinLotOverride))
     { Block("basket risk cap reached"); return; }
   if(RiskUsed(false)+realRisk>eq*InpMaxAccountRiskPct/100.0 &&
      !(atMin && InpMinLotOverride && RiskUsed(false)<=0.0))
     { Block("account risk cap reached"); return; }
   if(!MarginOK(dir,lots)){ Block(StringFormat("not enough free margin for %.2f lots",lots)); return; }

   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=lots;
   req.type=(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   req.price=entry; req.sl=sl; req.tp=tp;
   req.deviation=(ulong)InpDeviationPts; req.magic=(ulong)InpMagic;
   req.comment="MedulaPA"; req.type_filling=Filling();

   if(!Send(req,res))
     {
      LogEvent(StringFormat("ORDER REJECTED: %s %.2f retcode=%u (%s)",
                            dir>0?"BUY":"SELL",lots,res.retcode,res.comment));
      Block(StringFormat("broker rejected order, retcode %u",res.retcode));
      return;
     }

   g_entryConviction=g_view.conviction;
   g_initialRiskAmt=realRisk;
   g_initialLot=lots;
   g_entryZoneTop=g_view.zoneTop;
   g_entryZoneBottom=g_view.zoneBottom;
   g_lastEntryTime=TimeCurrent();
   g_barsSinceEntry=0;
   g_entries++;
   if(realRisk>eq*InpMaxBasketRiskPct/100.0)
      LogEvent(StringFormat("min-lot override: risking %.2f (%.1f%% of equity), ceiling %.0f%%",
                            realRisk,100.0*realRisk/MathMax(eq,0.01),InpMaxRiskPctHard));
   LogTrade(dir>0?"BUY":"SELL",lots,res.price,sl,tp,
            StringFormat("%s | struct=%.0f zone=%.0f mom=%.0f flow=%.0f mtf=%.0f conv=%.0f pct=%.0f risk=%.2f",
                         g_view.setup,g_view.structScore,g_view.zoneScore,g_view.momentumScore,
                         g_view.flowScore,g_view.mtfScore,g_view.conviction,
                         g_view.convPercentile,realRisk));
   g_block="—";
  }

//=============================== EXITS ==============================

void ManageOpen(const SBasket &b)
  {
   if(b.count==0 || g_initialRiskAmt<=0.0) return;
   double rMult=b.floatPL/g_initialRiskAmt;
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double stops=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*pt;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double op =PositionGetDouble(POSITION_PRICE_OPEN);
      double sl =PositionGetDouble(POSITION_SL);
      double tp =PositionGetDouble(POSITION_TP);
      int pd=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);

      if(InpUsePartialTP && rMult>=InpPartialAtR && !TicketSeen(g_partialDone,tk))
        {
         double step=LotStep();
         double part=MathFloor(vol*InpPartialPct/100.0/step+1e-9)*step;
         if(part>=MinLot() && (vol-part)>=MinLot())
           {
            if(ClosePartial(tk,part))
              { TicketMark(g_partialDone,tk); LogEvent(StringFormat("partial close %.2f at %.2fR",part,rMult)); }
           }
         else TicketMark(g_partialDone,tk);
        }

      if(InpUseBreakEven && rMult>=InpBreakEvenAtR && !TicketSeen(g_beDone,tk))
        {
         double be=NormalizeDouble(op+pd*InpBreakEvenBuf*g_view.atr,digits);
         bool better=(pd>0 ? (sl<=0.0 || be>sl+pt) : (sl<=0.0 || be<sl-pt));
         bool legal =(pd>0 ? be<g_view.bid-stops : be>g_view.ask+stops);
         if(better && legal && ModifySL(tk,be,tp))
           { TicketMark(g_beDone,tk); LogEvent(StringFormat("break-even at %.2fR",rMult)); }
        }

      // trail behind the most recent swing, which is where price action says
      // the trade would actually be wrong
      if(InpUseTrail && rMult>=InpBreakEvenAtR)
        {
         double anchor=(pd>0 ? g_view.lastSwingLow : g_view.lastSwingHigh);
         if(anchor>0.0)
           {
            double ns=NormalizeDouble(anchor-pd*InpTrailAtrMult*g_view.atr,digits);
            bool better=(pd>0 ? (sl<=0.0 || ns>sl+pt) : (sl<=0.0 || ns<sl-pt));
            bool legal =(pd>0 ? ns<g_view.bid-stops : ns>g_view.ask+stops);
            if(better && legal) ModifySL(tk,ns,tp);
           }
        }
     }

   if(InpExitOnOppZone && g_view.activeZoneIdx>=0 && g_view.zoneDir==-b.dir && rMult>0.3)
     { CloseAll("reached opposing zone"); return; }

   if((b.dir>0 && g_view.bearChoch) || (b.dir<0 && g_view.bullChoch))
     { CloseAll("structure flipped against the trade"); return; }

   int barsIn=(int)((TimeCurrent()-b.firstEntryTime)/MathMax(PeriodSeconds(PERIOD_CURRENT),1));
   if(barsIn>InpMaxBarsInTrade && b.floatPL<0.0)
     { CloseAll(StringFormat("time stop after %d bars",barsIn)); return; }
  }

//========================== ANALYSIS PASS ===========================

bool Analyse(void)
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t)){ Block("no tick data"); return false; }
   if(!LoadBars()) return false;

   g_view.bid=t.bid; g_view.ask=t.ask;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   g_view.spreadPts=(pt>0.0 ? (t.ask-t.bid)/pt : 0.0);

   g_view.atr=AverageTrueRange((int)InpAtrPeriod,0);
   if(g_view.atr<=0.0){ Block("true range is zero (no price movement yet)"); return false; }

   BuildStructure();      // §A + §C
   BuildZones();          // §B
   EvaluateZones();       // §B
   EvaluateMomentum();    // §D
   EvaluateFlow();        // §G
   EvaluateLiquidity();   // §F
   EvaluateMtf();         // §H
   ComputeConviction();
   FindSetup();
   return true;
  }

ENUM_DECISION Decide(const bool inTrade,const int basketDir)
  {
   if(!inTrade)
     {
      if(g_view.setupDir==0){ Block("no price-action setup present"); return DEC_WAIT; }
      if(g_view.conviction<InpMinAbsConviction)
        {
         Block(StringFormat("%s but conviction %.1f below floor %.1f",
                            g_view.setup,g_view.conviction,InpMinAbsConviction));
         return DEC_WAIT;
        }
      // the setup and the weight of evidence must point the same way
      if(MSign(g_view.convictionDir)!=g_view.setupDir && g_view.conviction>25.0)
        {
         Block(StringFormat("%s conflicts with overall evidence (%.0f)",
                            g_view.setup,g_view.convictionDir));
         return DEC_WAIT;
        }
      if(PercentileReady())
        {
         if(g_view.convPercentile<g_effPct)
           {
            Block(StringFormat("%s ranks %.0f pct, needs %.0f (idle %d bars)",
                               g_view.setup,g_view.convPercentile,g_effPct,g_barsSinceEntry));
            return DEC_WAIT;
           }
        }
      else if(g_view.conviction<InpBootstrapConv)
        {
         Block(StringFormat("warming up (%d/%d bars), conviction %.1f < %.1f",
                            g_convCount,InpMinSamples,g_view.conviction,InpBootstrapConv));
         return DEC_WAIT;
        }
      return (g_view.setupDir>0 ? DEC_BUY : DEC_SELL);
     }

   if(g_view.conviction<InpExitConvFraction*g_entryConviction &&
      MSign(g_view.convictionDir)!=basketDir)
      return DEC_EXIT;
   return DEC_HOLD;
  }

//======================== SELF-TEST & PANEL =========================

void SelfTest(void)
  {
   if(!InpSelfTest) return;
   LogEvent("──────── PRICE-ACTION SELF-TEST ────────");
   LogEvent(StringFormat("symbol %s  timeframe %s  bars loaded %d  (NO INDICATORS IN USE)",
                         _Symbol,EnumToString(_Period),g_bars));
   LogEvent(StringFormat("ATR from true range: %.5f (%.0f points)",
                         g_view.atr,
                         (SymbolInfoDouble(_Symbol,SYMBOL_POINT)>0.0
                          ? g_view.atr/SymbolInfoDouble(_Symbol,SYMBOL_POINT):0.0)));
   int alive=0; for(int i=0;i<ArraySize(g_zones);i++) if(g_zones[i].alive) alive++;
   LogEvent(StringFormat("supply/demand zones found: %d (%d still live), swings: %d",
                         ArraySize(g_zones),alive,ArraySize(g_swings)));
   LogEvent(StringFormat("structure: dir %d  trend score %.0f  last swing high %.5f  low %.5f",
                         g_view.structDir,g_view.trendScore,g_view.lastSwingHigh,g_view.lastSwingLow));
   LogEvent(StringFormat("broker: min lot %.2f  contract %.0f  digits %d  stops level %d  spread %.0f/%.0f pts",
                         MinLot(),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),
                         (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS),
                         (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                         g_view.spreadPts,MaxSpreadPts()));

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double slDist=2.0*g_view.atr;                       // representative stop
   double minRisk=RiskOfLots(MinLot(),slDist);
   LogEvent(StringFormat("account: equity %.2f  leverage 1:%d  algo trading %s",
                         eq,(int)AccountInfoInteger(ACCOUNT_LEVERAGE),
                         (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"ENABLED":"DISABLED")));
   if(minRisk>0.0)
     {
      LogEvent(StringFormat("one min-lot stop-out costs about %.2f = %.0f%% of equity",
                            minRisk,100.0*minRisk/MathMax(eq,0.01)));
      LogEvent(StringFormat("minimum viable deposit here: %.0f (under the %.0f%% ceiling), "
                            "%.0f (to honour the %.1f%% plan)",
                            minRisk/(InpMaxRiskPctHard/100.0),InpMaxRiskPctHard,
                            minRisk/(InpRiskPct/100.0),InpRiskPct));
      double afford=AffordableStopDistance();
      LogEvent(StringFormat("widest stop this account can carry at min lot: %.5f (%.2f x ATR)",
                            afford,(g_view.atr>0.0 ? afford/g_view.atr : 0.0)));
      if(afford<1.0*g_view.atr)
         LogEvent(StringFormat("NOTE: that is under 1 ATR — most structural stops will be too wide. "
                               "Either deposit ~%.0f, or set InpFitStopToAccount=true to trade with "
                               "stops placed by affordability instead of by structure.",
                               RiskOfLots(MinLot(),2.0*g_view.atr)/(InpMaxRiskPctHard/100.0)));
      if(minRisk>eq*InpMaxRiskPctHard/100.0)
         LogEvent("*** BLOCKING: one minimum-lot stop-out exceeds the hard risk ceiling on this "
                  "equity. The broker minimum is too large for this account on this symbol — "
                  "no setting can fix that. Increase the deposit or trade a smaller contract. ***");
     }
   LogEvent("────────────────────────────────────────");
  }

void Panel(const SBasket &b)
  {
   if(!InpShowPanel) return;
   int alive=0; for(int i=0;i<ArraySize(g_zones);i++) if(g_zones[i].alive) alive++;
   string zoneTxt="none nearby";
   if(g_view.activeZoneIdx>=0)
      zoneTxt=StringFormat("%s  %.5f-%.5f  str %.1f  tests %d",
                           (g_view.zoneDir>0?"DEMAND":"SUPPLY"),
                           g_view.zoneBottom,g_view.zoneTop,g_view.zoneStrength,g_view.zoneTests);
   string mode=(PercentileReady()
                ? StringFormat("rank>=%.0f%s",g_effPct,(g_effPct<g_entryPct-0.01?" (relaxed)":""))
                : StringFormat("warmup %d/%d",g_convCount,InpMinSamples));
   Comment(StringFormat(
      "MEDULA v3.10  PRICE ACTION  |  %s %s\n"
      "no indicators — structure, zones and candles only\n"
      "──────────────────────────────────────\n"
      "structure   %+6.0f   dir %+d\n"
      "zones       %+6.0f   %d live\n"
      "momentum    %+6.0f   flow %+6.0f\n"
      "MTF struct  %+6.0f   liquidity %+6.0f\n"
      "──────────────────────────────────────\n"
      "SETUP       %s\n"
      "active zone %s\n"
      "CONVICTION  %6.1f  %s   rank %3.0f pct\n"
      "gate        %s\n"
      "──────────────────────────────────────\n"
      "ATR %.5f   spread %.0f/%.0f pts\n"
      "positions %d  floating %.2f  R %.2f\n"
      "entries %d   idle %d bars\n"
      "status  %s",
      _Symbol,EnumToString(_Period),
      g_view.structScore,g_view.structDir,
      g_view.zoneScore,alive,
      g_view.momentumScore,g_view.flowScore,
      g_view.mtfScore,g_view.liquidityScore,
      g_view.setup,zoneTxt,
      g_view.conviction,(MSign(g_view.convictionDir)>0?"LONG":(MSign(g_view.convictionDir)<0?"SHORT":"flat")),
      g_view.convPercentile,mode,
      g_view.atr,g_view.spreadPts,MaxSpreadPts(),
      b.count,b.floatPL,(g_initialRiskAmt>0.0?b.floatPL/g_initialRiskAmt:0.0),
      g_entries,g_barsSinceEntry,g_block));
  }

//========================== EVENT HANDLERS ==========================

int OnInit(void)
  {
   double ws=InpWStructure+InpWZone+InpWMomentum+InpWFlow+InpWMtf+InpWLiquidity;
   if(ws<=0.0) ws=1.0;
   g_w[0]=InpWStructure/ws; g_w[1]=InpWZone/ws; g_w[2]=InpWMomentum/ws;
   g_w[3]=InpWFlow/ws;      g_w[4]=InpWMtf/ws;  g_w[5]=InpWLiquidity/ws;

   LogInit();

   int cs=MathMax(InpConfSampleSize,20);
   ArrayResize(g_conv,cs); ArrayInitialize(g_conv,0.0);
   g_convHead=0; g_convCount=0;
   g_entryPct=InpEntryPercentile; g_effPct=g_entryPct;
   g_barsSinceEntry=0;
   ArrayResize(g_partialDone,0); ArrayResize(g_beDone,0);

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEquity=eq; g_peakEquity=eq; g_dayKey=-1;
   g_breakerLatched=false;
   RiskUpdate();

   g_lastBar=0; g_lastEntryTime=0; g_entries=0;
   g_block="warming up"; g_haveView=false;

   if(Analyse())
     {
      g_haveView=true;
      // seed the conviction distribution from the bars already on the chart so
      // the ranking is meaningful from the first tick rather than hours later
      int seeded=0;
      for(int s=MathMin(g_bars-1,InpConfSampleSize);s>=1;s--)
        {
         int n=MathMin(10,g_bars-s-1);
         if(n<3) continue;
         double bodySum=0.0,rangeSum=0.0;
         for(int i=0;i<n;i++)
           {
            double rng=g_h[s+i]-g_l[s+i];
            if(rng<=0.0) continue;
            bodySum+=(g_c[s+i]-g_o[s+i]); rangeSum+=rng;
           }
         double dom=(rangeSum>0.0?bodySum/rangeSum:0.0);
         double fnum=0.0,fden=0.0;
         for(int i=0;i<MathMin(20,g_bars-s);i++)
           {
            double rng=g_h[s+i]-g_l[s+i];
            if(rng<=0.0) continue;
            double clv=((g_c[s+i]-g_l[s+i])-(g_h[s+i]-g_c[s+i]))/rng;
            double w=(double)g_v[s+i]; if(w<=0.0) w=1.0;
            fnum+=clv*w; fden+=w;
           }
         double flow=(fden>0.0?100.0*MTanh(2.0*(fnum/fden)):0.0);
         double mom =100.0*MTanh(1.4*0.75*dom);
         double raw =g_w[0]*(g_view.structScore/100.0)+g_w[1]*(g_view.zoneScore/100.0)
                    +g_w[2]*(mom/100.0)+g_w[3]*(flow/100.0)
                    +g_w[4]*(g_view.mtfScore/100.0)+g_w[5]*(g_view.liquidityScore/100.0);
         PushConv(MathAbs(100.0*MTanh(InpConvGain*raw)));
         seeded++;
        }
      if(seeded>0) LogEvent(StringFormat("conviction distribution seeded from %d bars",seeded));
     }

   SelfTest();
   LogEvent(StringFormat("v3.10 price-action mode ready — entry at rank %.0f pct, floor %.1f",
                         g_entryPct,InpMinAbsConviction));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Comment("");
   LogEvent(StringFormat("stopped (reason %d) — entries this run: %d",reason,g_entries));
   LogClose();
  }

void OnTick(void)
  {
   RiskUpdate();

   SBasket b; GetBasket(b);
   if(b.count==0)
     {
      g_entryConviction=0.0; g_initialRiskAmt=0.0; g_initialLot=0.0;
      ArrayResize(g_partialDone,0); ArrayResize(g_beDone,0);
     }

   if(CircuitBreaker())
     {
      if(b.count>0) CloseAll("risk circuit breaker");
      if(!g_breakerLogged){ LogEvent("CIRCUIT BREAKER ACTIVE — trading suspended"); g_breakerLogged=true; }
      g_block="circuit breaker latched";
      Panel(b);
      return;
     }
   g_breakerLogged=false;

   datetime cur=iTime(_Symbol,_Period,0);
   bool newBar=(cur!=g_lastBar && cur>0);
   if(newBar){ g_lastBar=cur; g_barsSinceEntry++; }

   if(!Analyse()){ Panel(b); return; }
   g_haveView=true;

   if(newBar) PushConv(g_view.conviction);
   g_view.convPercentile=ConvPercentile(g_view.conviction);
   g_effPct=EffectivePercentile();

   if(b.count>0)
     {
      ManageOpen(b);
      GetBasket(b);
     }

   ENUM_DECISION d=Decide(b.count>0,b.dir);
   if(d==DEC_EXIT)
     {
      CloseAll("conviction collapsed against the position");
      LogTrade("EXIT",0.0,0.0,0.0,0.0,"conviction collapsed");
     }
   else if(d==DEC_BUY)  TryEnter(1,b);
   else if(d==DEC_SELL) TryEnter(-1,b);
   else if(d==DEC_HOLD) g_block="holding position";

   Panel(b);
  }
//+------------------------------------------------------------------+
