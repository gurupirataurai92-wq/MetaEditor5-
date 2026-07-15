//+------------------------------------------------------------------+
//|                                               MedulaAnalysis.mqh |
//|  Analysis engines: Market State (§1), Structure (§2), Trend (§3),|
//|  Momentum (§4), Volatility (§5), Liquidity (§6), MTF (§7).       |
//+------------------------------------------------------------------+
#ifndef MEDULA_ANALYSIS_MQH
#define MEDULA_ANALYSIS_MQH

#include "MedulaTypes.mqh"
#include "MedulaIndicators.mqh"

class CAnalysis
  {
private:
   string            m_sym;
   ENUM_TIMEFRAMES   m_tf;
   SMedulaConfig     m_cfg;
   CIndicators      *m_ind;
   // swing storage for the Liquidity Engine (§6)
   double            m_swPrice[];
   bool              m_swIsHigh[];
   int               m_structDir;     // structural trend from BOS/CHoCH sequence
   double            m_peakMomAbs;    // rolling |momentum| peak, for exhaustion (§14)

public:
                     CAnalysis(void):m_ind(NULL),m_structDir(0),m_peakMomAbs(0.0){}

   bool Init(const string sym,const ENUM_TIMEFRAMES tf,const SMedulaConfig &cfg,CIndicators &ind)
     {
      m_sym=sym;
      m_tf=tf;
      m_cfg=cfg;
      m_ind=GetPointer(ind);
      return (m_ind!=NULL);
     }

   int    StructDir(void)  const { return m_structDir; }
   double PeakMomAbs(void) const { return m_peakMomAbs; }

   //--- run all analysis engines and fill the snapshot
   bool Update(SMarketSnapshot &snap)
     {
      double atr=m_ind.Atr(0);
      if(atr==EMPTY_VALUE || atr<=0.0)
         return false;
      double adx=m_ind.Adx(0);
      if(adx==EMPTY_VALUE)
         return false;

      MqlTick tick;
      if(!SymbolInfoTick(m_sym,tick))
         return false;

      snap.atr=atr;
      snap.adx=adx;
      snap.bid=tick.bid;
      snap.ask=tick.ask;
      snap.close=tick.bid;
      double pt=SymbolInfoDouble(m_sym,SYMBOL_POINT);
      snap.spreadPts=(pt>0.0 ? (tick.ask-tick.bid)/pt : 0.0);

      snap.er=EfficiencyRatio(m_sym,m_tf,m_cfg.erLen);   // §1

      UpdateVolatility(snap);   // §1, §5
      UpdateStructure(snap);    // §2
      UpdateTrend(snap);        // §3
      UpdateMomentum(snap);     // §4
      UpdateLiquidity(snap);    // §6
      UpdateMTF(snap);          // §7
      ClassifyRegime(snap);     // §1
      return true;
     }

private:
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
   void UpdateVolatility(SMarketSnapshot &snap)
     {
      int n=m_cfg.volPctBars;
      double a[];
      ArraySetAsSeries(a,true);
      if(CopyBuffer(m_ind.AtrHandle(),0,0,n+1,a)<n+1)
        {
         snap.vr=1.0;
         snap.volPercentile=50.0;
         snap.volSuitability=100.0;
         return;
        }
      int below=0;
      for(int i=1;i<=n;i++)
         if(a[i]<a[0])
            below++;
      snap.volPercentile=100.0*(double)below/(double)n;

      int ref=MathMin(m_cfg.volRefBars,n);
      double s=0.0;
      for(int i=0;i<ref;i++)
         s+=a[i];
      double atrRef=s/(double)ref;
      snap.vr=(atrRef>0.0 ? a[0]/atrRef : 1.0);

      // Gaussian suitability centered at the 55th percentile, sigma 30 (§5)
      double z=(snap.volPercentile-55.0)/30.0;
      snap.volSuitability=100.0*MathExp(-0.5*z*z);
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
      int n=ArraySize(m_swPrice);
      ArrayResize(m_swPrice,n+1);
      ArrayResize(m_swIsHigh,n+1);
      m_swPrice[n]=price;
      m_swIsHigh[n]=isHigh;
     }

   //--- Market Structure Engine (§2): swings, BOS, CHoCH, structure score.
   //    Replays the lookback window chronologically; a fractal only becomes
   //    tradable information k bars after it forms (causal confirmation).
   void UpdateStructure(SMarketSnapshot &snap)
     {
      snap.bullBos=false;  snap.bearBos=false;
      snap.bullChoch=false; snap.bearChoch=false;

      int bars=m_cfg.structLookback;
      double hi[],lo[],cl[];
      ArraySetAsSeries(hi,true);
      ArraySetAsSeries(lo,true);
      ArraySetAsSeries(cl,true);
      if(CopyHigh(m_sym,m_tf,0,bars,hi)<bars)  return;
      if(CopyLow(m_sym,m_tf,0,bars,lo)<bars)   return;
      if(CopyClose(m_sym,m_tf,0,bars,cl)<bars) return;

      int k=m_cfg.swingK;
      ArrayResize(m_swPrice,0);
      ArrayResize(m_swIsHigh,0);
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
            if(choch) { if(b==0) snap.bullChoch=true; }
            else      { PushInt(events,1); if(b==0) snap.bullBos=true; }
            lastSH=0.0;                // consume the level until a new swing confirms
           }
         if(lastSL>0.0 && cl[b]<lastSL)
           {
            bool choch=(trendDir==1);
            trendDir=-1;
            if(choch) { if(b==0) snap.bearChoch=true; }
            else      { PushInt(events,-1); if(b==0) snap.bearBos=true; }
            lastSL=0.0;
           }
        }

      int total=ArraySize(events);
      int nEv=MathMin(total,m_cfg.structEvents);
      int bull=0,bear=0;
      for(int i=total-nEv;i<total;i++)
        {
         if(events[i]>0) bull++;
         else            bear++;
        }
      snap.structureScore=100.0*(double)(bull-bear)/(double)(bull+bear+1);
      m_structDir=trendDir;
     }

   //--- Trend score core (§3), shared by chart TF and each higher TF.
   //    ADX (c1) and efficiency (c3) are strength-only, so they are signed
   //    by the EMA direction to keep the composite score directional.
   double TrendScoreCore(const double adx,const double e50_0,const double e50_n,
                         const double e20_0,const double atr,const double er)
     {
      if(atr<=0.0 || adx==EMPTY_VALUE || e50_0==EMPTY_VALUE ||
         e50_n==EMPTY_VALUE || e20_0==EMPTY_VALUE)
         return 0.0;
      double slope=(e50_0-e50_n)/((double)m_cfg.slopeBars*atr);
      double c1=MTanh(adx/25.0-1.0);
      double c2=MTanh(slope*10.0);
      double c3=MTanh((er-0.2)*5.0);
      double c4=(double)MSign(e20_0-e50_0);
      int dirSign=MSign(e20_0-e50_0);
      if(dirSign==0)
         dirSign=MSign(slope);
      return 100.0*(0.35*c1*dirSign+0.30*c2+0.20*c3*dirSign+0.15*c4);
     }

   void UpdateTrend(SMarketSnapshot &snap)
     {
      snap.trendScore=TrendScoreCore(snap.adx,
                                     m_ind.Ema50(0),
                                     m_ind.Ema50(m_cfg.slopeBars),
                                     m_ind.Ema20(0),
                                     snap.atr,
                                     snap.er);
      snap.trendDir=MSign(snap.trendScore);
     }

   //--- Momentum Engine (§4)
   void UpdateMomentum(SMarketSnapshot &snap)
     {
      snap.momentumScore=0.0;
      snap.momentumAccel=0.0;
      int n=m_cfg.rocLen;
      double c[];
      ArraySetAsSeries(c,true);
      if(CopyClose(m_sym,m_tf,0,n+2,c)<n+2)
         return;
      if(c[n]<=0.0 || c[n+1]<=0.0 || snap.atr<=0.0)
         return;
      double roc0=(c[0]-c[n])/c[n]*100.0;
      double roc1=(c[1]-c[n+1])/c[n+1]*100.0;

      double rsi=m_ind.Rsi(0);
      double m0=m_ind.MacdMain(0),s0=m_ind.MacdSignal(0);
      double m1=m_ind.MacdMain(1),s1=m_ind.MacdSignal(1);
      if(rsi==EMPTY_VALUE || m0==EMPTY_VALUE || s0==EMPTY_VALUE ||
         m1==EMPTY_VALUE || s1==EMPTY_VALUE)
         return;
      double rsiDev=rsi-50.0;
      double macdSlope=(m0-s0)-(m1-s1);

      snap.momentumScore=100.0*MTanh(0.40*(rsiDev/50.0)
                                    +0.30*MTanh(roc0/2.0)
                                    +0.30*MTanh(macdSlope/(0.1*snap.atr)));
      snap.momentumAccel=roc0-roc1;

      // rolling peak with slow decay, used by the exhaustion rule (§14)
      m_peakMomAbs=MathMax(MathAbs(snap.momentumScore),m_peakMomAbs*0.995);
     }

   //--- Liquidity Engine (§6): swing-point pools within 3*ATR of price
   void UpdateLiquidity(SMarketSnapshot &snap)
     {
      double d=m_cfg.liqRangeAtr*snap.atr;
      double above=0.0,below=0.0;
      int n=ArraySize(m_swPrice);
      for(int i=0;i<n;i++)
        {
         double p=m_swPrice[i];
         if(p>snap.close && p-snap.close<=d)
            above+=1.0;
         else if(p<snap.close && snap.close-p<=d)
            below+=1.0;
        }
      snap.liquidityScore=100.0*MTanh((below-above)/(below+above+1.0));
     }

   //--- Multi-Timeframe Engine (§7): D1 0.40, H4 0.30, H1 0.20, chart 0.10
   void UpdateMTF(SMarketSnapshot &snap)
     {
      double w[4]={0.40,0.30,0.20,0.10};
      double align=0.0;
      for(int i=0;i<3;i++)
        {
         double er=EfficiencyRatio(m_sym,m_ind.Mtf(i),m_cfg.erLen);
         double ts=TrendScoreCore(m_ind.AdxTF(i,0),
                                  m_ind.Ema50TF(i,0),
                                  m_ind.Ema50TF(i,m_cfg.slopeBars),
                                  m_ind.Ema20TF(i,0),
                                  m_ind.AtrTF(i,0),
                                  er);
         align+=w[i]*(double)MSign(ts);
        }
      align+=w[3]*(double)snap.trendDir;
      snap.mtfAlignment=align;
      snap.mtfConfluence=MathAbs(align)*100.0;
     }

   //--- Market State Engine (§1) with the spec's priority ordering
   void ClassifyRegime(SMarketSnapshot &snap)
     {
      bool trending=(snap.adx>25.0 && snap.er>0.30);
      bool ranging =(snap.adx<20.0 && snap.er<0.20);
      bool hiVol   =(snap.volPercentile>90.0);
      bool loVol   =(snap.volPercentile<10.0);

      double bu=m_ind.BandUpper(0),bl=m_ind.BandLower(0);
      bool breakout=false;
      if(bu!=EMPTY_VALUE && bl!=EMPTY_VALUE)
         breakout=(snap.vr>1.5 &&
                   ((snap.close>bu && snap.momentumScore>0.0) ||
                    (snap.close<bl && snap.momentumScore<0.0)));

      bool reversal=(snap.bullChoch && snap.momentumScore>0.0) ||
                    (snap.bearChoch && snap.momentumScore<0.0);

      if(reversal)      snap.regime=REGIME_REVERSAL;
      else if(breakout) snap.regime=REGIME_BREAKOUT;
      else if(hiVol)    snap.regime=REGIME_HIGH_VOL;
      else if(trending) snap.regime=REGIME_TRENDING;
      else if(ranging)  snap.regime=REGIME_RANGING;
      else if(loVol)    snap.regime=REGIME_LOW_VOL;
      else              snap.regime=REGIME_NEUTRAL;
     }
  };

#endif // MEDULA_ANALYSIS_MQH
