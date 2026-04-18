//+------------------------------------------------------------------+
//|                                                PropFirm_EA.mq5 |
//|                                  Copyright 2024, Trading Systems |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Systems"
#property link      ""
#property version   "1.10"

//--- Inputs
input double RiskPerTradePct = 0.5;         // Risk per trade (e.g. 0.5% of Equity)
input double TargetDailyProfitPct = 2.0;    // Aim daily profit of 1 - 3 %
input double MaxDailyLossPct = 2.0;         // Max daily loss -2%
input double MaxWeeklyLossPct = 5.0;        // Max weekly loss -5%
input int LondonOpenHour = 8;               // London Open (Server Time)
input int NYCloseHour = 17;                 // NY Close (Server Time)
input int MinutesBeforeNYClose = 15;        // Close All Trades before NY Session Close

// Trade Management Settings
input int ATR_Period = 14;                  // ATR Period for Stop Loss Calculation
input double ATR_Multiplier = 1.5;          // ATR Multiplier for Stop Loss
input double RiskRewardRatio = 2.4;         // Take Profit = Risk * 2.4
input bool UseBreakEven = true;             // Move to Break Even at 1:1 RR
input bool UseTrailingStop = true;          // Enable Trailing Stop after 1:1

// Hardcoded Assets
string AssetsToTrade[] = {"GBPJPY", "US30", "USOIL", "XAUUSD", "DAX30", "NDAQ", "SPX500"};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("Prop Firm EA Initialized with Advanced Trade Management.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Check Drawdown Rules
   if(CheckDailyDrawdown() || CheckWeeklyDrawdown()) return;

   // 2. Check Session Rules (Time Filters)
   if(!IsTradingSession())
     {
      CloseBeforeNYSession();
      return;
     }

   // 3. News & Correlation Check
   if(IsNewsWindow() || !CheckCorrelation()) return;

   // 4. Manage Open Positions (Break-Even & Trailing Stops)
   ManageOpenPositions();

   // 5. Signal Evaluation for Current Symbol
   int signal = EvaluateSignal(_Symbol);

   if(signal == 1) // Buy
     {
      double atr_value = GetATR(_Symbol);
      double stopLoss = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - (atr_value * ATR_Multiplier);
      double takeProfit = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + ((atr_value * ATR_Multiplier) * RiskRewardRatio);

      PrintFormat("Buy Signal! Calculated SL: %f, TP: %f (ATR Based)", stopLoss, takeProfit);
      // Placeholder: OrderSend(Buy)
     }
  }

//+------------------------------------------------------------------+
//| Get ATR for Dynamic Stop Loss                                    |
//+------------------------------------------------------------------+
double GetATR(string symbol)
  {
   double atr_array[];
   int atr_handle = iATR(symbol, PERIOD_M15, ATR_Period);
   CopyBuffer(atr_handle, 0, 0, 1, atr_array);
   IndicatorRelease(atr_handle); // Prevent memory leak
   return atr_array[0];
  }

//+------------------------------------------------------------------+
//| Manage Open Positions (Trailing Stop / Break Even)               |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   // Loop through all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double slPrice = PositionGetDouble(POSITION_SL);
      int type = (int)PositionGetInteger(POSITION_TYPE);

      double atr_value = GetATR(symbol);
      double riskAmount = atr_value * ATR_Multiplier;

      // Long Position Management
      if(type == POSITION_TYPE_BUY)
        {
         // Break-Even Logic (Price moved 1:1 in our favor)
         if(UseBreakEven && currentPrice >= openPrice + riskAmount && slPrice < openPrice)
           {
            Print("Moving SL to Break-Even.");
            // Placeholder: Modify Position SL to (openPrice + Commission)
           }

         // Trailing Stop Logic
         if(UseTrailingStop && currentPrice >= openPrice + riskAmount)
           {
            double newSL = currentPrice - (atr_value * ATR_Multiplier);
            if(newSL > slPrice)
              {
               Print("Trailing SL upwards.");
               // Placeholder: Modify Position SL to newSL
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
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentLossPct = (balance - equity) / balance * 100.0;

   if(currentLossPct >= MaxDailyLossPct) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Check Weekly Drawdown                                            |
//+------------------------------------------------------------------+
bool CheckWeeklyDrawdown() { return false; } // Placeholder

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

void CloseBeforeNYSession() { /* Placeholder: Close all positions */ }
bool IsNewsWindow() { return false; } // Placeholder: API call needed
bool CheckCorrelation() { return true; } // Placeholder

//+------------------------------------------------------------------+
//| Signal Evaluation (Peak/Bottom Reversal/Continuation)            |
//+------------------------------------------------------------------+
int EvaluateSignal(string symbol)
  {
   double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
   double highestPrice = iHigh(symbol, PERIOD_M15, iHighest(symbol, PERIOD_M15, MODE_HIGH, 20, 1));

   // Breakout confirmation
   if(currentPrice >= highestPrice)
     {
      return 1; // Buy Signal
     }
   return 0; // No signal
  }
