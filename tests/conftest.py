"""
Pytest configuration and shared fixtures for QuantFreedom tests.
"""
import numpy as np
import pandas as pd
import pytest

from quantfreedom.enums.enums import (
    AccountState,
    Arrays1dTuple,
    EntryOrder,
    LeverageMode,
    OrderResult,
    OrderType,
    SizeType,
    StaticVariables,
    StopsOrder,
)


@pytest.fixture
def sample_prices():
    """Generate sample OHLCV price data for testing."""
    np.random.seed(42)
    n_bars = 100
    base_price = 100.0

    # Generate realistic price movements
    returns = np.random.randn(n_bars) * 0.02  # 2% volatility
    close_prices = base_price * np.exp(np.cumsum(returns))

    # Generate OHLC from close prices
    high_prices = close_prices * (1 + np.abs(np.random.randn(n_bars) * 0.01))
    low_prices = close_prices * (1 - np.abs(np.random.randn(n_bars) * 0.01))
    open_prices = np.roll(close_prices, 1)
    open_prices[0] = base_price

    # Create DataFrame with MultiIndex columns (symbol, candle_info)
    columns = pd.MultiIndex.from_tuples(
        [
            ("BTC/USDT", "open"),
            ("BTC/USDT", "high"),
            ("BTC/USDT", "low"),
            ("BTC/USDT", "close"),
        ],
        names=["symbol", "candle_info"],
    )

    df = pd.DataFrame(
        np.column_stack([open_prices, high_prices, low_prices, close_prices]),
        columns=columns,
    )

    return df


@pytest.fixture
def sample_entries():
    """Generate sample entry signals."""
    np.random.seed(42)
    n_bars = 100

    # Create simple entry signals (every 10 bars)
    entries = np.zeros((n_bars, 1))
    entries[::10] = 1

    columns = pd.MultiIndex.from_tuples(
        [("BTC/USDT", 0)], names=["symbol", "indicator_setting"]
    )

    df = pd.DataFrame(entries, columns=columns)
    return df


@pytest.fixture
def basic_account_state():
    """Create a basic account state for testing."""
    return AccountState(
        available_balance=1000.0, cash_borrowed=0.0, cash_used=0.0, equity=1000.0
    )


@pytest.fixture
def long_entry_order():
    """Create a basic long entry order."""
    return EntryOrder(
        leverage=10.0,
        max_equity_risk_pct=np.nan,
        max_equity_risk_value=np.nan,
        order_type=OrderType.LongEntry,
        risk_rewards=np.nan,
        size_pct=np.nan,
        size_value=100.0,
        sl_pcts=0.02,  # 2% stop loss
        tp_pcts=0.05,  # 5% take profit
        tsl_pcts_init=np.nan,
    )


@pytest.fixture
def short_entry_order():
    """Create a basic short entry order."""
    return EntryOrder(
        leverage=10.0,
        max_equity_risk_pct=np.nan,
        max_equity_risk_value=np.nan,
        order_type=OrderType.ShortEntry,
        risk_rewards=np.nan,
        size_pct=np.nan,
        size_value=100.0,
        sl_pcts=0.02,
        tp_pcts=0.05,
        tsl_pcts_init=np.nan,
    )


@pytest.fixture
def empty_order_result():
    """Create an empty order result (no position)."""
    return OrderResult(
        average_entry=0.0,
        fees_paid=0.0,
        leverage=0.0,
        liq_price=np.nan,
        moved_sl_to_be=False,
        order_status=0,
        order_status_info=0,
        order_type=OrderType.LongEntry,
        pct_chg_trade=0.0,
        position=0.0,
        price=0.0,
        realized_pnl=0.0,
        size_value=0.0,
        sl_pcts=0.0,
        sl_prices=0.0,
        tp_pcts=0.0,
        tp_prices=0.0,
        tsl_pcts_init=0.0,
        tsl_prices=0.0,
    )


@pytest.fixture
def basic_static_variables():
    """Create basic static variables for testing."""
    return StaticVariables(
        divide_records_array_size_by=1.0,
        fee_pct=0.0006,  # 0.06%
        lev_mode=LeverageMode.Isolated,
        max_lev=100.0,
        max_order_size_pct=100.0,
        max_order_size_value=np.inf,
        min_order_size_pct=0.01,
        min_order_size_value=1.0,
        mmr_pct=0.005,  # 0.5%
        order_type=OrderType.LongEntry,
        size_type=SizeType.Amount,
        sl_to_be_then_trail=False,
        sl_to_be=False,
        tsl_true_or_false=False,
        upside_filter=-1.0,
    )


@pytest.fixture
def basic_stops_order():
    """Create basic stops order configuration."""
    return StopsOrder(
        sl_to_be=False,
        sl_to_be_based_on=np.nan,
        sl_to_be_then_trail=False,
        sl_to_be_trail_by_when_pct_from_avg_entry=np.nan,
        sl_to_be_when_pct_from_avg_entry=np.nan,
        sl_to_be_zero_or_entry=np.nan,
        tsl_based_on=np.nan,
        tsl_trail_by_pct=np.nan,
        tsl_true_or_false=False,
        tsl_when_pct_from_avg_entry=np.nan,
    )


@pytest.fixture
def sample_1d_arrays():
    """Create sample 1D arrays for cart product testing."""
    return Arrays1dTuple(
        leverage=np.array([10.0, 20.0]),
        max_equity_risk_pct=np.array([np.nan]),
        max_equity_risk_value=np.array([np.nan]),
        risk_rewards=np.array([np.nan]),
        size_pct=np.array([np.nan]),
        size_value=np.array([100.0]),
        sl_pcts=np.array([0.02, 0.03]),  # 2%, 3%
        sl_to_be_based_on=np.array([np.nan]),
        sl_to_be_trail_by_when_pct_from_avg_entry=np.array([np.nan]),
        sl_to_be_when_pct_from_avg_entry=np.array([np.nan]),
        sl_to_be_zero_or_entry=np.array([np.nan]),
        tp_pcts=np.array([0.05]),  # 5%
        tsl_based_on=np.array([np.nan]),
        tsl_pcts_init=np.array([np.nan]),
        tsl_trail_by_pct=np.array([np.nan]),
        tsl_when_pct_from_avg_entry=np.array([np.nan]),
    )
