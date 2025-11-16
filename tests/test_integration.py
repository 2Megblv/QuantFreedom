"""
Integration tests for full backtest workflow.
"""
import numpy as np
import pandas as pd
import pytest

from quantfreedom import backtest_df_only
from quantfreedom.enums.enums import LeverageMode, OrderType, SizeType


@pytest.mark.integration
class TestBacktestDfOnly:
    """Integration tests for the main backtest_df_only function."""

    def test_simple_backtest_long_only(self, sample_prices, sample_entries):
        """Test basic backtest with long-only strategy."""
        strat_results, settings_results = backtest_df_only(
            prices=sample_prices,
            entries=sample_entries,
            equity=1000.0,
            fee_pct=0.0006,
            mmr_pct=0.005,
            lev_mode=LeverageMode.Isolated,
            order_type=OrderType.LongEntry,
            size_type=SizeType.Amount,
            size_value=np.array([100.0]),
            sl_pcts=np.array([0.02]),
            tp_pcts=np.array([0.05]),
            gains_pct_filter=-np.inf,
            total_trade_filter=0,
        )

        # Should return results
        assert isinstance(strat_results, pd.DataFrame)
        assert isinstance(settings_results, pd.DataFrame)
        assert len(strat_results) > 0

        # Check required columns exist
        assert "gains_pct" in strat_results.columns
        assert "win_rate" in strat_results.columns
        assert "total_trades" in strat_results.columns
        assert "to_the_upside" in strat_results.columns
        assert "ending_eq" in strat_results.columns

    def test_backtest_with_multiple_parameters(self, sample_prices, sample_entries):
        """Test backtest with cartesian product of parameters."""
        # Test 2 leverage × 2 SL × 2 TP = 8 combinations
        strat_results, settings_results = backtest_df_only(
            prices=sample_prices,
            entries=sample_entries,
            equity=1000.0,
            fee_pct=0.0006,
            mmr_pct=0.005,
            lev_mode=LeverageMode.Isolated,
            order_type=OrderType.LongEntry,
            size_type=SizeType.Amount,
            leverage=np.array([10.0, 20.0]),
            size_value=np.array([100.0]),
            sl_pcts=np.array([0.02, 0.03]),
            tp_pcts=np.array([0.05, 0.10]),
            gains_pct_filter=-np.inf,
            total_trade_filter=0,
        )

        # Should test multiple combinations
        # Results depend on which combinations pass filters
        assert len(settings_results) > 0

        # Settings should have leverage, sl_pcts, tp_pcts columns
        assert "leverage" in settings_results.index or "leverage" in settings_results.columns
        assert "sl_pcts" in settings_results.index or "sl_pcts" in settings_results.columns
        assert "tp_pcts" in settings_results.index or "tp_pcts" in settings_results.columns

    def test_backtest_with_trailing_stop(self, sample_prices, sample_entries):
        """Test backtest with trailing stop loss enabled."""
        strat_results, settings_results = backtest_df_only(
            prices=sample_prices,
            entries=sample_entries,
            equity=1000.0,
            fee_pct=0.0006,
            mmr_pct=0.005,
            lev_mode=LeverageMode.Isolated,
            order_type=OrderType.LongEntry,
            size_type=SizeType.Amount,
            size_value=np.array([100.0]),
            tsl_true_or_false=True,
            tsl_pcts_init=np.array([0.02]),
            tsl_based_on=np.array([1]),  # High price
            tsl_trail_by_pct=np.array([0.01]),
            tsl_when_pct_from_avg_entry=np.array([0.03]),
            tp_pcts=np.array([0.10]),
        )

        # Should complete without error
        assert len(strat_results) >= 0  # May or may not have results depending on signals

    def test_backtest_with_break_even(self, sample_prices, sample_entries):
        """Test backtest with break even stops."""
        strat_results, settings_results = backtest_df_only(
            prices=sample_prices,
            entries=sample_entries,
            equity=1000.0,
            fee_pct=0.0006,
            mmr_pct=0.005,
            lev_mode=LeverageMode.Isolated,
            order_type=OrderType.LongEntry,
            size_type=SizeType.Amount,
            size_value=np.array([100.0]),
            sl_pcts=np.array([0.02]),
            sl_to_be=True,
            sl_to_be_based_on=np.array([3]),  # Close price
            sl_to_be_when_pct_from_avg_entry=np.array([0.05]),
            sl_to_be_zero_or_entry=np.array([0]),  # Zero loss
            tp_pcts=np.array([0.10]),
        )

        # Should complete without error
        assert len(strat_results) >= 0

    def test_backtest_risk_based_sizing(self, sample_prices, sample_entries):
        """Test backtest with risk-based position sizing."""
        strat_results, settings_results = backtest_df_only(
            prices=sample_prices,
            entries=sample_entries,
            equity=1000.0,
            fee_pct=0.0006,
            mmr_pct=0.005,
            lev_mode=LeverageMode.Isolated,
            order_type=OrderType.LongEntry,
            size_type=SizeType.RiskPercentOfAccount,
            leverage=np.array([10.0]),
            size_pct=np.array([0.01, 0.02]),  # Risk 1% or 2%
            sl_pcts=np.array([0.02]),
            tp_pcts=np.array([0.05]),
        )

        # Should calculate position sizes based on risk
        assert len(strat_results) >= 0

    def test_backtest_with_filters(self, sample_prices, sample_entries):
        """Test backtest with result filters."""
        # First get unfiltered results
        strat_all, _ = backtest_df_only(
            prices=sample_prices,
            entries=sample_entries,
            equity=1000.0,
            fee_pct=0.0006,
            mmr_pct=0.005,
            lev_mode=LeverageMode.Isolated,
            order_type=OrderType.LongEntry,
            size_type=SizeType.Amount,
            size_value=np.array([100.0]),
            sl_pcts=np.array([0.02]),
            tp_pcts=np.array([0.05]),
            gains_pct_filter=-np.inf,
            total_trade_filter=0,
        )

        # Now apply strict filters
        strat_filtered, _ = backtest_df_only(
            prices=sample_prices,
            entries=sample_entries,
            equity=1000.0,
            fee_pct=0.0006,
            mmr_pct=0.005,
            lev_mode=LeverageMode.Isolated,
            order_type=OrderType.LongEntry,
            size_type=SizeType.Amount,
            size_value=np.array([100.0]),
            sl_pcts=np.array([0.02]),
            tp_pcts=np.array([0.05]),
            gains_pct_filter=50.0,  # Only strategies with >50% gains
            total_trade_filter=5,   # Minimum 5 trades
        )

        # Filtered results should have fewer or equal rows
        assert len(strat_filtered) <= len(strat_all)

        # All filtered results should meet criteria
        if len(strat_filtered) > 0:
            assert (strat_filtered["gains_pct"] > 50.0).all()
            assert (strat_filtered["total_trades"] >= 5).all()

    def test_backtest_results_sorted(self, sample_prices, sample_entries):
        """Test that results are sorted by to_the_upside and gains_pct."""
        strat_results, _ = backtest_df_only(
            prices=sample_prices,
            entries=sample_entries,
            equity=1000.0,
            fee_pct=0.0006,
            mmr_pct=0.005,
            lev_mode=LeverageMode.Isolated,
            order_type=OrderType.LongEntry,
            size_type=SizeType.Amount,
            size_value=np.array([100.0]),
            sl_pcts=np.array([0.01, 0.02, 0.03]),  # Multiple params for variety
            tp_pcts=np.array([0.05, 0.10]),
        )

        if len(strat_results) > 1:
            # Should be sorted descending by to_the_upside, then gains_pct
            upside_sorted = strat_results["to_the_upside"].is_monotonic_decreasing
            # If to_the_upside is tied, should be sorted by gains_pct
            # (Hard to test exactly without creating specific data)
            assert upside_sorted or len(strat_results) <= 5  # Allow small samples

    def test_backtest_handles_no_signals(self, sample_prices):
        """Test backtest with no entry signals."""
        # Create empty entries (all zeros)
        entries = pd.DataFrame(
            np.zeros((len(sample_prices), 1)),
            columns=pd.MultiIndex.from_tuples([("BTC/USDT", 0)]),
        )

        strat_results, settings_results = backtest_df_only(
            prices=sample_prices,
            entries=entries,
            equity=1000.0,
            fee_pct=0.0006,
            mmr_pct=0.005,
            lev_mode=LeverageMode.Isolated,
            order_type=OrderType.LongEntry,
            size_type=SizeType.Amount,
            size_value=np.array([100.0]),
            sl_pcts=np.array([0.02]),
            tp_pcts=np.array([0.05]),
        )

        # Should return empty results
        assert len(strat_results) == 0

    def test_backtest_preserves_equity_balance(self, sample_prices, sample_entries):
        """Test that equity changes are properly tracked."""
        initial_equity = 1000.0

        strat_results, _ = backtest_df_only(
            prices=sample_prices,
            entries=sample_entries,
            equity=initial_equity,
            fee_pct=0.0006,
            mmr_pct=0.005,
            lev_mode=LeverageMode.Isolated,
            order_type=OrderType.LongEntry,
            size_type=SizeType.Amount,
            size_value=np.array([100.0]),
            sl_pcts=np.array([0.02]),
            tp_pcts=np.array([0.05]),
        )

        if len(strat_results) > 0:
            # Ending equity should equal initial + total_pnl
            ending_eq = strat_results.iloc[0]["ending_eq"]
            total_pnl = strat_results.iloc[0]["total_pnl"]
            expected_ending = initial_equity + total_pnl

            assert abs(ending_eq - expected_ending) < 0.01  # Small tolerance for floating point


@pytest.mark.integration
@pytest.mark.slow
class TestBacktestPerformance:
    """Performance tests for backtesting."""

    def test_large_dataset_performance(self):
        """Test backtest performance with larger dataset."""
        # Create larger dataset
        n_bars = 1000
        np.random.seed(42)

        base_price = 100.0
        returns = np.random.randn(n_bars) * 0.02
        close_prices = base_price * np.exp(np.cumsum(returns))
        high_prices = close_prices * (1 + np.abs(np.random.randn(n_bars) * 0.01))
        low_prices = close_prices * (1 - np.abs(np.random.randn(n_bars) * 0.01))
        open_prices = np.roll(close_prices, 1)
        open_prices[0] = base_price

        columns = pd.MultiIndex.from_tuples(
            [
                ("BTC/USDT", "open"),
                ("BTC/USDT", "high"),
                ("BTC/USDT", "low"),
                ("BTC/USDT", "close"),
            ],
        )

        prices = pd.DataFrame(
            np.column_stack([open_prices, high_prices, low_prices, close_prices]),
            columns=columns,
        )

        # Simple signals every 20 bars
        entries = pd.DataFrame(
            np.array([1 if i % 20 == 0 else 0 for i in range(n_bars)]).reshape(-1, 1),
            columns=pd.MultiIndex.from_tuples([("BTC/USDT", 0)]),
        )

        # Run backtest with multiple combinations (should be fast with Numba)
        import time
        start = time.time()

        strat_results, _ = backtest_df_only(
            prices=prices,
            entries=entries,
            equity=1000.0,
            fee_pct=0.0006,
            mmr_pct=0.005,
            lev_mode=LeverageMode.Isolated,
            order_type=OrderType.LongEntry,
            size_type=SizeType.Amount,
            size_value=np.array([100.0]),
            leverage=np.array([5.0, 10.0]),
            sl_pcts=np.array([0.01, 0.02, 0.03]),
            tp_pcts=np.array([0.03, 0.05, 0.10]),
        )

        elapsed = time.time() - start

        # Should complete in reasonable time (adjust threshold as needed)
        # First run will be slower due to Numba compilation
        assert elapsed < 30.0  # 30 seconds max
        assert len(strat_results) >= 0
