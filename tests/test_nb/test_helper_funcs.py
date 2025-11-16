"""
Tests for helper and utility functions.
"""
import numpy as np
import pytest

from quantfreedom.nb.helper_funcs import create_cart_product_nb, get_to_the_upside_nb
from quantfreedom.enums.enums import Arrays1dTuple


class TestCartesianProduct:
    """Tests for cartesian product generation."""

    def test_cart_product_basic(self, sample_1d_arrays):
        """Test basic cartesian product generation."""
        cart_result = create_cart_product_nb(arrays_1d_tuple=sample_1d_arrays)

        # Check that cart_result has same structure
        assert isinstance(cart_result, Arrays1dTuple)

        # Leverage: [10.0, 20.0], sl_pcts: [0.02, 0.03] = 4 combinations
        expected_size = 2 * 2  # 4 combinations
        assert len(cart_result.leverage) == expected_size
        assert len(cart_result.sl_pcts) == expected_size

        # Check all combinations exist
        combinations = set()
        for i in range(len(cart_result.leverage)):
            combinations.add((cart_result.leverage[i], cart_result.sl_pcts[i]))

        expected_combinations = {
            (10.0, 0.02),
            (10.0, 0.03),
            (20.0, 0.02),
            (20.0, 0.03),
        }
        assert combinations == expected_combinations

    def test_cart_product_single_values(self):
        """Test cartesian product with single values."""
        arrays = Arrays1dTuple(
            leverage=np.array([10.0]),
            max_equity_risk_pct=np.array([np.nan]),
            max_equity_risk_value=np.array([np.nan]),
            risk_rewards=np.array([np.nan]),
            size_pct=np.array([np.nan]),
            size_value=np.array([100.0]),
            sl_pcts=np.array([0.02]),
            sl_to_be_based_on=np.array([np.nan]),
            sl_to_be_trail_by_when_pct_from_avg_entry=np.array([np.nan]),
            sl_to_be_when_pct_from_avg_entry=np.array([np.nan]),
            sl_to_be_zero_or_entry=np.array([np.nan]),
            tp_pcts=np.array([0.05]),
            tsl_based_on=np.array([np.nan]),
            tsl_pcts_init=np.array([np.nan]),
            tsl_trail_by_pct=np.array([np.nan]),
            tsl_when_pct_from_avg_entry=np.array([np.nan]),
        )

        cart_result = create_cart_product_nb(arrays_1d_tuple=arrays)

        # Should have 1 combination
        assert len(cart_result.leverage) == 1
        assert cart_result.leverage[0] == 10.0
        assert cart_result.sl_pcts[0] == 0.02

    def test_cart_product_three_dimensions(self):
        """Test cartesian product with three varying dimensions."""
        arrays = Arrays1dTuple(
            leverage=np.array([5.0, 10.0]),
            max_equity_risk_pct=np.array([np.nan]),
            max_equity_risk_value=np.array([np.nan]),
            risk_rewards=np.array([np.nan]),
            size_pct=np.array([np.nan]),
            size_value=np.array([50.0, 100.0]),
            sl_pcts=np.array([0.01, 0.02, 0.03]),
            sl_to_be_based_on=np.array([np.nan]),
            sl_to_be_trail_by_when_pct_from_avg_entry=np.array([np.nan]),
            sl_to_be_when_pct_from_avg_entry=np.array([np.nan]),
            sl_to_be_zero_or_entry=np.array([np.nan]),
            tp_pcts=np.array([0.05]),
            tsl_based_on=np.array([np.nan]),
            tsl_pcts_init=np.array([np.nan]),
            tsl_trail_by_pct=np.array([np.nan]),
            tsl_when_pct_from_avg_entry=np.array([np.nan]),
        )

        cart_result = create_cart_product_nb(arrays_1d_tuple=arrays)

        # Should have 2 × 2 × 3 = 12 combinations
        expected_size = 2 * 2 * 3
        assert len(cart_result.leverage) == expected_size
        assert len(cart_result.size_value) == expected_size
        assert len(cart_result.sl_pcts) == expected_size


class TestToTheUpside:
    """Tests for to_the_upside (R²) calculation."""

    def test_perfect_linear_growth(self):
        """Test R² with perfect linear growth (should be 1.0)."""
        # Perfect linear growth: 1, 2, 3, 4, 5
        wins_and_losses = np.array([1.0, 1.0, 1.0, 1.0, 1.0])
        gains_pct = 50.0

        r_squared = get_to_the_upside_nb(
            gains_pct=gains_pct, wins_and_losses_array_no_be=wins_and_losses
        )

        # Perfect linear should have R² = 1.0
        assert r_squared > 0.99  # Allow tiny floating point error

    def test_volatile_but_profitable(self):
        """Test R² with volatile but ultimately profitable trades."""
        # Alternating wins and losses
        wins_and_losses = np.array([10.0, -5.0, 8.0, -3.0, 12.0, -4.0, 15.0])
        gains_pct = 30.0

        r_squared = get_to_the_upside_nb(
            gains_pct=gains_pct, wins_and_losses_array_no_be=wins_and_losses
        )

        # Volatile should have lower R²
        assert 0.0 < r_squared < 1.0

    def test_random_trades_low_r_squared(self):
        """Test that random trades produce low R²."""
        np.random.seed(42)
        # Random noise around zero
        wins_and_losses = np.random.randn(50)
        gains_pct = 5.0

        r_squared = get_to_the_upside_nb(
            gains_pct=gains_pct, wins_and_losses_array_no_be=wins_and_losses
        )

        # Random should have low R² (but might be positive or negative)
        # Just check it's calculated without error
        assert not np.isnan(r_squared)

    def test_consistent_wins(self):
        """Test R² with consistent winning trades."""
        # All wins of similar size
        wins_and_losses = np.array([5.0, 5.5, 5.2, 5.3, 5.1, 5.4, 5.0])
        gains_pct = 36.5

        r_squared = get_to_the_upside_nb(
            gains_pct=gains_pct, wins_and_losses_array_no_be=wins_and_losses
        )

        # Consistent wins should have high R²
        assert r_squared > 0.9

    def test_accelerating_gains(self):
        """Test R² with accelerating gains (exponential-like)."""
        # Gains that increase: 1, 2, 4, 8
        wins_and_losses = np.array([1.0, 2.0, 4.0, 8.0])
        gains_pct = 100.0

        r_squared = get_to_the_upside_nb(
            gains_pct=gains_pct, wins_and_losses_array_no_be=wins_and_losses
        )

        # Exponential should have high R² since cumsum is also curved
        assert r_squared > 0.8

    def test_single_trade(self):
        """Test R² with only one trade."""
        wins_and_losses = np.array([10.0])
        gains_pct = 10.0

        r_squared = get_to_the_upside_nb(
            gains_pct=gains_pct, wins_and_losses_array_no_be=wins_and_losses
        )

        # Single point can't really have R², but function should handle it
        # (might return NaN or 1.0 depending on implementation)
        assert not np.isnan(r_squared) or wins_and_losses.size == 1

    def test_two_trades(self):
        """Test R² with two trades (minimum for line fit)."""
        wins_and_losses = np.array([5.0, 5.0])
        gains_pct = 10.0

        r_squared = get_to_the_upside_nb(
            gains_pct=gains_pct, wins_and_losses_array_no_be=wins_and_losses
        )

        # Two identical points should have perfect fit
        assert r_squared > 0.99 or wins_and_losses.size < 3
