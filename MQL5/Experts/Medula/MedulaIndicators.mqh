//+------------------------------------------------------------------+
//|                                             MedulaIndicators.mqh |
//|  Central manager for all indicator handles (chart TF + MTF).     |
//+------------------------------------------------------------------+
#ifndef MEDULA_INDICATORS_MQH
#define MEDULA_INDICATORS_MQH

#include "MedulaTypes.mqh"

class CIndicators
  {
private:
   string            m_sym;
   ENUM_TIMEFRAMES   m_tf;
   // chart-timeframe handles
   int               m_hATR,m_hADX,m_hRSI,m_hMACD,m_hEMA20,m_hEMA50,m_hBands;
   // higher-timeframe handles for the MTF engine (§7): D1, H4, H1
   ENUM_TIMEFRAMES   m_mtf[3];
   int               m_hAdxTF[3],m_hEma20TF[3],m_hEma50TF[3],m_hAtrTF[3];

public:
                     CIndicators(void)
     {
      m_hATR=INVALID_HANDLE; m_hADX=INVALID_HANDLE; m_hRSI=INVALID_HANDLE;
      m_hMACD=INVALID_HANDLE; m_hEMA20=INVALID_HANDLE; m_hEMA50=INVALID_HANDLE;
      m_hBands=INVALID_HANDLE;
      for(int i=0;i<3;i++)
        {
         m_hAdxTF[i]=INVALID_HANDLE; m_hEma20TF[i]=INVALID_HANDLE;
         m_hEma50TF[i]=INVALID_HANDLE; m_hAtrTF[i]=INVALID_HANDLE;
        }
     }

   bool Init(const string sym,const ENUM_TIMEFRAMES tf,const SMedulaConfig &cfg)
     {
      m_sym=sym;
      m_tf=tf;
      m_mtf[0]=PERIOD_D1;
      m_mtf[1]=PERIOD_H4;
      m_mtf[2]=PERIOD_H1;

      m_hATR  =iATR(m_sym,m_tf,cfg.atrPeriod);
      m_hADX  =iADX(m_sym,m_tf,cfg.adxPeriod);
      m_hRSI  =iRSI(m_sym,m_tf,cfg.rsiPeriod,PRICE_CLOSE);
      m_hMACD =iMACD(m_sym,m_tf,12,26,9,PRICE_CLOSE);
      m_hEMA20=iMA(m_sym,m_tf,20,0,MODE_EMA,PRICE_CLOSE);
      m_hEMA50=iMA(m_sym,m_tf,50,0,MODE_EMA,PRICE_CLOSE);
      m_hBands=iBands(m_sym,m_tf,cfg.bbPeriod,0,cfg.bbDev,PRICE_CLOSE);

      if(m_hATR==INVALID_HANDLE || m_hADX==INVALID_HANDLE || m_hRSI==INVALID_HANDLE ||
         m_hMACD==INVALID_HANDLE || m_hEMA20==INVALID_HANDLE || m_hEMA50==INVALID_HANDLE ||
         m_hBands==INVALID_HANDLE)
         return false;

      for(int i=0;i<3;i++)
        {
         m_hAdxTF[i]  =iADX(m_sym,m_mtf[i],cfg.adxPeriod);
         m_hEma20TF[i]=iMA(m_sym,m_mtf[i],20,0,MODE_EMA,PRICE_CLOSE);
         m_hEma50TF[i]=iMA(m_sym,m_mtf[i],50,0,MODE_EMA,PRICE_CLOSE);
         m_hAtrTF[i]  =iATR(m_sym,m_mtf[i],cfg.atrPeriod);
         if(m_hAdxTF[i]==INVALID_HANDLE || m_hEma20TF[i]==INVALID_HANDLE ||
            m_hEma50TF[i]==INVALID_HANDLE || m_hAtrTF[i]==INVALID_HANDLE)
            return false;
        }
      return true;
     }

   void Release(void)
     {
      if(m_hATR!=INVALID_HANDLE)   IndicatorRelease(m_hATR);
      if(m_hADX!=INVALID_HANDLE)   IndicatorRelease(m_hADX);
      if(m_hRSI!=INVALID_HANDLE)   IndicatorRelease(m_hRSI);
      if(m_hMACD!=INVALID_HANDLE)  IndicatorRelease(m_hMACD);
      if(m_hEMA20!=INVALID_HANDLE) IndicatorRelease(m_hEMA20);
      if(m_hEMA50!=INVALID_HANDLE) IndicatorRelease(m_hEMA50);
      if(m_hBands!=INVALID_HANDLE) IndicatorRelease(m_hBands);
      for(int i=0;i<3;i++)
        {
         if(m_hAdxTF[i]!=INVALID_HANDLE)   IndicatorRelease(m_hAdxTF[i]);
         if(m_hEma20TF[i]!=INVALID_HANDLE) IndicatorRelease(m_hEma20TF[i]);
         if(m_hEma50TF[i]!=INVALID_HANDLE) IndicatorRelease(m_hEma50TF[i]);
         if(m_hAtrTF[i]!=INVALID_HANDLE)   IndicatorRelease(m_hAtrTF[i]);
        }
     }

   // single-value fetch; EMPTY_VALUE on failure so callers can guard
   double Val(const int handle,const int buffer,const int shift) const
     {
      double tmp[1];
      if(CopyBuffer(handle,buffer,shift,1,tmp)!=1)
         return EMPTY_VALUE;
      return tmp[0];
     }

   // chart-timeframe accessors
   double Atr(const int s)        const { return Val(m_hATR,0,s); }
   double Adx(const int s)        const { return Val(m_hADX,0,s); }
   double Rsi(const int s)        const { return Val(m_hRSI,0,s); }
   double MacdMain(const int s)   const { return Val(m_hMACD,0,s); }
   double MacdSignal(const int s) const { return Val(m_hMACD,1,s); }
   double Ema20(const int s)      const { return Val(m_hEMA20,0,s); }
   double Ema50(const int s)      const { return Val(m_hEMA50,0,s); }
   double BandUpper(const int s)  const { return Val(m_hBands,1,s); }
   double BandLower(const int s)  const { return Val(m_hBands,2,s); }
   int    AtrHandle(void)         const { return m_hATR; }

   // higher-timeframe accessors
   ENUM_TIMEFRAMES Mtf(const int i)          const { return m_mtf[i]; }
   double AdxTF(const int i,const int s)     const { return Val(m_hAdxTF[i],0,s); }
   double Ema20TF(const int i,const int s)   const { return Val(m_hEma20TF[i],0,s); }
   double Ema50TF(const int i,const int s)   const { return Val(m_hEma50TF[i],0,s); }
   double AtrTF(const int i,const int s)     const { return Val(m_hAtrTF[i],0,s); }
  };

#endif // MEDULA_INDICATORS_MQH
