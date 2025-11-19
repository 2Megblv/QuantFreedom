import numpy as np
from numba import njit

from quantfreedom._typing import Tuple
from quantfreedom.nb.position_funcs import increase_position_nb, decrease_position_nb
from quantfreedom.enums.enums import (
    AccountState,
    EntryOrder,
    OrderResult,
    RejectedOrderError,
    StaticVariables,

    OrderStatus,
    OrderStatusInfo,
    LeverageMode,
    SizeType,
)


# Short order to enter or add to a short position
@njit(cache=True)
def short_increase_nb(
    price: float,
    account_state: AccountState,
    entry_order: EntryOrder,
    order_result: OrderResult,
    static_variables_tuple: StaticVariables,
) -> Tuple[AccountState, OrderResult]:
    """
    Enter or add to a short position (backward compatibility wrapper).

    This function is a thin wrapper around increase_position_nb() that maintains
    backward compatibility with existing code. All position logic has been
    unified in position_funcs.py to eliminate the 92.6% code duplication that
    previously existed between long and short functions.

    For short positions:
    - Stop loss is ABOVE entry price (limits loss on price increase)
    - Take profit is BELOW entry price (captures profit on price decrease)
    - Liquidation is ABOVE entry price

    For detailed documentation, see increase_position_nb() in position_funcs.py.

    Parameters
    ----------
    price : float
        Current market price for entry
    account_state : AccountState
        Current account state
    entry_order : EntryOrder
        Entry order configuration
    order_result : OrderResult
        Previous order result (empty for new positions)
    static_variables_tuple : StaticVariables
        Static backtest configuration

    Returns
    -------
    account_state_new : AccountState
        Updated account state
    order_result_new : OrderResult
        New order result with position details

    See Also
    --------
    increase_position_nb : Unified position increase function (direction-agnostic)
    long_increase_nb : Long position equivalent
    short_decrease_nb : Close/reduce short positions
    """
    return increase_position_nb(
        direction=-1,  # Short position
        price=price,
        account_state=account_state,
        entry_order=entry_order,
        order_result=order_result,
        static_variables_tuple=static_variables_tuple,
    )


@njit(cache=True)
def short_decrease_nb(
    fee_pct: float,
    order_result: OrderResult,
    account_state: AccountState,
):
    """
    Exit or reduce a short position (backward compatibility wrapper).

    This function is a thin wrapper around decrease_position_nb() that maintains
    backward compatibility. All position closing logic has been unified in
    position_funcs.py to eliminate code duplication.

    For short positions, profit is realized when exit price is below entry price.

    For detailed documentation of PnL calculation, fee handling, and cash
    management, see decrease_position_nb() in position_funcs.py.

    Parameters
    ----------
    fee_pct : float
        Fee percentage as decimal (e.g., 0.001 for 0.1%)
    order_result : OrderResult
        Current order result with position size and exit price
    account_state : AccountState
        Current account state

    Returns
    -------
    account_state_new : AccountState
        Updated account state with PnL applied
    order_result_new : OrderResult
        New order result with realized PnL and reduced position

    See Also
    --------
    decrease_position_nb : Unified position decrease function (direction-agnostic)
    long_decrease_nb : Long position equivalent
    short_increase_nb : Open/add to short positions
    """
    return decrease_position_nb(
        direction=-1,  # Short position
        fee_pct=fee_pct,
        order_result=order_result,
        account_state=account_state,
    )
