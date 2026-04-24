//+------------------------------------------------------------------+
//|                                                jMathFx_EA.mq5    |
//|                                   Institutional HFT Architecture |
//+------------------------------------------------------------------+
#property copyright "jMathFx System"
#property link      ""
#property version   "1.00"

#include <Zmq/Zmq.mqh>

input string   InpZmqContext = "jMathFx_Ctx";
input string   InpPushUrl    = "tcp://127.0.0.1:5555"; // MT5 PUSHES tick data to Python PULL
input string   InpPullUrl    = "tcp://127.0.0.1:5556"; // MT5 PULLS commands from Python PUSH

Context *ctx = NULL;
Socket *pushSocket = NULL; // Sends Data
Socket *pullSocket = NULL; // Receives Commands

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Initializing jMathFx ZeroMQ Bridge...");

   ctx = new Context(InpZmqContext);

   pushSocket = new Socket(*ctx, ZMQ_PUSH);
   pullSocket = new Socket(*ctx, ZMQ_PULL);

   if(!pushSocket.connect(InpPushUrl)) {
      Print("Failed to connect PUSH socket to ", InpPushUrl);
      return INIT_FAILED;
   }

   if(!pullSocket.connect(InpPullUrl)) {
      Print("Failed to connect PULL socket to ", InpPullUrl);
      return INIT_FAILED;
   }

   // Create millisecond timer to check for execution commands continuously
   EventSetMillisecondTimer(10);

   Print("jMathFx Bridge Connected.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   if (pushSocket != NULL) delete pushSocket;
   if (pullSocket != NULL) delete pullSocket;
   if (ctx != NULL) delete ctx;

   Print("jMathFx Bridge Disconnected.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlTick last_tick;
   if(SymbolInfoTick(_Symbol, last_tick))
   {
      string payload = "TICK|" + DoubleToString(last_tick.bid, _Digits) + "|" + DoubleToString(last_tick.ask, _Digits);

      // Determine if a new bar has opened (Volume == 1) based on user specification
      long tick_volume = iTickVolume(_Symbol, PERIOD_CURRENT, 0);

      if(tick_volume == 1)
      {
         // New bar! The previous bar has just closed, so we send the previous bar's data.
         double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
         double low = iLow(_Symbol, PERIOD_CURRENT, 1);
         double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
         double close = iClose(_Symbol, PERIOD_CURRENT, 1);

         payload += "|BAR|" + DoubleToString(high, _Digits) + "|" + DoubleToString(low, _Digits) + "|" + DoubleToString(open, _Digits) + "|" + DoubleToString(close, _Digits);
      }

      // Send data to Python Engine
      pushSocket.send(payload, ZMQ_NOBLOCK);
   }
}

//+------------------------------------------------------------------+
//| Timer function for processing ZMQ Execution Commands             |
//+------------------------------------------------------------------+
void OnTimer()
{
   string command;
   int received = pullSocket.recv(command, ZMQ_NOBLOCK);

   if (received > 0 && StringLen(command) > 0)
   {
      ProcessCommand(command);
   }
}

//+------------------------------------------------------------------+
//| Process incoming execution commands                              |
//+------------------------------------------------------------------+
void ProcessCommand(string cmd)
{
   // Format: TRADE|OPEN|BUY|EURUSD|1.1050
   // Format: TRADE|CLOSE_ALL|EURUSD

   string sep = "|";
   ushort u_sep = StringGetCharacter(sep, 0);
   string parts[];

   int num_parts = StringSplit(cmd, u_sep, parts);

   if (num_parts >= 3 && parts[0] == "TRADE")
   {
      string action = parts[1];

      if (action == "OPEN")
      {
         string direction = parts[2];
         string symbol = parts[3];
         // Logic to execute order via OrderSend / CTrade
         Print("EXECUTE OPEN ", direction, " for ", symbol);
      }
      else if (action == "CLOSE_ALL")
      {
         string symbol = parts[2];
         // Logic to close all positions for symbol
         Print("EXECUTE CLOSE_ALL for ", symbol);
      }
   }
}
