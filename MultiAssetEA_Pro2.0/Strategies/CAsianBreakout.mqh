//+------------------------------------------------------------------+
//|                                               CAsianBreakout.mqh |
//|  v8.7.0 — 2026.04.17                                            |
//|  Asian range Sweep + Reclaim 3-phase breakout model.             |
//|  ValidateEntryTiming excluded: breakout entries sit above Asian  |
//|  High/below Low, outside the EMA±0.3×ATR pullback zone.         |
//+------------------------------------------------------------------+
#property strict

#include <MultiAssetEA_Pro2.0/Strategies/CStrategyBase.mqh>
#include <MultiAssetEA_Pro2.0/Core/CGlobalInputs.mqh>
#include <MultiAssetEA_Pro2.0/Core/CSymbolManager.mqh>

class CAsianBreakout : public CStrategyBase
{
public:
                     CAsianBreakout();
                    ~CAsianBreakout();

   virtual bool      EvaluateEntry(string symbol, double asianHigh, double asianLow,
                                    double liveEMA_Mid, double liveATR_pips,
                                    SSymbolConfig &cfg, int &direction);

private:
   double            PipsToPrice(string symbol, double pips);
};

CAsianBreakout::CAsianBreakout() {}
CAsianBreakout::~CAsianBreakout() {}

double CAsianBreakout::PipsToPrice(string symbol, double pips)
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

bool CAsianBreakout::EvaluateEntry(string symbol, double asianHigh, double asianLow,
                                    double liveEMA_Mid, double liveATR_pips,
                                    SSymbolConfig &cfg, int &direction)
{
   // If Asian range not yet updated (before 08:00), return false to skip this bar
   // Let the daily reset (OnNewBar) compute the range properly after 08:00
   if(asianHigh <= 0.0 || asianLow >= 999999.0) return false;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      if(Inp_EnableTradeLogging)
         Print("⚠️ CAsianBreakout: SymbolInfoTick failed for ", symbol, " err=", GetLastError());
      return false;
   }

   double buffer = PipsToPrice(symbol, Inp_BreakoutBufferPips);

   // ── PHASE 1: Detect sweep (price breaks out of Asian range) ──
   if(!cfg.asianSweepDetected)
   {
      // Upside sweep
      if(tick.bid > asianHigh + buffer)
      {
         cfg.asianSweepDetected = true;
         cfg.asianSweepDirection = 1;
         cfg.asianSweepBarCount = 0;
         cfg.asianSweepReclaimed = false;
         if(Inp_EnableTradeLogging)
            Print("🔍 ASIAN SWEEP DETECTED: ", symbol, " swept ABOVE high @ ", DoubleToString(asianHigh, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)));
         return false;  // Do NOT enter on sweep
      }
      // Downside sweep
      else if(tick.ask < asianLow - buffer)
      {
         cfg.asianSweepDetected = true;
         cfg.asianSweepDirection = -1;
         cfg.asianSweepBarCount = 0;
         cfg.asianSweepReclaimed = false;
         if(Inp_EnableTradeLogging)
            Print("🔍 ASIAN SWEEP DETECTED: ", symbol, " swept BELOW low @ ", DoubleToString(asianLow, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)));
         return false;  // Do NOT enter on sweep
      }
      return false;
   }

   // ── PHASE 2: Track sweep and wait for reclaim ──
   // Only increment bar count if reclaim hasn't happened yet
   if(!cfg.asianSweepReclaimed)
      cfg.asianSweepBarCount++;

   // Timeout: if reclaim hasn't happened within N bars, cancel and reset
   if(!cfg.asianSweepReclaimed && cfg.asianSweepBarCount > Inp_SweepReclaim_BarsToWait)
   {
      if(Inp_EnableTradeLogging)
         Print("⏰ ASIAN SWEEP TIMEOUT: ", symbol, " — no reclaim within ", Inp_SweepReclaim_BarsToWait, " bars");
      cfg.asianSweepDetected = false;
      cfg.asianSweepReclaimed = false;
      return false;
   }

   // Check if price pulled back inside the Asian range (reclaim).
   // Buffer is applied symmetrically with Phase 1 sweep and Phase 3 re-break:
   // a 1-pip dip back to asianHigh must NOT count as reclaim if the re-break
   // threshold is asianHigh + buffer — otherwise Phase 2 completes on noise
   // and Phase 3 is unreachable by the same amount of noise.
   if(!cfg.asianSweepReclaimed)
   {
      if(cfg.asianSweepDirection == 1)
      {
         if(tick.bid <= asianHigh - buffer)
         {
            cfg.asianSweepReclaimed = true;
            if(Inp_EnableTradeLogging)
               Print("✓ ASIAN RECLAIM: ", symbol, " pulled back inside range after upside sweep");
         }
      }
      else if(cfg.asianSweepDirection == -1)
      {
         if(tick.ask >= asianLow + buffer)
         {
            cfg.asianSweepReclaimed = true;
            if(Inp_EnableTradeLogging)
               Print("✓ ASIAN RECLAIM: ", symbol, " pulled back inside range after downside sweep");
         }
      }
      return false;
   }

   // ── PHASE 3: After reclaim, wait for re-break ──
   if(cfg.asianSweepDirection == 1 && tick.bid > asianHigh + buffer)
   {
      // Second break above Asian High after reclaim — THIS is the real entry.
      // ValidateEntryTiming (pullback quality filter) is NOT applied here.
      // That filter requires price near EMA Mid — breakout entries are by definition
      // above Asian High and away from EMA, so Layer 1 (extension) and Layer 2
      // (pullback zone) would systematically reject every valid breakout.
      // The sweep+reclaim 3-phase pattern IS the quality validation for this strategy.
      direction = 1;
      cfg.asianSweepDetected = false;
      cfg.asianSweepReclaimed = false;
      if(Inp_EnableTradeLogging)
         Print("🚀 ASIAN SWEEP+RECLAIM BUY: ", symbol, " — second break above high confirmed");
      return true;
   }
   else if(cfg.asianSweepDirection == -1 && tick.ask < asianLow - buffer)
   {
      // Second break below Asian Low after reclaim — THIS is the real entry.
      // See comment above — ValidateEntryTiming not applied for same reason.
      direction = -1;
      cfg.asianSweepDetected = false;
      cfg.asianSweepReclaimed = false;
      if(Inp_EnableTradeLogging)
         Print("🚀 ASIAN SWEEP+RECLAIM SELL: ", symbol, " — second break below low confirmed");
      return true;
   }

   return false;  // Reclaimed but second break hasn't happened yet
}
