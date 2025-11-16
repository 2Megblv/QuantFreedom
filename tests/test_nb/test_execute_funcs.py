"""
Tests for order execution and stop loss/take profit checking functions.
"""
import numpy as np
import pytest

from quantfreedom.nb.execute_funcs import check_sl_tp_nb
from quantfreedom.enums.enums import (
    AccountState,
    OrderResult,
    OrderType,
    SL_BE_or_Trail_BasedOn,
    StopsOrder,
)


class TestCheckSlTpNb:
    """Tests for check_sl_tp_nb function."""

    def test_long_stop_loss_triggered(self, basic_account_state, basic_stops_order):
        """Test that long stop loss is triggered when price drops."""
        # Create open long position
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.0,
            leverage=10.0,
            liq_price=90.0,
            moved_sl_to_be=False,
            order_status=0,
            order_status_info=0,
            order_type=OrderType.LongEntry,
            pct_chg_trade=0.0,
            position=1.0,
            price=100.0,
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=98.0,  # Stop loss at $98
            tp_pcts=0.05,
            tp_prices=105.0,
            tsl_pcts_init=0.0,
            tsl_prices=np.inf,  # No trailing stop
        )

        # Candle where low price hits stop loss
        high_price = 101.0
        low_price = 97.0  # Touches SL at 98
        open_price = 100.5
        close_price = 99.0

        result = check_sl_tp_nb(
            high_price=high_price,
            low_price=low_price,
            open_price=open_price,
            close_price=close_price,
            order_settings_counter=0,
            entry_type=OrderType.LongEntry,
            fee_pct=0.0006,
            bar=10,
            account_state=basic_account_state,
            order_result=order_result,
            stops_order=basic_stops_order,
        )

        # Should trigger stop loss
        assert result.order_type == OrderType.LongSL
        assert result.price == order_result.sl_prices
        assert not np.isnan(result.size_value)  # Size should be set for exit

    def test_long_take_profit_triggered(self, basic_account_state, basic_stops_order):
        """Test that long take profit is triggered when price rises."""
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.0,
            leverage=10.0,
            liq_price=90.0,
            moved_sl_to_be=False,
            order_status=0,
            order_status_info=0,
            order_type=OrderType.LongEntry,
            pct_chg_trade=0.0,
            position=1.0,
            price=100.0,
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=98.0,
            tp_pcts=0.05,
            tp_prices=105.0,  # Take profit at $105
            tsl_pcts_init=0.0,
            tsl_prices=np.inf,
        )

        # Candle where high price hits take profit
        high_price = 106.0  # Touches TP at 105
        low_price = 102.0
        open_price = 103.0
        close_price = 105.0

        result = check_sl_tp_nb(
            high_price=high_price,
            low_price=low_price,
            open_price=open_price,
            close_price=close_price,
            order_settings_counter=0,
            entry_type=OrderType.LongEntry,
            fee_pct=0.0006,
            bar=10,
            account_state=basic_account_state,
            order_result=order_result,
            stops_order=basic_stops_order,
        )

        # Should trigger take profit
        assert result.order_type == OrderType.LongTP
        assert result.price == order_result.tp_prices

    def test_long_liquidation_triggered(self, basic_account_state, basic_stops_order):
        """Test that long liquidation is triggered when price drops to liq price."""
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.0,
            leverage=10.0,
            liq_price=90.0,  # Liquidation at $90
            moved_sl_to_be=False,
            order_status=0,
            order_status_info=0,
            order_type=OrderType.LongEntry,
            pct_chg_trade=0.0,
            position=1.0,
            price=100.0,
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=98.0,
            tp_pcts=0.05,
            tp_prices=105.0,
            tsl_pcts_init=0.0,
            tsl_prices=np.inf,
        )

        # Candle where price drops to liquidation
        high_price = 95.0
        low_price = 89.0  # Touches liquidation at 90
        open_price = 93.0
        close_price = 91.0

        result = check_sl_tp_nb(
            high_price=high_price,
            low_price=low_price,
            open_price=open_price,
            close_price=close_price,
            order_settings_counter=0,
            entry_type=OrderType.LongEntry,
            fee_pct=0.0006,
            bar=10,
            account_state=basic_account_state,
            order_result=order_result,
            stops_order=basic_stops_order,
        )

        # Should trigger liquidation
        assert result.order_type == OrderType.LongLiq
        assert result.price == order_result.liq_price

    def test_long_break_even_move(self, basic_account_state):
        """Test moving stop loss to break even when profit threshold met."""
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.0,
            leverage=10.0,
            liq_price=90.0,
            moved_sl_to_be=False,  # Haven't moved to BE yet
            order_status=0,
            order_status_info=0,
            order_type=OrderType.LongEntry,
            pct_chg_trade=0.0,
            position=1.0,
            price=100.0,
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=98.0,
            tp_pcts=0.10,
            tp_prices=110.0,
            tsl_pcts_init=0.0,
            tsl_prices=np.inf,
        )

        # Enable break even at 5% profit
        stops_order = StopsOrder(
            sl_to_be=True,
            sl_to_be_based_on=SL_BE_or_Trail_BasedOn.close_price,
            sl_to_be_then_trail=False,
            sl_to_be_trail_by_when_pct_from_avg_entry=np.nan,
            sl_to_be_when_pct_from_avg_entry=0.05,  # Move to BE at 5% profit
            sl_to_be_zero_or_entry=0,  # 0 = zero loss (accounting for fees)
            tsl_based_on=np.nan,
            tsl_trail_by_pct=np.nan,
            tsl_true_or_false=False,
            tsl_when_pct_from_avg_entry=np.nan,
        )

        # Price reaches 5% profit
        high_price = 106.0
        low_price = 104.0
        open_price = 104.5
        close_price = 105.0  # Close at 5% profit

        result = check_sl_tp_nb(
            high_price=high_price,
            low_price=low_price,
            open_price=open_price,
            close_price=close_price,
            order_settings_counter=0,
            entry_type=OrderType.LongEntry,
            fee_pct=0.0006,
            bar=10,
            account_state=basic_account_state,
            order_result=order_result,
            stops_order=stops_order,
        )

        # Should move SL to break even
        assert result.moved_sl_to_be == True
        assert result.sl_prices > order_result.sl_prices  # SL moved up
        assert result.sl_prices >= order_result.average_entry  # At or above entry

    def test_trailing_stop_loss_activation(self, basic_account_state):
        """Test trailing stop loss activation and movement."""
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.0,
            leverage=10.0,
            liq_price=90.0,
            moved_sl_to_be=False,
            order_status=0,
            order_status_info=0,
            order_type=OrderType.LongEntry,
            pct_chg_trade=0.0,
            position=1.0,
            price=100.0,
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=98.0,
            tp_pcts=0.10,
            tp_prices=110.0,
            tsl_pcts_init=0.02,
            tsl_prices=98.0,  # Initial TSL same as SL
        )

        # Enable trailing stop
        stops_order = StopsOrder(
            sl_to_be=False,
            sl_to_be_based_on=np.nan,
            sl_to_be_then_trail=False,
            sl_to_be_trail_by_when_pct_from_avg_entry=np.nan,
            sl_to_be_when_pct_from_avg_entry=np.nan,
            sl_to_be_zero_or_entry=np.nan,
            tsl_based_on=SL_BE_or_Trail_BasedOn.high_price,
            tsl_trail_by_pct=0.01,  # Trail 1% from high
            tsl_true_or_false=True,
            tsl_when_pct_from_avg_entry=0.03,  # Start trailing at 3% profit
        )

        # Price reaches 5% profit (above 3% threshold)
        high_price = 105.0  # 5% profit
        low_price = 103.0
        open_price = 103.5
        close_price = 104.0

        result = check_sl_tp_nb(
            high_price=high_price,
            low_price=low_price,
            open_price=open_price,
            close_price=close_price,
            order_settings_counter=0,
            entry_type=OrderType.LongEntry,
            fee_pct=0.0006,
            bar=10,
            account_state=basic_account_state,
            order_result=order_result,
            stops_order=stops_order,
        )

        # TSL should have moved up
        expected_tsl = high_price * (1 - stops_order.tsl_trail_by_pct)  # 105 * 0.99 = 103.95
        assert result.tsl_prices > order_result.tsl_prices  # TSL moved up
        assert abs(result.tsl_prices - expected_tsl) < 0.01

    def test_short_stop_loss_triggered(self, basic_account_state, basic_stops_order):
        """Test that short stop loss is triggered when price rises."""
        # Create open short position
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.0,
            leverage=10.0,
            liq_price=110.0,  # Liq above entry for shorts
            moved_sl_to_be=False,
            order_status=0,
            order_status_info=0,
            order_type=OrderType.ShortEntry,
            pct_chg_trade=0.0,
            position=1.0,
            price=100.0,
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=102.0,  # Stop loss at $102 for short
            tp_pcts=0.05,
            tp_prices=95.0,  # TP below entry for short
            tsl_pcts_init=0.0,
            tsl_prices=0.0,  # No trailing stop
        )

        # Candle where high price hits stop loss
        high_price = 103.0  # Touches SL at 102
        low_price = 99.0
        open_price = 100.5
        close_price = 101.0

        result = check_sl_tp_nb(
            high_price=high_price,
            low_price=low_price,
            open_price=open_price,
            close_price=close_price,
            order_settings_counter=0,
            entry_type=OrderType.ShortEntry,
            fee_pct=0.0006,
            bar=10,
            account_state=basic_account_state,
            order_result=order_result,
            stops_order=basic_stops_order,
        )

        # Should trigger stop loss
        assert result.order_type == OrderType.ShortSL
        assert result.price == order_result.sl_prices

    def test_short_take_profit_triggered(self, basic_account_state, basic_stops_order):
        """Test that short take profit is triggered when price drops."""
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.0,
            leverage=10.0,
            liq_price=110.0,
            moved_sl_to_be=False,
            order_status=0,
            order_status_info=0,
            order_type=OrderType.ShortEntry,
            pct_chg_trade=0.0,
            position=1.0,
            price=100.0,
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=102.0,
            tp_pcts=0.05,
            tp_prices=95.0,  # TP at $95
            tsl_pcts_init=0.0,
            tsl_prices=0.0,
        )

        # Candle where low price hits take profit
        high_price = 98.0
        low_price = 94.0  # Touches TP at 95
        open_price = 97.0
        close_price = 95.0

        result = check_sl_tp_nb(
            high_price=high_price,
            low_price=low_price,
            open_price=open_price,
            close_price=close_price,
            order_settings_counter=0,
            entry_type=OrderType.ShortEntry,
            fee_pct=0.0006,
            bar=10,
            account_state=basic_account_state,
            order_result=order_result,
            stops_order=basic_stops_order,
        )

        # Should trigger take profit
        assert result.order_type == OrderType.ShortTP
        assert result.price == order_result.tp_prices

    def test_priority_order_liquidation_first(self, basic_account_state, basic_stops_order):
        """Test that liquidation has highest priority over SL/TP."""
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.0,
            leverage=10.0,
            liq_price=90.0,
            moved_sl_to_be=False,
            order_status=0,
            order_status_info=0,
            order_type=OrderType.LongEntry,
            pct_chg_trade=0.0,
            position=1.0,
            price=100.0,
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=98.0,
            tp_pcts=0.05,
            tp_prices=105.0,
            tsl_pcts_init=0.0,
            tsl_prices=np.inf,
        )

        # Candle where both liquidation and SL would trigger
        # Liquidation should take priority
        high_price = 100.0
        low_price = 85.0  # Hits both liq (90) and SL (98)
        open_price = 98.0
        close_price = 88.0

        result = check_sl_tp_nb(
            high_price=high_price,
            low_price=low_price,
            open_price=open_price,
            close_price=close_price,
            order_settings_counter=0,
            entry_type=OrderType.LongEntry,
            fee_pct=0.0006,
            bar=10,
            account_state=basic_account_state,
            order_result=order_result,
            stops_order=basic_stops_order,
        )

        # Liquidation should trigger (highest priority)
        assert result.order_type == OrderType.LongLiq
        assert result.price == order_result.liq_price
