//+------------------------------------------------------------------+
//|                                            CVolatilityMomentum.mqh |
//|  v8.6.1: ADX Slope Validation for Entry Confirmation            |
//+------------------------------------------------------------------+
#property strict

#include <MultiAssetEA_Pro2.0/Strategies/CStrategyBase.mqh>

class CVolatilityMomentum : public CStrategyBase
{
public:
                     CVolatilityMomentum();
                    ~CVolatilityMomentum();

   virtual bool      EvaluateEntry(string symbol, double adx, double adxPrevious, int trendDirection, int macroTrend, double currentATR_Pips, double tickVol, double tickVolMA, double qFisher, int &direction);
};

CVolatilityMomentum::CVolatilityMomentum() {}
CVolatilityMomentum::~CVolatilityMomentum() {}

bool CVolatilityMomentum::EvaluateEntry(string symbol, double adx, double adxPrevious, int trendDirection, int macroTrend, double currentATR_Pips, double tickVol, double tickVolMA, double qFisher, int &direction)
{
   if(trendDirection == 0) return false;
   if(currentATR_Pips < 15.0) return false; // Require raw expanding volatility

   // Sprint 5: Institutional MTF Context Filter
   if(trendDirection != macroTrend) return false; // Must align with continuous H4 institutional flow

   // v9.3: Removed Session Anchoring penalty.
   // Gold, FX, and Futures frequently establish their core structural trends
   // during the Asian/Sydney sessions. Penalizing early momentum mathematically
   // forces the EA into late "moving train" entries during the London/NY whipsaws,
   // drastically worsening the risk-to-reward ratio and increasing stop-outs.
   // Standardizing entry thresholds across all 24 hours.

   double reqAdx = 25.0;
   double reqVolMult = 2.0;

   if(adx < reqAdx) return false;          // Require structural trend

   // Sprint 5: VSA Proxy Filter
   if(tickVolMA > 0 && tickVol < tickVolMA * reqVolMult) return false; // Genuine algorithmic surges spike volume 200%+

   // v8.6.1: ADX Slope Validation (prevent entry on falling ADX = trend exhaustion)
   if(!IsADXRising(adx, adxPrevious))
   {
      return false;  // ADX falling — don't enter (trend exhausting)
   }

   // v9.5: QFisher ARMI Tick Volume Filter
   // Validate the entry momentum directionality utilizing custom algorithmic indicator.
   // Requires QFisher to agree with the underlying structural flow.
   if (qFisher != -99999.0) // INVALID_INDICATOR_VALUE check fallback
   {
      if (trendDirection == 1 && qFisher < 0.2) return false;   // Deny weak Longs
      if (trendDirection == -1 && qFisher > -0.2) return false; // Deny weak Shorts
   }

   direction = trendDirection;
   return true;
}
