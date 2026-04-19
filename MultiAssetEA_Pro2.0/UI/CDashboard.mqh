#ifndef GUARD_C_DASHBOARD
#define GUARD_C_DASHBOARD

#property strict

#include <MultiAssetEA_Pro2.0/Risk/CRiskManager.mqh>

//+------------------------------------------------------------------+
//|  CDashboard  ·  Pro 2.0  ·  Light Navy Chart Theme               |
//|                                                                   |
//|  Layout: Single-column grouped table (iOS Settings style)        |
//|  Width:  380 px  ·  Anchored: top-left                           |
//|                                                                   |
//|  Chart theme: Light Navy                                         |
//|    Background    #0F1E41  →  C'15,30,65'                        |
//|    Grid          #1A2D5A  →  C'26,45,90'                        |
//|    Foreground    #B4C8E6  →  C'180,200,230'                     |
//|                                                                   |
//|  Panel palette: Apple HIG Dark (adapted)                        |
//|    System BG     #1C1C1E  →  C'28,28,30'                        |
//|    Section BG    #2C2C2E  →  C'44,44,46'                        |
//|    Elevated      #3A3A3C  →  C'58,58,60'                        |
//|    Separator     #38383A  →  C'56,56,58'                        |
//|    Label         #FFFFFF                                         |
//|    Secondary     #8E8E93  →  C'142,142,147'                     |
//|    Tertiary      #636366  →  C'99,99,102'                       |
//|    Blue          #0A84FF  →  C'10,132,255'                      |
//|    Green         #30D158  →  C'48,209,88'                       |
//|    Red           #FF453A  →  C'255,69,58'                       |
//|    Orange        #FF9F0A  →  C'255,159,10'                      |
//|    Yellow        #FFD60A  →  C'255,214,10'                      |
//|    Teal          #5AC8FA  →  C'90,200,250'                      |
//+------------------------------------------------------------------+
class CDashboard
{
private:
   // ── Palette ────────────────────────────────────────────────────
   color  K_SYS_BG;
   color  K_SEC_BG;
   color  K_FILL;
   color  K_SEP;
   color  K_LBL;
   color  K_LBL2;
   color  K_LBL3;
   color  K_BLUE;
   color  K_GREEN;
   color  K_RED;
   color  K_ORANGE;
   color  K_YELLOW;
   color  K_TEAL;

   // ── Layout ─────────────────────────────────────────────────────
   string m_pfx;
   int    m_X;
   int    m_Y;
   int    m_W;    // 380
   int    m_RE;   // right-edge for ANCHOR_RIGHT text
   int    m_LP;   // left padding inside sections

   // ── Primitives ─────────────────────────────────────────────────
   void   Rect (string id, int x, int y, int w, int h, color bg);
   void   HSep (string id, int x, int y, int w);
   void   Lbl  (string id, int x, int y, string txt, color c, int sz, bool bold=false);
   void   LblR (string id,        int y, string txt, color c, int sz, bool bold=false);

   // ── Composite helpers ──────────────────────────────────────────
   int    SecHdr(string id, int y, string title);
   int    Row   (string pfx, int y, string lbl, string val, color valClr, bool sep=true);

   string N(string id) { return m_pfx + id; }

public:
            CDashboard();
           ~CDashboard();

   void     SetChartTheme();
   void     Draw(CRiskManager* pRiskMgr, double winRate,
                 int tradesToday, string &symbolStates[]);
   void     Clear() { ObjectsDeleteAll(0, m_pfx); }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CDashboard::CDashboard()
{
   m_pfx  = "DASH_";
   m_X    = 20;
   m_Y    = 20;
   m_W    = 380;
   m_RE   = m_X + m_W - 12;
   m_LP   = 16;

   K_SYS_BG  = C'28,28,30';
   K_SEC_BG  = C'44,44,46';
   K_FILL    = C'58,58,60';
   K_SEP     = C'56,56,58';
   K_LBL     = C'255,255,255';
   K_LBL2    = C'142,142,147';
   K_LBL3    = C'99,99,102';
   K_BLUE    = C'10,132,255';
   K_GREEN   = C'48,209,88';
   K_RED     = C'255,69,58';
   K_ORANGE  = C'255,159,10';
   K_YELLOW  = C'255,214,10';
   K_TEAL    = C'90,200,250';

   SetChartTheme();
}

CDashboard::~CDashboard() { Clear(); }

//+------------------------------------------------------------------+
//| SetChartTheme  — Light Navy chart background                      |
//+------------------------------------------------------------------+
void CDashboard::SetChartTheme()
{
   long chart = 0; // current chart

   // Background
   ChartSetInteger(chart, CHART_COLOR_BACKGROUND,  C'15,30,65');    // Light Navy
   ChartSetInteger(chart, CHART_COLOR_FOREGROUND,  C'180,200,230'); // Soft blue-grey labels
   ChartSetInteger(chart, CHART_COLOR_GRID,        C'26,45,90');    // Dark navy grid (subtle)

   // Candles
   ChartSetInteger(chart, CHART_COLOR_CANDLE_BULL, C'48,209,88');   // Green
   ChartSetInteger(chart, CHART_COLOR_CANDLE_BEAR, C'255,69,58');   // Red
   ChartSetInteger(chart, CHART_COLOR_CHART_UP,    C'48,209,88');   // Bar up
   ChartSetInteger(chart, CHART_COLOR_CHART_DOWN,  C'255,69,58');   // Bar down

   // Wicks — slightly muted so candle body stands out
   ChartSetInteger(chart, CHART_COLOR_CHART_LINE,  C'120,160,210'); // Line chart

   // Volume bars
   ChartSetInteger(chart, CHART_COLOR_VOLUME,      C'90,200,250');  // Teal

   // Bid/Ask lines
   ChartSetInteger(chart, CHART_COLOR_BID,         C'255,214,10');  // Yellow bid
   ChartSetInteger(chart, CHART_COLOR_ASK,         C'90,200,250');  // Teal ask

   // Stop levels
   ChartSetInteger(chart, CHART_COLOR_STOP_LEVEL,  C'255,69,58');   // Red stop

   ChartRedraw(chart);
}

//+------------------------------------------------------------------+
//| Rect                                                              |
//+------------------------------------------------------------------+
void CDashboard::Rect(string id, int x, int y, int w, int h, color bg)
{
   string n = N(id);
   if(ObjectFind(0, n) >= 0) ObjectDelete(0, n);
   ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR,bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_BACK,        false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,      1);
}

//+------------------------------------------------------------------+
//| HSep  — 1 px hairline separator                                   |
//+------------------------------------------------------------------+
void CDashboard::HSep(string id, int x, int y, int w)
{
   Rect(id, x, y, w, 1, K_SEP);
}

//+------------------------------------------------------------------+
//| Lbl  — left-anchored text label                                   |
//+------------------------------------------------------------------+
void CDashboard::Lbl(string id, int x, int y, string txt,
                     color c, int sz, bool bold)
{
   string n = N(id);
   if(ObjectFind(0, n) >= 0) ObjectDelete(0, n);
   ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, n, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  sz);
   ObjectSetString (0, n, OBJPROP_FONT,      bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, n, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,    ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_BACK,      false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,    3);
}

//+------------------------------------------------------------------+
//| LblR  — right-anchored text label                                 |
//+------------------------------------------------------------------+
void CDashboard::LblR(string id, int y, string txt,
                      color c, int sz, bool bold)
{
   string n = N(id);
   if(ObjectFind(0, n) >= 0) ObjectDelete(0, n);
   ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, m_RE);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, n, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  sz);
   ObjectSetString (0, n, OBJPROP_FONT,      bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, n, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_BACK,      false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,    3);
}

//+------------------------------------------------------------------+
//| SecHdr  — ALL-CAPS section header, returns y advanced by 26 px   |
//+------------------------------------------------------------------+
int CDashboard::SecHdr(string id, int y, string title)
{
   Lbl(id, m_X + m_LP, y + 8, title, K_LBL3, 8, true);
   return y + 26;
}

//+------------------------------------------------------------------+
//| Row  — left label + right value + optional separator             |
//+------------------------------------------------------------------+
int CDashboard::Row(string pfx, int y,
                    string lbl, string val, color valClr, bool sep)
{
   Lbl (pfx + "_L", m_X + m_LP, y + 3, lbl, K_LBL2, 9);
   LblR(pfx + "_V",             y + 3, val, valClr,  9, true);
   if(sep)
   {
      HSep(pfx + "_S", m_X + m_LP, y + 22, m_W - m_LP * 2);
      return y + 23;
   }
   return y + 22;
}

//+------------------------------------------------------------------+
//| Draw  — main render                                               |
//+------------------------------------------------------------------+
void CDashboard::Draw(CRiskManager* pRiskMgr,
                      double winRate, int tradesToday,
                      string &symbolStates[])
{
   Clear();

   const int X  = m_X;
   const int W  = m_W;
   const int LP = m_LP;
   int y = m_Y;

   // ── Account values ─────────────────────────────────────────────
   double eq     = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal    = AccountInfoDouble(ACCOUNT_BALANCE);
   double flt    = eq - bal;
   double fltPct = (bal > 0) ? (flt / bal * 100.0) : 0.0;
   color  fltCol = (flt >= 0) ? K_GREEN : K_RED;
   string fltStr = StringFormat("%s$%.2f  (%+.2f%%)",
                                (flt >= 0) ? "+" : "", MathAbs(flt), fltPct);

   // ── Risk state ─────────────────────────────────────────────────
   bool   dailyOk  = (pRiskMgr != NULL) ? !pRiskMgr.IsDailyLossLimitExceeded() : true;
   bool   weeklyOk = (pRiskMgr != NULL) ? !pRiskMgr.IsWeeklyDrawdownExceeded() : true;
   bool   globalOk = (pRiskMgr != NULL) ? !pRiskMgr.IsGlobalDrawdownExceeded() : true;

   color  dCol = dailyOk  ? K_GREEN : K_RED;
   color  wCol = weeklyOk ? K_GREEN : K_RED;
   color  gCol = globalOk ? K_GREEN : K_RED;

   string dTxt = dailyOk  ? "● HEALTHY"     : "● BREACHED";
   string wTxt = weeklyOk ? "● OK"           : "⚠ EXCEEDED";
   string gTxt = globalOk ? "● OK"           : "🚨 HALTED";

   // ── Win rate colour tier ───────────────────────────────────────
   color wrCol = (winRate >= 0.60) ? K_GREEN
               : (winRate >= 0.50) ? K_ORANGE
               :                     K_RED;

   // ── Symbol count ───────────────────────────────────────────────
   int numSym = ArraySize(symbolStates);

   // ── Height calculation ─────────────────────────────────────────
   //  Title bar         64
   //  Account          104  (26 hdr + 3 rows×22 + 2 seps + 10 pad)
   //  sep               5
   //  Risk Guard       128  (26 hdr + 4 rows×22 + 3 seps + 10 pad)
   //  sep               5
   //  Session           96  (26 hdr + 3 rows×22 + 2 seps + 10 pad)
   //  sep               5
   //  Matrix body       26 hdr + 24 col hdr + 6 + numSym×22 + (numSym-1)×1 + 10
   //  Footer            22
   int matH   = 26 + 24 + 6 + numSym * 22 + (numSym > 0 ? (numSym - 1) : 0) + 10;
   int totalH = 64 + 104 + 5 + 128 + 5 + 96 + 5 + matH + 22;
   Rect("MASTER", X, y, W, totalH, K_SYS_BG);

   // ══════════════════════════════════════════════════════════════
   //  TITLE BAR  (64 px)
   // ══════════════════════════════════════════════════════════════
   Rect("HDR_BG", X, y, W, 64, K_SYS_BG);

   // Live dot
   Rect("HDR_DOT", X + LP, y + 26, 8, 8, K_GREEN);

   // EA name
   Lbl("HDR_NAME", X + LP + 16, y + 10, "MULTI ASSET ENGINE", K_LBL, 14, true);
   Lbl("HDR_VER",  X + LP + 16, y + 30, "Pro 2.0  ·  SFX $250K", K_TEAL, 8);

   // Server time top-right
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   string timeStr = StringFormat("%02d:%02d:%02d", dt.hour, dt.min, dt.sec);
   LblR("HDR_TIME", y + 10, timeStr,   K_LBL,  11, true);
   LblR("HDR_DAY",  y + 28, StringFormat("%02d/%02d/%04d", dt.day, dt.mon, dt.year), K_LBL2, 7);

   y += 64;
   HSep("SEP_TOP", X, y, W);
   y += 1;

   // ══════════════════════════════════════════════════════════════
   //  SECTION: ACCOUNT  (104 px)
   // ══════════════════════════════════════════════════════════════
   Rect("ACC_BG", X, y, W, 104, K_SEC_BG);
   y = SecHdr("ACC_H", y, "ACCOUNT");
   y = Row("ACC_EQ",  y, "Equity",       StringFormat("$%.2f", eq),  K_LBL);
   y = Row("ACC_BAL", y, "Balance",      StringFormat("$%.2f", bal), K_LBL);
   y = Row("ACC_FLT", y, "Floating P&L", fltStr, fltCol, false);
   y += 10;

   y += 4;  HSep("SEP_1", X, y, W);  y += 1;

   // ══════════════════════════════════════════════════════════════
   //  SECTION: RISK GUARD  (128 px — 4 rows)
   // ══════════════════════════════════════════════════════════════
   Rect("RSK_BG", X, y, W, 128, K_SEC_BG);
   y = SecHdr("RSK_H", y, "RISK GUARD");
   y = Row("RSK_D", y, "Daily Limit",            dTxt, dCol);
   y = Row("RSK_W", y, "Weekly Drawdown",         wTxt, wCol);
   y = Row("RSK_G", y, "Global Circuit Breaker",  gTxt, gCol);

   // News guard status
   string ngTxt = StringFormat("±%d min buffer active", Inp_NewsGuardMinutes);
   color  ngCol = Inp_EnableToxicityGuard ? K_TEAL : K_LBL3;
   y = Row("RSK_N", y, "News Guard", ngTxt, ngCol, false);
   y += 10;

   y += 4;  HSep("SEP_2", X, y, W);  y += 1;

   // ══════════════════════════════════════════════════════════════
   //  SECTION: SESSION  (96 px — 3 rows)
   // ══════════════════════════════════════════════════════════════
   Rect("SES_BG", X, y, W, 96, K_SEC_BG);
   y = SecHdr("SES_H", y, "SESSION");
   y = Row("SES_TD", y, "Trades Today",   IntegerToString(tradesToday),            K_LBL);
   y = Row("SES_WR", y, "Win Rate",       StringFormat("%.1f%%", winRate * 100.0), wrCol);
   y = Row("SES_OP", y, "Open Positions", IntegerToString(PositionsTotal()),        K_BLUE, false);
   y += 10;

   y += 4;  HSep("SEP_3", X, y, W);  y += 1;

   // ══════════════════════════════════════════════════════════════
   //  SECTION: ALPHA ENGINES MATRIX
   // ══════════════════════════════════════════════════════════════
   Rect("MAT_BG", X, y, W, matH, K_SEC_BG);
   y = SecHdr("MAT_H", y, "ALPHA ENGINES  ·  " + IntegerToString(numSym) + " SYMBOLS");

   // Column headers
   Lbl("MAT_CH_SYM", X + LP,       y, "SYMBOL", K_LBL3, 7, true);
   Lbl("MAT_CH_STA", X + LP + 82,  y, "STATUS", K_LBL3, 7, true);
   Lbl("MAT_CH_TRD", X + LP + 200, y, "TREND",  K_LBL3, 7, true);
   Lbl("MAT_CH_ADX", X + LP + 290, y, "ADX",    K_LBL3, 7, true);
   y += 16;
   HSep("MAT_CH_SEP", X + LP, y, W - LP * 2);
   y += 8;

   // ── Symbol rows ────────────────────────────────────────────────
   for(int i = 0; i < numSym; i++)
   {
      string parts[];
      int    np = StringSplit(symbolStates[i], '|', parts);

      string sym  = (np > 0) ? parts[0] : symbolStates[i];
      string p1   = (np > 1) ? parts[1] : "";
      string p2   = (np > 2) ? parts[2] : "";

      StringTrimLeft(sym); StringTrimRight(sym);
      StringTrimLeft(p1);  StringTrimRight(p1);
      StringTrimLeft(p2);  StringTrimRight(p2);

      // ── Parse status / trend / ADX ──────────────────────────────
      string statusTxt = "";
      color  statusCol = K_LBL2;
      string trendTxt  = "-";
      color  trendCol  = K_LBL2;
      string adxTxt    = "-";

      if(StringFind(p1, "TOXIC") >= 0)
      {
         statusTxt = "TOXIC";
         statusCol = K_ORANGE;
      }
      else if(StringFind(p1, "POS OPEN") >= 0)
      {
         statusTxt = "IN TRADE";
         statusCol = K_TEAL;
      }
      else if(StringFind(p1, "PORTFOLIO") >= 0 || StringFind(p1, "HEDGE") >= 0)
      {
         statusTxt = "HEDGE LMT";
         statusCol = K_YELLOW;
      }
      else
      {
         // Normal state: p1 = "Tr:UP"  p2 = "ADX:25.4"
         statusTxt = "READY";
         statusCol = K_LBL3;

         // Parse trend
         int c1 = StringFind(p1, ":");
         string tVal = (c1 >= 0) ? StringSubstr(p1, c1 + 1) : p1;
         StringTrimLeft(tVal); StringTrimRight(tVal);
         if(tVal == "UP")        { trendTxt = "▲ UP";   trendCol = K_GREEN; }
         else if(tVal == "DOWN") { trendTxt = "▼ DOWN"; trendCol = K_RED;   }
         else                    { trendTxt = "● FLAT"; trendCol = K_LBL2;  }

         // Parse ADX
         int c2 = StringFind(p2, ":");
         if(c2 >= 0)
         {
            adxTxt = StringSubstr(p2, c2 + 1);
            StringTrimLeft(adxTxt); StringTrimRight(adxTxt);
         }

         // Set status colour based on trend alignment
         if(tVal == "UP" || tVal == "DOWN") { statusTxt = "ACTIVE"; statusCol = K_GREEN; }
      }

      string s = (string)i;
      int ry = y + 3;

      Lbl("MAT_SY" + s, X + LP,       ry, sym,       K_LBL,     9, true);
      Lbl("MAT_ST" + s, X + LP + 82,  ry, statusTxt, statusCol, 8);
      Lbl("MAT_TR" + s, X + LP + 200, ry, trendTxt,  trendCol,  9);
      Lbl("MAT_AX" + s, X + LP + 290, ry, adxTxt,    K_LBL2,    9);

      y += 22;
      if(i < numSym - 1)
      {
         HSep("MAT_L" + s, X + LP, y, W - LP * 2);
         y += 1;
      }
   }
   y += 10;

   // ══════════════════════════════════════════════════════════════
   //  FOOTER  (22 px)
   // ══════════════════════════════════════════════════════════════
   HSep("SEP_4", X, y, W);
   y += 1;
   Rect("FOOT_BG", X, y, W, 21, K_SYS_BG);
   Lbl("FOOT_L", X + LP, y + 5,
       "MultiAsset Engine  ·  Pro 2.0  ·  SFX Funded",
       K_LBL3, 7);
}

#endif
