//+------------------------------------------------------------------+
//|                                              MedulaAnalytics.mqh |
//|  Performance Analytics (§18), Kelly cap input (§15) and          |
//|  Adaptive Parameter Engine (§19).                                |
//+------------------------------------------------------------------+
#ifndef MEDULA_ANALYTICS_MQH
#define MEDULA_ANALYTICS_MQH

#include "MedulaTypes.mqh"

class CAnalytics
  {
private:
   string            m_sym;
   long              m_magic;
   int               m_recentN;
   double            m_profits[];       // closed-trade P/L, chronological
   double            m_grossWin,m_grossLoss;
   int               m_wins,m_losses;
   double            m_expAll,m_expRecent;

public:
                     CAnalytics(void):m_magic(0),m_recentN(20),
                                      m_grossWin(0.0),m_grossLoss(0.0),
                                      m_wins(0),m_losses(0),
                                      m_expAll(0.0),m_expRecent(0.0){}

   void Init(const string sym,const long magic,const int recentN)
     {
      m_sym=sym;
      m_magic=magic;
      m_recentN=MathMax(recentN,1);
     }

   //--- rebuild statistics from the account's deal history (§18)
   void Refresh(void)
     {
      ArrayResize(m_profits,0);
      m_grossWin=0.0; m_grossLoss=0.0;
      m_wins=0; m_losses=0;
      if(!HistorySelect(0,TimeCurrent()+60))
         return;
      int total=HistoryDealsTotal();
      for(int i=0;i<total;i++)
        {
         ulong tk=HistoryDealGetTicket(i);
         if(tk==0) continue;
         if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=m_magic) continue;
         if(HistoryDealGetString(tk,DEAL_SYMBOL)!=m_sym) continue;
         long entry=HistoryDealGetInteger(tk,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
         double p=HistoryDealGetDouble(tk,DEAL_PROFIT)
                 +HistoryDealGetDouble(tk,DEAL_SWAP)
                 +HistoryDealGetDouble(tk,DEAL_COMMISSION);
         int n=ArraySize(m_profits);
         ArrayResize(m_profits,n+1);
         m_profits[n]=p;
         if(p>=0.0) { m_wins++;   m_grossWin+=p; }
         else       { m_losses++; m_grossLoss+=-p; }
        }
      int n=ArraySize(m_profits);
      double s=0.0;
      for(int i=0;i<n;i++)
         s+=m_profits[i];
      m_expAll=(n>0 ? s/n : 0.0);
      int rN=MathMin(m_recentN,n);
      double sr=0.0;
      for(int i=n-rN;i<n;i++)
         sr+=m_profits[i];
      m_expRecent=(rN>0 ? sr/rN : 0.0);
     }

   int    Trades(void)          const { return ArraySize(m_profits); }
   double WinRate(void)         const { int n=Trades(); return (n>0 ? (double)m_wins/n : 0.0); }
   double ProfitFactor(void)    const { return (m_grossLoss>0.0 ? m_grossWin/m_grossLoss : (m_grossWin>0.0 ? 999.0 : 0.0)); }
   double ExpectancyAll(void)   const { return m_expAll; }
   double ExpectancyRecent(void)const { return m_expRecent; }
   double AvgWin(void)          const { return (m_wins>0   ? m_grossWin/m_wins    : 0.0); }
   double AvgLoss(void)         const { return (m_losses>0 ? m_grossLoss/m_losses : 0.0); }

   //--- fractional Kelly sizing cap (§15): f = (W*b - (1-W)) / b
   double KellyFraction(const double frac,const double capFrac)
     {
      if(m_wins==0 || m_losses==0)
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

   //--- Adaptive Parameter Engine (§19): bounded, EMA-smoothed threshold
   //    update. Recent underperformance vs. baseline raises the confidence
   //    threshold (system gets more selective); outperformance lowers it.
   void AdaptThreshold(double &thr,const double riskUnit,const SMedulaConfig &cfg)
     {
      if(Trades()<2*cfg.adaptRecentN)
         return;
      double g=m_expAll-m_expRecent;                  // >0 means recent is worse
      double unit=(riskUnit>0.0 ? riskUnit : 1.0);
      double target=MClamp(thr+cfg.adaptEta*MTanh(g/unit),cfg.thrMin,cfg.thrMax);
      thr=MClamp(cfg.adaptAlpha*target+(1.0-cfg.adaptAlpha)*thr,cfg.thrMin,cfg.thrMax);
     }

   string Summary(void) const
     {
      return StringFormat("trades=%d winRate=%.1f%% PF=%.2f expAll=%.2f expRecent=%.2f",
                          Trades(),WinRate()*100.0,ProfitFactor(),m_expAll,m_expRecent);
     }
  };

#endif // MEDULA_ANALYTICS_MQH
