//+------------------------------------------------------------------+
//|                                             MedulaConfidence.mqh |
//|  Confidence Engine (§8) and Decision Engine (§9).                |
//+------------------------------------------------------------------+
#ifndef MEDULA_CONFIDENCE_MQH
#define MEDULA_CONFIDENCE_MQH

#include "MedulaTypes.mqh"

//--- Confidence Engine (§8): weighted evidence -> tanh squash -> penalties
double ComputeConfidence(SMarketSnapshot &snap,const double execQuality,const SMedulaConfig &cfg)
  {
   double raw=cfg.w1*(snap.structureScore/100.0)
             +cfg.w2*(snap.trendScore/100.0)
             +cfg.w3*(snap.momentumScore/100.0)
             +cfg.w4*(snap.liquidityScore/100.0)
             +cfg.w5*snap.mtfAlignment;

   // gain (§8): weights sum to 1, so |raw| <= 1 and tanh alone could never
   // exceed 76 — the gain maps strong agreement onto the usable 0-100 scale
   snap.confidenceDir=100.0*MTanh(cfg.confGain*raw);
   double mag=MathAbs(snap.confidenceDir);

   double pVol   =snap.volSuitability/100.0;
   double pSpread=(cfg.maxSpreadPoints>0.0
                   ? MClamp(1.0-snap.spreadPts/cfg.maxSpreadPoints,0.0,1.0)
                   : 1.0);
   double pExec  =MClamp(execQuality/100.0,0.0,1.0);

   snap.confidenceFinal=mag*pVol*pSpread*pExec;
   return snap.confidenceFinal;
  }

//--- Decision Engine (§9): threshold + hysteresis + MTF veto
ENUM_DECISION Decide(const SMarketSnapshot &snap,const bool inTrade,const int basketDir,
                     const double threshold,const SMedulaConfig &cfg)
  {
   int dir=MSign(snap.confidenceDir);

   if(!inTrade)
     {
      if(dir!=0 && snap.confidenceFinal>=threshold)
        {
         // MTF veto (§7): block entries against a confident higher-TF bias
         if(MSign(snap.mtfAlignment)!=dir && snap.mtfConfluence>cfg.mtfVetoConfluence)
            return DECISION_WAIT;
         return (dir>0 ? DECISION_BUY : DECISION_SELL);
        }
      return DECISION_WAIT;
     }

   // in trade: exit on confidence collapse or a confident direction flip
   if(snap.confidenceFinal<threshold-cfg.hysteresis)
      return DECISION_EXIT;
   if(dir!=0 && basketDir!=0 && dir!=basketDir)
      return DECISION_EXIT;
   return DECISION_HOLD;
  }

#endif // MEDULA_CONFIDENCE_MQH
