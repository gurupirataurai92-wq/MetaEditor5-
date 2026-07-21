//+------------------------------------------------------------------+
//|                                                   EdgeModel.mqh |
//|  The arithmetic conscience of the EA. It measures, from the live |
//|  price series, whether V75 is currently deviating from a pure    |
//|  driftless random walk — and translates that into the expected   |
//|  value (in R multiples) of a proposed trade, INCLUDING spread.   |
//|                                                                  |
//|  Core identity: for driftless Brownian motion with barriers at   |
//|  +TP and -SL, P(hit TP first) = SL/(SL+TP), so EV = 0 before     |
//|  spread and negative after. The ONLY way EV turns positive is a  |
//|  statistically real drift mu (persistence). With drift, the      |
//|  two-barrier hitting probability (optional-stopping / gambler's  |
//|  ruin) is:                                                        |
//|      theta = 2*mu/sigma^2                                         |
//|      P_win = (1 - e^{theta*SL}) / (e^{-theta*TP} - e^{theta*SL})  |
//|  which collapses to SL/(SL+TP) as mu -> 0. Drift is used only     |
//|  when its t-stat clears a threshold; otherwise it is treated as  |
//|  zero and the trade is correctly judged unprofitable.            |
//+------------------------------------------------------------------+
#ifndef V75EA_EDGE_MODEL_MQH
#define V75EA_EDGE_MODEL_MQH

#property strict

class CEdgeModel
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int             m_lookback;
   double          m_tstatThreshold;

public:
                     CEdgeModel(void) : m_lookback(100), m_tstatThreshold(2.0) {}

   void              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                           const int lookback, const double tstatThreshold)
     {
      m_symbol         = symbol;
      m_tf             = tf;
      m_lookback       = MathMax(20, lookback);
      m_tstatThreshold = MathMax(0.0, tstatThreshold);
     }

   //--- log returns, newest first; returns count actually filled
   int               GetReturns(double &r[])
     {
      int n = m_lookback;
      double close[];
      ArraySetAsSeries(close, true);
      if(CopyClose(m_symbol, m_tf, 0, n + 1, close) < n + 1)
         return 0;
      ArrayResize(r, n);
      for(int i = 0; i < n; i++)
         r[i] = (close[i + 1] > 0.0) ? MathLog(close[i] / close[i + 1]) : 0.0;
      return n;
     }

   double            MeanReturn(const double &r[], const int n)
     {
      if(n <= 0) return 0.0;
      double s = 0.0;
      for(int i = 0; i < n; i++) s += r[i];
      return s / n;
     }

   double            StdReturn(const double &r[], const int n, const double mean)
     {
      if(n < 2) return 0.0;
      double v = 0.0;
      for(int i = 0; i < n; i++) { double d = r[i] - mean; v += d * d; }
      return MathSqrt(v / (n - 1));
     }

   //--- t-statistic of the mean return: is drift distinguishable from zero?
   double            DriftTStat(const double &r[], const int n, const double mean, const double sd)
     {
      if(n < 2 || sd <= 0.0) return 0.0;
      double se = sd / MathSqrt((double)n);
      return (se > 0.0) ? mean / se : 0.0;
     }

   //--- lag-1 autocorrelation (persistence vs mean-reversion), for context/logging
   double            Lag1Autocorr(const double &r[], const int n, const double mean)
     {
      if(n < 3) return 0.0;
      double num = 0.0, den = 0.0;
      for(int i = 0; i < n; i++) { double d = r[i] - mean; den += d * d; }
      for(int i = 0; i < n - 1; i++) num += (r[i] - mean) * (r[i + 1] - mean);
      return (den > 0.0) ? num / den : 0.0;
     }

   //--- variance ratio VR(q): >1 trending, <1 mean-reverting, ~1 random walk
   double            VarianceRatio(const double &r[], const int n, const int q)
     {
      if(n < q * 2 || q < 2) return 1.0;
      double mean = MeanReturn(r, n);
      double var1 = 0.0;
      for(int i = 0; i < n; i++) { double d = r[i] - mean; var1 += d * d; }
      var1 /= (n - 1);
      if(var1 <= 0.0) return 1.0;

      int m = n - q + 1;
      double varQ = 0.0;
      for(int i = 0; i < m; i++)
        {
         double sum = 0.0;
         for(int j = 0; j < q; j++) sum += r[i + j];
         double d = sum - q * mean;
         varQ += d * d;
        }
      varQ /= (m - 1);
      return varQ / (q * var1);
     }

   //--- expected value (in R multiples of the SL risk) of a trade in `direction`,
   //    with stop distance `sl` and target `tp` in price units, net of spread.
   //    Returns a large negative number if inputs are unusable.
   double            ExpectedValueR(const int direction, const double sl, const double tp,
                                     const double spreadPrice)
     {
      if(sl <= 0.0 || tp <= 0.0)
         return -1.0;

      double r[];
      int n = GetReturns(r);
      if(n < 20)
         return -1.0;

      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double mean  = MeanReturn(r, n);
      double sd    = StdReturn(r, n, mean);
      if(sd <= 0.0 || price <= 0.0)
         return -1.0;

      //--- only credit drift if it is statistically real; else treat as zero
      double tstat = DriftTStat(r, n, mean, sd);
      double effMeanLogRet = (MathAbs(tstat) >= m_tstatThreshold) ? mean : 0.0;

      //--- move to price units, oriented in the trade's favor
      double muPrice    = effMeanLogRet * price * direction;
      double sigmaPrice = sd * price;
      double var        = sigmaPrice * sigmaPrice;
      if(var <= 0.0)
         return -1.0;

      double rr = tp / sl;
      double pWin;

      double theta = 2.0 * muPrice / var;
      if(MathAbs(theta) < 1e-12)
        {
         pWin = sl / (sl + tp);            // driftless limit: EV = 0 before spread
        }
      else
        {
         //--- clamp exponents for numerical safety
         double eTP = SafeExp(-theta * tp);
         double eSL = SafeExp(theta * sl);
         double den = eTP - eSL;
         pWin = (MathAbs(den) < 1e-12) ? sl / (sl + tp) : (1.0 - eSL) / den;
        }
      pWin = MathMax(0.0, MathMin(1.0, pWin));

      double spreadR = spreadPrice / sl;   // cost expressed in R
      return pWin * rr - (1.0 - pWin) - spreadR;
     }

   //--- diagnostic bundle for logging / dashboard
   void              Diagnostics(double &driftTStat, double &autocorr, double &varRatio, const int q)
     {
      double r[];
      int n = GetReturns(r);
      if(n < 20) { driftTStat = 0.0; autocorr = 0.0; varRatio = 1.0; return; }
      double mean = MeanReturn(r, n);
      double sd   = StdReturn(r, n, mean);
      driftTStat  = DriftTStat(r, n, mean, sd);
      autocorr    = Lag1Autocorr(r, n, mean);
      varRatio    = VarianceRatio(r, n, q);
     }

private:
   double            SafeExp(const double x)
     {
      double c = MathMax(-30.0, MathMin(30.0, x));
      return MathExp(c);
     }
  };

#endif // V75EA_EDGE_MODEL_MQH
