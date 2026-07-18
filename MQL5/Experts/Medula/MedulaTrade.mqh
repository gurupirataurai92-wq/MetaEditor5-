//+------------------------------------------------------------------+
//|                                                  MedulaTrade.mqh |
//|  Execution Engine (§10), Basket Management (§11),                |
//|  Position Scaling (§12) and Exit Engine (§14).                   |
//+------------------------------------------------------------------+
#ifndef MEDULA_TRADE_MQH
#define MEDULA_TRADE_MQH

#include <Trade\Trade.mqh>
#include "MedulaTypes.mqh"

class CTradeManager
  {
private:
   CTrade            m_trade;
   string            m_sym;
   SMedulaConfig     m_cfg;
   CLogger          *m_log;
   // per-basket persistent state (reset when the basket goes flat)
   double            m_entryConfidence;
   double            m_initialRiskAmt;
   double            m_initialLot;
   double            m_trailMultEff;
   // execution-quality ring buffers (§10)
   int               m_fills[];
   double            m_slips[];
   int               m_execHead;
   int               m_execCount;

public:
                     CTradeManager(void):m_log(NULL),m_entryConfidence(0.0),
                                         m_initialRiskAmt(0.0),m_initialLot(0.0),
                                         m_trailMultEff(0.0),m_execHead(0),m_execCount(0){}

   bool Init(const string sym,const SMedulaConfig &cfg,CLogger &log)
     {
      m_sym=sym;
      m_cfg=cfg;
      m_log=GetPointer(log);
      m_trailMultEff=cfg.trailAtrMult;
      int w=MathMax(cfg.execWindow,1);
      ArrayResize(m_fills,w);
      ArrayResize(m_slips,w);
      ArrayInitialize(m_fills,0);
      ArrayInitialize(m_slips,0.0);
      m_trade.SetExpertMagicNumber((ulong)cfg.magic);
      m_trade.SetDeviationInPoints((ulong)cfg.deviationPts);
      m_trade.SetTypeFillingBySymbol(m_sym);
      return true;
     }

   double EntryConfidence(void) const { return m_entryConfidence; }
   double InitialLot(void)      const { return m_initialLot; }
   double InitialRiskAmt(void)  const { return m_initialRiskAmt; }

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
         if(PositionGetString(POSITION_SYMBOL)!=m_sym) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic) continue;
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
         m_entryConfidence=0.0;
         m_initialRiskAmt=0.0;
         m_initialLot=0.0;
         m_trailMultEff=m_cfg.trailAtrMult;
        }
     }

   // after a terminal restart the in-memory basket state is gone; rebuild
   // conservative estimates from what is recoverable
   void RecoverIfNeeded(const SBasket &b,const double conf,const double equity)
     {
      if(b.count>0 && m_initialRiskAmt<=0.0)
        {
         m_initialLot=(b.firstEntryVolume>0.0 ? b.firstEntryVolume
                                              : b.totalVolume/MathMax(b.count,1));
         m_initialRiskAmt=equity*m_cfg.riskPct/100.0;
         m_entryConfidence=(conf>0.0 ? conf : m_cfg.confThreshold);
         m_trailMultEff=m_cfg.trailAtrMult;
        }
     }

   //--- Execution Quality (§10)
   void RecordExecution(const bool filled,const double slipPts)
     {
      int w=ArraySize(m_fills);
      if(w<=0) return;
      m_fills[m_execHead]=(filled ? 1 : 0);
      m_slips[m_execHead]=(filled ? slipPts : 0.0);
      m_execHead=(m_execHead+1)%w;
      if(m_execCount<w)
         m_execCount++;
     }

   double ExecutionQuality(void)
     {
      if(m_execCount==0)
         return 100.0;
      int filled=0;
      double slipSum=0.0;
      for(int i=0;i<m_execCount;i++)
        {
         if(m_fills[i]==1)
           {
            filled++;
            slipSum+=m_slips[i];
           }
        }
      double fillRatio=(double)filled/(double)m_execCount;
      double avgSlip=(filled>0 ? slipSum/filled : 0.0);
      double slipPen=(m_cfg.maxSlippagePts>0.0
                      ? MClamp(1.0-avgSlip/m_cfg.maxSlippagePts,0.0,1.0)
                      : 1.0);
      return 100.0*fillRatio*slipPen;
     }

   // §10 circuit breaker: suspend entries once the window is full and degraded
   bool ExecutionHealthy(void)
     {
      if(m_execCount<ArraySize(m_fills))
         return true;
      return ExecutionQuality()>=m_cfg.execSuspendBelow;
     }

   //--- Open a market position with ATR-based SL/TP (§10, §14)
   bool Open(const int dir,const double lots,const double atr,const double conf,
             const double riskAmt,const bool isInitial,const int basketCount)
     {
      MqlTick t;
      if(!SymbolInfoTick(m_sym,t))
         return false;
      int digits=(int)SymbolInfoInteger(m_sym,SYMBOL_DIGITS);
      double pt=SymbolInfoDouble(m_sym,SYMBOL_POINT);
      double price=(dir>0 ? t.ask : t.bid);
      double sl=NormalizeDouble(dir>0 ? price-m_cfg.slAtrMult*atr
                                      : price+m_cfg.slAtrMult*atr,digits);
      double tp=NormalizeDouble(dir>0 ? price+m_cfg.tpAtrMult*atr
                                      : price-m_cfg.tpAtrMult*atr,digits);
      string comment=StringFormat("MDL|%d|%.0f",basketCount,conf);

      bool ok=(dir>0 ? m_trade.Buy(lots,m_sym,0.0,sl,tp,comment)
                     : m_trade.Sell(lots,m_sym,0.0,sl,tp,comment));
      uint rc=m_trade.ResultRetcode();
      bool filled=ok && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL ||
                         rc==TRADE_RETCODE_PLACED);

      double slip=0.0;
      if(filled && pt>0.0)
         slip=MathAbs(m_trade.ResultPrice()-price)/pt;
      RecordExecution(filled,slip);

      if(!filled)
        {
         if(m_log!=NULL)
            m_log.Event(StringFormat("order rejected: dir=%d lots=%.2f rc=%u",dir,lots,rc));
         return false;
        }

      if(isInitial)
        {
         m_entryConfidence=conf;
         m_initialRiskAmt=riskAmt;
         m_initialLot=lots;
         m_trailMultEff=m_cfg.trailAtrMult;
        }
      if(m_log!=NULL)
         m_log.Event(StringFormat("%s %.2f @ %.5f sl=%.5f tp=%.5f conf=%.1f slip=%.1fpts",
                                  dir>0?"BUY":"SELL",lots,m_trade.ResultPrice(),sl,tp,conf,slip));
      return true;
     }

   //--- close every position in the basket (§11)
   void CloseBasket(const string reason)
     {
      bool any=false;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic) continue;
         m_trade.PositionClose(tk);
         any=true;
        }
      if(any && m_log!=NULL)
         m_log.Event("basket closed: "+reason);
     }

   //--- Scaling preconditions (§12); risk caps are checked by the caller
   bool ScaleInAllowed(const SBasket &b,const SMarketSnapshot &snap)
     {
      if(b.count==0)
         return false;
      if(b.count-1>=m_cfg.maxScaleIns)
         return false;
      int dir=MSign(snap.confidenceDir);
      if(dir!=b.dir)
         return false;                                    // thesis no longer valid
      if(m_entryConfidence>0.0 &&
         snap.confidenceFinal<m_cfg.scaleConfK*m_entryConfidence)
         return false;                                    // conviction has weakened
      double px=(b.dir>0 ? snap.ask : snap.bid);
      if(MathAbs(px-b.lastEntryPrice)<m_cfg.scaleSpacingAtr*snap.atr)
         return false;                                    // spacing not reached
      return true;
     }

   //--- currency risk currently committed by this symbol's basket
   double BasketRiskUsed(void)
     {
      return RiskUsedFiltered(true);
     }

   //--- currency risk committed across ALL symbols with our magic (§13)
   double AccountRiskUsed(void)
     {
      return RiskUsedFiltered(false);
     }

   //--- Exit Engine (§14): target, invalidation, time stop, trailing
   void ManageExits(const SMarketSnapshot &snap,const SBasket &b,const double peakMomAbs)
     {
      if(b.count==0)
         return;

      // 1) basket profit target in R multiples (§11)
      if(m_initialRiskAmt>0.0)
        {
         double rMult=b.floatPL/m_initialRiskAmt;
         if(rMult>=m_cfg.basketTargetR)
           {
            CloseBasket(StringFormat("basket target %.1fR reached",rMult));
            return;
           }
        }

      // 2) structure invalidation: CHoCH against the basket (§2, §14)
      if((b.dir>0 && snap.bearChoch) || (b.dir<0 && snap.bullChoch))
        {
         CloseBasket("structure invalidation (CHoCH)");
         return;
        }

      // 3) time stop (§14)
      int barsIn=(int)((TimeCurrent()-b.firstEntryTime)/MathMax(PeriodSeconds(PERIOD_CURRENT),1));
      if(barsIn>m_cfg.maxBarsInTrade && b.floatPL<m_cfg.minAcceptPL)
        {
         CloseBasket(StringFormat("time stop after %d bars",barsIn));
         return;
        }

      // 4) momentum exhaustion tightens the trail rather than hard-exiting (§14)
      if(peakMomAbs>70.0 &&
         MSign(snap.momentumAccel)!=0 && MSign(snap.momentumScore)!=0 &&
         MSign(snap.momentumAccel)!=MSign(snap.momentumScore))
         m_trailMultEff=MathMin(m_trailMultEff,m_cfg.trailAtrMult*0.6);

      // 5) Chandelier trailing stop per position (§14)
      TrailPositions(snap,b);
     }

private:
   double RiskUsedFiltered(const bool thisSymbolOnly)
     {
      double used=0.0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic) continue;
         string ps=PositionGetString(POSITION_SYMBOL);
         if(thisSymbolOnly && ps!=m_sym) continue;
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
            used+=AccountInfoDouble(ACCOUNT_EQUITY)*m_cfg.riskPct/100.0;
        }
      return used;
     }

   void TrailPositions(const SMarketSnapshot &snap,const SBasket &b)
     {
      int digits=(int)SymbolInfoInteger(m_sym,SYMBOL_DIGITS);
      double pt=SymbolInfoDouble(m_sym,SYMBOL_POINT);
      double stopsLevel=(double)SymbolInfoInteger(m_sym,SYMBOL_TRADE_STOPS_LEVEL)*pt;
      double newSL=0.0;

      if(b.dir>0)
        {
         int idx=iHighest(m_sym,PERIOD_CURRENT,MODE_HIGH,m_cfg.trailLookback,0);
         if(idx<0) return;
         double hh=iHigh(m_sym,PERIOD_CURRENT,idx);
         newSL=NormalizeDouble(hh-m_trailMultEff*snap.atr,digits);
         if(newSL>=snap.bid-stopsLevel)
            return;
        }
      else
        {
         int idx=iLowest(m_sym,PERIOD_CURRENT,MODE_LOW,m_cfg.trailLookback,0);
         if(idx<0) return;
         double ll=iLow(m_sym,PERIOD_CURRENT,idx);
         newSL=NormalizeDouble(ll+m_trailMultEff*snap.atr,digits);
         if(newSL<=snap.ask+stopsLevel)
            return;
        }

      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic) continue;
         double curSL=PositionGetDouble(POSITION_SL);
         double curTP=PositionGetDouble(POSITION_TP);
         bool improve=(b.dir>0 ? (curSL<=0.0 || newSL>curSL+pt)
                               : (curSL<=0.0 || newSL<curSL-pt));
         if(improve)
            m_trade.PositionModify(tk,newSL,curTP);
        }
     }
  };

#endif // MEDULA_TRADE_MQH
