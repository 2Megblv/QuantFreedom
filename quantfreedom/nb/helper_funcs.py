import numpy as np
from numba import njit

from quantfreedom._typing import (
    RecordArray,
    Array1d,
    Array2d,
    PossibleArray,
)

from quantfreedom.enums import (
    AccountState,
    Arrays1dTuple,
    EntryOrder,
    LeverageMode,
    OrderResult,
    OrderType,
    SizeType,
    SL_BE_or_Trail_BasedOn,
    StaticVariables,
    StopsOrder,
)


@njit(cache=True)
def static_var_checker_nb(
    divide_records_array_size_by: float,
    equity: float,
    fee_pct: float,
    gains_pct_filter: float,
    lev_mode: int,
    max_lev: float,
    max_order_size_pct: float,
    max_order_size_value: float,
    min_order_size_pct: float,
    min_order_size_value: float,
    mmr_pct: float,
    order_type: int,
    size_type: int,
    sl_to_be_then_trail: bool,
    sl_to_be: bool,
    total_trade_filter: int,
    tsl_true_or_false: bool,
    upside_filter: float,
) -> StaticVariables:
    """
    Validate backtest configuration and create StaticVariables tuple.

    This function performs comprehensive validation of all static backtest
    parameters before running simulations. It checks parameter ranges,
    validates mutual exclusivity constraints, and converts percentage
    values to decimals. After validation, it constructs a StaticVariables
    namedtuple that is passed to all position and execution functions.

    Parameters
    ----------
    divide_records_array_size_by : float
        Memory optimization factor for result arrays (1 to 1000).
        Higher values reduce memory usage when testing many combinations
        with strict filters. Use 1 for no filtering, 10-100 for normal
        filtering, 100+ for strict filtering.
    equity : float
        Starting account equity (must be positive and finite)
    fee_pct : float
        Trading fee percentage (e.g., 0.1 for 0.1% maker/taker fees).
        Will be divided by 100 to convert to decimal.
    gains_pct_filter : float
        Minimum profit percentage to include strategy in results.
        Use -np.inf for no filter.
    lev_mode : int
        Leverage mode (LeverageMode enum): Isolated or LeastFreeCashUsed
    max_lev : float
        Maximum leverage allowed (1 to 100)
    max_order_size_pct : float
        Maximum order size as percentage of equity (min_order_size_pct to 100)
    max_order_size_value : float
        Maximum order size in dollars (must be > min_order_size_value)
    min_order_size_pct : float
        Minimum order size as percentage of equity (0.01 to 100)
    min_order_size_value : float
        Minimum order size in dollars (must be >= 1)
    mmr_pct : float
        Maintenance margin rate percentage for liquidation calculations.
        Will be divided by 100 to convert to decimal.
    order_type : int
        Order type (OrderType enum): LongEntry, ShortEntry, or Both
    size_type : int
        Position sizing method (SizeType enum): Amount, PercentOfAccount,
        RiskAmount, or RiskPercentOfAccount
    sl_to_be_then_trail : bool
        If True, convert stop loss to trailing stop after hitting breakeven.
        Cannot be True if tsl_true_or_false is True.
    sl_to_be : bool
        If True, move stop loss to breakeven when profit threshold reached.
        Cannot be True if tsl_true_or_false is True.
    total_trade_filter : int
        Minimum number of trades required to include strategy in results.
        Must be >= 0.
    tsl_true_or_false : bool
        If True, use trailing stop loss.
        Cannot be True if sl_to_be or sl_to_be_then_trail are True.
    upside_filter : float
        R² filter for equity curve quality (-1 to 1).
        Filters strategies by to-the-upside metric.
        Use -1 for no filter.

    Returns
    -------
    StaticVariables
        Validated and processed static variables with:
        - Percentage values converted to decimals (fee_pct, mmr_pct, etc.)
        - All validation checks passed
        - Ready for use in position and execution functions

    Raises
    ------
    ValueError
        - If equity <= 0 or not finite
        - If fee_pct < 0 or not finite
        - If mmr_pct < 0 or not finite
        - If max_lev not between 1 and 100
        - If min_order_size_pct not between 0.01 and 100
        - If max_order_size_pct < min_order_size_pct or > 100
        - If min_order_size_value < 1
        - If max_order_size_value < min_order_size_value
        - If gains_pct_filter is np.inf
        - If total_trade_filter < 0 or not finite
        - If both sl_to_be and tsl_true_or_false are True
        - If sl_to_be is not boolean
        - If sl_to_be_then_trail is not boolean
        - If tsl_true_or_false is not boolean
        - If order_type is invalid or out of range
        - If upside_filter not between -1 and 1
        - If divide_records_array_size_by not between 1 and 1000

    Notes
    -----
    **Mutual Exclusivity Rules**:
        - Cannot use both sl_to_be and tsl_true_or_false simultaneously
        - sl_to_be_then_trail requires sl_to_be to be True

    **Percentage Conversions**:
        The following parameters are divided by 100 to convert to decimals:
        - fee_pct: 0.1 → 0.001
        - mmr_pct: 0.5 → 0.005
        - max_order_size_pct: 50 → 0.5
        - min_order_size_pct: 1 → 0.01

    **Memory Optimization**:
        divide_records_array_size_by reduces result array allocation.
        Formula: array_size = combinations / divide_records_array_size_by
        Example: 5M combinations / 100 = 50K result array rows

    Examples
    --------
    >>> # Standard configuration for crypto futures
    >>> static_vars = static_var_checker_nb(
    ...     divide_records_array_size_by=1.0,
    ...     equity=1000.0,
    ...     fee_pct=0.1,  # 0.1% fees
    ...     gains_pct_filter=-np.inf,
    ...     lev_mode=LeverageMode.Isolated,
    ...     max_lev=10.0,
    ...     max_order_size_pct=100.0,
    ...     max_order_size_value=np.inf,
    ...     min_order_size_pct=0.01,
    ...     min_order_size_value=1.0,
    ...     mmr_pct=0.5,  # 0.5% maintenance margin
    ...     order_type=OrderType.LongEntry,
    ...     size_type=SizeType.RiskPercentOfAccount,
    ...     sl_to_be_then_trail=False,
    ...     sl_to_be=False,
    ...     total_trade_filter=0,
    ...     tsl_true_or_false=False,
    ...     upside_filter=-1.0,
    ... )
    >>> static_vars.fee_pct  # 0.001 (converted from 0.1%)
    >>> static_vars.mmr_pct  # 0.005 (converted from 0.5%)
    """
    if equity < 0 or not np.isfinite(equity):
        raise ValueError("YOU HAVE NO MONEY!!!! You Broke!!!!")

    if fee_pct < 0 or not np.isfinite(fee_pct):
        raise ValueError("fee_pct must be finite")

    if mmr_pct < 0 or not np.isfinite(mmr_pct):
        raise ValueError("mmr_pct must be finite")

    if not np.isfinite(max_lev) or 1 > max_lev > 100:
        raise ValueError("max lev has to be between 1 and 100")

    if not np.isfinite(min_order_size_pct) or 0.01 > min_order_size_pct > 100:
        raise ValueError("min_order_size_pct  has to be between .01 and 100")

    if (
        not np.isfinite(max_order_size_pct)
        or min_order_size_pct > max_order_size_pct > 100
    ):
        raise ValueError(
            "max_order_size_pct has to be between min_order_size_pct and 100"
        )

    if not np.isfinite(min_order_size_value) or min_order_size_value < 1:
        raise ValueError("min_order_size_value has to be between .01 and 1 min inf")

    if np.isnan(max_order_size_value) or max_order_size_value < min_order_size_value:
        raise ValueError("max_order_size_value has to be > min_order_size_value")

    if gains_pct_filter == np.inf:
        raise ValueError("gains_pct_filter can't be inf")

    if total_trade_filter < 0 or not np.isfinite(total_trade_filter):
        raise ValueError("total_trade_filter needs to be greater than 0")

    if sl_to_be == True and tsl_true_or_false == True:
        raise ValueError("You can't have sl_to_be and tsl_true_or_false both be true")

    if sl_to_be != True and sl_to_be != False:
        raise ValueError("sl_to_be needs to be true or false")

    if sl_to_be_then_trail != True and sl_to_be_then_trail != False:
        raise ValueError("sl_to_be_then_trail needs to be true or false")

    if tsl_true_or_false != True and tsl_true_or_false != False:
        raise ValueError("tsl_true_or_false needs to be true or false")

    # simple check if order size type is valid
    if 0 > order_type > len(OrderType) or not np.isfinite(order_type):
        raise ValueError("order_type is invalid")

    if not (-1 <= upside_filter <= 1):
        raise ValueError("upside filter must be between -1 and 1")

    if not (1 <= divide_records_array_size_by <= 1000):
        raise ValueError("divide_records_array_size_by filter must be between 1 and 1000")

    # Static variables creation
    fee_pct /= 100
    mmr_pct /= 100
    max_order_size_pct /= 100
    min_order_size_pct /= 100

    return StaticVariables(
        divide_records_array_size_by=divide_records_array_size_by,
        fee_pct=fee_pct,
        lev_mode=lev_mode,
        max_lev=max_lev,
        max_order_size_pct=max_order_size_pct,
        max_order_size_value=max_order_size_value,
        min_order_size_pct=min_order_size_pct,
        min_order_size_value=min_order_size_value,
        mmr_pct=mmr_pct,
        order_type=order_type,
        size_type=size_type,
        sl_to_be_then_trail=sl_to_be_then_trail,
        sl_to_be=sl_to_be,
        tsl_true_or_false=tsl_true_or_false,
        upside_filter=upside_filter,
    )


@njit(cache=True)
def create_1d_arrays_nb(
    leverage,
    max_equity_risk_pct,
    max_equity_risk_value,
    risk_rewards,
    size_pct,
    size_value,
    sl_pcts,
    sl_to_be_based_on,
    sl_to_be_trail_by_when_pct_from_avg_entry,
    sl_to_be_when_pct_from_avg_entry,
    sl_to_be_zero_or_entry,
    tsl_pcts_init,
    tsl_based_on,
    tsl_trail_by_pct,
    tsl_when_pct_from_avg_entry,
    tp_pcts,
) -> Arrays1dTuple:
    """
    Convert order parameters to 1D arrays and apply percentage conversions.

    This function takes individual order parameters (scalars, lists, or arrays) and
    normalizes them into uniform 1D float arrays. It also converts percentage values
    (which are expected as raw percentages like 10.0 for 10%) into decimal form
    (0.10) for internal calculations.

    This is a preprocessing step used by simulate_up_to_6_nb() to prepare parameters
    before validation via check_1d_arrays_nb() or cartesian product generation via
    create_cart_product_nb().

    Parameters
    ----------
    leverage : scalar or array-like
        Leverage multiplier(s)
    max_equity_risk_pct : scalar or array-like
        Max equity risk percentage(s). Will be divided by 100.
    max_equity_risk_value : scalar or array-like
        Max equity risk value(s) in dollars
    risk_rewards : scalar or array-like
        Risk-reward ratio(s) for TP calculation
    size_pct : scalar or array-like
        Position size percentage(s). Will be divided by 100.
    size_value : scalar or array-like
        Position size value(s) in dollars
    sl_pcts : scalar or array-like
        Stop loss percentage(s) from entry. Will be divided by 100.
    sl_to_be_based_on : scalar or array-like
        Price basis for breakeven calculation (SL_BE_or_Trail_BasedOn enum)
    sl_to_be_trail_by_when_pct_from_avg_entry : scalar or array-like
        Trailing distance after breakeven. Will be divided by 100.
    sl_to_be_when_pct_from_avg_entry : scalar or array-like
        Profit threshold to trigger breakeven. Will be divided by 100.
    sl_to_be_zero_or_entry : scalar or array-like
        Move SL to zero (0) or entry price (1)
    tsl_pcts_init : scalar or array-like
        Initial trailing stop distance. Will be divided by 100.
    tsl_based_on : scalar or array-like
        Price basis for TSL (SL_BE_or_Trail_BasedOn enum)
    tsl_trail_by_pct : scalar or array-like
        TSL trailing percentage. Will be divided by 100.
    tsl_when_pct_from_avg_entry : scalar or array-like
        Profit threshold to activate TSL. Will be divided by 100.
    tp_pcts : scalar or array-like
        Take profit percentage(s) from entry. Will be divided by 100.

    Returns
    -------
    Arrays1dTuple
        Named tuple containing all parameters as 1D float arrays with:
        - Percentage values converted to decimals
        - All arrays properly shaped via to_1d_array_nb()
        - Ready for validation or cartesian product generation

    Notes
    -----
    **Percentage Conversions** (divided by 100):
        - max_equity_risk_pct: 2.0 → 0.02
        - size_pct: 10.0 → 0.10
        - sl_pcts: 3.0 → 0.03
        - sl_to_be_trail_by_when_pct_from_avg_entry: 1.0 → 0.01
        - sl_to_be_when_pct_from_avg_entry: 5.0 → 0.05
        - tsl_pcts_init: 4.0 → 0.04
        - tsl_trail_by_pct: 1.5 → 0.015
        - tsl_when_pct_from_avg_entry: 3.0 → 0.03
        - tp_pcts: 6.0 → 0.06

    **No Conversion** (kept as-is):
        - leverage, max_equity_risk_value, risk_rewards, size_value
        - sl_to_be_based_on, sl_to_be_zero_or_entry, tsl_based_on

    **Array Normalization**:
        All parameters are converted to float and passed through to_1d_array_nb()
        which handles scalar expansion and dimension normalization.

    Examples
    --------
    >>> # Convert mixed scalar/array parameters
    >>> arrays = create_1d_arrays_nb(
    ...     leverage=np.array([2, 3, 5]),
    ...     max_equity_risk_pct=2.0,  # 2% → 0.02
    ...     max_equity_risk_value=np.nan,
    ...     risk_rewards=2.0,
    ...     size_pct=np.array([10, 20, 30]),  # 10%, 20%, 30% → 0.1, 0.2, 0.3
    ...     size_value=np.nan,
    ...     sl_pcts=3.0,  # 3% → 0.03
    ...     sl_to_be_based_on=np.nan,
    ...     sl_to_be_trail_by_when_pct_from_avg_entry=np.nan,
    ...     sl_to_be_when_pct_from_avg_entry=np.nan,
    ...     sl_to_be_zero_or_entry=np.nan,
    ...     tsl_pcts_init=np.nan,
    ...     tsl_based_on=np.nan,
    ...     tsl_trail_by_pct=np.nan,
    ...     tsl_when_pct_from_avg_entry=np.nan,
    ...     tp_pcts=6.0,  # 6% → 0.06
    ... )
    >>> arrays.leverage  # array([2., 3., 5.])
    >>> arrays.size_pct  # array([0.1, 0.2, 0.3])
    >>> arrays.sl_pcts  # array([0.03])
    >>> arrays.tp_pcts  # array([0.06])

    See Also
    --------
    check_1d_arrays_nb : Validates the arrays created by this function
    create_cart_product_nb : Creates cartesian product from these arrays
    to_1d_array_nb : Reshapes individual arrays to 1D
    simulate_up_to_6_nb : Uses this function to prepare parameters
    """
    leverage_array = to_1d_array_nb(np.asarray(leverage, dtype=np.float_))

    max_equity_risk_pct_array = to_1d_array_nb(
        np.asarray(np.asarray(max_equity_risk_pct) / 100, dtype=np.float_)
    )

    max_equity_risk_value_array = to_1d_array_nb(
        np.asarray(max_equity_risk_value, dtype=np.float_)
    )

    size_pct_array = to_1d_array_nb(
        np.asarray(np.asarray(size_pct) / 100, dtype=np.float_)
    )

    size_value_array = to_1d_array_nb(np.asarray(size_value, dtype=np.float_))

    # Stop Loss Arrays
    sl_pcts_array = to_1d_array_nb(
        np.asarray(np.asarray(sl_pcts) / 100, dtype=np.float_)
    )

    sl_to_be_based_on_array = to_1d_array_nb(
        np.asarray(sl_to_be_based_on, dtype=np.float_)
    )

    sl_to_be_trail_by_when_pct_from_avg_entry_array = to_1d_array_nb(
        np.asarray(
            np.asarray(sl_to_be_trail_by_when_pct_from_avg_entry) / 100, dtype=np.float_
        )
    )

    sl_to_be_when_pct_from_avg_entry_array = to_1d_array_nb(
        np.asarray(np.asarray(sl_to_be_when_pct_from_avg_entry) / 100, dtype=np.float_)
    )

    sl_to_be_zero_or_entry_array = to_1d_array_nb(
        np.asarray(sl_to_be_zero_or_entry, dtype=np.float_)
    )

    # Trailing Stop Loss Arrays
    tsl_pcts_init_array = to_1d_array_nb(
        np.asarray(np.asarray(tsl_pcts_init) / 100, dtype=np.float_)
    )

    tsl_based_on_array = to_1d_array_nb(np.asarray(tsl_based_on, dtype=np.float_))

    tsl_trail_by_pct_array = to_1d_array_nb(
        np.asarray(np.asarray(tsl_trail_by_pct) / 100, dtype=np.float_)
    )

    tsl_when_pct_from_avg_entry_array = to_1d_array_nb(
        np.asarray(np.asarray(tsl_when_pct_from_avg_entry) / 100, dtype=np.float_)
    )

    # Take Profit Arrays
    risk_rewards_array = to_1d_array_nb(np.asarray(risk_rewards, dtype=np.float_))

    tp_pcts_array = to_1d_array_nb(
        np.asarray(np.asarray(tp_pcts) / 100, dtype=np.float_)
    )

    return Arrays1dTuple(
        leverage=leverage_array,
        max_equity_risk_pct=max_equity_risk_pct_array,
        max_equity_risk_value=max_equity_risk_value_array,
        risk_rewards=risk_rewards_array,
        size_pct=size_pct_array,
        size_value=size_value_array,
        sl_pcts=sl_pcts_array,
        sl_to_be_based_on=sl_to_be_based_on_array,
        sl_to_be_trail_by_when_pct_from_avg_entry=sl_to_be_trail_by_when_pct_from_avg_entry_array,
        sl_to_be_when_pct_from_avg_entry=sl_to_be_when_pct_from_avg_entry_array,
        sl_to_be_zero_or_entry=sl_to_be_zero_or_entry_array,
        tp_pcts=tp_pcts_array,
        tsl_based_on=tsl_based_on_array,
        tsl_pcts_init=tsl_pcts_init_array,
        tsl_trail_by_pct=tsl_trail_by_pct_array,
        tsl_when_pct_from_avg_entry=tsl_when_pct_from_avg_entry_array,
    )


@njit(cache=True)
def check_1d_arrays_nb(
    arrays_1d_tuple: Arrays1dTuple,
    static_variables_tuple: StaticVariables,
) -> None:
    """
    Validate order parameter arrays for consistency and correctness.

    This function performs comprehensive validation of all order parameters after they
    have been converted to 1D arrays by create_1d_arrays_nb(). It checks value ranges,
    mutual exclusivity constraints, and ensures parameters are consistent with the
    selected sizing mode, leverage mode, and risk management settings.

    This is called after create_1d_arrays_nb() and before backtesting begins to catch
    configuration errors early.

    Parameters
    ----------
    arrays_1d_tuple : Arrays1dTuple
        Named tuple containing all order parameters as 1D arrays
        (leverage, size_pct, sl_pcts, tp_pcts, etc.)
    static_variables_tuple : StaticVariables
        Static backtest configuration (fee_pct, lev_mode, size_type, etc.)

    Returns
    -------
    None
        This function only validates; it raises errors on invalid input

    Raises
    ------
    ValueError
        **Size Validation**:
        - size_value < 1 or > max_order_size_value or < min_order_size_value
        - size_pct < 1 or > max_order_size_pct or < min_order_size_pct

        **Stop Loss / Take Profit Validation**:
        - sl_pcts is inf or < 0
        - tsl_pcts_init is inf or < 0
        - tp_pcts is inf or < 0

        **Leverage Mode Validation**:
        - lev_mode out of range or not finite
        - When Isolated mode: leverage not between 1 and max_lev
        - When LeastFreeCashUsed mode: leverage is not np.nan
        - When LeastFreeCashUsed mode: both sl and tsl are nan (need one)

        **Risk-Reward Validation**:
        - risk_rewards is inf or < 0
        - risk_rewards set but no sl_pcts or tsl_pcts_init
        - risk_rewards set and tp_pcts also set (mutually exclusive)

        **Risk-Based Sizing Validation**:
        - max_equity_risk_pct is inf or < 0
        - max_equity_risk_value is inf or < 0
        - Both max_equity_risk_pct and max_equity_risk_value are set (mutually exclusive)
        - Both size_value and size_pct are set (mutually exclusive)

        **Size Type Validation**:
        - order_type invalid or out of range
        - SizeType.Amount: size_value is nan or < 1
        - SizeType.PercentOfAccount: size_pct is nan
        - SizeType.RiskAmount or RiskPercentOfAccount: no sl_pcts or tsl_pcts_init
        - SizeType.RiskPercentOfAccount: size_pct is nan

        **Stop Loss to Breakeven (sl_to_be) Validation**:
        - sl_to_be_based_on not in valid range (0-3, see SL_BE_or_Trail_BasedOn enum)
        - sl_to_be_trail_by_when_pct_from_avg_entry is inf or < 0
        - sl_to_be_when_pct_from_avg_entry is inf or < 0
        - sl_to_be_zero_or_entry not 0 or 1
        - sl_to_be is False but sl_to_be_* parameters are set
        - sl_to_be is True but required params missing (sl_to_be_based_on, etc.)
        - sl_to_be_then_trail is True but sl_to_be is False

        **Trailing Stop Loss (tsl) Validation**:
        - tsl_based_on not in valid range (0-3)
        - tsl_trail_by_pct is inf or < 0
        - tsl_when_pct_from_avg_entry is inf or < 0
        - tsl_true_or_false is False but tsl_* parameters are set
        - tsl_true_or_false is True but required params missing

    Notes
    -----
    **Validation Order**:
        1. Size value/percentage range checks
        2. SL/TP/TSL percentage range checks
        3. Leverage mode compatibility
        4. Risk-reward logic
        5. Mutual exclusivity (risk_rewards vs tp_pcts, size_value vs size_pct, etc.)
        6. Size type requirements
        7. SL breakeven parameter consistency
        8. TSL parameter consistency

    **Mutual Exclusivity Rules**:
        - Cannot set both max_equity_risk_pct and max_equity_risk_value
        - Cannot set both size_value and size_pct
        - Cannot set both risk_rewards and tp_pcts
        - Cannot use LeastFreeCashUsed leverage mode without SL or TSL

    **Size Type Requirements**:
        - **Amount**: Requires size_value >= 1
        - **PercentOfAccount**: Requires size_pct > 0
        - **RiskAmount**: Requires sl_pcts or tsl_pcts_init
        - **RiskPercentOfAccount**: Requires size_pct and (sl_pcts or tsl_pcts_init)

    **Stop Loss to Breakeven Requirements**:
        If sl_to_be=True, must provide:
        - sl_to_be_based_on (price basis)
        - sl_to_be_when_pct_from_avg_entry (profit trigger)
        - sl_to_be_zero_or_entry (where to move SL)
        - sl_pcts (initial SL distance)

        If sl_to_be_then_trail=True, additionally requires:
        - sl_to_be_trail_by_when_pct_from_avg_entry (trailing distance)

    **Trailing Stop Loss Requirements**:
        If tsl_true_or_false=True, must provide:
        - tsl_based_on (price basis)
        - tsl_trail_by_pct (trailing percentage)
        - tsl_when_pct_from_avg_entry (activation trigger)
        - tsl_pcts_init (initial distance)

    Examples
    --------
    >>> # Valid configuration for risk-based sizing
    >>> static_vars = StaticVariables(
    ...     size_type=SizeType.RiskPercentOfAccount,
    ...     lev_mode=LeverageMode.Isolated,
    ...     ...
    ... )
    >>> arrays = Arrays1dTuple(
    ...     leverage=np.array([5.0]),
    ...     size_pct=np.array([0.02]),  # Risk 2% of account
    ...     sl_pcts=np.array([0.03]),   # 3% stop loss
    ...     tp_pcts=np.array([0.06]),   # 6% take profit
    ...     ...
    ... )
    >>> check_1d_arrays_nb(arrays, static_vars)  # Passes validation
    >>>
    >>> # Invalid: risk-based sizing without SL
    >>> bad_arrays = Arrays1dTuple(
    ...     leverage=np.array([5.0]),
    ...     size_pct=np.array([0.02]),
    ...     sl_pcts=np.array([np.nan]),  # Missing SL!
    ...     ...
    ... )
    >>> check_1d_arrays_nb(bad_arrays, static_vars)
    ValueError: When using Risk Amount or Risk Percent of Account set a proper sl pct or tsl pct > 0

    See Also
    --------
    create_1d_arrays_nb : Creates the arrays validated by this function
    static_var_checker_nb : Validates static variables
    simulate_up_to_6_nb : Uses this function for parameter validation
    """
    if np.isfinite(arrays_1d_tuple.size_value).all():
        if arrays_1d_tuple.size_value.any() < 1:
            raise ValueError("size_value must be greater than 1.")
        if (
            arrays_1d_tuple.size_value.any()
            > static_variables_tuple.max_order_size_value
        ):
            raise ValueError("size_value is greater than max_order_size_value")

        if (
            arrays_1d_tuple.size_value.any()
            < static_variables_tuple.min_order_size_value
        ):
            raise ValueError("size_value is greater than max_order_size_value")

    if not np.isfinite(arrays_1d_tuple.size_pct).all():
        if arrays_1d_tuple.size_pct.any() < 1:
            raise ValueError("size_pct must be greater than 1.")

        if arrays_1d_tuple.size_pct.any() > static_variables_tuple.max_order_size_pct:
            raise ValueError("size_pct is greater than max_order_size_pct")

        if arrays_1d_tuple.size_pct.any() < static_variables_tuple.min_order_size_pct:
            raise ValueError("size_pct is greater than max_order_size_pct")

    if np.isinf(arrays_1d_tuple.sl_pcts).any() or arrays_1d_tuple.sl_pcts.any() < 0:
        raise ValueError("sl_pcts has to be nan or greater than 0 and not inf")

    if (
        np.isinf(arrays_1d_tuple.tsl_pcts_init).any()
        or arrays_1d_tuple.tsl_pcts_init.any() < 0
    ):
        raise ValueError("tsl_pcts_init has to be nan or greater than 0 and not inf")

    if np.isinf(arrays_1d_tuple.tp_pcts).any() or arrays_1d_tuple.tp_pcts.any() < 0:
        raise ValueError("tp_pcts has to be nan or greater than 0 and not inf")

    if (0 > static_variables_tuple.lev_mode > len(LeverageMode)) or not np.isfinite(
        static_variables_tuple.lev_mode
    ):
        raise ValueError("leverage mode is out of range or not finite")

    check_sl_tsl_for_nan = (
        np.isnan(arrays_1d_tuple.sl_pcts).any()
        and np.isnan(arrays_1d_tuple.tsl_pcts_init).any()
    )

    # if leverage is too big or too small
    if static_variables_tuple.lev_mode == LeverageMode.Isolated:
        if not np.isfinite(arrays_1d_tuple.leverage).any() or (
            arrays_1d_tuple.leverage.any() > static_variables_tuple.max_lev
            or arrays_1d_tuple.leverage.any() < 0
        ):
            raise ValueError("leverage needs to be between 1 and max lev")
    if static_variables_tuple.lev_mode == LeverageMode.LeastFreeCashUsed:
        if check_sl_tsl_for_nan:
            raise ValueError(
                "When using Least Free Cash Used set a proper sl or tsl > 0"
            )
        if np.isfinite(arrays_1d_tuple.leverage).any():
            raise ValueError(
                "When using Least Free Cash Used leverage iso must be np.nan"
            )

    # making sure we have a number greater than 0 for rr
    if (
        np.isinf(arrays_1d_tuple.risk_rewards).any()
        or arrays_1d_tuple.risk_rewards.any() < 0
    ):
        raise ValueError("Risk Rewards has to be greater than 0 or np.nan")

    # check if RR has sl pct / price or tsl pct / price
    if not np.isnan(arrays_1d_tuple.risk_rewards).any() and check_sl_tsl_for_nan:
        raise ValueError("When risk to reward is set you have to have a sl or tsl > 0")

    if (
        arrays_1d_tuple.risk_rewards.any() > 0
        and np.isfinite(arrays_1d_tuple.tp_pcts).any()
    ):
        raise ValueError("You can't have take profits set when using Risk to reward")

    if (
        np.isinf(arrays_1d_tuple.max_equity_risk_pct).any()
        or arrays_1d_tuple.max_equity_risk_pct.any() < 0
    ):
        raise ValueError("Max equity risk percent has to be greater than 0 or np.nan")

    elif (
        np.isinf(arrays_1d_tuple.max_equity_risk_value).any()
        or arrays_1d_tuple.max_equity_risk_value.any() < 0
    ):
        raise ValueError("Max equity risk has to be greater than 0 or np.nan")

    if (
        not np.isnan(arrays_1d_tuple.max_equity_risk_pct).any()
        and not np.isnan(arrays_1d_tuple.max_equity_risk_value).any()
    ):
        raise ValueError(
            "You can't have max risk pct and max risk value both set at the same time."
        )
    if (
        not np.isnan(arrays_1d_tuple.size_value).any()
        and not np.isnan(arrays_1d_tuple.size_pct).any()
    ):
        raise ValueError("You can't have size and size pct set at the same time.")

    # simple check if order size type is valid
    if 0 > static_variables_tuple.order_type > len(OrderType) or not np.isfinite(
        static_variables_tuple.order_type
    ):
        raise ValueError("order_type is invalid")

    # Getting the right size for Size Type Amount
    if static_variables_tuple.size_type == SizeType.Amount:
        if (
            np.isnan(arrays_1d_tuple.size_value).any()
            or arrays_1d_tuple.size_value.any() < 1
        ):
            raise ValueError(
                "With SizeType as amount, size_value must be 1 or greater."
            )

    if static_variables_tuple.size_type == SizeType.PercentOfAccount:
        if np.isnan(arrays_1d_tuple.size_pct).any():
            raise ValueError("You need size_pct to be > 0 if using percent of account.")

    # checking to see if you set a stop loss for risk based size types
    if (
        static_variables_tuple.size_type == SizeType.RiskAmount
        or (static_variables_tuple.size_type == SizeType.RiskPercentOfAccount)
        and check_sl_tsl_for_nan
    ):
        raise ValueError(
            "When using Risk Amount or Risk Percent of Account set a proper sl pct or tsl pct > 0"
        )

    # setting risk percent size
    if static_variables_tuple.size_type == SizeType.RiskPercentOfAccount:
        if np.isnan(arrays_1d_tuple.size_pct).any():
            raise ValueError(
                "You need size_pct to be > 0 if using risk percent of account."
            )

    # stop loss break even checks
    if np.isfinite(arrays_1d_tuple.sl_to_be_based_on).any() and (
        arrays_1d_tuple.sl_to_be_based_on.any() < SL_BE_or_Trail_BasedOn.open_price
        or arrays_1d_tuple.sl_to_be_based_on.any() > SL_BE_or_Trail_BasedOn.close_price
    ):
        raise ValueError(
            "You need sl_to_be_based_on to be be either 0 1 2 or 3. look up SL_BE_or_Trail_BasedOn enums"
        )

    if (
        np.isinf(arrays_1d_tuple.sl_to_be_trail_by_when_pct_from_avg_entry).any()
        or arrays_1d_tuple.sl_to_be_trail_by_when_pct_from_avg_entry.any() < 0
    ):
        raise ValueError(
            "You need sl_to_be_trail_by_when_pct_from_avg_entry to be > 0 or not inf."
        )

    if (
        np.isinf(arrays_1d_tuple.sl_to_be_when_pct_from_avg_entry).any()
        or arrays_1d_tuple.sl_to_be_when_pct_from_avg_entry.any() < 0
    ):
        raise ValueError(
            "You need sl_to_be_when_pct_from_avg_entry to be > 0 or not inf."
        )

    if (
        arrays_1d_tuple.sl_to_be_zero_or_entry.any() < 0
        or arrays_1d_tuple.sl_to_be_zero_or_entry.any() > 1
    ):
        raise ValueError("sl_to_be_zero_or_entry needs to be 0 for zero or 1 for entry")

    if static_variables_tuple.sl_to_be == False:
        if np.isfinite(arrays_1d_tuple.sl_to_be_based_on).any():
            raise ValueError("sl_to_be needs to be True to use sl_to_be_based_on.")
        if static_variables_tuple.sl_to_be_then_trail == True:
            raise ValueError("sl_to_be needs to be True to use sl_to_be_then_trail.")
        if np.isfinite(arrays_1d_tuple.sl_to_be_trail_by_when_pct_from_avg_entry).any():
            raise ValueError(
                "sl_to_be needs to be True to use sl_to_be_trail_by_when_pct_from_avg_entry."
            )
        if np.isfinite(arrays_1d_tuple.sl_to_be_when_pct_from_avg_entry).any():
            raise ValueError(
                "sl_to_be needs to be True to use sl_to_be_when_pct_from_avg_entry."
            )
        if np.isfinite(arrays_1d_tuple.sl_to_be_zero_or_entry).any():
            raise ValueError("sl_to_be needs to be True to use sl_to_be_zero_or_entry.")

    if static_variables_tuple.sl_to_be and (
        not np.isfinite(arrays_1d_tuple.sl_to_be_based_on).any()
        or not np.isfinite(arrays_1d_tuple.sl_to_be_when_pct_from_avg_entry).any()
        or not np.isfinite(arrays_1d_tuple.sl_to_be_zero_or_entry).any()
        or not np.isfinite(arrays_1d_tuple.sl_pcts).any()
    ):
        raise ValueError(
            "If you have sl_to_be set to true then you must provide the other params like sl_pcts etc"
        )

    if (
        static_variables_tuple.sl_to_be and static_variables_tuple.sl_to_be_then_trail
    ) and (
        not np.isfinite(arrays_1d_tuple.sl_to_be_based_on).any()
        or not np.isfinite(arrays_1d_tuple.sl_to_be_when_pct_from_avg_entry).any()
        or not np.isfinite(arrays_1d_tuple.sl_to_be_zero_or_entry).any()
        or not np.isfinite(
            arrays_1d_tuple.sl_to_be_trail_by_when_pct_from_avg_entry
        ).any()
        or not np.isfinite(arrays_1d_tuple.sl_pcts).any()
    ):
        raise ValueError(
            "If you have sl_to_be set to true then you must provide the other params like sl_pcts etc"
        )

    # tsl Checks
    if np.isfinite(arrays_1d_tuple.tsl_based_on).any() and (
        arrays_1d_tuple.tsl_based_on.any() < SL_BE_or_Trail_BasedOn.open_price
        or arrays_1d_tuple.tsl_based_on.any() > SL_BE_or_Trail_BasedOn.close_price
    ):
        raise ValueError(
            "You need tsl_to_be_based_on to be be either 0 1 2 or 3. look up SL_BE_or_Trail_BasedOn enums"
        )

    if (
        np.isinf(arrays_1d_tuple.tsl_trail_by_pct).any()
        or arrays_1d_tuple.tsl_trail_by_pct.any() < 0
    ):
        raise ValueError("You need tsl_trail_by_pct to be > 0 or not inf.")

    if (
        np.isinf(arrays_1d_tuple.tsl_when_pct_from_avg_entry).any()
        or arrays_1d_tuple.tsl_when_pct_from_avg_entry.any() < 0
    ):
        raise ValueError("You need tsl_when_pct_from_avg_entry to be > 0 or not inf.")

    if static_variables_tuple.tsl_true_or_false == False:
        if np.isfinite(arrays_1d_tuple.tsl_based_on).any():
            raise ValueError("tsl_true_or_false needs to be True to use tsl_based_on.")
        if np.isfinite(arrays_1d_tuple.tsl_trail_by_pct).any():
            raise ValueError(
                "tsl_true_or_false needs to be True to use tsl_trail_by_pct."
            )
        if np.isfinite(arrays_1d_tuple.tsl_when_pct_from_avg_entry).any():
            raise ValueError(
                "tsl_true_or_false needs to be True to use tsl_when_pct_from_avg_entry."
            )

    if static_variables_tuple.tsl_true_or_false and (
        not np.isfinite(arrays_1d_tuple.tsl_based_on).any()
        or not np.isfinite(arrays_1d_tuple.tsl_trail_by_pct).any()
        or not np.isfinite(arrays_1d_tuple.tsl_when_pct_from_avg_entry).any()
        or not np.isfinite(arrays_1d_tuple.tsl_pcts_init).any()
    ):
        raise ValueError(
            "If you have tsl_true_or_false set to true then you must provide the other params like tsl_pcts_init etc"
        )


@njit(cache=True)
def create_cart_product_nb(
    arrays_1d_tuple: Arrays1dTuple,
) -> Arrays1dTuple:
    """
    Generate cartesian product of all order parameter arrays.

    This function takes validated 1D parameter arrays and creates a cartesian product,
    producing all possible combinations of the input parameters. This is used for
    exhaustive parameter sweep testing where every combination should be backtested.

    For example, if testing 3 leverage values, 5 stop loss percentages, and 4 take
    profit percentages, this creates 3 × 5 × 4 = 60 parameter combinations.

    The function uses an efficient numba-compatible algorithm that avoids Python loops
    and itertools, making it suitable for large parameter spaces.

    Parameters
    ----------
    arrays_1d_tuple : Arrays1dTuple
        Named tuple containing all order parameters as 1D arrays.
        All arrays should already be validated via check_1d_arrays_nb().
        Arrays can be different lengths - cartesian product handles this.

    Returns
    -------
    Arrays1dTuple
        Named tuple with same structure as input, but each array now has length
        equal to the total number of combinations (product of all input array sizes).
        Each position in the output arrays represents one complete parameter combination.

    Notes
    -----
    **Cartesian Product Logic**:
        Given input arrays of sizes [n₁, n₂, ..., nₖ], output arrays have size
        n₁ × n₂ × ... × nₖ. The rightmost parameters vary fastest (inner loop).

    **Example Combination Order**:
        Input:
        - leverage = [2, 5, 10]
        - sl_pcts = [0.02, 0.03]
        - (all other params single values)

        Output indices:
        - [0]: lev=2, sl=0.02
        - [1]: lev=2, sl=0.03
        - [2]: lev=5, sl=0.02
        - [3]: lev=5, sl=0.03
        - [4]: lev=10, sl=0.02
        - [5]: lev=10, sl=0.03

    **Memory Consideration**:
        Output size = product of all input sizes. Large parameter sweeps can create
        millions of combinations. Use divide_records_array_size_by in static_variables
        to reduce memory usage when applying strict result filters.

    **Implementation Details**:
        - Uses numpy operations for efficiency under numba JIT compilation
        - Two-pass algorithm: first fills columns, then replicates rows
        - Avoids Python loops and itertools for numba compatibility
        - Returns new Arrays1dTuple with cartesian product arrays

    Examples
    --------
    >>> # Create cartesian product of 2 parameters
    >>> import numpy as np
    >>> arrays = Arrays1dTuple(
    ...     leverage=np.array([2.0, 5.0]),
    ...     max_equity_risk_pct=np.array([0.01]),
    ...     max_equity_risk_value=np.array([np.nan]),
    ...     risk_rewards=np.array([2.0]),
    ...     size_pct=np.array([0.1, 0.2]),
    ...     size_value=np.array([np.nan]),
    ...     sl_pcts=np.array([0.03]),
    ...     sl_to_be_based_on=np.array([np.nan]),
    ...     sl_to_be_trail_by_when_pct_from_avg_entry=np.array([np.nan]),
    ...     sl_to_be_when_pct_from_avg_entry=np.array([np.nan]),
    ...     sl_to_be_zero_or_entry=np.array([np.nan]),
    ...     tp_pcts=np.array([0.06]),
    ...     tsl_based_on=np.array([np.nan]),
    ...     tsl_pcts_init=np.array([np.nan]),
    ...     tsl_trail_by_pct=np.array([np.nan]),
    ...     tsl_when_pct_from_avg_entry=np.array([np.nan]),
    ... )
    >>> cart_product = create_cart_product_nb(arrays)
    >>> # Result has 2 × 2 = 4 combinations:
    >>> cart_product.leverage  # array([2., 2., 5., 5.])
    >>> cart_product.size_pct  # array([0.1, 0.2, 0.1, 0.2])
    >>> cart_product.sl_pcts   # array([0.03, 0.03, 0.03, 0.03])

    >>> # Larger example with 3 varying parameters
    >>> arrays_large = Arrays1dTuple(
    ...     leverage=np.array([2.0, 5.0, 10.0]),      # 3 values
    ...     size_pct=np.array([0.1, 0.2]),           # 2 values
    ...     sl_pcts=np.array([0.02, 0.03, 0.05]),    # 3 values
    ...     # ... rest single values ...
    ... )
    >>> cart_large = create_cart_product_nb(arrays_large)
    >>> len(cart_large.leverage)  # 3 × 2 × 3 = 18 combinations

    See Also
    --------
    create_1d_arrays_nb : Creates the input arrays
    check_1d_arrays_nb : Validates arrays before cartesian product
    backtest_df_only_nb : Uses cartesian product for parameter sweep
    """
    # dtype_names = (
    #     'order_settings_id',
    #     'leverage',
    #     'max_equity_risk_pct',
    #     'max_equity_risk_value',
    #     'risk_rewards',
    #     'size_pct',
    #     'size_value',
    #     'sl_pcts',
    #     'sl_to_be_based_on',
    #     'sl_to_be_trail_by_when_pct_from_avg_entry',
    #     'sl_to_be_when_pct_from_avg_entry',
    #     'sl_to_be_zero_or_entry',
    #     'tp_pcts',
    #     'tsl_based_on',
    #     'tsl_pcts_init',
    #     'tsl_trail_by_pct',
    #     'tsl_when_pct_from_avg_entry',
    # )

    # cart array loop
    n = 1
    for x in arrays_1d_tuple:
        n *= x.size
    out = np.empty((n, len(arrays_1d_tuple)))

    for i in range(len(arrays_1d_tuple)):
        m = int(n / arrays_1d_tuple[i].size)
        out[:n, i] = np.repeat(arrays_1d_tuple[i], m)
        n //= arrays_1d_tuple[i].size

    n = arrays_1d_tuple[-1].size
    for k in range(len(arrays_1d_tuple) - 2, -1, -1):
        n *= arrays_1d_tuple[k].size
        m = int(n / arrays_1d_tuple[k].size)
        for j in range(1, arrays_1d_tuple[k].size):
            out[j * m : (j + 1) * m, k + 1 :] = out[0:m, k + 1 :]

    # # literal unroll
    # counter = 0
    # for dtype_name in literal_unroll(dtype_names):
    #     for col in range(n):
    #         cart_array[dtype_name][col] = out[col][counter]
    #     counter += 1

    # Setting variable arrys from cart arrays
    leverage_cart_array = out.T[0]
    max_equity_risk_pct_cart_array = out.T[1]
    max_equity_risk_value_cart_array = out.T[2]
    risk_rewards_cart_array = out.T[3]
    size_pct_cart_array = out.T[4]
    size_value_cart_array = out.T[5]
    sl_pcts_cart_array = out.T[6]
    sl_to_be_based_on_cart_array = out.T[7]
    sl_to_be_trail_by_when_pct_from_avg_entry_cart_array = out.T[8]
    sl_to_be_when_pct_from_avg_entry_cart_array = out.T[9]
    sl_to_be_zero_or_entry_cart_array = out.T[10]
    tp_pcts_cart_array = out.T[11]
    tsl_based_on_cart_array = out.T[12]
    tsl_pcts_init_cart_array = out.T[13]
    tsl_trail_by_pct_cart_array = out.T[14]
    tsl_when_pct_from_avg_entry_cart_array = out.T[15]

    # leverage_cart_array = cart_array['leverage']
    # max_equity_risk_pct_cart_array = cart_array['max_equity_risk_pct']
    # max_equity_risk_value_cart_array = cart_array['max_equity_risk_value']
    # risk_rewards_cart_array = cart_array['risk_rewards']
    # size_pct_cart_array = cart_array['size_pct']
    # size_value_cart_array = cart_array['size_value']
    # sl_pcts_cart_array = cart_array['sl_pcts']
    # sl_to_be_based_on_cart_array = cart_array['sl_to_be_based_on']
    # sl_to_be_trail_by_when_pct_from_avg_entry_cart_array = cart_array[
    #     'sl_to_be_trail_by_when_pct_from_avg_entry']
    # sl_to_be_when_pct_from_avg_entry_cart_array = cart_array[
    #     'sl_to_be_when_pct_from_avg_entry']
    # sl_to_be_zero_or_entry_cart_array = cart_array['sl_to_be_zero_or_entry']
    # tp_pcts_cart_array = cart_array['tp_pcts']
    # tsl_based_on_cart_array = cart_array['tsl_based_on']
    # tsl_pcts_init_cart_array = cart_array['tsl_pcts_init']
    # tsl_trail_by_pct_cart_array = cart_array['tsl_trail_by_pct']
    # tsl_when_pct_from_avg_entry_cart_array = cart_array['tsl_when_pct_from_avg_entry']

    return Arrays1dTuple(
        leverage_cart_array,
        max_equity_risk_pct_cart_array,
        max_equity_risk_value_cart_array,
        risk_rewards_cart_array,
        size_pct_cart_array,
        size_value_cart_array,
        sl_pcts_cart_array,
        sl_to_be_based_on_cart_array,
        sl_to_be_trail_by_when_pct_from_avg_entry_cart_array,
        sl_to_be_when_pct_from_avg_entry_cart_array,
        sl_to_be_zero_or_entry_cart_array,
        tp_pcts_cart_array,
        tsl_based_on_cart_array,
        tsl_pcts_init_cart_array,
        tsl_trail_by_pct_cart_array,
        tsl_when_pct_from_avg_entry_cart_array,
    )


@njit(cache=True)
def fill_order_records_nb(
    bar: int,  # time stamp
    order_records: RecordArray,
    order_settings_counter: int,
    order_records_id: Array1d,
    account_state: AccountState,
    order_result: OrderResult,
) -> RecordArray:
    """
    Fill a single order record with execution details.

    This function populates one row of the order_records array with details about
    an executed order (entry or exit). It captures the complete state of the order
    including price, size, fees, PnL, and stop/target prices. The order_records_id
    is incremented after filling to prepare for the next order.

    This is called by process_order_nb() after each order execution to maintain
    a complete audit trail of all trading activity.

    Parameters
    ----------
    bar : int
        Bar index (timestamp) when order was executed
    order_records : RecordArray
        Single record (row) from the order_records array to fill.
        This is typically order_records[order_records_id[0]].
    order_settings_counter : int
        Index identifying which parameter combination is being tested
    order_records_id : Array1d
        Single-element array [current_id] tracking next record to fill.
        Will be incremented by 1 after filling.
    account_state : AccountState
        Current account state after order execution (equity, balance, etc.)
    order_result : OrderResult
        Order execution result containing price, size, fees, PnL, stops, etc.

    Returns
    -------
    RecordArray
        The filled order_records row (same object passed in)

    Notes
    -----
    **Record Fields Populated**:
        - avg_entry: Average entry price for position
        - bar: Timestamp (bar index) of execution
        - equity: Account equity after order
        - fees_paid: Fees charged for this order
        - order_set_id: Parameter combination ID
        - order_id: Unique sequential order ID
        - order_type: Entry/exit type (LongEntry, ShortSL, etc.)
        - price: Execution price
        - real_pnl: Realized PnL (rounded to 4 decimals)
        - size_value: Order size in dollars
        - sl_prices: Stop loss price
        - tp_prices: Take profit price
        - tsl_prices: Trailing stop price

    **Side Effects**:
        order_records_id[0] is incremented by 1

    **Usage Context**:
        This function is called internally by process_order_nb() and
        check_sl_tp_nb() whenever an order executes. Users typically don't
        call this directly but instead receive the filled order_records array
        as output from simulate_up_to_6_nb() or similar functions.

    Examples
    --------
    >>> # Typical internal usage (simplified)
    >>> order_records = np.empty(100, dtype=or_dt)
    >>> order_records_id = np.array([0])
    >>> account_state = AccountState(equity=1050.0, ...)
    >>> order_result = OrderResult(
    ...     price=50000.0,
    ...     size_value=500.0,
    ...     fees_paid=0.50,
    ...     realized_pnl=50.0,
    ...     ...
    ... )
    >>> fill_order_records_nb(
    ...     bar=42,
    ...     order_records=order_records[0],
    ...     order_settings_counter=5,
    ...     order_records_id=order_records_id,
    ...     account_state=account_state,
    ...     order_result=order_result,
    ... )
    >>> order_records[0]['bar']  # 42
    >>> order_records[0]['price']  # 50000.0
    >>> order_records[0]['real_pnl']  # 50.0
    >>> order_records_id[0]  # 1 (incremented)

    See Also
    --------
    fill_strat_records_nb : Fill strategy-level trade records
    process_order_nb : Calls this function after order execution
    check_sl_tp_nb : Calls this function for exit orders
    """
    order_records["avg_entry"] = order_result.average_entry
    order_records["bar"] = bar
    order_records["equity"] = account_state.equity
    order_records["fees_paid"] = order_result.fees_paid
    order_records["order_set_id"] = order_settings_counter
    order_records["order_id"] = order_records_id[0]
    order_records["order_type"] = order_result.order_type
    order_records["price"] = order_result.price
    order_records["real_pnl"] = round(order_result.realized_pnl, 4)
    order_records["size_value"] = order_result.size_value
    order_records["sl_prices"] = order_result.sl_prices
    order_records["tp_prices"] = order_result.tp_prices
    order_records["tsl_prices"] = order_result.tsl_prices

    order_records_id[0] += 1


@njit(cache=True)
def fill_strat_records_nb(
    entries_col: int,
    equity: float,
    order_settings_counter: int,
    pnl: float,
    strat_records_filled: Array1d,
    strat_records: RecordArray,
    symbol_counter: int,
) -> RecordArray:
    """
    Fill a single strategy record with trade-level PnL and metadata.

    This function populates one row of the strat_records array with details about
    a completed trade. Unlike order_records which track individual order executions,
    strat_records track complete round-trip trades (entry to exit) with realized PnL.

    This is called by process_order_nb() when closing a position to record the
    trade's profitability and context.

    Parameters
    ----------
    entries_col : int
        Entry signal column index (identifies which indicator generated the signal)
    equity : float
        Account equity after trade completion
    order_settings_counter : int
        Index identifying which order parameter combination was used
    pnl : float
        Realized profit/loss from the completed trade
    strat_records_filled : Array1d
        Single-element array [count] tracking how many records have been filled.
        Will be incremented by 1 after filling.
    strat_records : RecordArray
        Single record (row) from the strat_records array to fill.
        This is typically strat_records[strat_records_filled[0]].
    symbol_counter : int
        Index identifying which symbol was traded

    Returns
    -------
    RecordArray
        The filled strat_records row (same object passed in)

    Notes
    -----
    **Record Fields Populated**:
        - equity: Account equity after trade
        - entries_col: Entry signal source
        - or_set: Order settings ID
        - symbol: Symbol counter
        - real_pnl: Realized PnL (rounded to 4 decimals)

    **Side Effects**:
        strat_records_filled[0] is incremented by 1

    **Trade vs Order Records**:
        - **Order records**: One record per order execution (both entries and exits)
        - **Strategy records**: One record per completed round-trip trade
        - Order records track execution details; strategy records track profitability

    **PnL Rounding**:
        PnL is rounded to 4 decimal places to avoid floating-point precision issues
        when calculating aggregate statistics.

    **Usage Context**:
        Called internally by process_order_nb() when an exit order closes a position.
        Used by backtest_df_only_nb() to calculate strategy performance metrics
        like win rate, total PnL, and to-the-upside R² values.

    Examples
    --------
    >>> # Typical internal usage
    >>> strat_records = np.empty(100, dtype=strat_records_dt)
    >>> strat_records_filled = np.array([0])
    >>> fill_strat_records_nb(
    ...     entries_col=3,
    ...     equity=1050.0,
    ...     order_settings_counter=7,
    ...     pnl=50.75,
    ...     strat_records_filled=strat_records_filled,
    ...     strat_records=strat_records[0],
    ...     symbol_counter=0,
    ... )
    >>> strat_records[0]['real_pnl']  # 50.75
    >>> strat_records[0]['equity']  # 1050.0
    >>> strat_records[0]['entries_col']  # 3
    >>> strat_records_filled[0]  # 1 (incremented)

    See Also
    --------
    fill_order_records_nb : Fill order-level execution records
    fill_strategy_result_records_nb : Fill aggregated strategy performance
    process_order_nb : Calls this function when closing positions
    """
    strat_records["equity"] = equity
    strat_records["entries_col"] = entries_col
    strat_records["or_set"] = order_settings_counter
    strat_records["symbol"] = symbol_counter
    strat_records["real_pnl"] = round(pnl, 4)

    strat_records_filled[0] += 1


@njit(cache=True)
def get_to_the_upside_nb(
    gains_pct: float,
    wins_and_losses_array_no_be: Array1d,
) -> float:
    """
    Calculate to-the-upside metric (R² of cumulative PnL regression).

    This function computes a quality metric for the equity curve by fitting a linear
    regression to the cumulative PnL and calculating the coefficient of determination
    (R²). Higher R² values indicate smoother, more consistent profit growth. The sign
    is inverted for losing strategies to distinguish them from winners.

    The to-the-upside metric helps identify strategies with:
    - Consistent profitability (high positive R²)
    - Smooth equity curves (vs erratic/choppy PnL)
    - Reliable edge (vs lucky streaks)

    Parameters
    ----------
    gains_pct : float
        Total profit percentage for the strategy.
        Used to determine sign of result (positive for winners, negative for losers).
    wins_and_losses_array_no_be : Array1d
        Array of realized PnL values for completed trades, excluding breakeven trades (PnL = 0).
        These are the individual trade profits/losses that will be analyzed.

    Returns
    -------
    float
        R² coefficient of determination for cumulative PnL linear regression.
        - **Positive R² (0 to 1)**: Winning strategies (gains_pct > 0)
          - Close to 1: Very smooth upward equity curve
          - Close to 0: Erratic equity curve despite overall profit
        - **Negative R² (0 to -1)**: Losing strategies (gains_pct <= 0)
          - Negated to distinguish from winners
          - More negative = smoother downward curve

    Notes
    -----
    **Calculation Method**:
        1. Create x-axis: [1, 2, 3, ..., n] for n trades
        2. Create y-axis: Cumulative sum of PnL array
        3. Fit linear regression: y_pred = b0 + b1 * x
        4. Calculate R² = Σ(y_pred - y_mean)² / Σ(y - y_mean)²
        5. Negate R² if gains_pct <= 0

    **Interpretation**:
        - **R² = 0.95**: 95% of PnL variance explained by linear trend (very smooth)
        - **R² = 0.50**: 50% explained (moderate consistency)
        - **R² = 0.10**: 10% explained (erratic, may be luck)
        - **R² = -0.80**: Losing strategy with smooth decline

    **Why Exclude Breakeven Trades**:
        Breakeven trades (PnL = 0) don't contribute to cumulative growth and
        can artificially inflate R² by adding flat segments. Excluding them
        focuses the metric on actual profit/loss dynamics.

    **Usage in Filtering**:
        backtest_df_only_nb() uses this metric with upside_filter to exclude
        strategies with low R² (erratic equity curves) even if profitable.

    **Mathematical Background**:
        R² measures goodness of fit for linear regression. High R² means
        cumulative PnL follows a straight line, indicating consistent
        per-trade profitability rather than dependence on a few outlier wins.

    Examples
    --------
    >>> # Smooth winning strategy
    >>> trades_smooth = np.array([10.0, 12.0, 11.0, 13.0, 10.0])
    >>> r2_smooth = get_to_the_upside_nb(gains_pct=56.0, wins_and_losses_array_no_be=trades_smooth)
    >>> r2_smooth  # ~0.98 (very high R²)

    >>> # Erratic winning strategy
    >>> trades_erratic = np.array([-5.0, -3.0, 80.0, -2.0, -4.0])  # One big win
    >>> r2_erratic = get_to_the_upside_nb(gains_pct=66.0, wins_and_losses_array_no_be=trades_erratic)
    >>> r2_erratic  # ~0.20 (low R², depends on luck)

    >>> # Losing strategy
    >>> trades_losing = np.array([-10.0, -8.0, -12.0, -9.0])
    >>> r2_losing = get_to_the_upside_nb(gains_pct=-39.0, wins_and_losses_array_no_be=trades_losing)
    >>> r2_losing  # Negative (e.g., -0.95 for smooth decline)

    See Also
    --------
    fill_strategy_result_records_nb : Uses this metric in strategy results
    backtest_df_only_nb : Filters strategies by upside_filter threshold
    """
    x = np.arange(1, len(wins_and_losses_array_no_be) + 1)
    y = wins_and_losses_array_no_be.cumsum()

    xm = x.mean()
    ym = y.mean()

    y_ym = y - ym
    y_ym_s = y_ym**2

    x_xm = x - xm
    x_xm_s = x_xm**2

    b1 = (x_xm * y_ym).sum() / x_xm_s.sum()
    b0 = ym - b1 * xm

    y_pred = b0 + b1 * x

    yp_ym = y_pred - ym

    yp_ym_s = yp_ym**2

    to_the_upside = yp_ym_s.sum() / y_ym_s.sum()

    if gains_pct <= 0:
        to_the_upside = -to_the_upside
    return to_the_upside


@njit(cache=True)
def fill_strategy_result_records_nb(
    gains_pct: float,
    strategy_result_records: RecordArray,
    temp_strat_records: Array1d,
    to_the_upside: float,
    total_trades: int,
    wins_and_losses_array_no_be: Array1d,
) -> RecordArray:
    """
    Fill strategy performance record with aggregated statistics.

    This function calculates and populates a strategy result record with comprehensive
    performance metrics including gains, win rate, total PnL, and to-the-upside R².
    It aggregates data from individual trade records (strat_records) into a single
    summary row for strategies that passed all filters.

    This is called by backtest_df_only_nb() after a strategy passes all filters
    (gains, trade count, R²) to record its performance metrics.

    Parameters
    ----------
    gains_pct : float
        Total profit percentage: ((final_equity - initial_equity) / initial_equity) × 100
    strategy_result_records : RecordArray
        Single record (row) from strategy_result_records array to fill.
        This is typically strategy_result_records[result_records_filled].
    temp_strat_records : Array1d
        Array of strategy records (completed trades) for this strategy.
        Subset of full strat_records array: strat_records[0:strat_records_filled[0]]
    to_the_upside : float
        R² metric for equity curve quality (from get_to_the_upside_nb)
    total_trades : int
        Total number of completed trades (including breakeven)
    wins_and_losses_array_no_be : Array1d
        Array of PnL values excluding breakeven trades (PnL != 0)

    Returns
    -------
    RecordArray
        The filled strategy_result_records row (same object passed in)

    Notes
    -----
    **Record Fields Populated**:
        - symbol: Symbol counter from first trade record
        - entries_col: Entry signal column from first trade record
        - or_set: Order settings counter from first trade record
        - total_trades: Number of completed trades
        - gains_pct: Total profit percentage
        - win_rate: Percentage of winning trades (excluding breakeven)
        - to_the_upside: R² equity curve metric
        - total_pnl: Sum of all realized PnL values
        - ending_eq: Final equity from last trade record

    **Win Rate Calculation**:
        - Only considers non-breakeven trades
        - win_rate = (number of trades with PnL > 0) / (total non-BE trades) × 100
        - Rounded to 2 decimal places
        - Example: 7 wins, 3 losses → 70.00%

    **Total PnL**:
        Sum of all PnL values including breakeven trades (from temp_strat_records)

    **Usage Context**:
        Called by backtest_df_only_nb() in the filtering pipeline:
        1. Check gains_pct > gains_pct_filter
        2. Check total_trades > total_trade_filter
        3. Calculate to_the_upside
        4. Check to_the_upside > upside_filter
        5. If all pass → call this function to record results

    Examples
    --------
    >>> # After strategy passes all filters
    >>> temp_strat_records = strat_records[0:10]  # 10 completed trades
    >>> wins_and_losses = np.array([10, -5, 8, -3, 12, 15, -4, 9])  # Excluding BE
    >>> strategy_result_records = np.empty(1, dtype=strat_df_array_dt)
    >>> fill_strategy_result_records_nb(
    ...     gains_pct=42.5,
    ...     strategy_result_records=strategy_result_records[0],
    ...     temp_strat_records=temp_strat_records,
    ...     to_the_upside=0.87,
    ...     total_trades=10,
    ...     wins_and_losses_array_no_be=wins_and_losses,
    ... )
    >>> strategy_result_records[0]['gains_pct']  # 42.5
    >>> strategy_result_records[0]['win_rate']  # 62.5 (5 wins / 8 trades)
    >>> strategy_result_records[0]['total_trades']  # 10
    >>> strategy_result_records[0]['to_the_upside']  # 0.87

    See Also
    --------
    fill_settings_result_records_nb : Fill corresponding settings record
    get_to_the_upside_nb : Calculate R² metric
    fill_strat_records_nb : Fill individual trade records
    backtest_df_only_nb : Uses this to store filtered results
    """
    # win rate calc
    win_loss = np.where(wins_and_losses_array_no_be < 0, 0, 1)
    win_rate = round(np.count_nonzero(win_loss) / win_loss.size * 100, 2)

    total_pnl = temp_strat_records["real_pnl"][
        ~np.isnan(temp_strat_records["real_pnl"])
    ].sum()

    # strat array
    strategy_result_records["symbol"] = temp_strat_records["symbol"][0]
    strategy_result_records["entries_col"] = temp_strat_records["entries_col"][0]
    strategy_result_records["or_set"] = temp_strat_records["or_set"][0]
    strategy_result_records["total_trades"] = total_trades
    strategy_result_records["gains_pct"] = gains_pct
    strategy_result_records["win_rate"] = win_rate
    strategy_result_records["to_the_upside"] = to_the_upside
    strategy_result_records["total_pnl"] = total_pnl
    strategy_result_records["ending_eq"] = temp_strat_records["equity"][-1]


@njit(cache=True)
def fill_settings_result_records_nb(
    entries_col: int,
    entry_order: EntryOrder,
    settings_result_records: RecordArray,
    stops_order: StopsOrder,
    symbol_counter: int,
) -> RecordArray:
    """
    Fill settings record with order parameter configuration.

    This function populates a settings result record with all the order parameters
    used by a strategy that passed filters. It pairs with fill_strategy_result_records_nb()
    to provide complete strategy information: performance metrics + exact configuration.

    This allows reconstruction of successful strategies by storing which parameters
    produced the results in the corresponding strategy_result_records row.

    Parameters
    ----------
    entries_col : int
        Entry signal column index (identifies which indicator was used)
    entry_order : EntryOrder
        Entry order configuration containing leverage, size, SL, TP, TSL settings
    settings_result_records : RecordArray
        Single record (row) from settings_result_records array to fill.
        This is typically settings_result_records[result_records_filled].
    stops_order : StopsOrder
        Stop order configuration containing breakeven and trailing stop parameters
    symbol_counter : int
        Index identifying which symbol was traded

    Returns
    -------
    RecordArray
        The filled settings_result_records row (same object passed in)

    Notes
    -----
    **Record Fields Populated** (percentages converted back to raw form):
        - symbol: Symbol counter
        - entries_col: Entry signal source
        - leverage: Leverage multiplier
        - max_equity_risk_pct: Max equity risk % (decimal × 100)
        - max_equity_risk_value: Max equity risk value
        - risk_rewards: Risk-reward ratio
        - size_pct: Position size % (decimal × 100)
        - size_value: Position size value
        - sl_pcts: Stop loss % (decimal × 100)
        - sl_to_be_based_on: Breakeven price basis
        - sl_to_be_trail_by_when_pct_from_avg_entry: BE trailing % (decimal × 100)
        - sl_to_be_when_pct_from_avg_entry: BE trigger % (decimal × 100)
        - sl_to_be_zero_or_entry: Move SL to zero or entry
        - tp_pcts: Take profit % (decimal × 100)
        - tsl_based_on: TSL price basis
        - tsl_pcts_init: TSL initial % (decimal × 100)
        - tsl_trail_by_pct: TSL trailing % (decimal × 100)
        - tsl_when_pct_from_avg_entry: TSL activation % (decimal × 100)

    **Percentage Conversion**:
        Internal decimal percentages are multiplied by 100 for human readability:
        - Internal: 0.03 → Output: 3.0
        - Internal: 0.15 → Output: 15.0

    **Pairing with Strategy Results**:
        Both arrays (strategy_result_records and settings_result_records) are
        filled at the same index (result_records_filled), creating matched pairs:
        - strategy_result_records[i]: Performance metrics
        - settings_result_records[i]: Parameters that produced those metrics

    **Usage Context**:
        Called by backtest_df_only_nb() immediately after
        fill_strategy_result_records_nb() to record the complete strategy definition.

    Examples
    --------
    >>> # After recording strategy performance
    >>> entry_order = EntryOrder(
    ...     leverage=5.0,
    ...     size_pct=0.10,  # 10% internal
    ...     sl_pcts=0.03,   # 3% internal
    ...     tp_pcts=0.06,   # 6% internal
    ...     ...
    ... )
    >>> stops_order = StopsOrder(...)
    >>> settings_result_records = np.empty(1, dtype=settings_array_dt)
    >>> fill_settings_result_records_nb(
    ...     entries_col=2,
    ...     entry_order=entry_order,
    ...     settings_result_records=settings_result_records[0],
    ...     stops_order=stops_order,
    ...     symbol_counter=0,
    ... )
    >>> settings_result_records[0]['leverage']  # 5.0
    >>> settings_result_records[0]['size_pct']  # 10.0 (converted back)
    >>> settings_result_records[0]['sl_pcts']  # 3.0 (converted back)
    >>> settings_result_records[0]['tp_pcts']  # 6.0 (converted back)

    See Also
    --------
    fill_strategy_result_records_nb : Fill corresponding performance record
    backtest_df_only_nb : Uses this to store parameter configurations
    """
    settings_result_records["symbol"] = symbol_counter
    settings_result_records["entries_col"] = entries_col
    settings_result_records["leverage"] = entry_order.leverage
    settings_result_records["max_equity_risk_pct"] = (
        entry_order.max_equity_risk_pct * 100
    )
    settings_result_records["max_equity_risk_value"] = entry_order.max_equity_risk_value
    settings_result_records["risk_rewards"] = entry_order.risk_rewards
    settings_result_records["size_pct"] = entry_order.size_pct * 100
    settings_result_records["size_value"] = entry_order.size_value
    settings_result_records["sl_pcts"] = entry_order.sl_pcts * 100
    settings_result_records["sl_to_be_based_on"] = stops_order.sl_to_be_based_on
    settings_result_records["sl_to_be_trail_by_when_pct_from_avg_entry"] = (
        stops_order.sl_to_be_trail_by_when_pct_from_avg_entry * 100
    )
    settings_result_records["sl_to_be_when_pct_from_avg_entry"] = (
        stops_order.sl_to_be_when_pct_from_avg_entry * 100
    )
    settings_result_records[
        "sl_to_be_zero_or_entry"
    ] = stops_order.sl_to_be_zero_or_entry
    settings_result_records["tp_pcts"] = entry_order.tp_pcts * 100
    settings_result_records["tsl_based_on"] = stops_order.tsl_based_on
    settings_result_records["tsl_pcts_init"] = entry_order.tsl_pcts_init * 100
    settings_result_records["tsl_trail_by_pct"] = stops_order.tsl_trail_by_pct * 100
    settings_result_records["tsl_when_pct_from_avg_entry"] = (
        stops_order.tsl_when_pct_from_avg_entry * 100
    )


@njit(cache=True)
def to_1d_array_nb(var: PossibleArray) -> Array1d:
    """
    Convert array of any shape to 1D array.

    This utility function normalizes arrays to exactly 1 dimension, handling scalars,
    1D arrays, and 2D column vectors. It's used extensively by create_1d_arrays_nb()
    to ensure all order parameters are uniformly shaped before validation or
    cartesian product generation.

    Parameters
    ----------
    var : PossibleArray
        Input array of any compatible shape:
        - 0D (scalar): Will be expanded to [value]
        - 1D (array): Returned as-is
        - 2D (column vector): First column extracted

    Returns
    -------
    Array1d
        1D numpy array with dtype float64

    Raises
    ------
    ValueError
        If input is 2D with more than 1 column, or has more than 2 dimensions

    Notes
    -----
    **Supported Input Shapes**:
        - Scalar (0D): np.float64(5.0) → np.array([5.0])
        - 1D array: np.array([1, 2, 3]) → np.array([1., 2., 3.])
        - 2D column: np.array([[1], [2], [3]]) → np.array([1., 2., 3.])

    **Unsupported Input Shapes**:
        - 2D with multiple columns: np.array([[1, 2], [3, 4]]) → ValueError
        - 3D or higher: ValueError

    **Use Cases**:
        - Normalizing user inputs (scalars, lists, arrays) to 1D format
        - Preparing parameters for broadcasting or cartesian product
        - Ensuring consistent array shapes for numba JIT compilation

    Examples
    --------
    >>> # Scalar to 1D
    >>> to_1d_array_nb(np.float64(5.0))
    array([5.])

    >>> # 1D array unchanged
    >>> to_1d_array_nb(np.array([1.0, 2.0, 3.0]))
    array([1., 2., 3.])

    >>> # 2D column vector to 1D
    >>> to_1d_array_nb(np.array([[1.0], [2.0], [3.0]]))
    array([1., 2., 3.])

    >>> # Invalid: 2D with multiple columns
    >>> to_1d_array_nb(np.array([[1.0, 2.0], [3.0, 4.0]]))
    ValueError: to 1d array problem

    See Also
    --------
    to_2d_array_nb : Convert array to 2D
    create_1d_arrays_nb : Uses this function to normalize all parameters
    """
    if var.ndim == 0:
        return np.expand_dims(var, axis=0)
    if var.ndim == 1:
        return var
    if var.ndim == 2 and var.shape[1] == 1:
        return var[:, 0]
    raise ValueError("to 1d array problem")


@njit(cache=True)
def to_2d_array_nb(var: PossibleArray, expand_axis: int = 1) -> Array2d:
    """
    Convert array of any shape to 2D array.

    This utility function normalizes arrays to exactly 2 dimensions, handling scalars,
    1D arrays, and existing 2D arrays. It provides flexible axis expansion for 1D inputs,
    allowing creation of either row vectors (expand_axis=0) or column vectors (expand_axis=1).

    Parameters
    ----------
    var : PossibleArray
        Input array of any compatible shape:
        - 0D (scalar): Will be expanded to [[value]]
        - 1D (array): Will be expanded along specified axis
        - 2D (array): Returned as-is
    expand_axis : int, optional
        Axis along which to expand 1D arrays (default: 1).
        - expand_axis=0: Creates row vector [[a, b, c]]
        - expand_axis=1: Creates column vector [[a], [b], [c]]

    Returns
    -------
    Array2d
        2D numpy array with dtype float64

    Raises
    ------
    ValueError
        If input has more than 2 dimensions

    Notes
    -----
    **Supported Input Shapes**:
        - **0D scalar**: np.float64(5.0) → np.array([[5.0]])
        - **1D with axis=1**: [1, 2, 3] → [[1], [2], [3]] (column vector)
        - **1D with axis=0**: [1, 2, 3] → [[1, 2, 3]] (row vector)
        - **2D array**: Returned unchanged

    **Unsupported Input Shapes**:
        - 3D or higher: ValueError

    **Axis Convention**:
        Following numpy convention:
        - axis=0: Vertical expansion (adds rows)
        - axis=1: Horizontal expansion (adds columns)

    **Use Cases**:
        - Preparing data for matrix operations
        - Ensuring consistent shapes for broadcasting
        - Converting 1D parameter arrays to column/row vectors for concatenation

    Examples
    --------
    >>> # Scalar to 2D
    >>> to_2d_array_nb(np.float64(5.0))
    array([[5.]])

    >>> # 1D to column vector (default)
    >>> to_2d_array_nb(np.array([1.0, 2.0, 3.0]))
    array([[1.],
           [2.],
           [3.]])

    >>> # 1D to row vector
    >>> to_2d_array_nb(np.array([1.0, 2.0, 3.0]), expand_axis=0)
    array([[1., 2., 3.]])

    >>> # 2D array unchanged
    >>> to_2d_array_nb(np.array([[1.0, 2.0], [3.0, 4.0]]))
    array([[1., 2.],
           [3., 4.]])

    >>> # Invalid: 3D array
    >>> to_2d_array_nb(np.array([[[1.0]]]))
    ValueError: to 2d array problem

    See Also
    --------
    to_1d_array_nb : Convert array to 1D
    """
    if var.ndim == 0:
        return np.expand_dims(np.expand_dims(var, axis=0), axis=0)
    if var.ndim == 1:
        return np.expand_dims(var, axis=expand_axis)
    if var.ndim == 2:
        return var
    raise ValueError("to 2d array problem")
