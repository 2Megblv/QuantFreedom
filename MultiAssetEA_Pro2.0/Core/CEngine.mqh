//+------------------------------------------------------------------+
//|                                                   CEngine.mqh    |
//|  v9.0.0 — 2026.04.17                                            |
//|  Main orchestration engine. Post-overhaul: Rank 3 artifact       |
//|  guards removed (defaults now defensible), seasonal config and   |
//|  Ext_* mutable globals purged. ValidateInputs() in OnInit halts  |
//|  on any out-of-range input so optimizer artifacts cannot ship.   |
//+------------------------------------------------------------------+
#ifndef GUARD_C_ENGINE
#define GUARD_C_ENGINE

#property strict

#include <MultiAssetEA_Pro2.0/Core/CSymbolManager.mqh>
#include <MultiAssetEA_Pro2.0/Core/CSweepStatePersistence.mqh>
#include <MultiAssetEA_Pro2.0/Risk/CRiskManager.mqh>
#include <MultiAssetEA_Pro2.0/Risk/CPortfolioRisk.mqh>
#include <MultiAssetEA_Pro2.0/Indicators/CIndicatorManager.mqh>
#include <MultiAssetEA_Pro2.0/Execution/CExecution.mqh>
#include <MultiAssetEA_Pro2.0/Strategies/CAsianBreakout.mqh>
#include <MultiAssetEA_Pro2.0/Strategies/CVWAPReversion.mqh>
#include <MultiAssetEA_Pro2.0/Strategies/CVolatilityMomentum.mqh>
#include <MultiAssetEA_Pro2.0/UI/CDashboard.mqh>
#include <MultiAssetEA_Pro2.0/Core/CGlobalInputs.mqh>

class CEngine
{
private:
   CSymbolManager*       m_symMgr;
   CRiskManager*         m_riskMgr;
   CIndicatorManager*    m_indMgr;
   CExecution*           m_exec;
   CDashboard*           m_dash;
   CSweepStatePersistence* m_sweepStateManager;

   CAsianBreakout*       m_stratBreakout;
   CVWAPReversion*       m_stratReversion;
   CVolatilityMomentum*  m_stratMomentum;
   CPortfolioRisk*       m_portfolioRisk;   // C5: Correlation delta guard

   datetime              m_lastBarTimes[];  // Per-symbol bar tracker
   datetime              m_lastDailyResetDate;   // Date-span tracker (replaces static int lastDay)
   datetime              m_lastAsianRangeDate;   // Date-span tracker (replaces static int lastAsianRangeDay)
   SIndicatorState       m_states[];

   void                  OnNewBar();
   void                  CheckWeekendFlatten();
   void                  CheckEODFlatten();
   bool                  ValidateInputs();
   static datetime       DayStart(datetime t);

public:
                     CEngine();
                    ~CEngine();

   bool              OnInit();
   void              OnTick();
   void              OnTimer();
   void              OnDeinit(const int reason);
   void              OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &req, const MqlTradeResult &res);
};

//+------------------------------------------------------------------+
//| Implementation                                                   |
//+------------------------------------------------------------------+
CEngine::CEngine() {}

CEngine::~CEngine()
{
   if(m_symMgr != NULL) delete m_symMgr;
   if(m_riskMgr != NULL) delete m_riskMgr;
   if(m_indMgr != NULL) delete m_indMgr;
   if(m_exec != NULL) delete m_exec;
   if(m_dash != NULL) delete m_dash;
   if(m_sweepStateManager != NULL) delete m_sweepStateManager;
   if(m_stratBreakout != NULL) delete m_stratBreakout;
   if(m_stratReversion != NULL) delete m_stratReversion;
   if(m_stratMomentum != NULL) delete m_stratMomentum;
   if(m_portfolioRisk != NULL) delete m_portfolioRisk;
}

bool CEngine::OnInit()
{
   if(!ValidateInputs()) return false;

   m_symMgr = new CSymbolManager();
   m_symMgr.InitializeSymbols(Inp_EngineSymbols);

   // Phase 2 Fix 2: Initialize sweep state persistence (DISABLED - field mismatch errors)
   // TODO: Fix field mapping between SSymbolConfig and CSweepStatePersistence JSON format
   // m_sweepStateManager = new CSweepStatePersistence();
   // Print("✓ Sweep state persistence initialized");
   m_sweepStateManager = NULL;  // Disabled for v9.0 compilation

   m_riskMgr = new CRiskManager();

   // Phase 3.2: Halt on corrupted persisted state (no silent fallback).
   // Constructor cannot return an error; poll IsStateCorrupted() right after new.
   if(m_riskMgr.IsStateCorrupted() && Inp_HaltOnStateCorruption)
   {
      Print("🛑 CEngine: RiskManagerState.bin is corrupted and Inp_HaltOnStateCorruption=true — halting. Delete or repair the file to proceed.");
      return false;
   }

   m_indMgr = new CIndicatorManager();
   m_exec = new CExecution();
   m_dash = new CDashboard();

   m_stratBreakout   = new CAsianBreakout();
   m_stratReversion  = new CVWAPReversion();
   m_stratMomentum   = new CVolatilityMomentum();
   m_portfolioRisk   = new CPortfolioRisk(); // C5

   ArrayResize(m_states, m_symMgr.GetCount());
   ArrayResize(m_lastBarTimes, m_symMgr.GetCount());
   ArrayFill(m_lastBarTimes, 0, m_symMgr.GetCount(), 0);
   m_lastDailyResetDate = 0;
   m_lastAsianRangeDate = 0;

   // Phase 2 Fix 2: Load sweep state from files for each symbol
   // This prevents double entries on pause/resume cycles
   // Sweep state loading disabled (persistence disabled in OnInit)
   // Print("Loading saved sweep states for symbols...");

   EventSetTimer(1);

   Print("CEngine: Initialized OOP Architecture for ", m_symMgr.GetCount(), " symbols.");
   return true;
}

datetime CEngine::DayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

bool CEngine::ValidateInputs()
{
   // Hard bounds: closes the optimizer-artifact attack vector at source.
   // Any .set file loading nonsense values halts the EA with a loud error.
   string err = "";
   if(Inp_Rule8_FirstTP_Pct  <= 0.0 || Inp_Rule8_FirstTP_Pct  > 100.0) err += " Rule8_FirstTP_Pct (0,100]";
   if(Inp_Rule8_SecondTP_Pct <= 0.0 || Inp_Rule8_SecondTP_Pct > 100.0) err += " Rule8_SecondTP_Pct (0,100]";
   if(Inp_Rule4_PartialClose_Pct <= 0.0 || Inp_Rule4_PartialClose_Pct > 100.0) err += " Rule4_PartialClose_Pct (0,100]";
   if(Inp_Rule11_Trigger_Pct <= 0.0 || Inp_Rule11_Trigger_Pct > 100.0) err += " Rule11_Trigger_Pct (0,100]";
   if(Inp_ToxicityMultiplier < 1.5 || Inp_ToxicityMultiplier > 10.0)   err += " ToxicityMultiplier [1.5,10]";
   if(Inp_Rule10_ATRMultiplier <= 0.0 || Inp_Rule10_ATRMultiplier > 5.0) err += " Rule10_ATRMultiplier (0,5]";
   if(Inp_Rule10_TrailBase_Pips <= 0.0 || Inp_Rule10_TrailBase_Pips > 200.0) err += " Rule10_TrailBase_Pips (0,200]";
   if(Inp_Rule5_ATRSpikeMultiplier < 1.5 || Inp_Rule5_ATRSpikeMultiplier > 10.0) err += " Rule5_ATRSpikeMultiplier [1.5,10]";
   if(Inp_SweepReclaim_BarsToWait < 4 || Inp_SweepReclaim_BarsToWait > 96) err += " SweepReclaim_BarsToWait [4,96]";
   if(Inp_Rule6_MaxTimeOpen_Seconds < 60 || Inp_Rule6_MaxTimeOpen_Seconds > 86400) err += " Rule6_MaxTimeOpen_Seconds [60,86400]";
   if(Inp_MaxTradesPerSymbolPerDay < 1 || Inp_MaxTradesPerSymbolPerDay > 50) err += " MaxTradesPerSymbolPerDay [1,50]";
   if(Inp_RiskRewardRatio < 1.0 || Inp_RiskRewardRatio > 5.0) err += " RiskRewardRatio [1.0,5.0]";
   if(Inp_FridayFlattenHour < -1 || Inp_FridayFlattenHour > 23) err += " FridayFlattenHour [-1,23]";

   if(StringLen(err) > 0)
   {
      Print("🛑 ValidateInputs: out-of-range input(s):", err, " — halting.");
      return false;
   }
   Print("✅ ValidateInputs: all inputs within bounds.");
   return true;
}

void CEngine::OnTick()
{
   // v9.1: Weekend flatten — cheap day-of-week check, fires once per Friday 22:00+.
   // Placed before tick exits so a RULE_WeekendFlat close-all beats any other exit.
   CheckWeekendFlatten();

   // EOD flatten — daily flatten 15 mins before NY Close
   CheckEODFlatten();

   // PER-TICK EXITS (Trailing stops, immediate risk stops)
   m_exec.ManageTickExits(m_riskMgr, m_states);

   // NEW BAR CHECKER - Per-symbol independent bar tracking
   int totalSymbols = m_symMgr.GetCount();
   bool anyNewBar = false;

   for(int i = 0; i < totalSymbols; i++)
   {
      SSymbolConfig conf;
      if(!m_symMgr.GetSymbolRef(i, conf)) continue;

      datetime barTime = iTime(conf.symbol, PERIOD_M15, 0);
      if(barTime != m_lastBarTimes[i])
      {
         m_lastBarTimes[i] = barTime;
         anyNewBar = true;
      }
   }

   if(anyNewBar)
   {
      OnNewBar();
   }
}

void CEngine::OnNewBar()
{
   m_riskMgr.CheckAllResets();  // Daily and weekly resets

   datetime today = DayStart(TimeCurrent());

   if(today != m_lastDailyResetDate)
   {
      m_symMgr.ResetDailySweepState();
      m_lastDailyResetDate = today;
      if(Inp_EnableTradeLogging)
         Print("CEngine: Daily sweep state reset (new trading day)");
   }

   // Asian session range (00:00–08:00 server time), computed once after 08:00.
   // Date-based comparison avoids the month-rollover trap of day-of-month checks
   // and survives EA restart mid-day (m_lastAsianRangeDate persists as 0 on init,
   // triggering computation on first post-08:00 bar after restart).
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(today != m_lastAsianRangeDate && dt.hour >= 8)
   {
      m_lastAsianRangeDate = today;

      int totalSymbols = m_symMgr.GetCount();
      MqlRates rates[];

      for(int i = 0; i < totalSymbols; i++)
      {
         SSymbolConfig conf;
         if(!m_symMgr.GetSymbolRef(i, conf)) continue;

         int copied = CopyRates(conf.symbol, PERIOD_H1, 1, 9, rates);
         if(copied == 9)
         {
            double asianHigh = 0.0;
            double asianLow = 999999.0;

            for(int j = 0; j < 9; j++)
            {
               if(rates[j].high > asianHigh) asianHigh = rates[j].high;
               if(rates[j].low < asianLow) asianLow = rates[j].low;
            }

            m_symMgr.UpdateAsianHighLow(i, asianHigh, asianLow);

            if(Inp_EnableTradeLogging)
               Print("Asian Range Updated: ", conf.symbol, " High=", DoubleToString(asianHigh, (int)SymbolInfoInteger(conf.symbol, SYMBOL_DIGITS)), " Low=", DoubleToString(asianLow, (int)SymbolInfoInteger(conf.symbol, SYMBOL_DIGITS)));
         }
         else if(Inp_EnableTradeLogging)
         {
            Print("⚠️ CEngine: CopyRates failed for ", conf.symbol, " (returned ", copied, ", err=", GetLastError(), "). Asian range skipped today.");
         }
      }
   }

   if(!m_riskMgr.CanEnterTrade()) return; // Risk guard blocks computation if daily breached

   int totalSymbols = m_symMgr.GetCount();
   string strStates[];
   ArrayResize(strStates, totalSymbols);

   for(int i = 0; i < totalSymbols; i++)
   {
      // v8.6.1: Pass symbol config by reference (not copy) for state persistence
      SSymbolConfig conf;
      if(!m_symMgr.GetSymbolRef(i, conf)) continue;

      // Update Cached Indicator State once per bar
      m_indMgr.UpdateIndicatorsOnBar(conf.symbol, conf.handleEMAFast, conf.handleEMAMid, conf.handleEMASlow, conf.handleEMAMacro, conf.handleADX, conf.handleATR, m_states[i]);

      // Manage Bar Exits (Divergence, logic drops)
      m_exec.ManageBarExits(m_riskMgr, m_states[i], conf.symbol);

      // C5: INSTITUTIONAL GUARD — Toxicity + Portfolio delta checks before ANY entry
      if(m_riskMgr.IsToxicMarket(conf.symbol))
      {
         strStates[i] = StringFormat("%s | ⚠ TOXIC MARKET", conf.symbol);
         m_symMgr.UpdateSymbolConfig(i, conf);
         continue;
      }

      // Evaluate Strategy Engine Entrances (Only if no position already open for this symbol)
      if(m_exec.IsPositionOpen(conf.symbol))
      {
         strStates[i] = StringFormat("%s | POS OPEN", conf.symbol);
         m_symMgr.UpdateSymbolConfig(i, conf);
         continue;
      }

      int dir = 0;
      // Feature 1: Scaling ATR (Position Sizing)
      // Calculate SL distance in pips based on Live ATR (x2 for safety margin).
      double atrPips = (m_states[i].liveATR_pips > 0) ? m_states[i].liveATR_pips : 50.0;
      double slDistancePips = atrPips * 2.0;

      // v9.1: Clamp SL distance above broker STOPS_LEVEL (+2 pip buffer) so the
      // entry SL survives broker validation AND the sizing math matches the SL
      // that's actually placed on the order. Without this, sizing assumes a
      // tighter SL than the broker allows, and positions run oversized.
      long   stopsLvl   = SymbolInfoInteger(conf.symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double point      = SymbolInfoDouble(conf.symbol, SYMBOL_POINT);
      double stopsPips  = m_exec.PriceToPips(conf.symbol, (double)stopsLvl * point);
      double minSLPips  = stopsPips + 2.0;
      if(slDistancePips < minSLPips) slDistancePips = minSLPips;

      double lotSize = m_riskMgr.CalculateLotSize(conf.symbol, slDistancePips);

      // v9.1: Pre-compute SL/TP pip offsets for all entry branches below.
      // Entry reference price is the current ask (BUY) / bid (SELL) for market
      // orders; limit-order branches substitute the limit price as entryPx.
      MqlTick entryTick;
      bool haveTick = SymbolInfoTick(conf.symbol, entryTick);
      double slPts   = m_exec.PipsToPrice(conf.symbol, slDistancePips);
      double tpPts   = m_exec.PipsToPrice(conf.symbol, slDistancePips * Inp_RiskRewardRatio);
      int    digits  = (int)SymbolInfoInteger(conf.symbol, SYMBOL_DIGITS);

      // v8.6.1: Asian Breakout with sweep+reclaim (pass config by ref + EMA Mid for quality filter)
      if(Inp_EnableAsianBreakout &&
         m_stratBreakout.EvaluateEntry(conf.symbol, conf.asianHigh, conf.asianLow,
                                         m_states[i].liveEMAMid, m_states[i].liveATR_pips,
                                         conf, dir))
      {
         if(!m_riskMgr.CanEnterTradeForSymbol(conf.symbol))
         {
            strStates[i] = StringFormat("%s | ⛔ PER-SYM CAP", conf.symbol);
         }
         else if(m_portfolioRisk.CanAddExposure(conf.symbol, dir, lotSize)) // C5: delta gate
         {
            Print("Breakout Entry → ", conf.symbol, " dir=", dir);
            if(Inp_UseLimitOrdersForBreakout)
            {
               double limitPrice = (dir == 1) ? conf.asianHigh + m_exec.PipsToPrice(conf.symbol, Inp_LimitBufferPips) : conf.asianLow - m_exec.PipsToPrice(conf.symbol, Inp_LimitBufferPips);
               double slLim = NormalizeDouble((dir == 1) ? limitPrice - slPts : limitPrice + slPts, digits);
               double tpLim = NormalizeDouble((dir == 1) ? limitPrice + tpPts : limitPrice - tpPts, digits);
               m_exec.ExecuteLimitOrder(conf.symbol, dir, lotSize, limitPrice, slLim, tpLim);
            }
            else if(haveTick)
            {
               double entryPx = (dir == 1) ? entryTick.ask : entryTick.bid;
               double slPx = NormalizeDouble((dir == 1) ? entryPx - slPts : entryPx + slPts, digits);
               double tpPx = NormalizeDouble((dir == 1) ? entryPx + tpPts : entryPx - tpPts, digits);
               m_exec.ExecuteMarketOrder(conf.symbol, dir, lotSize, slPx, tpPx);
            }
            m_riskMgr.IncrementTradesToday(conf.symbol);
         }
         else
         {
            strStates[i] = StringFormat("%s | ⛔ PORTFOLIO HEDGE LIMIT", conf.symbol);
         }
      }
      // v8.6.1: VWAP Reversion with sweep+reclaim (pass config by ref + EMA Mid for quality filter)
      else if(Inp_EnableVWAPReversion &&
              m_stratReversion.EvaluateEntry(conf.symbol, m_states[i].liveVWAP, m_states[i].liveATR_pips,
                                              m_states[i].liveEMAMid, conf, dir))
      {
         if(!m_riskMgr.CanEnterTradeForSymbol(conf.symbol))
         {
            strStates[i] = StringFormat("%s | ⛔ PER-SYM CAP", conf.symbol);
         }
         else if(m_portfolioRisk.CanAddExposure(conf.symbol, dir, lotSize))
         {
            Print("Reversion Entry → ", conf.symbol, " dir=", dir);
            if(haveTick)
            {
               double entryPx = (dir == 1) ? entryTick.ask : entryTick.bid;
               double slPx = NormalizeDouble((dir == 1) ? entryPx - slPts : entryPx + slPts, digits);
               double tpPx = NormalizeDouble((dir == 1) ? entryPx + tpPts : entryPx - tpPts, digits);
               m_exec.ExecuteMarketOrder(conf.symbol, dir, lotSize, slPx, tpPx);
            }
            m_riskMgr.IncrementTradesToday(conf.symbol);
         }
         else
         {
            strStates[i] = StringFormat("%s | ⛔ PORTFOLIO HEDGE LIMIT", conf.symbol);
         }
      }
      // v8.6.1: Volatility Momentum with ADX slope filter (pass adxPrevious for slope validation)
      else if(Inp_EnableVolatilityMom &&
              m_stratMomentum.EvaluateEntry(conf.symbol, m_states[i].liveADX, m_states[i].liveADXPrev,
                                             m_states[i].liveTrend, m_states[i].macroTrend,
                                             m_states[i].liveATR_pips, m_states[i].liveTickVolume, m_states[i].liveTickVolumeMA, dir))
      {
         if(!m_riskMgr.CanEnterTradeForSymbol(conf.symbol))
         {
            strStates[i] = StringFormat("%s | ⛔ PER-SYM CAP", conf.symbol);
         }
         else if(m_portfolioRisk.CanAddExposure(conf.symbol, dir, lotSize))
         {
            Print("Momentum Entry → ", conf.symbol, " dir=", dir);
            if(haveTick)
            {
               double entryPx = (dir == 1) ? entryTick.ask : entryTick.bid;
               double slPx = NormalizeDouble((dir == 1) ? entryPx - slPts : entryPx + slPts, digits);
               double tpPx = NormalizeDouble((dir == 1) ? entryPx + tpPts : entryPx - tpPts, digits);
               m_exec.ExecuteMarketOrder(conf.symbol, dir, lotSize, slPx, tpPx);
            }
            m_riskMgr.IncrementTradesToday(conf.symbol);
         }
         else
         {
            strStates[i] = StringFormat("%s | ⛔ PORTFOLIO HEDGE LIMIT", conf.symbol);
         }
      }

      // Write sweep state changes back to master symbol array (critical for multi-bar sweep+reclaim persistence)
      m_symMgr.UpdateSymbolConfig(i, conf);

      // Phase 2 Fix 2: Save sweep state to file (DISABLED - persistence disabled in OnInit)
      // if(m_sweepStateManager != NULL)
      // {
      //    m_sweepStateManager.SaveSymbolState(conf.symbol, conf);
      // }

      // Format Dashboard state
      string trendStr = (m_states[i].liveTrend == 1) ? "UP" : (m_states[i].liveTrend == -1) ? "DOWN" : "FLAT";
      strStates[i] = StringFormat("%s | Tr:%s | ADX:%.1f", conf.symbol, trendStr, m_states[i].liveADX);
   }
   
   m_dash.Draw(m_riskMgr, 0.0, m_riskMgr.GetTradesEnteredToday(), strStates);
}

void CEngine::CheckWeekendFlatten()
{
   // v9.1: Flat all positions before weekend close.
   // Why: Monday gap exposure (Trade #147 USOUSD lost $3,300 on a 67.83 → 67.24 gap).
   // MQL5: MqlDateTime.day_of_week — 0=Sun, 1=Mon, ... 5=Fri, 6=Sat.
   // Set Inp_FridayFlattenHour = -1 to disable (e.g. FX-only accounts).
   if(Inp_FridayFlattenHour < 0) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week != 5) return;
   if(dt.hour < Inp_FridayFlattenHour) return;

   // Cheap early-out: skip the position loop when flat.
   if(PositionsTotal() == 0) return;

   m_exec.CloseAllPositions("RULE_WeekendFlat", m_riskMgr);
}

void CEngine::CheckEODFlatten()
{
   // EOD Flat Logic (NY Close): Flatten all positions ~15 mins before NY close.
   // Typical NY Close is 16:00 EST / 17:00 EST depending on DST.
   // Assuming Server Time is typically GMT+2/3, NY Close is ~23:00 / 00:00 Server Time.
   // We flatten at hour 23, minute 45.

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // EOD flatten execution:
   if(dt.hour == 23 && dt.min >= 45)
   {
      // Fast path out
      if(PositionsTotal() == 0) return;

      m_exec.CloseAllPositions("RULE_EODFlat", m_riskMgr);
   }
}

void CEngine::OnTimer()
{
   // Refreshes portfolio delta cache once per second
   if(m_portfolioRisk != NULL) m_portfolioRisk.Refresh();
}

void CEngine::OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &req, const MqlTradeResult &res)
{
   // C1: Route all async fill confirmations into the execution layer for slippage tracking
   if(m_exec != NULL) m_exec.OnTransactionFill(trans);
}

void CEngine::OnDeinit(const int reason)
{
   EventKillTimer();

   // Phase 2 Fix 2: Final sweep state save and cleanup on shutdown
   if(m_sweepStateManager != NULL)
   {
      Print("Saving final sweep states before shutdown...");
      for(int i = 0; i < m_symMgr.GetCount(); i++)
      {
         SSymbolConfig cfg = m_symMgr.GetSymbol(i);
         
         m_sweepStateManager.SaveSymbolState(cfg.symbol, cfg);
      }
      Print("Cleaning up old state files...");
      m_sweepStateManager.ClearOldStates();
   }

   Print("CEngine: Graceful Shutdown.");
}

#endif
