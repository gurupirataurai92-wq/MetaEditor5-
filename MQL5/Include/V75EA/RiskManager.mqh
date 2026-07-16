//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh |
//|  Converts a stop-loss distance into a position size that risks  |
//|  a fixed percentage of current equity, clamped to broker limits.|
//+------------------------------------------------------------------+
#ifndef V75EA_RISK_MANAGER_MQH
#define V75EA_RISK_MANAGER_MQH

#property strict

class CRiskManager
  {
private:
   string m_symbol;
   double m_riskPercent;
   double m_maxRiskPercent;
   double m_minLot;
   double m_maxLot;
   double m_lotStep;

public:
                     CRiskManager(void) : m_riskPercent(1.0), m_maxRiskPercent(2.0), m_minLot(0.01), m_maxLot(100.0), m_lotStep(0.01) {}

   void              Init(const string symbol, const double riskPercent, const double maxRiskPercent)
     {
      m_symbol         = symbol;
      m_maxRiskPercent = maxRiskPercent;
      m_riskPercent    = MathMax(0.0, MathMin(riskPercent, maxRiskPercent));
      m_minLot         = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      m_maxLot         = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      m_lotStep        = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
     }

   //--- adaptive risk requests are always clamped to the hard cap set at Init
   void              SetRiskPercent(const double p)
     {
      m_riskPercent = MathMax(0.0, MathMin(p, m_maxRiskPercent));
     }

   //--- Position size that risks m_riskPercent of equity given a stop-loss distance in price units
   double            CalculateLotSize(const double stopLossDistance)
     {
      if(stopLossDistance <= 0.0)
         return m_minLot;

      double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmount = equity * (m_riskPercent / 100.0);

      double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0 || tickValue <= 0.0)
         return m_minLot;

      double valuePerPoint = tickValue / tickSize;
      double lossPerLot    = stopLossDistance * valuePerPoint;
      if(lossPerLot <= 0.0)
         return m_minLot;

      double lots = riskAmount / lossPerLot;

      //--- normalize to broker lot step and clamp to min/max
      lots = MathFloor(lots / m_lotStep) * m_lotStep;
      lots = MathMax(m_minLot, MathMin(m_maxLot, lots));
      return NormalizeDouble(lots, 2);
     }

   double            RiskPercent(void) const { return m_riskPercent; }
  };

#endif // V75EA_RISK_MANAGER_MQH
