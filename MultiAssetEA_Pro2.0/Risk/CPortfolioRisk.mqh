//+------------------------------------------------------------------+
//|                                              CPortfolioRisk.mqh  |
//|  v8.7.0 — 2026.04.17                                            |
//|  C3 — Correlation Delta & USD Exposure Guard.                    |
//|  Delta caps recalibrated for $250K: USD=20, Gold=10,            |
//|  Index=10, Oil=10 (sourced from CGlobalInputs).                 |
//|  Note: XAUUSD contributes to BOTH USD delta (via GetUSDFactor)  |
//|  and Gold delta — by design, gold creates USD exposure.          |
//+------------------------------------------------------------------+
#ifndef GUARD_C_PORTFOLIO_RISK
#define GUARD_C_PORTFOLIO_RISK

#property strict

#include <MultiAssetEA_Pro2.0/Core/CGlobalInputs.mqh>
#include <MultiAssetEA_Pro2.0/Risk/CRiskManager.mqh>
#include <MultiAssetEA_Pro2.0/Indicators/CIndicatorManager.mqh>

// USD bias per symbol: +1 = long USD, -1 = short USD, 0 = no FX
double GetUSDFactor(string symbol, int direction)
{
   // 1. Identify Indices first (no direct FX lot-delta tracking usually)
   if(StringFind(symbol, "SPX") >= 0 || StringFind(symbol, "NAS") >= 0 || StringFind(symbol, "D30") >= 0 || 
      StringFind(symbol, "US30") >= 0 || StringFind(symbol, "DAX") >= 0 || StringFind(symbol, "DE3") >= 0 || 
      StringFind(symbol, "GER") >= 0 || StringFind(symbol, "UK1") >= 0 || StringFind(symbol, "FRA") >= 0 || 
      StringFind(symbol, "CAC") >= 0 || StringFind(symbol, "ESTX") >= 0 || StringFind(symbol, "HK50") >= 0 ||
      StringFind(symbol, "100") >= 0 || StringFind(symbol, "JPN") >= 0 || StringFind(symbol, "USTE") >= 0)
   {
      return 0.0; 
   }

   // 2. Identify Gold
   if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0) return (direction == 1) ? -1.0 : +1.0; 

   // 3. Identify Oil/Energy — priced in USD but not an FX exposure bucket
   if(StringFind(symbol, "XTI") >= 0 || StringFind(symbol, "WTI") >= 0 || StringFind(symbol, "OIL") >= 0 ||
      StringFind(symbol, "USOIL") >= 0 || StringFind(symbol, "USO") >= 0 || StringFind(symbol, "BRENT") >= 0)
   {
      return 0.0; // Oil has its own delta bucket
   }

   // 4. Identify FX
   if(StringFind(symbol, "USD") == 0)           return (direction == 1) ? +1.0 : -1.0; // USDJPY: BUY = long USD
   if(StringFind(symbol, "USD") >= 3)           return (direction == 1) ? -1.0 : +1.0; // EURUSD: BUY = short USD
   
   return 0.0;
}

class CPortfolioRisk
{
private:
   int               m_magic;
   double            m_netUSDDelta;
   double            m_netGoldDelta;
   double            m_netIndexDelta;
   double            m_netOilDelta;     // NEW: Energy/Oil commodity bucket
   
   void              Recalculate();

public:
                     CPortfolioRisk();
                    ~CPortfolioRisk();

   void              SetMagicNumber(int magic) { m_magic = magic; }
   void              Refresh();
   bool              CanAddExposure(string symbol, int direction, double lotSize);
   
   double            GetNetUSDDelta()   { return m_netUSDDelta; }
   double            GetNetGoldDelta()  { return m_netGoldDelta; }
   double            GetNetIndexDelta() { return m_netIndexDelta; }
   double            GetNetOilDelta()   { return m_netOilDelta; }  // NEW
};

CPortfolioRisk::CPortfolioRisk()
{
   m_magic         = Inp_MagicNumber;
   m_netUSDDelta   = 0.0;
   m_netGoldDelta  = 0.0;
   m_netIndexDelta = 0.0;
   m_netOilDelta   = 0.0;  // NEW
}

CPortfolioRisk::~CPortfolioRisk() {}

void CPortfolioRisk::Recalculate()
{
   m_netUSDDelta   = 0.0;
   m_netGoldDelta  = 0.0;
   m_netIndexDelta = 0.0;
   m_netOilDelta   = 0.0;  // NEW
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
      
      string sym  = PositionGetString(POSITION_SYMBOL);
      double lots = PositionGetDouble(POSITION_VOLUME);
      int dir     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      
      double usdFactor = GetUSDFactor(sym, dir);
      m_netUSDDelta += lots * usdFactor;
      
      if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
         m_netGoldDelta += lots * dir;
      else if(StringFind(sym, "XTI") >= 0 || StringFind(sym, "WTI") >= 0 || StringFind(sym, "OIL") >= 0 ||
              StringFind(sym, "USOIL") >= 0 || StringFind(sym, "USO") >= 0 || StringFind(sym, "BRENT") >= 0)
         m_netOilDelta += lots * dir;  // NEW Oil bucket
      else if(StringFind(sym, "SPX") >= 0 || StringFind(sym, "NAS") >= 0 || StringFind(sym, "D30") >= 0 || 
               StringFind(sym, "US30") >= 0 || StringFind(sym, "DAX") >= 0 || StringFind(sym, "DE3") >= 0 || 
               StringFind(sym, "GER") >= 0 || StringFind(sym, "UK1") >= 0 || StringFind(sym, "FRA") >= 0 || 
               StringFind(sym, "CAC") >= 0 || StringFind(sym, "ESTX") >= 0 || StringFind(sym, "HK50") >= 0 ||
               StringFind(sym, "100") >= 0 || StringFind(sym, "JPN") >= 0 || StringFind(sym, "USTE") >= 0)
         m_netIndexDelta += lots * dir;
   }
}

void CPortfolioRisk::Refresh()
{
   Recalculate();
}

bool CPortfolioRisk::CanAddExposure(string symbol, int direction, double lotSize)
{
   Recalculate(); // Always use live account state
   
   double usdFactor   = GetUSDFactor(symbol, direction);
   double newUSDDelta  = m_netUSDDelta + lotSize * usdFactor;
   
   // Delta caps computed as 2× per-trade lot cap — never stale from a cached .set file.
   double capUSD   = Inp_MaxLotsFX    * 2.0;
   double capGold  = Inp_MaxLotsGold  * 2.0;
   double capIndex = Inp_MaxLotsIndex * 2.0;
   double capOil   = Inp_MaxLotsOil   * 2.0;

   // USD Delta Cap
   if(MathAbs(newUSDDelta) > capUSD)
   {
      Print("⛔ CPortfolioRisk: USD delta breach. Current=", m_netUSDDelta, " New=", newUSDDelta, " Cap=", capUSD);
      return false;
   }

   // Gold Delta Cap
   if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
   {
      double newGoldDelta = m_netGoldDelta + lotSize * direction;
      if(MathAbs(newGoldDelta) > capGold)
      {
         Print("⛔ CPortfolioRisk: Gold delta breach. Current=", m_netGoldDelta, " New=", newGoldDelta, " Cap=", capGold);
         return false;
      }
   }

   // Oil Delta Cap
   if(StringFind(symbol, "XTI") >= 0 || StringFind(symbol, "WTI") >= 0 || StringFind(symbol, "OIL") >= 0 ||
      StringFind(symbol, "USOIL") >= 0 || StringFind(symbol, "USO") >= 0 || StringFind(symbol, "BRENT") >= 0)
   {
      double newOilDelta = m_netOilDelta + lotSize * direction;
      if(MathAbs(newOilDelta) > capOil)
      {
         Print("⛔ CPortfolioRisk: Oil delta breach. Current=", m_netOilDelta, " New=", newOilDelta, " Cap=", capOil);
         return false;
      }
   }

   // Index Delta Cap
   if(StringFind(symbol, "SPX") >= 0 || StringFind(symbol, "NAS") >= 0 || StringFind(symbol, "D30") >= 0 ||
      StringFind(symbol, "US30") >= 0 || StringFind(symbol, "DAX") >= 0 || StringFind(symbol, "DE3") >= 0 ||
      StringFind(symbol, "GER") >= 0 || StringFind(symbol, "UK1") >= 0 || StringFind(symbol, "FRA") >= 0 ||
      StringFind(symbol, "CAC") >= 0 || StringFind(symbol, "ESTX") >= 0 || StringFind(symbol, "HK50") >= 0 ||
      StringFind(symbol, "100") >= 0 || StringFind(symbol, "JPN") >= 0 || StringFind(symbol, "USTE") >= 0)
   {
      double newIdxDelta = m_netIndexDelta + lotSize * direction;
      if(MathAbs(newIdxDelta) > capIndex)
      {
         Print("⛔ CPortfolioRisk: Index delta breach. Current=", m_netIndexDelta, " New=", newIdxDelta, " Cap=", capIndex);
         return false;
      }
   }
   
   return true; // All delta checks passed
}
};

#endif
