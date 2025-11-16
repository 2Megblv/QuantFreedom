# QuantFreedom Test Suite

Comprehensive test suite for the QuantFreedom backtesting library.

## Test Structure

```
tests/
├── conftest.py              # Shared fixtures and configuration
├── test_integration.py      # Integration tests for full workflows
├── test_nb/                 # Tests for Numba-optimized core functions
│   ├── test_buy_funcs.py    # Long position entry/exit tests
│   ├── test_execute_funcs.py # SL/TP/liquidation tests
│   └── test_helper_funcs.py  # Utility function tests
└── README.md                # This file
```

## Running Tests

### Run all tests
```bash
pytest
```

### Run with coverage
```bash
pytest --cov=quantfreedom --cov-report=html
```

### Run specific test file
```bash
pytest tests/test_integration.py
```

### Run specific test class
```bash
pytest tests/test_nb/test_buy_funcs.py::TestLongIncreaseNb
```

### Run specific test
```bash
pytest tests/test_nb/test_buy_funcs.py::TestLongIncreaseNb::test_basic_long_entry_fixed_amount
```

### Skip slow tests
```bash
pytest -m "not slow"
```

### Run only integration tests
```bash
pytest -m integration
```

## Test Markers

- `@pytest.mark.unit` - Unit tests (fast, isolated)
- `@pytest.mark.integration` - Integration tests (test full workflows)
- `@pytest.mark.slow` - Slow tests (large datasets, performance tests)

## Test Coverage

Current coverage targets:
- **Core functions (nb/)**: 80%+ coverage
- **Integration tests**: Key workflows covered
- **Edge cases**: Position entry/exit, liquidation, stop losses

## Writing New Tests

### Using Fixtures

Fixtures are defined in `conftest.py` and available in all tests:

```python
def test_example(sample_prices, basic_account_state, long_entry_order):
    """Test using predefined fixtures."""
    # Fixtures are automatically injected
    assert len(sample_prices) > 0
```

### Testing Numba Functions

Numba-compiled functions can be tested directly:

```python
from quantfreedom.nb.buy_funcs import long_increase_nb

def test_long_entry(basic_account_state, long_entry_order, empty_order_result, basic_static_variables):
    account_state_new, order_result_new = long_increase_nb(
        price=100.0,
        account_state=basic_account_state,
        entry_order=long_entry_order,
        order_result=empty_order_result,
        static_variables_tuple=basic_static_variables,
    )

    assert order_result_new.position > 0
```

### Integration Test Example

```python
@pytest.mark.integration
def test_full_backtest(sample_prices, sample_entries):
    """Test complete backtest workflow."""
    strat_results, settings = backtest_df_only(
        prices=sample_prices,
        entries=sample_entries,
        equity=1000.0,
        # ... other parameters
    )

    assert len(strat_results) > 0
```

## Continuous Integration

Tests run automatically on:
- Every push to `main`, `develop`, or `claude/**` branches
- Every pull request

CI Matrix:
- **Python**: 3.8, 3.9, 3.10, 3.11
- **OS**: Ubuntu, Windows, macOS
- **Coverage**: Reported to Codecov (Ubuntu + Python 3.10)

## Test Data

### Fixtures Provided

- `sample_prices` - 100 bars of realistic OHLC data
- `sample_entries` - Entry signals every 10 bars
- `basic_account_state` - $1000 starting equity
- `long_entry_order` - Basic long order configuration
- `short_entry_order` - Basic short order configuration
- `empty_order_result` - Empty result (no position)
- `basic_static_variables` - Default backtest settings
- `basic_stops_order` - Default stop configuration
- `sample_1d_arrays` - Parameter arrays for cart product

### Creating Custom Fixtures

Add to `conftest.py`:

```python
@pytest.fixture
def custom_prices():
    """Create custom price data."""
    # Your custom data generation
    return prices_df
```

## Common Test Patterns

### Testing Entry Logic
```python
def test_entry_logic(basic_account_state, entry_order, empty_order_result, static_vars):
    account, result = long_increase_nb(
        price=100.0,
        account_state=basic_account_state,
        entry_order=entry_order,
        order_result=empty_order_result,
        static_variables_tuple=static_vars,
    )

    # Verify order filled
    assert result.order_status == OrderStatus.Filled
    # Verify position opened
    assert result.position > 0
    # Verify fees deducted
    assert result.fees_paid > 0
```

### Testing Stop Loss
```python
def test_stop_loss(basic_account_state, order_result, stops_order):
    result = check_sl_tp_nb(
        high_price=101.0,
        low_price=97.0,  # Hits SL at 98
        open_price=100.0,
        close_price=99.0,
        order_settings_counter=0,
        entry_type=OrderType.LongEntry,
        fee_pct=0.0006,
        bar=10,
        account_state=basic_account_state,
        order_result=order_result,
        stops_order=stops_order,
    )

    # Verify SL triggered
    assert result.order_type == OrderType.LongSL
```

### Testing Backtest Results
```python
@pytest.mark.integration
def test_backtest(sample_prices, sample_entries):
    strat_results, settings = backtest_df_only(
        prices=sample_prices,
        entries=sample_entries,
        # ... parameters
    )

    # Verify results structure
    assert "gains_pct" in strat_results.columns
    assert "win_rate" in strat_results.columns

    # Verify calculations
    if len(strat_results) > 0:
        assert strat_results.iloc[0]["ending_eq"] > 0
```

## Debugging Tests

### Run with verbose output
```bash
pytest -vv
```

### Stop on first failure
```bash
pytest -x
```

### Drop into debugger on failure
```bash
pytest --pdb
```

### Print output
```bash
pytest -s
```

## Performance Testing

Slow/performance tests are marked with `@pytest.mark.slow`:

```python
@pytest.mark.slow
def test_large_backtest():
    """Test with 1000+ candles."""
    # Large dataset test
```

Run only performance tests:
```bash
pytest -m slow
```

## Coverage Reports

After running tests with coverage:
- **Terminal**: Shows coverage summary
- **HTML**: Open `htmlcov/index.html` in browser
- **XML**: Used by Codecov in CI

View HTML coverage report:
```bash
pytest --cov=quantfreedom --cov-report=html
open htmlcov/index.html  # macOS
# or
start htmlcov/index.html  # Windows
```

## Contributing Tests

When adding new features:
1. Write tests first (TDD)
2. Ensure >80% coverage for new code
3. Add integration test if it's a workflow feature
4. Update this README if adding new test patterns

## Known Test Limitations

- **Numba compilation**: First test run is slower due to JIT compilation
- **Floating point**: Use `assert abs(a - b) < 0.01` for float comparisons
- **Random data**: Use `np.random.seed(42)` for reproducibility
- **Windows paths**: Use `Path` from `pathlib` for cross-platform compatibility

## Troubleshooting

### Tests fail with "Numba error"
- First run compiles Numba functions (takes longer)
- Try running tests again

### Coverage too low
- Check which lines aren't covered: `pytest --cov=quantfreedom --cov-report=term-missing`
- Add tests for uncovered code paths

### Fixtures not found
- Ensure `conftest.py` is in tests directory
- Check fixture name matches exactly

### Import errors
- Install package in dev mode: `pip install -e ".[dev]"`
- Check all dependencies installed: `pip install -e ".[dev]"`

## Resources

- [pytest documentation](https://docs.pytest.org/)
- [pytest fixtures](https://docs.pytest.org/en/stable/fixture.html)
- [coverage.py](https://coverage.readthedocs.io/)
- [Testing with Numba](https://numba.readthedocs.io/en/stable/user/troubleshoot.html)
