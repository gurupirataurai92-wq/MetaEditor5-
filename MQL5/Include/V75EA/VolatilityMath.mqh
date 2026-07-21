//+------------------------------------------------------------------+
//|                                               VolatilityMath.mqh |
//|  Encodes the arithmetic of a Deriv volatility index: a driftless |
//|  geometric Brownian motion with a constant annualized volatility |
//|  (75% for V75). Provides the theoretical per-bar sigma, realized  |
//|  vs theoretical volatility (the clustering signal), first-passage |
//|  touch probabilities (reflection principle), and sigma-scaled     |
//|  stop distances so risk is constant in PROBABILITY terms.         |
//|                                                                  |
//|  Key implication encoded here: under pure driftless GBM no SL/TP  |
//|  geometry beats break-even, so the EA must trade deviations from  |
//|  randomness (vol expansion, trend persistence) — this module      |
//|  measures them rather than assuming price predictability.         |
//+------------------------------------------------------------------+
#ifndef V75EA_VOLATILITY_MATH_MQH
#define V75EA_VOLATILITY_MATH_MQH

#property strict

class CVolatilityMath
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   double          m_annualVol;     // e.g. 0.75 for V75
   double          m_barSeconds;
   double          m_secondsPerYear;

public:
                     CVolatilityMath(void) : m_annualVol(0.75), m_barSeconds(300.0),
                                              m_secondsPerYear(31536000.0) {}

   void              Init(const string symbol, const ENUM_TIMEFRAMES tf, const double annualVolPercent)
     {
      m_symbol         = symbol;
      m_tf             = tf;
      m_annualVol      = MathMax(0.01, annualVolPercent / 100.0);
      m_barSeconds     = (double)PeriodSeconds(tf);
      m_secondsPerYear = 365.0 * 24.0 * 3600.0;
     }

   //--- theoretical std-dev of one bar's log-return (fraction of price)
   double            BarSigma(void)
     {
      return m_annualVol * MathSqrt(m_barSeconds / m_secondsPerYear);
     }

   //--- theoretical std-dev of log-return over N bars
   double            HorizonSigma(const int bars)
     {
      double t = m_barSeconds * MathMax(1, bars);
      return m_annualVol * MathSqrt(t / m_secondsPerYear);
     }

   //--- expected absolute price move over one bar: price * sigma * sqrt(2/pi)
   double            ExpectedBarMove(void)
     {
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      return price * BarSigma() * MathSqrt(2.0 / M_PI);
     }

   //--- realized log-return sigma over the last N closed bars
   double            RealizedSigma(const int bars)
     {
      int n = MathMax(2, bars);
      double close[];
      ArraySetAsSeries(close, true);
      if(CopyClose(m_symbol, m_tf, 0, n + 1, close) < n + 1)
         return 0.0;

      double mean = 0.0;
      double rets[];
      ArrayResize(rets, n);
      for(int i = 0; i < n; i++)
        {
         double r = (close[i + 1] > 0.0) ? MathLog(close[i] / close[i + 1]) : 0.0;
         rets[i]  = r;
         mean    += r;
        }
      mean /= n;

      double var = 0.0;
      for(int i = 0; i < n; i++)
        {
         double d = rets[i] - mean;
         var += d * d;
        }
      var /= (n - 1);
      return MathSqrt(var);
     }

   //--- realized / theoretical volatility. >1 = expansion (cluster), <1 = compression.
   //    This is the exploitable signal: magnitude is predictable, direction is not.
   double            VolRatio(const int bars)
     {
      double theo = BarSigma();
      if(theo <= 0.0)
         return 1.0;
      double realized = RealizedSigma(bars);
      return realized / theo;
     }

   //--- probability price touches a barrier `distance` away within `bars`,
   //    for driftless BM: P = 2 * (1 - Phi(distance / (price * horizonSigma)))
   double            ProbTouch(const double distance, const int bars)
     {
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double sig   = price * HorizonSigma(bars);
      if(sig <= 0.0 || distance <= 0.0)
         return 0.0;
      double z = distance / sig;
      double p = 2.0 * (1.0 - NormCdf(z));
      return MathMax(0.0, MathMin(1.0, p));
     }

   //--- stop distance placed at k theoretical sigmas over `bars` (constant-probability risk)
   double            SigmaStopDistance(const int bars, const double k)
     {
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      return price * HorizonSigma(bars) * MathMax(0.1, k);
     }

private:
   //--- standard normal CDF via erf approximation (Abramowitz & Stegun 7.1.26)
   double            NormCdf(const double x)
     {
      return 0.5 * (1.0 + Erf(x / MathSqrt(2.0)));
     }

   double            Erf(const double x)
     {
      double t    = 1.0 / (1.0 + 0.3275911 * MathAbs(x));
      double y    = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t
                    - 0.284496736) * t + 0.254829592) * t * MathExp(-x * x);
      return (x >= 0.0) ? y : -y;
     }
  };

#endif // V75EA_VOLATILITY_MATH_MQH
