//+------------------------------------------------------------------+
//|                                                        Types.mqh |
//|  Shared enums/structs used across the V75EA modules.            |
//+------------------------------------------------------------------+
#ifndef V75EA_TYPES_MQH
#define V75EA_TYPES_MQH

#property strict

enum ENUM_SIGNAL
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

//--- result of a confluence evaluation
struct SConfluenceResult
  {
   ENUM_SIGNAL signal;      // final decision (NONE unless confidence >= threshold)
   double      confidence;  // 0..1
   double      atr;         // current ATR, for stop/target sizing
   string      reason;      // human-readable breakdown for logging
  };

#endif // V75EA_TYPES_MQH
