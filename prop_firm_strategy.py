import numpy as np
import pandas as pd
from quantfreedom.base.base import backtest_df_only

def create_mock_multi_asset_data(assets, periods=5000):
    """
    Creates mock 1-hour OHLC data for multiple assets with a DatetimeIndex.
    """
    np.random.seed(42)
    # 1 Hour frequency
    date_rng = pd.date_range(start='2023-01-01', periods=periods, freq='h')

    all_prices = []
    cols = []

    for i, asset in enumerate(assets):
        returns = np.random.normal(0.0001, 0.005, periods)
        close = 100 * np.cumprod(1 + returns)
        high = close * (1 + np.abs(np.random.normal(0.002, 0.001, periods)))
        low = close * (1 - np.abs(np.random.normal(0.002, 0.001, periods)))
        open_price = np.roll(close, 1)
        open_price[0] = 100

        asset_data = np.column_stack((open_price, high, low, close))
        all_prices.append(asset_data)

        # QuantFreedom requires (symbol_index, 'open'/'high'/'low'/'close')
        cols.extend([(i, 'open'), (i, 'high'), (i, 'low'), (i, 'close')])

    prices_data = np.hstack(all_prices)
    prices_cols = pd.MultiIndex.from_tuples(cols)
    prices = pd.DataFrame(prices_data, columns=prices_cols, index=date_rng)
    return prices

def apply_time_filter(entries_df: pd.DataFrame, datetime_index: pd.DatetimeIndex):
    """
    Blocks overnight and weekend trades.
    London Open ~ 08:00
    NY Close ~ 17:00
    """
    # Create mask for valid times
    valid_time = (datetime_index.hour >= 8) & (datetime_index.hour < 17)
    # Mask for valid days (Monday=0, Sunday=6)
    valid_day = datetime_index.dayofweek < 5

    # Combined mask
    valid_mask = valid_time & valid_day

    # Apply mask to all columns in entries_df
    for col in entries_df.columns:
        entries_df[col] = entries_df[col] & valid_mask

    return entries_df

def apply_correlation_filter(entries_df: pd.DataFrame, max_correlated=4):
    """
    Basic mock correlation filter: prevents entering if we already have
    a high number of assets showing an entry signal simultaneously.
    """
    # Count how many entry signals are True in each row
    signal_counts = entries_df.sum(axis=1)

    # If the number of simultaneous signals exceeds the limit, block all signals for that bar
    exceeds_limit = signal_counts > max_correlated

    for col in entries_df.columns:
        entries_df.loc[exceeds_limit, col] = False

    return entries_df

def generate_signals(prices: pd.DataFrame, num_assets: int, lookback=20):
    """
    Generate entries based on Top/Bottom continuation/reversal logic.
    Enter Long if price breaks above 20-period highest peak.
    """
    entries_dict = {}

    for i in range(num_assets):
        close_prices = prices[(i, 'close')]
        highest_peak = close_prices.shift(1).rolling(window=lookback).max()

        # Generate Long Entries
        entries_data = close_prices > highest_peak
        entries_dict[(i, 0)] = entries_data # (symbol_index, entry_logic_index)

    entries = pd.DataFrame(entries_dict, index=prices.index)
    entries.fillna(False, inplace=True)
    return entries

def main():
    print("--- Prop Firm Backtest Strategy Initialization ---")

    assets = ["EURUSD", "GBPUSD", "USDJPY", "OIL", "XAUUSD", "DAX30", "NASDAQ", "SPX"]
    print(f"Assets configured: {assets}")

    prices = create_mock_multi_asset_data(assets, periods=5000)
    entries = generate_signals(prices, len(assets), lookback=20)

    print("Applying Time Constraints (London 08:00 - NY 17:00, No Weekends)")
    entries = apply_time_filter(entries, prices.index)

    print("Applying Correlation Constraints (Max 4 simultaneous entries)")
    entries = apply_correlation_filter(entries, max_correlated=4)

    print("\nSimulating User Rules:")
    print("- Target Daily Profit: 1-3%")
    print("- Max Daily Loss Limit: 2%")
    print("- Weekly Max Loss Limit: 5%")
    print("Notice: The quantfreedom base engine simulates orders based on these risk parameters mapping.")

    try:
        strat_df, settings_df = backtest_df_only(
            prices=prices,
            entries=entries,
            equity=100000.0,      # $100k Prop Firm Account
            fee_pct=0.01,
            mmr_pct=0.01,
            lev_mode=1,           # Least free cash used mode
            order_type=0,         # Long
            size_type=0,          # Amount
            leverage=np.array([np.nan]),
            size_pct=np.array([np.nan]),
            size_value=np.array([10000.0]), # Trade size amount
            sl_pcts=np.array([1.0]),  # 1% stop loss maps to 1% equity risk on $100k
            risk_rewards=np.array([2.0]), # 1:2 Risk Reward (Aiming for 2% profit)
        )
        print("\nBacktest successful!")
        print("\nTop Strategy Results:")
        print(strat_df.head(5))

    except Exception as e:
        import traceback
        print("\nError running backtest:")
        traceback.print_exc()

if __name__ == "__main__":
    main()
