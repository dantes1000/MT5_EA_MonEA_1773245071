//+------------------------------------------------------------------+
//|                                                      RiskManager.mqh |
//|                        Copyright 2024, Your Company Name            |
//|                                       https://www.yourwebsite.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Company Name"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Risk Manager Class                                               |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   // Trade objects
   CTrade           m_trade;
   CSymbolInfo      m_symbol;
   CPositionInfo    m_position;
   CAccountInfo     m_account;
   
   // Input parameters
   double           m_riskPercent;          // Risk percentage per trade (0.5-1%)
   double           m_minLot;               // Minimum lot size
   double           m_maxLot;               // Maximum lot size
   double           m_dailyLossLimit;       // Daily loss limit percentage (4-5%)
   bool             m_weekendClose;         // Close positions before weekend
   int              m_closeHourFri;         // Friday close hour (GMT)
   int              m_closeMinuteFri;       // Friday close minute (GMT)
   bool             m_closeIfInProfit;      // Close only if in profit
   int              m_maxOpenTrades;        // Maximum open trades (1)
   
   // Internal variables
   double           m_initialEquity;        // Equity at start of day
   datetime         m_lastTradeTime;        // Time of last trade
   double           m_dailyLoss;            // Daily loss amount
   
public:
   // Constructor
   CRiskManager() : 
      m_riskPercent(1.0),
      m_minLot(0.01),
      m_maxLot(5.0),
      m_dailyLossLimit(5.0),
      m_weekendClose(true),
      m_closeHourFri(21),
      m_closeMinuteFri(0),
      m_closeIfInProfit(true),
      m_maxOpenTrades(1),
      m_initialEquity(0),
      m_lastTradeTime(0),
      m_dailyLoss(0)
   {
      // Initialize trade object
      m_trade.SetExpertMagicNumber(12345);
      m_trade.SetDeviationInPoints(10);
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   }
   
   // Destructor
   ~CRiskManager() {}
   
   // Set input parameters
   void SetParameters(double riskPercent, double minLot, double maxLot, 
                      double dailyLossLimit, bool weekendClose, 
                      int closeHourFri, int closeMinuteFri, bool closeIfInProfit,
                      int maxOpenTrades)
   {
      m_riskPercent = MathMax(0.1, MathMin(riskPercent, 10.0));
      m_minLot = MathMax(0.01, minLot);
      m_maxLot = MathMax(m_minLot, maxLot);
      m_dailyLossLimit = MathMax(1.0, MathMin(dailyLossLimit, 20.0));
      m_weekendClose = weekendClose;
      m_closeHourFri = MathMax(0, MathMin(closeHourFri, 23));
      m_closeMinuteFri = MathMax(0, MathMin(closeMinuteFri, 59));
      m_closeIfInProfit = closeIfInProfit;
      m_maxOpenTrades = MathMax(1, maxOpenTrades);
   }
   
   // Calculate lot size based on equity risk percentage
   double CalculateLotSize(string symbol, double stopLossPips, double riskPercent = -1)
   {
      if(!m_symbol.Name(symbol))
         return m_minLot;
         
      // Use provided risk percent or default
      double riskPc = (riskPercent > 0) ? riskPercent : m_riskPercent;
      
      // Get current free margin (equity)
      double equity = m_account.FreeMargin();
      if(equity <= 0) return m_minLot;
      
      // Calculate risk amount in account currency
      double riskAmount = equity * (riskPc / 100.0);
      
      // Calculate pip value
      double pipValue = m_symbol.TickValue() * (m_symbol.TickSize() / m_symbol.Point());
      
      // Calculate lot size
      double lotSize = riskAmount / (stopLossPips * pipValue);
      
      // Adjust for symbol lot step
      double lotStep = m_symbol.LotsStep();
      lotSize = MathFloor(lotSize / lotStep) * lotStep;
      
      // Apply min/max limits
      lotSize = MathMax(m_minLot, MathMin(m_maxLot, lotSize));
      
      // Ensure lot size doesn't exceed margin requirements
      double marginRequired = m_symbol.MarginCheck(symbol, ORDER_TYPE_BUY, lotSize, m_symbol.Ask());
      double freeMargin = m_account.FreeMargin();
      
      if(marginRequired > freeMargin * 0.8) // Use 80% of free margin as safety
      {
         // Reduce lot size to fit margin
         double maxLotByMargin = (freeMargin * 0.8) / marginRequired * lotSize;
         lotSize = MathFloor(maxLotByMargin / lotStep) * lotStep;
         lotSize = MathMax(m_minLot, MathMin(m_maxLot, lotSize));
      }
      
      return lotSize;
   }
   
   // Calculate stop loss price based on range
   double CalculateStopLoss(string symbol, ENUM_ORDER_TYPE orderType, double rangeHigh, double rangeLow)
   {
      if(!m_symbol.Name(symbol))
         return 0;
         
      double stopLoss = 0;
      
      if(orderType == ORDER_TYPE_BUY)
      {
         // For buy orders, SL at range low
         stopLoss = rangeLow;
         
         // Add some buffer (optional)
         double buffer = m_symbol.Point() * 10; // 10 pips buffer
         stopLoss -= buffer;
      }
      else if(orderType == ORDER_TYPE_SELL)
      {
         // For sell orders, SL at range high
         stopLoss = rangeHigh;
         
         // Add some buffer (optional)
         double buffer = m_symbol.Point() * 10; // 10 pips buffer
         stopLoss += buffer;
      }
      
      return NormalizeDouble(stopLoss, m_symbol.Digits());
   }
   
   // Calculate take profit price based on risk/reward ratio
   double CalculateTakeProfit(string symbol, ENUM_ORDER_TYPE orderType, 
                              double entryPrice, double stopLossPrice, double riskRewardRatio)
   {
      if(!m_symbol.Name(symbol))
         return 0;
         
      double takeProfit = 0;
      double stopLossDistance = MathAbs(entryPrice - stopLossPrice);
      
      if(orderType == ORDER_TYPE_BUY)
      {
         takeProfit = entryPrice + (stopLossDistance * riskRewardRatio);
      }
      else if(orderType == ORDER_TYPE_SELL)
      {
         takeProfit = entryPrice - (stopLossDistance * riskRewardRatio);
      }
      
      return NormalizeDouble(takeProfit, m_symbol.Digits());
   }
   
   // Calculate take profit based on ATR
   double CalculateTakeProfitATR(string symbol, ENUM_ORDER_TYPE orderType, 
                                 double entryPrice, double atrValue, double atrMultiplier)
   {
      if(!m_symbol.Name(symbol))
         return 0;
         
      double takeProfit = 0;
      
      if(orderType == ORDER_TYPE_BUY)
      {
         takeProfit = entryPrice + (atrValue * atrMultiplier);
      }
      else if(orderType == ORDER_TYPE_SELL)
      {
         takeProfit = entryPrice - (atrValue * atrMultiplier);
      }
      
      return NormalizeDouble(takeProfit, m_symbol.Digits());
   }
   
   // Check daily drawdown limit
   bool CheckDailyDrawdown()
   {
      // Reset at start of new day
      MqlDateTime currentTime;
      TimeToStruct(TimeCurrent(), currentTime);
      
      static int lastDay = -1;
      if(lastDay != currentTime.day)
      {
         m_initialEquity = m_account.Equity();
         m_dailyLoss = 0;
         lastDay = currentTime.day;
         return true; // New day, no drawdown yet
      }
      
      // Calculate current drawdown
      double currentEquity = m_account.Equity();
      double drawdownAmount = m_initialEquity - currentEquity;
      double drawdownPercent = (m_initialEquity > 0) ? (drawdownAmount / m_initialEquity * 100.0) : 0;
      
      m_dailyLoss = drawdownAmount;
      
      // Check if drawdown exceeds limit
      if(drawdownPercent >= m_dailyLossLimit)
      {
         Print("Daily drawdown limit reached: ", drawdownPercent, "%");
         return false;
      }
      
      return true;
   }
   
   // Close all positions if daily drawdown limit reached
   void HandleDailyDrawdown()
   {
      if(!CheckDailyDrawdown())
      {
         Print("Closing all positions due to daily drawdown limit");
         CloseAllPositions();
         
         // Disable EA trading (optional - can be handled by main EA)
         // ExpertRemove();
      }
   }
   
   // Close all open positions
   void CloseAllPositions()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(m_position.SelectByIndex(i))
         {
            if(m_position.Symbol() == m_symbol.Name())
            {
               m_trade.PositionClose(m_position.Ticket());
            }
         }
      }
   }
   
   // Check if weekend closing is needed
   bool CheckWeekendClosing()
   {
      if(!m_weekendClose)
         return false;
         
      MqlDateTime currentTime;
      TimeToStruct(TimeCurrent(), currentTime);
      
      // Check if it's Friday
      if(currentTime.day_of_week == 5) // Friday
      {
         // Check if current time is after close time
         int currentHour = currentTime.hour;
         int currentMinute = currentTime.min;
         
         int currentTotalMinutes = currentHour * 60 + currentMinute;
         int closeTotalMinutes = m_closeHourFri * 60 + m_closeMinuteFri;
         
         if(currentTotalMinutes >= closeTotalMinutes)
         {
            return true;
         }
      }
      
      return false;
   }
   
   // Handle weekend position closing
   void HandleWeekendClosing()
   {
      if(CheckWeekendClosing())
      {
         int positionsCount = PositionsTotal();
         
         if(positionsCount > 0)
         {
            Print("Weekend closing activated");
            
            if(m_closeIfInProfit)
            {
               // Close only profitable positions
               for(int i = positionsCount - 1; i >= 0; i--)
               {
                  if(m_position.SelectByIndex(i))
                  {
                     if(m_position.Profit() > 0)
                     {
                        m_trade.PositionClose(m_position.Ticket());
                        Print("Closed profitable position for weekend: Ticket ", m_position.Ticket());
                     }
                  }
               }
            }
            else
            {
               // Close all positions
               CloseAllPositions();
               Print("Closed all positions for weekend");
            }
         }
      }
   }
   
   // Check if maximum open trades limit is reached
   bool CheckMaxOpenTrades(string symbol = "")
   {
      int openTrades = 0;
      
      for(int i = 0; i < PositionsTotal(); i++)
      {
         if(m_position.SelectByIndex(i))
         {
            if(symbol == "" || m_position.Symbol() == symbol)
            {
               openTrades++;
            }
         }
      }
      
      return (openTrades < m_maxOpenTrades);
   }
   
   // Get current daily loss
   double GetDailyLoss() const { return m_dailyLoss; }
   
   // Get daily loss percentage
   double GetDailyLossPercent() const
   {
      return (m_initialEquity > 0) ? (m_dailyLoss / m_initialEquity * 100.0) : 0;
   }
   
   // Update last trade time
   void UpdateLastTradeTime() { m_lastTradeTime = TimeCurrent(); }
   
   // Get time since last trade in hours
   double GetTimeSinceLastTrade()
   {
      if(m_lastTradeTime == 0) return 999; // No trades yet
      
      double hours = (TimeCurrent() - m_lastTradeTime) / 3600.0;
      return hours;
   }
   
   // Check if minimum time between trades has passed
   bool CheckMinTimeBetweenTrades(double minHours)
   {
      return (GetTimeSinceLastTrade() >= minHours);
   }
   
   // Calculate position size based on volatility (ATR)
   double CalculateVolatilityBasedLotSize(string symbol, double atrValue, double riskPercent = -1)
   {
      if(!m_symbol.Name(symbol))
         return m_minLot;
         
      // Convert ATR to pips
      double atrPips = atrValue / m_symbol.Point();
      
      // Use ATR as stop loss distance
      return CalculateLotSize(symbol, atrPips, riskPercent);
   }
   
   // Validate lot size against broker limits
   bool ValidateLotSize(string symbol, double &lotSize)
   {
      if(!m_symbol.Name(symbol))
         return false;
         
      // Check against symbol limits
      double minAllowed = m_symbol.LotsMin();
      double maxAllowed = m_symbol.LotsMax();
      double lotStep = m_symbol.LotsStep();
      
      // Apply limits
      lotSize = MathMax(minAllowed, MathMin(maxAllowed, lotSize));
      
      // Round to lot step
      lotSize = MathFloor(lotSize / lotStep) * lotStep;
      
      // Apply EA's min/max limits
      lotSize = MathMax(m_minLot, MathMin(m_maxLot, lotSize));
      
      return (lotSize >= m_minLot && lotSize <= m_maxLot);
   }
   
   // Calculate position value
   double CalculatePositionValue(string symbol, double lotSize, double price)
   {
      if(!m_symbol.Name(symbol))
         return 0;
         
      return m_symbol.NormalizeVolume(lotSize) * m_symbol.ContractSize() * price;
   }
   
   // Calculate required margin for position
   double CalculateRequiredMargin(string symbol, ENUM_ORDER_TYPE orderType, double lotSize, double price)
   {
      if(!m_symbol.Name(symbol))
         return 0;
         
      return m_symbol.MarginCheck(symbol, orderType, lotSize, price);
   }
   
   // Check if enough margin is available
   bool CheckMarginAvailable(string symbol, ENUM_ORDER_TYPE orderType, double lotSize, double price)
   {
      double requiredMargin = CalculateRequiredMargin(symbol, orderType, lotSize, price);
      double freeMargin = m_account.FreeMargin();
      
      // Use 80% of free margin as safety buffer
      return (requiredMargin <= freeMargin * 0.8);
   }
   
   // Get account information
   double GetAccountEquity() const { return m_account.Equity(); }
   double GetAccountBalance() const { return m_account.Balance(); }
   double GetAccountFreeMargin() const { return m_account.FreeMargin(); }
   double GetAccountMargin() const { return m_account.Margin(); }
   
   // Calculate risk/reward ratio for a position
   double CalculateRiskRewardRatio(double entryPrice, double stopLoss, double takeProfit)
   {
      if(stopLoss == 0 || entryPrice == stopLoss)
         return 0;
         
      double risk = MathAbs(entryPrice - stopLoss);
      double reward = MathAbs(takeProfit - entryPrice);
      
      return (risk > 0) ? (reward / risk) : 0;
   }
   
   // Calculate breakeven price
   double CalculateBreakevenPrice(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss, double spread)
   {
      if(orderType == ORDER_TYPE_BUY)
      {
         return entryPrice + MathAbs(entryPrice - stopLoss) + spread;
      }
      else if(orderType == ORDER_TYPE_SELL)
      {
         return entryPrice - MathAbs(entryPrice - stopLoss) - spread;
      }
      
      return 0;
   }
   
   // Calculate trailing stop price
   double CalculateTrailingStop(string symbol, ENUM_ORDER_TYPE orderType, 
                                double currentPrice, double atrValue, double atrMultiplier)
   {
      if(!m_symbol.Name(symbol))
         return 0;
         
      double trailingStop = 0;
      double trailDistance = atrValue * atrMultiplier;
      
      if(orderType == ORDER_TYPE_BUY)
      {
         trailingStop = currentPrice - trailDistance;
      }
      else if(orderType == ORDER_TYPE_SELL)
      {
         trailingStop = currentPrice + trailDistance;
      }
      
      return NormalizeDouble(trailingStop, m_symbol.Digits());
   }
   
   // Check if trailing stop should be activated
   bool ShouldActivateTrailingStop(double currentProfit, double targetProfit, double activationPercent)
   {
      if(targetProfit <= 0) return false;
      
      double profitPercent = (currentProfit / targetProfit) * 100.0;
      return (profitPercent >= activationPercent);
   }
};

//+------------------------------------------------------------------+
//| Risk Manager Input Parameters                                    |
//+------------------------------------------------------------------+
input group "=== Risk Management Settings ==="
input double   InpRiskPercent        = 1.0;      // Risk percentage per trade (0.5-1%)
input double   InpMinLot             = 0.01;     // Minimum lot size
input double   InpMaxLot             = 5.0;      // Maximum lot size
input double   InpDailyLossLimit     = 5.0;      // Daily loss limit percentage (4-5%)
input bool     InpWeekendClose       = true;     // Close positions before weekend
input int      InpCloseHourFri       = 21;       // Friday close hour (GMT)
input int      InpCloseMinuteFri     = 0;        // Friday close minute (GMT)
input bool     InpCloseIfInProfit    = true;     // Close only if in profit
input int      InpMaxOpenTrades      = 1;        // Maximum open trades (1)

//+------------------------------------------------------------------+
//| Global Risk Manager Instance                                     |
//+------------------------------------------------------------------+
CRiskManager RiskManager;

//+------------------------------------------------------------------+
//| Initialize Risk Manager                                          |
//+------------------------------------------------------------------+
void InitializeRiskManager()
{
   RiskManager.SetParameters(InpRiskPercent, InpMinLot, InpMaxLot,
                            InpDailyLossLimit, InpWeekendClose,
                            InpCloseHourFri, InpCloseMinuteFri,
                            InpCloseIfInProfit, InpMaxOpenTrades);
}

//+------------------------------------------------------------------+
//| Check Trading Conditions                                         |
//+------------------------------------------------------------------+
bool CheckTradingConditions(string symbol, double minTimeBetweenTrades = 1.0)
{
   // Check daily drawdown
   RiskManager.HandleDailyDrawdown();
   
   // Check weekend closing
   RiskManager.HandleWeekendClosing();
   
   // Check maximum open trades
   if(!RiskManager.CheckMaxOpenTrades(symbol))
   {
      Print("Maximum open trades limit reached for ", symbol);
      return false;
   }
   
   // Check minimum time between trades
   if(!RiskManager.CheckMinTimeBetweenTrades(minTimeBetweenTrades))
   {
      Print("Minimum time between trades not met for ", symbol);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate Position Parameters                                    |
//+------------------------------------------------------------------+
bool CalculatePositionParams(string symbol, ENUM_ORDER_TYPE orderType,
                            double rangeHigh, double rangeLow,
                            double &lotSize, double &stopLoss,
                            double &takeProfit, double riskRewardRatio = 1.5,
                            double atrValue = 0, double atrTPMultiplier = 3.0,
                            string tpMethod = "Dynamic_ATR")
{
   // Calculate stop loss based on range
   stopLoss = RiskManager.CalculateStopLoss(symbol, orderType, rangeHigh, rangeLow);
   
   if(stopLoss == 0)
      return false;
   
   // Get entry price
   double entryPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) 
                                                     : SymbolInfoDouble(symbol, SYMBOL_BID);
   
   // Calculate stop loss distance in pips
   double stopLossPips = MathAbs(entryPrice - stopLoss) / SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   // Calculate lot size based on risk
   lotSize = RiskManager.CalculateLotSize(symbol, stopLossPips);
   
   // Validate lot size
   if(!RiskManager.ValidateLotSize(symbol, lotSize))
      return false;
   
   // Calculate take profit
   if(tpMethod == "Dynamic_ATR" && atrValue > 0)
   {
      takeProfit = RiskManager.CalculateTakeProfitATR(symbol, orderType, entryPrice, atrValue, atrTPMultiplier);
   }
   else
   {
      takeProfit = RiskManager.CalculateTakeProfit(symbol, orderType, entryPrice, stopLoss, riskRewardRatio);
   }
   
   // Check margin availability
   if(!RiskManager.CheckMarginAvailable(symbol, orderType, lotSize, entryPrice))
   {
      Print("Insufficient margin for trade on ", symbol);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Update Trailing Stop                                             |
//+------------------------------------------------------------------+
void UpdateTrailingStop(string symbol, double atrValue, double atrMultiplier = 0.5,
                       double activationPercent = 50.0)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == symbol)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentStopLoss = PositionGetDouble(POSITION_SL);
         double currentTakeProfit = PositionGetDouble(POSITION_TP);
         double profit = PositionGetDouble(POSITION_PROFIT);
         
         // Calculate target profit
         double targetProfit = 0;
         if(currentTakeProfit > 0)
         {
            if(orderType == ORDER_TYPE_BUY)
               targetProfit = (currentTakeProfit - openPrice) * PositionGetDouble(POSITION_VOLUME) * 100000;
            else if(orderType == ORDER_TYPE_SELL)
               targetProfit = (openPrice - currentTakeProfit) * PositionGetDouble(POSITION_VOLUME) * 100000;
         }
         
         // Check if trailing stop should be activated
         if(RiskManager.ShouldActivateTrailingStop(profit, targetProfit, activationPercent))
         {
            // Calculate new trailing stop
            double newStopLoss = RiskManager.CalculateTrailingStop(symbol, orderType, 
                                                                  currentPrice, atrValue, atrMultiplier);
            
            // Update stop loss if it improves position
            if((orderType == ORDER_TYPE_BUY && newStopLoss > currentStopLoss) ||
               (orderType == ORDER_TYPE_SELL && newStopLoss < currentStopLoss))
            {
               CTrade trade;
               trade.PositionModify(ticket, newStopLoss, currentTakeProfit);
               Print("Trailing stop updated for position ", ticket, ": New SL = ", newStopLoss);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get Risk Statistics                                              |
//+------------------------------------------------------------------+
string GetRiskStatistics()
{
   string stats = "";
   stats += "Account Equity: $" + DoubleToString(RiskManager.GetAccountEquity(), 2) + "\n";
   stats += "Account Balance: $" + DoubleToString(RiskManager.GetAccountBalance(), 2) + "\n";
   stats += "Free Margin: $" + DoubleToString(RiskManager.GetAccountFreeMargin(), 2) + "\n";
   stats += "Daily Loss: $" + DoubleToString(RiskManager.GetDailyLoss(), 2) + "\n";
   stats += "Daily Loss %: " + DoubleToString(RiskManager.GetDailyLossPercent(), 2) + "%\n";
   stats += "Time since last trade: " + DoubleToString(RiskManager.GetTimeSinceLastTrade(), 2) + " hours\n";
   
   return stats;
}

//+------------------------------------------------------------------+
