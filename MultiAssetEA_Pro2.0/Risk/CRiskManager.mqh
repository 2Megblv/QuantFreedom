//+------------------------------------------------------------------+
//|                                             CRiskManager.mqh     |
//|  v8.7.0 — 2026.04.17                                            |
//|  ATR-based lot sizing with per-asset hard caps applied inside    |
//|  CalculateLotSize() before return. Caps sourced from             |
//|  CGlobalInputs: Inp_MaxLotsFX/Gold/Index/Oil.                   |
//+------------------------------------------------------------------+
#ifndef GUARD_C_RISK_MANAGER
#define GUARD_C_RISK_MANAGER

#property strict

//--- Risk Inputs Migrated from Monolith
#include <MultiAssetEA_Pro2.0/Core/CGlobalInputs.mqh>

// Phase 1 FR-2 fix: Risk state persistence across broker reconnects
struct SRiskManagerState
{
   double            dailyStartEquity;
   double            dailyMaxLossAmount;
   double            dailyProfitTargetAmount;
   datetime          lastDailyReset;
   double            dailyLockedProfit;

   double            weeklyStartEquity;
   double            weeklyMaxLossAmount;
   datetime          lastWeeklyReset;

   double            globalStartEquity;
   double            globalMaxLossAmount;

   int               tradesEnteredToday;
   bool              tradingDisabled;

   uchar             checksum[32];      // SHA256 checksum for corruption detection
};

class CRiskManager
{
private:
   double            m_dailyStartEquity;
   double            m_dailyMaxLossAmount;
   double            m_dailyProfitTargetAmount;
   datetime          m_lastDailyReset;
   double            m_dailyLockedProfit;

   double            m_weeklyStartEquity;
   double            m_weeklyMaxLossAmount;
   datetime          m_lastWeeklyReset;

   double            m_globalStartEquity;
   double            m_globalMaxLossAmount;

   int               m_tradesEnteredToday;
   bool              m_tradingDisabled;

   // Per-symbol daily trade count — prevents one runaway symbol dominating risk
   string            m_symbolTradeNames[];
   int               m_symbolTradeCounts[];

   // Set true only when a present state file fails checksum validation.
   // Constructor cannot return error, so CEngine polls IsStateCorrupted() after new.
   bool              m_stateCorrupted;

   double            PipSize(string symbol);
   double            PriceToPips(string symbol, double priceDistance);

   void              SaveState();
   bool              LoadState();
   void              ComputeChecksum(SRiskManagerState& state);
   bool              ValidateChecksum(const SRiskManagerState& state);

   int               FindOrAddSymbolSlot(string symbol);

public:
                     CRiskManager();
                    ~CRiskManager();

   void              InitializeGlobalLimits();
   void              CheckAllResets();
   void              CheckDailyReset();
   void              CheckWeeklyReset();

   bool              CanEnterTrade();
   bool              CanEnterTradeForSymbol(string symbol);
   double            CalculateLotSize(string symbol, double slDistancePips);

   bool              IsDailyLossLimitExceeded();
   bool              IsDailyProfitTargetReached();
   bool              IsWeeklyDrawdownExceeded();
   bool              IsWeeklyWarningTriggered();
   bool              IsGlobalDrawdownExceeded();

   double            GetRealisticSpread(string symbol);
   double            AdjustEVForCosts(double baseEV, string symbol);

   void              RecordDailyProfit(double realizedProfit);
   void              IncrementTradesToday();
   void              IncrementTradesToday(string symbol);
   int               GetTradesEnteredToday() const { return m_tradesEnteredToday; }
   int               GetTradesTodayForSymbol(string symbol);
   bool              IsToxicMarket(string symbol);
   bool              IsStateCorrupted() const { return m_stateCorrupted; }
};

//+------------------------------------------------------------------+
//| Constructor / Destructor                                         |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager()
{
   m_dailyLockedProfit = 0.0;
   m_tradesEnteredToday = 0;
   m_tradingDisabled = false;
   m_stateCorrupted = false;
   ArrayResize(m_symbolTradeNames, 0);
   ArrayResize(m_symbolTradeCounts, 0);
   InitializeGlobalLimits();
   CheckWeeklyReset();  // Initialize weekly equity baseline on startup

   // Phase 1 FR-2 fix: Attempt to load persisted state from previous session
   if(!LoadState())
   {
      // No valid state file, initialize fresh
      if(Inp_EnableTradeLogging)
         Print("═══ RISK STATE: No valid state file, initializing fresh baselines");
   }
   else
   {
      if(Inp_EnableTradeLogging)
         Print("═══ RISK STATE: Restored from disk - daily baseline preserved across reconnect");
   }
}

CRiskManager::~CRiskManager()
{
   // Phase 1 FR-2 fix: Save state before shutdown for recovery on next session
   SaveState();
}

//+------------------------------------------------------------------+
//| Initialization & Resets                                          |
//+------------------------------------------------------------------+
void CRiskManager::InitializeGlobalLimits()
{
   m_globalStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_globalMaxLossAmount = -MathAbs(m_globalStartEquity * Inp_GlobalMaxDrawdownPct / 100.0);
}

void CRiskManager::CheckAllResets()
{
   CheckDailyReset();
   CheckWeeklyReset();
}

void CRiskManager::CheckDailyReset()
{
   if(!Inp_EnableDailyLossLimit) return;

   MqlDateTime now, last;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(m_lastDailyReset, last);

   if(now.day != last.day)
   {
      m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dailyMaxLossAmount = -MathAbs(m_dailyStartEquity * Inp_DailyMaxLossPct / 100.0);
      m_dailyProfitTargetAmount = m_dailyStartEquity * Inp_DailyProfitTargetPct / 100.0;
      m_lastDailyReset = TimeCurrent();

      m_tradesEnteredToday = 0;
      m_tradingDisabled = false;
      m_dailyLockedProfit = 0.0;

      // Phase 3.3: Zero per-symbol daily trade counts
      for(int i = 0; i < ArraySize(m_symbolTradeCounts); i++)
         m_symbolTradeCounts[i] = 0;

      // Phase 1 FR-2 fix: Save state immediately after reset to prevent loss limit bypass
      SaveState();

      if(Inp_EnableTradeLogging)
         Print("═══ DAILY RESET (OOP) ═══ New equity: ", m_dailyStartEquity, " | Trading enabled");
   }
}

void CRiskManager::CheckWeeklyReset()
{
   if(!Inp_EnableWeeklyDrawdown) return;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   int dayOfWeek = now.day_of_week;

   // Fire on Monday if the last reset was more than 6 days ago.
   // The old condition (lastDayOfWeek != 1) failed from week 2 onward because
   // after the first Monday reset, lastDayOfWeek is always 1 — condition permanently false.
   if(dayOfWeek == 1 && (TimeCurrent() - m_lastWeeklyReset) > (datetime)(6 * 86400))
   {
      m_weeklyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_weeklyMaxLossAmount = -MathAbs(m_weeklyStartEquity * Inp_WeeklyMaxDrawdownPct / 100.0);
      m_lastWeeklyReset = TimeCurrent();

      // Phase 1 FR-2 fix: Save state immediately after reset to prevent loss limit bypass
      SaveState();

      if(Inp_EnableTradeLogging)
         Print("═══ WEEKLY RESET (OOP) ═══ New equity: ", m_weeklyStartEquity);
   }
}

//+------------------------------------------------------------------+
//| Core Limit Checks                                                |
//+------------------------------------------------------------------+
bool CRiskManager::IsDailyLossLimitExceeded()
{
   if(!Inp_EnableDailyLossLimit) return false;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLoss = currentEquity - m_dailyStartEquity;
   return (dailyLoss <= m_dailyMaxLossAmount);
}

bool CRiskManager::IsDailyProfitTargetReached()
{
   if(!Inp_EnableDailyLossLimit) return false;
   return (m_dailyProfitTargetAmount > 0 && m_dailyLockedProfit >= m_dailyProfitTargetAmount);
}

bool CRiskManager::IsWeeklyDrawdownExceeded()
{
   if(!Inp_EnableWeeklyDrawdown) return false;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double weeklyLoss = currentEquity - m_weeklyStartEquity;
   return (weeklyLoss <= m_weeklyMaxLossAmount);
}

bool CRiskManager::IsWeeklyWarningTriggered()
{
   if(!Inp_EnableWeeklyDrawdown) return false;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double weeklyLoss = currentEquity - m_weeklyStartEquity;
   double warningLevel = m_weeklyMaxLossAmount * 0.75;
   return (weeklyLoss <= warningLevel && weeklyLoss > m_weeklyMaxLossAmount);
}

bool CRiskManager::IsGlobalDrawdownExceeded()
{
   if(!Inp_EnableGlobalDrawdown) return false;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double globalLoss = currentEquity - m_globalStartEquity;
   return (globalLoss <= m_globalMaxLossAmount);
}

bool CRiskManager::CanEnterTrade()
{
   if(IsDailyLossLimitExceeded())
   {
      if(Inp_EnableTradeLogging) Print("❌ OOP ENTRY BLOCKED: Daily loss limit exceeded");
      return false;
   }
   if(IsDailyProfitTargetReached())
   {
      if(Inp_EnableTradeLogging) Print("✅ OOP ENTRY BLOCKED: Daily profit target reached");
      return false;
   }
   if(IsWeeklyDrawdownExceeded())
   {
      if(Inp_EnableTradeLogging) Print("❌ OOP ENTRY BLOCKED: Weekly loss limit exceeded");
      return false;
   }
   if(IsGlobalDrawdownExceeded())
   {
      if(Inp_EnableTradeLogging) Print("🛑 CRITICAL OOP: Global drawdown exceeded - NO MORE TRADING");
      return false;
   }
   return true;
}

double CRiskManager::CalculateLotSize(string symbol, double slDistancePips)
{
   if(slDistancePips <= 0) return 0.01; // Fallback
   
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (Inp_RiskPerTradePct / 100.0);
   
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double pipSize   = PipSize(symbol);
   
   if(tickValue <= 0 || tickSize <= 0 || pipSize <= 0) return 0.01;
   
   double riskPerLot = slDistancePips * (pipSize / tickSize) * tickValue;
   if(riskPerLot <= 0) return 0.01;
   
   double rawLot = riskAmount / riskPerLot;
   
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   if(stepLot <= 0) stepLot = 0.01;
   double normalizedLot = MathFloor(rawLot / stepLot) * stepLot;

   // Apply per-asset hard lot cap (safety net against tight-ATR extreme sizing)
   string symUpper = symbol;
   StringToUpper(symUpper);
   bool isIndex = (StringFind(symUpper,"SPX")  >= 0 || StringFind(symUpper,"NAS")  >= 0 ||
                   StringFind(symUpper,"D30")  >= 0 || StringFind(symUpper,"US30") >= 0 ||
                   StringFind(symUpper,"GER")  >= 0 || StringFind(symUpper,"DAX")  >= 0 ||
                   StringFind(symUpper,"DE")   >= 0);
   bool isGold  = (StringFind(symUpper,"XAU")  >= 0 || StringFind(symUpper,"GOLD") >= 0);
   bool isOil   = (StringFind(symUpper,"XTI")  >= 0 || StringFind(symUpper,"WTI")  >= 0 ||
                   StringFind(symUpper,"OIL")  >= 0 || StringFind(symUpper,"USO")  >= 0 ||
                   StringFind(symUpper,"BRENT")>= 0 || StringFind(symUpper,"UKO")  >= 0 ||
                   StringFind(symUpper,"XBR")  >= 0);
   double assetCap = isIndex ? Inp_MaxLotsIndex :
                     isGold  ? Inp_MaxLotsGold  :
                     isOil   ? Inp_MaxLotsOil   :
                               Inp_MaxLotsFX;
   normalizedLot = MathMin(normalizedLot, assetCap);

   return MathMax(minLot, MathMin(normalizedLot, maxLot));
}

//+------------------------------------------------------------------+
//| Slippage & Costs Logic                                           |
//+------------------------------------------------------------------+
double CRiskManager::PipSize(string symbol)
{
   if(StringFind(symbol, "XAU") >= 0) return 0.1;
   if(StringFind(symbol, "XTI") >= 0 || StringFind(symbol, "WTI") >= 0 || StringFind(symbol, "OIL") >= 0 ||
      StringFind(symbol, "USOIL") >= 0 || StringFind(symbol, "USO") >= 0 || StringFind(symbol, "BRENT") >= 0) return 0.01;
   if(StringFind(symbol, "JPY") >= 0) return 0.01;
   // Indices: US30, GER40 (DAX), SPX500, NAS, D30, DE3 etc.
   if(StringFind(symbol, "SPX") >= 0 || StringFind(symbol, "NAS") >= 0 || StringFind(symbol, "D30") >= 0 ||
      StringFind(symbol, "GER") >= 0 || StringFind(symbol, "DE") >= 0) return 1.0; 
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits == 5 || digits == 3) return point * 10.0;
   return point;
}

double CRiskManager::PriceToPips(string symbol, double priceDistance) 
{ 
   double ps = PipSize(symbol); 
   return (ps <= 0.0) ? 0.0 : priceDistance / ps; 
}

double CRiskManager::GetRealisticSpread(string symbol)
{
   if(!Inp_EnableSlippageModeling) return 0.0;
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick)) return 10.0;
   double actualSpread = tick.ask - tick.bid;
   double spreadPips = PriceToPips(symbol, actualSpread);
   if(spreadPips > Inp_MaxAcceptableSpreadPips) return spreadPips;
   
   double baseline = 2.0;
   if(StringFind(symbol, "XAU") >= 0) baseline = Inp_AverageSpreadPips_Metals;
   if(StringFind(symbol, "XTI") >= 0 || StringFind(symbol, "WTI") >= 0 || StringFind(symbol, "OIL") >= 0 ||
      StringFind(symbol, "USOIL") >= 0 || StringFind(symbol, "USO") >= 0 || StringFind(symbol, "BRENT") >= 0)
      baseline = Inp_AverageSpreadPips_Energy;  // NEW Oil energy baseline
   if(StringFind(symbol, "D30") >= 0 || StringFind(symbol, "NAS") >= 0 || StringFind(symbol, "US30") >= 0 ||
      StringFind(symbol, "GER") >= 0 || StringFind(symbol, "SPX") >= 0) baseline = Inp_AverageSpreadPips_Indices;
   return MathMax(spreadPips, baseline);
}

double CRiskManager::AdjustEVForCosts(double baseEV, string symbol)
{
   if(!Inp_EnableSlippageModeling) return baseEV;
   double spread = GetRealisticSpread(symbol);
   double totalCost = spread + Inp_CommissionPipsRoundTrip;
   return baseEV - totalCost;
}

void CRiskManager::RecordDailyProfit(double realizedProfit)
{
   m_dailyLockedProfit += realizedProfit;
}

void CRiskManager::IncrementTradesToday()
{
   m_tradesEnteredToday++;
}

//+------------------------------------------------------------------+
//| Phase 3.3: Per-symbol daily trade count                          |
//+------------------------------------------------------------------+
int CRiskManager::FindOrAddSymbolSlot(string symbol)
{
   int sz = ArraySize(m_symbolTradeNames);
   for(int i = 0; i < sz; i++)
      if(m_symbolTradeNames[i] == symbol) return i;

   ArrayResize(m_symbolTradeNames, sz + 1);
   ArrayResize(m_symbolTradeCounts, sz + 1);
   m_symbolTradeNames[sz] = symbol;
   m_symbolTradeCounts[sz] = 0;
   return sz;
}

void CRiskManager::IncrementTradesToday(string symbol)
{
   m_tradesEnteredToday++;
   int slot = FindOrAddSymbolSlot(symbol);
   m_symbolTradeCounts[slot]++;
}

int CRiskManager::GetTradesTodayForSymbol(string symbol)
{
   int sz = ArraySize(m_symbolTradeNames);
   for(int i = 0; i < sz; i++)
      if(m_symbolTradeNames[i] == symbol) return m_symbolTradeCounts[i];
   return 0;
}

bool CRiskManager::CanEnterTradeForSymbol(string symbol)
{
   if(!CanEnterTrade()) return false;
   if(Inp_MaxTradesPerSymbolPerDay > 0 &&
      GetTradesTodayForSymbol(symbol) >= Inp_MaxTradesPerSymbolPerDay)
   {
      if(Inp_EnableTradeLogging)
         Print("❌ PER-SYMBOL CAP [", symbol, "]: ", GetTradesTodayForSymbol(symbol),
               "/", Inp_MaxTradesPerSymbolPerDay, " trades today — blocking entry");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| C4: Toxicity / News Guard — Two-Layer Defence                    |
//+------------------------------------------------------------------+
bool CRiskManager::IsToxicMarket(string symbol)
{
   if(!Inp_EnableToxicityGuard) return false;
   
   // ─── LAYER 1: Tick Volume Spike Detection ───
   long currentVol = iVolume(symbol, PERIOD_M1, 0);
   long avgVol     = 0;
   int  sampleBars = 20;
   for(int i = 1; i <= sampleBars; i++)
      avgVol += iVolume(symbol, PERIOD_M1, i);
   avgVol = (sampleBars > 0) ? avgVol / sampleBars : 1;
   
   if(avgVol > 0 && (double)currentVol > (double)avgVol * Inp_ToxicityMultiplier)
   {
      if(Inp_EnableTradeLogging)
         Print("⚠️ TOXICITY L1 [", symbol, "]: Tick spike=", currentVol, " vs avg=", avgVol, " (", Inp_ToxicityMultiplier, "x threshold)");
      return true;
   }
   
   // ─── LAYER 2: MT5 Economic Calendar Guard ───
   datetime now     = TimeCurrent();
   datetime fromDT  = now - (datetime)(Inp_NewsGuardMinutes * 60);
   datetime toDT    = now + (datetime)(Inp_NewsGuardMinutes * 60);
   
   MqlCalendarValue values[];
   if(CalendarValueHistory(values, fromDT, toDT, NULL, NULL) > 0)
   {
      // Extract target currencies for the symbol without breaking MT5 API
      string cur1 = "";
      string cur2 = "";
      string upperSym = symbol;
      StringToUpper(upperSym);
      
      bool isGold = (StringFind(upperSym, "XAU") >= 0 || StringFind(upperSym, "GOLD") >= 0);
      bool isOil  = (StringFind(upperSym, "XTI")   >= 0 || StringFind(upperSym, "WTI")   >= 0 ||
                     StringFind(upperSym, "USO")   >= 0 || StringFind(upperSym, "OIL")   >= 0 ||
                     StringFind(upperSym, "BRENT") >= 0 || StringFind(upperSym, "XBR")   >= 0 ||
                     StringFind(upperSym, "UKO")   >= 0);  // XBR/UKO = broker-specific Brent names
      bool isIdxUSD = (StringFind(upperSym, "SPX") >= 0 || StringFind(upperSym, "NAS") >= 0 || StringFind(upperSym, "US30") >= 0 || StringFind(upperSym, "DOW") >= 0);
      bool isIdxEUR = (StringFind(upperSym, "GER") >= 0 || StringFind(upperSym, "D30") >= 0 || StringFind(upperSym, "DE3") >= 0 || StringFind(upperSym, "FRA") >= 0 || StringFind(upperSym, "ESTX") >= 0);
      
      if(isGold || isOil || isIdxUSD) { cur1 = "USD"; }
      else if(isIdxEUR) { cur1 = "EUR"; }
      else {
         // Standard 6-char FX pair parsing fallback
         int len = StringLen(upperSym);
         if(len >= 6) {
            cur1 = StringSubstr(upperSym, 0, 3);
            cur2 = StringSubstr(upperSym, 3, 3);
         }
      }

      for(int i = 0; i < ArraySize(values); i++)
      {
         // Skip events with no confirmed release time (unscheduled/all-day events)
         if(values[i].time == 0) continue;

         // CRITICAL: CalendarValueHistory filters by data period, NOT release time.
         // Must explicitly check the actual release time is within our guard window.
         long timeDiff = MathAbs((long)values[i].time - (long)now);
         if(timeDiff > (long)(Inp_NewsGuardMinutes * 60)) continue;

         // Bug fix: prevent yesterday's events from blocking today's session.
         // An event at 23:42 carries into 00:12 the next day (28-min timeDiff passes above).
         // Compare calendar day of event vs. calendar day of now — skip cross-day events.
         MqlDateTime evtDT; TimeToStruct(values[i].time, evtDT);
         MqlDateTime nowDT; TimeToStruct(now, nowDT);
         if(evtDT.day != nowDT.day || evtDT.mon != nowDT.mon) continue;

         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id, event)) continue;

         if(event.importance == CALENDAR_IMPORTANCE_HIGH)
         {
            MqlCalendarCountry country;
            if(CalendarCountryById(event.country_id, country))
            {
               if(cur1 == "") continue; // symbol parsing failed — skip

               // ── Symbol classification ──────────────────────────────
               // Must match isOil detection above — keep both in sync
               bool isOilSymbol     = (StringFind(upperSym, "XTI")   >= 0 ||
                                       StringFind(upperSym, "WTI")   >= 0 ||
                                       StringFind(upperSym, "USO")   >= 0 ||
                                       StringFind(upperSym, "OIL")   >= 0 ||
                                       StringFind(upperSym, "BRENT") >= 0 ||
                                       StringFind(upperSym, "XBR")   >= 0 ||
                                       StringFind(upperSym, "UKO")   >= 0);
               bool isGoldSymbol    = (StringFind(upperSym, "XAU")  >= 0 ||
                                       StringFind(upperSym, "GOLD") >= 0);
               bool isUSIdxSymbol   = (StringFind(upperSym, "NAS")  >= 0 ||
                                       StringFind(upperSym, "SPX")  >= 0 ||
                                       StringFind(upperSym, "US30") >= 0 ||
                                       StringFind(upperSym, "DOW")  >= 0);
               bool isEURIdxSymbol  = (StringFind(upperSym, "D30")  >= 0 ||
                                       StringFind(upperSym, "GER")  >= 0 ||
                                       StringFind(upperSym, "DAX")  >= 0 ||
                                       StringFind(upperSym, "DE3")  >= 0);

               // ── Event classification (case-insensitive) ─────────────
               // StringFind is case-sensitive — uppercase first to handle
               // broker calendar naming variations ("crude" vs "Crude").
               string evtUpper = event.name;
               StringToUpper(evtUpper);

               bool isOilEvent  = (StringFind(evtUpper, "CRUDE")       >= 0 ||
                                   StringFind(evtUpper, "EIA")          >= 0 ||
                                   StringFind(evtUpper, "DOE")          >= 0 ||  // Dept of Energy
                                   StringFind(evtUpper, "OPEC")         >= 0 ||
                                   StringFind(evtUpper, "OIL")          >= 0 ||
                                   StringFind(evtUpper, "PETROLEUM")    >= 0 ||
                                   StringFind(evtUpper, "NATURAL GAS")  >= 0 ||
                                   StringFind(evtUpper, "GASOLINE")     >= 0 ||  // e.g. "Gasoline Inventories"
                                   StringFind(evtUpper, "DISTILLATE")   >= 0 ||  // e.g. "Distillate Fuel Inventories"
                                   StringFind(evtUpper, "REFINERY")     >= 0 ||  // e.g. "Refinery Utilization"
                                   StringFind(evtUpper, "RIG COUNT")    >= 0);   // e.g. "Baker Hughes Rig Count"

               bool isMacroEvent = (StringFind(evtUpper, "FED")               >= 0 ||
                                    StringFind(evtUpper, "FEDERAL")           >= 0 ||
                                    StringFind(evtUpper, "FOMC")              >= 0 ||
                                    StringFind(evtUpper, "INTEREST RATE")     >= 0 ||
                                    StringFind(evtUpper, "CPI")               >= 0 ||
                                    StringFind(evtUpper, "INFLATION")         >= 0 ||
                                    StringFind(evtUpper, "NFP")               >= 0 ||
                                    StringFind(evtUpper, "NONFARM")           >= 0 ||
                                    StringFind(evtUpper, "NON-FARM")          >= 0 ||
                                    StringFind(evtUpper, "PPI")               >= 0 ||
                                    StringFind(evtUpper, "GDP")               >= 0 ||
                                    StringFind(evtUpper, "RETAIL SALES")      >= 0 ||
                                    StringFind(evtUpper, "UNEMPLOYMENT")      >= 0 ||
                                    StringFind(evtUpper, "PCE")               >= 0 ||
                                    StringFind(evtUpper, "TREASURY")          >= 0 ||
                                    StringFind(evtUpper, "ECB")               >= 0 ||
                                    StringFind(evtUpper, "EUROPEAN CENTRAL")  >= 0 ||
                                    StringFind(evtUpper, "BOE")               >= 0 ||
                                    StringFind(evtUpper, "BANK OF ENGLAND")   >= 0 ||
                                    StringFind(evtUpper, "BOJ")               >= 0 ||
                                    StringFind(evtUpper, "BANK OF JAPAN")     >= 0);

               // ── Filtering rules per asset class ───────────────────
               // Oil events: only block oil symbols — skip for FX, gold, indices
               if(isOilEvent && !isOilSymbol) continue;
               // Oil symbols: only blocked by oil events — skip macro/FX news
               if(isOilSymbol && !isOilEvent) continue;
               // Gold: only macro events
               if(isGoldSymbol && !isMacroEvent) continue;
               // US indices: only macro events
               if(isUSIdxSymbol && !isMacroEvent) continue;
               // EUR indices: only macro events
               if(isEURIdxSymbol && !isMacroEvent) continue;
               // FX pairs (EURUSD, GBPUSD, USDJPY): all HIGH-impact events for their currencies

               if(country.currency == cur1 || country.currency == cur2)
               {
                  if(Inp_EnableTradeLogging)
                     Print("📰 TOXICITY L2 [", symbol, "]: HIGH-impact ", country.currency,
                           " [", event.name, "]",
                           " @ ", TimeToString(values[i].time, TIME_MINUTES),
                           " within ±", Inp_NewsGuardMinutes, " min. Trading paused.");
                  return true;
               }
            }
         }
      }
   }
   
   return false; // Market is clean
}

//+------------------------------------------------------------------+
//| Phase 1 FR-2: Risk State Persistence                             |
//+------------------------------------------------------------------+

// Compute SHA256-like checksum of state (simplified version for MQL5)
void CRiskManager::ComputeChecksum(SRiskManagerState& state)
{
   // Simple but effective checksum: XOR all state variables using MQL5 ArrayFill + direct XOR

   // Initialize checksum to zero
   ArrayFill(state.checksum, 0, 32, 0);

   // XOR each byte of each state variable into checksum
   ulong equity_bits = (ulong)state.dailyStartEquity;
   for(int i = 0; i < 8; i++) state.checksum[i % 32] ^= (uchar)(equity_bits >> (i * 8));

   ulong loss_bits = (ulong)state.dailyMaxLossAmount;
   for(int i = 0; i < 8; i++) state.checksum[(i + 1) % 32] ^= (uchar)(loss_bits >> (i * 8));

   ulong profit_bits = (ulong)state.dailyProfitTargetAmount;
   for(int i = 0; i < 8; i++) state.checksum[(i + 2) % 32] ^= (uchar)(profit_bits >> (i * 8));

   long reset_bits = (long)state.lastDailyReset;
   for(int i = 0; i < 8; i++) state.checksum[(i + 3) % 32] ^= (uchar)(reset_bits >> (i * 8));

   ulong locked_bits = (ulong)state.dailyLockedProfit;
   for(int i = 0; i < 8; i++) state.checksum[(i + 4) % 32] ^= (uchar)(locked_bits >> (i * 8));

   ulong weekly_eq = (ulong)state.weeklyStartEquity;
   for(int i = 0; i < 8; i++) state.checksum[(i + 5) % 32] ^= (uchar)(weekly_eq >> (i * 8));

   ulong weekly_loss = (ulong)state.weeklyMaxLossAmount;
   for(int i = 0; i < 8; i++) state.checksum[(i + 6) % 32] ^= (uchar)(weekly_loss >> (i * 8));

   long weekly_reset = (long)state.lastWeeklyReset;
   for(int i = 0; i < 8; i++) state.checksum[(i + 7) % 32] ^= (uchar)(weekly_reset >> (i * 8));

   ulong global_eq = (ulong)state.globalStartEquity;
   for(int i = 0; i < 8; i++) state.checksum[(i + 8) % 32] ^= (uchar)(global_eq >> (i * 8));

   ulong global_loss = (ulong)state.globalMaxLossAmount;
   for(int i = 0; i < 8; i++) state.checksum[(i + 9) % 32] ^= (uchar)(global_loss >> (i * 8));

   int trades_bits = state.tradesEnteredToday;
   for(int i = 0; i < 4; i++) state.checksum[(i + 10) % 32] ^= (uchar)(trades_bits >> (i * 8));

   int disabled_bit = state.tradingDisabled ? 1 : 0;
   state.checksum[11 % 32] ^= (uchar)disabled_bit;
}

// Validate checksum before restoring state
bool CRiskManager::ValidateChecksum(const SRiskManagerState& state)
{
   SRiskManagerState temp = state;
   uchar savedChecksum[32];
   ArrayCopy(savedChecksum, state.checksum, 0, 0, 32);

   ComputeChecksum(temp);

   // Compare checksums
   for(int i = 0; i < 32; i++)
   {
      if(temp.checksum[i] != savedChecksum[i])
      {
         if(Inp_EnableTradeLogging)
            Print("❌ RISK STATE: Checksum validation failed - corrupted state file");
         return false;
      }
   }
   return true;
}

// Save risk state to file with checksum (atomic write pattern)
void CRiskManager::SaveState()
{
   SRiskManagerState state;

   // Pack current state into struct
   state.dailyStartEquity = m_dailyStartEquity;
   state.dailyMaxLossAmount = m_dailyMaxLossAmount;
   state.dailyProfitTargetAmount = m_dailyProfitTargetAmount;
   state.lastDailyReset = m_lastDailyReset;
   state.dailyLockedProfit = m_dailyLockedProfit;

   state.weeklyStartEquity = m_weeklyStartEquity;
   state.weeklyMaxLossAmount = m_weeklyMaxLossAmount;
   state.lastWeeklyReset = m_lastWeeklyReset;

   state.globalStartEquity = m_globalStartEquity;
   state.globalMaxLossAmount = m_globalMaxLossAmount;

   state.tradesEnteredToday = m_tradesEnteredToday;
   state.tradingDisabled = m_tradingDisabled;

   // Compute checksum
   ComputeChecksum(state);

   // Write to file in MQL5 Files directory
   string filename = "RiskManagerState.bin";
   int handle = FileOpen(filename, FILE_WRITE | FILE_BIN);

   if(handle == INVALID_HANDLE)
   {
      if(Inp_EnableTradeLogging)
         Print("⚠️ RISK STATE: Failed to open state file for writing");
      return;
   }

   // Write struct to file
   FileWriteStruct(handle, state);
   FileClose(handle);

   if(Inp_EnableTradeLogging)
      Print("✅ RISK STATE: Saved to disk - daily baseline protected across reconnect");
}

// Load risk state from file with validation
bool CRiskManager::LoadState()
{
   string filename = "RiskManagerState.bin";

   // Check if file exists
   if(!FileIsExist(filename))
   {
      if(Inp_EnableTradeLogging)
         Print("ℹ️ RISK STATE: No persisted state file found - initializing fresh");
      return false;
   }

   int handle = FileOpen(filename, FILE_READ | FILE_BIN);

   if(handle == INVALID_HANDLE)
   {
      if(Inp_EnableTradeLogging)
         Print("⚠️ RISK STATE: Failed to open state file for reading");
      return false;
   }

   SRiskManagerState state;

   // Read struct from file
   if(!FileReadStruct(handle, state))
   {
      FileClose(handle);
      if(Inp_EnableTradeLogging)
         Print("⚠️ RISK STATE: Failed to read state file");
      return false;
   }

   FileClose(handle);

   // Validate checksum before restoring
   // File exists but checksum fails → genuine corruption (distinct from missing file).
   // Flag m_stateCorrupted so CEngine::OnInit can halt per Inp_HaltOnStateCorruption.
   if(!ValidateChecksum(state))
   {
      m_stateCorrupted = true;
      Print("🛑 RISK STATE CORRUPTED: checksum validation failed on RiskManagerState.bin — operator intervention required");
      return false;
   }

   // Restore state from file
   m_dailyStartEquity = state.dailyStartEquity;
   m_dailyMaxLossAmount = state.dailyMaxLossAmount;
   m_dailyProfitTargetAmount = state.dailyProfitTargetAmount;
   m_lastDailyReset = state.lastDailyReset;
   m_dailyLockedProfit = state.dailyLockedProfit;

   m_weeklyStartEquity = state.weeklyStartEquity;
   m_weeklyMaxLossAmount = state.weeklyMaxLossAmount;
   m_lastWeeklyReset = state.lastWeeklyReset;

   m_globalStartEquity = state.globalStartEquity;
   m_globalMaxLossAmount = state.globalMaxLossAmount;

   m_tradesEnteredToday = state.tradesEnteredToday;
   m_tradingDisabled = state.tradingDisabled;

   if(Inp_EnableTradeLogging)
      Print("✅ RISK STATE: Loaded from disk - baseline preserved");

   return true;
}


#endif
