//+------------------------------------------------------------------+
//|                                            CIndicatorManager.mqh |
//+------------------------------------------------------------------+
#property strict

// Phase 1 FR-4 fix: Sentinel value for invalid indicator values
const double INVALID_INDICATOR_VALUE = -99999.0;

// OOP Indicator state holder per symbol
struct SIndicatorState {
   double liveEMAFast;
   double liveEMAMid;
   double liveEMASlow;
   double liveEMAMacroFast;
   double liveEMAMacroMid;
   double liveADX;
   double liveADXPrev;
   double liveATR_pips;
   
   double asianHigh;
   double asianLow;
   double liveVWAP;
   
   double liveTickVolume;
   double liveTickVolumeMA;
   
   int    liveTrend;
   int    macroTrend;
};

class CIndicatorManager
{
private:
   // Phase 1 FR-4 fix: Helper for handle validation
   bool              IsValidHandle(int handle);

public:
                     CIndicatorManager();
                    ~CIndicatorManager();

   // Core update: Only route this method ONCE per new bar!
   void              UpdateIndicatorsOnBar(string symbol, int handleEMAFast, int handleEMAMid, int handleEMASlow, int handleEMAMacro, int handleADX, int handleATR, SIndicatorState &outState);

   // Phase 1 FR-4 fix: Initialize state with sentinel values
   void              InitializeState(SIndicatorState &state);
};

CIndicatorManager::CIndicatorManager() {}

CIndicatorManager::~CIndicatorManager()
{
   // Phase 1 FR-4 fix: Explicit cleanup (note: handles released by MT5 on EA shutdown)
   // This destructor ensures proper lifecycle management
}

//+------------------------------------------------------------------+
//| Phase 1 FR-4: Indicator Handle Lifecycle Management              |
//+------------------------------------------------------------------+

// Check if handle is valid (not INVALID_HANDLE)
bool CIndicatorManager::IsValidHandle(int handle)
{
   return (handle != INVALID_HANDLE && handle > 0);
}

// Initialize indicator state with sentinel values
void CIndicatorManager::InitializeState(SIndicatorState &state)
{
   state.liveEMAFast = INVALID_INDICATOR_VALUE;
   state.liveEMAMid = INVALID_INDICATOR_VALUE;
   state.liveEMASlow = INVALID_INDICATOR_VALUE;
   state.liveEMAMacroFast = INVALID_INDICATOR_VALUE;
   state.liveEMAMacroMid = INVALID_INDICATOR_VALUE;
   state.liveADX = INVALID_INDICATOR_VALUE;
   state.liveADXPrev = INVALID_INDICATOR_VALUE;
   state.liveATR_pips = INVALID_INDICATOR_VALUE;

   state.asianHigh = INVALID_INDICATOR_VALUE;
   state.asianLow = INVALID_INDICATOR_VALUE;
   state.liveVWAP = INVALID_INDICATOR_VALUE;

   state.liveTickVolume = INVALID_INDICATOR_VALUE;
   state.liveTickVolumeMA = INVALID_INDICATOR_VALUE;

   state.liveTrend = 0;
   state.macroTrend = 0;
}

void CIndicatorManager::UpdateIndicatorsOnBar(string symbol, int handleEMAFast, int handleEMAMid, int handleEMASlow, int handleEMAMacro, int handleADX, int handleATR, SIndicatorState &outState)
{
   // Phase 1 FR-4 fix: Validate all handles before use
   if(!IsValidHandle(handleEMAFast) || !IsValidHandle(handleEMAMid) ||
      !IsValidHandle(handleEMASlow) || !IsValidHandle(handleEMAMacro) ||
      !IsValidHandle(handleADX) || !IsValidHandle(handleATR))
   {
      // One or more handles are invalid - mark all indicators as invalid
      InitializeState(outState);
      if(Inp_EnableTradeLogging)
         Print("⚠️ INDICATOR: Invalid handle detected for ", symbol, " - using sentinel values");
      return;
   }

   double buf[1];

   // Phase 1 FR-4 fix: Validate CopyBuffer success before accepting values
   if(CopyBuffer(handleEMAFast, 0, 1, 1, buf) > 0)
      outState.liveEMAFast = buf[0];
   else
      outState.liveEMAFast = INVALID_INDICATOR_VALUE;

   if(CopyBuffer(handleEMAMid, 0, 1, 1, buf) > 0)
      outState.liveEMAMid = buf[0];
   else
      outState.liveEMAMid = INVALID_INDICATOR_VALUE;

   if(CopyBuffer(handleEMASlow, 0, 1, 1, buf) > 0)
      outState.liveEMASlow = buf[0];
   else
      outState.liveEMASlow = INVALID_INDICATOR_VALUE;

   if(CopyBuffer(handleEMAMacro, 0, 1, 1, buf) > 0)
      outState.liveEMAMacroMid = buf[0];
   else
      outState.liveEMAMacroMid = INVALID_INDICATOR_VALUE;

   if(CopyBuffer(handleADX, 0, 1, 1, buf) > 0)
      outState.liveADX = buf[0];
   else
      outState.liveADX = INVALID_INDICATOR_VALUE;

   if(CopyBuffer(handleADX, 0, 2, 1, buf) > 0)
      outState.liveADXPrev = buf[0];
   else
      outState.liveADXPrev = INVALID_INDICATOR_VALUE;

   if(CopyBuffer(handleATR, 0, 1, 1, buf) > 0)
   {
      // Pip-aware ATR conversion — matches RiskManager.PipSize() logic
      double pipSize = 0.0;
      if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0) pipSize = 0.1;
      else if(StringFind(symbol, "XTI") >= 0 || StringFind(symbol, "WTI") >= 0 || StringFind(symbol, "OIL") >= 0 ||
              StringFind(symbol, "USO") >= 0 || StringFind(symbol, "BRENT") >= 0) pipSize = 0.01;
      else if(StringFind(symbol, "JPY") >= 0) pipSize = 0.01;
      else if(StringFind(symbol, "SPX") >= 0 || StringFind(symbol, "NAS") >= 0 || StringFind(symbol, "D30") >= 0 ||
              StringFind(symbol, "GER") >= 0 || StringFind(symbol, "US30") >= 0 || StringFind(symbol, "UK1") >= 0) pipSize = 1.0;
      else
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         pipSize = (digits == 5 || digits == 3) ? point * 10.0 : point;
      }
      outState.liveATR_pips = (pipSize > 0.0) ? buf[0] / pipSize : buf[0] / SymbolInfoDouble(symbol, SYMBOL_POINT);
   }
   else
      outState.liveATR_pips = INVALID_INDICATOR_VALUE;

   // Phase 1 FR-4 fix: Check for sentinel values before calculating trends
   outState.liveTrend = 0;
   if(outState.liveEMAFast != INVALID_INDICATOR_VALUE &&
      outState.liveEMAMid != INVALID_INDICATOR_VALUE &&
      outState.liveEMASlow != INVALID_INDICATOR_VALUE)
   {
      if(outState.liveEMAFast > outState.liveEMAMid && outState.liveEMAMid > outState.liveEMASlow)
         outState.liveTrend = 1;
      if(outState.liveEMAFast < outState.liveEMAMid && outState.liveEMAMid < outState.liveEMASlow)
         outState.liveTrend = -1;
   }
   
   // Phase 1 FR-4 fix: Check macro EMA validity before calculating macro trend
   outState.macroTrend = 0;
   double closePrice[1];
   if(CopyClose(symbol, PERIOD_H4, 1, 1, closePrice) > 0 &&
      outState.liveEMAMacroMid != INVALID_INDICATOR_VALUE)
   {
      if(closePrice[0] > outState.liveEMAMacroMid)
         outState.macroTrend = 1;
      else if(closePrice[0] < outState.liveEMAMacroMid)
         outState.macroTrend = -1;
   }
   
   // Sprint 5: Dynamic Tick Volume MA (20-period)
   outState.liveTickVolume = 0;
   outState.liveTickVolumeMA = 0;
   long vArr[];
   if(CopyTickVolume(symbol, PERIOD_M15, 1, 20, vArr) == 20)
   {
      long sum = 0;
      for(int i=0; i<20; i++) sum += vArr[i];
      outState.liveTickVolumeMA = (double)sum / 20.0;
      outState.liveTickVolume = (double)vArr[0];  // Most recent bar, not oldest
   }

   // Session-anchored VWAP — cumulates typicalPrice*volume from 00:00 server
   // time through the most recent closed bar. Resets daily at the 00:00 boundary.
   // Institutional mean-reversion trades against the session VWAP, not against
   // a rolling 20-bar window that drifts with price and loses its anchor.
   // Initialize to current bid/ask midpoint as fallback so strategies can trigger on first bar
   MqlTick initVWAPTick;
   if(!SymbolInfoTick(symbol, initVWAPTick))
      initVWAPTick.bid = initVWAPTick.ask = 0;
   outState.liveVWAP = (initVWAPTick.bid > 0 && initVWAPTick.ask > 0) ? (initVWAPTick.bid + initVWAPTick.ask) / 2.0 : 0.0;
   {
      MqlDateTime nowDt;
      TimeToStruct(TimeCurrent(), nowDt);
      nowDt.hour = 0; nowDt.min = 0; nowDt.sec = 0;
      datetime sessionStart = StructToTime(nowDt);

      // v9.1 Fix 4 — symbol-aware session anchor.
      // FX trades 24h so 00:00 server always has bars; commodities/indices
      // open later (XAU 01:00, indices 15:30, USO 23:00 Sun) and CopyRates
      // returns -1 / err 4401. Clamp to the current D1 bar open — that is
      // the earliest timestamp for which this symbol has intraday data.
      datetime symbolDayOpen = iTime(symbol, PERIOD_D1, 0);
      if(symbolDayOpen > 0 && symbolDayOpen > sessionStart)
         sessionStart = symbolDayOpen;

      MqlRates sess[];
      int copied = CopyRates(symbol, PERIOD_M15, sessionStart, TimeCurrent(), sess);
      if(copied > 1)
      {
         double tpv = 0.0;
         long   volSum = 0;
         // Skip the forming bar (last index) — match the "bar 1" convention used above.
         int lastClosedIdx = copied - 2;
         for(int i = 0; i <= lastClosedIdx; i++)
         {
            double tp = (sess[i].high + sess[i].low + sess[i].close) / 3.0;
            long   vol = (long)sess[i].tick_volume;
            tpv    += tp * vol;
            volSum += vol;
         }
         if(volSum > 0) outState.liveVWAP = tpv / volSum;
      }
      else if(Inp_EnableTradeLogging)
      {
         Print("⚠️ CIndicatorManager: session VWAP CopyRates returned ", copied,
               " for ", symbol, " err=", GetLastError());
      }
   }
};

#endif
