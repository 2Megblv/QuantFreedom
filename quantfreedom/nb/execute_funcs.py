"""
Testing the tester
"""

import numpy as np
from numba import njit

from quantfreedom._typing import Optional
from quantfreedom.nb.helper_funcs import fill_order_records_nb, fill_strat_records_nb
from quantfreedom.nb.buy_funcs import long_increase_nb, long_decrease_nb
from quantfreedom.nb.sell_funcs import short_increase_nb, short_decrease_nb
from quantfreedom._typing import (
    RecordArray,
    Array1d,
    Optional,
    Tuple,
)
from quantfreedom.enums.enums import (
    OrderType,
    SL_BE_or_Trail_BasedOn,
    OrderStatus,
    AccountState,
    EntryOrder,
    OrderResult,
    StopsOrder,
    StaticVariables,
)


@njit(cache=True)
def check_sl_tp_nb(
    high_price: float,
    low_price: float,
    open_price: float,
    close_price: float,
    order_settings_counter: int,
    entry_type: int,
    fee_pct: float,
    bar: int,
    account_state: AccountState,
    order_result: OrderResult,
    stops_order: StopsOrder,
    order_records_id: Optional[Array1d] = None,
    order_records: Optional[RecordArray] = None,
) -> OrderResult:
    """
    Check and execute stop loss, take profit, and liquidation conditions.

    This function is called on each bar to determine if any exit conditions
    have been triggered (stop loss, trailing stop loss, take profit, or
    liquidation). It also manages advanced stop loss features like moving
    stop loss to breakeven and implementing trailing stop losses.

    The function uses bar high/low prices to check trigger conditions with
    correct priority: liquidation > stop loss > take profit. It updates
    the order result with the appropriate exit price and order type if
    any condition is met.

    Parameters
    ----------
    high_price : float
        Highest price during the current bar
    low_price : float
        Lowest price during the current bar
    open_price : float
        Opening price of current bar (used for SL/TSL trailing logic)
    close_price : float
        Closing price of current bar (used for SL/TSL trailing logic)
    order_settings_counter : int
        Current order settings index for record keeping
    entry_type : int
        Order type (OrderType.LongEntry or OrderType.ShortEntry)
    fee_pct : float
        Fee percentage for breakeven calculations
    bar : int
        Current bar index for record keeping
    account_state : AccountState
        Current account state
    order_result : OrderResult
        Current order result with position and stop prices
    stops_order : StopsOrder
        Stop loss configuration including breakeven and trailing parameters
    order_records_id : Optional[Array1d], default None
        Array tracking order record IDs (incremented when stops move)
    order_records : Optional[RecordArray], default None
        Array for storing order records when stops are adjusted

    Returns
    -------
    order_result_new : OrderResult
        Updated order result with:
        - order_type: Changed to exit type if condition triggered
          (LongSL, LongTP, ShortSL, etc.)
        - price: Set to exit price if condition met, np.nan otherwise
        - size_value: Set to np.inf for full exit, np.nan if no exit
        - sl_prices/tsl_prices: Updated if trailing stop adjusted
        - moved_sl_to_be: Set True if stop moved to breakeven

    Notes
    -----
    **Exit Priority** (checked in this order):
        1. Liquidation - Highest priority, always checked first
        2. Stop Loss - Regular or trailing stop loss
        3. Take Profit - Checked last

    **Long Position Logic**:
        - SL triggered: if low_price <= sl_price
        - TSL triggered: if low_price <= tsl_price
        - Liquidation triggered: if low_price <= liq_price
        - TP triggered: if high_price >= tp_price

    **Short Position Logic**:
        - SL triggered: if high_price >= sl_price
        - TSL triggered: if high_price >= tsl_price
        - Liquidation triggered: if high_price >= liq_price
        - TP triggered: if low_price <= tp_price

    **Stop Loss to Breakeven**:
        When enabled (stops_order.sl_to_be=True), moves stop loss to
        breakeven (or small profit) when price moves favorably by
        sl_to_be_when_pct_from_avg_entry. Breakeven price accounts
        for entry and exit fees to ensure zero loss.

    **Trailing Stop Loss**:
        When enabled, dynamically adjusts stop loss as price moves
        favorably. Trails by tsl_trail_by_pct distance. Can be based
        on high/low/open/close price depending on tsl_based_on setting.

    **Trailing After Breakeven**:
        If sl_to_be_then_trail=True, converts breakeven stop to
        trailing stop after it's triggered, combining both features.

    Examples
    --------
    >>> # Check for exits on current bar
    >>> high, low, open_price, close = 51000, 49000, 50500, 50000
    >>> order_result = OrderResult(
    ...     average_entry=50000,
    ...     sl_prices=49000,  # 2% stop loss
    ...     tp_prices=52000,  # 4% take profit
    ...     ...
    ... )
    >>> result = check_sl_tp_nb(
    ...     high, low, open_price, close, 0, OrderType.LongEntry,
    ...     0.001, 100, account_state, order_result, stops_order
    ... )
    >>> result.order_type  # OrderType.LongSL (stop loss triggered)
    >>> result.price  # 49000 (exit at stop loss price)
    """
    # Check SL
    moved_sl_to_be_new = order_result.moved_sl_to_be
    moved_tsl = False
    record_sl_move = False
    order_type_new = entry_type
    price_new = order_result.price
    size_value_new = np.inf
    sl_prices_new = order_result.sl_prices
    tsl_prices_new = order_result.tsl_prices

    average_entry = order_result.average_entry

    # checking if we are in a long
    if order_type_new == OrderType.LongEntry:
        # Regular Stop Loss
        if low_price <= sl_prices_new:
            price_new = sl_prices_new
            order_type_new = OrderType.LongSL
        # Trailing Stop Loss
        elif low_price <= tsl_prices_new:
            price_new = tsl_prices_new
            order_type_new = OrderType.LongTSL
        # Liquidation
        elif low_price <= order_result.liq_price:
            price_new = order_result.liq_price
            order_type_new = OrderType.LongLiq
        # Take Profit
        elif high_price >= order_result.tp_prices:
            price_new = order_result.tp_prices
            order_type_new = OrderType.LongTP

        # Stop Loss to break even
        elif not moved_sl_to_be_new and stops_order.sl_to_be:
            if stops_order.sl_to_be_based_on == SL_BE_or_Trail_BasedOn.low_price:
                sl_be_based_on = low_price
            elif stops_order.sl_to_be_based_on == SL_BE_or_Trail_BasedOn.close_price:
                sl_be_based_on = close_price
            elif stops_order.sl_to_be_based_on == SL_BE_or_Trail_BasedOn.open_price:
                sl_be_based_on = open_price
            elif stops_order.sl_to_be_based_on == SL_BE_or_Trail_BasedOn.high_price:
                sl_be_based_on = high_price

            if (
                sl_be_based_on - average_entry
            ) / average_entry > stops_order.sl_to_be_when_pct_from_avg_entry:
                if stops_order.sl_to_be_zero_or_entry == 0:
                    # this formula only works with a 1 because it represents a size val of 1
                    # if i were to use any other value for size i would have to use the solving for tp code
                    sl_prices_new = (fee_pct * average_entry + average_entry) / (
                        1 - fee_pct
                    )
                else:
                    sl_prices_new = average_entry
                moved_sl_to_be_new = True
                order_type_new = OrderType.MovedSLtoBE
                record_sl_move = True
            price_new = np.nan
            size_value_new = np.nan

        # Trailing Stop Loss
        elif stops_order.tsl_true_or_false:
            if stops_order.tsl_based_on == SL_BE_or_Trail_BasedOn.low_price:
                trail_based_on = low_price
            elif stops_order.tsl_based_on == SL_BE_or_Trail_BasedOn.high_price:
                trail_based_on = high_price
            elif stops_order.tsl_based_on == SL_BE_or_Trail_BasedOn.open_price:
                trail_based_on = open_price
            elif stops_order.tsl_based_on == SL_BE_or_Trail_BasedOn.close_price:
                trail_based_on = close_price

            # not going to adjust every candle
            x = (
                trail_based_on - average_entry
            ) / average_entry > stops_order.tsl_when_pct_from_avg_entry
            if x:
                temp_tsl_price = (
                    trail_based_on - trail_based_on * stops_order.tsl_trail_by_pct
                )
                if temp_tsl_price > tsl_prices_new:
                    tsl_prices_new = temp_tsl_price
                    moved_tsl = True
                    order_type_new = OrderType.MovedTSL
            price_new = np.nan
            size_value_new = np.nan
        else:
            price_new = np.nan
            size_value_new = np.nan

    # checking if we are in a short
    elif order_type_new == OrderType.ShortEntry:
        # Regular Stop Loss
        if high_price >= sl_prices_new:
            price_new = sl_prices_new
            order_type_new = OrderType.ShortSL
        # Trailing Stop Loss
        elif high_price >= tsl_prices_new:
            price_new = tsl_prices_new
            order_type_new = OrderType.ShortTSL
        # Liquidation
        elif high_price >= order_result.liq_price:
            price_new = order_result.liq_price
            order_type_new = OrderType.ShortLiq
        # Take Profit
        elif low_price <= order_result.tp_prices:
            price_new = order_result.tp_prices
            order_type_new = OrderType.ShortTP

        # Stop Loss to break even
        elif not moved_sl_to_be_new and stops_order.sl_to_be:
            if stops_order.sl_to_be_based_on == SL_BE_or_Trail_BasedOn.low_price:
                sl_be_based_on = low_price
            elif stops_order.sl_to_be_based_on == SL_BE_or_Trail_BasedOn.close_price:
                sl_be_based_on = close_price
            elif stops_order.sl_to_be_based_on == SL_BE_or_Trail_BasedOn.open_price:
                sl_be_based_on = open_price
            elif stops_order.sl_to_be_based_on == SL_BE_or_Trail_BasedOn.high_price:
                sl_be_based_on = high_price

            if (
                average_entry - sl_be_based_on
            ) / average_entry > stops_order.sl_to_be_when_pct_from_avg_entry:
                if stops_order.sl_to_be_zero_or_entry == 0:
                    # this formula only works with a 1 because it represents a size val of 1
                    # if i were to use any other value for size i would have to use the solving for tp code
                    sl_prices_new = (average_entry - fee_pct * average_entry) / (
                        1 + fee_pct
                    )
                else:
                    sl_prices_new = average_entry
                moved_sl_to_be_new = True
                order_type_new = OrderType.MovedSLtoBE
                record_sl_move = True
            price_new = np.nan
            size_value_new = np.nan

        # Trailing Stop Loss
        elif stops_order.tsl_true_or_false:
            if stops_order.tsl_based_on == SL_BE_or_Trail_BasedOn.high_price:
                trail_based_on = high_price
            elif stops_order.tsl_based_on == SL_BE_or_Trail_BasedOn.close_price:
                trail_based_on = close_price
            elif stops_order.tsl_based_on == SL_BE_or_Trail_BasedOn.open_price:
                trail_based_on = open_price
            elif stops_order.tsl_based_on == SL_BE_or_Trail_BasedOn.low_price:
                trail_based_on = low_price

            # not going to adjust every candle
            x = (
                average_entry - trail_based_on
            ) / average_entry > stops_order.tsl_when_pct_from_avg_entry
            if x:
                temp_tsl_price = (
                    trail_based_on + trail_based_on * stops_order.tsl_trail_by_pct
                )
                if temp_tsl_price < tsl_prices_new:
                    tsl_prices_new = temp_tsl_price
                    moved_tsl = True
                    order_type_new = OrderType.MovedTSL
            price_new = np.nan
            size_value_new = np.nan
        else:
            price_new = np.nan
            size_value_new = np.nan

    order_result_new = OrderResult(
        average_entry=order_result.average_entry,
        fees_paid=order_result.fees_paid,
        leverage=order_result.leverage,
        liq_price=order_result.liq_price,
        moved_sl_to_be=moved_sl_to_be_new,
        order_status=order_result.order_status,
        order_status_info=order_result.order_status_info,
        order_type=order_type_new,
        pct_chg_trade=order_result.pct_chg_trade,
        position=order_result.position,
        price=price_new,
        realized_pnl=order_result.realized_pnl,
        size_value=size_value_new,
        sl_pcts=order_result.sl_pcts,
        sl_prices=sl_prices_new,
        tp_pcts=order_result.tp_pcts,
        tp_prices=order_result.tp_prices,
        tsl_pcts_init=order_result.tsl_pcts_init,
        tsl_prices=tsl_prices_new,
    )

    if order_records is not None and (record_sl_move or moved_tsl):
        fill_order_records_nb(
            bar=bar,
            order_records=order_records,
            order_settings_counter=order_settings_counter,
            order_records_id=order_records_id,
            account_state=account_state,
            order_result=order_result_new,
        )

    return order_result_new


@njit(cache=True)
def process_order_nb(
    price: float,
    bar: int,
    order_type: int,
    entries_col: int,
    order_settings_counter: int,
    symbol_counter: int,
    account_state: AccountState,
    entry_order: EntryOrder,
    order_result: OrderResult,
    static_variables_tuple: StaticVariables,
    order_records: Optional[RecordArray] = None,
    order_records_id: Optional[Array1d] = None,
    strat_records: Optional[RecordArray] = None,
    strat_records_filled: Optional[Array1d] = None,
) -> Tuple[AccountState, OrderResult]:
    """
    Process and execute an order by dispatching to appropriate position functions.

    This is the main order execution dispatcher that routes order types to the
    correct position management functions (long/short increase/decrease). It
    handles both entry and exit orders, manages record keeping for completed
    trades, and ensures proper account state updates.

    The function acts as a central orchestrator, determining whether an order
    is an entry (increase position) or exit (decrease position) and calling
    the appropriate underlying function. For exits, it also triggers strategy
    and order record filling.

    Parameters
    ----------
    price : float
        Execution price for the order
    bar : int
        Current bar index for record keeping
    order_type : int
        Order type from OrderType enum:
        - LongEntry: Open/add to long position
        - ShortEntry: Open/add to short position
        - LongLiq/LongSL/LongTSL/LongTP: Close long position
        - ShortLiq/ShortSL/ShortTSL/ShortTP: Close short position
    entries_col : int
        Entry signal column index for record keeping
    order_settings_counter : int
        Order settings index for record keeping
    symbol_counter : int
        Symbol index for multi-symbol backtests
    account_state : AccountState
        Current account state with balances
    entry_order : EntryOrder
        Entry order configuration (used for position increases)
    order_result : OrderResult
        Current order result with position details
    static_variables_tuple : StaticVariables
        Static backtest configuration
    order_records : Optional[RecordArray], default None
        Array for storing detailed order records. If provided, all filled
        orders are logged with execution details.
    order_records_id : Optional[Array1d], default None
        Array tracking order record IDs (incremented for each record)
    strat_records : Optional[RecordArray], default None
        Array for storing strategy-level trade records. If provided,
        completed trades (exits) are logged with PnL.
    strat_records_filled : Optional[Array1d], default None
        Array tracking number of strategy records filled

    Returns
    -------
    account_state_new : AccountState
        Updated account state after order execution
    order_result_new : OrderResult
        Updated order result with new position details, or exit details
        if order was a close

    Notes
    -----
    **Order Type Dispatch Logic**:
        - LongEntry → long_increase_nb()
        - ShortEntry → short_increase_nb()
        - Long exits (Liq/SL/TSL/TP) → long_decrease_nb()
        - Short exits (Liq/SL/TSL/TP) → short_decrease_nb()

    **Exit Order Range Check**:
        Long exits: OrderType.LongLiq (10) through OrderType.LongTSL (13)
        Short exits: OrderType.ShortLiq (20) through OrderType.ShortTSL (23)
        This range check handles all long/short exit types efficiently.

    **Record Filling**:
        - Strategy records: Filled only for exits (when fill_strat=True)
          Contains PnL, equity, and trade metadata
        - Order records: Filled for all successful orders (entries + exits)
          Contains price, size, fees, and stop/target prices

    **Record Conditionals**:
        - Both records only filled if OrderStatus.Filled
        - Strategy records only for completed trades (exits)
        - Order records for any filled order

    Examples
    --------
    >>> # Process long entry order
    >>> account_state = AccountState(equity=1000.0, ...)
    >>> entry_order = EntryOrder(leverage=10.0, ...)
    >>> order_result = OrderResult()  # Empty for new position
    >>> new_account, new_order = process_order_nb(
    ...     price=50000.0,
    ...     bar=100,
    ...     order_type=OrderType.LongEntry,
    ...     entries_col=0,
    ...     order_settings_counter=0,
    ...     symbol_counter=0,
    ...     account_state=account_state,
    ...     entry_order=entry_order,
    ...     order_result=order_result,
    ...     static_variables_tuple=static_vars,
    ... )
    >>> new_order.position  # New position size
    >>> new_order.order_type  # OrderType.LongEntry

    >>> # Process stop loss exit
    >>> exit_order_result = OrderResult(
    ...     position=1000.0,
    ...     average_entry=50000.0,
    ...     price=49000.0,  # SL triggered
    ...     order_type=OrderType.LongSL,
    ...     ...
    ... )
    >>> new_account, new_order = process_order_nb(
    ...     price=49000.0,
    ...     bar=150,
    ...     order_type=OrderType.LongSL,
    ...     ...,
    ...     order_result=exit_order_result,
    ...     strat_records=strat_array,  # Will be filled
    ... )
    >>> new_order.realized_pnl  # Loss from stop loss
    >>> new_order.position  # 0 (closed)

    See Also
    --------
    long_increase_nb : Increase long position
    short_increase_nb : Increase short position
    long_decrease_nb : Decrease long position
    short_decrease_nb : Decrease short position
    fill_order_records_nb : Fill order record details
    fill_strat_records_nb : Fill strategy record details
    """
    fill_strat = False
    if order_type == OrderType.LongEntry:
        account_state_new, order_result_new = long_increase_nb(
            price=price,
            entry_order=entry_order,
            order_result=order_result,
            account_state=account_state,
            static_variables_tuple=static_variables_tuple,
        )
    elif order_type == OrderType.ShortEntry:
        account_state_new, order_result_new = short_increase_nb(
            price=price,
            entry_order=entry_order,
            order_result=order_result,
            account_state=account_state,
            static_variables_tuple=static_variables_tuple,
        )
    elif OrderType.LongLiq <= order_type <= OrderType.LongTSL:
        account_state_new, order_result_new = long_decrease_nb(
            order_result=order_result,
            account_state=account_state,
            fee_pct=static_variables_tuple.fee_pct,
        )
        fill_strat = True
    elif OrderType.ShortLiq <= order_type <= OrderType.ShortTSL:
        account_state_new, order_result_new = short_decrease_nb(
            order_result=order_result,
            account_state=account_state,
            fee_pct=static_variables_tuple.fee_pct,
        )
        fill_strat = True

    if (
        fill_strat
        and strat_records is not None
        and order_result_new.order_status == OrderStatus.Filled
    ):
        fill_strat_records_nb(
            entries_col=entries_col,
            order_settings_counter=order_settings_counter,
            symbol_counter=symbol_counter,
            strat_records=strat_records,
            strat_records_filled=strat_records_filled,
            equity=account_state_new.equity,
            pnl=order_result_new.realized_pnl,
        )

    if (
        order_records is not None
        and order_result_new.order_status == OrderStatus.Filled
    ):
        fill_order_records_nb(
            bar=bar,
            order_records=order_records,
            order_settings_counter=order_settings_counter,
            order_records_id=order_records_id,
            account_state=account_state_new,
            order_result=order_result_new,
        )

    return account_state_new, order_result_new
