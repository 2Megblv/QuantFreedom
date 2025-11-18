"""
Tests for short position (sell) functions.
"""
import numpy as np
import pytest

from quantfreedom.nb.sell_funcs import short_decrease_nb, short_increase_nb
from quantfreedom.enums.enums import (
    AccountState,
    EntryOrder,
    OrderResult,
    OrderStatus,
    OrderType,
    SizeType,
    StaticVariables,
)


class TestShortIncreaseNb:
    """Tests for short_increase_nb function."""

    def test_basic_short_entry_fixed_amount(self, basic_account_state, short_entry_order, empty_order_result, basic_static_variables):
        """Test basic short entry with fixed position size."""
        price = 100.0

        # Modify static variables for short
        static_vars = StaticVariables(
            divide_records_array_size_by=1.0,
            fee_pct=0.0006,
            lev_mode=0,
            max_lev=100.0,
            max_order_size_pct=100.0,
            max_order_size_value=np.inf,
            min_order_size_pct=0.01,
            min_order_size_value=1.0,
            mmr_pct=0.005,
            order_type=OrderType.ShortEntry,  # Short order type
            size_type=SizeType.Amount,
            sl_to_be_then_trail=False,
            sl_to_be=False,
            tsl_true_or_false=False,
            upside_filter=-1.0,
        )

        account_state_new, order_result_new = short_increase_nb(
            price=price,
            account_state=basic_account_state,
            entry_order=short_entry_order,
            order_result=empty_order_result,
            static_variables_tuple=static_vars,
        )

        # Check order was filled
        assert order_result_new.order_status == OrderStatus.Filled
        assert order_result_new.position > 0
        assert order_result_new.average_entry == price

        # Check fees were deducted
        assert order_result_new.fees_paid > 0
        expected_fee = short_entry_order.size_value * price * static_vars.fee_pct
        assert abs(order_result_new.fees_paid - expected_fee) < 0.01

        # Check available balance decreased
        assert account_state_new.available_balance < basic_account_state.available_balance

    def test_short_entry_with_stop_loss(self, basic_account_state, short_entry_order, empty_order_result):
        """Test short entry with stop loss set (above entry for shorts)."""
        price = 100.0

        static_vars = StaticVariables(
            divide_records_array_size_by=1.0,
            fee_pct=0.0006,
            lev_mode=0,
            max_lev=100.0,
            max_order_size_pct=100.0,
            max_order_size_value=np.inf,
            min_order_size_pct=0.01,
            min_order_size_value=1.0,
            mmr_pct=0.005,
            order_type=OrderType.ShortEntry,
            size_type=SizeType.Amount,
            sl_to_be_then_trail=False,
            sl_to_be=False,
            tsl_true_or_false=False,
            upside_filter=-1.0,
        )

        account_state_new, order_result_new = short_increase_nb(
            price=price,
            account_state=basic_account_state,
            entry_order=short_entry_order,
            order_result=empty_order_result,
            static_variables_tuple=static_vars,
        )

        # Check stop loss price is set (ABOVE entry for shorts)
        assert order_result_new.sl_prices > 0
        expected_sl = price * (1 + short_entry_order.sl_pcts)  # ABOVE for shorts
        assert abs(order_result_new.sl_prices - expected_sl) < 0.01

        # Check SL percentage is stored
        assert order_result_new.sl_pcts == short_entry_order.sl_pcts

    def test_short_entry_with_take_profit(self, basic_account_state, short_entry_order, empty_order_result):
        """Test short entry with take profit set (below entry for shorts)."""
        price = 100.0

        static_vars = StaticVariables(
            divide_records_array_size_by=1.0,
            fee_pct=0.0006,
            lev_mode=0,
            max_lev=100.0,
            max_order_size_pct=100.0,
            max_order_size_value=np.inf,
            min_order_size_pct=0.01,
            min_order_size_value=1.0,
            mmr_pct=0.005,
            order_type=OrderType.ShortEntry,
            size_type=SizeType.Amount,
            sl_to_be_then_trail=False,
            sl_to_be=False,
            tsl_true_or_false=False,
            upside_filter=-1.0,
        )

        account_state_new, order_result_new = short_increase_nb(
            price=price,
            account_state=basic_account_state,
            entry_order=short_entry_order,
            order_result=empty_order_result,
            static_variables_tuple=static_vars,
        )

        # Check take profit price is set (BELOW entry for shorts)
        assert order_result_new.tp_prices > 0
        expected_tp = price * (1 - short_entry_order.tp_pcts)  # BELOW for shorts
        assert abs(order_result_new.tp_prices - expected_tp) < 0.01

    def test_short_entry_risk_based_sizing(self, basic_account_state, empty_order_result):
        """Test position sizing based on risk percentage for shorts."""
        # Create risk-based short entry order
        entry_order = EntryOrder(
            leverage=10.0,
            max_equity_risk_pct=np.nan,
            max_equity_risk_value=np.nan,
            order_type=OrderType.ShortEntry,
            risk_rewards=np.nan,
            size_pct=0.01,  # Risk 1% of equity
            size_value=np.nan,
            sl_pcts=0.02,  # 2% stop loss
            tp_pcts=0.05,
            tsl_pcts_init=np.nan,
        )

        static_vars = StaticVariables(
            divide_records_array_size_by=1.0,
            fee_pct=0.0006,
            lev_mode=0,
            max_lev=100.0,
            max_order_size_pct=100.0,
            max_order_size_value=np.inf,
            min_order_size_pct=0.01,
            min_order_size_value=1.0,
            mmr_pct=0.005,
            order_type=OrderType.ShortEntry,
            size_type=SizeType.RiskPercentOfAccount,  # Risk-based sizing
            sl_to_be_then_trail=False,
            sl_to_be=False,
            tsl_true_or_false=False,
            upside_filter=-1.0,
        )

        price = 100.0

        account_state_new, order_result_new = short_increase_nb(
            price=price,
            account_state=basic_account_state,
            entry_order=entry_order,
            order_result=empty_order_result,
            static_variables_tuple=static_vars,
        )

        # Position size should be calculated to risk exactly 1% of equity
        expected_size_approx = (basic_account_state.equity * entry_order.size_pct) / entry_order.sl_pcts
        assert order_result_new.size_value > 0
        # Allow some tolerance for fee calculations
        assert abs(order_result_new.size_value - expected_size_approx) / expected_size_approx < 0.1

    def test_short_entry_with_leverage(self, basic_account_state, empty_order_result):
        """Test that leverage is properly recorded for shorts."""
        entry_order = EntryOrder(
            leverage=20.0,  # 20x leverage
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

        static_vars = StaticVariables(
            divide_records_array_size_by=1.0,
            fee_pct=0.0006,
            lev_mode=0,
            max_lev=100.0,
            max_order_size_pct=100.0,
            max_order_size_value=np.inf,
            min_order_size_pct=0.01,
            min_order_size_value=1.0,
            mmr_pct=0.005,
            order_type=OrderType.ShortEntry,
            size_type=SizeType.Amount,
            sl_to_be_then_trail=False,
            sl_to_be=False,
            tsl_true_or_false=False,
            upside_filter=-1.0,
        )

        price = 100.0

        account_state_new, order_result_new = short_increase_nb(
            price=price,
            account_state=basic_account_state,
            entry_order=entry_order,
            order_result=empty_order_result,
            static_variables_tuple=static_vars,
        )

        # Leverage should be recorded in result
        assert order_result_new.leverage == 20.0

    def test_short_direction_opposite_to_long(self, basic_account_state, short_entry_order, empty_order_result):
        """Test that short stop loss and take profit are in opposite direction to longs."""
        price = 100.0
        sl_pct = 0.02
        tp_pct = 0.05

        entry_order = EntryOrder(
            leverage=10.0,
            max_equity_risk_pct=np.nan,
            max_equity_risk_value=np.nan,
            order_type=OrderType.ShortEntry,
            risk_rewards=np.nan,
            size_pct=np.nan,
            size_value=100.0,
            sl_pcts=sl_pct,
            tp_pcts=tp_pct,
            tsl_pcts_init=np.nan,
        )

        static_vars = StaticVariables(
            divide_records_array_size_by=1.0,
            fee_pct=0.0006,
            lev_mode=0,
            max_lev=100.0,
            max_order_size_pct=100.0,
            max_order_size_value=np.inf,
            min_order_size_pct=0.01,
            min_order_size_value=1.0,
            mmr_pct=0.005,
            order_type=OrderType.ShortEntry,
            size_type=SizeType.Amount,
            sl_to_be_then_trail=False,
            sl_to_be=False,
            tsl_true_or_false=False,
            upside_filter=-1.0,
        )

        account_state_new, order_result_new = short_increase_nb(
            price=price,
            account_state=basic_account_state,
            entry_order=entry_order,
            order_result=empty_order_result,
            static_variables_tuple=static_vars,
        )

        # For shorts: SL is ABOVE entry, TP is BELOW entry (opposite of longs)
        assert order_result_new.sl_prices > price  # SL above entry
        assert order_result_new.tp_prices < price  # TP below entry


class TestShortDecreaseNb:
    """Tests for short_decrease_nb function."""

    def test_basic_short_exit_with_profit(self, basic_account_state):
        """Test basic short position exit with profit (price decreased)."""
        # Create an open short position
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.6,  # Already paid on entry
            leverage=10.0,
            liq_price=110.0,  # Liq above entry for shorts
            moved_sl_to_be=False,
            order_status=OrderStatus.Filled,
            order_status_info=0,
            order_type=OrderType.ShortTP,  # Exiting via take profit
            pct_chg_trade=0.0,
            position=1.0,  # 1 unit position
            price=95.0,  # Exit at $95 (5% profit for short)
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=102.0,  # SL above entry for shorts
            tp_pcts=0.05,
            tp_prices=95.0,  # TP below entry for shorts
            tsl_pcts_init=0.0,
            tsl_prices=np.inf,
        )

        fee_pct = 0.0006

        account_state_new, order_result_new = short_decrease_nb(
            order_result=order_result,
            account_state=basic_account_state,
            fee_pct=fee_pct,
        )

        # Check position is closed
        assert order_result_new.position == 0.0

        # Check realized PnL is positive (took profit)
        # For short: entry at 100, exit at 95 = 5 profit per unit
        assert order_result_new.realized_pnl > 0

        # Available balance should increase
        assert account_state_new.available_balance > basic_account_state.available_balance

    def test_short_exit_with_loss(self, basic_account_state):
        """Test short position exit with a loss (price increased - hit stop loss)."""
        # Create an open short position that hit stop loss
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.6,
            leverage=10.0,
            liq_price=110.0,
            moved_sl_to_be=False,
            order_status=OrderStatus.Filled,
            order_status_info=0,
            order_type=OrderType.ShortSL,  # Exiting via stop loss
            pct_chg_trade=0.0,
            position=1.0,
            price=102.0,  # Exit at $102 (2% loss for short)
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=102.0,
            tp_pcts=0.05,
            tp_prices=95.0,
            tsl_pcts_init=0.0,
            tsl_prices=np.inf,
        )

        fee_pct = 0.0006

        account_state_new, order_result_new = short_decrease_nb(
            order_result=order_result,
            account_state=basic_account_state,
            fee_pct=fee_pct,
        )

        # Check realized PnL is negative (stopped out)
        # For short: entry at 100, exit at 102 = -2 loss per unit
        assert order_result_new.realized_pnl < 0

        # Loss should be approximately (100 - 102) * 1.0 - fees
        expected_loss = (order_result.average_entry - order_result.price) * order_result.position - order_result.fees_paid - (order_result.price * order_result.position * fee_pct)
        assert abs(order_result_new.realized_pnl - expected_loss) < 0.01

    def test_short_pnl_opposite_to_long(self, basic_account_state):
        """Test that short PnL calculation is opposite to long."""
        # Short profits when price goes DOWN
        order_result_profit = OrderResult(
            average_entry=100.0,
            fees_paid=0.6,
            leverage=10.0,
            liq_price=110.0,
            moved_sl_to_be=False,
            order_status=OrderStatus.Filled,
            order_status_info=0,
            order_type=OrderType.ShortTP,
            pct_chg_trade=0.0,
            position=1.0,
            price=90.0,  # Price dropped 10%
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=102.0,
            tp_pcts=0.10,
            tp_prices=90.0,
            tsl_pcts_init=0.0,
            tsl_prices=np.inf,
        )

        fee_pct = 0.0006

        account_state_new, order_result_new = short_decrease_nb(
            order_result=order_result_profit,
            account_state=basic_account_state,
            fee_pct=fee_pct,
        )

        # Short should profit when price drops
        # Entry 100, exit 90 = +10 profit (opposite of long)
        assert order_result_new.realized_pnl > 8  # After fees

    def test_short_liquidation_exit(self, basic_account_state):
        """Test short position liquidation (price rises to liq price)."""
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.6,
            leverage=10.0,
            liq_price=110.0,  # Liquidation at $110
            moved_sl_to_be=False,
            order_status=OrderStatus.Filled,
            order_status_info=0,
            order_type=OrderType.ShortLiq,  # Liquidation
            pct_chg_trade=0.0,
            position=1.0,
            price=110.0,  # Liquidated at liq price
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=102.0,
            tp_pcts=0.05,
            tp_prices=95.0,
            tsl_pcts_init=0.0,
            tsl_prices=np.inf,
        )

        fee_pct = 0.0006

        account_state_new, order_result_new = short_decrease_nb(
            order_result=order_result,
            account_state=basic_account_state,
            fee_pct=fee_pct,
        )

        # Liquidation should result in significant loss
        assert order_result_new.realized_pnl < -8  # Substantial loss
        assert order_result_new.position == 0.0  # Position closed
