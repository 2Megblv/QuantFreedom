//+------------------------------------------------------------------+
//| QFisher_ARMI_TickVolume.mq5 |
//| True Tick-Volume ARMI + Fisher Transform |
//| Clean-room implementation for MT5 |
//+------------------------------------------------------------------+
#property indicator_separate_window
#property indicator_buffers 2
#property indicator_plots 1

#property indicator_label1 "QFisher_ARMI_TV"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrDeepSkyBlue
#property indicator_width1 2

input int Lookback = 14;

double FisherBuffer[];
double ArmiBuffer[];

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, FisherBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ArmiBuffer, INDICATOR_CALCULATIONS);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total <= Lookback + 1) return 0;

   int start = MathMax(prev_calculated - 1, Lookback);

   for(int i = start; i < rates_total; i++)
   {
      // --- TRUE tick-volume ARMI ---
      double upTV = 0.0;
      double downTV = 0.0;

      if(close[i] > open[i])
         upTV = (double)tick_volume[i];
      else if(close[i] < open[i])
         downTV = (double)tick_volume[i];

      double armi = 0.0;
      if((upTV + downTV) > 0.0)
         armi = (upTV - downTV) / (upTV + downTV);

      ArmiBuffer[i] = armi;

      // --- rolling min/max of ARMI ---
      double minA = armi;
      double maxA = armi;

      for(int j = i - Lookback + 1; j <= i; j++)
      {
         minA = MathMin(minA, ArmiBuffer[j]);
         maxA = MathMax(maxA, ArmiBuffer[j]);
      }

      // --- normalize ---
      double x = 0.0;
      if(maxA != minA)
         x = 2.0 * (armi - minA) / (maxA - minA) - 1.0;

      x = MathMax(-0.999, MathMin(0.999, x));

      // --- Fisher Transform ---
      double f = 0.5 * MathLog((1.0 + x) / (1.0 - x));

      if(i == 0)
         FisherBuffer[i] = f;
      else
         FisherBuffer[i] = 0.33 * f + 0.67 * FisherBuffer[i - 1];
   }

   return rates_total;
}
//+------------------------------------------------------------------+
