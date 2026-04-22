import numpy as np
import pandas as pd
from quantfreedom.base.base import backtest_df_only

try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False

try:
    import yfinance as yf
    YF_AVAILABLE = True
except ImportError:
    YF_AVAILABLE = False

def fetch_historical_data(assets):
    """
    Attempts to fetch 1-Hour data from MT5.
    Falls back to yfinance if MT5 is unavailable (e.g. on Linux/Mac).
    """
    all_prices = []
    cols = []

    # 1. Try MetaTrader 5
    if MT5_AVAILABLE:
        print("Attempting to initialize MetaTrader 5...")
        if mt5.initialize():
            print("MT5 initialized successfully.")
            timeframe = mt5.TIMEFRAME_H1
            num_bars = 5000

            success = True
            df_index = None
            for i, asset in enumerate(assets):
                print(f"Fetching {asset} from MT5...")
                # MT5 asset names might need exact broker matching (e.g., EURUSD.a)
                rates = mt5.copy_rates_from_pos(asset, timeframe, 0, num_bars)
                if rates is None or len(rates) == 0:
                    print(f"Failed to fetch {asset} from MT5. Check symbol name or MT5 connection.")
                    success = False
                    break

                df = pd.DataFrame(rates)
                df['time'] = pd.to_datetime(df['time'], unit='s')
                df.set_index('time', inplace=True)
                df_index = df.index

                asset_data = df[['open', 'high', 'low', 'close']].values
                all_prices.append(asset_data)
                cols.extend([(i, 'open'), (i, 'high'), (i, 'low'), (i, 'close')])

            mt5.shutdown()

            if success:
                print("Successfully fetched all data from MT5.")
                prices_data = np.hstack(all_prices)
                prices_cols = pd.MultiIndex.from_tuples(cols)
                prices = pd.DataFrame(prices_data, columns=prices_cols, index=df_index)
                return prices
        else:
            print("MT5 initialization failed. Falling back...")
    else:
        print("MetaTrader5 package not found. Falling back...")

    # 2. Fallback to yfinance
    print("Falling back to yfinance for historical data...")
    if not YF_AVAILABLE:
        raise ImportError("yfinance is not installed. Please run: pip install yfinance")

    yf_tickers = {
        "GBPJPY": "GBPJPY=X",
        "US30": "^DJI",      # Dow Jones Industrial Average
        "OIL": "CL=F",       # Crude Oil Futures
        "XAUUSD": "GC=F",    # Gold Futures
        "DAX30": "^GDAXI",
        "NASDAQ": "^IXIC",
        "SPX": "^GSPC"
    }

    # yfinance 15m data is limited to max 60 days
    print("Downloading 59 days of 15-minute data from yfinance...")
    end_date = pd.Timestamp.now()
    start_date = end_date - pd.Timedelta(days=59)

    df_yf = yf.download(list(yf_tickers.values()), start=start_date, end=end_date, interval="15m", group_by='ticker', progress=False)

    # Forward fill missing data across different session hours
    df_yf.ffill(inplace=True)
    df_yf.dropna(inplace=True)

    for i, asset in enumerate(assets):
        ticker = yf_tickers[asset]
        open_col = df_yf[ticker]['Open'].values
        high_col = df_yf[ticker]['High'].values
        low_col  = df_yf[ticker]['Low'].values
        close_col = df_yf[ticker]['Close'].values

        asset_data = np.column_stack((open_col, high_col, low_col, close_col))
        all_prices.append(asset_data)
        cols.extend([(i, 'open'), (i, 'high'), (i, 'low'), (i, 'close')])

    prices_data = np.hstack(all_prices)
    prices_cols = pd.MultiIndex.from_tuples(cols)
    prices = pd.DataFrame(prices_data, columns=prices_cols, index=df_yf.index)
    return prices

def apply_time_filter(entries_df: pd.DataFrame, datetime_index: pd.DatetimeIndex):
    # Expanded Time Filter: Asian Open (0:00) to NY Close (17:00)
    valid_time = (datetime_index.hour >= 0) & (datetime_index.hour < 17)
    valid_day = datetime_index.dayofweek < 5
    valid_mask = valid_time & valid_day

    for col in entries_df.columns:
        entries_df[col] = entries_df[col] & valid_mask
    return entries_df

def apply_correlation_filter(entries_df: pd.DataFrame, max_correlated=4):
    signal_counts = entries_df.sum(axis=1)
    exceeds_limit = signal_counts > max_correlated
    for col in entries_df.columns:
        entries_df.loc[exceeds_limit, col] = False
    return entries_df

def generate_signals(prices: pd.DataFrame, num_assets: int, lookback=20):
    entries_dict = {}
    for i in range(num_assets):
        close_prices = prices[(i, 'close')]
        highest_peak = close_prices.shift(1).rolling(window=lookback).max()
        entries_data = close_prices > highest_peak
        entries_dict[(i, 0)] = entries_data
    entries = pd.DataFrame(entries_dict, index=prices.index)
    entries.fillna(False, inplace=True)
    return entries

try:
    import talib
    TALIB_AVAILABLE = True
except ImportError:
    TALIB_AVAILABLE = False

def apply_adx_ny_filter(entries_df: pd.DataFrame, prices: pd.DataFrame, datetime_index: pd.DatetimeIndex, num_assets: int):
    """
    Simulates the precision ADX filter during NY Session (>= 14:00)
    If time >= 14 and ADX < 30.0, set entry to False to avoid whipsaws.
    Gracefully bypasses if talib is not installed.
    """
    if not TALIB_AVAILABLE:
        print("WARNING: TA-Lib not installed. Bypassing NY Session ADX precision filter.")
        return entries_df

    for i in range(num_assets):
        high_prices = prices[(i, 'high')]
        low_prices = prices[(i, 'low')]
        close_prices = prices[(i, 'close')]

        # Calculate 14-period ADX
        adx_values = talib.ADX(high_prices, low_prices, close_prices, timeperiod=14)

        # Mask where time is NY Session (>= 14) AND ADX is weak (< 30) - 80% Precision Req
        ny_whipsaw_mask = (datetime_index.hour >= 14) & (adx_values < 30.0)

        # Apply filter to that asset's entries
        entries_df[(i, 0)] = entries_df[(i, 0)] & (~ny_whipsaw_mask)

    return entries_df

def main():
    assets = ["GBPJPY", "US30", "OIL", "XAUUSD", "DAX30", "NASDAQ", "SPX"]
    prices = fetch_historical_data(assets)

    if prices is None or prices.empty:
        print("Failed to fetch data.")
        return

    entries = generate_signals(prices, len(assets), lookback=20)
    entries = apply_time_filter(entries, prices.index)
    entries = apply_adx_ny_filter(entries, prices, prices.index, len(assets))
    entries = apply_correlation_filter(entries, max_correlated=4)

    total_bars = len(prices)
    # 15m data: 4 bars per hour, ~120 trading hours in a week = 480 bars per week
    total_weeks = total_bars / 480.0

    try:
        strat_df, settings_df = backtest_df_only(
            prices=prices,
            entries=entries,
            equity=100000.0,
            fee_pct=0.01,
            mmr_pct=0.01,
            lev_mode=1,
            order_type=0,
            size_type=0,
            leverage=np.array([np.nan]),
            max_equity_risk_pct=np.array([0.50]), # Increased to 0.5%
            size_pct=np.array([np.nan]),
            size_value=np.array([10000.0]),
            sl_pcts=np.array([1.0]),
            risk_rewards=np.array([2.4]),
        )

        symbol_map = {str(i): asset for i, asset in enumerate(assets)}

        print("\n--- Real Historical Data Weekly Returns ---")
        print(f"Total simulated time span: ~{total_weeks:.1f} trading weeks ({total_bars} bars)")
        print(f"Starting Equity: $100,000\n")

        for index, row in strat_df.iterrows():
            sym_idx = str(int(float(row['symbol'])))
            asset_name = symbol_map.get(sym_idx, sym_idx)
            total_pnl = float(row['total_pnl'])
            avg_weekly_pnl = total_pnl / total_weeks if total_weeks > 0 else 0
            avg_weekly_pct = (avg_weekly_pnl / 100000.0) * 100

            print(f"Asset: {asset_name:8s} | Total PnL: ${total_pnl:9.2f} | Avg Weekly PnL: ${avg_weekly_pnl:7.2f} | Avg Weekly Return: {avg_weekly_pct:5.2f}%")

    except Exception as e:
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
