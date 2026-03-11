//+------------------------------------------------------------------+
//|                                                      TradeManager.mqh |
//|                        Copyright 2024, Your Company Name            |
//|                                             https://www.yourwebsite.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Company Name"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Input parameters for trade management                            |
//+------------------------------------------------------------------+
input double   Risk_PC = 1.0;                // Risk percentage per trade (0.5-1%)
input string   Lot_Method = "EquityRisk";    // Lot sizing method: EquityRisk, Fixed
input double   Min_Lot = 0.01;               // Minimum lot size
input double   Max_Lot = 5.0;                // Maximum lot size
input int      Max_Open_Trades = 1;          // Maximum open trades at once
input bool     Allow_Add_If_Trailed = false; // Allow new trade if previous is trailed
input int      Min_Time_Between_Trades_Hrs = 1; // Minimum hours between trades
input int      Max_Trades_Per_Day = 3;       // Maximum trades per day
input double   Daily_DD_Limit_PC = 5.0;      // Daily drawdown limit percentage
input bool     Weekend_Close = true;         // Close positions before weekend
input string   Close_Hour_Fri = "21:00";     // Friday close hour (GMT)
input bool     Close_If_In_Profit = true;    // Close only if in profit on Friday
input string   Trail_Method = "ATR";         // Trailing method: ATR, FixedPips, Percent
input double   Trail_Mult = 0.5;             // Trailing multiplier for ATR method
input double   Trail_Activation_PC = 50.0;   // Profit % to activate trailing
input double   Fixed_Trail_Pips = 20.0;      // Fixed trailing pips (if method=FixedPips)
input double   Percent_Trail_PC = 33.0;      // Percent trailing (if method=Percent)
input int      ATR_Period = 14;              // ATR period for trailing
input int      ATR_Timeframe = PERIOD_H1;    // Timeframe for ATR calculation

//+------------------------------------------------------------------+
//| Class CTradeManager: Manages trade execution and risk            |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
   CTrade        m_trade;                    // Trade object for execution
   CSymbolInfo   m_symbol;                   // Symbol info object
   CPositionInfo m_position;                 // Position info object
   COrderInfo    m_order;                    // Order info object
   CAccountInfo  m_account;                  // Account info object
   
   // Internal variables
   datetime      m_lastTradeTime;            // Time of last trade
   int           m_tradesToday;              // Number of trades today
   double        m_dailyEquityHigh;          // Daily equity high for drawdown calc
   bool          m_dailyDDTriggered;         // Daily drawdown limit triggered
   
   // Helper methods
   double        CalculateLotSize(double stopLossPips);
   bool          CheckMaxTrades();
   bool          CheckMinTimeBetweenTrades();
   bool          CheckDailyTradesLimit();
   bool          CheckDailyDrawdown();
   bool          CheckWeekendClose();
   void          UpdateTrailingStop();
   double        GetATRValue();
   
public:
   // Constructor and destructor
   CTradeManager();
   ~CTradeManager();
   
   // Initialization
   bool          Init(string symbol);
   
   // Trade execution methods
   bool          BuyStop(double price, double stopLoss, double takeProfit, string comment="");
   bool          SellStop(double price, double stopLoss, double takeProfit, string comment="");
   bool          Buy(double stopLoss, double takeProfit, string comment="");
   bool          Sell(double stopLoss, double takeProfit, string comment="");
   
   // Trade management methods
   bool          CloseAllPositions();
   bool          ClosePosition(ulong ticket);
   bool          ModifyPosition(ulong ticket, double stopLoss, double takeProfit);
   bool          DeleteAllPending();
   bool          DeletePending(ulong ticket);
   
   // Risk management checks
   bool          CanOpenNewTrade();
   bool          ShouldCloseFriday();
   
   // Update methods (call in OnTick)
   void          OnTick();
   void          ResetDaily();
   
   // Getters
   int           GetOpenPositionsCount();
   int           GetPendingOrdersCount();
   double        GetDailyPL();
   bool          IsDailyDDTriggered() { return m_dailyDDTriggered; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTradeManager::CTradeManager()
{
   m_lastTradeTime = 0;
   m_tradesToday = 0;
   m_dailyEquityHigh = 0;
   m_dailyDDTriggered = false;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTradeManager::~CTradeManager()
{
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CTradeManager::Init(string symbol)
{
   if(!m_symbol.Name(symbol))
   {
      Print("Failed to set symbol: ", symbol);
      return false;
   }
   
   m_trade.SetExpertMagicNumber(12345);
   m_trade.SetDeviationInPoints(10);
   m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   m_dailyEquityHigh = m_account.Equity();
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                      |
//+------------------------------------------------------------------+
double CTradeManager::CalculateLotSize(double stopLossPips)
{
   if(Lot_Method != "EquityRisk")
   {
      // Fixed lot method
      return NormalizeDouble(Min_Lot, 2);
   }
   
   // Equity risk method
   double accountEquity = m_account.Equity();
   double riskAmount = accountEquity * (Risk_PC / 100.0);
   
   if(stopLossPips <= 0)
   {
      Print("Warning: Stop loss pips is zero or negative");
      return Min_Lot;
   }
   
   double tickValue = m_symbol.TickValue();
   double tickSize = m_symbol.TickSize();
   double pointValue = m_symbol.Point();
   
   if(tickValue <= 0 || tickSize <= 0 || pointValue <= 0)
   {
      Print("Error: Invalid symbol properties");
      return Min_Lot;
   }
   
   // Calculate lot size
   double lotSize = riskAmount / (stopLossPips * 10 * tickValue);
   
   // Adjust for symbol properties
   lotSize = lotSize * (pointValue / tickSize);
   
   // Normalize and apply limits
   lotSize = NormalizeDouble(lotSize, 2);
   lotSize = MathMax(lotSize, Min_Lot);
   lotSize = MathMin(lotSize, Max_Lot);
   
   // Adjust to symbol lot step
   double lotStep = m_symbol.LotsStep();
   if(lotStep > 0)
   {
      lotSize = lotSize - MathMod(lotSize, lotStep);
   }
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Check maximum open trades limit                                  |
//+------------------------------------------------------------------+
bool CTradeManager::CheckMaxTrades()
{
   int openPositions = PositionsTotal();
   
   if(openPositions >= Max_Open_Trades)
   {
      if(!Allow_Add_If_Trailed)
         return false;
      
      // Check if any position has been trailed (modified SL)
      for(int i = 0; i < openPositions; i++)
      {
         if(m_position.SelectByIndex(i))
         {
            if(m_position.StopLoss() != 0)
            {
               // Position has SL set, check if it's been modified
               // For simplicity, we'll allow new trade if any position has SL
               return true;
            }
         }
      }
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check minimum time between trades                                |
//+------------------------------------------------------------------+
bool CTradeManager::CheckMinTimeBetweenTrades()
{
   if(m_lastTradeTime == 0)
      return true;
   
   datetime currentTime = TimeCurrent();
   int hoursSinceLastTrade = (int)((currentTime - m_lastTradeTime) / 3600);
   
   return (hoursSinceLastTrade >= Min_Time_Between_Trades_Hrs);
}

//+------------------------------------------------------------------+
//| Check daily trades limit                                         |
//+------------------------------------------------------------------+
bool CTradeManager::CheckDailyTradesLimit()
{
   return (m_tradesToday < Max_Trades_Per_Day);
}

//+------------------------------------------------------------------+
//| Check daily drawdown limit                                       |
//+------------------------------------------------------------------+
bool CTradeManager::CheckDailyDrawdown()
{
   if(m_dailyDDTriggered)
      return false;
   
   double currentEquity = m_account.Equity();
   
   // Update daily high equity
   if(currentEquity > m_dailyEquityHigh)
      m_dailyEquityHigh = currentEquity;
   
   // Calculate drawdown from daily high
   double drawdown = m_dailyEquityHigh - currentEquity;
   double drawdownPercent = (drawdown / m_dailyEquityHigh) * 100.0;
   
   if(drawdownPercent >= Daily_DD_Limit_PC)
   {
      m_dailyDDTriggered = true;
      Print("Daily drawdown limit triggered: ", drawdownPercent, "%");
      CloseAllPositions();
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if should close positions before weekend                   |
//+------------------------------------------------------------------+
bool CTradeManager::CheckWeekendClose()
{
   if(!Weekend_Close)
      return false;
   
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   // Check if it's Friday
   if(timeStruct.day_of_week == 5) // Friday
   {
      // Parse close hour
      int closeHour, closeMinute;
      StringToTime(Close_Hour_Fri, closeHour, closeMinute);
      
      // Check if current time is after close hour
      if(timeStruct.hour >= closeHour && timeStruct.min >= closeMinute)
      {
         if(!Close_If_In_Profit)
            return true;
         
         // Check if any position is in profit
         for(int i = 0; i < PositionsTotal(); i++)
         {
            if(m_position.SelectByIndex(i))
            {
               if(m_position.Profit() > 0)
                  return true;
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Update trailing stops for open positions                         |
//+------------------------------------------------------------------+
void CTradeManager::UpdateTrailingStop()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() != m_symbol.Name())
            continue;
         
         double currentPrice = m_position.PriceCurrent();
         double openPrice = m_position.PriceOpen();
         double stopLoss = m_position.StopLoss();
         double takeProfit = m_position.TakeProfit();
         
         // Calculate profit percentage
         double profitPips = 0;
         if(m_position.PositionType() == POSITION_TYPE_BUY)
         {
            profitPips = (currentPrice - openPrice) / m_symbol.Point();
         }
         else if(m_position.PositionType() == POSITION_TYPE_SELL)
         {
            profitPips = (openPrice - currentPrice) / m_symbol.Point();
         }
         
         double tpPips = 0;
         if(takeProfit > 0)
         {
            if(m_position.PositionType() == POSITION_TYPE_BUY)
               tpPips = (takeProfit - openPrice) / m_symbol.Point();
            else
               tpPips = (openPrice - takeProfit) / m_symbol.Point();
         }
         
         double profitPercent = (tpPips > 0) ? (profitPips / tpPips) * 100.0 : 0;
         
         // Check if trailing should be activated
         if(profitPercent >= Trail_Activation_PC)
         {
            double newStopLoss = stopLoss;
            
            if(Trail_Method == "ATR")
            {
               double atrValue = GetATRValue();
               double trailDistance = atrValue * Trail_Mult;
               
               if(m_position.PositionType() == POSITION_TYPE_BUY)
               {
                  newStopLoss = currentPrice - trailDistance;
                  if(newStopLoss > stopLoss && newStopLoss < currentPrice)
                  {
                     m_trade.PositionModify(m_position.Ticket(), newStopLoss, takeProfit);
                  }
               }
               else if(m_position.PositionType() == POSITION_TYPE_SELL)
               {
                  newStopLoss = currentPrice + trailDistance;
                  if(newStopLoss < stopLoss && newStopLoss > currentPrice)
                  {
                     m_trade.PositionModify(m_position.Ticket(), newStopLoss, takeProfit);
                  }
               }
            }
            else if(Trail_Method == "FixedPips")
            {
               double trailDistance = Fixed_Trail_Pips * m_symbol.Point();
               
               if(m_position.PositionType() == POSITION_TYPE_BUY)
               {
                  newStopLoss = currentPrice - trailDistance;
                  if(newStopLoss > stopLoss)
                  {
                     m_trade.PositionModify(m_position.Ticket(), newStopLoss, takeProfit);
                  }
               }
               else if(m_position.PositionType() == POSITION_TYPE_SELL)
               {
                  newStopLoss = currentPrice + trailDistance;
                  if(newStopLoss < stopLoss)
                  {
                     m_trade.PositionModify(m_position.Ticket(), newStopLoss, takeProfit);
                  }
               }
            }
            else if(Trail_Method == "Percent")
            {
               double trailDistance = (profitPips * (Percent_Trail_PC / 100.0)) * m_symbol.Point();
               
               if(m_position.PositionType() == POSITION_TYPE_BUY)
               {
                  newStopLoss = openPrice + trailDistance;
                  if(newStopLoss > stopLoss && newStopLoss < currentPrice)
                  {
                     m_trade.PositionModify(m_position.Ticket(), newStopLoss, takeProfit);
                  }
               }
               else if(m_position.PositionType() == POSITION_TYPE_SELL)
               {
                  newStopLoss = openPrice - trailDistance;
                  if(newStopLoss < stopLoss && newStopLoss > currentPrice)
                  {
                     m_trade.PositionModify(m_position.Ticket(), newStopLoss, takeProfit);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get ATR value for current symbol                                 |
//+------------------------------------------------------------------+
double CTradeManager::GetATRValue()
{
   double atrArray[];
   ArraySetAsSeries(atrArray, true);
   
   int copied = CopyBuffer(iATR(m_symbol.Name(), ATR_Timeframe, ATR_Period), 0, 0, 1, atrArray);
   
   if(copied > 0)
      return atrArray[0];
   
   return 0;
}

//+------------------------------------------------------------------+
//| Place buy stop order                                             |
//+------------------------------------------------------------------+
bool CTradeManager::BuyStop(double price, double stopLoss, double takeProfit, string comment="")
{
   if(!CanOpenNewTrade())
      return false;
   
   double lotSize = CalculateLotSize(MathAbs(price - stopLoss) / m_symbol.Point());
   
   if(lotSize <= 0)
   {
      Print("Error: Invalid lot size calculated");
      return false;
   }
   
   bool result = m_trade.BuyStop(lotSize, price, m_symbol.Name(), stopLoss, takeProfit, ORDER_TIME_GTC, 0, comment);
   
   if(result)
   {
      m_lastTradeTime = TimeCurrent();
      m_tradesToday++;
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Place sell stop order                                            |
//+------------------------------------------------------------------+
bool CTradeManager::SellStop(double price, double stopLoss, double takeProfit, string comment="")
{
   if(!CanOpenNewTrade())
      return false;
   
   double lotSize = CalculateLotSize(MathAbs(price - stopLoss) / m_symbol.Point());
   
   if(lotSize <= 0)
   {
      Print("Error: Invalid lot size calculated");
      return false;
   }
   
   bool result = m_trade.SellStop(lotSize, price, m_symbol.Name(), stopLoss, takeProfit, ORDER_TIME_GTC, 0, comment);
   
   if(result)
   {
      m_lastTradeTime = TimeCurrent();
      m_tradesToday++;
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Execute buy market order                                         |
//+------------------------------------------------------------------+
bool CTradeManager::Buy(double stopLoss, double takeProfit, string comment="")
{
   if(!CanOpenNewTrade())
      return false;
   
   double currentPrice = m_symbol.Ask();
   double lotSize = CalculateLotSize(MathAbs(currentPrice - stopLoss) / m_symbol.Point());
   
   if(lotSize <= 0)
   {
      Print("Error: Invalid lot size calculated");
      return false;
   }
   
   bool result = m_trade.Buy(lotSize, m_symbol.Name(), currentPrice, stopLoss, takeProfit, comment);
   
   if(result)
   {
      m_lastTradeTime = TimeCurrent();
      m_tradesToday++;
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Execute sell market order                                        |
//+------------------------------------------------------------------+
bool CTradeManager::Sell(double stopLoss, double takeProfit, string comment="")
{
   if(!CanOpenNewTrade())
      return false;
   
   double currentPrice = m_symbol.Bid();
   double lotSize = CalculateLotSize(MathAbs(currentPrice - stopLoss) / m_symbol.Point());
   
   if(lotSize <= 0)
   {
      Print("Error: Invalid lot size calculated");
      return false;
   }
   
   bool result = m_trade.Sell(lotSize, m_symbol.Name(), currentPrice, stopLoss, takeProfit, comment);
   
   if(result)
   {
      m_lastTradeTime = TimeCurrent();
      m_tradesToday++;
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
bool CTradeManager::CloseAllPositions()
{
   bool result = true;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == m_symbol.Name())
         {
            if(!m_trade.PositionClose(m_position.Ticket()))
               result = false;
         }
      }
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Close specific position                                          |
//+------------------------------------------------------------------+
bool CTradeManager::ClosePosition(ulong ticket)
{
   if(m_position.SelectByTicket(ticket))
   {
      return m_trade.PositionClose(ticket);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Modify position                                                  |
//+------------------------------------------------------------------+
bool CTradeManager::ModifyPosition(ulong ticket, double stopLoss, double takeProfit)
{
   if(m_position.SelectByTicket(ticket))
   {
      return m_trade.PositionModify(ticket, stopLoss, takeProfit);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Delete all pending orders                                        |
//+------------------------------------------------------------------+
bool CTradeManager::DeleteAllPending()
{
   bool result = true;
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(m_order.SelectByIndex(i))
      {
         if(m_order.Symbol() == m_symbol.Name())
         {
            if(!m_trade.OrderDelete(m_order.Ticket()))
               result = false;
         }
      }
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Delete specific pending order                                    |
//+------------------------------------------------------------------+
bool CTradeManager::DeletePending(ulong ticket)
{
   if(m_order.SelectByTicket(ticket))
   {
      return m_trade.OrderDelete(ticket);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if new trade can be opened                                 |
//+------------------------------------------------------------------+
bool CTradeManager::CanOpenNewTrade()
{
   return (CheckMaxTrades() && 
           CheckMinTimeBetweenTrades() && 
           CheckDailyTradesLimit() && 
           CheckDailyDrawdown());
}

//+------------------------------------------------------------------+
//| Check if should close positions on Friday                        |
//+------------------------------------------------------------------+
bool CTradeManager::ShouldCloseFriday()
{
   return CheckWeekendClose();
}

//+------------------------------------------------------------------+
//| OnTick update method                                             |
//+------------------------------------------------------------------+
void CTradeManager::OnTick()
{
   // Update trailing stops
   UpdateTrailingStop();
   
   // Check daily drawdown
   CheckDailyDrawdown();
   
   // Check Friday close
   if(ShouldCloseFriday())
   {
      CloseAllPositions();
      DeleteAllPending();
   }
}

//+------------------------------------------------------------------+
//| Reset daily counters                                             |
//+------------------------------------------------------------------+
void CTradeManager::ResetDaily()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   static int lastResetDay = -1;
   
   if(timeStruct.day != lastResetDay)
   {
      m_tradesToday = 0;
      m_dailyEquityHigh = m_account.Equity();
      m_dailyDDTriggered = false;
      lastResetDay = timeStruct.day;
   }
}

//+------------------------------------------------------------------+
//| Get count of open positions                                      |
//+------------------------------------------------------------------+
int CTradeManager::GetOpenPositionsCount()
{
   int count = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == m_symbol.Name())
            count++;
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Get count of pending orders                                      |
//+------------------------------------------------------------------+
int CTradeManager::GetPendingOrdersCount()
{
   int count = 0;
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(m_order.SelectByIndex(i))
      {
         if(m_order.Symbol() == m_symbol.Name())
            count++;
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Get daily profit/loss                                            |
//+------------------------------------------------------------------+
double CTradeManager::GetDailyPL()
{
   double dailyPL = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == m_symbol.Name())
         {
            // Check if position was opened today
            MqlDateTime posTime, currentTime;
            TimeToStruct(m_position.Time(), posTime);
            TimeToStruct(TimeCurrent(), currentTime);
            
            if(posTime.day == currentTime.day && 
               posTime.mon == currentTime.mon && 
               posTime.year == currentTime.year)
            {
               dailyPL += m_position.Profit();
            }
         }
      }
   }
   
   return dailyPL;
}
//+------------------------------------------------------------------+