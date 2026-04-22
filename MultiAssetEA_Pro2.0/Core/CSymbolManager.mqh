//+------------------------------------------------------------------+
//|                                               CSymbolManager.mqh |
//+------------------------------------------------------------------+
#ifndef GUARD_C_SYMBOL_MANAGER
#define GUARD_C_SYMBOL_MANAGER

#property strict

#include <MultiAssetEA_Pro2.0/Core/SSymbolConfig.mqh>
#include <MultiAssetEA_Pro2.0/Core/CGlobalInputs.mqh>

class CSymbolManager
{
private:
   SSymbolConfig     m_symbols[];
   int               m_count;
   
public:
                     CSymbolManager();
                    ~CSymbolManager();

   void              InitializeSymbols(string symbolsList);
   int               GetCount() { return m_count; }
   SSymbolConfig     GetSymbol(int index);
   bool              GetSymbolRef(int index, SSymbolConfig &outCfg);
   void              UpdateSymbolConfig(int index, SSymbolConfig &cfg);  // Persist modified config back
   void              UpdateAsianHighLow(int index, double high, double low);
   void              ResetDailySweepState();
   void              ReleaseHandles();
};

CSymbolManager::CSymbolManager() { m_count = 0; }
CSymbolManager::~CSymbolManager() { ReleaseHandles(); }

void CSymbolManager::InitializeSymbols(string symbolsList)
{
   string result[];
   int k = StringSplit(symbolsList, ',', result);
   if(k <= 0) return;
   
   m_count = k;
   ArrayResize(m_symbols, m_count);
   
   for(int i = 0; i < k; i++)
   {
      StringTrimLeft(result[i]);
      StringTrimRight(result[i]);
      m_symbols[i].symbol = result[i];
      m_symbols[i].handleEMAFast = iMA(result[i], PERIOD_M15, 9, 0, MODE_EMA, PRICE_CLOSE);
      m_symbols[i].handleEMAMid = iMA(result[i], PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
      m_symbols[i].handleEMASlow = iMA(result[i], PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_symbols[i].handleEMAMacro = iMA(result[i], PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_symbols[i].handleADX = iADX(result[i], PERIOD_M15, 14);
      m_symbols[i].handleATR = iATR(result[i], PERIOD_M15, 14);
      m_symbols[i].handleQFisher = iCustom(result[i], PERIOD_M15, "QFisher_ARMI_TickVolume", 14);
      
      m_symbols[i].asianHigh = 0;
      m_symbols[i].asianLow = 999999;
   }
}

void CSymbolManager::ReleaseHandles()
{
   for(int i = 0; i < m_count; i++)
   {
      if(m_symbols[i].handleEMAFast != INVALID_HANDLE) IndicatorRelease(m_symbols[i].handleEMAFast);
      if(m_symbols[i].handleEMAMid != INVALID_HANDLE) IndicatorRelease(m_symbols[i].handleEMAMid);
      if(m_symbols[i].handleEMASlow != INVALID_HANDLE) IndicatorRelease(m_symbols[i].handleEMASlow);
      if(m_symbols[i].handleEMAMacro != INVALID_HANDLE) IndicatorRelease(m_symbols[i].handleEMAMacro);
      if(m_symbols[i].handleADX != INVALID_HANDLE) IndicatorRelease(m_symbols[i].handleADX);
      if(m_symbols[i].handleATR != INVALID_HANDLE) IndicatorRelease(m_symbols[i].handleATR);
      if(m_symbols[i].handleQFisher != INVALID_HANDLE) IndicatorRelease(m_symbols[i].handleQFisher);
   }
   m_count = 0;
}

SSymbolConfig CSymbolManager::GetSymbol(int index)
{
   if(index >= 0 && index < m_count) return m_symbols[index];
   SSymbolConfig empty;
   ZeroMemory(empty);
   return empty;
}

bool CSymbolManager::GetSymbolRef(int index, SSymbolConfig &outCfg)
{
   // Returns output parameter so modifications persist across ticks
   if(index >= 0 && index < m_count)
   {
      outCfg = m_symbols[index];
      return true;
   }
   return false;
}

void CSymbolManager::UpdateAsianHighLow(int index, double high, double low)
{
   if(index >= 0 && index < m_count)
   {
      m_symbols[index].asianHigh = high;
      m_symbols[index].asianLow = low;
   }
}

void CSymbolManager::ResetDailySweepState()
{
   // Reset all sweep state tracking when daily Asian range resets
   for(int i = 0; i < m_count; i++)
   {
      m_symbols[i].asianSweepDetected = false;
      m_symbols[i].asianSweepDirection = 0;
      m_symbols[i].asianSweepBarCount = 0;
      m_symbols[i].asianSweepReclaimed = false;

      m_symbols[i].vwapSweepDetected = false;
      m_symbols[i].vwapSweepDirection = 0;
      m_symbols[i].vwapSweepBarCount = 0;
      m_symbols[i].vwapSweepReclaimed = false;

      m_symbols[i].volSweepDetected = false;
      m_symbols[i].volSweepDirection = 0;
      m_symbols[i].volSweepBarCount = 0;
   }
   if(Inp_EnableTradeLogging)
      Print("CSymbolManager: Daily sweep state reset for all symbols");
}

void CSymbolManager::UpdateSymbolConfig(int index, SSymbolConfig &cfg)
{
   // Persist modifications back to internal array
   if(index >= 0 && index < m_count)
      m_symbols[index] = cfg;
}

#endif
