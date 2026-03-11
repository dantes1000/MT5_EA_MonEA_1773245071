//+------------------------------------------------------------------+
//|                                                      NewsFilter.mqh |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| News Filter Class                                                |
//+------------------------------------------------------------------+
class CNewsFilter
{
private:
   // FFCal indicator handle
   int               m_ffcal_handle;
   
   // Configuration parameters
   string            m_impact_level;      // Impact level to filter (High, Medium, Low)
   int               m_pause_before_min;  // Minutes to pause before news
   int               m_pause_after_min;   // Minutes to pause after news
   bool              m_enabled;           // Whether news filter is enabled
   
   // Internal variables
   datetime          m_last_check_time;
   bool              m_is_paused;
   datetime          m_pause_until;
   string            m_current_symbol;
   
   // Helper methods
   bool              LoadFFCalIndicator();
   bool              IsHighImpactNews(datetime time);
   datetime          GetNextNewsTime();
   
public:
   // Constructor
   CNewsFilter();
   
   // Destructor
   ~CNewsFilter();
   
   // Initialization method
   bool              Init(string impact_level = "High", int pause_before = 60, int pause_after = 30, bool enabled = true);
   
   // Main method to check if trading should be paused
   bool              IsTradingPaused();
   
   // Method to get pause status
   bool              GetPauseStatus() const { return m_is_paused; }
   
   // Method to get time until pause ends
   datetime          GetPauseUntil() const { return m_pause_until; }
   
   // Method to manually force a pause
   void              ForcePause(int minutes);
   
   // Method to manually resume trading
   void              ResumeTrading();
   
   // Method to update configuration
   void              UpdateConfig(string impact_level, int pause_before, int pause_after, bool enabled);
   
   // Method to get current impact level
   string            GetImpactLevel() const { return m_impact_level; }
   
   // Method to get pause durations
   int               GetPauseBefore() const { return m_pause_before_min; }
   int               GetPauseAfter() const { return m_pause_after_min; }
   
   // Method to check if filter is enabled
   bool              IsEnabled() const { return m_enabled; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CNewsFilter::CNewsFilter() :
   m_ffcal_handle(INVALID_HANDLE),
   m_impact_level("High"),
   m_pause_before_min(60),
   m_pause_after_min(30),
   m_enabled(true),
   m_last_check_time(0),
   m_is_paused(false),
   m_pause_until(0),
   m_current_symbol(_Symbol)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CNewsFilter::~CNewsFilter()
{
   if(m_ffcal_handle != INVALID_HANDLE)
   {
      IndicatorRelease(m_ffcal_handle);
   }
}

//+------------------------------------------------------------------+
//| Initialization method                                            |
//+------------------------------------------------------------------+
bool CNewsFilter::Init(string impact_level = "High", int pause_before = 60, int pause_after = 30, bool enabled = true)
{
   m_impact_level = impact_level;
   m_pause_before_min = pause_before;
   m_pause_after_min = pause_after;
   m_enabled = enabled;
   m_current_symbol = _Symbol;
   
   // Load FFCal indicator if enabled
   if(m_enabled)
   {
      if(!LoadFFCalIndicator())
      {
         Print("Warning: Failed to load FFCal indicator. News filter may not work correctly.");
         // Continue without indicator - will use time-based filtering
      }
   }
   
   m_last_check_time = TimeCurrent();
   m_is_paused = false;
   m_pause_until = 0;
   
   return true;
}

//+------------------------------------------------------------------+
//| Load FFCal indicator                                             |
//+------------------------------------------------------------------+
bool CNewsFilter::LoadFFCalIndicator()
{
   // Try to load FFCal indicator
   m_ffcal_handle = iCustom(m_current_symbol, PERIOD_CURRENT, "FFCal");
   
   if(m_ffcal_handle == INVALID_HANDLE)
   {
      // Try alternative names
      m_ffcal_handle = iCustom(m_current_symbol, PERIOD_CURRENT, "ForexFactoryCalendar");
      
      if(m_ffcal_handle == INVALID_HANDLE)
      {
         m_ffcal_handle = iCustom(m_current_symbol, PERIOD_CURRENT, "FFCal.ex5");
         
         if(m_ffcal_handle == INVALID_HANDLE)
         {
            Print("Error: FFCal indicator not found. Please ensure FFCal.ex5 is in the Indicators folder.");
            return false;
         }
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if trading should be paused                                |
//+------------------------------------------------------------------+
bool CNewsFilter::IsTradingPaused()
{
   // If filter is disabled, never pause
   if(!m_enabled)
      return false;
   
   datetime current_time = TimeCurrent();
   
   // Check only once per minute to reduce CPU load
   if(current_time - m_last_check_time < 60)
      return m_is_paused;
   
   m_last_check_time = current_time;
   
   // Check if we're currently in a pause period
   if(m_is_paused)
   {
      if(current_time >= m_pause_until)
      {
         // Pause period has ended
         m_is_paused = false;
         m_pause_until = 0;
         Print("News filter: Pause period ended at ", TimeToString(current_time, TIME_DATE|TIME_SECONDS));
      }
      return m_is_paused;
   }
   
   // Check for upcoming news events
   if(m_ffcal_handle != INVALID_HANDLE)
   {
      // Get next news time from FFCal indicator
      datetime next_news_time = GetNextNewsTime();
      
      if(next_news_time > 0)
      {
         // Calculate pause window
         datetime pause_start = next_news_time - (m_pause_before_min * 60);
         datetime pause_end = next_news_time + (m_pause_after_min * 60);
         
         if(current_time >= pause_start && current_time <= pause_end)
         {
            m_is_paused = true;
            m_pause_until = pause_end;
            Print("News filter: Trading paused due to high-impact news from ", 
                  TimeToString(pause_start, TIME_DATE|TIME_SECONDS), " to ", 
                  TimeToString(pause_end, TIME_DATE|TIME_SECONDS));
            return true;
         }
      }
   }
   else
   {
      // Fallback: Simple time-based filtering for known high-impact news times
      // This is a basic implementation - in production, you would want a more
      // comprehensive list of known news times or use a different indicator
      
      // Example: Check for NFP (first Friday of the month at 13:30 GMT)
      MqlDateTime dt;
      TimeToStruct(current_time, dt);
      
      // Check if it's the first Friday of the month
      if(dt.day_of_week == 5 && dt.day <= 7)
      {
         // Check if current time is around 13:30 GMT
         int hour = dt.hour;
         int minute = dt.min;
         
         // Convert to GMT (assuming server time is GMT)
         // Adjust this based on your broker's timezone
         
         // Check if within pause window around 13:30
         int target_hour = 13;
         int target_minute = 30;
         
         datetime news_time = StringToTime(IntegerToString(dt.year) + "." + 
                                          IntegerToString(dt.mon) + "." + 
                                          IntegerToString(dt.day) + " " + 
                                          IntegerToString(target_hour) + ":" + 
                                          IntegerToString(target_minute));
         
         datetime pause_start = news_time - (m_pause_before_min * 60);
         datetime pause_end = news_time + (m_pause_after_min * 60);
         
         if(current_time >= pause_start && current_time <= pause_end)
         {
            m_is_paused = true;
            m_pause_until = pause_end;
            Print("News filter: Trading paused for NFP news from ", 
                  TimeToString(pause_start, TIME_DATE|TIME_SECONDS), " to ", 
                  TimeToString(pause_end, TIME_DATE|TIME_SECONDS));
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Get next news time from FFCal indicator                          |
//+------------------------------------------------------------------+
datetime CNewsFilter::GetNextNewsTime()
{
   if(m_ffcal_handle == INVALID_HANDLE)
      return 0;
   
   // FFCal indicator typically stores news times in buffers
   // Buffer 0: News time
   // Buffer 1: Impact level (1=Low, 2=Medium, 3=High)
   
   datetime next_news_time = 0;
   double impact_level = 0;
   
   // Look ahead up to 24 hours for news events
   for(int i = 0; i < 1440; i++)  // 1440 minutes = 24 hours
   {
      // Get news time from buffer 0
      double news_time_val = iCustomGet(m_current_symbol, PERIOD_CURRENT, m_ffcal_handle, 0, i);
      
      if(news_time_val > 0)
      {
         // Get impact level from buffer 1
         impact_level = iCustomGet(m_current_symbol, PERIOD_CURRENT, m_ffcal_handle, 1, i);
         
         // Check if impact level matches our filter
         if((m_impact_level == "High" && impact_level >= 3) ||
            (m_impact_level == "Medium" && impact_level >= 2) ||
            (m_impact_level == "Low" && impact_level >= 1))
         {
            next_news_time = (datetime)news_time_val;
            break;
         }
      }
   }
   
   return next_news_time;
}

//+------------------------------------------------------------------+
//| Check if specific time has high impact news                      |
//+------------------------------------------------------------------+
bool CNewsFilter::IsHighImpactNews(datetime time)
{
   if(m_ffcal_handle == INVALID_HANDLE)
      return false;
   
   // Convert time to bar index
   int bar_index = iBarShift(m_current_symbol, PERIOD_CURRENT, time);
   
   if(bar_index >= 0)
   {
      double impact_level = iCustomGet(m_current_symbol, PERIOD_CURRENT, m_ffcal_handle, 1, bar_index);
      
      // Check if high impact news exists at this time
      if(impact_level >= 3 && m_impact_level == "High")
         return true;
      else if(impact_level >= 2 && m_impact_level == "Medium")
         return true;
      else if(impact_level >= 1 && m_impact_level == "Low")
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Force a pause for specified minutes                              |
//+------------------------------------------------------------------+
void CNewsFilter::ForcePause(int minutes)
{
   m_is_paused = true;
   m_pause_until = TimeCurrent() + (minutes * 60);
   Print("News filter: Manual pause activated until ", TimeToString(m_pause_until, TIME_DATE|TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| Resume trading manually                                          |
//+------------------------------------------------------------------+
void CNewsFilter::ResumeTrading()
{
   m_is_paused = false;
   m_pause_until = 0;
   Print("News filter: Manual resume activated");
}

//+------------------------------------------------------------------+
//| Update configuration                                             |
//+------------------------------------------------------------------+
void CNewsFilter::UpdateConfig(string impact_level, int pause_before, int pause_after, bool enabled)
{
   bool needs_reload = (impact_level != m_impact_level) || (enabled != m_enabled);
   
   m_impact_level = impact_level;
   m_pause_before_min = pause_before;
   m_pause_after_min = pause_after;
   m_enabled = enabled;
   
   if(needs_reload && m_enabled)
   {
      if(m_ffcal_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_ffcal_handle);
      }
      LoadFFCalIndicator();
   }
   else if(!m_enabled && m_ffcal_handle != INVALID_HANDLE)
   {
      IndicatorRelease(m_ffcal_handle);
      m_ffcal_handle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Helper function to get custom indicator value                    |
//+------------------------------------------------------------------+
double iCustomGet(string symbol, ENUM_TIMEFRAMES timeframe, int handle, int buffer, int shift)
{
   double value[1];
   
   if(CopyBuffer(handle, buffer, shift, 1, value) <= 0)
   {
      return 0;
   }
   
   return value[0];
}

//+------------------------------------------------------------------+
