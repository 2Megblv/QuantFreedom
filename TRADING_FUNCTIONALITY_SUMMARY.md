# QuantFreedom Trading Functionality Summary
**Date**: 2025-11-06
**Audience**: Traders and Strategy Developers

---

## What is QuantFreedom?

QuantFreedom is a **high-performance Python library for backtesting cryptocurrency trading strategies at scale**. It's designed to test thousands of parameter combinations efficiently using Numba JIT compilation, helping traders optimize their strategies across multiple symbols, timeframes, and risk parameters.

**Primary Use Case**: Systematic strategy development and optimization for leveraged cryptocurrency trading (primarily designed for exchanges like Bybit, Binance via CCXT).

---

## Core Trading Capabilities

### 1. **Position Types**

QuantFreedom supports three order types:

- **Long Only** (`OrderType.LongEntry`) - Buy and hold bullish positions
- **Short Only** (`OrderType.ShortEntry`) - Sell and hold bearish positions
- **Both** (`OrderType.Both`) - Trade both directions based on signals

**Location**: `quantfreedom/enums/enums.py:165-169`

### 2. **Leverage Trading**

Two leverage modes are supported:

#### **Isolated Margin** (`LeverageMode.Isolated`)
- Fixed leverage per trade (1x to 100x)
- Risk is isolated to the position
- Liquidation only affects that specific position
- **Use case**: Conservative traders who want to limit downside

#### **Cross Margin** (`LeverageMode.LeastFreeCashUsed`)
- Uses available account balance to avoid liquidation
- More flexible, harder to liquidate
- Leverage varies based on position size
- **Use case**: Experienced traders managing multiple positions

**Location**: `quantfreedom/enums/enums.py:140-145`

---

## Position Sizing Strategies

QuantFreedom offers four sophisticated position sizing methods:

### **1. Fixed Amount** (`SizeType.Amount`)
```python
size_value = 1000.0  # $1000 per trade
```
- Trade a fixed dollar amount
- Simple, predictable position sizes

### **2. Percent of Account** (`SizeType.PercentOfAccount`)
```python
size_pct = 10.0  # 10% of equity
```
- Risk a percentage of your account balance
- Scales with account growth

### **3. Risk Amount** (`SizeType.RiskAmount`)
```python
size_value = 50.0  # Risk $50 per trade
sl_pcts = 2.0      # With 2% stop loss
# Calculates: position_size = $50 / 0.02 = $2,500
```
- **Fixed dollar risk per trade**
- Position size adjusts based on stop loss distance
- Professional risk management approach

### **4. Risk Percent of Account** (`SizeType.RiskPercentOfAccount`)
```python
size_pct = 1.0     # Risk 1% of equity
sl_pcts = 2.0      # With 2% stop loss
equity = 10000
# Calculates: position_size = (10000 * 0.01) / 0.02 = $5,000
```
- **Percentage-based risk management**
- Kelly Criterion compatible
- Most common among professional traders

**Implementation**: `quantfreedom/nb/buy_funcs.py:49-95`

---

## Risk Management Features

### 1. **Stop Loss (SL)**

Basic stop loss functionality:
```python
sl_pcts = 2.0  # Stop loss at 2% from entry
```

**How it works**:
- **Long positions**: Exits when price drops 2% below entry
- **Short positions**: Exits when price rises 2% above entry
- Executed at open of next candle (realistic slippage modeling)

**Implementation**: `quantfreedom/nb/execute_funcs.py:59-70` (long), `136-146` (short)

---

### 2. **Trailing Stop Loss (TSL)**

Dynamic stop loss that follows price in favorable direction:

```python
tsl_pcts_init = 2.0              # Initial stop: 2% from entry
tsl_true_or_false = True          # Enable TSL
tsl_based_on = SL_BE_or_Trail_BasedOn.high_price  # Trail based on high
tsl_trail_by_pct = 1.0            # Trail 1% from high
tsl_when_pct_from_avg_entry = 3.0 # Start trailing at 3% profit
```

**Example (Long Trade)**:
1. Enter at $100
2. Initial stop at $98 (2%)
3. Price rises to $105 (5% profit > 3% threshold)
4. TSL activates: Stop moves to $105 - 1% = $103.95
5. If price rises to $110, stop moves to $108.90
6. Locks in profits while allowing position to run

**Based On Options**:
- `open_price` - Trail based on candle open
- `high_price` - Trail based on candle high (aggressive for longs)
- `low_price` - Trail based on candle low (conservative for longs)
- `close_price` - Trail based on candle close

**Implementation**: `quantfreedom/nb/execute_funcs.py:104-131` (long), `180-204` (short)

---

### 3. **Stop Loss to Break Even (SL to BE)**

Automatically moves stop loss to entry price (or zero loss) after hitting profit target:

```python
sl_to_be = True                           # Enable break even
sl_to_be_based_on = SL_BE_or_Trail_BasedOn.close_price
sl_to_be_when_pct_from_avg_entry = 5.0    # Move to BE at 5% profit
sl_to_be_zero_or_entry = 0                # 0 = zero loss, 1 = entry price
```

**Example**:
1. Enter long at $100
2. Initial SL at $98
3. Price reaches $105 (5% profit)
4. SL automatically moves to $100.20 (accounting for fees to ensure zero loss)
5. Now a "risk-free" trade

**Advanced: Break Even Then Trail**:
```python
sl_to_be_then_trail = True
sl_to_be_trail_by_when_pct_from_avg_entry = 2.0  # Trail 2% after BE
```
After moving to break even, the stop continues to trail the price.

**Implementation**: `quantfreedom/nb/execute_funcs.py:76-103` (long), `152-178` (short)

---

### 4. **Take Profit (TP)**

Two methods to set profit targets:

#### **Fixed Percentage**
```python
tp_pcts = 5.0  # Take profit at 5%
```

#### **Risk-Reward Ratio**
```python
sl_pcts = 2.0
risk_rewards = 3.0  # 3:1 reward-to-risk
# TP will be at 6% (2% * 3)
```

**Implementation**: `quantfreedom/nb/execute_funcs.py:72-74` (long), `148-150` (short)

---

### 5. **Liquidation Protection**

The system tracks liquidation prices based on:
- Leverage used
- Maintenance margin rate (MMR) - exchange-specific
- Position size and entry price

**Liquidation triggers**:
- **Long**: Price drops to liquidation level
- **Short**: Price rises to liquidation level

When liquidated, the entire position is closed at the liquidation price (worst-case scenario).

**Implementation**: `quantfreedom/nb/execute_funcs.py:68-70` (long), `144-146` (short)

---

## Order Execution Logic

### Entry Process

When an entry signal is generated (`entries[bar] == True`):

1. **Calculate Position Size** (based on SizeType)
2. **Validate Against Limits**:
   - `max_order_size_pct` (default 100%)
   - `min_order_size_pct` (default 0.01%)
   - `max_order_size_value` (default infinity)
   - `min_order_size_value` (default $1)
3. **Check Max Equity Risk**:
   - Ensures you don't risk more than a set % or $ amount
   - Prevents oversizing
4. **Calculate Fees** (deducted from available balance)
5. **Set Stop Loss and Take Profit Prices**
6. **Update Account State**:
   - Deduct from `available_balance`
   - Add to `cash_used`
   - Update `position`

**Implementation**: `quantfreedom/nb/buy_funcs.py:21-353` (long)

---

### Exit Process

Every bar after entry, the system checks (in priority order):

1. **Liquidation** - Highest priority
2. **Regular Stop Loss** - Second priority
3. **Trailing Stop Loss** - Third priority
4. **Take Profit** - Fourth priority
5. **Break Even Move** - If conditions met
6. **TSL Adjustment** - If price moving favorably

**Exit execution**:
- Closes position at next candle open
- Calculates realized PnL
- Deducts exit fees
- Returns cash to available balance
- Records trade statistics

**Implementation**: `quantfreedom/nb/execute_funcs.py:30-241`

---

## Backtesting Workflow

### Step 1: Data Download

```python
from quantfreedom import data_download_from_ccxt

prices = data_download_from_ccxt(
    exchange='bybit',
    start='2023-01-01T00:00:00Z',
    end='2024-01-01T00:00:00Z',
    symbols=['BTC/USDT', 'ETH/USDT'],
    timeframe='1h',
    drop_volume=True
)
```

**Returns**: MultiIndex DataFrame with OHLC data
```
Columns: [(BTC/USDT, open), (BTC/USDT, high), (BTC/USDT, low), (BTC/USDT, close), ...]
Index: DatetimeIndex
```

**Implementation**: `quantfreedom/data/data_dl.py:8-184`

---

### Step 2: Generate Entry Signals

Users provide entry signals as a DataFrame:

```python
import pandas as pd

# Example: Simple moving average crossover
entries = pd.DataFrame()
entries['BTC/USDT'] = (prices['BTC/USDT']['close'] > sma_slow).astype(int)
entries['ETH/USDT'] = (prices['ETH/USDT']['close'] > sma_slow).astype(int)
```

**Format**:
- 1 = Enter long (or short, depending on `order_type`)
- 0 = No signal
- Shape: (num_candles, num_symbols * num_indicator_settings)

---

### Step 3: Run Backtest

```python
from quantfreedom import backtest_df_only

strat_results, settings = backtest_df_only(
    # Data
    prices=prices,
    entries=entries,

    # Account settings
    equity=1000.0,
    fee_pct=0.06,  # 0.06% per trade
    mmr_pct=0.5,   # 0.5% maintenance margin (Bybit)

    # Order configuration
    lev_mode=0,    # Isolated margin
    order_type=0,  # Long only
    size_type=3,   # Risk percent of account

    # Position sizing
    leverage=np.array([5.0, 10.0, 20.0]),  # Test 3 leverage levels
    size_pct=np.array([1.0, 2.0]),         # Risk 1% or 2%

    # Risk management
    sl_pcts=np.array([1.0, 2.0, 3.0]),     # Test 3 SL levels
    tp_pcts=np.array([3.0, 5.0, 10.0]),    # Test 3 TP levels

    # Trailing stop
    tsl_true_or_false=True,
    tsl_pcts_init=np.array([2.0]),
    tsl_based_on=np.array([1]),  # High price
    tsl_trail_by_pct=np.array([1.0]),
    tsl_when_pct_from_avg_entry=np.array([3.0]),

    # Filters
    gains_pct_filter=0.0,      # Only return profitable strategies
    total_trade_filter=10,      # Minimum 10 trades
    upside_filter=0.5,          # R² filter for equity curve smoothness
)
```

**What happens internally**:

1. **Cartesian Product Generation**: Creates all combinations
   - 2 symbols × 3 leverages × 2 size_pcts × 3 SLs × 3 TPs = 108 combinations

2. **Simulation Loop** (Numba-optimized):
   ```
   For each symbol:
       For each indicator setting:
           For each order setting combination:
               For each candle bar:
                   - Check for entry signal
                   - Process entry if signal present
                   - Check stops (SL, TSL, TP, Liq)
                   - Update account state
   ```

3. **Performance Metrics Calculation**:
   - Total trades
   - Win rate
   - Gains %
   - Total PnL
   - "To the upside" (R² of cumulative PnL - smoothness metric)

4. **Filtering**:
   - Remove strategies below thresholds
   - Sort by "to_the_upside" and "gains_pct"

**Implementation**: `quantfreedom/nb/simulate.py:29-263`

---

### Step 4: Analyze Results

**Strategy Results** (`strat_results`):
```
| symbol    | entries_col | or_set | total_trades | gains_pct | win_rate | to_the_upside | total_pnl | ending_eq |
|-----------|-------------|--------|--------------|-----------|----------|---------------|-----------|-----------|
| BTC/USDT  | 0           | 42     | 156          | 245.8     | 58.3     | 0.94          | 2458.23   | 3458.23   |
| ETH/USDT  | 0           | 15     | 203          | 189.4     | 61.2     | 0.89          | 1894.55   | 2894.55   |
```

**Settings Results** (`settings`):
```
| symbol    | entries_col | leverage | size_pct | sl_pcts | tp_pcts | tsl_based_on | ...
|-----------|-------------|----------|----------|---------|---------|--------------|
| BTC/USDT  | 0           | 10.0     | 2.0      | 2.0     | 5.0     | high_price   | ...
| ETH/USDT  | 0           | 5.0      | 1.0      | 1.0     | 3.0     | high_price   | ...
```

---

## Advanced Features

### 1. **Cartesian Product Testing**

Test thousands of parameter combinations automatically:

```python
# This creates 2 × 3 × 3 × 3 = 54 combinations per symbol
leverage = np.array([5.0, 10.0])
sl_pcts = np.array([1.0, 2.0, 3.0])
tp_pcts = np.array([3.0, 5.0, 10.0])
size_pct = np.array([1.0, 2.0, 3.0])
```

**Performance**: Can backtest **millions of candles** across thousands of combinations in minutes thanks to Numba JIT compilation.

**Implementation**: `quantfreedom/nb/helper_funcs.py` (cartesian product generation)

---

### 2. **Multi-Symbol Backtesting**

Backtest multiple cryptocurrencies simultaneously:

```python
prices_df  # Columns: BTC/USDT, ETH/USDT, SOL/USDT (OHLC for each)
entries_df # Columns: Same structure with entry signals

# Results show performance per symbol
results_btc = strat_results[strat_results['symbol'] == 'BTC/USDT']
results_eth = strat_results[strat_results['symbol'] == 'ETH/USDT']
```

---

### 3. **"To the Upside" Metric**

QuantFreedom's unique quality metric:

**Formula**: R² (coefficient of determination) of cumulative PnL

**What it measures**:
- How smoothly equity grows
- Strategy consistency
- Lower drawdown variance

**Values**:
- `1.0` = Perfect smooth upward equity curve
- `0.5` = Moderate consistency
- `0.0` = Random/choppy results

**Why it matters**: High gains with high "to_the_upside" = reliable strategy

**Implementation**: `quantfreedom/nb/helper_funcs.py` (R² calculation on cumulative PnL)

---

### 4. **Memory Optimization**

For large backtests (millions of combinations):

```python
divide_records_array_size_by=100  # Pre-allocate 1/100th of possible results
```

**How it works**:
- System pre-allocates result arrays
- With strict filters, most combinations won't pass
- This parameter reduces memory usage

**Example**: Testing 10M combinations but expecting only 10k to pass filters
```python
divide_records_array_size_by=1000  # Allocate 10k rows instead of 10M
```

---

## Realistic Trading Simulation

### Execution Model

1. **Entry**: Always at open of candle after signal
   ```
   Bar N: Signal generated
   Bar N+1: Enter at open price
   ```

2. **Stops**: Checked during candle, executed at next open
   ```
   Bar N: Low touches stop loss
   Bar N+1: Exit at open price (realistic slippage)
   ```

3. **Fees**: Applied on both entry and exit
   ```python
   entry_fee = position_size * price * fee_pct
   exit_fee = position_size * exit_price * fee_pct
   realized_pnl = gross_pnl - entry_fee - exit_fee
   ```

### Account State Tracking

After every order:
```python
AccountState(
    available_balance=7500.0,  # Cash available for new trades
    cash_borrowed=0.0,          # Amount borrowed (leverage)
    cash_used=2500.0,           # Cash tied up in positions
    equity=10200.0              # Total account value (incl. unrealized PnL)
)
```

**Bankruptcy Protection**: Stops taking new trades when `available_balance < $5`

---

## Visualization & Analysis

### Interactive Dashboard

```python
from quantfreedom.plotting import create_strategy_dashboard

create_strategy_dashboard(
    prices=prices,
    strat_results=strat_results,
    settings=settings
)
```

**Features**:
- Interactive Plotly Dash interface
- Candlestick charts with entry/exit markers
- Cumulative PnL graphs
- Trade-by-trade analysis
- Parameter comparison

**Implementation**: `quantfreedom/plotting/plotting_main.py`

---

## Typical Use Cases

### 1. **Strategy Parameter Optimization**

**Goal**: Find optimal SL/TP levels for a moving average crossover

```python
# Test 27 combinations
sl_pcts = np.array([0.5, 1.0, 1.5, 2.0, 2.5, 3.0])
tp_pcts = np.array([1.0, 2.0, 3.0, 5.0, 10.0])

results, settings = backtest_df_only(...)

# Best combination by "to_the_upside"
best = results.iloc[0]
best_settings = settings[best['or_set']]
```

---

### 2. **Multi-Timeframe Strategy**

**Goal**: Test if strategy works better on 1h vs 4h timeframes

```python
# Download both timeframes
prices_1h = data_download_from_ccxt(..., timeframe='1h')
prices_4h = data_download_from_ccxt(..., timeframe='4h')

# Generate signals
entries_1h = generate_signals(prices_1h)
entries_4h = generate_signals(prices_4h)

# Backtest both
results_1h, _ = backtest_df_only(prices=prices_1h, entries=entries_1h, ...)
results_4h, _ = backtest_df_only(prices=prices_4h, entries=entries_4h, ...)

# Compare
print(f"1h avg gains: {results_1h['gains_pct'].mean()}")
print(f"4h avg gains: {results_4h['gains_pct'].mean()}")
```

---

### 3. **Risk Management Testing**

**Goal**: Compare fixed % SL vs trailing stop loss

```python
# Test 1: Fixed SL only
results_fixed, _ = backtest_df_only(
    sl_pcts=np.array([2.0]),
    tsl_true_or_false=False,
    ...
)

# Test 2: Trailing SL
results_tsl, _ = backtest_df_only(
    tsl_pcts_init=np.array([2.0]),
    tsl_true_or_false=True,
    tsl_trail_by_pct=np.array([1.0]),
    tsl_when_pct_from_avg_entry=np.array([3.0]),
    ...
)

# Compare win rates and avg gains
```

---

### 4. **Portfolio Testing**

**Goal**: Test strategy across top 10 cryptocurrencies

```python
symbols = ['BTC/USDT', 'ETH/USDT', 'SOL/USDT', ...]  # 10 symbols

prices = data_download_from_ccxt(
    symbols=symbols,
    ...
)

results, _ = backtest_df_only(prices, entries, ...)

# Analyze per-symbol performance
for symbol in symbols:
    sym_results = results[results['symbol'] == symbol]
    print(f"{symbol}: {sym_results['gains_pct'].mean():.2f}%")
```

---

## Performance Characteristics

### Speed

**Thanks to Numba JIT compilation**:
- First run: Slow (compilation overhead, ~30s)
- Subsequent runs: Fast (compiled code cached)
- Typical: **10,000 candles × 1,000 combinations in ~5-10 seconds**

### Memory Usage

**Depends on**:
- Number of combinations
- Number of trades
- `divide_records_array_size_by` parameter

**Example**:
- 10M combinations tested
- 100k pass filters
- ~500MB memory usage (with proper `divide_records_array_size_by`)

---

## Key Trading Concepts Implemented

### 1. **Position Management**
- ✅ Adding to positions
- ✅ Reducing positions
- ✅ Averaging entry price
- ✅ Tracking open position size

### 2. **Risk Management**
- ✅ Stop loss (fixed percentage)
- ✅ Trailing stop loss (dynamic)
- ✅ Break even stops
- ✅ Take profit targets
- ✅ Risk-reward ratios
- ✅ Max equity risk limits
- ✅ Liquidation protection

### 3. **Money Management**
- ✅ Fixed dollar sizing
- ✅ Percentage-based sizing
- ✅ Risk-based sizing (Kelly-compatible)
- ✅ Leverage control
- ✅ Position size limits

### 4. **Performance Analysis**
- ✅ Total trades
- ✅ Win rate
- ✅ Total PnL
- ✅ Gains percentage
- ✅ Ending equity
- ✅ Equity curve smoothness (R²)

---

## What QuantFreedom Does NOT Do

**Not Included** (users must implement):
- ❌ Indicator calculations (use TA-Lib, pandas-ta, etc.)
- ❌ Signal generation logic (user provides entry signals)
- ❌ Live trading / order execution
- ❌ Portfolio allocation across symbols
- ❌ Walk-forward optimization
- ❌ Monte Carlo simulation
- ❌ Overfitting detection
- ❌ Strategy combination/ensembling

**Focus**: Fast, accurate backtesting of user-defined entry signals with comprehensive risk management.

---

## Comparison to Other Backtesters

| Feature | QuantFreedom | Backtrader | Zipline | VectorBT |
|---------|--------------|------------|---------|----------|
| **Speed** | ⭐⭐⭐⭐⭐ (Numba) | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ (Numba) |
| **Leverage Support** | ✅ Full | ⚠️ Limited | ❌ No | ⚠️ Basic |
| **Trailing Stops** | ✅ Advanced | ✅ Yes | ❌ No | ✅ Yes |
| **Parameter Optimization** | ✅ Cartesian | ✅ Yes | ⚠️ Manual | ✅ Grid |
| **Multi-Symbol** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| **Crypto-Focused** | ✅ Yes | ⚠️ Generic | ❌ Stocks | ✅ Yes |
| **Break Even Stops** | ✅ Yes | ❌ No | ❌ No | ❌ No |
| **Live Trading** | ❌ No | ✅ Yes | ✅ Yes | ⚠️ Partial |

**QuantFreedom's Niche**: Ultra-fast parameter optimization for leveraged crypto strategies with advanced stop loss management.

---

## Example: Complete Trading Strategy

Here's a complete example combining all features:

```python
import numpy as np
import pandas as pd
from quantfreedom import backtest_df_only, data_download_from_ccxt

# 1. Download data
prices = data_download_from_ccxt(
    exchange='bybit',
    start='2023-01-01T00:00:00Z',
    end='2024-01-01T00:00:00Z',
    symbols=['BTC/USDT', 'ETH/USDT'],
    timeframe='1h',
)

# 2. Generate entry signals (simple SMA crossover)
for symbol in ['BTC/USDT', 'ETH/USDT']:
    close = prices[symbol]['close']
    sma_fast = close.rolling(20).mean()
    sma_slow = close.rolling(50).mean()

    # Long signal when fast crosses above slow
    entries[symbol] = (sma_fast > sma_slow).astype(int)

# 3. Define parameter space for optimization
leverage_tests = np.array([5.0, 10.0, 15.0])
sl_tests = np.array([1.0, 1.5, 2.0, 2.5])
tp_tests = np.array([3.0, 5.0, 8.0])
risk_pct_tests = np.array([0.5, 1.0, 1.5])

# Total: 2 symbols × 3 leverage × 4 SL × 3 TP × 3 risk = 216 combinations

# 4. Run backtest
results, settings = backtest_df_only(
    # Data
    prices=prices,
    entries=entries,

    # Account
    equity=10000.0,
    fee_pct=0.06,
    mmr_pct=0.5,

    # Order type
    lev_mode=0,  # Isolated
    order_type=0,  # Long only
    size_type=3,   # Risk % of account

    # Parameter arrays (cartesian product)
    leverage=leverage_tests,
    size_pct=risk_pct_tests,
    sl_pcts=sl_tests,
    tp_pcts=tp_tests,

    # Advanced risk management
    tsl_true_or_false=True,
    tsl_pcts_init=sl_tests,  # Same as initial SL
    tsl_based_on=np.array([1]),  # High price
    tsl_trail_by_pct=np.array([1.0]),  # Trail 1%
    tsl_when_pct_from_avg_entry=np.array([4.0]),  # Start at 4% profit

    sl_to_be=True,  # Move to break even
    sl_to_be_based_on=np.array([3]),  # Based on close
    sl_to_be_when_pct_from_avg_entry=np.array([3.0]),  # At 3% profit
    sl_to_be_zero_or_entry=np.array([0]),  # Zero loss (not entry)

    # Filters
    gains_pct_filter=10.0,  # Only strategies with >10% gains
    total_trade_filter=20,   # Minimum 20 trades
    upside_filter=0.6,       # R² > 0.6 (smooth equity curve)
)

# 5. Analyze top strategies
print("\n=== Top 5 Strategies ===")
print(results.head())

# 6. Get best strategy details
best = results.iloc[0]
best_settings = settings[best['or_set']]

print(f"\n=== Best Strategy Details ===")
print(f"Symbol: {best['symbol']}")
print(f"Leverage: {best_settings['leverage']}")
print(f"Risk %: {best_settings['size_pct']}")
print(f"SL %: {best_settings['sl_pcts']}")
print(f"TP %: {best_settings['tp_pcts']}")
print(f"Gains: {best['gains_pct']:.2f}%")
print(f"Win Rate: {best['win_rate']:.2f}%")
print(f"Total Trades: {best['total_trades']}")
print(f"To the Upside: {best['to_the_upside']:.3f}")
```

---

## Summary

**QuantFreedom is designed for**:
- ✅ Traders who want to optimize strategy parameters systematically
- ✅ Testing thousands of combinations efficiently
- ✅ Leveraged cryptocurrency trading strategies
- ✅ Advanced stop loss management (TSL, break even)
- ✅ Professional risk management (risk-based position sizing)
- ✅ Multi-symbol backtesting

**Best suited for**:
- Systematic traders
- Quantitative researchers
- Strategy developers
- Crypto traders using leverage

**Core Philosophy**: Provide entry signals → QuantFreedom handles everything else (position sizing, risk management, execution, performance tracking).

---

## Next Steps for Traders

1. **Start Simple**: Test with basic SL/TP first
2. **Add Complexity**: Gradually add trailing stops, break even
3. **Optimize**: Use cartesian product to find best parameters
4. **Validate**: Use walk-forward testing (not built-in, but can be done manually)
5. **Paper Trade**: Test in real-time before live trading
6. **Go Live**: Implement best strategies with proper risk management

**Remember**: Past performance doesn't guarantee future results. Always use proper position sizing and risk management in live trading.
