# Contributing to QuantFreedom

Thank you for your interest in contributing to QuantFreedom! This guide will help you get started.

## Development Setup

### 1. Clone the Repository
```bash
git clone https://github.com/QuantFreedom1022/quantfreedom.git
cd quantfreedom
```

### 2. Install Development Dependencies
```bash
pip install -e ".[dev]"
```

### 3. Install Pre-commit Hooks
```bash
pip install pre-commit
pre-commit install
```

## Development Workflow

### Running Tests
```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=quantfreedom --cov-report=html

# Run specific tests
pytest tests/test_nb/test_buy_funcs.py

# Skip slow tests
pytest -m "not slow"
```

### Code Formatting

We use `black` for code formatting and `isort` for import sorting:

```bash
# Format code
black quantfreedom tests

# Sort imports
isort quantfreedom tests

# Check formatting without changes
black --check quantfreedom tests
isort --check quantfreedom tests
```

### Linting

```bash
# Run flake8
flake8 quantfreedom tests

# Run mypy (type checking)
mypy quantfreedom
```

### Pre-commit Hooks

Pre-commit hooks will automatically run before each commit:
- Trailing whitespace removal
- End-of-file fixer
- YAML/JSON/TOML validation
- Black formatting
- isort import sorting
- Flake8 linting
- MyPy type checking (basic)

To run manually:
```bash
pre-commit run --all-files
```

## Pull Request Process

1. **Create a Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make Your Changes**
   - Write code following the style guide
   - Add tests for new functionality
   - Update documentation

3. **Run Tests and Linting**
   ```bash
   pytest
   black quantfreedom tests
   flake8 quantfreedom tests
   ```

4. **Commit Your Changes**
   ```bash
   git add .
   git commit -m "Add feature: description"
   ```

   Pre-commit hooks will run automatically. Fix any issues they find.

5. **Push and Create PR**
   ```bash
   git push origin feature/your-feature-name
   ```

   Then create a pull request on GitHub.

## Code Style Guidelines

### Python Style

- **Line length**: 100 characters
- **Formatting**: Use Black (automatic)
- **Imports**: Use isort (automatic)
- **Docstrings**: NumPy style

### Docstring Example
```python
def function_name(param1: float, param2: int) -> tuple:
    """
    Brief one-line description.

    Longer description explaining the function's purpose,
    algorithm, and important behavior.

    Parameters
    ----------
    param1 : float
        Description of param1
    param2 : int
        Description of param2

    Returns
    -------
    tuple
        Description of return value

    Examples
    --------
    >>> function_name(1.0, 2)
    (result1, result2)
    """
    pass
```

### Type Hints

Add type hints to all new functions:

```python
from typing import Optional, Tuple
import numpy as np

def process_order(
    price: float,
    size: float,
    leverage: Optional[float] = None
) -> Tuple[float, float]:
    """Process an order."""
    # Implementation
    return pnl, fees
```

## Testing Guidelines

### Writing Tests

1. **Use pytest fixtures** (defined in `tests/conftest.py`)
2. **Follow naming convention**: `test_<functionality>_<scenario>`
3. **Test edge cases**: Zero, negative, infinity, NaN
4. **Use markers**: `@pytest.mark.unit`, `@pytest.mark.integration`, `@pytest.mark.slow`

### Test Example
```python
def test_long_entry_with_stop_loss(basic_account_state, long_entry_order):
    """Test long entry with stop loss set."""
    account_state, order_result = long_increase_nb(
        price=100.0,
        account_state=basic_account_state,
        entry_order=long_entry_order,
        # ... other params
    )

    # Assert conditions
    assert order_result.sl_prices > 0
    assert order_result.sl_prices < 100.0  # Below entry for long
```

### Coverage Requirements

- **New features**: Aim for 80%+ coverage
- **Bug fixes**: Add test that reproduces the bug
- **Core functions**: Maintain >80% coverage

## Commit Message Guidelines

Follow conventional commits format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Adding or updating tests
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `chore`: Build process or auxiliary tool changes

### Examples
```
feat(trading): Add trailing stop loss functionality

Implements dynamic trailing stop loss that moves with favorable
price movement to lock in profits.

- Add tsl_trail_by_pct parameter
- Update check_sl_tp_nb to handle TSL movement
- Add tests for TSL activation and trailing

Closes #123
```

```
fix(backtest): Correct fee calculation for liquidations

Fees were not being applied on liquidation exits, resulting in
incorrect PnL calculations.

Fixes #456
```

## What to Contribute

### Priority Areas

1. **Testing**: Increase test coverage
2. **Documentation**: Improve docstrings and examples
3. **Performance**: Optimize Numba functions
4. **Features**: New risk management strategies
5. **Bug Fixes**: See open issues

### Good First Issues

Look for issues labeled `good first issue` on GitHub. These are suitable for new contributors.

## Code of Conduct

### Our Standards

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Assume good intentions

### Unacceptable Behavior

- Harassment or discrimination
- Trolling or insulting comments
- Publishing others' private information
- Other unprofessional conduct

## Questions?

- **Documentation**: Check the [docs](https://quantfreedom1022.github.io/QuantFreedom/)
- **Issues**: Open an issue on GitHub
- **Discussions**: Use GitHub Discussions

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 with Commons Clause license.

---

Thank you for contributing to QuantFreedom! 🚀
