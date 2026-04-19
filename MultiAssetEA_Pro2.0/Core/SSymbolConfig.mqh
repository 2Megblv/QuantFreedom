//+------------------------------------------------------------------+
//|                                                   SSymbolConfig.mqh |
//| Symbol Configuration Struct — Shared across all modules            |
//+------------------------------------------------------------------+
#ifndef GUARD_S_SYMBOL_CONFIG
#define GUARD_S_SYMBOL_CONFIG

#property strict

struct SSymbolConfig
{
   string  symbol;
   int     handleEMAFast;
   int     handleEMAMid;
   int     handleEMASlow;
   int     handleEMAMacro;
   int     handleADX;
   int     handleATR;

   double  asianHigh;
   double  asianLow;

   // v8.6.1: Sweep+Reclaim tracking (9 new fields for state persistence)
   bool    asianSweepDetected;
   int     asianSweepDirection;
   int     asianSweepBarCount;
   bool    asianSweepReclaimed;

   bool    vwapSweepDetected;
   int     vwapSweepDirection;
   int     vwapSweepBarCount;
   bool    vwapSweepReclaimed;

   bool    volSweepDetected;
   int     volSweepDirection;
   int     volSweepBarCount;
};

#endif
