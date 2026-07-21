//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|  On-chart status panel + control buttons ("Godmode" EA trait).   |
//|  Renders a live readout of the OODA/God-mode state and exposes   |
//|  PAUSE/RESUME and CLOSE ALL buttons. HandleEvent() is called     |
//|  from the EA's OnChartEvent and returns the action to perform.   |
//+------------------------------------------------------------------+
#ifndef V75EA_DASHBOARD_MQH
#define V75EA_DASHBOARD_MQH

#property strict

#include <V75EA\Types.mqh>

enum ENUM_PANEL_ACTION
  {
   PANEL_NONE         = 0,
   PANEL_TOGGLE_PAUSE = 1,
   PANEL_CLOSE_ALL    = 2
  };

class CDashboard
  {
private:
   string   m_prefix;
   bool     m_enabled;
   int      m_x;
   int      m_y;
   int      m_w;
   int      m_rowH;

   string   m_bg, m_title, m_btnPause, m_btnClose;
   string   m_rows[10];
   int      m_rowCount;

   //--- palette (V75EA gold-on-charcoal identity)
   color    m_cBg, m_cText, m_cMuted, m_cGold, m_cUp, m_cDown;

public:
                     CDashboard(void) : m_enabled(false), m_x(14), m_y(28), m_w(240), m_rowH(20), m_rowCount(0) {}

   void              Init(const string prefix, const bool enabled)
     {
      m_prefix  = prefix;
      m_enabled = enabled;
      m_cBg   = (color)C'20,25,36';
      m_cText = (color)C'232,236,244';
      m_cMuted= (color)C'140,149,168';
      m_cGold = (color)C'217,160,63';
      m_cUp   = (color)C'63,182,139';
      m_cDown = (color)C'224,92,92';

      m_bg       = m_prefix + "bg";
      m_title    = m_prefix + "title";
      m_btnPause = m_prefix + "btnPause";
      m_btnClose = m_prefix + "btnClose";

      if(!m_enabled)
         return;

      CreatePanel();
     }

   void              Deinit(void)
     {
      if(!m_enabled)
         return;
      ObjectsDeleteAll(0, m_prefix);
     }

   //--- returns the action a button click requests (PANEL_NONE otherwise)
   ENUM_PANEL_ACTION HandleEvent(const int id, const long &lparam,
                                  const double &dparam, const string &sparam)
     {
      if(!m_enabled || id != CHARTEVENT_OBJECT_CLICK)
         return PANEL_NONE;

      if(sparam == m_btnPause)
        {
         ObjectSetInteger(0, m_btnPause, OBJPROP_STATE, false);
         return PANEL_TOGGLE_PAUSE;
        }
      if(sparam == m_btnClose)
        {
         ObjectSetInteger(0, m_btnClose, OBJPROP_STATE, false);
         return PANEL_CLOSE_ALL;
        }
      return PANEL_NONE;
     }

   void              Update(const SDashboardState &s)
     {
      if(!m_enabled)
         return;

      color pnlColor = (s.dailyPnlPercent >= 0.0) ? m_cUp : m_cDown;

      SetTitle(StringFormat("V75EA  %s", s.godMode ? "GOD MODE" : "STANDARD"));

      SetRow(0, "State",       s.paused ? "PAUSED" : s.status, s.paused ? m_cDown : m_cGold);
      SetRow(1, "Regime",      s.regime, m_cText);
      SetRow(2, "Confidence",  StringFormat("%.2f / thr %.2f", s.confidence, s.threshold), m_cText);
      SetRow(3, "Vol ratio",   StringFormat("%.2f x", s.volRatio),
             (s.volRatio >= 1.0) ? m_cUp : m_cMuted);
      SetRow(4, "Risk mult",   StringFormat("%.2f x", s.riskMult), m_cText);
      SetRow(5, "Recovery",    (s.recoveryStep > 0) ? StringFormat("step %d", s.recoveryStep) : "-",
             (s.recoveryStep > 0) ? m_cDown : m_cMuted);
      SetRow(6, "Positions",   StringFormat("%d", s.openPositions), m_cText);
      SetRow(7, "Day P/L",     StringFormat("%+.2f%%", s.dailyPnlPercent), pnlColor);
      SetRow(8, "Equity",      StringFormat("%.2f", s.equity), m_cText);

      //--- keep pause button label in sync
      ObjectSetString(0, m_btnPause, OBJPROP_TEXT, s.paused ? "RESUME" : "PAUSE");
     }

private:
   void              CreatePanel(void)
     {
      int rows   = 9;
      int height = 34 + rows * m_rowH + 34;

      //--- background
      ObjectCreate(0, m_bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, m_bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, m_bg, OBJPROP_XDISTANCE, m_x);
      ObjectSetInteger(0, m_bg, OBJPROP_YDISTANCE, m_y);
      ObjectSetInteger(0, m_bg, OBJPROP_XSIZE, m_w);
      ObjectSetInteger(0, m_bg, OBJPROP_YSIZE, height);
      ObjectSetInteger(0, m_bg, OBJPROP_BGCOLOR, m_cBg);
      ObjectSetInteger(0, m_bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, m_bg, OBJPROP_COLOR, m_cGold);
      ObjectSetInteger(0, m_bg, OBJPROP_BACK, false);
      ObjectSetInteger(0, m_bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, m_bg, OBJPROP_HIDDEN, true);

      //--- title
      CreateLabel(m_title, m_x + 12, m_y + 10, "V75EA", m_cGold, 11, true);

      //--- rows
      for(int i = 0; i < rows; i++)
        {
         string keyName = m_prefix + "k" + (string)i;
         string valName = m_prefix + "v" + (string)i;
         int yy = m_y + 34 + i * m_rowH;
         CreateLabel(keyName, m_x + 12, yy, "", m_cMuted, 9, false);
         CreateLabel(valName, m_x + m_w - 12, yy, "", m_cText, 9, false, ANCHOR_RIGHT_UPPER);
         m_rows[i] = valName;
        }
      m_rowCount = rows;

      //--- buttons
      int by = m_y + 34 + rows * m_rowH + 4;
      CreateButton(m_btnPause, m_x + 12, by, 100, 24, "PAUSE", m_cGold);
      CreateButton(m_btnClose, m_x + m_w - 112, by, 100, 24, "CLOSE ALL", m_cDown);
     }

   void              CreateLabel(const string name, const int x, const int y, const string text,
                                  const color clr, const int fontSize, const bool bold,
                                  const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }

   void              CreateButton(const string name, const int x, const int y, const int w, const int h,
                                   const string text, const color clr)
     {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_COLOR, (color)C'232,236,244');
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, (color)C'32,40,56');
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }

   void              SetTitle(const string text)
     {
      ObjectSetString(0, m_title, OBJPROP_TEXT, text);
     }

   void              SetRow(const int i, const string key, const string val, const color valColor)
     {
      if(i < 0 || i >= m_rowCount)
         return;
      ObjectSetString(0, m_prefix + "k" + (string)i, OBJPROP_TEXT, key);
      ObjectSetString(0, m_rows[i], OBJPROP_TEXT, val);
      ObjectSetInteger(0, m_rows[i], OBJPROP_COLOR, valColor);
     }
  };

#endif // V75EA_DASHBOARD_MQH
