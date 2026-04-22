//+------------------------------------------------------------------+
//|                                                PropFirm_EA.mq5 |
//|                                  Copyright 2024, Trading Systems |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Systems"
#property link      ""
#property version   "3.00"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Inputs
input double RiskPerTradePct = 0.5;         // Risk per trade (e.g. 0.5% of Equity)
input double MaxDailyLossPct = 2.0;         // Max daily loss -2%
input double MaxWeeklyLossPct = 5.0;        // Max weekly loss -5%

// Session Times
input int AsianOpenHour = 17;               // Asian Open
input int NYOpenHour = 17;                  // NY Open
input int NYCloseHour = 15;                 // NY Close
input int MinutesBeforeNYClose = 2;         // Hard Rule: Close before NY close
input int AggressiveTrailHoursBeforeClose = 2; // Aggressive trailing kicks in 2 hours before close
input int NewsWindowMinutes = 30;           // No new Trades on News Event 30Min before and After

// Trade Management Settings
input int ATR_Period = 13;
input double ATR_Multiplier = 1.38;         // Initial SL
input double PartialTakeProfitRR = 1.50;    // 50% TP distance
input double ExtendedTakeProfitRR = 12.48;  // Extended TP for the remaining 50%
input double NY_Precision_ADX_Level = 30.0; // >= 80% Confidence Level required for NY Entries

// Behavioural Constants
input bool UsePartialTP = true;             // Execute the Partial TP half
input bool UseExtendedTP = true;            // Execute the Extended TP half
input bool AllowMultiplePositions = false;  // Allow multiple concurrent positions on a single symbol

// Hardcoded Assets
string AssetsToTrade[] = {"GBPJPY", "US30", "USOIL", "XAUUSD", "DAX30", "NDAQ", "SPX500"};

// Variables for Drawdown tracking
double StartOfDayBalance = 0;
double StartOfWeekBalance = 0;

// Global Indicator Handles
int ATR_Handle = INVALID_HANDLE;
int ADX_Handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("Prop Firm EA Initialized with NY Session Capital Preservation Logic.");
   StartOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   StartOfWeekBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   ATR_Handle = iATR(_Symbol, PERIOD_M15, ATR_Period);
   ADX_Handle = iADX(_Symbol, PERIOD_M15, 14);

   if(ATR_Handle == INVALID_HANDLE || ADX_Handle == INVALID_HANDLE)
     {
      Print("Failed to initialize indicators.");
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(ATR_Handle != INVALID_HANDLE) IndicatorRelease(ATR_Handle);
   if(ADX_Handle != INVALID_HANDLE) IndicatorRelease(ADX_Handle);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(CheckDailyDrawdown() || CheckWeeklyDrawdown()) return;

   // HARD RULE: Close all trades 15 mins before NY Close
   CloseBeforeNYSession();

   if(!IsTradingSession()) return;

   if(IsNewsWindow(_Symbol) || !CheckCorrelation()) return;

   // Manage Open Positions (Partial TPs, Break-Even, Aggressive NY Trailing)
   ManageOpenPositions();

   // Entry Logic
   if (AllowMultiplePositions || !HasOpenPosition(_Symbol))
     {
      // No NY Trades if we have existing positions globally, to preserve capital
      if (IsNYSession() && PositionsTotal() > 0) return;

      int signal = EvaluateSignal(_Symbol);

      if(signal == 1) ExecuteTrade(_Symbol, ORDER_TYPE_BUY);
      else if (signal == -1) ExecuteTrade(_Symbol, ORDER_TYPE_SELL);
     }
  }

//+------------------------------------------------------------------+
//| Execute Trade (Two Halves for Partial TP)                        |
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

   // Calculate Lot Size based on Total Risk %
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (RiskPerTradePct / 100.0);
   double slTicks = stopLossDist / tickSize;
   double totalLotSize = NormalizeDouble(riskAmount / (slTicks * tickValue), 2);

   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   if (totalLotSize < minLot * 2) return; // Cannot split trade into 2 halves if too small

   // Split into two equal halves
   double halfLot = NormalizeDouble(totalLotSize / 2.0, 2);

   double entryPrice = (orderType == ORDER_TYPE_BUY) ? ask : bid;
   double slPrice = (orderType == ORDER_TYPE_BUY) ? entryPrice - stopLossDist : entryPrice + stopLossDist;

   // Half 1: Partial TP
   double partialTpPrice = (orderType == ORDER_TYPE_BUY) ? entryPrice + (stopLossDist * PartialTakeProfitRR) : entryPrice - (stopLossDist * PartialTakeProfitRR);
   // Half 2: Extended Trend TP
   double extendedTpPrice = (orderType == ORDER_TYPE_BUY) ? entryPrice + (stopLossDist * ExtendedTakeProfitRR) : entryPrice - (stopLossDist * ExtendedTakeProfitRR);

   // Execute halves based on Behavioural Constants
   if (orderType == ORDER_TYPE_BUY)
     {
      if (UsePartialTP) trade.Buy(halfLot, symbol, entryPrice, slPrice, partialTpPrice, "Asian/London Partial");
      if (UseExtendedTP) trade.Buy(halfLot, symbol, entryPrice, slPrice, extendedTpPrice, "Trend Runner");
     }
   else
     {
      if (UsePartialTP) trade.Sell(halfLot, symbol, entryPrice, slPrice, partialTpPrice, "Asian/London Partial");
      if (UseExtendedTP) trade.Sell(halfLot, symbol, entryPrice, slPrice, extendedTpPrice, "Trend Runner");
     }
  }

double GetATR()
  {
   if (ATR_Handle == INVALID_HANDLE) return 0.0;
   double atr_array[];
   if(CopyBuffer(ATR_Handle, 0, 0, 1, atr_array) <= 0) return 0.0;
   return atr_array[0];
  }

double GetADX()
  {
   if (ADX_Handle == INVALID_HANDLE) return 0.0;
   double adx_array[];
   if(CopyBuffer(ADX_Handle, 0, 0, 1, adx_array) <= 0) return 0.0;
   return adx_array[0];
  }

//+------------------------------------------------------------------+
//| Manage Open Positions (Aggressive NY Risk Control)               |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   MqlDateTime dt;
   TimeCurrent(dt);

   // Check if we are in the last 2 hours of the NY session
   bool isAggressiveNYClose = (dt.hour >= (NYCloseHour - AggressiveTrailHoursBeforeClose));
   double currentADX = GetADX();
   bool isWeakeningTrend = (currentADX < 20.0); // ADX dropping implies ranging/compression

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

      // Aggressive Pre-Close Risk Control
      if (isAggressiveNYClose && isWeakeningTrend)
        {
         // Apply aggressive 0.5x ATR trailing stop to preserve gains
         double aggressiveTrailDist = atr_value * 0.5;

         if (type == POSITION_TYPE_BUY)
           {
            double newSL = currentPrice - aggressiveTrailDist;
            if (newSL > slPrice) trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
           }
         else if (type == POSITION_TYPE_SELL)
           {
            double newSL = currentPrice + aggressiveTrailDist;
            if (newSL < slPrice || slPrice == 0) trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
           }
         continue;
        }

      // Standard Trade Runner Logic (Post Partial TP)
      // Moving to BE + standard trail if extended trade is in deep profit
      if(type == POSITION_TYPE_BUY)
        {
         if(currentPrice >= (openPrice + riskAmount * PartialTakeProfitRR) && slPrice < openPrice)
           {
            trade.PositionModify(ticket, openPrice, PositionGetDouble(POSITION_TP)); // Move to BE
           }
        }
      if(type == POSITION_TYPE_SELL)
        {
         if(currentPrice <= (openPrice - riskAmount * PartialTakeProfitRR) && (slPrice > openPrice || slPrice == 0))
           {
            trade.PositionModify(ticket, openPrice, PositionGetDouble(POSITION_TP)); // Move to BE
           }
        }
     }
  }

//+------------------------------------------------------------------+
bool CheckDailyDrawdown()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
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
      CloseAllPositions();
      return true;
     }
   return false;
  }

bool CheckWeeklyDrawdown()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime dt;
   TimeCurrent(dt);
   static int lastWeek = -1;
   if(dt.day_of_week == 1 && dt.day != lastWeek)
     {
      StartOfWeekBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastWeek = dt.day;
     }
   if (StartOfWeekBalance == 0) return false;

   double currentLossPct = (StartOfWeekBalance - equity) / StartOfWeekBalance * 100.0;
   if(currentLossPct >= MaxWeeklyLossPct)
     {
      CloseAllPositions();
      return true;
     }
   return false;
  }

bool IsTradingSession()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   if (dt.day_of_week == 0 || dt.day_of_week == 6) return false;

   // Check for midnight crossover
   bool isSessionActive = false;
   if (AsianOpenHour < NYCloseHour)
     {
      isSessionActive = (dt.hour >= AsianOpenHour && dt.hour < NYCloseHour);
     }
   else
     {
      isSessionActive = (dt.hour >= AsianOpenHour || dt.hour < NYCloseHour);
     }

   if (!isSessionActive) return false;

   // If we are inside the liquidation window, DO NOT allow new trades
   int liquidationHour = NYCloseHour - 1;
   if (liquidationHour < 0) liquidationHour = 23;

   if(dt.hour == liquidationHour && dt.min >= (60 - MinutesBeforeNYClose)) return false;

   return true;
  }

bool IsNYSession()
  {
   MqlDateTime dt;
   TimeCurrent(dt);

   if (NYOpenHour < NYCloseHour)
     {
      return (dt.hour >= NYOpenHour && dt.hour < NYCloseHour);
     }
   else
     {
      return (dt.hour >= NYOpenHour || dt.hour < NYCloseHour);
     }
  }

void CloseBeforeNYSession()
  {
   MqlDateTime dt;
   TimeCurrent(dt);

   int liquidationHour = NYCloseHour - 1;
   if (liquidationHour < 0) liquidationHour = 23;

   if(dt.hour == liquidationHour && dt.min >= (60 - MinutesBeforeNYClose))
     {
      if (PositionsTotal() > 0)
        {
         Print("HARD RULE: Closing all positions 15 mins before NY Session closes.");
         CloseAllPositions();
        }
     }
  }

void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--) trade.PositionClose(PositionGetTicket(i));
  }

bool IsNewsWindow(string symbol)
  {
   MqlCalendarValue values[];
   datetime currentTime = TimeCurrent();
   datetime startTime = currentTime - (NewsWindowMinutes * 60);
   datetime endTime = currentTime + (NewsWindowMinutes * 60);

   if(CalendarValueHistory(values, startTime, endTime))
     {
      for(int i = 0; i < ArraySize(values); i++)
        {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
           {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH) return true;
           }
        }
     }
   return false;
  }

bool CheckCorrelation()
  {
   if (PositionsTotal() >= 4) return false;
   return true;
  }

bool HasOpenPosition(string symbol)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == symbol) return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Signal Evaluation (Precision Breakout)                           |
//+------------------------------------------------------------------+
int EvaluateSignal(string symbol)
  {
   double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);

   double highestPrice = iHigh(symbol, PERIOD_M15, iHighest(symbol, PERIOD_M15, MODE_HIGH, 20, 1));
   double lowestPrice = iLow(symbol, PERIOD_M15, iLowest(symbol, PERIOD_M15, MODE_LOW, 20, 1));

   if (IsNYSession())
     {
      double adx = GetADX();
      // Precision Requirement: Require overwhelming directional bias (ADX > 30) for new NY Trades
      if (adx < NY_Precision_ADX_Level) return 0;
     }

   if(currentAsk >= highestPrice) return 1;
   if(currentBid <= lowestPrice) return -1;

   return 0;
  }
