//+------------------------------------------------------------------+
//|                                                PropFirm_EA.mq5 |
//|                                  Copyright 2024, Trading Systems |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Systems"
#property link      ""
#property version   "2.00"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Inputs
input double RiskPerTradePct = 0.5;         // Risk per trade (e.g. 0.5% of Equity)
input double TargetDailyProfitPct = 2.0;    // Aim daily profit of 1 - 3 %
input double MaxDailyLossPct = 2.0;         // Max daily loss -2%
input double MaxWeeklyLossPct = 5.0;        // Max weekly loss -5%
input int LondonOpenHour = 8;               // London Open (Server Time)
input int NYCloseHour = 17;                 // NY Close (Server Time)
input int MinutesBeforeNYClose = 15;        // Close All Trades before NY Session Close
input int NewsWindowMinutes = 30;           // No new Trades on News Event 30Min before and After

// Trade Management Settings
input int ATR_Period = 14;                  // ATR Period for Stop Loss Calculation
input double ATR_Multiplier = 1.5;          // ATR Multiplier for Stop Loss
input double RiskRewardRatio = 2.4;         // Take Profit = Risk * 2.4
input bool UseBreakEven = true;             // Move to Break Even at 1:1 RR
input bool UseTrailingStop = true;          // Enable Trailing Stop after 1:1

// Hardcoded Assets
string AssetsToTrade[] = {"GBPJPY", "US30", "USOIL", "XAUUSD", "DAX30", "NDAQ", "SPX500"};

// Variables for Drawdown tracking
double StartOfDayBalance = 0;
double StartOfWeekBalance = 0;

// Global Indicator Handles
int ATR_Handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("Prop Firm EA Initialized with Trade Execution.");
   StartOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   StartOfWeekBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Initialize ATR Handle once globally to prevent memory leaks/lag
   ATR_Handle = iATR(_Symbol, PERIOD_M15, ATR_Period);
   if(ATR_Handle == INVALID_HANDLE)
     {
      Print("Failed to initialize ATR indicator.");
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(ATR_Handle != INVALID_HANDLE) IndicatorRelease(ATR_Handle);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Check Drawdown Rules
   if(CheckDailyDrawdown() || CheckWeeklyDrawdown()) return;

   // 2. Manage EOD Closing (Run on every tick before session check)
   CloseBeforeNYSession();

   // 3. Check Session Rules (Time Filters)
   if(!IsTradingSession())
     {
      return;
     }

   // 4. News & Correlation Check
   if(IsNewsWindow(_Symbol) || !CheckCorrelation()) return;

   // 5. Manage Open Positions (Break-Even & Trailing Stops)
   ManageOpenPositions();

   // 6. Signal Evaluation for Current Symbol
   // Prevent opening more trades if we reached our concurrency limit
   if (!HasOpenPosition(_Symbol)) // Only 1 trade per symbol
     {
      int signal = EvaluateSignal(_Symbol);

      if(signal == 1) // Buy
        {
         ExecuteTrade(_Symbol, ORDER_TYPE_BUY);
        }
      else if (signal == -1) // Sell
        {
         ExecuteTrade(_Symbol, ORDER_TYPE_SELL);
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if Symbol has open position                                |
//+------------------------------------------------------------------+
bool HasOpenPosition(string symbol)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == symbol) return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Execute Trade with Risk Management                               |
//+------------------------------------------------------------------+
void ExecuteTrade(string symbol, ENUM_ORDER_TYPE orderType)
  {
   double atr_value = GetATR();
   if (atr_value == 0) return;

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   double stopLossDist = atr_value * ATR_Multiplier;
   double takeProfitDist = stopLossDist * RiskRewardRatio;

   double slPrice = 0;
   double tpPrice = 0;
   double entryPrice = 0;

   if (orderType == ORDER_TYPE_BUY)
     {
      entryPrice = ask;
      slPrice = entryPrice - stopLossDist;
      tpPrice = entryPrice + takeProfitDist;
     }
   else if (orderType == ORDER_TYPE_SELL)
     {
      entryPrice = bid;
      slPrice = entryPrice + stopLossDist;
      tpPrice = entryPrice - takeProfitDist;
     }

   // Calculate Lot Size based on Risk %
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (RiskPerTradePct / 100.0);

   // Convert SL distance to points/ticks
   double slTicks = stopLossDist / tickSize;
   double lotSize = NormalizeDouble(riskAmount / (slTicks * tickValue), 2);

   // Enforce Min/Max Lots
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if (lotSize < minLot) lotSize = minLot;
   if (lotSize > maxLot) lotSize = maxLot;

   PrintFormat("Opening %s trade on %s. Size: %.2f, SL: %.5f, TP: %.5f", EnumToString(orderType), symbol, lotSize, slPrice, tpPrice);

   if (orderType == ORDER_TYPE_BUY)
     {
      trade.Buy(lotSize, symbol, entryPrice, slPrice, tpPrice, "PropFirm Breakout");
     }
   else
     {
      trade.Sell(lotSize, symbol, entryPrice, slPrice, tpPrice, "PropFirm Breakout");
     }
  }

//+------------------------------------------------------------------+
//| Get ATR for Dynamic Stop Loss                                    |
//+------------------------------------------------------------------+
double GetATR()
  {
   if (ATR_Handle == INVALID_HANDLE) return 0.0;

   double atr_array[];
   if(CopyBuffer(ATR_Handle, 0, 0, 1, atr_array) <= 0)
     {
      Print("Error copying ATR buffer.");
      return 0.0;
     }

   return atr_array[0];
  }

//+------------------------------------------------------------------+
//| Manage Open Positions (Trailing Stop / Break Even)               |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double slPrice = PositionGetDouble(POSITION_SL);
      int type = (int)PositionGetInteger(POSITION_TYPE);

      double atr_value = GetATR();
      double riskAmount = atr_value * ATR_Multiplier;

      // Long Position Management
      if(type == POSITION_TYPE_BUY)
        {
         // Break-Even Logic (Price moved 1:1 in our favor)
         if(UseBreakEven && currentPrice >= (openPrice + riskAmount) && slPrice < openPrice)
           {
            Print("Moving Buy SL to Break-Even.");
            trade.PositionModify(ticket, openPrice, PositionGetDouble(POSITION_TP));
            continue; // Move to next position after modifying
           }

         // Trailing Stop Logic
         if(UseTrailingStop && currentPrice >= (openPrice + riskAmount))
           {
            double newSL = currentPrice - riskAmount;
            if(newSL > slPrice)
              {
               Print("Trailing Buy SL upwards.");
               trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
              }
           }
        }

      // Short Position Management
      if(type == POSITION_TYPE_SELL)
        {
         // Break-Even Logic
         if(UseBreakEven && currentPrice <= (openPrice - riskAmount) && (slPrice > openPrice || slPrice == 0))
           {
            Print("Moving Sell SL to Break-Even.");
            trade.PositionModify(ticket, openPrice, PositionGetDouble(POSITION_TP));
            continue;
           }

         // Trailing Stop Logic
         if(UseTrailingStop && currentPrice <= (openPrice - riskAmount))
           {
            double newSL = currentPrice + riskAmount;
            if(newSL < slPrice || slPrice == 0)
              {
               Print("Trailing Sell SL downwards.");
               trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check Daily Drawdown                                             |
//+------------------------------------------------------------------+
bool CheckDailyDrawdown()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   // Reset daily balance if a new day has started
   MqlDateTime dt;
   TimeCurrent(dt);
   static int lastDay = -1;
   if(dt.day != lastDay)
     {
      StartOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDay = dt.day;
     }

   double currentLossPct = (StartOfDayBalance - equity) / StartOfDayBalance * 100.0;

   if(currentLossPct >= MaxDailyLossPct)
     {
      PrintFormat("WARNING: Daily Max Loss (%.2f%%) Hit! Trading suspended for the day.", currentLossPct);
      CloseAllPositions();
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Check Weekly Drawdown                                            |
//+------------------------------------------------------------------+
bool CheckWeeklyDrawdown()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   MqlDateTime dt;
   TimeCurrent(dt);
   static int lastWeek = -1;
   // Reset at the start of a new week (e.g. Monday)
   if(dt.day_of_week == 1 && dt.day != lastWeek)
     {
      StartOfWeekBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastWeek = dt.day;
     }

   if (StartOfWeekBalance == 0) return false;

   double currentLossPct = (StartOfWeekBalance - equity) / StartOfWeekBalance * 100.0;

   if(currentLossPct >= MaxWeeklyLossPct)
     {
      PrintFormat("WARNING: Weekly Max Loss (%.2f%%) Hit! Trading suspended for the week.", currentLossPct);
      CloseAllPositions();
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Check Time/Session                                               |
//+------------------------------------------------------------------+
bool IsTradingSession()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   if (dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   if(dt.hour >= LondonOpenHour && dt.hour < NYCloseHour) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Close all trades 15 mins before NY Session                       |
//+------------------------------------------------------------------+
void CloseBeforeNYSession()
  {
   MqlDateTime dt;
   TimeCurrent(dt);

   if(dt.hour == NYCloseHour - 1 && dt.min >= (60 - MinutesBeforeNYClose))
     {
      if (PositionsTotal() > 0)
        {
         Print("Closing all open positions before NY Session closes...");
         CloseAllPositions();
        }
     }
  }

//+------------------------------------------------------------------+
//| Close All Open Positions Helper                                  |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      trade.PositionClose(ticket);
     }
  }

//+------------------------------------------------------------------+
//| News Filter (Using MT5 Built-in Economic Calendar API)           |
//+------------------------------------------------------------------+
bool IsNewsWindow(string symbol)
  {
   // Array to store calendar events
   MqlCalendarValue values[];

   // We look for events from 'NewsWindowMinutes' ago up to 'NewsWindowMinutes' in the future
   datetime currentTime = TimeCurrent();
   datetime startTime = currentTime - (NewsWindowMinutes * 60);
   datetime endTime = currentTime + (NewsWindowMinutes * 60);

   // We need to know which currency relates to the symbol (e.g., "USD" for "US30", "GBP" for "GBPJPY")
   // For simplicity, we fetch ALL country events here, but you should filter by 'currency' string
   // to reduce processing load in a real live environment.

   if(CalendarValueHistory(values, startTime, endTime))
     {
      for(int i = 0; i < ArraySize(values); i++)
        {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
           {
            // Check if the event is High Importance
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
              {
               PrintFormat("High Impact News detected! Event ID: %I64d at Time: %s", event.id, TimeToString(values[i].time));
               return true; // Block trading
              }
           }
        }
     }

   return false; // Safe to trade
  }

//+------------------------------------------------------------------+
//| Correlation / Concurrency Filter                                 |
//+------------------------------------------------------------------+
bool CheckCorrelation()
  {
   // Limit the maximum number of concurrent open trades across all assets
   // This acts as a proxy for our correlation and exposure risk filter.
   // MaxCorrelatedAssets is defined as an input.
   if (PositionsTotal() >= 4) // MaxCorrelatedAssets placeholder limit
     {
      return false; // Concurrency limit reached
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Signal Evaluation (Peak/Bottom Reversal/Continuation)            |
//+------------------------------------------------------------------+
int EvaluateSignal(string symbol)
  {
   double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);

   double highestPrice = iHigh(symbol, PERIOD_M15, iHighest(symbol, PERIOD_M15, MODE_HIGH, 20, 1));
   double lowestPrice = iLow(symbol, PERIOD_M15, iLowest(symbol, PERIOD_M15, MODE_LOW, 20, 1));

   // Breakout confirmation (Long)
   if(currentAsk >= highestPrice)
     {
      return 1; // Buy Signal
     }
   // Breakout confirmation (Short)
   if(currentBid <= lowestPrice)
     {
      return -1; // Sell Signal
     }

   return 0; // No signal
  }
