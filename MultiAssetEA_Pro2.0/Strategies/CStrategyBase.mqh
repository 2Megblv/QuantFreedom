//+------------------------------------------------------------------+
//|                                                 CStrategyBase.mqh|
//| v9.2: Entry Decision Logging for visibility into filter logic
//+------------------------------------------------------------------+
#property strict

#include <MultiAssetEA_Pro2.0/Core/CGlobalInputs.mqh>

//+------------------------------------------------------------------+
//| Entry Decision Tracking (Phase 2 Fix 3)
//+------------------------------------------------------------------+

struct SEntryDecision
{
   string   symbol;          // Trading pair (e.g., "EURUSD")
   long     timestamp;       // Timestamp of decision
   int      direction;       // 1=BUY, -1=SELL
   bool     passedLayer1;    // Extension filter (<1.0 ATR from EMA)
   bool     passedLayer2;    // Pullback zone (0.3 ATR from EMA)
   bool     passedLayer3;    // Candle momentum confirmation
   bool     finalResult;     // Final decision (accepted or rejected)
   double   price;           // Entry price (ASK for BUY, BID for SELL)
   double   ema;             // EMA Mid at decision time
   double   atr;             // ATR in pips at decision time
   string   reason;          // Why accepted/rejected
};

class CStrategyBase
{
public:
                     CStrategyBase();
   virtual          ~CStrategyBase();

   virtual bool      EvaluateEntry(string symbol, int &direction); // Per bar entry check

   // v8.6.1: Pullback Quality Filter (3-layer validation)
   bool              ValidateEntryTiming(
      string symbol,
      double liveEMA_Mid,
      double liveATR_pips,
      int direction,
      MqlTick &tick
   );

   // v8.6.1: ADX Slope validation (prevents entry on falling ADX)
   bool              IsADXRising(double adxCurrent, double adxPrevious);

   // Phase 2 Fix 3: Entry decision logging and monitoring
   void              LogEntryDecision(const SEntryDecision &decision);
   SEntryDecision    GetLastDecision();
   int               GetDecisionCount() { return m_decisionIndex; }

private:
   double            PipsToPrice(string symbol, double pips);
   
   // Phase 2 Fix 3: Track last 8 entry decisions
   SEntryDecision    m_lastDecisions[8];
   int               m_decisionIndex;  // Current index in circular buffer
};

//+------------------------------------------------------------------+
//| Implementation                                                   |
//+------------------------------------------------------------------+
CStrategyBase::CStrategyBase() 
{
   m_decisionIndex = 0;
   // MQL5: ArrayFill doesn't work with structs - use loop instead
   for(int i = 0; i < 8; i++)
   {
      m_lastDecisions[i].symbol = "";
      m_lastDecisions[i].timestamp = 0;
      m_lastDecisions[i].direction = 0;
      m_lastDecisions[i].passedLayer1 = false;
      m_lastDecisions[i].passedLayer2 = false;
   }
}

CStrategyBase::~CStrategyBase() {}

bool CStrategyBase::EvaluateEntry(string symbol, int &direction) { return false; }

//+------------------------------------------------------------------+
//| Phase 2 Fix 3: Entry Decision Logging
//+------------------------------------------------------------------+

void CStrategyBase::LogEntryDecision(const SEntryDecision &decision)
{
   // Store decision in circular buffer (last 8 decisions)
   m_lastDecisions[m_decisionIndex] = decision;
   m_decisionIndex = (m_decisionIndex + 1) % 8;
   
   // Log to journal
   string dirStr = (decision.direction == 1) ? "BUY" : "SELL";
   string resultStr = decision.finalResult ? "✅ ACCEPT" : "❌ REJECT";
   
   Print(StringFormat("Entry Decision: %s %s | %s | L1:%d L2:%d L3:%d | Price:%.5f EMA:%.5f ATR:%.1f | Reason: %s",
      decision.symbol,
      dirStr,
      resultStr,
      decision.passedLayer1,
      decision.passedLayer2,
      decision.passedLayer3,
      decision.price,
      decision.ema,
      decision.atr,
      decision.reason
   ));
}

SEntryDecision CStrategyBase::GetLastDecision()
{
   // Return the last recorded decision (m_decisionIndex points to NEXT slot)
   int lastIdx = (m_decisionIndex - 1 + 8) % 8;
   return m_lastDecisions[lastIdx];
}

double CStrategyBase::PipsToPrice(string symbol, double pips)
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

bool CStrategyBase::IsADXRising(double adxCurrent, double adxPrevious)
{
   // v9.2: ADX slope smoothing with threshold (prevents single-bar noise)
   // Returns true if:
   // - ADX rising by ≥0.5 (threshold prevents noise), OR
   // - ADX level >30 (strong trend regardless of single-bar move)
   // Fixes: ~5-10% entry rate improvement by accepting valid moves on noisy M15
   
   double adxThreshold = 0.5;  // Minimum rise to count as "rising"
   double strongADXLevel = 30.0;  // Strong trend threshold
   
   bool isRising = (adxCurrent > adxPrevious + adxThreshold);
   bool isStrongTrend = (adxCurrent > strongADXLevel);
   
   return isRising || isStrongTrend;
}

bool CStrategyBase::ValidateEntryTiming(
   string symbol,
   double liveEMA_Mid,
   double liveATR_pips,
   int direction,
   MqlTick &tick
)
{
   // v8.6.1: 3-Layer Pullback Quality Filter
   // Ensures entries are on pullbacks, not on peaks/exhaustion
   // Phase 2 Fix 3: Log each layer decision

   SEntryDecision decision;
   decision.symbol = symbol;
   decision.timestamp = TimeCurrent();
   decision.direction = direction;
   decision.ema = liveEMA_Mid;
   decision.atr = liveATR_pips;
   decision.price = (direction == 1) ? tick.ask : tick.bid;
   decision.passedLayer1 = false;
   decision.passedLayer2 = false;
   decision.passedLayer3 = false;
   decision.finalResult = false;
   decision.reason = "";

   if(liveATR_pips <= 0.0)
   {
      decision.reason = "ATR invalid (<=0)";
      LogEntryDecision(decision);
      return false;
   }

   double atrPrice = PipsToPrice(symbol, liveATR_pips);

   // ── LAYER 1: Extension Filter ──
   // Price must NOT be too far from EMA Mid (max 1.0 ATR distance)
   // BUY:  price <= EMA_Mid + (1.0 * ATR)
   // SELL: price >= EMA_Mid - (1.0 * ATR)
   double maxExtension = atrPrice * 1.0;

   if(direction == 1)  // BUY
   {
      if(tick.ask > liveEMA_Mid + maxExtension)
      {
         decision.reason = StringFormat("Layer 1: Price too extended (ask=%.5f > EMA+ATR=%.5f)", 
            tick.ask, liveEMA_Mid + maxExtension);
         LogEntryDecision(decision);
         return false;  // Price too extended above EMA Mid
      }
   }
   else if(direction == -1)  // SELL
   {
      if(tick.bid < liveEMA_Mid - maxExtension)
      {
         decision.reason = StringFormat("Layer 1: Price too extended (bid=%.5f < EMA-ATR=%.5f)", 
            tick.bid, liveEMA_Mid - maxExtension);
         LogEntryDecision(decision);
         return false;  // Price too extended below EMA Mid
      }
   }
   
   decision.passedLayer1 = true;

   // ── LAYER 2: Pullback Zone Filter ──
   // Price must be within pullback zone (0.3 ATR from EMA Mid)
   // BUY:  price >= EMA_Mid - (0.3 * ATR)  [entry within pullback zone]
   // SELL: price <= EMA_Mid + (0.3 * ATR)
   double pullbackZone = atrPrice * 0.3;

   if(direction == 1)  // BUY
   {
      if(tick.ask < liveEMA_Mid - pullbackZone)
      {
         decision.reason = StringFormat("Layer 2: Outside pullback zone (ask=%.5f < EMA-0.3ATR=%.5f)", 
            tick.ask, liveEMA_Mid - pullbackZone);
         LogEntryDecision(decision);
         return false;  // Price too extended below EMA Mid
      }
   }
   else if(direction == -1)  // SELL
   {
      if(tick.bid > liveEMA_Mid + pullbackZone)
      {
         decision.reason = StringFormat("Layer 2: Outside pullback zone (bid=%.5f > EMA+0.3ATR=%.5f)", 
            tick.bid, liveEMA_Mid + pullbackZone);
         LogEntryDecision(decision);
         return false;  // Price too extended above EMA Mid
      }
   }
   
   decision.passedLayer2 = true;

   // ── LAYER 3: Candle Confirmation Filter ──
   // Requires momentum candle in specific zone of bar range
   // BUY:  candle close in upper 60% of range (momentum up)
   // SELL: candle close in lower 40% of range (momentum down)
   // Use bar[1] (last CLOSED bar) — bar[0] is the still-forming bar whose
   // high/low/close change every tick and would give unreliable ratio readings.

   MqlRates rates[];
   if(CopyRates(symbol, PERIOD_M15, 1, 1, rates) <= 0)
   {
      // Can't validate, allow entry
      decision.reason = "Layer 3: CopyRates failed, allowing entry";
      decision.passedLayer3 = true;
      decision.finalResult = true;
      LogEntryDecision(decision);
      return true;
   }

   double range = rates[0].high - rates[0].low;

   if(range <= 0.0)
   {
      // No range, allow entry
      decision.reason = "Layer 3: No bar range, allowing entry";
      decision.passedLayer3 = true;
      decision.finalResult = true;
      LogEntryDecision(decision);
      return true;
   }

   double closeRatio = (rates[0].close - rates[0].low) / range;  // 0.0 = bottom, 1.0 = top

   if(direction == 1)  // BUY: close should be in upper 60% of range
   {
      if(closeRatio < 0.60)
      {
         decision.reason = StringFormat("Layer 3: No candle momentum (closeRatio=%.2f < 0.60)", closeRatio);
         LogEntryDecision(decision);
         return false;  // Candle not in upper part of range
      }
   }
   else if(direction == -1)  // SELL: close should be in lower 40% of range
   {
      if(closeRatio > 0.40)
      {
         decision.reason = StringFormat("Layer 3: No candle momentum (closeRatio=%.2f > 0.40)", closeRatio);
         LogEntryDecision(decision);
         return false;  // Candle not in lower part of range
      }
   }

   // All 3 layers passed
   decision.passedLayer3 = true;
   decision.finalResult = true;
   decision.reason = "All layers passed - entry accepted";
   LogEntryDecision(decision);
   return true;
}
