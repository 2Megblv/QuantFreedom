//+------------------------------------------------------------------+
//|   MultiAsset EA Pro2.0 - Professional Edition                    |
//|   v8.6.1 Sweep+Reclaim Entry Timing + Modular v9 Architecture    |
//|   CEO Approved (APPROVAL_LOG_Apr26.md)                           |
//|   Production Ready for Live Trading                              |
//+------------------------------------------------------------------+
#property strict
#property copyright "Professional Quant Trading Systems"
#property version   "2.00"
#property description "Pro2.0: v8.6.1 Logic in Modular Architecture"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS (must be in main .mq5, not in .mqh includes)
//+------------------------------------------------------------------+

// All input parameters are strictly defined inside CGlobalInputs.mqh to prevent
// multiple definition errors across modular includes.
#include <MultiAssetEA_Pro2.0/Core/CGlobalInputs.mqh>

#include <MultiAssetEA_Pro2.0/Core/CEngine.mqh>

// Global engine instance
CEngine g_Engine;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize engine with Pro2.0 configuration
   if(!g_Engine.OnInit())
   {
      Print("ERROR: CEngine initialization failed");
      return INIT_FAILED;
   }

   Print("═══════════════════════════════════════════════════════════");
   Print("MultiAsset_EA_Pro2.0 initialized successfully");
   Print("Version: 2.0.0");
   Print("Source: v8.7_PRO (CEO Approved)");
   Print("Logic: v8.6.1 Sweep+Reclaim + 3-Layer Pullback Quality");
   Print("Architecture: Modular v9 Classes");
   Print("═══════════════════════════════════════════════════════════");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_Engine.OnDeinit(reason);
   Print("MultiAsset_EA_Pro2.0 shutting down (reason: ", reason, ")");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   g_Engine.OnTick();
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_Engine.OnTimer();
}

//+------------------------------------------------------------------+
//| Expert trade transaction function                                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &req, const MqlTradeResult &res)
{
   g_Engine.OnTradeTransaction(trans, req, res);
}

//+------------------------------------------------------------------+
//| Expert chart event function                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Chart events (button clicks, etc.) handled here if needed
}

//+------------------------------------------------------------------+
//| MODULE INTEGRATION CHECKLIST                                     |
//+------------------------------------------------------------------+
// ✅ CSymbolManager: Sweep state tracking (9 fields x 3 strategies)
// ✅ CStrategyBase: ValidateEntryTiming() + IsADXRising()
// ✅ CAsianBreakout: Phase 1/2/3 sweep+reclaim + quality filter
// ✅ CVWAPReversion: Phase 1/2/3 sweep+reclaim + quality filter
// ✅ CVolatilityMomentum: ADX slope validation
// ✅ CEngine: State persistence by reference + daily reset
// ✅ CRiskManager: 3-tier limits (-2%, -5%, -10%)
// ✅ CExecution: Order execution
// ✅ CIndicatorManager: Indicator calculations
// ✅ CPortfolioRisk: Portfolio correlation guard
// ✅ CDashboard: Dashboard display
// ✅ CSeasonalConfig: Seasonal parameter intelligence
// ✅ CGlobalInputs: All input parameters

//+------------------------------------------------------------------+
//| CONFIGURATION & DEPLOYMENT                                       |
//+------------------------------------------------------------------+
// Configuration file: MultiAsset_EA_Pro2.0_Config.json
// Optimized parameters: Pass #378 from ReportOptimizer-Apr26.xml
// Performance: Sharpe 2.58, Stop-hit <20%, Win rate 57%
//
// To deploy to live:
// 1. Copy MultiAsset_EA_Pro2.0_Config.json to MT5 Files/ directory
// 2. Load MultiAsset_EA_Pro2.0_Apr26_Optimized.set file
// 3. Attach EA to EURUSD M15 chart on live account
// 4. Monitor first week in APPROVAL_LOG_Apr26.md

//+------------------------------------------------------------------+
