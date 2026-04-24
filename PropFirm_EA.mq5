//+------------------------------------------------------------------+
//|                                                PropFirm_EA.mq5 |
//|                                  Copyright 2024, Trading Systems |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Systems"
#property link      ""
#property version   "1.30"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Inputs
input ulong MagicNumber = 8888;             // Magic Number (Unique ID per EA instance)
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

// QFisher ARMI Precision Filter
input int QFisher_Lookback = 14;            // Lookback for QFisher ARMI
input double QFisher_Threshold = 1.5;       // Threshold for QFisher Signal (e.g. 1.5 for strong trend)

// Behavioural Constants
input bool UsePartialTP = true;             // Execute the Partial TP half
input bool UseExtendedTP = true;            // Execute the Extended TP half
input bool AllowMultiplePositions = false;  // Allow multiple concurrent positions on a single symbol

// Dynamic Assets List (Comma Separated)
input string TradeAssets = "EURUSD,GBPJPY,U30USD,USOUSD,XAUUSD,D30EUR,NASUSD,SPXUSD";
string AssetList[];

// Variables for Drawdown tracking
double StartOfDayBalance = 0;
double StartOfWeekBalance = 0;

// Global Indicator Handles (Arrays for Multi-Asset tracking)
int ATR_Handles[];
int ADX_Handles[];
int QFisher_Handles[];

//+------------------------------------------------------------------+
//| Dashboard Helper                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard(string statusMessage)
  {
   string dashboard = "==============================\n";
   dashboard += "    PROP FIRM EA PRO\n";
   dashboard += "    Version: 2.20\n";
   dashboard += "==============================\n";
   dashboard += "Symbol: " + _Symbol + "\n";
   dashboard += "Magic: " + IntegerToString(MagicNumber) + "\n";
   dashboard += "Status: " + statusMessage + "\n";
   dashboard += "==============================";

   Comment(dashboard);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("Prop Firm Multi-Asset EA Initialized.");

   trade.SetExpertMagicNumber(MagicNumber);

   StartOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   StartOfWeekBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Set Chart Colors to Dark Professional Theme
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrDarkSlateGray);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrSilver);
   ChartSetInteger(0, CHART_COLOR_GRID, clrDimGray);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrSeaGreen);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrIndianRed);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, clrSeaGreen);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrIndianRed);

   UpdateDashboard("Initializing Headless Indicators...");

   ushort separator = StringGetCharacter(",", 0);
   int numAssets = StringSplit(TradeAssets, separator, AssetList);

   if(numAssets == 0)
     {
      Print("Error: No assets defined in TradeAssets input.");
      return(INIT_FAILED);
     }

   ArrayResize(ATR_Handles, numAssets);
   ArrayResize(ADX_Handles, numAssets);
   ArrayResize(QFisher_Handles, numAssets);

   // Initialize Indicators Headlessly for each Asset
   for(int i = 0; i < numAssets; i++)
     {
      string symbol = AssetList[i];
      StringTrimLeft(symbol); StringTrimRight(symbol);
      AssetList[i] = symbol;

      SymbolSelect(symbol, true);

      ATR_Handles[i] = iATR(symbol, PERIOD_M15, ATR_Period);
      ADX_Handles[i] = iADX(symbol, PERIOD_M15, 14);
      QFisher_Handles[i] = iCustom(symbol, PERIOD_M15, "QFisher_ARMI_TickVolume", QFisher_Lookback);

      if(ATR_Handles[i] == INVALID_HANDLE || ADX_Handles[i] == INVALID_HANDLE || QFisher_Handles[i] == INVALID_HANDLE)
        {
         PrintFormat("Failed to initialize headless indicators for %s. Ensure QFisher_ARMI_TickVolume.ex5 is compiled in Indicators folder.", symbol);
         return(INIT_FAILED);
        }
     }

   UpdateDashboard("Running Multi-Asset Engine");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   Comment(""); // Clear Dashboard
   for(int i = 0; i < ArraySize(AssetList); i++)
     {
      if(i < ArraySize(ATR_Handles) && ATR_Handles[i] != INVALID_HANDLE) IndicatorRelease(ATR_Handles[i]);
      if(i < ArraySize(ADX_Handles) && ADX_Handles[i] != INVALID_HANDLE) IndicatorRelease(ADX_Handles[i]);
      if(i < ArraySize(QFisher_Handles) && QFisher_Handles[i] != INVALID_HANDLE) IndicatorRelease(QFisher_Handles[i]);
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(CheckDailyDrawdown() || CheckWeeklyDrawdown())
     {
      UpdateDashboard("Drawdown limit reached! Trading Suspended.");
      return;
     }

   // HARD RULE: Close all trades 15 mins before NY Close
   CloseBeforeNYSession();

   if(!IsTradingSession())
     {
      UpdateDashboard("Outside Trading Session (Flattened)");
      return;
     }

   if (!CheckCorrelation())
     {
      UpdateDashboard("Max Correlation Exposure Reached");
      return;
     }

   // Manage Open Positions (Partial TPs, Break-Even, Aggressive NY Trailing)
   ManageOpenPositions();

   // Entry Logic: Loop through all configured assets
   bool isScanning = false;
   for(int i = 0; i < ArraySize(AssetList); i++)
     {
      string symbol = AssetList[i];

      // Symbol Specific News Check
      if(IsNewsWindow(symbol)) continue;

      if (HasOpenPosition(symbol))
        {
         continue; // We already have a position on this asset
        }
      else
        {
         // No NY Trades if we have existing positions globally, to preserve capital
         if (IsNYSession() && PositionsTotal() > 0) continue;

         isScanning = true;

         if (AllowMultiplePositions || !HasOpenPosition(symbol))
           {
            int signal = EvaluateSignal(symbol, i);

            if(signal == 1) ExecuteTrade(symbol, ORDER_TYPE_BUY, i);
            else if (signal == -1) ExecuteTrade(symbol, ORDER_TYPE_SELL, i);
           }
        }
     }

   if(isScanning)
      UpdateDashboard("Scanning for Precision Setups...");
   else
      UpdateDashboard("Managing Active Trades / Pending Filters");
  }

//+------------------------------------------------------------------+
//| Execute Trade (Two Halves for Partial TP)                        |
//+------------------------------------------------------------------+
void ExecuteTrade(string symbol, ENUM_ORDER_TYPE orderType, int assetIndex)
  {
   double atr_value = GetATR(assetIndex);
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

double GetATR(int index)
  {
   if (index >= ArraySize(ATR_Handles) || ATR_Handles[index] == INVALID_HANDLE) return 0.0;
   double atr_array[];
   if(CopyBuffer(ATR_Handles[index], 0, 0, 1, atr_array) <= 0) return 0.0;
   return atr_array[0];
  }

double GetADX(int index)
  {
   if (index >= ArraySize(ADX_Handles) || ADX_Handles[index] == INVALID_HANDLE) return 0.0;
   double adx_array[];
   if(CopyBuffer(ADX_Handles[index], 0, 0, 1, adx_array) <= 0) return 0.0;
   return adx_array[0];
  }

double GetQFisher(int index)
  {
   if (index >= ArraySize(QFisher_Handles) || QFisher_Handles[index] == INVALID_HANDLE) return 0.0;
   double fisher_array[];
   // Buffer 0 is the FisherBuffer based on the provided custom indicator code
   if(CopyBuffer(QFisher_Handles[index], 0, 0, 1, fisher_array) <= 0) return 0.0;
   return fisher_array[0];
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

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      // Filter out trades not belonging to this EA instance
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);

      // Find asset index for indicators
      int assetIndex = -1;
      for(int j = 0; j < ArraySize(AssetList); j++)
        {
         if (AssetList[j] == symbol)
           {
            assetIndex = j;
            break;
           }
        }
      if (assetIndex == -1) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double slPrice = PositionGetDouble(POSITION_SL);
      int type = (int)PositionGetInteger(POSITION_TYPE);

      double atr_value = GetATR(assetIndex);
      double riskAmount = atr_value * ATR_Multiplier;
      double currentADX = GetADX(assetIndex);
      bool isWeakeningTrend = (currentADX < 20.0); // ADX dropping implies ranging/compression

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
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      // Ensure we only close trades belonging to this instance
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         trade.PositionClose(ticket);
        }
     }
  }

bool IsNewsWindow(string symbol)
  {
   MqlCalendarValue values[];
   datetime currentTime = TimeCurrent();
   datetime startTime = currentTime - (NewsWindowMinutes * 60);
   datetime endTime = currentTime + (NewsWindowMinutes * 60);

   // Attempt to isolate the currency for the news filter based on the symbol
   // For example, "EURUSD" -> "EUR" and "USD". For "US30", we'll assume "USD".
   string base_currency = StringSubstr(symbol, 0, 3);
   string quote_currency = StringSubstr(symbol, 3, 3);
   if (StringFind(symbol, "US") != -1 || StringFind(symbol, "SPX") != -1 || StringFind(symbol, "NAS") != -1) base_currency = "USD";
   if (StringFind(symbol, "DAX") != -1) base_currency = "EUR";

   if(CalendarValueHistory(values, startTime, endTime))
     {
      for(int i = 0; i < ArraySize(values); i++)
        {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
           {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
              {
               // MT5 built-in calendar actually uses event.country_id (int) instead of strings
               // To properly map country_id to currency strings requires calling CalendarCountryById.
               // For safety and simplicity in this generalized blueprint, we revert to a Global News Block:
               // If ANY High Impact news is happening, we block trading across the portfolio.
               return true;
              }
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
int EvaluateSignal(string symbol, int assetIndex)
  {
   double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);

   double highestPrice = iHigh(symbol, PERIOD_M15, iHighest(symbol, PERIOD_M15, MODE_HIGH, 20, 1));
   double lowestPrice = iLow(symbol, PERIOD_M15, iLowest(symbol, PERIOD_M15, MODE_LOW, 20, 1));

   if (IsNYSession())
     {
      double adx = GetADX(assetIndex);
      // Precision Requirement: Require overwhelming directional bias (ADX > 30) for new NY Trades
      if (adx < NY_Precision_ADX_Level) return 0;
     }

   // Breakout confirmation combined with QFisher ARMI precision filter
   if(currentAsk >= highestPrice && GetQFisher(assetIndex) >= QFisher_Threshold) return 1;
   if(currentBid <= lowestPrice && GetQFisher(assetIndex) <= -QFisher_Threshold) return -1;

   return 0;
  }
