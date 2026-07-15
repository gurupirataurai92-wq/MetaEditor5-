//+------------------------------------------------------------------+
//|                                                   MedulaRisk.mqh |
//|  Risk Management (§13), Session Intelligence (§16),              |
//|  Correlation (§17) and sizing helpers (§13, §15).                |
//+------------------------------------------------------------------+
#ifndef MEDULA_RISK_MQH
#define MEDULA_RISK_MQH

#include "MedulaTypes.mqh"

class CRisk
  {
private:
   string            m_sym;
   SMedulaConfig     m_cfg;
   double            m_dayStartEquity;
   int               m_dayKey;
   double            m_peakEquity;
   bool              m_breakerLatched;

public:
                     CRisk(void):m_dayStartEquity(0.0),m_dayKey(-1),
                                 m_peakEquity(0.0),m_breakerLatched(false){}

   bool Init(const string sym,const SMedulaConfig &cfg)
     {
      m_sym=sym;
      m_cfg=cfg;
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      m_dayStartEquity=eq;
      m_peakEquity=eq;
      m_dayKey=-1;
      m_breakerLatched=false;
      Update();
      return true;
     }

   //--- track day boundary and equity peak (§13)
   void Update(void)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(),dt);
      int key=dt.year*1000+dt.day_of_year;
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(key!=m_dayKey)
        {
         m_dayKey=key;
         m_dayStartEquity=eq;
         m_breakerLatched=false;     // daily-loss breaker resets each day
        }
      if(eq>m_peakEquity)
         m_peakEquity=eq;
     }

   //--- Circuit breaker (§13): daily loss limit OR max drawdown from peak
   bool CircuitBreaker(void)
     {
      if(m_breakerLatched)
         return true;
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      bool daily=(m_dayStartEquity-eq)>=m_dayStartEquity*m_cfg.dailyLossPct/100.0;
      bool dd   =(m_peakEquity-eq)>=m_peakEquity*m_cfg.maxDDPct/100.0;
      if(daily || dd)
         m_breakerLatched=true;
      return m_breakerLatched;
     }

   //--- Session Intelligence (§16), hours in GMT
   double SessionMultiplier(void)
     {
      if(!m_cfg.useSessions)
         return 1.0;
      MqlDateTime g;
      TimeToStruct(TimeGMT(),g);
      int h=g.hour;
      if(h>=7  && h<12) return m_cfg.sessLondon;
      if(h>=12 && h<16) return m_cfg.sessOverlap;
      if(h>=16 && h<21) return m_cfg.sessNewYork;
      if(h>=21)         return m_cfg.sessDead;
      return m_cfg.sessAsian;      // 0..6
     }

   //--- Regime-based risk modulation (spec §1 behavior table)
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
      double tickVal=SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_VALUE);
      double tickSz =SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_SIZE);
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
      double tickVal=SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_VALUE);
      double tickSz =SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_SIZE);
      if(tickVal<=0.0 || tickSz<=0.0)
         return 0.0;
      return slDistPrice/tickSz*tickVal*lots;
     }

   //--- broker-constraint normalization; min-lot override keeps small
   //    accounts tradable (explicit opt-in because it raises risk above plan)
   double NormalizeLots(double lots)
     {
      double step=SymbolInfoDouble(m_sym,SYMBOL_VOLUME_STEP);
      double minL=SymbolInfoDouble(m_sym,SYMBOL_VOLUME_MIN);
      double maxL=SymbolInfoDouble(m_sym,SYMBOL_VOLUME_MAX);
      if(step<=0.0)
         step=0.01;
      lots=MathFloor(lots/step+1e-9)*step;
      if(lots<minL)
         return (m_cfg.allowMinLot ? minL : 0.0);
      return MathMin(lots,maxL);
     }

   //--- §10 pre-trade margin validation with safety factor
   bool MarginOK(const int dir,const double lots)
     {
      MqlTick t;
      if(!SymbolInfoTick(m_sym,t))
         return false;
      double price=(dir>0 ? t.ask : t.bid);
      double margin=0.0;
      if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,m_sym,lots,price,margin))
         return false;
      return AccountInfoDouble(ACCOUNT_MARGIN_FREE)>=margin*m_cfg.marginSafety;
     }

   //--- Correlation Engine (§17): soft dampener on confidence.
   //    Scans open positions on OTHER symbols carrying our magic number.
   double CorrelationDampener(const int dir,const long magic)
     {
      if(!m_cfg.useCorrelation)
         return 1.0;
      double damp=1.0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=magic) continue;
         string ps=PositionGetString(POSITION_SYMBOL);
         if(ps==m_sym) continue;
         double r=PearsonReturns(m_sym,ps,m_cfg.corrBars,(ENUM_TIMEFRAMES)_Period);
         if(MathAbs(r)<=m_cfg.corrThreshold) continue;
         int pdir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
         if(pdir*MSign(r)==dir)
           {
            double x=MClamp((MathAbs(r)-m_cfg.corrThreshold)/(1.0-m_cfg.corrThreshold),0.0,1.0);
            damp=MathMin(damp,1.0-0.3*x);
           }
        }
      return damp;
     }

   //--- Correlation hard veto (§17): too many same-direction correlated legs
   bool CorrelationVeto(const int dir,const long magic)
     {
      if(!m_cfg.useCorrelation)
         return false;
      int correlated=0;
      string counted="";
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=magic) continue;
         string ps=PositionGetString(POSITION_SYMBOL);
         if(ps==m_sym) continue;
         if(StringFind(counted,"|"+ps+"|")>=0) continue;    // one count per symbol
         double r=PearsonReturns(m_sym,ps,m_cfg.corrBars,(ENUM_TIMEFRAMES)_Period);
         if(MathAbs(r)<=m_cfg.corrThreshold) continue;
         int pdir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
         if(pdir*MSign(r)==dir)
           {
            correlated++;
            counted+="|"+ps+"|";
           }
        }
      return (correlated>=m_cfg.maxCorrelated);
     }

private:
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
  };

#endif // MEDULA_RISK_MQH
