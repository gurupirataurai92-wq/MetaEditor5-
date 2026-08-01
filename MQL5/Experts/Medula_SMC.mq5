//+------------------------------------------------------------------+
//|                                                   Medula_SMC.mq5 |
//|  Medula v4.00 — Smart Money Concepts / ICT.  M5 execution.       |
//|  Single file, zero includes, ZERO INDICATORS.                    |
//|                                                                  |
//|  Every decision comes from raw OHLC. There is no iRSI / iMACD /  |
//|  iADX / iBands / iMA / iATR handle and no CopyBuffer call in     |
//|  this file. The only market data read is CopyHigh, CopyLow,      |
//|  CopyOpen, CopyClose, CopyTime and CopyTickVolume.               |
//|                                                                  |
//|  ENGINES                                                         |
//|    §1  Market structure   swings, BOS, CHoCH, MSS                |
//|    §2  Order blocks       last opposing candle before            |
//|                           displacement that breaks structure     |
//|    §3  Fair value gaps    three-candle imbalance, fill tracking  |
//|    §4  Liquidity          EQH/EQL pools, session and prior-day   |
//|                           highs and lows, sweep detection        |
//|    §5  Premium / discount dealing range, equilibrium, OTE        |
//|    §6  Killzones          London, New York, London close (GMT)   |
//|    §7  HTF bias           structure on M15 / H1 / H4             |
//|    §8  Displacement       impulsive legs that leave imbalance    |
//|    §9  Basket manager     average entry, basket targets, scaling |
//|                                                                  |
//|  THE ENTRY MODEL (all conditions, in order)                      |
//|    1. Higher timeframe bias agrees                               |
//|    2. Liquidity is swept — a prior low/high is taken and         |
//|       rejected (stop hunt / turtle soup)                         |
//|    3. Market structure shifts against the sweep (CHoCH / BOS)    |
//|    4. That shift was displacement — it left an FVG or order block|
//|    5. Price returns into the FVG or order block                  |
//|    6. The entry sits in discount (longs) or premium (shorts)     |
//|    7. Optionally inside an ICT killzone                          |
//|  Stop goes beyond the sweep extreme. Target is the opposing      |
//|  liquidity pool, or an R multiple if none is in range.           |
//+------------------------------------------------------------------+
#property copyright "Medula Project"
#property version   "4.10"

//============================== INPUTS ==============================

input group "General"
input long   InpMagic           = 770040;  // Magic number
input int    InpDeviationPts    = 30;      // Max price deviation (points)
input bool   InpVerboseLog      = true;    // Print to Experts log
input bool   InpCsvLog          = true;    // Write MedulaSMC.csv
input bool   InpShowPanel       = true;    // Live panel on chart
input bool   InpDrawObjects     = true;    // Draw zones on the chart
input bool   InpDiagnostics     = true;    // Log why an entry was skipped
input int    InpDiagThrottleSec = 900;     // Seconds between repeats of a reason
input bool   InpSelfTest        = true;    // Readiness report on attach

input group "Market Structure (§1)"
input int    InpBars            = 500;     // Bars of M5 history analysed
input int    InpSwingK          = 2;       // Fractal wing size
input double InpBosBufferPct    = 0.05;    // Break must clear by this share of avg range
input int    InpStructureLookback = 60;    // Bars searched for the structure shift

input group "Order Blocks (§2)"
input bool   InpUseOrderBlocks  = true;    // Trade order-block returns
input int    InpMaxOrderBlocks  = 20;      // Order blocks tracked per side
input int    InpObMaxAgeBars    = 300;     // Forget order blocks older than this
input double InpObMitigatedPct  = 50.0;    // Mitigated once price fills this % of it
input bool   InpUseBreakers     = true;    // Trade breaker blocks (failed OB that flips)

input group "Fair Value Gaps (§3)"
input bool   InpUseFVG          = true;    // Trade FVG returns
input int    InpMaxFVGs         = 20;      // FVGs tracked
input int    InpFvgMaxAgeBars   = 200;     // Forget FVGs older than this
input double InpFvgMinPct       = 0.25;    // Gap must be >= this share of avg range
input double InpFvgFillPct      = 50.0;    // Consumed once price fills this % (CE)

input group "Liquidity (§4)"
input double InpEqualTolPct     = 0.12;    // Equal-level tolerance (share of avg range)
input int    InpLiqLookback     = 200;     // Bars scanned for liquidity pools
input bool   InpRequireSweep    = false;   // Demand a liquidity sweep before entry
input int    InpSweepMaxAgeBars = 30;      // Sweep must be this recent
input bool   InpUsePrevDayLevels= true;    // Include previous day high/low as liquidity

input group "Premium / Discount (§5)"
input bool   InpUsePremiumDiscount = false;// Buy only in discount, sell only in premium
input int    InpDealingRangeBars   = 120;  // Bars forming the dealing range
input double InpOteLow              = 0.62; // OTE zone lower retracement
input double InpOteHigh             = 0.79; // OTE zone upper retracement
input bool   InpRequireOte          = false;// Demand entry inside the OTE window

input group "Killzones (§6, GMT)"
input bool   InpUseKillzones    = false;   // Trade only in ICT killzones
input int    InpLondonStart     = 7;       // London open killzone start hour
input int    InpLondonEnd       = 10;      // London open killzone end hour
input int    InpNyStart         = 12;      // New York open killzone start hour
input int    InpNyEnd           = 15;      // New York open killzone end hour
input int    InpLnCloseStart    = 15;      // London close killzone start hour
input int    InpLnCloseEnd      = 17;      // London close killzone end hour

input group "Higher Timeframe Bias (§7)"
input bool   InpUseHtfBias      = true;    // Require higher-timeframe agreement
input bool   InpHtfM15          = true;    // Include M15 structure
input bool   InpHtfH1           = true;    // Include H1 structure
input bool   InpHtfH4           = true;    // Include H4 structure
input double InpHtfMinAgreement = 0.12;    // Minimum weighted agreement (-1..+1)

input group "Displacement (§8)"
input double InpDisplacementMult = 1.5;    // Leg range >= this x average range
input double InpDisplacementBody = 0.50;   // Body must be this share of the leg

input group "Scalp Mode"
input bool   InpScalpMode       = true;    // Scalper profile: POI stops, quick targets
input bool   InpStopBeyondPOI   = true;    // Stop just past the FVG/OB, not past the sweep
input double InpPoiStopBuffer   = 0.30;    // Stop beyond the POI by this x average range
input double InpScalpTargetR    = 1.6;     // Scalp target in R
input int    InpMaxHoldBars     = 24;      // Close a scalp after this many M5 bars

input group "Entries"
input bool   InpEntryOnFVG      = true;    // Enter on FVG return
input bool   InpEntryOnOB       = true;    // Enter on order-block return
input double InpEntryZoneBuffer = 0.10;    // Zone widened by this share of avg range
input int    InpEntryCooldownSec= 120;     // Min seconds between entries
input int    InpMaxSetupAgeBars = 40;      // Setup must trigger within this many bars

input group "Risk"
input double InpRiskPct         = 1.0;     // Risk per trade (% equity)
input double InpSlBufferPct     = 0.25;    // Stop beyond the sweep by this x avg range
input double InpMinRR           = 1.5;     // Minimum reward:risk to accept a setup
input double InpTpRMultiple     = 3.0;     // Target when no liquidity pool is in range
input double InpDailyLossPct    = 5.0;     // Daily loss limit (%)
input double InpMaxDDPct        = 20.0;    // Max drawdown from peak (%)
input double InpMaxRiskPctHard  = 20.0;    // ABSOLUTE ceiling on one trade (% equity)
input double InpMarginSafety    = 1.2;     // Free-margin safety factor
input bool   InpAllowMinLot     = true;    // Round up to broker minimum lot
input bool   InpFitStopToAccount= true;    // Tighten stop so min lot fits the ceiling

input group "Basket Manager (§9)"
input bool   InpUseBasket       = true;    // Manage positions as one basket
input int    InpMaxBasketTrades = 4;       // Max positions in a basket
input double InpBasketTargetR   = 1.6;     // Close the basket at this R
input double InpBasketStopR     = 1.5;     // Close the basket at this loss in R
input double InpMaxBasketRiskPct= 4.0;     // Max combined basket risk (% equity)
input bool   InpBasketBreakEven = true;    // Move basket to break-even in profit
input double InpBasketBeAtR     = 0.5;     // Break-even trigger (R)
input bool   InpBasketPartial   = true;    // Partial close at the first target
input double InpBasketPartialR  = 0.6;     // Partial trigger (R)
input double InpBasketPartialPct= 50.0;    // Percent of volume closed
input bool   InpAllowScaleIn    = true;    // Add on a fresh confirmation
input double InpScaleDecay      = 0.6;     // Lot decay per add
input double InpScaleMinSpacing = 0.75;    // Min spacing between adds (x avg range)
input bool   InpCloseOnFlip     = true;    // Close basket when HTF bias flips

//========================= TYPES & HELPERS ==========================

enum ENUM_DEC { DEC_WAIT=0, DEC_BUY, DEC_SELL, DEC_HOLD, DEC_EXIT };

double MClamp(const double x,const double lo,const double hi){ return MathMin(MathMax(x,lo),hi); }
int    MSign(const double x){ if(x>0.0) return 1; if(x<0.0) return -1; return 0; }

//--- an order block: the last opposing candle before displacement (§2)
struct SOB
  {
   double            top,bottom;
   int               dir;          // +1 bullish OB (demand), -1 bearish OB (supply)
   int               shift;
   double            strength;     // displacement size in average-range units
   bool              mitigated;
   bool              breaker;      // flipped after failing
   bool              alive;
  };

//--- a fair value gap: three-candle imbalance (§3)
struct SFVG
  {
   double            top,bottom;
   int               dir;          // +1 bullish gap, -1 bearish gap
   int               shift;
   bool              filled;
   bool              alive;
  };

//--- a resting liquidity pool (§4)
struct SLIQ
  {
   double            price;
   int               side;         // +1 buyside (highs), -1 sellside (lows)
   int               touches;
   int               shift;
   bool              swept;
   bool              alive;
  };

//--- everything the engines see this bar
struct SView
  {
   double            avgRange;     // mean true range, a distance unit only
   double            bid,ask,spreadPts;
   // §1 structure
   int               structDir;
   bool              bullBos,bearBos,bullChoch,bearChoch;
   bool              bullMss,bearMss;      // shift right after a sweep
   int               mssAgeBars;
   double            lastSwingHigh,lastSwingLow;
   // §4 liquidity
   bool              sweptSellside,sweptBuyside;
   double            sweepLevel,sweepExtreme;
   int               sweepAgeBars;
   double            nearestBuyside,nearestSellside;
   // §5 premium / discount
   double            rangeHigh,rangeLow,equilibrium;
   double            pdPosition;           // 0 = range low, 1 = range high
   bool              inDiscount,inPremium,inOte;
   // §6 killzone
   bool              inKillzone;
   string            killzoneName;
   // §7 HTF
   double            htfBias;              // -1..+1
   // active setup
   string            setup;
   int               setupDir;
   double            zoneTop,zoneBottom;   // the POI being entered
   double            stopLevel,targetLevel;
   double            setupRR;
   int               obCount,fvgCount,liqCount;
  };

//--- basket state (§9)
struct SBasket
  {
   int               count;
   double            volume,avgEntry,floatPL;
   int               dir;
   datetime          firstTime,lastTime;
   double            lastPrice,firstVolume;
  };

//=========================== GLOBAL STATE ===========================

double   g_h[],g_l[],g_o[],g_c[];
datetime g_t[];
long     g_v[];
int      g_bars=0;

SOB      g_obs[];
SFVG     g_fvgs[];
SLIQ     g_liqs[];
SView    g_view;

double   g_basketRisk=0.0;          // R unit for the whole basket
double   g_firstLot=0.0;
double   g_basketStop=0.0;
ulong    g_partialDone[],g_beDone[];

double   g_dayStartEquity=0.0,g_peakEquity=0.0;
int      g_dayKey=-1;
bool     g_breaker=false,g_breakerLogged=false;

datetime g_lastBar=0,g_lastEntry=0;
int      g_logHandle=INVALID_HANDLE;
string   g_block="starting",g_lastBlock="";
datetime g_lastBlockLog=0;
int      g_entries=0;
int      g_objCount=0;

//============================== LOGGING =============================

void LogInit(void)
  {
   g_logHandle=INVALID_HANDLE;
   if(!InpCsvLog) return;
   g_logHandle=FileOpen("MedulaSMC.csv",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(g_logHandle!=INVALID_HANDLE)
     {
      if(FileSize(g_logHandle)==0)
         FileWriteString(g_logHandle,"time;symbol;setup;dir;htfBias;pd;killzone;entry;sl;tp;rr;lots;risk;basket;reason\n");
      FileSeek(g_logHandle,0,SEEK_END);
     }
  }
void LogClose(void){ if(g_logHandle!=INVALID_HANDLE){ FileClose(g_logHandle); g_logHandle=INVALID_HANDLE; } }
void LogEvent(const string m){ if(InpVerboseLog) Print("[SMC] ",m); }

void LogTrade(const string dir,const double entry,const double sl,const double tp,
              const double rr,const double lots,const double risk,const int basket,
              const string reason)
  {
   string line=StringFormat("%s;%s;%s;%s;%.2f;%.2f;%s;%.5f;%.5f;%.5f;%.2f;%.2f;%.2f;%d;%s",
                            TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),_Symbol,
                            g_view.setup,dir,g_view.htfBias,g_view.pdPosition,
                            g_view.killzoneName,entry,sl,tp,rr,lots,risk,basket,reason);
   if(InpVerboseLog) Print("[SMC] ",line);
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

//========================= RAW PRICE ACCESS =========================

//--- true range is arithmetic on the bars, not an indicator
double TrueRange(const int i)
  {
   if(i+1>=g_bars) return g_h[i]-g_l[i];
   double a=g_h[i]-g_l[i];
   return MathMax(a,MathMax(MathAbs(g_h[i]-g_c[i+1]),MathAbs(g_l[i]-g_c[i+1])));
  }

double AverageRange(const int period)
  {
   int n=MathMin(period,g_bars-1);
   if(n<=0) return 0.0;
   double s=0.0;
   for(int i=0;i<n;i++) s+=TrueRange(i);
   return s/n;
  }

bool LoadBars(void)
  {
   ArraySetAsSeries(g_h,true); ArraySetAsSeries(g_l,true);
   ArraySetAsSeries(g_o,true); ArraySetAsSeries(g_c,true);
   ArraySetAsSeries(g_t,true); ArraySetAsSeries(g_v,true);
   int got=CopyHigh(_Symbol,PERIOD_M5,0,InpBars,g_h);
   if(got<120){ Block(StringFormat("only %d M5 bars loaded, need 120+",got)); return false; }
   if(CopyLow(_Symbol,PERIOD_M5,0,got,g_l)<got)   return false;
   if(CopyOpen(_Symbol,PERIOD_M5,0,got,g_o)<got)  return false;
   if(CopyClose(_Symbol,PERIOD_M5,0,got,g_c)<got) return false;
   if(CopyTime(_Symbol,PERIOD_M5,0,got,g_t)<got)  return false;
   if(CopyTickVolume(_Symbol,PERIOD_M5,0,got,g_v)<got) ArrayInitialize(g_v,1);
   g_bars=got;
   return true;
  }

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

//================== §1 MARKET STRUCTURE / MSS =======================

//--- Walk the window oldest to newest tracking swing points and the breaks
//    between them. A break in the direction of the prevailing leg is a BOS;
//    a break against it is a CHoCH. A CHoCH that lands immediately after a
//    liquidity sweep is a market structure shift — the ICT entry trigger.
void BuildStructure(void)
  {
   g_view.bullBos=false; g_view.bearBos=false;
   g_view.bullChoch=false; g_view.bearChoch=false;
   g_view.bullMss=false; g_view.bearMss=false;
   g_view.mssAgeBars=9999;
   g_view.lastSwingHigh=0.0; g_view.lastSwingLow=0.0;

   int k=InpSwingK;
   double buf=InpBosBufferPct*g_view.avgRange;
   double lastSH=0.0,lastSL=0.0;
   int dir=0;

   for(int b=g_bars-1-k;b>=0;b--)
     {
      int j=b+k;                                  // confirmed k bars later
      if(j<=g_bars-1-k)
        {
         if(IsSwingHigh(j,k)) lastSH=g_h[j];
         if(IsSwingLow(j,k))  lastSL=g_l[j];
        }
      if(lastSH>0.0 && g_c[b]>lastSH+buf)
        {
         bool choch=(dir==-1);
         dir=1;
         if(b<=InpStructureLookback)
           {
            if(choch){ g_view.bullChoch=true; g_view.bullMss=true; g_view.mssAgeBars=MathMin(g_view.mssAgeBars,b); }
            else       g_view.bullBos=true;
           }
         lastSH=0.0;
        }
      if(lastSL>0.0 && g_c[b]<lastSL-buf)
        {
         bool choch=(dir==1);
         dir=-1;
         if(b<=InpStructureLookback)
           {
            if(choch){ g_view.bearChoch=true; g_view.bearMss=true; g_view.mssAgeBars=MathMin(g_view.mssAgeBars,b); }
            else       g_view.bearBos=true;
           }
         lastSL=0.0;
        }
     }
   g_view.structDir=dir;

   for(int j=k;j<g_bars-k;j++)
     {
      if(g_view.lastSwingHigh<=0.0 && IsSwingHigh(j,k)) g_view.lastSwingHigh=g_h[j];
      if(g_view.lastSwingLow <=0.0 && IsSwingLow(j,k))  g_view.lastSwingLow =g_l[j];
      if(g_view.lastSwingHigh>0.0 && g_view.lastSwingLow>0.0) break;
     }
  }

//======================= §2 ORDER BLOCKS ============================

void PushOB(const double top,const double bottom,const int dir,const int shift,
            const double strength)
  {
   int n=ArraySize(g_obs);
   if(n>=InpMaxOrderBlocks*2) return;
   ArrayResize(g_obs,n+1);
   g_obs[n].top=top; g_obs[n].bottom=bottom; g_obs[n].dir=dir;
   g_obs[n].shift=shift; g_obs[n].strength=strength;
   g_obs[n].mitigated=false; g_obs[n].breaker=false; g_obs[n].alive=true;
  }

//--- An order block is the last candle against the move, immediately before
//    a displacement leg. Institutions are held to have positioned there, so
//    price returning to it is the classic entry. A block price has closed
//    decisively through has failed and becomes a breaker in the other
//    direction.
void BuildOrderBlocks(void)
  {
   ArrayResize(g_obs,0);
   if(!InpUseOrderBlocks || g_view.avgRange<=0.0) return;

   int scan=MathMin(g_bars-4,InpObMaxAgeBars);
   for(int i=scan;i>=1;i--)
     {
      double rng=g_h[i]-g_l[i];
      if(rng<=0.0) continue;
      double body=MathAbs(g_c[i]-g_o[i]);
      bool up=(rng>=InpDisplacementMult*g_view.avgRange &&
               body>=InpDisplacementBody*rng && g_c[i]>g_o[i]);
      bool dn=(rng>=InpDisplacementMult*g_view.avgRange &&
               body>=InpDisplacementBody*rng && g_c[i]<g_o[i]);
      if(!up && !dn) continue;

      // the last opposing candle before the displacement
      int ob=-1;
      for(int b=i+1;b<=i+6 && b<g_bars;b++)
        {
         if(up && g_c[b]<g_o[b]){ ob=b; break; }
         if(dn && g_c[b]>g_o[b]){ ob=b; break; }
        }
      if(ob<0) continue;
      PushOB(g_h[ob],g_l[ob],(up?1:-1),ob,rng/g_view.avgRange);
     }

   // mitigation and breaker state
   for(int z=ArraySize(g_obs)-1;z>=0;z--)
     {
      double top=g_obs[z].top,bot=g_obs[z].bottom,h=top-bot;
      if(h<=0.0){ g_obs[z].alive=false; continue; }
      double mitLevel=(g_obs[z].dir>0 ? top-h*InpObMitigatedPct/100.0
                                      : bot+h*InpObMitigatedPct/100.0);
      for(int i=g_obs[z].shift-1;i>=0;i--)
        {
         if(g_obs[z].dir>0)
           {
            if(g_l[i]<=mitLevel) g_obs[z].mitigated=true;
            if(g_c[i]<bot-0.2*g_view.avgRange)
              {
               if(InpUseBreakers){ g_obs[z].breaker=true; g_obs[z].dir=-1; }
               else g_obs[z].alive=false;
               break;
              }
           }
         else
           {
            if(g_h[i]>=mitLevel) g_obs[z].mitigated=true;
            if(g_c[i]>top+0.2*g_view.avgRange)
              {
               if(InpUseBreakers){ g_obs[z].breaker=true; g_obs[z].dir=1; }
               else g_obs[z].alive=false;
               break;
              }
           }
        }
     }
   g_view.obCount=0;
   for(int z=0;z<ArraySize(g_obs);z++) if(g_obs[z].alive) g_view.obCount++;
  }

//====================== §3 FAIR VALUE GAPS ==========================

//--- A fair value gap is a three-candle imbalance: price moved so fast that
//    candle 1 and candle 3 do not overlap. The unfilled space is inefficient
//    pricing that price tends to revisit.
void BuildFVGs(void)
  {
   ArrayResize(g_fvgs,0);
   if(!InpUseFVG || g_view.avgRange<=0.0) return;
   double minGap=InpFvgMinPct*g_view.avgRange;

   int scan=MathMin(g_bars-3,InpFvgMaxAgeBars);
   for(int i=scan;i>=1;i--)
     {
      // bullish: low of the newer candle above the high of the older one
      double gapUp=g_l[i-1]-g_h[i+1];
      if(gapUp>=minGap)
        {
         int n=ArraySize(g_fvgs);
         if(n<InpMaxFVGs*2)
           {
            ArrayResize(g_fvgs,n+1);
            g_fvgs[n].top=g_l[i-1]; g_fvgs[n].bottom=g_h[i+1];
            g_fvgs[n].dir=1; g_fvgs[n].shift=i;
            g_fvgs[n].filled=false; g_fvgs[n].alive=true;
           }
        }
      double gapDn=g_l[i+1]-g_h[i-1];
      if(gapDn>=minGap)
        {
         int n=ArraySize(g_fvgs);
         if(n<InpMaxFVGs*2)
           {
            ArrayResize(g_fvgs,n+1);
            g_fvgs[n].top=g_l[i+1]; g_fvgs[n].bottom=g_h[i-1];
            g_fvgs[n].dir=-1; g_fvgs[n].shift=i;
            g_fvgs[n].filled=false; g_fvgs[n].alive=true;
           }
        }
     }

   // consumption: price trading through the consequent encroachment (mid)
   for(int z=ArraySize(g_fvgs)-1;z>=0;z--)
     {
      double ce=(g_fvgs[z].top+g_fvgs[z].bottom)*0.5;
      double lim=(g_fvgs[z].dir>0
                  ? g_fvgs[z].top-(g_fvgs[z].top-g_fvgs[z].bottom)*InpFvgFillPct/100.0
                  : g_fvgs[z].bottom+(g_fvgs[z].top-g_fvgs[z].bottom)*InpFvgFillPct/100.0);
      for(int i=g_fvgs[z].shift-1;i>=0;i--)
        {
         if(g_fvgs[z].dir>0 && g_l[i]<=lim){ g_fvgs[z].filled=true; }
         if(g_fvgs[z].dir<0 && g_h[i]>=lim){ g_fvgs[z].filled=true; }
         if(g_fvgs[z].dir>0 && g_c[i]<g_fvgs[z].bottom){ g_fvgs[z].alive=false; break; }
         if(g_fvgs[z].dir<0 && g_c[i]>g_fvgs[z].top)   { g_fvgs[z].alive=false; break; }
        }
     }
   g_view.fvgCount=0;
   for(int z=0;z<ArraySize(g_fvgs);z++) if(g_fvgs[z].alive) g_view.fvgCount++;
  }

//==================== §4 LIQUIDITY AND SWEEPS =======================

void PushLiq(const double price,const int side,const int touches,const int shift)
  {
   int n=ArraySize(g_liqs);
   ArrayResize(g_liqs,n+1);
   g_liqs[n].price=price; g_liqs[n].side=side; g_liqs[n].touches=touches;
   g_liqs[n].shift=shift; g_liqs[n].swept=false; g_liqs[n].alive=true;
  }

//--- Stops rest above equal highs and below equal lows, and at the previous
//    day's extremes. Those pools are what gets hunted. A sweep is price
//    taking the level and closing back on the original side — the wick
//    through it is the stop run.
void BuildLiquidity(void)
  {
   ArrayResize(g_liqs,0);
   g_view.sweptBuyside=false; g_view.sweptSellside=false;
   g_view.sweepLevel=0.0; g_view.sweepExtreme=0.0; g_view.sweepAgeBars=9999;
   g_view.nearestBuyside=0.0; g_view.nearestSellside=0.0;
   if(g_view.avgRange<=0.0) return;

   double tol=InpEqualTolPct*g_view.avgRange;
   int k=InpSwingK;
   int scan=MathMin(g_bars-1-k,InpLiqLookback);

   // swing extremes become pools; equal levels stack into stronger ones
   for(int j=k;j<=scan;j++)
     {
      if(IsSwingHigh(j,k))
        {
         bool merged=false;
         for(int z=0;z<ArraySize(g_liqs);z++)
            if(g_liqs[z].side>0 && MathAbs(g_liqs[z].price-g_h[j])<=tol)
              { g_liqs[z].touches++; merged=true; break; }
         if(!merged) PushLiq(g_h[j],1,1,j);
        }
      if(IsSwingLow(j,k))
        {
         bool merged=false;
         for(int z=0;z<ArraySize(g_liqs);z++)
            if(g_liqs[z].side<0 && MathAbs(g_liqs[z].price-g_l[j])<=tol)
              { g_liqs[z].touches++; merged=true; break; }
         if(!merged) PushLiq(g_l[j],-1,1,j);
        }
     }

   // previous day's high and low are major pools
   if(InpUsePrevDayLevels)
     {
      double dh[],dl[];
      ArraySetAsSeries(dh,true); ArraySetAsSeries(dl,true);
      if(CopyHigh(_Symbol,PERIOD_D1,0,3,dh)>=2 && CopyLow(_Symbol,PERIOD_D1,0,3,dl)>=2)
        {
         PushLiq(dh[1],1,3,0);
         PushLiq(dl[1],-1,3,0);
        }
     }

   // sweep detection: level taken, then rejected
   for(int z=0;z<ArraySize(g_liqs);z++)
     {
      for(int i=MathMin(g_liqs[z].shift-1,InpSweepMaxAgeBars);i>=0;i--)
        {
         if(i<0) break;
         if(g_liqs[z].side>0 && g_h[i]>g_liqs[z].price && g_c[i]<g_liqs[z].price)
           {
            g_liqs[z].swept=true;
            if(i<g_view.sweepAgeBars)
              {
               g_view.sweptBuyside=true; g_view.sweptSellside=false;
               g_view.sweepLevel=g_liqs[z].price;
               g_view.sweepExtreme=g_h[i];
               g_view.sweepAgeBars=i;
              }
           }
         if(g_liqs[z].side<0 && g_l[i]<g_liqs[z].price && g_c[i]>g_liqs[z].price)
           {
            g_liqs[z].swept=true;
            if(i<g_view.sweepAgeBars)
              {
               g_view.sweptSellside=true; g_view.sweptBuyside=false;
               g_view.sweepLevel=g_liqs[z].price;
               g_view.sweepExtreme=g_l[i];
               g_view.sweepAgeBars=i;
              }
           }
        }
     }

   // nearest untouched pools become the natural targets
   double px=g_view.bid,bestUp=DBL_MAX,bestDn=DBL_MAX;
   for(int z=0;z<ArraySize(g_liqs);z++)
     {
      if(!g_liqs[z].alive || g_liqs[z].swept) continue;
      if(g_liqs[z].side>0 && g_liqs[z].price>px && (g_liqs[z].price-px)<bestUp)
        { bestUp=g_liqs[z].price-px; g_view.nearestBuyside=g_liqs[z].price; }
      if(g_liqs[z].side<0 && g_liqs[z].price<px && (px-g_liqs[z].price)<bestDn)
        { bestDn=px-g_liqs[z].price; g_view.nearestSellside=g_liqs[z].price; }
     }
   g_view.liqCount=ArraySize(g_liqs);
  }

//=================== §5 PREMIUM / DISCOUNT / OTE ====================

//--- The dealing range runs from the recent swing low to the recent swing
//    high. Below its midpoint is discount — where longs are cheap. Above is
//    premium. The optimal trade entry band sits at the 62-79% retracement.
void BuildPremiumDiscount(void)
  {
   int n=MathMin(InpDealingRangeBars,g_bars-1);
   double hi=-DBL_MAX,lo=DBL_MAX;
   for(int i=0;i<n;i++)
     {
      if(g_h[i]>hi) hi=g_h[i];
      if(g_l[i]<lo) lo=g_l[i];
     }
   g_view.rangeHigh=hi; g_view.rangeLow=lo;
   double span=hi-lo;
   g_view.equilibrium=(hi+lo)*0.5;
   g_view.pdPosition=(span>0.0 ? (g_view.bid-lo)/span : 0.5);
   g_view.inDiscount=(g_view.pdPosition<0.5);
   g_view.inPremium =(g_view.pdPosition>0.5);

   // OTE measured from whichever end the current leg started
   double retr=(g_view.structDir>=0 ? 1.0-g_view.pdPosition : g_view.pdPosition);
   g_view.inOte=(retr>=InpOteLow && retr<=InpOteHigh);
  }

//========================== §6 KILLZONES ============================

void BuildKillzone(void)
  {
   g_view.inKillzone=false;
   g_view.killzoneName="outside";
   MqlDateTime g;
   TimeToStruct(TimeGMT(),g);
   int h=g.hour;
   if(h>=InpLondonStart && h<InpLondonEnd){ g_view.inKillzone=true; g_view.killzoneName="London"; }
   else if(h>=InpNyStart && h<InpNyEnd)   { g_view.inKillzone=true; g_view.killzoneName="NewYork"; }
   else if(h>=InpLnCloseStart && h<InpLnCloseEnd){ g_view.inKillzone=true; g_view.killzoneName="LondonClose"; }
  }

//========================= §7 HIGHER TF BIAS ========================

//--- Higher-timeframe direction read the same way: the sequence of swing
//    highs and lows, not an average of price.
double HtfStructure(const ENUM_TIMEFRAMES tf)
  {
   double hh[],ll[];
   ArraySetAsSeries(hh,true); ArraySetAsSeries(ll,true);
   int want=100;
   if(CopyHigh(_Symbol,tf,0,want,hh)<want) return 0.0;
   if(CopyLow(_Symbol,tf,0,want,ll)<want)  return 0.0;
   int k=2,up=0,dn=0;
   double ph=0.0,pl=0.0;
   for(int j=want-1-k;j>=k;j--)
     {
      bool sh=true,sl=true;
      for(int m=1;m<=k;m++)
        {
         if(hh[j]<=hh[j+m] || hh[j]<=hh[j-m]) sh=false;
         if(ll[j]>=ll[j+m] || ll[j]>=ll[j-m]) sl=false;
        }
      if(sh){ if(ph>0.0){ if(hh[j]>ph) up++; else dn++; } ph=hh[j]; }
      if(sl){ if(pl>0.0){ if(ll[j]>pl) up++; else dn++; } pl=ll[j]; }
     }
   return (double)(up-dn)/(double)(up+dn+1);
  }

void BuildHtfBias(void)
  {
   if(!InpUseHtfBias){ g_view.htfBias=0.0; return; }
   double sum=0.0,w=0.0;
   if(InpHtfM15){ sum+=0.25*HtfStructure(PERIOD_M15); w+=0.25; }
   if(InpHtfH1) { sum+=0.35*HtfStructure(PERIOD_H1);  w+=0.35; }
   if(InpHtfH4) { sum+=0.40*HtfStructure(PERIOD_H4);  w+=0.40; }
   g_view.htfBias=(w>0.0 ? MClamp(sum/w,-1.0,1.0) : 0.0);
  }

//======================= THE ICT ENTRY MODEL ========================

//--- Assemble the model. Each condition is checked in the order a trader
//    would check it, and the first failure is reported so the journal shows
//    exactly which leg of the setup was missing.
void FindSetup(void)
  {
   g_view.setup="none";
   g_view.setupDir=0;
   g_view.zoneTop=0.0; g_view.zoneBottom=0.0;
   g_view.stopLevel=0.0; g_view.targetLevel=0.0; g_view.setupRR=0.0;

   double px=g_view.bid;
   double buf=InpEntryZoneBuffer*g_view.avgRange;

   for(int pass=0;pass<2;pass++)
     {
      int dir=(pass==0 ? 1 : -1);

      // 1. higher-timeframe agreement
      if(InpUseHtfBias && dir*g_view.htfBias<InpHtfMinAgreement) continue;

      // 2. liquidity taken on the opposite side (optional filter)
      bool swept=(dir>0 ? g_view.sweptSellside : g_view.sweptBuyside);
      bool sweepFresh=(swept && g_view.sweepAgeBars<=InpSweepMaxAgeBars);
      if(InpRequireSweep && !sweepFresh) continue;

      // 3. structure. A sweep plus a shift is the textbook reversal entry;
      //    without a sweep, structure simply has to be on our side and a
      //    break must have happened recently — the continuation entry a
      //    scalper takes far more often than the full reversal model.
      bool mss=(dir>0 ? (g_view.bullMss || g_view.bullBos)
                      : (g_view.bearMss || g_view.bearBos));
      bool aligned=(g_view.structDir==dir);
      if(!mss && !aligned) continue;
      if(mss && g_view.mssAgeBars>InpMaxSetupAgeBars && !aligned) continue;

      // 4/5. price is back inside the imbalance or block that shift created
      double zt=0.0,zb=0.0;
      string src="";

      if(InpEntryOnFVG)
         for(int z=0;z<ArraySize(g_fvgs);z++)
           {
            if(!g_fvgs[z].alive || g_fvgs[z].filled) continue;
            if(g_fvgs[z].dir!=dir) continue;
            if(g_fvgs[z].shift>InpMaxSetupAgeBars+10) continue;
            if(px<=g_fvgs[z].top+buf && px>=g_fvgs[z].bottom-buf)
              { zt=g_fvgs[z].top; zb=g_fvgs[z].bottom; src="FVG"; break; }
           }

      if(zt<=0.0 && InpEntryOnOB)
         for(int z=0;z<ArraySize(g_obs);z++)
           {
            if(!g_obs[z].alive) continue;
            if(g_obs[z].dir!=dir) continue;
            if(g_obs[z].shift>InpObMaxAgeBars) continue;
            if(px<=g_obs[z].top+buf && px>=g_obs[z].bottom-buf)
              {
               zt=g_obs[z].top; zb=g_obs[z].bottom;
               src=(g_obs[z].breaker ? "breaker block" : "order block");
               break;
              }
           }

      if(zt<=0.0) continue;

      // 6. premium / discount discipline
      if(InpUsePremiumDiscount)
        {
         if(dir>0 && !g_view.inDiscount) continue;
         if(dir<0 && !g_view.inPremium)  continue;
        }
      if(InpRequireOte && !g_view.inOte) continue;

      // 7. killzone
      if(InpUseKillzones && !g_view.inKillzone) continue;

      // Stop placement decides whether this is a scalp or a swing.
      //   Beyond the POI  -> the idea is wrong the moment the zone fails.
      //                      Typically 0.5-1.5 x average range: tight enough
      //                      to scalp and small enough for a modest account.
      //   Beyond the sweep-> the idea is wrong only if the whole raid fails.
      //                      Typically 2-5 x average range: a swing stop.
      double sl,tp;
      if(InpStopBeyondPOI || InpScalpMode)
        {
         double buf2=InpPoiStopBuffer*g_view.avgRange;
         sl=(dir>0 ? zb-buf2 : zt+buf2);
        }
      else
        {
         double slBuf=InpSlBufferPct*g_view.avgRange;
         if(dir>0) sl=(g_view.sweepExtreme>0.0 ? MathMin(g_view.sweepExtreme,zb) : zb)-slBuf;
         else      sl=(g_view.sweepExtreme>0.0 ? MathMax(g_view.sweepExtreme,zt) : zt)+slBuf;
        }

      double risk=MathAbs(px-sl);
      if(risk<=0.0) continue;
      if(risk<0.25*g_view.avgRange)          // never a meaningless stop
        {
         risk=0.25*g_view.avgRange;
         sl=(dir>0 ? px-risk : px+risk);
        }

      // A scalper banks the nearer of the R target and the next pool; a
      // swing trader runs to the pool. Same liquidity logic, different
      // patience.
      double rTarget=(InpScalpMode ? InpScalpTargetR : InpTpRMultiple)*risk;
      double pool=(dir>0 ? g_view.nearestBuyside : g_view.nearestSellside);
      bool poolValid=(dir>0 ? pool>px : (pool>0.0 && pool<px));
      if(InpScalpMode)
        {
         tp=(dir>0 ? px+rTarget : px-rTarget);
         if(poolValid && MathAbs(pool-px)<rTarget) tp=pool;   // take the closer one
        }
      else
         tp=(poolValid ? pool : (dir>0 ? px+rTarget : px-rTarget));

      double rr=MathAbs(tp-px)/risk;
      if(rr<InpMinRR) continue;

      string model;
      if(sweepFresh && mss) model="sweep + MSS + "+src;      // full ICT reversal
      else if(mss)          model="MSS + "+src;              // shift into the POI
      else                  model=src+" continuation";       // with-structure scalp
      g_view.setup=StringFormat("%s %s",(dir>0?"bullish":"bearish"),model);
      g_view.setupDir=dir;
      g_view.zoneTop=zt; g_view.zoneBottom=zb;
      g_view.stopLevel=sl; g_view.targetLevel=tp; g_view.setupRR=rr;
      return;
     }
  }

//--- explain the first missing leg, for the journal
string MissingLeg(void)
  {
   if(InpUseHtfBias && MathAbs(g_view.htfBias)<InpHtfMinAgreement)
      return StringFormat("higher timeframes undecided (bias %.2f, need %.2f)",
                          g_view.htfBias,InpHtfMinAgreement);
   if(InpRequireSweep && !g_view.sweptBuyside && !g_view.sweptSellside)
      return "no liquidity sweep yet";
   if(!g_view.bullMss && !g_view.bearMss && !g_view.bullBos && !g_view.bearBos)
      return "no market structure shift after the sweep";
   if(g_view.obCount==0 && g_view.fvgCount==0)
      return "no unmitigated order block or fair value gap";
   if(InpUseKillzones && !g_view.inKillzone)
      return "outside the killzones";
   if(InpUsePremiumDiscount)
      return StringFormat("waiting for price to reach a POI in %s (now %.0f%% of range)",
                          (g_view.htfBias>=0?"discount":"premium"),g_view.pdPosition*100.0);
   return "conditions incomplete";
  }

//============================ RISK / SIZE ===========================

void RiskUpdate(void)
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int key=dt.year*1000+dt.day_of_year;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(key!=g_dayKey){ g_dayKey=key; g_dayStartEquity=eq; g_breaker=false; }
   if(eq>g_peakEquity) g_peakEquity=eq;
  }
bool CircuitBreaker(void)
  {
   if(g_breaker) return true;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if((g_dayStartEquity-eq)>=g_dayStartEquity*InpDailyLossPct/100.0) g_breaker=true;
   if((g_peakEquity-eq)>=g_peakEquity*InpMaxDDPct/100.0)             g_breaker=true;
   return g_breaker;
  }

double MinLot(void){ double m=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN); return (m>0.0?m:0.01); }
double LotStep(void){ double s=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP); return (s>0.0?s:0.01); }

double LotForRisk(const double amount,const double dist)
  {
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0.0||ts<=0.0||dist<=0.0||amount<=0.0) return 0.0;
   double perLot=dist/ts*tv;
   return (perLot>0.0 ? amount/perLot : 0.0);
  }
double RiskOfLots(const double lots,const double dist)
  {
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0.0||ts<=0.0) return 0.0;
   return dist/ts*tv*lots;
  }
double NormalizeLots(double lots)
  {
   double step=LotStep(),mn=MinLot(),mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   lots=MathFloor(lots/step+1e-9)*step;
   if(lots<mn) return (InpAllowMinLot?mn:0.0);
   if(mx>0.0)  lots=MathMin(lots,mx);
   return lots;
  }
//--- widest stop this account can carry at minimum lot inside the ceiling
double AffordableStop(void)
  {
   double cap=AccountInfoDouble(ACCOUNT_EQUITY)*InpMaxRiskPctHard/100.0;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0.0||ts<=0.0) return 0.0;
   return cap/(tv/ts*MinLot());
  }
bool MarginOK(const int dir,const double lots)
  {
   MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return false;
   double m=0.0;
   if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,lots,
                       (dir>0?t.ask:t.bid),m)) return false;
   return AccountInfoDouble(ACCOUNT_MARGIN_FREE)>=m*InpMarginSafety;
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
bool TicketSeen(const ulong &a[],const ulong t)
  { for(int i=ArraySize(a)-1;i>=0;i--) if(a[i]==t) return true; return false; }
void TicketMark(ulong &a[],const ulong t)
  { int n=ArraySize(a); ArrayResize(a,n+1); a[n]=t; }

//========================= §9 BASKET MANAGER ========================

//--- Positions on this symbol under this magic are one exposure. The basket
//    has a single average entry, a single R unit taken from the first entry,
//    and one set of targets — individual legs are never managed alone.
void GetBasket(SBasket &b)
  {
   b.count=0; b.volume=0.0; b.avgEntry=0.0; b.floatPL=0.0; b.dir=0;
   b.firstTime=0; b.lastTime=0; b.lastPrice=0.0; b.firstVolume=0.0;
   double pv=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double op =PositionGetDouble(POSITION_PRICE_OPEN);
      datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
      b.count++; b.volume+=vol; pv+=vol*op;
      b.floatPL+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      b.dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);
      if(b.firstTime==0 || ot<b.firstTime){ b.firstTime=ot; b.firstVolume=vol; }
      if(ot>=b.lastTime){ b.lastTime=ot; b.lastPrice=op; }
     }
   if(b.volume>0.0) b.avgEntry=pv/b.volume;
  }

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
   req.deviation=(ulong)InpDeviationPts; req.magic=(ulong)InpMagic;
   req.type_filling=Filling();
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
void CloseBasket(const string reason)
  {
   bool any=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      CloseTicket(tk); any=true;
     }
   if(any)
     {
      LogEvent("BASKET CLOSED: "+reason);
      g_basketRisk=0.0; g_firstLot=0.0; g_basketStop=0.0;
      ArrayResize(g_partialDone,0); ArrayResize(g_beDone,0);
     }
  }
double BasketRiskUsed(void)
  {
   double used=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      double sl=PositionGetDouble(POSITION_SL);
      double op=PositionGetDouble(POSITION_PRICE_OPEN);
      double vol=PositionGetDouble(POSITION_VOLUME);
      if(sl>0.0) used+=RiskOfLots(vol,MathAbs(op-sl));
      else       used+=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPct/100.0;
     }
   return used;
  }

//--- basket-level management, run every tick while exposure exists
void ManageBasket(const SBasket &b)
  {
   if(b.count==0 || g_basketRisk<=0.0) return;
   double R=b.floatPL/g_basketRisk;

   if(R>=InpBasketTargetR){ CloseBasket(StringFormat("basket target %.2fR",R)); return; }

   // a scalp that has not resolved is dead money — release the risk
   if(InpScalpMode && b.firstTime>0)
     {
      int held=(int)((TimeCurrent()-b.firstTime)/MathMax(PeriodSeconds(PERIOD_M5),1));
      if(held>InpMaxHoldBars && R<0.3)
        { CloseBasket(StringFormat("scalp timed out after %d M5 bars at %.2fR",held,R)); return; }
     }
   if(R<=-InpBasketStopR) { CloseBasket(StringFormat("basket stop %.2fR",R));  return; }

   if(InpCloseOnFlip && MSign(g_view.htfBias)!=0 && MSign(g_view.htfBias)!=b.dir &&
      MathAbs(g_view.htfBias)>=InpHtfMinAgreement)
     { CloseBasket("higher-timeframe bias flipped against the basket"); return; }

   if((b.dir>0 && g_view.bearChoch) || (b.dir<0 && g_view.bullChoch))
     { CloseBasket("structure shifted against the basket"); return; }

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double stops=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*pt;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double sl =PositionGetDouble(POSITION_SL);
      double tp =PositionGetDouble(POSITION_TP);
      int pd=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);

      if(InpBasketPartial && R>=InpBasketPartialR && !TicketSeen(g_partialDone,tk))
        {
         double step=LotStep();
         double part=MathFloor(vol*InpBasketPartialPct/100.0/step+1e-9)*step;
         if(part>=MinLot() && (vol-part)>=MinLot())
           {
            if(ClosePartial(tk,part))
              { TicketMark(g_partialDone,tk);
                LogEvent(StringFormat("basket partial: closed %.2f at %.2fR",part,R)); }
           }
         else TicketMark(g_partialDone,tk);
        }

      // break-even is set on the BASKET average, not on each leg
      if(InpBasketBreakEven && R>=InpBasketBeAtR && !TicketSeen(g_beDone,tk))
        {
         double be=NormalizeDouble(b.avgEntry+pd*0.1*g_view.avgRange,digits);
         bool better=(pd>0 ? (sl<=0.0||be>sl+pt) : (sl<=0.0||be<sl-pt));
         bool legal =(pd>0 ? be<g_view.bid-stops : be>g_view.ask+stops);
         if(better && legal && ModifySL(tk,be,tp))
           { TicketMark(g_beDone,tk);
             LogEvent(StringFormat("basket break-even at %.2fR (avg entry %.5f)",R,b.avgEntry)); }
        }
     }
  }

//--- a scale-in requires a fresh, independent confirmation in the same
//    direction, spacing from the last fill, and room under the basket cap
bool ScaleInAllowed(const SBasket &b)
  {
   if(!InpAllowScaleIn || b.count==0) return false;
   if(b.count>=InpMaxBasketTrades) return false;
   if(g_view.setupDir!=b.dir) return false;
   if(MathAbs(g_view.bid-b.lastPrice)<InpScaleMinSpacing*g_view.avgRange) return false;
   return true;
  }

//============================== ENTRY ===============================

void TryEnter(const SBasket &b,const bool isScale)
  {
   int dir=g_view.setupDir;
   if(dir==0) return;

   if(InpEntryCooldownSec>0 && g_lastEntry>0 &&
      (TimeCurrent()-g_lastEntry)<InpEntryCooldownSec)
     { Block("entry cooldown"); return; }

   MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return;
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double stops=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*pt;
   double entry=(dir>0?t.ask:t.bid);

   double sl=g_view.stopLevel,tp=g_view.targetLevel;
   if(dir>0){ if(entry-sl<stops+pt) sl=entry-(stops+pt); if(tp-entry<stops+pt) tp=entry+(stops+pt); }
   else     { if(sl-entry<stops+pt) sl=entry+(stops+pt); if(entry-tp<stops+pt) tp=entry-(stops+pt); }
   sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);

   double dist=MathAbs(entry-sl);
   if(dist<=0.0){ Block("stop distance is zero"); return; }

   double afford=AffordableStop();
   if(afford>0.0 && dist>afford)
     {
      if(InpFitStopToAccount)
        {
         double old=dist;
         dist=afford;
         sl=NormalizeDouble(dir>0?entry-dist:entry+dist,digits);
         tp=NormalizeDouble(dir>0?entry+InpTpRMultiple*dist:entry-InpTpRMultiple*dist,digits);
         LogEvent(StringFormat("stop tightened to fit account: %.5f -> %.5f (%.1fx closer than structure)",
                               old,dist,old/MathMax(dist,1e-9)));
        }
      else
        {
         Block(StringFormat("%s needs a %.5f stop, account carries %.5f at min lot "
                            "(deposit ~%.0f, or set InpFitStopToAccount)",
                            g_view.setup,dist,afford,
                            RiskOfLots(MinLot(),dist)/(InpMaxRiskPctHard/100.0)));
         return;
        }
     }

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double planned=eq*InpRiskPct/100.0;
   double lots=NormalizeLots(LotForRisk(planned,dist));
   if(isScale && g_firstLot>0.0)
      lots=NormalizeLots(g_firstLot*MathPow(InpScaleDecay,b.count));
   if(lots<=0.0){ Block("size below broker minimum"); return; }

   double realRisk=RiskOfLots(lots,dist);
   if(realRisk>eq*InpMaxRiskPctHard/100.0)
     {
      Block(StringFormat("risk %.2f = %.0f%% of equity over the %.0f%% ceiling",
                         realRisk,100.0*realRisk/MathMax(eq,0.01),InpMaxRiskPctHard));
      return;
     }
   if(InpUseBasket && BasketRiskUsed()+realRisk>eq*InpMaxBasketRiskPct/100.0)
     { Block("basket risk cap reached"); return; }
   if(!MarginOK(dir,lots)){ Block("insufficient free margin"); return; }

   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=lots;
   req.type=(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   req.price=entry; req.sl=sl; req.tp=tp;
   req.deviation=(ulong)InpDeviationPts; req.magic=(ulong)InpMagic;
   req.comment="SMC"; req.type_filling=Filling();

   if(!Send(req,res))
     {
      LogEvent(StringFormat("ORDER REJECTED: %s %.2f retcode=%u (%s)",
                            dir>0?"BUY":"SELL",lots,res.retcode,res.comment));
      Block(StringFormat("broker rejected, retcode %u",res.retcode));
      return;
     }

   if(!isScale || g_basketRisk<=0.0)
     {
      g_basketRisk=realRisk;                    // R for the whole basket
      g_firstLot=lots;
      g_basketStop=sl;
     }
   g_lastEntry=TimeCurrent();
   g_entries++;
   LogTrade(dir>0?"BUY":"SELL",res.price,sl,tp,g_view.setupRR,lots,realRisk,
            b.count+1,
            StringFormat("%s | htf %.2f | pd %.0f%% | %s%s",
                         g_view.setup,g_view.htfBias,g_view.pdPosition*100.0,
                         g_view.killzoneName,(isScale?" | SCALE-IN":"")));
   g_block="—";
  }

//========================== CHART OBJECTS ===========================

void ClearObjects(void)
  {
   ObjectsDeleteAll(0,"SMC_");
   g_objCount=0;
  }
void DrawBox(const string name,const datetime t1,const double p1,
             const datetime t2,const double p2,const color clr,const bool fill)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   else
     {
      ObjectMove(0,name,0,t1,p1);
      ObjectMove(0,name,1,t2,p2);
     }
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,fill);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   g_objCount++;
  }
void DrawZones(void)
  {
   if(!InpDrawObjects) return;
   ClearObjects();
   datetime now=(g_bars>0 ? g_t[0] : TimeCurrent());
   datetime fwd=now+PeriodSeconds(PERIOD_M5)*20;
   int drawn=0;
   for(int z=0;z<ArraySize(g_obs) && drawn<10;z++)
     {
      if(!g_obs[z].alive || g_obs[z].shift>=g_bars) continue;
      DrawBox(StringFormat("SMC_OB_%d",z),g_t[g_obs[z].shift],g_obs[z].top,fwd,g_obs[z].bottom,
              (g_obs[z].dir>0?clrTeal:clrFireBrick),true);
      drawn++;
     }
   drawn=0;
   for(int z=0;z<ArraySize(g_fvgs) && drawn<10;z++)
     {
      if(!g_fvgs[z].alive || g_fvgs[z].filled || g_fvgs[z].shift>=g_bars) continue;
      DrawBox(StringFormat("SMC_FVG_%d",z),g_t[g_fvgs[z].shift],g_fvgs[z].top,fwd,g_fvgs[z].bottom,
              (g_fvgs[z].dir>0?clrSteelBlue:clrIndianRed),false);
      drawn++;
     }
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

   g_view.avgRange=AverageRange(20);
   if(g_view.avgRange<=0.0){ Block("no price movement yet"); return false; }

   BuildStructure();        // §1
   BuildOrderBlocks();      // §2
   BuildFVGs();             // §3
   BuildLiquidity();        // §4
   BuildPremiumDiscount();  // §5
   BuildKillzone();         // §6
   BuildHtfBias();          // §7
   FindSetup();             // the model
   return true;
  }

//======================== SELF-TEST & PANEL =========================

void SelfTest(void)
  {
   if(!InpSelfTest) return;
   LogEvent("────────── SMC / ICT SELF-TEST ──────────");
   LogEvent(StringFormat("symbol %s  execution timeframe M5  bars loaded %d  (NO INDICATORS)",
                         _Symbol,g_bars));
   LogEvent(StringFormat("average range %.5f  spread %.0f pts",g_view.avgRange,g_view.spreadPts));
   LogEvent(StringFormat("structure dir %d | order blocks %d | FVGs %d | liquidity pools %d",
                         g_view.structDir,g_view.obCount,g_view.fvgCount,g_view.liqCount));
   LogEvent(StringFormat("HTF bias %.2f (need |%.2f|) | killzone %s | range position %.0f%%",
                         g_view.htfBias,InpHtfMinAgreement,g_view.killzoneName,
                         g_view.pdPosition*100.0));
   LogEvent(StringFormat("broker: min lot %.2f  contract %.0f  digits %d  stops level %d",
                         MinLot(),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),
                         (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS),
                         (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)));

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double afford=AffordableStop();
   LogEvent(StringFormat("account: equity %.2f  leverage 1:%d  algo trading %s",
                         eq,(int)AccountInfoInteger(ACCOUNT_LEVERAGE),
                         (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"ENABLED":"DISABLED")));
   LogEvent(StringFormat("widest stop this account can carry at min lot: %.5f (%.2f x avg range)",
                         afford,(g_view.avgRange>0.0?afford/g_view.avgRange:0.0)));
   if(afford<2.0*g_view.avgRange)
      LogEvent(StringFormat("*** WARNING: SMC stops sit beyond the swept extreme, typically 2-5 x "
                            "average range. This account can only carry %.1f x. Most setups will be "
                            "refused. Deposit about %.0f, or set InpFitStopToAccount=true and accept "
                            "stops placed by affordability rather than by structure. ***",
                            (g_view.avgRange>0.0?afford/g_view.avgRange:0.0),
                            RiskOfLots(MinLot(),3.0*g_view.avgRange)/(InpMaxRiskPctHard/100.0)));
   LogEvent("─────────────────────────────────────────");
  }

void Panel(const SBasket &b)
  {
   if(!InpShowPanel) return;
   string sweep="none";
   if(g_view.sweptSellside) sweep=StringFormat("SELLSIDE @ %.5f (%d bars ago)",
                                               g_view.sweepLevel,g_view.sweepAgeBars);
   else if(g_view.sweptBuyside) sweep=StringFormat("BUYSIDE @ %.5f (%d bars ago)",
                                                   g_view.sweepLevel,g_view.sweepAgeBars);
   string mss="none";
   if(g_view.bullMss) mss="BULLISH MSS";
   else if(g_view.bearMss) mss="BEARISH MSS";
   else if(g_view.bullBos) mss="bullish BOS";
   else if(g_view.bearBos) mss="bearish BOS";

   Comment(StringFormat(
      "MEDULA v4.10  SMC / ICT SCALPER  |  %s  M5\n"
      "no indicators — structure, liquidity, OB, FVG only\n"
      "──────────────────────────────────────────\n"
      "HTF bias      %+5.2f  (need %.2f)\n"
      "structure     dir %+d   %s\n"
      "liquidity     %s\n"
      "order blocks  %d      FVGs %d      pools %d\n"
      "dealing range %.5f - %.5f\n"
      "position      %.0f%% (%s%s)\n"
      "killzone      %s\n"
      "──────────────────────────────────────────\n"
      "SETUP   %s\n"
      "zone    %.5f - %.5f\n"
      "sl %.5f  tp %.5f  RR %.2f\n"
      "──────────────────────────────────────────\n"
      "BASKET  %d trades  vol %.2f  avg %.5f\n"
      "        float %.2f   R %.2f   risk unit %.2f\n"
      "entries %d   spread %.0f pts\n"
      "status  %s",
      _Symbol,
      g_view.htfBias,InpHtfMinAgreement,
      g_view.structDir,mss,
      sweep,
      g_view.obCount,g_view.fvgCount,g_view.liqCount,
      g_view.rangeLow,g_view.rangeHigh,
      g_view.pdPosition*100.0,
      (g_view.inDiscount?"discount":"premium"),(g_view.inOte?", OTE":""),
      g_view.killzoneName,
      g_view.setup,
      g_view.zoneBottom,g_view.zoneTop,
      g_view.stopLevel,g_view.targetLevel,g_view.setupRR,
      b.count,b.volume,b.avgEntry,
      b.floatPL,(g_basketRisk>0.0?b.floatPL/g_basketRisk:0.0),g_basketRisk,
      g_entries,g_view.spreadPts,
      g_block));
  }

//========================== EVENT HANDLERS ==========================

int OnInit(void)
  {
   LogInit();
   ArrayResize(g_partialDone,0); ArrayResize(g_beDone,0);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEquity=eq; g_peakEquity=eq; g_dayKey=-1;
   g_breaker=false; g_lastBar=0; g_lastEntry=0; g_entries=0;
   g_basketRisk=0.0; g_firstLot=0.0;
   g_block="warming up";
   RiskUpdate();

   if(_Period!=PERIOD_M5)
      LogEvent(StringFormat("NOTE: attached to %s but this EA reads M5 for execution "
                            "regardless of the chart timeframe",EnumToString(_Period)));

   if(Analyse()) SelfTest();
   LogEvent("v4.10 SMC/ICT scalper ready — sweep + MSS + FVG/OB, basket manager active");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Comment("");
   ClearObjects();
   LogEvent(StringFormat("stopped (reason %d) — entries this run: %d",reason,g_entries));
   LogClose();
  }

void OnTick(void)
  {
   RiskUpdate();

   SBasket b; GetBasket(b);
   if(b.count==0 && g_basketRisk>0.0)
     {
      g_basketRisk=0.0; g_firstLot=0.0;
      ArrayResize(g_partialDone,0); ArrayResize(g_beDone,0);
     }

   if(CircuitBreaker())
     {
      if(b.count>0) CloseBasket("risk circuit breaker");
      if(!g_breakerLogged){ LogEvent("CIRCUIT BREAKER ACTIVE"); g_breakerLogged=true; }
      g_block="circuit breaker";
      Panel(b);
      return;
     }
   g_breakerLogged=false;

   if(!Analyse()){ Panel(b); return; }

   datetime cur=(g_bars>0?g_t[0]:0);
   bool newBar=(cur!=g_lastBar && cur>0);
   if(newBar){ g_lastBar=cur; DrawZones(); }

   if(b.count>0)
     {
      ManageBasket(b);
      GetBasket(b);
     }

   if(g_view.setupDir==0)
     {
      Block(MissingLeg());
      Panel(b);
      return;
     }

   if(b.count==0)                       TryEnter(b,false);
   else if(ScaleInAllowed(b))           TryEnter(b,true);
   else                                 g_block="holding basket";

   Panel(b);
  }
//+------------------------------------------------------------------+
