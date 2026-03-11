//+------------------------------------------------------------------+
//| MarketConditions.mqh                                             |
//| Range Breakout Asian Session EA - Market Conditions Validation   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Range Breakout EA"
#property link      "https://www.example.com"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Indicators\Trend.mqh>
#include <Indicators\Volumes.mqh>
#include <Indicators\Oscilators.mqh>
#include <Indicators\BillWilliams.mqh>

//+------------------------------------------------------------------+
//| Market Conditions Validation Class                              |
//+------------------------------------------------------------------+
class CMarketConditions
{
private:
   // Input parameters
   string            m_allowed_pairs[];          // Allowed trading pairs
   double            m_min_atr_pips;             // Minimum ATR threshold in pips
   double            m_max_atr_pips;             // Maximum ATR threshold in pips
   double            m_min_range_pips;           // Minimum range width in pips
   double            m_max_range_pips;           // Maximum range width in pips
   int               m_atr_period;               // ATR period for volatility check
   ENUM_TIMEFRAMES   m_atr_timeframe;            // Timeframe for ATR calculation
   double            m_atr_mult_min;             // Minimum ATR multiplier for range validation
   double            m_atr_mult_max;             // Maximum ATR multiplier for range validation
   int               m_bb_period;                // Bollinger Bands period
   double            m_bb_dev;                   // Bollinger Bands deviation
   bool              m_use_vol_filter;           // Use volume filter
   int               m_vol_period;               // Volume SMA period
   double            m_vol_mult_threshold;       // Volume multiplier threshold
   ENUM_TIMEFRAMES   m_session_start_tf;         // Timeframe for session timing
   int               m_asian_session_start;      // Asian session start hour (GMT)
   int               m_asian_session_end;        // Asian session end hour (GMT)
   int               m_london_session_open;      // London session open hour (GMT)
   
   // Internal variables
   CTrade            m_trade;
   CSymbolInfo       m_symbol;
   CPositionInfo     m_position;
   CiATR             m_atr_indicator;
   CiBands           m_bb_indicator;
   CiVolumes         m_volume_indicator;
   
   // Helper methods
   double            PipsToPoints(double pips);
   double            GetATRValue(string symbol, ENUM_TIMEFRAMES tf);
   double            GetBollingerWidth(string symbol, ENUM_TIMEFRAMES tf);
   double            GetVolumeRatio(string symbol, ENUM_TIMEFRAMES tf);
   bool              IsTradingSession(int current_hour);
   
public:
   // Constructor
   CMarketConditions();
   
   // Initialization method
   bool              Init(string allowed_pairs, double min_atr_pips, double max_atr_pips,
                         double min_range_pips, double max_range_pips, int atr_period,
                         ENUM_TIMEFRAMES atr_timeframe, double atr_mult_min, double atr_mult_max,
                         int bb_period, double bb_dev, bool use_vol_filter, int vol_period,
                         double vol_mult_threshold, ENUM_TIMEFRAMES session_start_tf,
                         int asian_session_start, int asian_session_end, int london_session_open);
   
   // Validation methods
   bool              IsPairAllowed(string symbol);
   bool              CheckVolatility(string symbol);
   bool              CheckRangeWidth(string symbol, double range_width_pips);
   bool              CheckATRRange(string symbol, double range_width_pips);
   bool              CheckBollingerWidth(string symbol);
   bool              CheckVolume(string symbol, ENUM_TIMEFRAMES tf);
   bool              CheckSessionTiming();
   bool              ValidateAllConditions(string symbol, double range_width_pips, ENUM_TIMEFRAMES tf);
   
   // Getters
   string            GetAllowedPairs() { return ArrayToString(m_allowed_pairs, ","); }
   double            GetMinATRPips() { return m_min_atr_pips; }
   double            GetMaxATRPips() { return m_max_atr_pips; }
   double            GetMinRangePips() { return m_min_range_pips; }
   double            GetMaxRangePips() { return m_max_range_pips; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CMarketConditions::CMarketConditions()
{
   // Initialize arrays
   ArrayResize(m_allowed_pairs, 0);
   
   // Initialize indicators
   m_atr_indicator = CiATR();
   m_bb_indicator = CiBands();
   m_volume_indicator = CiVolumes();
}

//+------------------------------------------------------------------+
//| Initialization method                                            |
//+------------------------------------------------------------------+
bool CMarketConditions::Init(string allowed_pairs, double min_atr_pips, double max_atr_pips,
                           double min_range_pips, double max_range_pips, int atr_period,
                           ENUM_TIMEFRAMES atr_timeframe, double atr_mult_min, double atr_mult_max,
                           int bb_period, double bb_dev, bool use_vol_filter, int vol_period,
                           double vol_mult_threshold, ENUM_TIMEFRAMES session_start_tf,
                           int asian_session_start, int asian_session_end, int london_session_open)
{
   // Parse allowed pairs
   string pairs[];
   int count = StringSplit(allowed_pairs, ',', pairs);
   ArrayResize(m_allowed_pairs, count);
   for(int i = 0; i < count; i++)
   {
      m_allowed_pairs[i] = StringTrim(pairs[i]);
   }
   
   // Set parameters
   m_min_atr_pips = min_atr_pips;
   m_max_atr_pips = max_atr_pips;
   m_min_range_pips = min_range_pips;
   m_max_range_pips = max_range_pips;
   m_atr_period = atr_period;
   m_atr_timeframe = atr_timeframe;
   m_atr_mult_min = atr_mult_min;
   m_atr_mult_max = atr_mult_max;
   m_bb_period = bb_period;
   m_bb_dev = bb_dev;
   m_use_vol_filter = use_vol_filter;
   m_vol_period = vol_period;
   m_vol_mult_threshold = vol_mult_threshold;
   m_session_start_tf = session_start_tf;
   m_asian_session_start = asian_session_start;
   m_asian_session_end = asian_session_end;
   m_london_session_open = london_session_open;
   
   // Initialize trade object
   m_trade.SetExpertMagicNumber(12345);
   
   return true;
}

//+------------------------------------------------------------------+
//| Convert pips to points                                           |
//+------------------------------------------------------------------+
double CMarketConditions::PipsToPoints(double pips)
{
   return pips * m_symbol.Point() * 10;
}

//+------------------------------------------------------------------+
//| Get ATR value for specified symbol and timeframe                 |
//+------------------------------------------------------------------+
double CMarketConditions::GetATRValue(string symbol, ENUM_TIMEFRAMES tf)
{
   if(!m_atr_indicator.Create(symbol, tf, m_atr_period))
      return 0.0;
   
   double atr_value = m_atr_indicator.Main(1);
   double atr_pips = atr_value / m_symbol.Point() / 10;
   
   return atr_pips;
}

//+------------------------------------------------------------------+
//| Get Bollinger Bands width in pips                                |
//+------------------------------------------------------------------+
double CMarketConditions::GetBollingerWidth(string symbol, ENUM_TIMEFRAMES tf)
{
   if(!m_bb_indicator.Create(symbol, tf, m_bb_period, 0, m_bb_dev, PRICE_CLOSE))
      return 0.0;
   
   double upper_band = m_bb_indicator.Upper(1);
   double lower_band = m_bb_indicator.Lower(1);
   double width_pips = (upper_band - lower_band) / m_symbol.Point() / 10;
   
   return width_pips;
}

//+------------------------------------------------------------------+
//| Get volume ratio (current volume / SMA volume)                   |
//+------------------------------------------------------------------+
double CMarketConditions::GetVolumeRatio(string symbol, ENUM_TIMEFRAMES tf)
{
   if(!m_volume_indicator.Create(symbol, tf, VOLUME_TICK))
      return 1.0;
   
   double current_volume = m_volume_indicator.Main(1);
   
   // Calculate SMA of volume
   double sum_volume = 0;
   for(int i = 1; i <= m_vol_period; i++)
   {
      sum_volume += m_volume_indicator.Main(i);
   }
   double sma_volume = sum_volume / m_vol_period;
   
   if(sma_volume == 0)
      return 1.0;
   
   return current_volume / sma_volume;
}

//+------------------------------------------------------------------+
//| Check if current hour is within trading session                  |
//+------------------------------------------------------------------+
bool CMarketConditions::IsTradingSession(int current_hour)
{
   // Check if current hour is within Asian session (for range calculation)
   // or after London open (for trade execution)
   if(current_hour >= m_asian_session_start && current_hour < m_asian_session_end)
      return true; // Asian session for range calculation
   
   if(current_hour >= m_london_session_open)
      return true; // London session for trade execution
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if symbol is in allowed pairs list                         |
//+------------------------------------------------------------------+
bool CMarketConditions::IsPairAllowed(string symbol)
{
   for(int i = 0; i < ArraySize(m_allowed_pairs); i++)
   {
      if(m_allowed_pairs[i] == symbol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check volatility using ATR thresholds                            |
//+------------------------------------------------------------------+
bool CMarketConditions::CheckVolatility(string symbol)
{
   if(!m_symbol.Name(symbol))
      return false;
   
   double atr_pips = GetATRValue(symbol, m_atr_timeframe);
   
   // Check if ATR is within acceptable range
   if(atr_pips < m_min_atr_pips)
   {
      Print("Volatility too low for ", symbol, ": ATR = ", atr_pips, " pips (min required: ", m_min_atr_pips, ")");
      return false;
   }
   
   if(atr_pips > m_max_atr_pips)
   {
      Print("Volatility too high for ", symbol, ": ATR = ", atr_pips, " pips (max allowed: ", m_max_atr_pips, ")");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if range width is within acceptable limits                 |
//+------------------------------------------------------------------+
bool CMarketConditions::CheckRangeWidth(string symbol, double range_width_pips)
{
   if(range_width_pips < m_min_range_pips)
   {
      Print("Range too narrow for ", symbol, ": ", range_width_pips, " pips (min required: ", m_min_range_pips, ")");
      return false;
   }
   
   if(range_width_pips > m_max_range_pips)
   {
      Print("Range too wide for ", symbol, ": ", range_width_pips, " pips (max allowed: ", m_max_range_pips, ")");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if range width is appropriate relative to ATR              |
//+------------------------------------------------------------------+
bool CMarketConditions::CheckATRRange(string symbol, double range_width_pips)
{
   if(!m_symbol.Name(symbol))
      return false;
   
   double atr_pips = GetATRValue(symbol, m_atr_timeframe);
   
   if(atr_pips == 0)
      return false;
   
   double atr_ratio = range_width_pips / atr_pips;
   
   // Check if range width is within ATR multiplier limits
   if(atr_ratio < m_atr_mult_min)
   {
      Print("Range too narrow relative to ATR for ", symbol, ": ", atr_ratio, "x ATR (min required: ", m_atr_mult_min, "x)");
      return false;
   }
   
   if(atr_ratio > m_atr_mult_max)
   {
      Print("Range too wide relative to ATR for ", symbol, ": ", atr_ratio, "x ATR (max allowed: ", m_atr_mult_max, "x)");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check Bollinger Bands width for volatility filter                |
//+------------------------------------------------------------------+
bool CMarketConditions::CheckBollingerWidth(string symbol)
{
   if(!m_symbol.Name(symbol))
      return false;
   
   double bb_width_pips = GetBollingerWidth(symbol, PERIOD_D1);
   
   // Convert min/max range pips to comparable values
   // Bollinger width should be proportional to the acceptable range
   if(bb_width_pips < m_min_range_pips * 0.5)
   {
      Print("Bollinger Bands too narrow for ", symbol, ": ", bb_width_pips, " pips");
      return false;
   }
   
   if(bb_width_pips > m_max_range_pips * 2)
   {
      Print("Bollinger Bands too wide for ", symbol, ": ", bb_width_pips, " pips");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check volume for breakout confirmation                           |
//+------------------------------------------------------------------+
bool CMarketConditions::CheckVolume(string symbol, ENUM_TIMEFRAMES tf)
{
   if(!m_use_vol_filter)
      return true;
   
   if(!m_symbol.Name(symbol))
      return false;
   
   double volume_ratio = GetVolumeRatio(symbol, tf);
   
   if(volume_ratio < m_vol_mult_threshold)
   {
      Print("Volume too low for ", symbol, ": ", volume_ratio, "x average (min required: ", m_vol_mult_threshold, "x)");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check session timing                                             |
//+------------------------------------------------------------------+
bool CMarketConditions::CheckSessionTiming()
{
   MqlDateTime dt;
   TimeGMT(dt);
   
   return IsTradingSession(dt.hour);
}

//+------------------------------------------------------------------+
//| Validate all market conditions                                   |
//+------------------------------------------------------------------+
bool CMarketConditions::ValidateAllConditions(string symbol, double range_width_pips, ENUM_TIMEFRAMES tf)
{
   // 1. Check if pair is allowed
   if(!IsPairAllowed(symbol))
   {
      Print("Symbol not allowed: ", symbol);
      return false;
   }
   
   // 2. Check volatility using ATR
   if(!CheckVolatility(symbol))
      return false;
   
   // 3. Check range width
   if(!CheckRangeWidth(symbol, range_width_pips))
      return false;
   
   // 4. Check ATR range ratio
   if(!CheckATRRange(symbol, range_width_pips))
      return false;
   
   // 5. Check Bollinger Bands width
   if(!CheckBollingerWidth(symbol))
      return false;
   
   // 6. Check volume
   if(!CheckVolume(symbol, tf))
      return false;
   
   // 7. Check session timing
   if(!CheckSessionTiming())
   {
      Print("Not within valid trading session");
      return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+