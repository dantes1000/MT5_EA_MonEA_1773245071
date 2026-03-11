//+------------------------------------------------------------------+
//|                                                      Utilities.mqh |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Utility functions for pip calculations, time conversions,        |
//| error logging, and input parameter validation                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Pip calculation functions                                        |
//+------------------------------------------------------------------+

//--- Calculate pip value for the current symbol
double PipValue()
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if (point == 0 || tickSize == 0) return 0;
   
   return (tickValue * point) / tickSize;
}

//--- Convert pips to price points
double PipsToPoints(double pips)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double digits = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   if (digits <= 3) // JPY pairs
      return pips * 0.01;
   else
      return pips * 0.0001 / point;
}

//--- Calculate distance in pips between two prices
double PriceToPips(double price1, double price2)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double digits = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   if (point == 0) return 0;
   
   if (digits <= 3) // JPY pairs
      return MathAbs(price1 - price2) / 0.01;
   else
      return MathAbs(price1 - price2) / 0.0001;
}

//--- Normalize lot size to broker requirements
double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if (lot < minLot) lot = minLot;
   if (lot > maxLot) lot = maxLot;
   
   lot = MathRound(lot / lotStep) * lotStep;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Time conversion functions                                        |
//+------------------------------------------------------------------+

//--- Convert GMT hour to server time
int GMTToServerHour(int gmtHour)
{
   datetime gmtTime = StringToTime("1970.01.01 " + IntegerToString(gmtHour) + ":00");
   datetime serverTime = TimeGMTToServer(gmtTime);
   
   MqlDateTime dt;
   TimeToStruct(serverTime, dt);
   
   return dt.hour;
}

//--- Check if current time is within specified GMT hour range
bool IsTimeInRangeGMT(int startHourGMT, int endHourGMT)
{
   datetime currentGMT = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(currentGMT, dt);
   
   int currentHourGMT = dt.hour;
   
   if (startHourGMT <= endHourGMT)
      return (currentHourGMT >= startHourGMT && currentHourGMT < endHourGMT);
   else // Range crosses midnight
      return (currentHourGMT >= startHourGMT || currentHourGMT < endHourGMT);
}

//--- Convert string time "HH:MM" to minutes since midnight
int TimeStringToMinutes(string timeStr)
{
   string parts[];
   StringSplit(timeStr, ':', parts);
   
   if (ArraySize(parts) >= 2)
      return StringToInteger(parts[0]) * 60 + StringToInteger(parts[1]);
   
   return 0;
}

//--- Check if current time is after specified GMT time
bool IsTimeAfterGMT(string timeStrGMT)
{
   datetime currentGMT = TimeGMT();
   datetime targetGMT = StringToTime("1970.01.01 " + timeStrGMT);
   
   MqlDateTime currentDT, targetDT;
   TimeToStruct(currentGMT, currentDT);
   TimeToStruct(targetGMT, targetDT);
   
   currentDT.year = targetDT.year = 1970;
   currentDT.mon = targetDT.mon = 1;
   currentDT.day = targetDT.day = 1;
   
   datetime currentNormalized = StructToTime(currentDT);
   datetime targetNormalized = StructToTime(targetDT);
   
   return currentNormalized >= targetNormalized;
}

//+------------------------------------------------------------------+
//| Error logging functions                                          |
//+------------------------------------------------------------------+

//--- Log error message with timestamp
void LogError(string functionName, string errorMessage, int errorCode = 0)
{
   string logMessage = StringFormat("%s: %s", functionName, errorMessage);
   
   if (errorCode != 0)
      logMessage += StringFormat(" (Error Code: %d)", errorCode);
   
   Print(logMessage);
}

//--- Log trade operation result
void LogTradeResult(string operation, double price, double volume, string comment = "")
{
   string logMessage = StringFormat("%s: Price=%.5f, Volume=%.2f", operation, price, volume);
   
   if (comment != "")
      logMessage += StringFormat(", Comment=%s", comment);
   
   Print(logMessage);
}

//--- Log strategy signal
void LogSignal(string signalType, double value1 = 0, double value2 = 0, string additionalInfo = "")
{
   string logMessage = StringFormat("Signal: %s", signalType);
   
   if (value1 != 0)
      logMessage += StringFormat(", Value1=%.5f", value1);
   
   if (value2 != 0)
      logMessage += StringFormat(", Value2=%.5f", value2);
   
   if (additionalInfo != "")
      logMessage += StringFormat(", Info=%s", additionalInfo);
   
   Print(logMessage);
}

//+------------------------------------------------------------------+
//| Input parameter validation functions                             |
//+------------------------------------------------------------------+

//--- Validate risk percentage input
bool ValidateRiskPercent(double riskPercent, double &validatedValue)
{
   if (riskPercent < 0.1 || riskPercent > 5.0)
   {
      LogError("ValidateRiskPercent", "Risk percentage must be between 0.1% and 5.0%");
      return false;
   }
   
   validatedValue = riskPercent;
   return true;
}

//--- Validate ATR multiplier input
bool ValidateATRMultiplier(double multiplier, double &validatedValue)
{
   if (multiplier < 0.5 || multiplier > 5.0)
   {
      LogError("ValidateATRMultiplier", "ATR multiplier must be between 0.5 and 5.0");
      return false;
   }
   
   validatedValue = multiplier;
   return true;
}

//--- Validate pip range input
bool ValidatePipRange(double minPips, double maxPips, double &validatedMin, double &validatedMax)
{
   if (minPips < 5 || minPips > 100)
   {
      LogError("ValidatePipRange", "Minimum pips must be between 5 and 100");
      return false;
   }
   
   if (maxPips < 20 || maxPips > 200)
   {
      LogError("ValidatePipRange", "Maximum pips must be between 20 and 200");
      return false;
   }
   
   if (minPips >= maxPips)
   {
      LogError("ValidatePipRange", "Minimum pips must be less than maximum pips");
      return false;
   }
   
   validatedMin = minPips;
   validatedMax = maxPips;
   return true;
}

//--- Validate time input (0-23)
bool ValidateHour(int hour, int &validatedHour)
{
   if (hour < 0 || hour > 23)
   {
      LogError("ValidateHour", "Hour must be between 0 and 23");
      return false;
   }
   
   validatedHour = hour;
   return true;
}

//--- Validate symbol against allowed pairs
bool ValidateSymbol(string symbol, string allowedPairs)
{
   string pairs[];
   StringSplit(allowedPairs, ',', pairs);
   
   for (int i = 0; i < ArraySize(pairs); i++)
   {
      string trimmedPair = StringTrimLeft(pairs[i]);
      trimmedPair = StringTrimRight(trimmedPair);
      
      if (symbol == trimmedPair)
         return true;
   }
   
   LogError("ValidateSymbol", StringFormat("Symbol %s is not in allowed pairs list", symbol));
   return false;
}

//--- Validate lot size limits
bool ValidateLotSize(double lot, double minLot, double maxLot, double &validatedLot)
{
   if (lot < minLot)
   {
      LogError("ValidateLotSize", StringFormat("Lot size %.2f is below minimum %.2f", lot, minLot));
      return false;
   }
   
   if (lot > maxLot)
   {
      LogError("ValidateLotSize", StringFormat("Lot size %.2f is above maximum %.2f", lot, maxLot));
      return false;
   }
   
   validatedLot = NormalizeLot(lot);
   return true;
}

//--- Calculate stop loss price based on range
double CalculateStopLossPrice(int orderType, double rangeHigh, double rangeLow)
{
   if (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_BUY)
      return rangeLow;
   else if (orderType == ORDER_TYPE_SELL_STOP || orderType == ORDER_TYPE_SELL)
      return rangeHigh;
   
   return 0;
}

//--- Calculate take profit price based on risk-reward ratio
double CalculateTakeProfitPrice(int orderType, double entryPrice, double stopLossPrice, double riskRewardRatio)
{
   double stopDistance = MathAbs(entryPrice - stopLossPrice);
   double takeProfitDistance = stopDistance * riskRewardRatio;
   
   if (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_BUY)
      return entryPrice + takeProfitDistance;
   else if (orderType == ORDER_TYPE_SELL_STOP || orderType == ORDER_TYPE_SELL)
      return entryPrice - takeProfitDistance;
   
   return 0;
}

//--- Calculate dynamic take profit based on ATR
double CalculateDynamicTakeProfit(int orderType, double entryPrice, double atrValue, double atrMultiplier)
{
   double takeProfitDistance = atrValue * atrMultiplier;
   
   if (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_BUY)
      return entryPrice + takeProfitDistance;
   else if (orderType == ORDER_TYPE_SELL_STOP || orderType == ORDER_TYPE_SELL)
      return entryPrice - takeProfitDistance;
   
   return 0;
}

//--- Calculate lot size based on risk percentage
double CalculateLotSize(double riskPercent, double stopLossPips, double accountEquity)
{
   double riskAmount = accountEquity * (riskPercent / 100);
   double pipValue = PipValue();
   
   if (pipValue == 0 || stopLossPips == 0)
      return 0;
   
   double lotSize = riskAmount / (stopLossPips * pipValue);
   
   return NormalizeLot(lotSize);
}

//+------------------------------------------------------------------+
//| Market information functions                                     |
//+------------------------------------------------------------------+

//--- Get current ATR value
double GetATRValue(int period, ENUM_TIMEFRAMES timeframe)
{
   double atrArray[];
   ArraySetAsSeries(atrArray, true);
   
   int atrHandle = iATR(_Symbol, timeframe, period);
   if (atrHandle == INVALID_HANDLE)
   {
      LogError("GetATRValue", "Failed to get ATR handle");
      return 0;
   }
   
   if (CopyBuffer(atrHandle, 0, 0, 1, atrArray) < 1)
   {
      LogError("GetATRValue", "Failed to copy ATR buffer");
      return 0;
   }
   
   IndicatorRelease(atrHandle);
   
   return atrArray[0];
}

//--- Get ATR value in pips
double GetATRInPips(int period, ENUM_TIMEFRAMES timeframe)
{
   double atrValue = GetATRValue(period, timeframe);
   return PriceToPips(0, atrValue);
}

//--- Get volume indicator value
double GetVolumeValue(int period, ENUM_TIMEFRAMES timeframe)
{
   double volumeArray[];
   ArraySetAsSeries(volumeArray, true);
   
   int volumeHandle = iVolumes(_Symbol, timeframe, VOLUME_TICK);
   if (volumeHandle == INVALID_HANDLE)
   {
      LogError("GetVolumeValue", "Failed to get volume handle");
      return 0;
   }
   
   if (CopyBuffer(volumeHandle, 0, 0, 1, volumeArray) < 1)
   {
      LogError("GetVolumeValue", "Failed to copy volume buffer");
      return 0;
   }
   
   IndicatorRelease(volumeHandle);
   
   return volumeArray[0];
}

//--- Get SMA of volume
double GetVolumeSMA(int period, ENUM_TIMEFRAMES timeframe, int smaPeriod)
{
   double volumeArray[];
   ArraySetAsSeries(volumeArray, true);
   
   // Get volume values for SMA period
   int volumeHandle = iVolumes(_Symbol, timeframe, VOLUME_TICK);
   if (volumeHandle == INVALID_HANDLE)
   {
      LogError("GetVolumeSMA", "Failed to get volume handle");
      return 0;
   }
   
   if (CopyBuffer(volumeHandle, 0, 0, smaPeriod, volumeArray) < smaPeriod)
   {
      LogError("GetVolumeSMA", "Failed to copy volume buffer");
      IndicatorRelease(volumeHandle);
      return 0;
   }
   
   IndicatorRelease(volumeHandle);
   
   // Calculate SMA
   double sum = 0;
   for (int i = 0; i < smaPeriod; i++)
      sum += volumeArray[i];
   
   return sum / smaPeriod;
}

//--- Check if volume is above threshold
bool IsVolumeAboveThreshold(double thresholdMultiplier, int volumePeriod, ENUM_TIMEFRAMES timeframe)
{
   double currentVolume = GetVolumeValue(volumePeriod, timeframe);
   double volumeSMA = GetVolumeSMA(volumePeriod, timeframe, 20);
   
   if (volumeSMA == 0) return false;
   
   return (currentVolume / volumeSMA) >= thresholdMultiplier;
}

//+------------------------------------------------------------------+
//| Date and time utility functions                                  |
//+------------------------------------------------------------------+

//--- Check if it's Friday and close time
bool IsFridayCloseTime(string closeHourGMT)
{
   datetime currentGMT = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(currentGMT, dt);
   
   if (dt.day_of_week != 5) // Not Friday
      return false;
   
   return IsTimeAfterGMT(closeHourGMT);
}

//--- Get minutes since last trade
double GetMinutesSinceLastTrade()
{
   datetime lastTradeTime = 0;
   
   // Check positions
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionGetSymbol(i) == _Symbol)
      {
         ulong ticket = PositionGetTicket(i);
         if (PositionSelectByTicket(ticket))
         {
            datetime positionTime = (datetime)PositionGetInteger(POSITION_TIME);
            if (positionTime > lastTradeTime)
               lastTradeTime = positionTime;
         }
      }
   }
   
   // Check orders
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderGetTicket(i))
      {
         if (OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            datetime orderTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
            if (orderTime > lastTradeTime)
               lastTradeTime = orderTime;
         }
      }
   }
   
   if (lastTradeTime == 0)
      return 1440; // More than 24 hours if no trades
   
   return (TimeCurrent() - lastTradeTime) / 60.0; // Convert to minutes
}

//--- Check if minimum time between trades has passed
bool HasMinimumTimePassed(double minHoursBetweenTrades)
{
   double minutesSinceLastTrade = GetMinutesSinceLastTrade();
   double requiredMinutes = minHoursBetweenTrades * 60;
   
   return minutesSinceLastTrade >= requiredMinutes;
}

//+------------------------------------------------------------------+
