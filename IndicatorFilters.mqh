//+------------------------------------------------------------------+
//|                                                      IndicatorFilters.mqh |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Includes                                                         |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Indicators\Trend.mqh>
#include <Indicators\Oscilators.mqh>
#include <Indicators\Volumes.mqh>
#include <Indicators\Bands.mqh>

//+------------------------------------------------------------------+
//| Indicator Filter Functions                                       |
//+------------------------------------------------------------------+
class CIndicatorFilters
{
private:
   // Handles for indicators
   int               m_atr_handle;
   int               m_ema_handle;
   int               m_adx_handle;
   int               m_bb_handle;
   int               m_volume_handle;
   
   // Indicator buffers
   double            m_atr_buffer[];
   double            m_ema_buffer[];
   double            m_adx_buffer[];
   double            m_bb_upper_buffer[];
   double            m_bb_lower_buffer[];
   double            m_volume_buffer[];
   
   // Timeframes
   ENUM_TIMEFRAMES   m_atr_tf;
   ENUM_TIMEFRAMES   m_ema_tf;
   ENUM_TIMEFRAMES   m_bb_tf;
   
   // Parameters
   int               m_atr_period;
   double            m_atr_mult_min;
   double            m_atr_mult_max;
   int               m_ema_period;
   int               m_adx_period;
   int               m_adx_threshold;
   int               m_bb_period;
   double            m_bb_dev;
   int               m_volume_period;
   double            m_volume_mult_threshold;
   double            m_min_atr_pips;
   double            m_max_atr_pips;
   
   // Helper objects
   CTrade            m_trade;
   CSymbolInfo       m_symbol;
   
public:
   // Constructor
   CIndicatorFilters() : 
      m_atr_handle(INVALID_HANDLE),
      m_ema_handle(INVALID_HANDLE),
      m_adx_handle(INVALID_HANDLE),
      m_bb_handle(INVALID_HANDLE),
      m_volume_handle(INVALID_HANDLE),
      m_atr_tf(PERIOD_H1),
      m_ema_tf(PERIOD_H1),
      m_bb_tf(PERIOD_D1),
      m_atr_period(14),
      m_atr_mult_min(1.25),
      m_atr_mult_max(3.0),
      m_ema_period(200),
      m_adx_period(14),
      m_adx_threshold(20),
      m_bb_period(20),
      m_bb_dev(2.0),
      m_volume_period(20),
      m_volume_mult_threshold(1.5),
      m_min_atr_pips(20),
      m_max_atr_pips(150)
   {
      m_symbol.Name(Symbol());
      m_symbol.RefreshRates();
   }
   
   // Destructor
   ~CIndicatorFilters()
   {
      if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
      if(m_ema_handle != INVALID_HANDLE) IndicatorRelease(m_ema_handle);
      if(m_adx_handle != INVALID_HANDLE) IndicatorRelease(m_adx_handle);
      if(m_bb_handle != INVALID_HANDLE) IndicatorRelease(m_bb_handle);
      if(m_volume_handle != INVALID_HANDLE) IndicatorRelease(m_volume_handle);
   }
   
   // Initialization method
   bool Init(
      ENUM_TIMEFRAMES atr_tf = PERIOD_H1,
      ENUM_TIMEFRAMES ema_tf = PERIOD_H1,
      ENUM_TIMEFRAMES bb_tf = PERIOD_D1,
      int atr_period = 14,
      double atr_mult_min = 1.25,
      double atr_mult_max = 3.0,
      int ema_period = 200,
      int adx_period = 14,
      int adx_threshold = 20,
      int bb_period = 20,
      double bb_dev = 2.0,
      int volume_period = 20,
      double volume_mult_threshold = 1.5,
      double min_atr_pips = 20,
      double max_atr_pips = 150)
   {
      m_atr_tf = atr_tf;
      m_ema_tf = ema_tf;
      m_bb_tf = bb_tf;
      m_atr_period = atr_period;
      m_atr_mult_min = atr_mult_min;
      m_atr_mult_max = atr_mult_max;
      m_ema_period = ema_period;
      m_adx_period = adx_period;
      m_adx_threshold = adx_threshold;
      m_bb_period = bb_period;
      m_bb_dev = bb_dev;
      m_volume_period = volume_period;
      m_volume_mult_threshold = volume_mult_threshold;
      m_min_atr_pips = min_atr_pips;
      m_max_atr_pips = max_atr_pips;
      
      // Initialize ATR indicator
      m_atr_handle = iATR(Symbol(), m_atr_tf, m_atr_period);
      if(m_atr_handle == INVALID_HANDLE)
      {
         Print("Failed to create ATR indicator");
         return false;
      }
      
      // Initialize EMA indicator
      m_ema_handle = iMA(Symbol(), m_ema_tf, m_ema_period, 0, MODE_EMA, PRICE_CLOSE);
      if(m_ema_handle == INVALID_HANDLE)
      {
         Print("Failed to create EMA indicator");
         return false;
      }
      
      // Initialize ADX indicator
      m_adx_handle = iADX(Symbol(), m_ema_tf, m_adx_period);
      if(m_adx_handle == INVALID_HANDLE)
      {
         Print("Failed to create ADX indicator");
         return false;
      }
      
      // Initialize Bollinger Bands indicator
      m_bb_handle = iBands(Symbol(), m_bb_tf, m_bb_period, 0, m_bb_dev, PRICE_CLOSE);
      if(m_bb_handle == INVALID_HANDLE)
      {
         Print("Failed to create Bollinger Bands indicator");
         return false;
      }
      
      // Initialize Volume indicator (Real Volume)
      m_volume_handle = iVolumes(Symbol(), m_atr_tf, VOLUME_REAL);
      if(m_volume_handle == INVALID_HANDLE)
      {
         Print("Failed to create Volume indicator");
         return false;
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| ATR Breakout Confirmation Filter                                 |
   //+------------------------------------------------------------------+
   bool CheckATRBreakout(double breakout_distance, double &atr_value)
   {
      // Get current ATR value
      if(!GetIndicatorValue(m_atr_handle, 0, atr_value, m_atr_buffer))
         return false;
      
      // Convert ATR to pips
      double atr_pips = atr_value / m_symbol.Point();
      
      // Check if ATR is within acceptable range
      if(atr_pips < m_min_atr_pips || atr_pips > m_max_atr_pips)
      {
         Print("ATR filter: ATR value ", atr_pips, " pips is outside acceptable range [", 
               m_min_atr_pips, ", ", m_max_atr_pips, "]");
         return false;
      }
      
      // Check if breakout distance exceeds minimum ATR multiplier
      double min_breakout_distance = atr_value * m_atr_mult_min;
      if(breakout_distance < min_breakout_distance)
      {
         Print("ATR filter: Breakout distance ", breakout_distance, " is less than minimum required ", 
               min_breakout_distance, " (ATR * ", m_atr_mult_min, ")");
         return false;
      }
      
      // Check if breakout distance is within maximum ATR multiplier
      double max_breakout_distance = atr_value * m_atr_mult_max;
      if(breakout_distance > max_breakout_distance)
      {
         Print("ATR filter: Breakout distance ", breakout_distance, " exceeds maximum allowed ", 
               max_breakout_distance, " (ATR * ", m_atr_mult_max, ")");
         return false;
      }
      
      Print("ATR filter: Breakout confirmed with ATR value ", atr_value, ", breakout distance ", breakout_distance);
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Volume Confirmation Filter using Real Volume SMA                |
   //+------------------------------------------------------------------+
   bool CheckVolumeConfirmation()
   {
      // Get current volume
      double current_volume;
      if(!GetIndicatorValue(m_volume_handle, 0, current_volume, m_volume_buffer))
         return false;
      
      // Calculate SMA of volume
      double volume_sma = 0;
      int count = 0;
      
      for(int i = 0; i < m_volume_period; i++)
      {
         double volume_value;
         if(GetIndicatorValue(m_volume_handle, i, volume_value, m_volume_buffer))
         {
            volume_sma += volume_value;
            count++;
         }
      }
      
      if(count == 0) return false;
      
      volume_sma /= count;
      
      // Check if current volume exceeds threshold
      if(current_volume > volume_sma * m_volume_mult_threshold)
      {
         Print("Volume filter: Current volume ", current_volume, " exceeds SMA threshold ", 
               volume_sma * m_volume_mult_threshold, " (SMA * ", m_volume_mult_threshold, ")");
         return true;
      }
      
      Print("Volume filter: Current volume ", current_volume, " does not exceed SMA threshold ", 
            volume_sma * m_volume_mult_threshold);
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Trend Filter with EMA200 + ADX                                  |
   //+------------------------------------------------------------------+
   bool CheckTrendFilter(ENUM_ORDER_TYPE order_type)
   {
      // Get current price
      double current_price = order_type == ORDER_TYPE_BUY ? m_symbol.Ask() : m_symbol.Bid();
      
      // Get EMA value
      double ema_value;
      if(!GetIndicatorValue(m_ema_handle, 0, ema_value, m_ema_buffer))
         return false;
      
      // Get ADX value
      double adx_value;
      if(!GetIndicatorValue(m_adx_handle, 0, adx_value, m_adx_buffer))
         return false;
      
      // Check trend direction based on order type
      bool trend_ok = false;
      
      if(order_type == ORDER_TYPE_BUY)
      {
         // For buy orders: price should be above EMA200 and ADX should indicate strong trend
         trend_ok = (current_price > ema_value) && (adx_value > m_adx_threshold);
         Print("Trend filter for BUY: Price=", current_price, ", EMA200=", ema_value, ", ADX=", adx_value, ", Result=", trend_ok);
      }
      else if(order_type == ORDER_TYPE_SELL)
      {
         // For sell orders: price should be below EMA200 and ADX should indicate strong trend
         trend_ok = (current_price < ema_value) && (adx_value > m_adx_threshold);
         Print("Trend filter for SELL: Price=", current_price, ", EMA200=", ema_value, ", ADX=", adx_value, ", Result=", trend_ok);
      }
      
      return trend_ok;
   }
   
   //+------------------------------------------------------------------+
   //| Bollinger Bands Volatility Filter                               |
   //+------------------------------------------------------------------+
   bool CheckBollingerBandsFilter(double range_high, double range_low, double &bb_width_pips)
   {
      // Get Bollinger Bands values
      double bb_upper, bb_lower;
      
      if(!GetIndicatorValue(m_bb_handle, 0, bb_upper, m_bb_upper_buffer, 1)) // Upper band
         return false;
      
      if(!GetIndicatorValue(m_bb_handle, 0, bb_lower, m_bb_lower_buffer, 2)) // Lower band
         return false;
      
      // Calculate BB width in pips
      bb_width_pips = (bb_upper - bb_lower) / m_symbol.Point();
      
      // Check if Asian range fits within Bollinger Bands
      bool within_bands = (range_high <= bb_upper) && (range_low >= bb_lower);
      
      Print("Bollinger Bands filter: Range [", range_low, ", ", range_high, "] within BB [", 
            bb_lower, ", ", bb_upper, "]: ", within_bands, ", BB width: ", bb_width_pips, " pips");
      
      return within_bands;
   }
   
   //+------------------------------------------------------------------+
   //| Comprehensive Market Condition Check                            |
   //+------------------------------------------------------------------+
   bool CheckMarketConditions(double range_high, double range_low, ENUM_ORDER_TYPE order_type)
   {
      // Get ATR value for volatility check
      double atr_value;
      if(!GetIndicatorValue(m_atr_handle, 0, atr_value, m_atr_buffer))
         return false;
      
      double atr_pips = atr_value / m_symbol.Point();
      
      // Check ATR range
      if(atr_pips < m_min_atr_pips)
      {
         Print("Market condition: ATR too low (", atr_pips, " pips < ", m_min_atr_pips, ")");
         return false;
      }
      
      if(atr_pips > m_max_atr_pips)
      {
         Print("Market condition: ATR too high (", atr_pips, " pips > ", m_max_atr_pips, ")");
         return false;
      }
      
      // Check trend filter
      if(!CheckTrendFilter(order_type))
      {
         Print("Market condition: Trend filter failed");
         return false;
      }
      
      // Check Bollinger Bands filter
      double bb_width_pips;
      if(!CheckBollingerBandsFilter(range_high, range_low, bb_width_pips))
      {
         Print("Market condition: Bollinger Bands filter failed");
         return false;
      }
      
      // Check volume confirmation
      if(!CheckVolumeConfirmation())
      {
         Print("Market condition: Volume confirmation failed");
         return false;
      }
      
      Print("Market conditions: All filters passed. ATR: ", atr_pips, " pips, BB width: ", bb_width_pips, " pips");
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate Dynamic Take Profit based on ATR                      |
   //+------------------------------------------------------------------+
   double CalculateDynamicTP(double entry_price, double sl_price, ENUM_ORDER_TYPE order_type, double atr_tp_mult)
   {
      double atr_value;
      if(!GetIndicatorValue(m_atr_handle, 0, atr_value, m_atr_buffer))
         return 0;
      
      double tp_distance = atr_value * atr_tp_mult;
      
      if(order_type == ORDER_TYPE_BUY)
         return entry_price + tp_distance;
      else if(order_type == ORDER_TYPE_SELL)
         return entry_price - tp_distance;
      
      return 0;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate Trailing Stop based on ATR                            |
   //+------------------------------------------------------------------+
   double CalculateTrailingStop(double current_price, double best_price, ENUM_ORDER_TYPE order_type, double trail_mult)
   {
      double atr_value;
      if(!GetIndicatorValue(m_atr_handle, 0, atr_value, m_atr_buffer))
         return 0;
      
      double trail_distance = atr_value * trail_mult;
      
      if(order_type == ORDER_TYPE_BUY)
         return best_price - trail_distance;
      else if(order_type == ORDER_TYPE_SELL)
         return best_price + trail_distance;
      
      return 0;
   }
   
private:
   //+------------------------------------------------------------------+
   //| Helper function to get indicator values                         |
   //+------------------------------------------------------------------+
   bool GetIndicatorValue(int handle, int shift, double &value, double &buffer[], int buffer_num = 0)
   {
      if(handle == INVALID_HANDLE)
         return false;
      
      if(CopyBuffer(handle, buffer_num, shift, 1, buffer) <= 0)
         return false;
      
      value = buffer[0];
      return true;
   }
};

//+------------------------------------------------------------------+
