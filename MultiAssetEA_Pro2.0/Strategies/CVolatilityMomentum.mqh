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

   virtual bool      EvaluateEntry(string symbol, double adx, double adxPrevious, int trendDirection, int macroTrend, double currentATR_Pips, double tickVol, double tickVolMA, int &direction);
};

CVolatilityMomentum::CVolatilityMomentum() {}
CVolatilityMomentum::~CVolatilityMomentum() {}

bool CVolatilityMomentum::EvaluateEntry(string symbol, double adx, double adxPrevious, int trendDirection, int macroTrend, double currentATR_Pips, double tickVol, double tickVolMA, int &direction)
{
   if(trendDirection == 0) return false;
   if(currentATR_Pips < 15.0) return false; // Require raw expanding volatility

   // Sprint 5: Institutional MTF Context Filter
   if(trendDirection != macroTrend) return false; // Must align with continuous H4 institutional flow

   // Sprint 5: Session Anchoring (Liquidity Windows)
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // London: 08:00 - 10:00 | NY: 13:30 - 15:30 (Server Time roughly GMT+2/3)
   // We will approximate broadly for standard brokers:
   bool isLondonOpen = (dt.hour >= 8 && dt.hour <= 10);
   bool isNYOpen = (dt.hour >= 14 && dt.hour <= 16);
   bool isInstWindow = (isLondonOpen || isNYOpen);

   // Dynamic Weighting: Require exponentially more proof outside major sessions
   double reqAdx = isInstWindow ? 25.0 : 40.0;
   double reqVolMult = isInstWindow ? 2.0 : 4.0;

   if(adx < reqAdx) return false;          // Require structural trend

   // Sprint 5: VSA Proxy Filter
   if(tickVolMA > 0 && tickVol < tickVolMA * reqVolMult) return false; // Genuine algorithmic surges spike volume 200%+ (400% outside sessions)

   // v8.6.1: ADX Slope Validation (prevent entry on falling ADX = trend exhaustion)
   if(!IsADXRising(adx, adxPrevious))
   {
      return false;  // ADX falling — don't enter (trend exhausting)
   }

   direction = trendDirection;
   return true;
}
