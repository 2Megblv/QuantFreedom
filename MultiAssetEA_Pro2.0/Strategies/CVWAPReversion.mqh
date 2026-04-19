//+------------------------------------------------------------------+
//|                                               CVWAPReversion.mqh |
//|  v8.7.0 — 2026.04.17                                            |
//|  Sweep + Reclaim 3-phase mean reversion model.                   |
//|  Fix: Removed ValidateEntryTiming from Phase 3 — band re-touch  |
//|  geometry (2.5–3.5×ATR from VWAP) is incompatible with the      |
//|  pullback-zone filter (EMA±0.3×ATR). 3-phase IS the quality gate.|
//+------------------------------------------------------------------+
#property strict

#include <MultiAssetEA_Pro2.0/Strategies/CStrategyBase.mqh>
#include <MultiAssetEA_Pro2.0/Core/CGlobalInputs.mqh>
#include <MultiAssetEA_Pro2.0/Core/CSymbolManager.mqh>

class CVWAPReversion : public CStrategyBase
{
public:
                     CVWAPReversion();
                    ~CVWAPReversion();

   virtual bool      EvaluateEntry(string symbol, double liveVWAP, double liveATRPips,
                                    double liveEMA_Mid, SSymbolConfig &cfg, int &direction);

private:
   double            PipsToPrice(string symbol, double pips);
};

CVWAPReversion::CVWAPReversion() {}
CVWAPReversion::~CVWAPReversion() {}

double CVWAPReversion::PipsToPrice(string symbol, double pips)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double pipSize = (digits == 5 || digits == 3) ? point * 10.0 : point;

   if(StringFind(symbol, "XAU") >= 0) pipSize = 0.1;
   if(StringFind(symbol, "USO") >= 0) pipSize = 0.01;
   if(StringFind(symbol, "JPY") >= 0) pipSize = 0.01;
   if(StringFind(symbol, "SPX") >= 0 || StringFind(symbol, "NAS") >= 0 || StringFind(symbol, "D30") >= 0) pipSize = 1.0;

   return pips * pipSize;
}

bool CVWAPReversion::EvaluateEntry(string symbol, double liveVWAP, double liveATRPips,
                                    double liveEMA_Mid, SSymbolConfig &cfg, int &direction)
{
   // Use fallback values if indicators not yet ready (prevents false blocks on first bars)
   if(liveVWAP <= 0.0 || liveATRPips <= 0.0)
   {
      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick)) return false;
      if(liveVWAP <= 0.0) liveVWAP = (tick.bid + tick.ask) / 2.0;  // Mid-price fallback
      if(liveATRPips <= 0.0) liveATRPips = 50.0;  // Conservative fallback (pips)
   }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      if(Inp_EnableTradeLogging)
         Print("⚠️ CVWAPReversion: SymbolInfoTick failed for ", symbol, " err=", GetLastError());
      return false;
   }

   double atrPrice = PipsToPrice(symbol, liveATRPips);

   string symUpper = symbol;
   StringToUpper(symUpper);
   bool isComm  = (StringFind(symUpper, "XAU") >= 0 || StringFind(symUpper, "GOLD") >= 0 ||
                   StringFind(symUpper, "XTI") >= 0 || StringFind(symUpper, "WTI")  >= 0 ||
                   StringFind(symUpper, "USO") >= 0 || StringFind(symUpper, "OIL")  >= 0 ||
                   StringFind(symUpper, "XBR") >= 0 || StringFind(symUpper, "UKO")  >= 0 ||
                   StringFind(symUpper, "BRENT") >= 0);
   bool isIndex = (StringFind(symUpper, "NAS")  >= 0 || StringFind(symUpper, "SPX")  >= 0 ||
                   StringFind(symUpper, "US30") >= 0 || StringFind(symUpper, "DOW")  >= 0 ||
                   StringFind(symUpper, "D30")  >= 0 || StringFind(symUpper, "GER")  >= 0 ||
                   StringFind(symUpper, "DAX")  >= 0);
   double vwapDev = isComm  ? Inp_VWAP_Dev_Commodity :
                   isIndex  ? Inp_VWAP_Dev_Index      :
                              Inp_VWAP_Dev_FX;

   double upperBand = liveVWAP + (atrPrice * vwapDev);
   double lowerBand = liveVWAP - (atrPrice * vwapDev);

   // ── PHASE 1: Detect spike past VWAP band (liquidity hunt) ──
   if(!cfg.vwapSweepDetected)
   {
      // Spike above upper band (reversion SHORT setup)
      if(tick.bid > upperBand)
      {
         cfg.vwapSweepDetected = true;
         cfg.vwapSweepDirection = -1;  // Setup to SELL
         cfg.vwapSweepBarCount = 0;
         cfg.vwapSweepReclaimed = false;
         if(Inp_EnableTradeLogging)
            Print("🔍 VWAP SWEEP DETECTED: ", symbol, " spiked ABOVE upper band @ ", DoubleToString(upperBand, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)));
         return false;  // Do NOT enter on spike
      }
      // Spike below lower band (reversion LONG setup)
      else if(tick.ask < lowerBand)
      {
         cfg.vwapSweepDetected = true;
         cfg.vwapSweepDirection = 1;  // Setup to BUY
         cfg.vwapSweepBarCount = 0;
         cfg.vwapSweepReclaimed = false;
         if(Inp_EnableTradeLogging)
            Print("🔍 VWAP SWEEP DETECTED: ", symbol, " spiked BELOW lower band @ ", DoubleToString(lowerBand, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)));
         return false;  // Do NOT enter on spike
      }
      return false;
   }

   // ── PHASE 2: Track spike and wait for reclaim inside bands ──
   // Only increment bar count if reclaim hasn't happened yet
   if(!cfg.vwapSweepReclaimed)
      cfg.vwapSweepBarCount++;

   // Timeout: if reclaim hasn't happened within N bars, cancel and reset
   // v9.2: Silent skip (no logging) to prevent clutter during optimization runs
   if(!cfg.vwapSweepReclaimed && cfg.vwapSweepBarCount > Inp_SweepReclaim_BarsToWait)
   {
      cfg.vwapSweepDetected = false;
      cfg.vwapSweepReclaimed = false;
      return false;
   }

   // Check if price pulled back inside VWAP bands (reclaim)
   if(!cfg.vwapSweepReclaimed)
   {
      if(cfg.vwapSweepDirection == -1)
      {
         // After spiking ABOVE: price must pull back below upper band
         // Use bid (consistent with Phase 1/3 which use bid for above-band checks)
         if(tick.bid <= upperBand)
         {
            cfg.vwapSweepReclaimed = true;
            if(Inp_EnableTradeLogging)
               Print("✓ VWAP RECLAIM: ", symbol, " pulled back inside bands after upside spike");
         }
      }
      else if(cfg.vwapSweepDirection == 1)
      {
         // After spiking BELOW: price must rally back above lower band
         // Use ask (consistent with Phase 1/3 which use ask for below-band checks)
         if(tick.ask >= lowerBand)
         {
            cfg.vwapSweepReclaimed = true;
            if(Inp_EnableTradeLogging)
               Print("✓ VWAP RECLAIM: ", symbol, " pulled back inside bands after downside spike");
         }
      }
      return false;  // Wait for reclaim to complete
   }

   // ── PHASE 3: After reclaim, wait for re-touch with quality validation ──
   if(cfg.vwapSweepDirection == -1 && tick.bid > upperBand)
   {
      // Re-touch upper band after reclaim — mean reversion SHORT
      // ValidateEntryTiming NOT applied here. That filter requires price near EMA Mid
      // (within 0.3 ATR). VWAP Phase 3 entries are band re-touches at 2.5–3.5 ATR
      // from VWAP — the opposite geometry — so Layer 2 systematically rejects every
      // valid entry. The sweep+reclaim+retouch 3-phase pattern IS the quality gate.
      direction = -1;
      cfg.vwapSweepDetected = false;
      cfg.vwapSweepReclaimed = false;
      if(Inp_EnableTradeLogging)
         Print("🚀 VWAP SWEEP+RECLAIM SELL: ", symbol, " — re-touch upper band confirmed");
      return true;
   }
   else if(cfg.vwapSweepDirection == 1 && tick.ask < lowerBand)
   {
      // Re-touch lower band after reclaim — mean reversion LONG
      // See comment above — ValidateEntryTiming not applied for same reason.
      direction = 1;
      cfg.vwapSweepDetected = false;
      cfg.vwapSweepReclaimed = false;
      if(Inp_EnableTradeLogging)
         Print("🚀 VWAP SWEEP+RECLAIM BUY: ", symbol, " — re-touch lower band confirmed");
      return true;
   }

   return false;  // Reclaimed but re-touch hasn't happened yet
}
