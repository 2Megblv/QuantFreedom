"""
Tests for evaluator functions.
"""
import numpy as np
import pandas as pd
import pytest

from quantfreedom.evaluators.evaluators import is_above, is_below


class TestIsAbove:
    """Tests for is_above evaluator."""

    def test_simple_above_threshold(self):
        """Test basic above threshold evaluation."""
        # Create simple price data
        data = pd.DataFrame({
            ('BTC/USDT', 'close'): [100, 105, 110, 95, 100]
        })
        data.columns = pd.MultiIndex.from_tuples(data.columns)

        # Test: price above 102
        result = is_above(
            indicator_data=data,
            compare_against_value=102.0,
            comparison_col_name="close",
        )

        # Should be True when price > 102
        expected = pd.DataFrame({
            ('BTC/USDT', 0): [False, True, True, False, False]
        })
        expected.columns = pd.MultiIndex.from_tuples(expected.columns)

        pd.testing.assert_frame_equal(result.astype(int), expected.astype(int))

    def test_above_with_array(self):
        """Test above with array of thresholds."""
        data = pd.DataFrame({
            ('BTC/USDT', 'close'): [100, 105, 110, 95, 100]
        })
        data.columns = pd.MultiIndex.from_tuples(data.columns)

        # Test with multiple thresholds
        result = is_above(
            indicator_data=data,
            compare_against_value=np.array([100, 105]),
            comparison_col_name="close",
        )

        # Should create two columns (one per threshold)
        assert result.shape[1] == 2

    def test_above_boundary_case(self):
        """Test exact boundary (should not be above itself)."""
        data = pd.DataFrame({
            ('BTC/USDT', 'close'): [100.0]
        })
        data.columns = pd.MultiIndex.from_tuples(data.columns)

        result = is_above(
            indicator_data=data,
            compare_against_value=100.0,
            comparison_col_name="close",
        )

        # Exactly equal should be False (not above)
        assert result.iloc[0, 0] == False


class TestIsBelow:
    """Tests for is_below evaluator."""

    def test_simple_below_threshold(self):
        """Test basic below threshold evaluation."""
        data = pd.DataFrame({
            ('BTC/USDT', 'close'): [100, 105, 110, 95, 100]
        })
        data.columns = pd.MultiIndex.from_tuples(data.columns)

        # Test: price below 102
        result = is_below(
            indicator_data=data,
            compare_against_value=102.0,
            comparison_col_name="close",
        )

        # Should be True when price < 102
        expected = pd.DataFrame({
            ('BTC/USDT', 0): [True, False, False, True, True]
        })
        expected.columns = pd.MultiIndex.from_tuples(expected.columns)

        pd.testing.assert_frame_equal(result.astype(int), expected.astype(int))

    def test_below_with_array(self):
        """Test below with array of thresholds."""
        data = pd.DataFrame({
            ('BTC/USDT', 'close'): [100, 105, 110, 95, 100]
        })
        data.columns = pd.MultiIndex.from_tuples(data.columns)

        # Test with multiple thresholds
        result = is_below(
            indicator_data=data,
            compare_against_value=np.array([100, 105]),
            comparison_col_name="close",
        )

        # Should create two columns (one per threshold)
        assert result.shape[1] == 2

    def test_below_boundary_case(self):
        """Test exact boundary (should not be below itself)."""
        data = pd.DataFrame({
            ('BTC/USDT', 'close'): [100.0]
        })
        data.columns = pd.MultiIndex.from_tuples(data.columns)

        result = is_below(
            indicator_data=data,
            compare_against_value=100.0,
            comparison_col_name="close",
        )

        # Exactly equal should be False (not below)
        assert result.iloc[0, 0] == False

    def test_below_with_nan_handling(self):
        """Test that NaN values are handled properly."""
        data = pd.DataFrame({
            ('BTC/USDT', 'close'): [100, np.nan, 110, 95, 100]
        })
        data.columns = pd.MultiIndex.from_tuples(data.columns)

        result = is_below(
            indicator_data=data,
            compare_against_value=102.0,
            comparison_col_name="close",
        )

        # NaN should result in False (or be handled gracefully)
        assert result.shape[0] == 5


class TestEvaluatorComparison:
    """Tests comparing is_above and is_below."""

    def test_above_and_below_are_complementary(self):
        """Test that above and below are complementary (except for equal case)."""
        data = pd.DataFrame({
            ('BTC/USDT', 'close'): [95, 100, 105]
        })
        data.columns = pd.MultiIndex.from_tuples(data.columns)

        above = is_above(data, 100.0, "close")
        below = is_below(data, 100.0, "close")

        # For 95: not above, is below
        assert above.iloc[0, 0] == False
        assert below.iloc[0, 0] == True

        # For 100: not above, not below (equal)
        assert above.iloc[1, 0] == False
        assert below.iloc[1, 0] == False

        # For 105: is above, not below
        assert above.iloc[2, 0] == True
        assert below.iloc[2, 0] == False
