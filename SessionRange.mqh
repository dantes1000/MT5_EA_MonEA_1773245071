//+------------------------------------------------------------------+
//|                                                      SessionRange.mqh |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| SessionRange class: Calculates Asian session high/low range      |
//| with margin filtering and validates width against min/max pip    |
//| thresholds.                                                      |
//+------------------------------------------------------------------+
class CSessionRange
{
private:
   // Input parameters
   int               m_asian_session_start;      // Asian session start hour (GMT)
   int               m_asian_session_end;        // Asian session end hour (GMT)
   int               m_margin_pips;              // Margin in pips to filter noise
   double            m_min_width_pips;           // Minimum range width in pips
   double            m_max_width_pips;           // Maximum range width in pips
   string            m_range_calc_method;        // Range calculation method
   
   // Internal variables
   double            m_session_high;             // Calculated session high
   double            m_session_low;              // Calculated session low
   double            m_range_width_pips;         // Range width in pips
   bool              m_range_valid;              // Flag if range is valid
   datetime          m_last_calc_time;           // Last calculation time
   
   // Helper methods
   double            CalculateMarginPoints(const string symbol);
   bool              IsInAsianSession(const datetime time);
   
public:
   // Constructor
   CSessionRange();
   
   // Destructor
   ~CSessionRange();
   
   // Initialization method
   void              Initialize(int asian_start, int asian_end, int margin_pips, 
                                double min_width, double max_width, string calc_method);
   
   // Main calculation method
   bool              CalculateRange(const string symbol, const datetime current_time);
   
   // Getter methods
   double            GetSessionHigh() const { return m_session_high; }
   double            GetSessionLow() const { return m_session_low; }
   double            GetRangeWidthPips() const { return m_range_width_pips; }
   bool              IsRangeValid() const { return m_range_valid; }
   datetime          GetLastCalcTime() const { return m_last_calc_time; }
   
   // Validation methods
   bool              ValidateWidth(const string symbol) const;
   
   // Utility methods
   static double     PipsToPoints(const string symbol, double pips);
   static double     PointsToPips(const string symbol, double points);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSessionRange::CSessionRange() :
   m_asian_session_start(0),
   m_asian_session_end(6),
   m_margin_pips(5),
   m_min_width_pips(30.0),
   m_max_width_pips(120.0),
   m_range_calc_method("Closed_Candles"),
   m_session_high(0.0),
   m_session_low(0.0),
   m_range_width_pips(0.0),
   m_range_valid(false),
   m_last_calc_time(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSessionRange::~CSessionRange()
{
}

//+------------------------------------------------------------------+
//| Initialization method                                            |
//+------------------------------------------------------------------+
void CSessionRange::Initialize(int asian_start, int asian_end, int margin_pips, 
                               double min_width, double max_width, string calc_method)
{
   m_asian_session_start = asian_start;
   m_asian_session_end = asian_end;
   m_margin_pips = margin_pips;
   m_min_width_pips = min_width;
   m_max_width_pips = max_width;
   m_range_calc_method = calc_method;
   
   // Reset internal variables
   m_session_high = 0.0;
   m_session_low = 0.0;
   m_range_width_pips = 0.0;
   m_range_valid = false;
   m_last_calc_time = 0;
   
   Print("SessionRange initialized: Asian Session ", m_asian_session_start, 
         ":00-", m_asian_session_end, ":00 GMT, Margin=", m_margin_pips, 
         " pips, Width Range=", m_min_width_pips, "-", m_max_width_pips, " pips");
}

//+------------------------------------------------------------------+
//| Calculate margin in points for the given symbol                  |
//+------------------------------------------------------------------+
double CSessionRange::CalculateMarginPoints(const string symbol)
{
   return PipsToPoints(symbol, m_margin_pips);
}

//+------------------------------------------------------------------+
//| Check if given time is within Asian session hours               |
//+------------------------------------------------------------------+
bool CSessionRange::IsInAsianSession(const datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   int hour = dt.hour;
   
   // Handle session that crosses midnight
   if (m_asian_session_start < m_asian_session_end)
   {
      // Normal session (e.g., 0-6)
      return (hour >= m_asian_session_start && hour < m_asian_session_end);
   }
   else
   {
      // Session crosses midnight (e.g., 22-6)
      return (hour >= m_asian_session_start || hour < m_asian_session_end);
   }
}

//+------------------------------------------------------------------+
//| Main method to calculate Asian session range                    |
//+------------------------------------------------------------------+
bool CSessionRange::CalculateRange(const string symbol, const datetime current_time)
{
   // Reset previous values
   m_session_high = 0.0;
   m_session_low = 0.0;
   m_range_width_pips = 0.0;
   m_range_valid = false;
   
   // Get current day's start time (00:00 GMT)
   MqlDateTime dt_current;
   TimeToStruct(current_time, dt_current);
   dt_current.hour = 0;
   dt_current.min = 0;
   dt_current.sec = 0;
   datetime day_start = StructToTime(dt_current);
   
   // Calculate session start and end times for today
   datetime session_start = day_start + (m_asian_session_start * 3600);
   datetime session_end = day_start + (m_asian_session_end * 3600);
   
   // Adjust if session crosses midnight
   if (m_asian_session_start >= m_asian_session_end)
   {
      session_end += 24 * 3600; // Add one day
   }
   
   // Check if current time is after session end
   if (current_time < session_end)
   {
      // Session not yet completed
      Print("Asian session not yet completed for ", symbol);
      return false;
   }
   
   // Calculate the number of minutes in the session
   int session_minutes = (int)((session_end - session_start) / 60);
   
   // Determine timeframe based on session length
   ENUM_TIMEFRAMES tf;
   if (session_minutes <= 60)
      tf = PERIOD_M1;
   else if (session_minutes <= 240)
      tf = PERIOD_M5;
   else if (session_minutes <= 480)
      tf = PERIOD_M15;
   else
      tf = PERIOD_H1;
   
   // Get number of bars needed to cover the session
   int bars_needed = (int)MathCeil(session_minutes / PeriodSeconds(tf) * 60);
   bars_needed = MathMin(bars_needed, 1000); // Limit to reasonable number
   
   // Copy high and low prices for the session period
   double highs[], lows[];
   int copied = CopyHigh(symbol, tf, session_start, bars_needed, highs);
   int copied_lows = CopyLow(symbol, tf, session_start, bars_needed, lows);
   
   if (copied <= 0 || copied_lows <= 0 || copied != copied_lows)
   {
      Print("Failed to copy price data for ", symbol, ", copied highs=", copied, ", lows=", copied_lows);
      return false;
   }
   
   // Initialize with first values
   m_session_high = highs[0];
   m_session_low = lows[0];
   
   // Find session high and low
   for (int i = 1; i < copied; i++)
   {
      if (highs[i] > m_session_high) m_session_high = highs[i];
      if (lows[i] < m_session_low) m_session_low = lows[i];
   }
   
   // Apply margin filtering if specified
   if (m_margin_pips > 0)
   {
      double margin_points = CalculateMarginPoints(symbol);
      m_session_high -= margin_points;
      m_session_low += margin_points;
      
      // Ensure high is still above low after margin adjustment
      if (m_session_high <= m_session_low)
      {
         // Adjust to maintain minimum spread
         double midpoint = (m_session_high + m_session_low) / 2.0;
         double spread = SymbolInfoDouble(symbol, SYMBOL_POINT) * 10; // 1 pip
         m_session_high = midpoint + spread;
         m_session_low = midpoint - spread;
      }
   }
   
   // Calculate range width in pips
   m_range_width_pips = PointsToPips(symbol, m_session_high - m_session_low);
   
   // Validate range width
   m_range_valid = ValidateWidth(symbol);
   
   // Update last calculation time
   m_last_calc_time = current_time;
   
   // Log results
   PrintFormat("Asian Session Range for %s: High=%.5f, Low=%.5f, Width=%.1f pips, Valid=%s",
               symbol, m_session_high, m_session_low, m_range_width_pips, 
               m_range_valid ? "Yes" : "No");
   
   return true;
}

//+------------------------------------------------------------------+
//| Validate range width against min/max thresholds                 |
//+------------------------------------------------------------------+
bool CSessionRange::ValidateWidth(const string symbol) const
{
   if (m_range_width_pips < m_min_width_pips)
   {
      PrintFormat("Range width %.1f pips is below minimum %.1f pips for %s", 
                  m_range_width_pips, m_min_width_pips, symbol);
      return false;
   }
   
   if (m_range_width_pips > m_max_width_pips)
   {
      PrintFormat("Range width %.1f pips exceeds maximum %.1f pips for %s", 
                  m_range_width_pips, m_max_width_pips, symbol);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Convert pips to points for the given symbol                     |
//+------------------------------------------------------------------+
double CSessionRange::PipsToPoints(const string symbol, double pips)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   
   // Standard calculation for most forex pairs
   double pip_value = point * 10;
   
   // Adjust for pairs where pip is not 0.0001 (e.g., JPY pairs)
   if (SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3 || SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 2)
   {
      pip_value = point * 100;
   }
   
   return pips * pip_value;
}

//+------------------------------------------------------------------+
//| Convert points to pips for the given symbol                     |
//+------------------------------------------------------------------+
double CSessionRange::PointsToPips(const string symbol, double points)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   // Standard calculation for most forex pairs
   double pip_value = point * 10;
   
   // Adjust for pairs where pip is not 0.0001 (e.g., JPY pairs)
   if (SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3 || SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 2)
   {
      pip_value = point * 100;
   }
   
   if (pip_value == 0) return 0.0;
   
   return points / pip_value;
}
//+------------------------------------------------------------------+