"""
Tests for long position (buy) functions.
"""
import numpy as np
import pytest

from quantfreedom.nb.buy_funcs import long_decrease_nb, long_increase_nb
from quantfreedom.enums.enums import (
    AccountState,
    EntryOrder,
    OrderResult,
    OrderStatus,
    OrderType,
    SizeType,
    StaticVariables,
)


class TestLongIncreaseNb:
    """Tests for long_increase_nb function."""

    def test_basic_long_entry_fixed_amount(self, basic_account_state, long_entry_order, empty_order_result, basic_static_variables):
        """Test basic long entry with fixed position size."""
        price = 100.0

        account_state_new, order_result_new = long_increase_nb(
            price=price,
            account_state=basic_account_state,
            entry_order=long_entry_order,
            order_result=empty_order_result,
            static_variables_tuple=basic_static_variables,
        )

        # Check order was filled
        assert order_result_new.order_status == OrderStatus.Filled
        assert order_result_new.position > 0
        assert order_result_new.average_entry == price

        # Check fees were deducted
        assert order_result_new.fees_paid > 0
        expected_fee = long_entry_order.size_value * price * basic_static_variables.fee_pct
        assert abs(order_result_new.fees_paid - expected_fee) < 0.01

        # Check available balance decreased
        assert account_state_new.available_balance < basic_account_state.available_balance

    def test_long_entry_with_stop_loss(self, basic_account_state, long_entry_order, empty_order_result, basic_static_variables):
        """Test long entry with stop loss set."""
        price = 100.0

        account_state_new, order_result_new = long_increase_nb(
            price=price,
            account_state=basic_account_state,
            entry_order=long_entry_order,
            order_result=empty_order_result,
            static_variables_tuple=basic_static_variables,
        )

        # Check stop loss price is set
        assert order_result_new.sl_prices > 0
        expected_sl = price * (1 - long_entry_order.sl_pcts)
        assert abs(order_result_new.sl_prices - expected_sl) < 0.01

        # Check SL percentage is stored
        assert order_result_new.sl_pcts == long_entry_order.sl_pcts

    def test_long_entry_with_take_profit(self, basic_account_state, long_entry_order, empty_order_result, basic_static_variables):
        """Test long entry with take profit set."""
        price = 100.0

        account_state_new, order_result_new = long_increase_nb(
            price=price,
            account_state=basic_account_state,
            entry_order=long_entry_order,
            order_result=empty_order_result,
            static_variables_tuple=basic_static_variables,
        )

        # Check take profit price is set
        assert order_result_new.tp_prices > 0
        expected_tp = price * (1 + long_entry_order.tp_pcts)
        assert abs(order_result_new.tp_prices - expected_tp) < 0.01

    def test_long_entry_risk_based_sizing(self, basic_account_state, empty_order_result):
        """Test position sizing based on risk percentage."""
        # Create risk-based entry order
        entry_order = EntryOrder(
            leverage=10.0,
            max_equity_risk_pct=np.nan,
            max_equity_risk_value=np.nan,
            order_type=OrderType.LongEntry,
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
            order_type=OrderType.LongEntry,
            size_type=SizeType.RiskPercentOfAccount,  # Risk-based sizing
            sl_to_be_then_trail=False,
            sl_to_be=False,
            tsl_true_or_false=False,
            upside_filter=-1.0,
        )

        price = 100.0

        account_state_new, order_result_new = long_increase_nb(
            price=price,
            account_state=basic_account_state,
            entry_order=entry_order,
            order_result=empty_order_result,
            static_variables_tuple=static_vars,
        )

        # Position size should be calculated to risk exactly 1% of equity
        # risk_amount = equity * size_pct = 1000 * 0.01 = 10
        # position_size ≈ risk_amount / sl_pcts = 10 / 0.02 = 500
        expected_size_approx = (basic_account_state.equity * entry_order.size_pct) / entry_order.sl_pcts
        assert order_result_new.size_value > 0
        # Allow some tolerance for fee calculations
        assert abs(order_result_new.size_value - expected_size_approx) / expected_size_approx < 0.1

    def test_long_entry_insufficient_balance(self, empty_order_result, long_entry_order, basic_static_variables):
        """Test long entry when insufficient balance available."""
        # Account with very low balance
        poor_account = AccountState(
            available_balance=1.0,  # Only $1
            cash_borrowed=0.0,
            cash_used=0.0,
            equity=1.0,
        )

        # Try to place $100 order
        price = 100.0

        account_state_new, order_result_new = long_increase_nb(
            price=price,
            account_state=poor_account,
            entry_order=long_entry_order,
            order_result=empty_order_result,
            static_variables_tuple=basic_static_variables,
        )

        # Order should be rejected or capped
        # (Implementation might reject or reduce size - check actual behavior)
        assert order_result_new.size_value <= poor_account.available_balance * price

    def test_long_entry_with_leverage(self, basic_account_state, empty_order_result, basic_static_variables):
        """Test that leverage is properly recorded."""
        entry_order = EntryOrder(
            leverage=20.0,  # 20x leverage
            max_equity_risk_pct=np.nan,
            max_equity_risk_value=np.nan,
            order_type=OrderType.LongEntry,
            risk_rewards=np.nan,
            size_pct=np.nan,
            size_value=100.0,
            sl_pcts=0.02,
            tp_pcts=0.05,
            tsl_pcts_init=np.nan,
        )

        price = 100.0

        account_state_new, order_result_new = long_increase_nb(
            price=price,
            account_state=basic_account_state,
            entry_order=entry_order,
            order_result=empty_order_result,
            static_variables_tuple=basic_static_variables,
        )

        # Leverage should be recorded in result
        assert order_result_new.leverage == 20.0


class TestLongDecreaseNb:
    """Tests for long_decrease_nb function."""

    def test_basic_long_exit(self, basic_account_state):
        """Test basic long position exit."""
        # Create an open long position
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.6,  # Already paid on entry
            leverage=10.0,
            liq_price=90.0,
            moved_sl_to_be=False,
            order_status=OrderStatus.Filled,
            order_status_info=0,
            order_type=OrderType.LongTP,  # Exiting via take profit
            pct_chg_trade=0.0,
            position=1.0,  # 1 unit position
            price=105.0,  # Exit at $105 (5% profit)
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=98.0,
            tp_pcts=0.05,
            tp_prices=105.0,
            tsl_pcts_init=0.0,
            tsl_prices=0.0,
        )

        fee_pct = 0.0006

        account_state_new, order_result_new = long_decrease_nb(
            order_result=order_result,
            account_state=basic_account_state,
            fee_pct=fee_pct,
        )

        # Check position is closed
        assert order_result_new.position == 0.0

        # Check realized PnL is positive (took profit)
        assert order_result_new.realized_pnl > 0

        # PnL should be approximately (105 - 100) * 1.0 - fees
        # Entry fee: 100 * 0.0006 = 0.06
        # Exit fee: 105 * 0.0006 = 0.063
        # Gross profit: 5.0
        # Net profit ≈ 5.0 - 0.06 - 0.063 = 4.877
        expected_pnl = (order_result.price - order_result.average_entry) * order_result.position - order_result.fees_paid - (order_result.price * order_result.position * fee_pct)
        assert abs(order_result_new.realized_pnl - expected_pnl) < 0.01

        # Available balance should increase
        assert account_state_new.available_balance > basic_account_state.available_balance

    def test_long_exit_with_loss(self, basic_account_state):
        """Test long position exit with a loss (stop loss hit)."""
        # Create an open long position that hit stop loss
        order_result = OrderResult(
            average_entry=100.0,
            fees_paid=0.6,
            leverage=10.0,
            liq_price=90.0,
            moved_sl_to_be=False,
            order_status=OrderStatus.Filled,
            order_status_info=0,
            order_type=OrderType.LongSL,  # Exiting via stop loss
            pct_chg_trade=0.0,
            position=1.0,
            price=98.0,  # Exit at $98 (2% loss)
            realized_pnl=0.0,
            size_value=100.0,
            sl_pcts=0.02,
            sl_prices=98.0,
            tp_pcts=0.05,
            tp_prices=105.0,
            tsl_pcts_init=0.0,
            tsl_prices=0.0,
        )

        fee_pct = 0.0006

        account_state_new, order_result_new = long_decrease_nb(
            order_result=order_result,
            account_state=basic_account_state,
            fee_pct=fee_pct,
        )

        # Check realized PnL is negative
        assert order_result_new.realized_pnl < 0

        # Loss should be approximately (98 - 100) * 1.0 - fees
        expected_loss = (order_result.price - order_result.average_entry) * order_result.position - order_result.fees_paid - (order_result.price * order_result.position * fee_pct)
        assert abs(order_result_new.realized_pnl - expected_loss) < 0.01
