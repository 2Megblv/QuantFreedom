import numpy as np
from numba import njit

from quantfreedom._typing import Tuple
from quantfreedom.nb.position_funcs import increase_position_nb, decrease_position_nb
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


# Long order to enter or add to a long position
@njit(cache=True)
def long_increase_nb(
    price: float,
    account_state: AccountState,
    entry_order: EntryOrder,
    order_result: OrderResult,
    static_variables_tuple: StaticVariables,
) -> Tuple[AccountState, OrderResult]:
    """
    Increase or open a long position (backward compatibility wrapper).

    This function now calls the unified increase_position_nb with direction=1.
    All logic has been consolidated into position_funcs.py to eliminate duplication.
    """
    return increase_position_nb(
        direction=1,  # Long position
        price=price,
        account_state=account_state,
        entry_order=entry_order,
        order_result=order_result,
        static_variables_tuple=static_variables_tuple,
    )


@njit(cache=True)
def long_decrease_nb(
    fee_pct: float,
    order_result: OrderResult,
    account_state: AccountState,
):
    """
    Decrease or close a long position (backward compatibility wrapper).

    This function now calls the unified decrease_position_nb with direction=1.
    All logic has been consolidated into position_funcs.py to eliminate duplication.
    """
    return decrease_position_nb(
        direction=1,  # Long position
        fee_pct=fee_pct,
        order_result=order_result,
        account_state=account_state,
    )
