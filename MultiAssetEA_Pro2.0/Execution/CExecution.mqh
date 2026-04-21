#ifndef GUARD_C_EXECUTION
#define GUARD_C_EXECUTION

#property strict

#include <MultiAssetEA_Pro2.0/Core/CGlobalInputs.mqh>
#include <MultiAssetEA_Pro2.0/Core/CMemoryMonitor.mqh>
#include <MultiAssetEA_Pro2.0/Risk/CRiskManager.mqh>
#include <MultiAssetEA_Pro2.0/Indicators/CIndicatorManager.mqh>

// Order tracking structure for atomic execution validation and exit management
struct SOrderRecord
{
   int               ticket;           // Broker ticket from OrderSend
   string            symbol;           // Trading symbol
   double            intendedPrice;    // Price when order was placed
   long              timestamp;        // Time order was placed
   int               attempts;         // Number of placement attempts
   bool              reconciled;       // True if confirmed exists in broker
   bool              tp50Taken;        // True after RULE8 TP50 partial close fired once
   bool              tp75Taken;        // True after RULE8 TP75 partial close fired once
};

class CExecution
{
private:
   // Async tracking: maps request IDs to symbols for OnTradeTransaction
   ulong             m_asyncReqIds[];
   string            m_asyncSymbols[];
   double            m_asyncIntendedPrices[];
   int               m_asyncCount;

   // Order reconciliation tracking (Phase 1 fix for FR-1)
   SOrderRecord      m_orderRecords[];
   int               m_orderCount;

   // Phase 2 Fix 4: Memory monitoring for array capacity tracking
   CMemoryMonitor*   m_memMonitor;

   void              RegisterAsyncRequest(ulong reqId, string symbol, double intendedPrice);
   void              ClosePositionPartial(ulong ticket, double volume, ENUM_POSITION_TYPE type, string symbol, string reason, CRiskManager* pRiskMgr);

   // Helper functions for error handling (Phase 1 FR-1 fix)
   bool              IsRetryableError(int error);
   bool              ReconcileOrderPlacement(int ticket, string symbol, double intendedPrice);
   void              TrackOrderRecord(int ticket, string symbol, double intendedPrice);

   // TP level state: returns record index, creating a minimal record if not found
   // (covers positions that existed before EA start or after reconnect)
   int               FindOrAddTPRecord(ulong ticket, string symbol);

public:
   double            PipSize(string symbol);
   double            PriceToPips(string symbol, double priceDistance);
   double            PipsToPrice(string symbol, double pips);

   CExecution();
   ~CExecution();

   // Entry execution
   bool              ExecuteMarketOrder(string symbol, int direction, double lotSize, double sl, double tp);
   bool              ExecuteMarketOrderAsync(string symbol, int direction, double lotSize, double sl, double tp);
   bool              IcebergMarketOrder(string symbol, int direction, double totalLots, double sl, double tp);
   bool              ExecuteLimitOrder(string symbol, int direction, double lotSize, double price, double sl, double tp);
   
   // OnTradeTransaction callback — call this from main EA OnTradeTransaction()
   void              OnTransactionFill(const MqlTradeTransaction &trans);
   
   // Exit management
   void              ManageTickExits(CRiskManager* pRiskMgr, SIndicatorState &states[]);
   void              ManageBarExits(CRiskManager* pRiskMgr, SIndicatorState &indState, string symbol);
   bool              IsPositionOpen(string symbol);
   void              CloseAllPositions(string reason, CRiskManager* pRiskMgr);
   void              ManageNewsPositions(CRiskManager* pRiskMgr);
   
   // Phase 2 Fix 4: Memory monitoring
   CMemoryMonitor*   GetMemoryMonitor() { return m_memMonitor; }
   string            GetMemoryStatus() { return (m_memMonitor != NULL) ? m_memMonitor.GetCapacityStatus() : "N/A"; }
};

//+------------------------------------------------------------------+
//| Implementation                                                   |
//+------------------------------------------------------------------+
CExecution::CExecution()
{
   m_asyncCount = 0;
   m_orderCount = 0;
   ArrayResize(m_asyncReqIds, 0);
   ArrayResize(m_asyncSymbols, 0);
   ArrayResize(m_asyncIntendedPrices, 0);
   ArrayResize(m_orderRecords, 0);
   
   // Phase 2 Fix 4: Initialize memory monitor
   m_memMonitor = new CMemoryMonitor();
   Print("✓ CExecution: Memory monitor initialized");
}

// Phase 1 FR-1 fix: Explicit cleanup on EA deinit to prevent memory leaks and stale async requests
CExecution::~CExecution()
{
   // Clear all async tracking arrays
   ArrayFree(m_asyncReqIds);
   ArrayFree(m_asyncSymbols);
   ArrayResize(m_asyncIntendedPrices, 0);
   m_asyncCount = 0;

   // Clear all order records
   ArrayFree(m_orderRecords);
   m_orderCount = 0;
   
   // Phase 2 Fix 4: Cleanup memory monitor
   if(m_memMonitor != NULL)
   {
      m_memMonitor.LogStatus();
      delete m_memMonitor;
      m_memMonitor = NULL;
   }
}

//+------------------------------------------------------------------+
//| Phase 1 FR-1 Helper Functions: Atomic Order Execution             |
//+------------------------------------------------------------------+

// Check if an error code is retryable (network/broker busy) vs permanent
bool CExecution::IsRetryableError(int error)
{
   // Permanent errors that should NOT be retried
   if(error == TRADE_RETCODE_NO_MONEY) return false;                // Permanent
   if(error == TRADE_RETCODE_INVALID_PRICE) return false;           // Permanent
   if(error == TRADE_RETCODE_INVALID_VOLUME) return false;          // Permanent
   if(error == TRADE_RETCODE_MARKET_CLOSED) return false;           // Permanent
   if(error == TRADE_RETCODE_INVALID_STOPS) return false;           // Permanent
   if(error == TRADE_RETCODE_TRADE_DISABLED) return false;          // Permanent

   // Transient/retryable errors
   if(error == TRADE_RETCODE_TIMEOUT) return true;
   if(error == TRADE_RETCODE_REQUOTE) return true;
   if(error == TRADE_RETCODE_REJECT) return true;
   if(error == TRADE_RETCODE_CANCEL) return true;

   return true;  // Default: assume retryable for safety
}

// Verify order was actually executed in broker.
// CRITICAL FIX: OrderSelect() only queries the PENDING orders pool.
// TRADE_ACTION_DEAL fills synchronously — by the time this runs, the order
// is already in the POSITIONS pool (open) or HISTORY (closed by TP/SL immediately).
// Must check positions first, then history, before declaring failure.
bool CExecution::ReconcileOrderPlacement(int ticket, string symbol, double intendedPrice)
{
   if(ticket <= 0) return false;

   // ── Check 1: Position pool (normal case — market order is open) ──
   if(PositionSelectByTicket((ulong)ticket))
   {
      if((long)PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber)
      {
         Print("❌ RECONCILE FAIL [", symbol, "]: Ticket ", ticket, " magic mismatch (position)");
         return false;
      }
      if(PositionGetString(POSITION_SYMBOL) != symbol)
      {
         Print("❌ RECONCILE FAIL [", symbol, "]: Ticket ", ticket, " symbol mismatch (position)");
         return false;
      }
      Print("✅ RECONCILE SUCCESS [", symbol, "]: Ticket ", ticket, " confirmed as open position");
      return true;
   }

   // ── Check 2: Order history (rare case — position hit TP/SL before this call) ──
   if(HistoryOrderSelect((ulong)ticket))
   {
      if((long)HistoryOrderGetInteger(ticket, ORDER_MAGIC) != Inp_MagicNumber)
      {
         Print("❌ RECONCILE FAIL [", symbol, "]: Ticket ", ticket, " magic mismatch (history)");
         return false;
      }
      if(HistoryOrderGetString(ticket, ORDER_SYMBOL) != symbol)
      {
         Print("❌ RECONCILE FAIL [", symbol, "]: Ticket ", ticket, " symbol mismatch (history)");
         return false;
      }
      Print("✅ RECONCILE SUCCESS [", symbol, "]: Ticket ", ticket, " confirmed in order history");
      return true;
   }

   // ── Check 3: Pending orders pool (limit/stop orders not yet filled) ──
   if(OrderSelect((ulong)ticket))
   {
      if((long)OrderGetInteger(ORDER_MAGIC) != Inp_MagicNumber)
      {
         Print("❌ RECONCILE FAIL [", symbol, "]: Ticket ", ticket, " magic mismatch (pending)");
         return false;
      }
      if(OrderGetString(ORDER_SYMBOL) != symbol)
      {
         Print("❌ RECONCILE FAIL [", symbol, "]: Ticket ", ticket, " symbol mismatch (pending)");
         return false;
      }
      Print("✅ RECONCILE SUCCESS [", symbol, "]: Ticket ", ticket, " confirmed as pending order");
      return true;
   }

   Print("❌ RECONCILE FAIL [", symbol, "]: Ticket ", ticket, " not found in positions, history, or pending pool");
   return false;
}

// Track order with reconciliation status for later validation
void CExecution::TrackOrderRecord(int ticket, string symbol, double intendedPrice)
{
   if(ticket <= 0) return;

   ArrayResize(m_orderRecords, m_orderCount + 1);
   m_orderRecords[m_orderCount].ticket        = ticket;
   m_orderRecords[m_orderCount].symbol        = symbol;
   m_orderRecords[m_orderCount].intendedPrice = intendedPrice;
   m_orderRecords[m_orderCount].timestamp     = TimeCurrent();
   m_orderRecords[m_orderCount].attempts      = 1;
   m_orderRecords[m_orderCount].reconciled    = false;
   m_orderRecords[m_orderCount].tp50Taken     = false;
   m_orderRecords[m_orderCount].tp75Taken     = false;
   m_orderCount++;
}

// Return the m_orderRecords index for a ticket.
// Creates a minimal record if not found — covers positions open before EA start
// or after reconnect where in-memory records were lost.
int CExecution::FindOrAddTPRecord(ulong ticket, string symbol)
{
   int iticket = (int)ticket;
   for(int i = 0; i < m_orderCount; i++)
      if(m_orderRecords[i].ticket == iticket) return i;

   // Not in records — create on-the-fly so TP flags can be tracked from now on
   ArrayResize(m_orderRecords, m_orderCount + 1);
   m_orderRecords[m_orderCount].ticket        = iticket;
   m_orderRecords[m_orderCount].symbol        = symbol;
   m_orderRecords[m_orderCount].intendedPrice = 0.0;
   m_orderRecords[m_orderCount].timestamp     = TimeCurrent();
   m_orderRecords[m_orderCount].attempts      = 0;
   m_orderRecords[m_orderCount].reconciled    = true;   // position is open — assume valid
   m_orderRecords[m_orderCount].tp50Taken     = false;
   m_orderRecords[m_orderCount].tp75Taken     = false;
   m_orderCount++;
   return m_orderCount - 1;
}

//+------------------------------------------------------------------+
//| Utility Functions                                                 |
//+------------------------------------------------------------------+

double CExecution::PipSize(string symbol)
{
   if(StringFind(symbol, "XAU") >= 0) return 0.1;
   if(StringFind(symbol, "USO") >= 0) return 0.01;
   if(StringFind(symbol, "JPY") >= 0) return 0.01;
   if(StringFind(symbol, "SPX") >= 0 || StringFind(symbol, "NAS") >= 0 || StringFind(symbol, "D30") >= 0) return 1.0; 
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits == 5 || digits == 3) return point * 10.0;
   return point;
}

double CExecution::PriceToPips(string symbol, double priceDistance) 
{ 
   double ps = PipSize(symbol); 
   return (ps <= 0.0) ? 0.0 : priceDistance / ps; 
}

double CExecution::PipsToPrice(string symbol, double pips) 
{ 
   return pips * PipSize(symbol); 
}

//--- Synchronous with atomic execution and reconciliation (Phase 1 FR-1 fix)
bool CExecution::ExecuteMarketOrder(string symbol, int direction, double lotSize, double sl, double tp)
{
   if(lotSize > Inp_IcebergThreshold) return IcebergMarketOrder(symbol, direction, lotSize, sl, tp);

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick)) return false;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req); ZeroMemory(res);

   req.action        = TRADE_ACTION_DEAL;
   req.symbol        = symbol;
   req.volume        = lotSize;
   req.type          = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price         = (direction == 1) ? tick.ask : tick.bid;
   req.sl            = sl;
   req.tp            = tp;
   req.magic         = Inp_MagicNumber;
   req.type_filling  = ORDER_FILLING_IOC;
   req.deviation     = 20;

   // Phase 1 FR-1: Atomic order execution with retry logic
   const int MAX_RETRIES = 3;
   int attempts = 0;

   while(attempts < MAX_RETRIES)
   {
      bool sent = OrderSend(req, res);

      if(sent && res.order > 0)
      {
         // FR-1 FIX: Verify order exists in broker using OrderGetTicket()
         if(ReconcileOrderPlacement((int)res.order, symbol, req.price))
         {
            TrackOrderRecord((int)res.order, symbol, req.price);
            Print("✅ SYNC FILL [", symbol, "]: ", DoubleToString(req.price, 5), " Vol: ", lotSize);
            return true;  // Success: order placed AND verified
         }
         else
         {
            Print("⚠️ SYNC RECONCILE FAILED [", symbol, "]: Placed but not verified, retrying");
            attempts++;
            Sleep(100);
            continue;
         }
      }

      // FR-1 FIX: Check if error is retryable
      int error = GetLastError();
      if(!IsRetryableError(error))
      {
         Print("❌ SYNC FAIL [", symbol, "]: Non-retryable error: ", error);
         return false;
      }

      attempts++;
      if(attempts < MAX_RETRIES)
      {
         Print("⚠️ SYNC RETRY [", symbol, "]: Attempt ", attempts, " of ", MAX_RETRIES);
         Sleep(100);
      }
   }

   Print("❌ SYNC FAIL [", symbol, "]: Failed after ", MAX_RETRIES, " attempts");
   return false;
}

//--- C1: Async single clip (Phase 1 FR-1 fix: track with reconciliation)
bool CExecution::ExecuteMarketOrderAsync(string symbol, int direction, double lotSize, double sl, double tp)
{
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick)) return false;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req); ZeroMemory(res);

   req.action        = TRADE_ACTION_DEAL;
   req.symbol        = symbol;
   req.volume        = lotSize;
   req.type          = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price         = (direction == 1) ? tick.ask : tick.bid;
   req.sl            = sl;
   req.tp            = tp;
   req.magic         = Inp_MagicNumber;
   req.type_filling  = ORDER_FILLING_IOC;
   req.deviation     = 20;

   bool sent = OrderSendAsync(req, res);
   if(sent && res.order > 0)
   {
      // FR-1 FIX: Track async request and validate in OnTransactionFill
      RegisterAsyncRequest(res.order, symbol, req.price);
      TrackOrderRecord((int)res.order, symbol, req.price);
   }
   return sent;
}

//--- C2: Iceberg slicer — breaks large orders into clips to avoid sweeping liquidity
bool CExecution::IcebergMarketOrder(string symbol, int direction, double totalLots, double sl, double tp)
{
   double remaining  = totalLots;
   bool   allFired   = true;
   
   while(remaining > 0.0001)
   {
      double clip = MathMin(remaining, Inp_IcebergClipSize);
      clip = NormalizeDouble(clip, 2);
      if(clip <= 0.0) break;
      
      if(!ExecuteMarketOrderAsync(symbol, direction, clip, sl, tp)) allFired = false;
      remaining -= clip;
      if(remaining > 0.0001) Sleep(Inp_IcebergDelayMs); // Brief pause between clips
   }
   return allFired;
}

void CExecution::RegisterAsyncRequest(ulong reqId, string symbol, double intendedPrice)
{
   ArrayResize(m_asyncReqIds, m_asyncCount + 1);
   ArrayResize(m_asyncSymbols, m_asyncCount + 1);
   ArrayResize(m_asyncIntendedPrices, m_asyncCount + 1);
   m_asyncReqIds[m_asyncCount]         = reqId;
   m_asyncSymbols[m_asyncCount]        = symbol;
   m_asyncIntendedPrices[m_asyncCount] = intendedPrice;
   m_asyncCount++;
   
   // Phase 2 Fix 4: Track memory allocation
   if(m_memMonitor != NULL)
   {
      m_memMonitor.TrackAllocation(m_asyncCount);
   }
}

//--- OnTradeTransaction fill confirmation mapper (Phase 1 FR-1: mark as reconciled)
void CExecution::OnTransactionFill(const MqlTradeTransaction &trans)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong orderId = trans.order;
   for(int i = 0; i < m_asyncCount; i++)
   {
      if(m_asyncReqIds[i] == orderId)
      {
         string sym    = m_asyncSymbols[i];
         double intended = m_asyncIntendedPrices[i];
         double fillPrice = trans.price;
         double slippagePips = MathAbs(fillPrice - intended) / (SymbolInfoDouble(sym, SYMBOL_POINT) * 10.0);

         if(slippagePips > Inp_MaxSlippagePips)
            Print("⚠️ ASYNC FILL SLIPPAGE [", sym, "]: ", DoubleToString(slippagePips, 1), " pips (max=" , Inp_MaxSlippagePips, ")");
         else
            Print("✅ ASYNC FILL [", sym, "]: ", DoubleToString(fillPrice, 5), " slip=", DoubleToString(slippagePips,1), " pips");

         // FR-1 FIX: Mark order as reconciled in m_orderRecords
         for(int k = 0; k < m_orderCount; k++)
         {
            if(m_orderRecords[k].ticket == (int)orderId)
            {
               m_orderRecords[k].reconciled = true;
               break;
            }
         }

         // Compact array after processing
         for(int j = i; j < m_asyncCount - 1; j++)
         {
            m_asyncReqIds[j]          = m_asyncReqIds[j+1];
            m_asyncSymbols[j]         = m_asyncSymbols[j+1];
            m_asyncIntendedPrices[j]  = m_asyncIntendedPrices[j+1];
         }
         m_asyncCount--;
         ArrayResize(m_asyncReqIds, m_asyncCount);
         ArrayResize(m_asyncSymbols, m_asyncCount);
         ArrayResize(m_asyncIntendedPrices, m_asyncCount);
         return;
      }
   }
}

bool CExecution::IsPositionOpen(string symbol)
{
   // 1. Check open positions
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) == symbol) return true;
   }
   
   // 2. Check pending MT5 orders (Limit/Stop)
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0 || !OrderSelect(ticket)) continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != Inp_MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) == symbol) return true;
   }
   
   // 3. Check async requests currently in-flight to the broker
   for(int i = 0; i < m_asyncCount; i++)
   {
      if(m_asyncSymbols[i] == symbol) return true;
   }
   
   return false;
}

bool CExecution::ExecuteLimitOrder(string symbol, int direction, double lotSize, double price, double sl, double tp)
{
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   
   req.action = TRADE_ACTION_PENDING;
   req.symbol = symbol;
   req.volume = lotSize;
   req.type = (direction == 1) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   req.price = price;
   req.sl = sl;
   req.tp = tp;
   req.magic = Inp_MagicNumber;
   req.type_filling = ORDER_FILLING_RETURN;
   
   return OrderSend(req, res);
}

void CExecution::ClosePositionPartial(ulong ticket, double volume, ENUM_POSITION_TYPE type, string symbol, string reason, CRiskManager* pRiskMgr)
{
   if(ticket <= 0 || volume <= 0) return;

   // Block execution attempts if the symbol is off-session to prevent log floods of "Market closed"
   if(!SymbolInfoInteger(symbol, SYMBOL_SESSION_DEALS)) return;

   double positionProfit = 0.0;
   double fullVolume     = 0.0;
   if(PositionSelectByTicket(ticket))
   {
      positionProfit = PositionGetDouble(POSITION_PROFIT);
      fullVolume     = PositionGetDouble(POSITION_VOLUME);
   }
   else return;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick)) return;

   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);

   req.action = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol = symbol;
   req.volume = volume;
   req.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
   req.magic = Inp_MagicNumber;
   req.type_filling = ORDER_FILLING_IOC;
   req.deviation = 20;
   req.comment = reason;

   bool sendResult = OrderSend(req, res);
   if(sendResult)
   {
      // Bug fix: record only the proportional P&L for the slice being closed.
      // POSITION_PROFIT is the full open position P&L — for a partial close of
      // 50% of a $500-profit position, only $250 is realised.
      // Over-recording inflates daily profit tracking and can trigger the SFX
      // profit-target cutoff prematurely.
      if(positionProfit != 0.0 && fullVolume > 0.0 && pRiskMgr != NULL)
      {
         double proportionalProfit = positionProfit * (volume / fullVolume);
         pRiskMgr.RecordDailyProfit(proportionalProfit);
         Print("CLOSE: ", symbol, " ", reason,
               " Vol: ", volume, "/", fullVolume,
               " Profit: ", proportionalProfit, " (of ", positionProfit, " total)");
      }
      else
         Print("CLOSE: ", symbol, " ", reason, " Profit: ", positionProfit);
   }
   else
   {
      int err = GetLastError();
      // ERR_MARKET_CLOSED (10018) should skip noisily logging
      if(err != 10018 && err != 4756)
      {
         // ERR_INVALID_VOLUME (4751) or ERR_INVALID_STOPS (4756)
         // Volume errors happen if close slice volume is invalid.
         // Often partial close percentages yield volumes that don't match the broker's SYMBOL_VOLUME_STEP.
         // Error 4756 occurs frequently if modifying a close while market has just moved.
         Print("⚠️ ERROR closing partial volume ", volume, " for ", symbol, ": ", err);
      }
   }
}

void CExecution::CloseAllPositions(string reason, CRiskManager* pRiskMgr)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      ClosePositionPartial(ticket, vol, type, symbol, reason, pRiskMgr);
   }
}

//--- PER TICK EXITS (Time critical)
void CExecution::ManageTickExits(CRiskManager* pRiskMgr, SIndicatorState &states[])
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;
      
      string symbol = PositionGetString(POSITION_SYMBOL);

      // Verify symbol is trading before trying to run trailing stops or market closes
      // Prevents "Market closed" API errors and slowness off-hours
      if(!SymbolInfoInteger(symbol, SYMBOL_SESSION_DEALS)) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double vol = PositionGetDouble(POSITION_VOLUME);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      
      int secondsOpen = (int)(TimeCurrent() - openTime);
      bool tooFreshToExit = (secondsOpen < 300);
      
      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick))
      {
         if(Inp_EnableTradeLogging)
            Print("⚠️ CExecution: SymbolInfoTick failed for ", symbol, " err=", GetLastError());
         continue;
      }

      // RULE 2: Daily Loss Guard
      if(Inp_Rule2_DailyLossLimitEnabled && pRiskMgr != NULL && pRiskMgr.IsDailyLossLimitExceeded())
      {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit <= 0 || !Inp_Rule2_CloseOnlyLosers)
         {
            ClosePositionPartial(ticket, vol, type, symbol, "RULE2_DailyLoss", pRiskMgr);
            continue;
         }
      }
      
      // RULE 6: Timeout (Time Based)
      if(Inp_Rule6_TimeBasedExitEnabled && secondsOpen > Inp_Rule6_MaxTimeOpen_Seconds)
      {
         ClosePositionPartial(ticket, vol, type, symbol, "RULE6_TimeOut", pRiskMgr);
         continue;
      }
      
      // RULE 8: Partial TP
      if(Inp_Rule8_PartialTPEnabled && tp > 0.0)
      {
         double tpDistance = MathAbs(tp - entry);
         double tp50 = (type == POSITION_TYPE_BUY) ? entry + tpDistance * 0.5 : entry - tpDistance * 0.5;
         double tp75 = (type == POSITION_TYPE_BUY) ? entry + tpDistance * 0.75 : entry - tpDistance * 0.75;
         
         bool hitTP75 = (type == POSITION_TYPE_BUY && tick.bid >= tp75) || (type == POSITION_TYPE_SELL && tick.ask <= tp75);
         bool hitTP50 = (type == POSITION_TYPE_BUY && tick.bid >= tp50) || (type == POSITION_TYPE_SELL && tick.ask <= tp50);

         // Bug fix: guard with per-position flags so each TP level fires exactly once.
         // Without flags, every tick at TP75 would close another slice of the position.
         int recIdx = FindOrAddTPRecord(ticket, symbol);

         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

         if(hitTP75 && !m_orderRecords[recIdx].tp75Taken)
         {
            double pct = MathMin(100.0, MathMax(0.0, Inp_Rule8_SecondTP_Pct));
            double closeVol = NormalizeDouble(vol * (pct / 100.0), 2);
            closeVol = MathRound(closeVol / stepLot) * stepLot; // Align to broker step

            if(closeVol >= minLot && closeVol <= vol) // Cannot close less than minimum allowed by broker
            {
               ClosePositionPartial(ticket, closeVol, type, symbol, "RULE8_TP75", pRiskMgr);
               m_orderRecords[recIdx].tp75Taken = true;
            }
         }
         else if(hitTP50 && !m_orderRecords[recIdx].tp50Taken)
         {
            double pct = MathMin(100.0, MathMax(0.0, Inp_Rule8_FirstTP_Pct));
            double closeVol = NormalizeDouble(vol * (pct / 100.0), 2);
            closeVol = MathRound(closeVol / stepLot) * stepLot; // Align to broker step

            if(closeVol >= minLot && closeVol <= vol)
            {
               ClosePositionPartial(ticket, closeVol, type, symbol, "RULE8_TP50", pRiskMgr);
               m_orderRecords[recIdx].tp50Taken = true;
            }
         }
      }
      
      // RULE 10: Trailing Stops — ATR-adaptive with pip floor
      // trail = max(TrailBase_Pips, liveATR_pips × ATRMultiplier); floor prevents
      // absurdly-tight trails on quiet bars when ATR collapses.
      if(Inp_Rule10_TrailingStopEnabled)
      {
         double profitPips = (type == POSITION_TYPE_BUY) ? PriceToPips(symbol, tick.bid - entry) : PriceToPips(symbol, entry - tick.ask);

         if(profitPips > Inp_Rule10_ProfitThreshold_Pips)
         {
            double atrPips = Inp_Rule10_TrailBase_Pips;   // fallback to floor
            int atrHandle = iATR(symbol, PERIOD_M15, 14);
            if(atrHandle != INVALID_HANDLE)
            {
               double atrArr[1];
               if(CopyBuffer(atrHandle, 0, 0, 1, atrArr) == 1 && atrArr[0] > 0.0)
                  atrPips = PriceToPips(symbol, atrArr[0]);
            }

            // v9.3: Advanced EOD Locking
            // If we are within the EOD Block Entry window, apply a hyper-aggressive
            // trailing stop so we lock out max profits before NY close.
            MqlDateTime dt_lock;
            TimeToStruct(TimeCurrent(), dt_lock);
            int minutesFromMidnight = (23 - dt_lock.hour) * 60 + (60 - dt_lock.min);

            double appliedATRMultiplier = Inp_Rule10_ATRMultiplier;
            if(minutesFromMidnight <= Inp_EODBlockEntryMinutes)
            {
               // Hyper aggressive ATR
               appliedATRMultiplier = Inp_EODTightTrail_ATR;
            }

            double trailPips = MathMax(Inp_Rule10_TrailBase_Pips, atrPips * appliedATRMultiplier);
            double trailDist = PipsToPrice(symbol, trailPips);
            int    digits    = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            double newSL = (type == POSITION_TYPE_BUY) ? NormalizeDouble(tick.bid - trailDist, digits) : NormalizeDouble(tick.ask + trailDist, digits);

            // v9.1: Broker STOPS_LEVEL clamp. When newSL lands inside the broker's
            // minimum stop distance (10–50 pips on FX, often 100+ on commodities),
            // TRADE_ACTION_SLTP returns retcode 10016 and the SL is never tightened.
            // Clamp newSL outside stopsLevel so the modify always succeeds.
            long   stopsLvl   = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double point      = SymbolInfoDouble(symbol, SYMBOL_POINT);
            double minDistPts = (double)stopsLvl * point;
            if(minDistPts > 0.0)
            {
               if(type == POSITION_TYPE_BUY)  newSL = MathMin(newSL, NormalizeDouble(tick.bid - minDistPts, digits));
               else                           newSL = MathMax(newSL, NormalizeDouble(tick.ask + minDistPts, digits));
            }

            bool modify = false;
            if(newSL > 0.0)
            {
               if(type == POSITION_TYPE_BUY  && (sl == 0.0 || newSL > sl)) modify = true;
               if(type == POSITION_TYPE_SELL && (sl == 0.0 || newSL < sl)) modify = true;
               if(MathAbs(sl - newSL) < 0.00001) modify = false;
            }
            if(modify)
            {
               MqlTradeRequest req; MqlTradeResult res;
               ZeroMemory(req); ZeroMemory(res);
               req.action = TRADE_ACTION_SLTP;
               req.symbol = symbol; req.position = ticket; req.sl = newSL; req.tp = tp;

               double freezeLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
               bool isValid = true;
               if(type == POSITION_TYPE_BUY && newSL >= tick.bid - freezeLevel - minDistPts) isValid = false;
               if(type == POSITION_TYPE_SELL && newSL <= tick.ask + freezeLevel + minDistPts) isValid = false;

               if(isValid)
               {
                  if(!OrderSend(req, res) || res.retcode != TRADE_RETCODE_DONE)
                     Print("⚠️ Trailing Stop Modify [", symbol, "] retcode=", res.retcode, " err=", GetLastError(), " newSL=", newSL);
               }
            }
         }
      }
      
      // RULE 11: TP-PROXIMITY TIGHTENING (Lock-in before reversal)
      if(Inp_Rule11_TPTightenEnabled && tp > 0.0)
      {
         double totalDist = MathAbs(tp - entry);
         double currentDist = (type == POSITION_TYPE_BUY) ? (tick.bid - entry) : (entry - tick.ask);
         double progressPct = (totalDist > 0) ? (currentDist / totalDist) * 100.0 : 0;
         
         if(progressPct >= Inp_Rule11_Trigger_Pct)
         {
            double lockLevel = (type == POSITION_TYPE_BUY) ? NormalizeDouble(entry + PipsToPrice(symbol, Inp_Rule11_LockedProfit_Pips), 5) : NormalizeDouble(entry - PipsToPrice(symbol, Inp_Rule11_LockedProfit_Pips), 5);
            
            // v9.2: Apply STOPS_LEVEL clamp to lockLevel (same as newSL for Rule 10)
            long   stopsLvlR11   = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double pointR11      = SymbolInfoDouble(symbol, SYMBOL_POINT);
            double minDistPtsR11 = (double)stopsLvlR11 * pointR11;
            int    digitsR11     = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            if(minDistPtsR11 > 0.0)
            {
               if(type == POSITION_TYPE_BUY)  lockLevel = MathMin(lockLevel, NormalizeDouble(tick.bid - minDistPtsR11, digitsR11));
               else                           lockLevel = MathMax(lockLevel, NormalizeDouble(tick.ask + minDistPtsR11, digitsR11));
            }
            
            bool modify = false;
            // Prevent attempting modifications if the target lockLevel is already applied or worse than current SL
            if(type == POSITION_TYPE_BUY && (sl == 0.0 || lockLevel > sl + pointR11)) modify = true;
            if(type == POSITION_TYPE_SELL && (sl == 0.0 || lockLevel < sl - pointR11)) modify = true;
            
            if(modify)
            {
               MqlTradeRequest req; MqlTradeResult res;
               ZeroMemory(req); ZeroMemory(res);
               req.action = TRADE_ACTION_SLTP;
               req.symbol = symbol; req.position = ticket; req.sl = lockLevel; req.tp = tp;

               // Avoid invalid stops error by re-verifying stops vs current ask/bid
               double freezeLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL) * pointR11;
               bool isValid = true;
               if(type == POSITION_TYPE_BUY && lockLevel >= tick.bid - freezeLevel - minDistPtsR11) isValid = false;
               if(type == POSITION_TYPE_SELL && lockLevel <= tick.ask + freezeLevel + minDistPtsR11) isValid = false;

               if(isValid)
               {
                  if(!OrderSend(req, res))
                  {
                     int err = GetLastError();
                     // 4756 = ERR_TRADE_SEND_FAILED (often due to no change in SL/TP or too close to market)
                     if(err != 4756) Print("⚠️ RULE11: TP-Prox Locked Profit Error: ", err);
                  }
                  else Print("🔒 RULE11: TP-Prox Lock-in [", symbol, "] Level: ", lockLevel);
               }
            }
         }
      }
   }
}

//--- PER BAR EXITS (Logic critical)
void CExecution::ManageBarExits(CRiskManager* pRiskMgr, SIndicatorState &indState, string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int secondsOpen = (int)(TimeCurrent() - openTime);
      
      if(secondsOpen < 300) continue; // Skip fresh trades
      
      // RULE 4: Momentum Divergence
      if(Inp_Rule4_MomentumDivergenceEnabled)
      {
         if(indState.liveADX < Inp_Rule4_ADXDecliningThreshold && indState.liveADX < indState.liveADXPrev)
         {
            double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

            double pct = MathMin(100.0, MathMax(0.0, Inp_Rule4_PartialClose_Pct));
            double closeVol = NormalizeDouble(vol * (pct / 100.0), 2);
            closeVol = MathRound(closeVol / stepLot) * stepLot; // Align to broker step

            if(closeVol >= minLot && closeVol <= vol)
            {
               ClosePositionPartial(ticket, closeVol, type, symbol, "RULE4_Divergence", pRiskMgr);
            }
         }
      }
   }
}

void CExecution::ManageNewsPositions(CRiskManager* pRiskMgr)
{
   // Implement news-based logic here if needed
}

#endif
