//+------------------------------------------------------------------+
//|                                 RangeBreakoutAsianEA.mq5         |
//|                        Copyright 2024, Your Company Name         |
//|                                       https://www.yourwebsite.com|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Company Name"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property strict

//--- Include necessary files
#include <RangeBreakoutAsianEA/Config.mqh>
#include <RangeBreakoutAsianEA/Indicators.mqh>
#include <RangeBreakoutAsianEA/RiskManagement.mqh>
#include <RangeBreakoutAsianEA/TradeManagement.mqh>
#include <RangeBreakoutAsianEA/NewsFilter.mqh>
#include <RangeBreakoutAsianEA/Utilities.mqh>

//--- Input parameters (main configuration)
input string   Strategy_Settings="--- Strategy Settings ---";
input ENUM_TIMEFRAMES RangeTF = PERIOD_D1;          // Timeframe for Asian range analysis
input ENUM_TIMEFRAMES ExecTF = PERIOD_M15;          // Timeframe for trade execution
input int      Asian_Session_Start = 0;             // Asian session start hour (GMT)
input int      Asian_Session_End = 6;               // Asian session end hour (GMT)
input int      London_Session_Open = 8;             // London session open hour (GMT)
input int      Valid_Break_End = 11;                // Valid breakout end hour (GMT)
input int      Margin_Pips = 5;                     // Margin for range calculation (pips)
input string   Range_Calc = "Closed_Candles";       // Range calculation method
input string   Early_Break_Action = "Cancel";       // Action on early breakout (Cancel/Adjust)

input string   Indicator_Settings="--- Indicator Settings ---";
input int      ATR_Period = 14;                     // ATR period
input double   ATR_Mult_Min = 1.25;                 // Minimum ATR multiplier for range filter
input double   ATR_Mult_Max = 3.0;                  // Maximum ATR multiplier for range filter
input ENUM_TIMEFRAMES ATR_Timeframe = PERIOD_H1;    // Timeframe for ATR calculation
input bool     Vol_Confirm = true;                  // Enable volume confirmation
input string   Vol_Confirm_Type = "Real";           // Volume type (Real/Tick)
input int      Vol_Period = 20;                     // Volume SMA period
input double   Vol_Mult_Threshold = 1.5;            // Volume multiplier threshold
input string   Trend_Filter = "EMA_ADX";            // Trend filter type (Strict/EMA_ADX/None)
input int      EMA_Period = 200;                    // EMA period for trend filter
input ENUM_TIMEFRAMES EMA_TF = PERIOD_H1;           // Timeframe for EMA
input int      ADX_Period = 14;                     // ADX period
input int      ADX_Threshold = 20;                  // ADX threshold
input string   Vol_Filter = "BB";                   // Volatility filter (BB/None)
input int      BB_Period = 20;                      // Bollinger Bands period
input double   BB_Dev = 2.0;                        // Bollinger Bands deviation
input int      Min_Width_Pips = 30;                 // Minimum range width (pips)
input int      Max_Width_Pips = 120;                // Maximum range width (pips)

input string   Risk_Settings="--- Risk Management Settings ---";
input double   Risk_PC = 1.0;                       // Risk percentage per trade (0.5-1%)
input string   Lot_Method = "EquityRisk";           // Lot sizing method
input double   Min_Lot = 0.01;                      // Minimum lot size
input double   Max_Lot = 5.0;                       // Maximum lot size
input string   TP_Method = "Dynamic_ATR";           // Take Profit method (Dynamic_ATR/Fixed)
input double   ATR_TP_Mult = 3.0;                   // ATR multiplier for TP
input double   Fixed_RR = 1.5;                      // Fixed Risk/Reward ratio
input bool     Weekend_Close = true;                // Close positions before weekend
input int      Close_Hour_Fri = 21;                 // Friday close hour (GMT)
input bool     Close_If_In_Profit = true;           // Close only if in profit
input double   Daily_DD_Limit = 5.0;                // Daily drawdown limit (%)
input int      Max_Open_Trades = 1;                 // Maximum open trades
input bool     Allow_Add_If_Trailed = false;        // Allow new trade if previous trailed
input int      Min_Time_Between_Trades_Hrs = 1;     // Minimum time between trades (hours)
input int      Max_Trades_Per_Day = 3;              // Maximum trades per day

input string   Filter_Settings="--- Filter Settings ---";
input string   News_Filter = "FFCal";               // News filter type (FFCal/None)
input string   Impact_Level = "High";               // News impact level (High/Medium)
input int      Pause_Before_Min = 60;               // Pause before news (minutes)
input int      Pause_After_Min = 30;                // Pause after news (minutes)
input string   Allowed_Pairs = "EURUSD,GBPUSD,USDJPY"; // Allowed trading pairs
input int      Min_ATR_Pips = 20;                   // Minimum ATR (pips)
input int      Max_ATR_Pips = 150;                  // Maximum ATR (pips)

input string   Trailing_Settings="--- Trailing Stop Settings ---";
input double   Trail_Activation_PC = 50.0;          // Trailing activation percentage
input string   Trail_Method = "ATR";                // Trailing method (ATR/Fixed)
input double   Trail_Mult = 0.5;                    // Trailing multiplier for ATR

//--- Global variables
CIndicators    *indicators;
CRiskManagement *riskManager;
CTradeManagement *tradeManager;
CNewsFilter    *newsFilter;
CUtilities     *utils;

//--- Session and range variables
datetime       lastTradeTime;
double         asianHigh, asianLow;
double         breakoutHigh, breakoutLow;
bool           rangeCalculated;
int            tradesToday;
datetime       lastTradeDay;
double         dailyEquityStart;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Initialize objects
   indicators = new CIndicators(ATR_Period, ATR_Timeframe, EMA_Period, EMA_TF, ADX_Period, BB_Period, BB_Dev, Vol_Period);
   riskManager = new CRiskManagement(Risk_PC, Min_Lot, Max_Lot, Daily_DD_Limit, Min_ATR_Pips, Max_ATR_Pips);
   tradeManager = new CTradeManagement(Max_Open_Trades, Allow_Add_If_Trailed, Trail_Activation_PC, Trail_Method, Trail_Mult, TP_Method, ATR_TP_Mult, Fixed_RR);
   newsFilter = new CNewsFilter(News_Filter, Impact_Level, Pause_Before_Min, Pause_After_Min);
   utils = new CUtilities(Allowed_Pairs, Min_Time_Between_Trades_Hrs, Max_Trades_Per_Day, Margin_Pips);
   
   //--- Initialize variables
   rangeCalculated = false;
   lastTradeTime = 0;
   tradesToday = 0;
   lastTradeDay = 0;
   dailyEquityStart = AccountInfoDouble(ACCOUNT_EQUITY);
   
   //--- Check if current symbol is allowed
   if(!utils.IsSymbolAllowed(Symbol()))
   {
      Print("Symbol not allowed for trading: ", Symbol());
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   //--- Set timer for periodic checks (every minute)
   EventSetTimer(60);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Delete objects
   delete indicators;
   delete riskManager;
   delete tradeManager;
   delete newsFilter;
   delete utils;
   
   //--- Remove timer
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if trading is allowed
   if(!IsTradingAllowed())
      return;
   
   //--- Check daily drawdown limit
   if(riskManager.CheckDailyDrawdown(dailyEquityStart))
   {
      tradeManager.CloseAllTrades();
      ExpertRemove();
      return;
   }
   
   //--- Check weekend close condition
   if(Weekend_Close && utils.IsWeekendCloseTime(Close_Hour_Fri))
   {
      if(!Close_If_In_Profit || tradeManager.IsAnyTradeInProfit())
         tradeManager.CloseAllTrades();
      return;
   }
   
   //--- Reset daily counters if new day
   if(utils.IsNewDay(lastTradeDay))
   {
      tradesToday = 0;
      lastTradeDay = TimeCurrent();
      dailyEquityStart = AccountInfoDouble(ACCOUNT_EQUITY);
   }
   
   //--- Calculate Asian range at the end of Asian session
   if(!rangeCalculated && utils.IsAsianSessionEnd(Asian_Session_End))
   {
      CalculateAsianRange();
      rangeCalculated = true;
   }
   
   //--- Reset range calculation at midnight GMT
   if(utils.IsMidnightGMT())
   {
      rangeCalculated = false;
      asianHigh = 0;
      asianLow = 0;
   }
   
   //--- Place pending orders after London open if range is calculated
   if(rangeCalculated && utils.IsLondonSessionOpen(London_Session_Open) && tradesToday < Max_Trades_Per_Day)
   {
      PlacePendingOrders();
   }
   
   //--- Check for breakout and manage trades
   ManageTrades();
   
   //--- Update trailing stops
   tradeManager.UpdateTrailingStops(indicators.GetATR());
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   //--- Periodic checks (e.g., news filter updates)
   newsFilter.UpdateNewsEvents();
}

//+------------------------------------------------------------------+
//| Calculate Asian range                                            |
//+------------------------------------------------------------------+
void CalculateAsianRange()
{
   datetime sessionStart = utils.GetSessionStartTime(Asian_Session_Start);
   datetime sessionEnd = utils.GetSessionEndTime(Asian_Session_End);
   
   //--- Get high and low during Asian session
   asianHigh = iHigh(Symbol(), RangeTF, iBarShift(Symbol(), RangeTF, sessionStart));
   asianLow = iLow(Symbol(), RangeTF, iBarShift(Symbol(), RangeTF, sessionStart));
   
   //--- Adjust with margin
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double margin = Margin_Pips * point * 10;
   asianHigh += margin;
   asianLow -= margin;
   
   //--- Calculate breakout levels
   breakoutHigh = asianHigh;
   breakoutLow = asianLow;
   
   Print("Asian Range Calculated: High=", asianHigh, " Low=", asianLow);
}

//+------------------------------------------------------------------+
//| Place pending orders                                             |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
   //--- Check if we already have pending orders or open trades
   if(tradeManager.HasOpenTrades() || tradeManager.HasPendingOrders())
      return;
   
   //--- Check minimum time between trades
   if(!utils.CheckMinTimeBetweenTrades(lastTradeTime, Min_Time_Between_Trades_Hrs))
      return;
   
   //--- Check news filter
   if(newsFilter.IsNewsEvent())
   {
      Print("Trading paused due to news event");
      return;
   }
   
   //--- Check volatility filters
   double atrValue = indicators.GetATR();
   double rangeWidth = (asianHigh - asianLow) / (SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10);
   
   if(!riskManager.CheckVolatilityFilters(atrValue, rangeWidth, Min_Width_Pips, Max_Width_Pips))
      return;
   
   //--- Check trend filter
   if(!indicators.CheckTrendFilter(Trend_Filter, ADX_Threshold))
      return;
   
   //--- Calculate lot size
   double stopLossPips = (asianHigh - asianLow) / (SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10);
   double lotSize = riskManager.CalculateLotSize(stopLossPips, Lot_Method);
   
   if(lotSize <= 0)
      return;
   
   //--- Place buy stop order
   double buyStopPrice = breakoutHigh;
   double buySL = asianLow;
   double buyTP = tradeManager.CalculateTP(buyStopPrice, buySL, atrValue);
   
   if(tradeManager.PlaceBuyStopOrder(lotSize, buyStopPrice, buySL, buyTP))
      Print("Buy Stop order placed at: ", buyStopPrice);
   
   //--- Place sell stop order
   double sellStopPrice = breakoutLow;
   double sellSL = asianHigh;
   double sellTP = tradeManager.CalculateTP(sellStopPrice, sellSL, atrValue);
   
   if(tradeManager.PlaceSellStopOrder(lotSize, sellStopPrice, sellSL, sellTP))
      Print("Sell Stop order placed at: ", sellStopPrice);
}

//+------------------------------------------------------------------+
//| Manage trades                                                    |
//+------------------------------------------------------------------+
void ManageTrades()
{
   //--- Check for early breakout
   if(rangeCalculated && utils.IsBeforeLondonOpen(London_Session_Open))
   {
      double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      
      if(currentPrice >= breakoutHigh || currentPrice <= breakoutLow)
      {
         if(Early_Break_Action == "Cancel")
         {
            tradeManager.DeleteAllPendingOrders();
            rangeCalculated = false;
            Print("Early breakout detected, pending orders cancelled");
         }
         return;
      }
   }
   
   //--- Check for valid breakout after London open
   if(rangeCalculated && utils.IsAfterLondonOpen(London_Session_Open) && utils.IsBeforeValidBreakEnd(Valid_Break_End))
   {
      //--- Check if any pending order was triggered
      if(tradeManager.CheckPendingOrderTriggered())
      {
         //--- Delete opposite pending order
         tradeManager.DeleteOppositePendingOrder();
         
         //--- Update trade counters
         tradesToday++;
         lastTradeTime = TimeCurrent();
         
         //--- Check volume confirmation
         if(Vol_Confirm && !indicators.CheckVolumeConfirmation(Vol_Confirm_Type, Vol_Mult_Threshold))
         {
            //--- Volume confirmation failed, close the trade
            tradeManager.CloseAllTrades();
            Print("Trade closed due to lack of volume confirmation");
         }
         
         //--- Check ATR breakout confirmation
         double atrValue = indicators.GetATR();
         double breakoutDistance = MathAbs(SymbolInfoDouble(Symbol(), SYMBOL_BID) - (asianHigh + asianLow) / 2);
         
         if(breakoutDistance < atrValue * ATR_Mult_Min)
         {
            tradeManager.CloseAllTrades();
            Print("Trade closed due to insufficient breakout distance");
         }
      }
   }
   
   //--- Check if valid breakout period has ended
   if(rangeCalculated && utils.IsAfterValidBreakEnd(Valid_Break_End))
   {
      tradeManager.DeleteAllPendingOrders();
      rangeCalculated = false;
      Print("Valid breakout period ended, pending orders deleted");
   }
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
   //--- Check if expert is allowed to trade
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Print("Trading is not allowed");
      return false;
   }
   
   //--- Check if symbol is allowed
   if(!utils.IsSymbolAllowed(Symbol()))
      return false;
   
   //--- Check news filter
   if(newsFilter.IsNewsEvent())
      return false;
   
   //--- Check market volatility
   double atrValue = indicators.GetATR();
   if(!riskManager.CheckATRLimits(atrValue))
      return false;
   
   return true;
}
//+------------------------------------------------------------------+