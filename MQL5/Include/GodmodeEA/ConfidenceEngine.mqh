//+------------------------------------------------------------------+
//|                                              ConfidenceEngine.mqh |
//|  MODULE 4 -- weighted score, NOT AND-gated filters. Adding a     |
//|  7th input shifts the distribution instead of collapsing trade  |
//|  count to zero. Tune the threshold against measured frequency.  |
//+------------------------------------------------------------------+
#property strict
#include "Defines.mqh"

class CConfidenceEngine
  {
private:
   string            m_symbol;
   ConfidenceWeights m_weights;

   int               m_ema_d1_handle;
   int               m_ema_h4_handle;
   int               m_rsi_handle;
   int               m_atr_handle;

   double            m_score_full_size;   // 0.75
   double            m_score_half_size;   // 0.65

   double            m_weight_floor;
   double            m_weight_ceiling;
   double            m_learning_rate;

   ENUM_TRADE_DIR SlopeDirection(const int handle, const int lookback)
     {
      double buf[];
      if(CopyBuffer(handle, 0, 1, lookback+1, buf) < lookback+1) return DIR_NONE;
      double diff = buf[ArraySize(buf)-1] - buf[0];
      if(diff > 0) return DIR_BUY;
      if(diff < 0) return DIR_SELL;
      return DIR_NONE;
     }

   double ClampD(double v, double lo, double hi)
     {
      if(v < lo) return lo;
      if(v > hi) return hi;
      return v;
     }

public:
                     CConfidenceEngine()
     {
      m_ema_d1_handle = INVALID_HANDLE;
      m_ema_h4_handle = INVALID_HANDLE;
      m_rsi_handle    = INVALID_HANDLE;
      m_atr_handle    = INVALID_HANDLE;
     }

   bool Init(const string symbol, const double score_full_size, const double score_half_size,
             const double learning_rate, const double weight_floor, const double weight_ceiling)
     {
      m_symbol = symbol;
      m_score_full_size = score_full_size;
      m_score_half_size = score_half_size;
      m_learning_rate = learning_rate;
      m_weight_floor = weight_floor;
      m_weight_ceiling = weight_ceiling;

      // Starting weights per spec table -- adapted online within hard bounds.
      m_weights.htf_bias        = 0.20;
      m_weights.structural_pos  = 0.20;
      m_weights.momentum        = 0.15;
      m_weights.candle          = 0.15;
      m_weights.vol_expansion   = 0.10;
      m_weights.liquidity_sweep = 0.10;
      m_weights.cost_headroom   = 0.10;

      m_ema_d1_handle = iMA(m_symbol, PERIOD_D1, 21, 0, MODE_EMA, PRICE_CLOSE);
      m_ema_h4_handle = iMA(m_symbol, PERIOD_H4, 21, 0, MODE_EMA, PRICE_CLOSE);
      m_rsi_handle    = iRSI(m_symbol, PERIOD_M5, 14, PRICE_CLOSE);
      m_atr_handle    = iATR(m_symbol, PERIOD_M5, 14);

      if(m_ema_d1_handle == INVALID_HANDLE || m_ema_h4_handle == INVALID_HANDLE ||
         m_rsi_handle == INVALID_HANDLE || m_atr_handle == INVALID_HANDLE)
        {
         Print("ConfidenceEngine: failed to create indicator handle(s).");
         return false;
        }

      LoadWeights();
      return true;
     }

   void Release()
     {
      if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
      if(m_ema_d1_handle != INVALID_HANDLE) IndicatorRelease(m_ema_d1_handle);
      if(m_ema_h4_handle != INVALID_HANDLE) IndicatorRelease(m_ema_h4_handle);
      if(m_rsi_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_handle);
     }

   ConfidenceWeights GetWeights() const { return m_weights; }

   //--- Module 4 core: weighted score across the seven components ----
   double Score(ThesisSignal &sig, const ENUM_TRADE_DIR h1_dir, const ENUM_TRADE_DIR m15_dir,
                const bool atr_expanding, const double cost_ratio, const double cost_gate_ratio)
     {
      ENUM_TRADE_DIR d1_dir = SlopeDirection(m_ema_d1_handle, 10);
      ENUM_TRADE_DIR h4_dir = SlopeDirection(m_ema_h4_handle, 10);

      int aligned = 0, total = 0;
      ENUM_TRADE_DIR tfs[4] = {d1_dir, h4_dir, h1_dir, m15_dir};
      for(int i=0; i<4; i++)
        {
         if(tfs[i] == DIR_NONE) continue;
         total++;
         if(tfs[i] == sig.direction) aligned++;
        }
      sig.comp_htf_bias = (total > 0) ? (double)aligned/(double)total : 0.5;

      // structural position: round-number magnetism ($10/$25/$50) near the trigger
      double atr_buf[];
      double atr = 0.0;
      if(CopyBuffer(m_atr_handle, 0, 1, 1, atr_buf) == 1) atr = atr_buf[0];
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double nearest25 = MathRound(sig.trigger_price / 25.0) * 25.0;
      double dist = MathAbs(sig.trigger_price - nearest25);
      sig.comp_structural_pos = (atr > 0) ? ClampD(1.0 - dist/(atr*0.5), 0.0, 1.0) : 0.5;

      // momentum confirmation -- continuation of the entry direction ONLY, never a fade signal
      double rsi_buf[];
      double rsi = 50.0;
      if(CopyBuffer(m_rsi_handle, 0, 1, 1, rsi_buf) == 1) rsi = rsi_buf[0];
      if(sig.direction == DIR_BUY)
         sig.comp_momentum = ClampD((rsi - 50.0)/25.0, 0.0, 1.0);
      else
         sig.comp_momentum = ClampD((50.0 - rsi)/25.0, 0.0, 1.0);

      // candle confirmation: engulfing or rejection wick at the trigger level
      double o[], c[], h[], l[];
      if(CopyOpen(m_symbol, PERIOD_M5, 1, 2, o) == 2 && CopyClose(m_symbol, PERIOD_M5, 1, 2, c) == 2 &&
         CopyHigh(m_symbol, PERIOD_M5, 1, 2, h) == 2 && CopyLow(m_symbol, PERIOD_M5, 1, 2, l) == 2)
        {
         double body = MathAbs(c[1]-o[1]);
         double lowerWick = MathMin(o[1],c[1]) - l[1];
         double upperWick = h[1] - MathMax(o[1],c[1]);
         bool engulf = (sig.direction==DIR_BUY) ?
                       (c[1]>o[1] && c[1]>o[0] && o[1]<c[0]) :
                       (c[1]<o[1] && c[1]<o[0] && o[1]>c[0]);
         bool wick = (sig.direction==DIR_BUY) ? (lowerWick > body*1.5) : (upperWick > body*1.5);
         sig.comp_candle = (engulf && wick) ? 1.0 : ((engulf || wick) ? 0.6 : 0.0);
        }
      else
         sig.comp_candle = 0.0;

      // volatility expansion
      sig.comp_vol_expansion = atr_expanding ? 1.0 : 0.0;

      // liquidity sweep confluence is supplied by caller via comp_liquidity_sweep already
      // (set by ThesisEngine.CheckSweepConfluence before calling Score)

      // cost headroom: more room under the gate ratio = higher score
      sig.comp_cost_headroom = (cost_gate_ratio > 0) ? ClampD(1.0 - cost_ratio/cost_gate_ratio, 0.0, 1.0) : 0.5;

      double score =
         m_weights.htf_bias        * sig.comp_htf_bias +
         m_weights.structural_pos  * sig.comp_structural_pos +
         m_weights.momentum        * sig.comp_momentum +
         m_weights.candle          * sig.comp_candle +
         m_weights.vol_expansion   * sig.comp_vol_expansion +
         m_weights.liquidity_sweep * sig.comp_liquidity_sweep +
         m_weights.cost_headroom   * sig.comp_cost_headroom;

      sig.confidence = score;
      return score;
     }

   //--- tiered sizing: >=0.75 full, 0.65-0.75 half, <0.65 no trade ---
   double TierSizeMultiplier(const double confidence) const
     {
      if(confidence >= m_score_full_size) return 1.0;
      if(confidence >= m_score_half_size) return 0.5;
      return 0.0;
     }

   //--- v1 adaptive learning: small learning rate, hard bounds. Persist. ---
   //--- Unbounded adaptation chases noise; this nudges weights toward     ---
   //--- whichever components actually predicted the trade's outcome.     ---
   void AdaptWeights(const ThesisSignal &sig, const double r_multiple)
     {
      double outcome = (r_multiple > 0) ? 1.0 : -1.0;
      double comps[7];
      comps[0] = sig.comp_htf_bias;
      comps[1] = sig.comp_structural_pos;
      comps[2] = sig.comp_momentum;
      comps[3] = sig.comp_candle;
      comps[4] = sig.comp_vol_expansion;
      comps[5] = sig.comp_liquidity_sweep;
      comps[6] = sig.comp_cost_headroom;

      double w[7];
      w[0]=m_weights.htf_bias; w[1]=m_weights.structural_pos; w[2]=m_weights.momentum;
      w[3]=m_weights.candle; w[4]=m_weights.vol_expansion; w[5]=m_weights.liquidity_sweep;
      w[6]=m_weights.cost_headroom;

      double sum = 0.0;
      for(int i=0; i<7; i++)
        {
         w[i] = ClampD(w[i] + m_learning_rate * outcome * (comps[i] - 0.5), m_weight_floor, m_weight_ceiling);
         sum += w[i];
        }
      if(sum > 0)
         for(int i=0; i<7; i++) w[i] /= sum; // renormalize to sum to 1.0

      m_weights.htf_bias=w[0]; m_weights.structural_pos=w[1]; m_weights.momentum=w[2];
      m_weights.candle=w[3]; m_weights.vol_expansion=w[4]; m_weights.liquidity_sweep=w[5];
      m_weights.cost_headroom=w[6];

      PersistWeights();
     }

   void PersistWeights()
     {
      GlobalVariableSet("GM_W_HTF", m_weights.htf_bias);
      GlobalVariableSet("GM_W_STRUCT", m_weights.structural_pos);
      GlobalVariableSet("GM_W_MOM", m_weights.momentum);
      GlobalVariableSet("GM_W_CANDLE", m_weights.candle);
      GlobalVariableSet("GM_W_VOL", m_weights.vol_expansion);
      GlobalVariableSet("GM_W_SWEEP", m_weights.liquidity_sweep);
      GlobalVariableSet("GM_W_COST", m_weights.cost_headroom);
     }

   void LoadWeights()
     {
      if(GlobalVariableCheck("GM_W_HTF"))    m_weights.htf_bias        = GlobalVariableGet("GM_W_HTF");
      if(GlobalVariableCheck("GM_W_STRUCT")) m_weights.structural_pos  = GlobalVariableGet("GM_W_STRUCT");
      if(GlobalVariableCheck("GM_W_MOM"))    m_weights.momentum        = GlobalVariableGet("GM_W_MOM");
      if(GlobalVariableCheck("GM_W_CANDLE")) m_weights.candle          = GlobalVariableGet("GM_W_CANDLE");
      if(GlobalVariableCheck("GM_W_VOL"))    m_weights.vol_expansion   = GlobalVariableGet("GM_W_VOL");
      if(GlobalVariableCheck("GM_W_SWEEP"))  m_weights.liquidity_sweep = GlobalVariableGet("GM_W_SWEEP");
      if(GlobalVariableCheck("GM_W_COST"))   m_weights.cost_headroom   = GlobalVariableGet("GM_W_COST");
     }
  };
//+------------------------------------------------------------------+
