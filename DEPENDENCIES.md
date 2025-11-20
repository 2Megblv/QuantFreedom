# QuantFreedom Dependencies Guide

This document explains QuantFreedom's dependencies and installation options.

## Installation Options

### Core Installation (Recommended for Most Users)

```bash
pip install quantfreedom
```

This installs the minimum dependencies needed for backtesting and strategy development:
- **ccxt**: Cryptocurrency exchange connectivity
- **numpy**: Numerical computing
- **pandas**: Data manipulation
- **numba**: JIT compilation for performance
- **plotly**: Basic plotting
- **polars**: Fast data processing
- **pyarrow**: Columnar data format
- **tables**: HDF5 support
- **h5py**: HDF5 Python interface
- **tqdm**: Progress bars

### With Visualization Dashboard (Optional)

```bash
pip install quantfreedom[viz]
```

Adds interactive dashboard and Jupyter notebook visualization:
- **dash**: Interactive web dashboards
- **dash-bootstrap-components**: Dashboard themes
- **dash-bootstrap-templates**: Dark theme templates
- **jupyter-dash**: Jupyter integration
- **ipywidgets**: Interactive widgets
- **kaleido**: Static image export
- **notebook**: Jupyter notebook support

**Note**: The `viz` dependencies may have version conflicts with some plotly versions. If you encounter issues, use the core installation which includes plotly for basic plotting.

### Development Installation

```bash
pip install quantfreedom[dev]
```

Adds development and testing tools:
- **pytest**: Testing framework
- **pytest-cov**: Code coverage
- **pytest-mock**: Mocking support
- **hypothesis**: Property-based testing
- **black**: Code formatting
- **flake8**: Linting
- **isort**: Import sorting
- **mypy**: Type checking

### Full Installation

```bash
pip install quantfreedom[viz,dev]
```

Installs all optional dependencies.

## Optional Dependencies

### TA-Lib (Technical Analysis Library)

**TA-Lib is completely optional**. QuantFreedom works fine without it.

If you want to use TA-Lib indicators:

1. **Install system library** (required before pip install):

   **macOS** (via Homebrew):
   ```bash
   brew install ta-lib
   ```

   **Ubuntu/Debian**:
   ```bash
   wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz
   tar -xzf ta-lib-0.4.0-src.tar.gz
   cd ta-lib/
   ./configure --prefix=/usr
   make
   sudo make install
   ```

   **Windows**:
   Download pre-built binaries from: https://github.com/TA-Lib/ta-lib-python

2. **Install Python wrapper**:
   ```bash
   pip install TA-Lib
   ```

If TA-Lib is not installed, you'll get a helpful error message when trying to use it:
```
ImportError: TA-Lib is not installed. To use this function, install TA-Lib:
  pip install TA-Lib

Note: TA-Lib requires a system C library installation.
See: https://github.com/TA-Lib/ta-lib-python for installation instructions.

TA-Lib is optional for QuantFreedom. You can use the library without it.
```

## Known Issues & Solutions

### Issue 1: plotly/dash-bootstrap-templates Conflict

**Problem**: `dash-bootstrap-templates` uses deprecated `heatmapgl` which was removed in newer plotly versions.

**Solution**: This is automatically handled. The package gracefully falls back if dash-bootstrap-templates fails to load. The dark theme is optional.

**Workaround** (if you really want the dark theme):
```bash
pip install plotly==5.14.1 dash-bootstrap-templates
```

### Issue 2: Numba Compatibility

**Problem**: Numba has specific version requirements for different Python versions.

**Solution**: This is handled automatically in pyproject.toml:
- Python >= 3.10: `numba>=0.56.0`
- Python < 3.10: `numba>=0.53.1`

### Issue 3: TA-Lib Installation Complexity

**Problem**: TA-Lib requires system C library installation before pip install.

**Solution**: TA-Lib is completely optional. Skip it if you don't need it. See installation instructions above if you do.

## Dependency Version Constraints

Current version constraints (as of 2025-11-20):

### Core Dependencies
```
ccxt>=2.0.0,<5.0.0
h5py>=3.0.0,<4.0.0
mypy-extensions>=0.4.0,<2.0.0
tqdm>=4.60.0,<5.0.0
numba>=0.56.0 (Python >= 3.10)
numba>=0.53.1 (Python < 3.10)
numpy>=1.21.0,<2.0.0
pandas>=1.3.0,<3.0.0
polars>=0.15.0,<2.0.0
plotly>=5.0.0,<6.0.0
pyarrow>=6.0.0,<16.0.0
tables>=3.7.0,<4.0.0
```

### Optional: Visualization ([viz])
```
dash>=2.0.0,<3.0.0
dash-bootstrap-components>=1.0.0,<2.0.0
dash-bootstrap-templates>=1.0.0,<2.0.0
ipywidgets>=8.0.0,<9.0.0
jupyter-dash>=0.4.0,<1.0.0
jupyterlab-widgets>=3.0.0,<4.0.0
kaleido>=0.2.0,<1.0.0
notebook>=6.4.0,<8.0.0
```

### Optional: Development ([dev])
```
pytest>=7.0.0,<9.0.0
pytest-cov>=3.0.0,<5.0.0
pytest-mock>=3.10.0,<4.0.0
hypothesis>=6.0.0,<7.0.0
black>=22.0.0,<25.0.0
flake8>=5.0.0,<8.0.0
isort>=5.0.0,<6.0.0
mypy>=1.0.0,<2.0.0
```

## Python Version Support

**Supported**: Python 3.8, 3.9, 3.10, 3.11, 3.12

**Required**: `>=3.8,<3.13`

## Testing Dependency Installation

After installation, verify imports work:

```python
# Test core imports
import quantfreedom
from quantfreedom.nb.simulate import backtest_df_only_nb
from quantfreedom.nb.helper_funcs import static_var_checker_nb
print("✓ Core imports successful")

# Test TA-Lib (if installed)
try:
    from quantfreedom.indicators.talib_ind import from_talib
    print("✓ TA-Lib available")
except ImportError:
    print("! TA-Lib not installed (optional)")

# Test visualization (if installed [viz])
try:
    from quantfreedom.plotting import strat_dashboard
    print("✓ Visualization tools available")
except ImportError:
    print("! Visualization tools not installed (install with [viz])")
```

## Troubleshooting

### Can't Import QuantFreedom

```python
import quantfreedom  # Fails
```

**Solution**: Make sure you've installed the package:
```bash
pip install quantfreedom
```

### ImportError for dash/jupyter-dash

```
ImportError: cannot import name 'strat_dashboard'
```

**Solution**: Install visualization dependencies:
```bash
pip install quantfreedom[viz]
```

### TA-Lib ImportError

```
ImportError: TA-Lib is not installed
```

**Solution**: This is expected if TA-Lib is not installed. It's optional. Install following instructions above if needed.

### Numba Compilation Errors

```
NumbaTypeSafetyWarning: unsafe cast from uint64 to int64
```

**Solution**: These warnings are generally safe to ignore. They're related to Numba's JIT compilation and don't affect functionality.

### Plotly Version Conflicts

```
ValueError: Invalid property specified: 'heatmapgl'
```

**Solution**: This error is automatically caught and handled. The package will work without the dark theme. If you see this error, ensure you're using the latest version of quantfreedom.

## For Contributors

If you're contributing to QuantFreedom:

1. **Clone the repository**:
   ```bash
   git clone https://github.com/QuantFreedom1022/quantfreedom.git
   cd quantfreedom
   ```

2. **Install in development mode**:
   ```bash
   pip install -e .[dev]
   ```

3. **Install pre-commit hooks**:
   ```bash
   pip install pre-commit
   pre-commit install
   ```

4. **Run tests**:
   ```bash
   pytest
   ```

See [CONTRIBUTING.md](CONTRIBUTING.md) for full development guidelines.

## Keeping Dependencies Updated

We regularly review and update dependencies to ensure:
- Security patches are applied
- Compatibility with latest Python versions
- Performance improvements
- Bug fixes

Last dependency review: **2025-11-20**

## Questions?

- **Issues**: https://github.com/QuantFreedom1022/quantfreedom/issues
- **Documentation**: https://quantfreedom1022.github.io/QuantFreedom/
- **Discussions**: https://github.com/QuantFreedom1022/quantfreedom/discussions
