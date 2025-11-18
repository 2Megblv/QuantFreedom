"""
Unified position management functions (direction-agnostic).

This module consolidates the logic from buy_funcs.py and sell_funcs.py
into unified functions that work for both long and short positions.

Direction parameter:
    1 = Long position (buy)
   -1 = Short position (sell)
"""
import numpy as np
from numba import njit

from quantfreedom._typing import Tuple
from quantfreedom.enums.enums import (
    AccountState,
    EntryOrder,
    OrderResult,
    OrderStatus,
    OrderStatusInfo,
    RejectedOrderError,
    LeverageMode,
    StaticVariables,
    SizeType,
)


@njit(cache=True)
def increase_position_nb(
    direction: int,  # 1 for long, -1 for short
    price: float,
    account_state: AccountState,
    entry_order: EntryOrder,
    order_result: OrderResult,
    static_variables_tuple: StaticVariables,
) -> Tuple[AccountState, OrderResult]:
    """
    Unified function to increase position (long or short).

    Parameters
    ----------
    direction : int
        1 for long position, -1 for short position
    price : float
        Current market price
    account_state : AccountState
        Current account state
    entry_order : EntryOrder
        Entry order parameters
    order_result : OrderResult
        Previous order result
    static_variables_tuple : StaticVariables
        Static backtest variables

    Returns
    -------
    Tuple[AccountState, OrderResult]
        Updated account state and order result
    """
    # Initialize new values
    available_balance_new = account_state.available_balance
    cash_used_new = account_state.cash_used
    leverage_new = entry_order.leverage
    average_entry_new = order_result.average_entry
    liq_price_new = order_result.liq_price
    position_new = order_result.position

    sl_pcts_new = entry_order.sl_pcts
    tp_pcts_new = entry_order.tp_pcts
    tsl_pcts_init_new = entry_order.tsl_pcts_init

    sl_prices_new = np.nan
    tsl_prices_new = np.nan
    tp_prices_new = np.nan

    # Direction multiplier for SL/TP calculations
    # Long: SL below entry (negative), TP above (positive)
    # Short: SL above entry (positive), TP below (negative)
    sl_direction = -direction
    tp_direction = direction

    # Calculate position size based on size type
    if (
        static_variables_tuple.size_type != SizeType.Amount
        and static_variables_tuple.size_type != SizeType.PercentOfAccount
    ):
        # Risk-based sizing
        if np.isfinite(sl_pcts_new):
            # Initial size calculation based on risk percentage or amount
            if static_variables_tuple.size_type == SizeType.RiskPercentOfAccount:
                size_value = account_state.equity * entry_order.size_pct / sl_pcts_new
            elif static_variables_tuple.size_type == SizeType.RiskAmount:
                size_value = entry_order.size_value / sl_pcts_new
                if size_value < 1:
                    raise ValueError(
                        "Risk Amount has produced a size_value values less than 1."
                    )

            # Calculate SL price (direction-dependent)
            temp_sl_price = price + (sl_direction * price * sl_pcts_new)
            possible_loss = size_value * sl_pcts_new

            # Calculate adjusted size based on fees (direction-dependent)
            if direction == 1:  # Long
                size_value = -possible_loss / (
                    temp_sl_price / price
                    - 1
                    - static_variables_tuple.fee_pct
                    - temp_sl_price * static_variables_tuple.fee_pct / price
                )
            else:  # Short
                size_value = -possible_loss / (
                    1
                    - temp_sl_price / price
                    - static_variables_tuple.fee_pct
                    - temp_sl_price * static_variables_tuple.fee_pct / price
                )

        elif np.isfinite(tsl_pcts_init_new):
            # Initial size calculation for TSL
            if static_variables_tuple.size_type == SizeType.RiskPercentOfAccount:
                size_value = (
                    account_state.equity * entry_order.size_pct / tsl_pcts_init_new
                )
            elif static_variables_tuple.size_type == SizeType.RiskAmount:
                size_value = entry_order.size_value / tsl_pcts_init_new
                if size_value < 1:
                    raise ValueError(
                        "Risk Amount has produced a size_value values less than 1."
                    )

            # Calculate TSL price (direction-dependent)
            temp_tsl_price = price + (sl_direction * price * tsl_pcts_init_new)
            possible_loss = size_value * tsl_pcts_init_new

            # Calculate adjusted size based on fees (direction-dependent)
            if direction == 1:  # Long
                size_value = -possible_loss / (
                    temp_tsl_price / price
                    - 1
                    - static_variables_tuple.fee_pct
                    - temp_tsl_price * static_variables_tuple.fee_pct / price
                )
            else:  # Short
                size_value = -possible_loss / (
                    1
                    - temp_tsl_price / price
                    - static_variables_tuple.fee_pct
                    - temp_tsl_price * static_variables_tuple.fee_pct / price
                )

    elif static_variables_tuple.size_type == SizeType.Amount:
        # Fixed amount sizing
        size_value = entry_order.size_value
        if size_value > static_variables_tuple.max_order_size_value:
            size_value = static_variables_tuple.max_order_size_value
        elif size_value == np.inf:
            size_value = order_result.position

    elif static_variables_tuple.size_type == SizeType.PercentOfAccount:
        # Percentage of account sizing
        size_value = account_state.equity * entry_order.size_pct

    else:
        raise TypeError(
            "Invalid size_type - cannot calculate size_value"
        )

    # Validate size value
    if (
        size_value < 1
        or size_value > static_variables_tuple.max_order_size_value
        or size_value < static_variables_tuple.min_order_size_value
    ):
        position_type = "Long" if direction == 1 else "Short"
        raise RejectedOrderError(
            f"{position_type} Increase - Size Value is either too big or too small"
        )

    # Calculate average entry price
    if position_new != 0.0:
        average_entry_new = (size_value + position_new) / (
            (size_value / price) + (position_new / average_entry_new)
        )
    else:
        average_entry_new = price

    # Update position size
    position_new = position_new + size_value

    # Create stop loss prices (direction-dependent)
    if not np.isnan(sl_pcts_new):
        sl_prices_new = average_entry_new + (sl_direction * average_entry_new * sl_pcts_new)
    else:
        sl_prices_new = np.nan
        sl_pcts_new = np.nan

    # Create trailing stop loss prices (direction-dependent)
    if not np.isnan(tsl_pcts_init_new):
        tsl_prices_new = average_entry_new + (
            sl_direction * average_entry_new * tsl_pcts_init_new
        )
    else:
        tsl_prices_new = np.nan
        tsl_pcts_init_new = np.nan

    # Risk percentage check
    is_stop_loss = (
        not np.isnan(sl_prices_new)
        or not np.isnan(tsl_prices_new)
        or not np.isnan(liq_price_new)
    )

    is_max_risk = not np.isnan(entry_order.max_equity_risk_pct) or not np.isnan(
        entry_order.max_equity_risk_value
    )

    if is_stop_loss and is_max_risk:
        # Get closest stop price
        if not np.isnan(sl_prices_new):
            temp_price = sl_prices_new
        elif not np.isnan(tsl_prices_new):
            temp_price = tsl_prices_new
        elif not np.isnan(liq_price_new):
            temp_price = liq_price_new

        # Calculate possible loss
        coin_size = position_new / average_entry_new

        # Direction-dependent PnL calculation
        if direction == 1:  # Long
            pnl_no_fees = coin_size * (temp_price - average_entry_new)
        else:  # Short
            pnl_no_fees = coin_size * (average_entry_new - temp_price)

        open_fee = coin_size * average_entry_new * static_variables_tuple.fee_pct
        close_fee = coin_size * temp_price * static_variables_tuple.fee_pct
        possible_loss = -(pnl_no_fees - open_fee - close_fee)
        possible_loss = float(int(possible_loss))

        # Get account risk amount
        if not np.isnan(entry_order.max_equity_risk_pct):
            account_risk_amount = float(
                int(account_state.equity * entry_order.max_equity_risk_pct)
            )
        elif not np.isnan(entry_order.max_equity_risk_value):
            account_risk_amount = entry_order.max_equity_risk_value

        # Check if risk exceeds maximum - return Ignored status (don't raise error)
        if 0 < possible_loss > account_risk_amount:
            return account_state, OrderResult(
                average_entry=order_result.average_entry,
                fees_paid=np.nan,
                leverage=order_result.leverage,
                liq_price=order_result.liq_price,
                moved_sl_to_be=order_result.moved_sl_to_be,
                order_status=OrderStatus.Ignored,
                order_status_info=OrderStatusInfo.MaxEquityRisk,
                order_type=entry_order.order_type,
                pct_chg_trade=np.nan,
                position=order_result.position,
                price=price,
                realized_pnl=np.nan,
                size_value=np.nan,
                sl_pcts=order_result.sl_pcts,
                sl_prices=order_result.sl_prices,
                tp_pcts=order_result.tp_pcts,
                tp_prices=order_result.tp_prices,
                tsl_pcts_init=order_result.tsl_pcts_init,
                tsl_prices=order_result.tsl_prices,
            )

    # Calculate leverage (direction-dependent)
    if static_variables_tuple.lev_mode == LeverageMode.LeastFreeCashUsed:
        # Create leverage for sl/tsl
        if not np.isnan(sl_prices_new):
            temp_price = sl_prices_new
        elif not np.isnan(tsl_prices_new):
            temp_price = tsl_prices_new

        # Direction-dependent leverage calculation
        if direction == 1:  # Long
            leverage_new = -average_entry_new / (
                temp_price
                - temp_price * 0.002  # TODO: 0.002 is percent padding user wants
                - average_entry_new
                - static_variables_tuple.mmr_pct * average_entry_new
            )
        else:  # Short
            leverage_new = average_entry_new / (
                temp_price
                + temp_price * 0.002  # TODO: 0.002 is percent padding user wants
                - average_entry_new
                + static_variables_tuple.mmr_pct * average_entry_new
            )

        if leverage_new > static_variables_tuple.max_lev:
            leverage_new = static_variables_tuple.max_lev
    else:
        raise RejectedOrderError(
            "Position Increase - Either lev mode is nan or something is wrong with leverage or leverage mode"
        )

    # Calculate order cost (initial margin, fees, potential bankruptcy fee)
    initial_margin = size_value / leverage_new
    fee_to_open = size_value * static_variables_tuple.fee_pct

    # Direction-dependent bankruptcy fee calculation
    if direction == 1:  # Long
        possible_bankruptcy_fee = (
            size_value * (leverage_new - 1) / leverage_new * static_variables_tuple.fee_pct
        )
    else:  # Short
        possible_bankruptcy_fee = (
            size_value * (leverage_new + 1) / leverage_new * static_variables_tuple.fee_pct
        )

    cash_used_new = initial_margin + fee_to_open + possible_bankruptcy_fee

    # Validate cash requirements
    if cash_used_new > available_balance_new * leverage_new:
        raise RejectedOrderError(
            "Position increase - cash used greater than available balance * lev ... size_value is too big"
        )
    elif cash_used_new > available_balance_new:
        raise RejectedOrderError(
            "Position increase - cash used greater than available balance ... maybe increase lev"
        )

    # Update balances
    available_balance_new = available_balance_new - cash_used_new
    cash_used_new = account_state.cash_used + cash_used_new
    cash_borrowed_new = account_state.cash_borrowed + size_value - cash_used_new

    # Calculate liquidation price (direction-dependent)
    if direction == 1:  # Long
        liq_price_new = average_entry_new * (
            1 - (1 / leverage_new) + static_variables_tuple.mmr_pct
        )
    else:  # Short
        liq_price_new = average_entry_new * (
            1 + (1 / leverage_new) - static_variables_tuple.mmr_pct
        )

    # Create take profit prices (direction-dependent)
    # Handle risk/reward ratio TP calculation with direction-specific formulas
    if not np.isnan(entry_order.risk_rewards):
        if np.isfinite(sl_prices_new):
            sl_or_tsl_prices = sl_prices_new
        elif np.isfinite(tsl_prices_new):
            sl_or_tsl_prices = tsl_prices_new

        coin_size = size_value / average_entry_new

        # Direction-dependent loss calculation
        if direction == 1:  # Long
            loss_no_fees = coin_size * (sl_or_tsl_prices - average_entry_new)
        else:  # Short
            loss_no_fees = coin_size * (average_entry_new - sl_or_tsl_prices)

        fee_open = coin_size * average_entry_new * static_variables_tuple.fee_pct
        fee_close = coin_size * sl_or_tsl_prices * static_variables_tuple.fee_pct
        loss = loss_no_fees - fee_open - fee_close
        profit = -loss * entry_order.risk_rewards

        # Direction-dependent TP price calculation
        if direction == 1:  # Long
            tp_prices_new = (
                profit + size_value * static_variables_tuple.fee_pct + size_value
            ) * (
                average_entry_new / (size_value - size_value * static_variables_tuple.fee_pct)
            )
        else:  # Short
            tp_prices_new = -(
                (profit - size_value + size_value * static_variables_tuple.fee_pct)
                * (average_entry_new / (size_value + size_value * static_variables_tuple.fee_pct))
            )

        # Direction-dependent TP percentage calculation
        if direction == 1:  # Long
            tp_pcts_new = (tp_prices_new - average_entry_new) / average_entry_new
        else:  # Short
            tp_pcts_new = (average_entry_new - tp_prices_new) / average_entry_new

    elif not np.isnan(tp_pcts_new):
        tp_prices_new = average_entry_new + (tp_direction * average_entry_new * tp_pcts_new)
    else:
        tp_pcts_new = np.nan
        tp_prices_new = np.nan

    # Final balance check
    if available_balance_new < 0:
        raise RejectedOrderError("Position increase - available balance < 0")

    # Create new account state
    return AccountState(
        available_balance=available_balance_new,
        cash_borrowed=cash_borrowed_new,
        cash_used=cash_used_new,
        equity=account_state.equity,
    ), OrderResult(
        average_entry=average_entry_new,
        fees_paid=np.nan,
        leverage=leverage_new,
        liq_price=liq_price_new,
        moved_sl_to_be=False,
        order_status=OrderStatus.Filled,
        order_status_info=OrderStatusInfo.HopefullyNoProblems,
        order_type=entry_order.order_type,
        pct_chg_trade=np.nan,
        position=position_new,
        price=price,
        realized_pnl=np.nan,
        size_value=size_value,
        sl_pcts=sl_pcts_new,
        sl_prices=sl_prices_new,
        tp_pcts=tp_pcts_new,
        tp_prices=tp_prices_new,
        tsl_pcts_init=tsl_pcts_init_new,
        tsl_prices=tsl_prices_new,
    )


@njit(cache=True)
def decrease_position_nb(
    direction: int,  # 1 for long, -1 for short
    fee_pct: float,
    order_result: OrderResult,
    account_state: AccountState,
) -> Tuple[AccountState, OrderResult]:
    """
    Unified function to decrease/close position (long or short).

    Parameters
    ----------
    direction : int
        1 for long position, -1 for short position
    fee_pct : float
        Fee percentage
    order_result : OrderResult
        Current order result with position details
    account_state : AccountState
        Current account state

    Returns
    -------
    Tuple[AccountState, OrderResult]
        Updated account state and order result
    """
    # Determine size to close (handle partial closes)
    if order_result.size_value >= order_result.position:
        size_value = order_result.position
    else:
        size_value = order_result.size_value

    # Calculate percentage change in trade (direction-dependent)
    if direction == 1:  # Long
        pct_chg_trade = (
            order_result.price - order_result.average_entry
        ) / order_result.average_entry
    else:  # Short
        pct_chg_trade = (
            order_result.average_entry - order_result.price
        ) / order_result.average_entry

    # Calculate new position size and percentage changed
    position_new = order_result.position - size_value
    position_pct_chg = (order_result.position - position_new) / order_result.position

    # Calculate PnL (direction-dependent)
    coin_size = size_value / order_result.average_entry

    if direction == 1:  # Long
        pnl = coin_size * (order_result.price - order_result.average_entry)
    else:  # Short
        pnl = coin_size * (order_result.average_entry - order_result.price)

    # Calculate fees
    fee_open = coin_size * order_result.average_entry * fee_pct
    fee_close = coin_size * order_result.price * fee_pct
    fees_paid = fee_open + fee_close

    # Calculate realized PnL
    realized_pnl = pnl - fees_paid

    # Update account state with proportional cash management
    equity_new = account_state.equity + realized_pnl

    cash_borrowed_new = account_state.cash_borrowed - (
        account_state.cash_borrowed * position_pct_chg
    )

    cash_used_new = account_state.cash_used - (
        account_state.cash_used * position_pct_chg
    )

    available_balance_new = (
        realized_pnl
        + account_state.available_balance
        + (account_state.cash_used * position_pct_chg)
    )

    return AccountState(
        available_balance=available_balance_new,
        cash_borrowed=cash_borrowed_new,
        cash_used=cash_used_new,
        equity=equity_new,
    ), OrderResult(
        average_entry=order_result.average_entry,
        fees_paid=fees_paid,
        leverage=order_result.leverage,
        liq_price=order_result.liq_price,
        moved_sl_to_be=order_result.moved_sl_to_be,
        order_status=OrderStatus.Filled,
        order_status_info=OrderStatusInfo.HopefullyNoProblems,
        order_type=order_result.order_type,
        pct_chg_trade=pct_chg_trade,
        position=position_new,
        price=order_result.price,
        realized_pnl=realized_pnl,
        size_value=size_value,
        sl_pcts=order_result.sl_pcts,
        sl_prices=order_result.sl_prices,
        tp_pcts=order_result.tp_pcts,
        tp_prices=order_result.tp_prices,
        tsl_pcts_init=order_result.tsl_pcts_init,
        tsl_prices=order_result.tsl_prices,
    )
