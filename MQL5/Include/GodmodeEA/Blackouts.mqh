//+------------------------------------------------------------------+
//|                                                    Blackouts.mqh |
//|  MODULE 9 -- news blackout is the single filter most likely to  |
//|  save the account. Tighten it; never loosen it.                 |
//+------------------------------------------------------------------+
#property strict
#include "Defines.mqh"

class CBlackouts
  {
private:
   string   m_symbol;
   int      m_news_minutes_before;
   int      m_news_minutes_after;
   int      m_rollover_hour_server;
   int      m_rollover_minutes_buffer;
   int      m_session_start_hour_gmt;
   int      m_session_end_hour_gmt;
   int      m_monday_gap_guard_minutes;
   int      m_friday_late_guard_hour_gmt;

public:
   void Init(const string symbol, const int news_minutes_before, const int news_minutes_after,
             const int rollover_hour_server, const int rollover_minutes_buffer,
             const int session_start_hour_gmt, const int session_end_hour_gmt,
             const int monday_gap_guard_minutes, const int friday_late_guard_hour_gmt)
     {
      m_symbol = symbol;
      m_news_minutes_before = news_minutes_before;
      m_news_minutes_after = news_minutes_after;
      m_rollover_hour_server = rollover_hour_server;
      m_rollover_minutes_buffer = rollover_minutes_buffer;
      m_session_start_hour_gmt = session_start_hour_gmt;
      m_session_end_hour_gmt = session_end_hour_gmt;
      m_monday_gap_guard_minutes = monday_gap_guard_minutes;
      m_friday_late_guard_hour_gmt = friday_late_guard_hour_gmt;
     }

   //--- high-impact USD calendar events: gold moves 300-800pts in seconds on these
   bool IsNewsBlackout() const
     {
      datetime now = TimeCurrent();
      datetime from = now - 4*3600;
      datetime to   = now + 4*3600;

      MqlCalendarValue values[];
      if(!CalendarValueHistory(values, from, to, NULL, "USD"))
        {
         // "Tighten it; never loosen it" -- if the calendar is unavailable we
         // cannot rule out a live high-impact event, so fail CLOSED (blocked)
         // rather than silently trading through an unmonitored news window.
         Print("Blackouts: Economic Calendar unavailable -- failing closed (news blackout assumed).");
         return true;
        }

      for(int i=0; i<ArraySize(values); i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev)) continue;
         if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;

         datetime evt = values[i].time;
         datetime window_start = evt - m_news_minutes_before*60;
         datetime window_end   = evt + m_news_minutes_after*60;
         if(now >= window_start && now <= window_end)
            return true;
        }
      return false;
     }

   bool IsRolloverBlackout() const
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int nowMinutes = dt.hour*60 + dt.min;
      int rolloverMinutes = m_rollover_hour_server*60;
      int diff = MathAbs(nowMinutes - rolloverMinutes);
      diff = MathMin(diff, 1440 - diff); // wrap around midnight
      return (diff <= m_rollover_minutes_buffer);
     }

   //--- London + NY morning, kept WIDER than an FX window -- gold reacts
   //--- to Asian-session risk events too, so don't over-restrict to the overlap.
   bool IsOutsideSession() const
     {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      int hour = dt.hour;
      if(m_session_start_hour_gmt <= m_session_end_hour_gmt)
         return (hour < m_session_start_hour_gmt || hour >= m_session_end_hour_gmt);
      return !(hour >= m_session_start_hour_gmt || hour < m_session_end_hour_gmt);
     }

   bool IsMondayGapGuard() const
     {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      if(dt.day_of_week != MONDAY) return false;
      int minutesSinceMidnight = dt.hour*60 + dt.min;
      int sessionStartMinutes = m_session_start_hour_gmt*60;
      return (minutesSinceMidnight >= sessionStartMinutes &&
              minutesSinceMidnight < sessionStartMinutes + m_monday_gap_guard_minutes);
     }

   bool IsFridayLateGuard() const
     {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      if(dt.day_of_week != FRIDAY) return false;
      return (dt.hour >= m_friday_late_guard_hour_gmt);
     }

   //--- aggregate check for new-entry gating (does NOT affect managing open trades)
   ENUM_REJECT_REASON CheckAll() const
     {
      if(IsNewsBlackout())       return REJECT_NEWS_BLACKOUT;
      if(IsRolloverBlackout())   return REJECT_ROLLOVER_BLACKOUT;
      if(IsMondayGapGuard())     return REJECT_GAP_GUARD;
      if(IsFridayLateGuard())    return REJECT_SESSION_CLOSED;
      if(IsOutsideSession())     return REJECT_SESSION_CLOSED;
      return REJECT_NONE;
     }
  };
//+------------------------------------------------------------------+
