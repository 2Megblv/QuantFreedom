//+------------------------------------------------------------------+
//|                                             CGlobalInputs.mqh    |
//|  v9.0.0 — 2026.04.17                                            |
//|  All EA input parameters. Defensible first-principles defaults   |
//|  after Rank 3 optimizer artifact purge. All exit-rule percentage |
//|  and multiplier defaults are within sane ranges; walk-forward    |
//|  re-optimization must respect the bounds enforced by             |
//|  CEngine::ValidateInputs().                                      |
//+------------------------------------------------------------------+
#ifndef C_GLOBAL_INPUTS_MQH
#define C_GLOBAL_INPUTS_MQH
#property strict

input group "════════ MASTER SETTINGS ════════"
input int      Inp_MagicNumber                    = 20250122; // Master Magic Number (v9.2: Multi-instance config)
                                                                // IMPORTANT: Each EA instance on SAME account MUST use UNIQUE magic
                                                                // Example: Chart1=20250122, Chart2=20250123, Chart3=20250124
                                                                // Risk: Identical magic numbers → order conflicts if 2+ instances active
input string   Inp_EngineSymbols                  = "EURUSD,GBPUSD,XAUUSD,USDJPY,D30EUR,NASUSD,SPXUSD,USOUSD"; // Specific broker symbol mapping

input group "════════ OPTIMIZATION TRICK (Check to START) ════════"
input int      Inp_DummyOptimization              = 1;        // Range:1, Step:1, Stop:2 (MT5 UI workaround)

input group "════════ ACCOUNT & RISK (OOP) - SFX $250K ════════"
input double   Inp_RiskPerTradePct                = 1.0;      // SFX: 1.0% risk = $2,500 per trade
input double   Inp_DailyMaxLossPct                = -3.0;     // SFX: 3% daily limit = $7,500 loss max
input bool     Inp_EnableDailyLossLimit           = true;     // SFX: ENFORCE daily limit
input double   Inp_DailyProfitTargetPct           = 0.0;      // SFX: No hard daily target (long-term focus)
input double   Inp_WeeklyMaxDrawdownPct           = -5.00;    // TIER 2: Weekly cumulative loss
input bool     Inp_EnableWeeklyDrawdown           = true;     // Enable weekly tracking
input double   Inp_GlobalMaxDrawdownPct           = -6.0;     // SFX: 6% trailing drawdown limit (CRITICAL)
input bool     Inp_EnableGlobalDrawdown           = true;     // Enable global protection
input bool     Inp_EnableTradeLogging             = true;     // Enable logging
input bool     Inp_EnableSlippageModeling         = true;     // Enable slippage costs
input double   Inp_AverageSpreadPips_ForEx        = 2.0;      // Forex spread
input double   Inp_AverageSpreadPips_Metals       = 3.5;      // Metals spread (XAU)
input double   Inp_AverageSpreadPips_Indices      = 8.0;      // Indices spread (US30, GER40, SPX500)
input double   Inp_AverageSpreadPips_Energy       = 5.0;      // Energy spread (Oil/XTIUSD)
input double   Inp_CommissionPipsRoundTrip        = 2.0;
input double   Inp_MaxAcceptableSpreadPips        = 6.0;

input group "════════ PORTFOLIO RISK (C3) - SFX BALANCED ════════"
// Per-trade hard lot caps — safety net against tight-ATR extreme sizing.
// At $250K / 1% risk, FX lots scale inversely with ATR: tight ATR (10 pip) → ~25 lots,
// normal ATR (40 pip) → ~6 lots. Caps prevent oversizing in low-volatility sessions.
input double   Inp_MaxLotsFX        = 10.0;  // Max lots per single FX trade
input double   Inp_MaxLotsGold      = 5.0;   // Max lots per single Gold trade (XAUUSD)
input double   Inp_MaxLotsIndex     = 5.0;   // Max lots per single Index trade
input double   Inp_MaxLotsOil       = 5.0;   // Max lots per single Oil trade (USOUSD)
// Net portfolio delta caps are computed at runtime as 2× per-trade lot cap.

input group "════════ TOXICITY GUARD (D2) ════════"
input bool     Inp_EnableToxicityGuard   = true;   // Filter noise/news
input double   Inp_ToxicityMultiplier    = 3.0;    // Spike threshold: current volume > 3× average
input int      Inp_NewsGuardMinutes      = 30;     // Buffer ±news event

input group "════════ ASYNC EXECUTION (C1/C2) ════════"
input double   Inp_IcebergThreshold   = 10.0;   // Lot size threshold for iceberg slicing
input double   Inp_IcebergClipSize    = 2.0;    // Clip size per async fire
input int      Inp_IcebergDelayMs     = 50;     // Delay between clips (ms)
input double   Inp_MaxSlippagePips    = 3.0;    // Max acceptable slippage vs intended

input group "════════ STRATEGY ENABLE FLAGS ════════"
input bool     Inp_EnableAsianBreakout      = true;
input bool     Inp_EnableVWAPReversion      = true;
input bool     Inp_EnableVolatilityMom      = true;

input group "════════ STRATEGY PARAMETERS ════════"
input double   Inp_BreakoutBufferPips       = 5.0;  // Buffer on both Phase 1 sweep and Phase 2 reclaim (symmetric)
input double   Inp_VWAP_Dev_FX              = 2.5;  // FX pairs — strong mean reversion
input double   Inp_VWAP_Dev_Commodity       = 3.0;  // Gold, Oil — commodities trend longer
input double   Inp_VWAP_Dev_Index           = 3.5;  // Indices — indices run hardest
input int      Inp_SweepReclaim_BarsToWait  = 32;   // 8 hours on M15 — one session of patience

input group "════════ EXIT RULE PARAMETERS ════════"
input bool     Inp_Rule2_DailyLossLimitEnabled    = true;
input bool     Inp_Rule2_CloseOnlyLosers          = true;     // Recovery mode on daily limit
input bool     Inp_Rule4_MomentumDivergenceEnabled = false;
input double   Inp_Rule4_ADXDecliningThreshold    = 20.0;     // Standard ADX trend-loss level
input double   Inp_Rule4_PartialClose_Pct         = 50.0;     // Close 50% on momentum divergence (must be ≤100)
input bool     Inp_Rule5_VolatilitySpikeEnabled   = true;
input double   Inp_Rule5_ATRSpikeMultiplier       = 2.5;      // Current ATR > 2.5× 20-bar avg ATR (ratio, asset-agnostic)
input bool     Inp_Rule6_TimeBasedExitEnabled     = true;
input int      Inp_Rule6_MaxTimeOpen_Seconds      = 14400;    // 4 hours max hold
input bool     Inp_Rule8_PartialTPEnabled         = true;
input double   Inp_Rule8_FirstTP_Pct              = 50.0;     // Close 50% at TP-50 (must be ≤100)
input double   Inp_Rule8_SecondTP_Pct             = 50.0;     // Close 50% of remainder at TP-75 (must be ≤100)
input bool     Inp_Rule10_TrailingStopEnabled     = true;
input double   Inp_Rule10_ProfitThreshold_Pips    = 30.0;     // Start trailing once 30 pips in profit
input double   Inp_Rule10_TrailBase_Pips          = 25.0;     // Floor trail distance in pips
input double   Inp_Rule10_ATRMultiplier           = 1.5;      // Standard ATR-trailing coefficient

input group "════════ TP-PROXIMITY (Rule 11) ════════"
input bool     Inp_Rule11_TPTightenEnabled        = true;     // Lock profits near TP
input double   Inp_Rule11_Trigger_Pct             = 75.0;     // Fire when 75% of TP distance reached (must be ≤100)
input double   Inp_Rule11_LockedProfit_Pips       = 30.0;     // Min 30 pips locked

input group "════════ PER-SYMBOL TRADE LIMIT ════════"
input int      Inp_MaxTradesPerSymbolPerDay       = 5;        // Prevents one runaway symbol dominating risk

input group "════════ STATE PERSISTENCE ════════"
input bool     Inp_HaltOnStateCorruption          = true;     // Halt EA on risk-state checksum failure

input bool     Inp_UseLimitOrdersForBreakout      = false;    // Use Limits instead of Market
input double   Inp_LimitBufferPips                = 1.0;      // Pips to lead/lag for limits

input group "════════ ENTRY SL/TP (v9.1) ════════"
// Entries now set real SL/TP at order placement. Sizing math assumes the SL is
// actually placed — without this, positions run unprotected (see Trade #275).
input double   Inp_RiskRewardRatio                = 2.0;      // TP distance = SL distance × ratio (range [1.0, 5.0])

input group "════════ WEEKEND GAP PROTECTION (v9.1) ════════"
// Flat all positions before weekend close. USOUSD most gap-prone; applies to all.
// Set to -1 to disable (FX-only accounts or 24/7 symbols).
input int      Inp_FridayFlattenHour              = 22;       // Server hour (0–23) at which Friday close-all fires; -1 disables

#endif
