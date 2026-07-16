//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh |
//|  Order execution and open-position management: entry with       |
//|  retry-on-requote, breakeven stop, and partial profit-taking.    |
//+------------------------------------------------------------------+
#ifndef V75EA_TRADE_MANAGER_MQH
#define V75EA_TRADE_MANAGER_MQH

#property strict
#include <Trade\Trade.mqh>
#include <V75EA\Types.mqh>

class CTradeManager
  {
private:
   CTrade m_trade;
   string m_symbol;
   int    m_maxRetries;
   double m_breakevenTriggerAtr;
   double m_partialCloseAtr;
   double m_partialClosePercent;

public:
                     CTradeManager(void) : m_maxRetries(3) {}

   void              Init(const string symbol, const ulong magicNumber, const int slippagePoints,
                           const double breakevenTriggerAtr, const double partialCloseAtr,
                           const double partialClosePercent)
     {
      m_symbol               = symbol;
      m_breakevenTriggerAtr  = breakevenTriggerAtr;
      m_partialCloseAtr      = partialCloseAtr;
      m_partialClosePercent  = partialClosePercent;

      m_trade.SetExpertMagicNumber(magicNumber);
      m_trade.SetDeviationInPoints(slippagePoints);
      m_trade.SetTypeFillingBySymbol(symbol);
     }

   bool              HasOpenPosition(void)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) == m_symbol)
            return true;
        }
      return false;
     }

   bool              OpenTrade(const ENUM_SIGNAL signal, const double lots,
                                const double slDistance, const double tpDistance)
     {
      if(signal == SIGNAL_NONE || lots <= 0.0)
         return false;

      double price = (signal == SIGNAL_BUY)
                      ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                      : SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double sl = (signal == SIGNAL_BUY) ? price - slDistance : price + slDistance;
      double tp = (signal == SIGNAL_BUY) ? price + tpDistance : price - tpDistance;

      bool result = false;
      for(int attempt = 0; attempt < m_maxRetries && !result; attempt++)
        {
         if(signal == SIGNAL_BUY)
            result = m_trade.Buy(lots, m_symbol, price, sl, tp);
         else
            result = m_trade.Sell(lots, m_symbol, price, sl, tp);

         if(!result)
           {
            uint code = m_trade.ResultRetcode();
            Print("CTradeManager: order attempt ", attempt + 1, " failed, retcode=", code);
            if(code != TRADE_RETCODE_REQUOTE && code != TRADE_RETCODE_PRICE_CHANGED)
               break; // non-transient error, don't retry
           }
        }
      return result;
     }

   //--- Breakeven stop and partial close once price has moved favorably by a multiple of ATR
   void              ManageOpenPositions(const double currentAtr)
     {
      if(currentAtr <= 0.0)
         return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;

         long   type      = PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSl = PositionGetDouble(POSITION_SL);
         double currentTp = PositionGetDouble(POSITION_TP);
         double volume    = PositionGetDouble(POSITION_VOLUME);
         double price     = (type == POSITION_TYPE_BUY)
                             ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                             : SymbolInfoDouble(m_symbol, SYMBOL_ASK);

         double favorableMove = (type == POSITION_TYPE_BUY) ? (price - openPrice) : (openPrice - price);

         //--- breakeven
         if(favorableMove >= m_breakevenTriggerAtr * currentAtr)
           {
            bool needsUpdate = (type == POSITION_TYPE_BUY)
                                ? (currentSl < openPrice)
                                : (currentSl > openPrice || currentSl == 0.0);
            if(needsUpdate)
               m_trade.PositionModify(ticket, openPrice, currentTp);
           }

         //--- partial close
         double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
         if(favorableMove >= m_partialCloseAtr * currentAtr && volume > minLot)
           {
            double closeVolume = NormalizeDouble(volume * m_partialClosePercent / 100.0, 2);
            if(closeVolume >= minLot && closeVolume < volume)
               m_trade.PositionClosePartial(ticket, closeVolume);
           }
        }
     }
  };

#endif // V75EA_TRADE_MANAGER_MQH
