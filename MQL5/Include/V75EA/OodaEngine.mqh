//+------------------------------------------------------------------+
//|                                                   OodaEngine.mqh |
//|  OODA decision cycle: Observe -> Orient -> Decide (Act happens   |
//|  in the main EA via CTradeManager), plus the Feedback stage that |
//|  makes God mode adaptive: a rolling win/loss buffer eases the    |
//|  confluence threshold and boosts risk on hot streaks, and        |
//|  tightens/cuts them faster on cold streaks. All adaptation is    |
//|  bounded — the SafetyGuard and RiskManager hard caps still rule. |
//+------------------------------------------------------------------+
#ifndef V75EA_OODA_ENGINE_MQH
#define V75EA_OODA_ENGINE_MQH

#property strict

#include <V75EA\Types.mqh>
#include <V75EA\RegimeDetector.mqh>
#include <V75EA\ConfluenceEngine.mqh>

//--- snapshot of market state gathered in the Observe stage
struct SObservation
  {
   double      atr;
   ENUM_REGIME regime;
   long        spreadPoints;
  };

//--- output of the Decide stage
struct SDecision
  {
   ENUM_SIGNAL signal;
   double      confidence;
   double      riskPercent;   // requested risk; RiskManager still hard-caps it
   double      slDistance;
   double      tpDistance;
   bool        useTrailing;
   string      reason;
  };

#define OODA_RESULT_CAPACITY 32

class COodaEngine
  {
private:
   string             m_symbol;
   CRegimeDetector   *m_regime;
   CConfluenceEngine *m_confluence;

   //--- adaptive state
   bool     m_godMode;
   double   m_baseConfidence;     // threshold when there is no streak evidence
   double   m_minConfidence;      // most aggressive threshold adaptation may reach
   double   m_maxConfidence;      // most defensive threshold after losses
   double   m_dynamicConfidence;
   double   m_riskBoostMax;       // risk multiplier ceiling on winning streaks
   double   m_riskMultiplier;

   int      m_results[OODA_RESULT_CAPACITY]; // ring buffer: 1 = win, -1 = loss
   int      m_resultCount;
   int      m_resultHead;

public:
                     COodaEngine(void) : m_regime(NULL), m_confluence(NULL), m_godMode(false),
                                          m_dynamicConfidence(0.6), m_riskMultiplier(1.0),
                                          m_resultCount(0), m_resultHead(0) {}

   bool              Init(const string symbol, CRegimeDetector *regime, CConfluenceEngine *confluence,
                           const bool godMode, const double baseConfidence,
                           const double minConfidence, const double maxConfidence,
                           const double riskBoostMax)
     {
      m_symbol            = symbol;
      m_regime            = regime;
      m_confluence        = confluence;
      m_godMode           = godMode;
      m_baseConfidence    = baseConfidence;
      m_minConfidence     = MathMin(minConfidence, baseConfidence);
      m_maxConfidence     = MathMax(maxConfidence, baseConfidence);
      m_dynamicConfidence = baseConfidence;
      m_riskBoostMax      = MathMax(1.0, riskBoostMax);
      m_riskMultiplier    = 1.0;
      m_resultCount       = 0;
      m_resultHead        = 0;
      ArrayInitialize(m_results, 0);

      if(m_regime == NULL || m_confluence == NULL)
        {
         Print("COodaEngine: NULL module reference");
         return false;
        }
      return true;
     }

   //--- OBSERVE: gather the market snapshot the rest of the cycle runs on
   bool              Observe(SObservation &obs)
     {
      obs.atr          = m_confluence.GetAtr();
      obs.regime       = m_regime.Classify();
      obs.spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      return (obs.atr > 0.0);
     }

   //--- ORIENT + DECIDE: confluence evaluation under the adaptive threshold,
   //    then translate the verdict into concrete trade parameters
   bool              Decide(const SObservation &obs, SDecision &out,
                             const double atrStopMult, const double atrTpMult,
                             const double baseRiskPercent)
     {
      m_confluence.SetMinConfidence(m_dynamicConfidence);
      SConfluenceResult c = m_confluence.Evaluate();

      out.signal      = c.signal;
      out.confidence  = c.confidence;
      out.slDistance  = obs.atr * atrStopMult;

      //--- in god mode, stretch targets and trail when the regime is hot
      double tpMult = atrTpMult;
      bool hotRegime = (obs.regime == REGIME_BREAKOUT ||
                        obs.regime == REGIME_STRONG_UPTREND ||
                        obs.regime == REGIME_STRONG_DOWNTREND);
      if(m_godMode && hotRegime)
         tpMult *= 1.5;
      out.tpDistance  = obs.atr * tpMult;
      out.useTrailing = m_godMode;

      //--- risk request: base * streak multiplier * confidence scaling.
      //    RiskManager clamps this to its hard cap regardless.
      out.riskPercent = baseRiskPercent * m_riskMultiplier * (0.5 + 0.5 * c.confidence);

      out.reason = c.reason + StringFormat(" | ooda: thr=%.2f riskX=%.2f",
                                           m_dynamicConfidence, m_riskMultiplier);
      return (out.signal != SIGNAL_NONE);
     }

   //--- FEEDBACK: closes the loop; call on every realized trade result
   void              RegisterTradeResult(const bool win)
     {
      m_results[m_resultHead] = win ? 1 : -1;
      m_resultHead = (m_resultHead + 1) % OODA_RESULT_CAPACITY;
      if(m_resultCount < OODA_RESULT_CAPACITY)
         m_resultCount++;
      Adapt();
     }

   double            DynamicConfidence(void) const { return m_dynamicConfidence; }
   double            RiskMultiplier(void)    const { return m_riskMultiplier; }

private:
   //--- asymmetric adaptation: loosen slowly on evidence of edge,
   //    tighten and de-risk fast when the edge fades
   void              Adapt(void)
     {
      if(!m_godMode)
         return;
      if(m_resultCount < 8) // not enough evidence to adapt yet
         return;

      int wins = 0;
      for(int i = 0; i < m_resultCount; i++)
         if(m_results[i] == 1)
            wins++;
      double winRate = (double)wins / m_resultCount;

      if(winRate >= 0.55)
        {
         m_dynamicConfidence = MathMax(m_minConfidence, m_dynamicConfidence - 0.02);
         m_riskMultiplier    = MathMin(m_riskBoostMax, m_riskMultiplier + 0.05);
        }
      else if(winRate <= 0.45)
        {
         m_dynamicConfidence = MathMin(m_maxConfidence, m_dynamicConfidence + 0.03);
         m_riskMultiplier    = MathMax(0.5, m_riskMultiplier - 0.10);
        }
      else
        {
         //--- drift back toward neutral in the dead zone
         if(m_dynamicConfidence < m_baseConfidence) m_dynamicConfidence = MathMin(m_baseConfidence, m_dynamicConfidence + 0.01);
         if(m_dynamicConfidence > m_baseConfidence) m_dynamicConfidence = MathMax(m_baseConfidence, m_dynamicConfidence - 0.01);
         if(m_riskMultiplier > 1.0) m_riskMultiplier = MathMax(1.0, m_riskMultiplier - 0.05);
         if(m_riskMultiplier < 1.0) m_riskMultiplier = MathMin(1.0, m_riskMultiplier + 0.05);
        }
     }
  };

#endif // V75EA_OODA_ENGINE_MQH
