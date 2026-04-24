# jMathFx Institutional Architecture - Deployment Plan

This document outlines the end-to-end setup, integration, and deployment plan for the jMathFx Decoupled Trading Architecture. This system leverages MetaTrader 5 (MT5) as a high-frequency execution terminal and a dedicated Python engine for heavy mathematical processing (SCG Neural Networks).

## 1. Hardware & System Prerequisites
The system is designed to fully utilize high-performance hardware for Phase 2 deep learning and real-time HFT calculations.

*   **Processor:** AMD Ryzen 9 (16 Cores / 32 Threads). *Required for parallelizing matrix operations and ZeroMQ non-blocking polling.*
*   **Memory:** 32 GB RAM. *Crucial for loading the massive 72GB historical dataset into memory chunks using Pandas/Dask.*
*   **Storage:** Fast NVMe SSD. *Required to read 72GB of tick data without bottlenecking the Neural Network pre-training sequence.*
*   **OS:** Windows 10/11 Pro (or Windows Server) for native MT5 compatibility.

### Software Requirements
*   **Python:** Version `3.9 - 3.10` is highly recommended. (Newer versions like 3.12 may have breaking changes with standard TensorFlow/Keras or specific scientific libraries).
*   **MetaTrader 5:** Latest build. Ensure it is connected to a broker with low latency (<5ms ping) to the trade server.
*   **ZeroMQ:** The Python `pyzmq` package and the MQL5 standard C++ `libzmq.dll` bindings.

---

## 2. PC Setup & Python Environment Configuration

### Step 2.1: Python Virtual Environment
To prevent dependency conflicts, create an isolated virtual environment for the mathematical engine.

```bash
# Open command prompt or PowerShell
python -m venv jmathfx_env
# Activate the environment
jmathfx_env\Scripts\activate
# Install required scientific libraries
pip install pandas numpy pyzmq tensorflow scikit-learn
```

### Step 2.2: MT5 Terminal Setup
To allow the MT5 terminal to use ZeroMQ DLLs, you must explicitly enable DLL imports:
1. Open MT5.
2. Go to `Tools` -> `Options` (or `Ctrl+O`).
3. Navigate to the `Expert Advisors` tab.
4. Check **"Allow DLL imports"**. This is an absolute requirement for the `libzmq.dll` to function.

### Step 2.3: Install MQL5 ZMQ Bindings
The provided project scaffold includes a dummy `Zmq.mqh` file for compilation. Before live deployment, you must install the actual ZMQ bindings.
1. Download standard MQL5 ZMQ bindings (e.g., from `dingmaotu/mql-zmq` on GitHub).
2. Place the `Zmq.mqh` header inside `C:\Users\[User]\AppData\Roaming\MetaQuotes\Terminal\[Instance_ID]\MQL5\Include\Zmq\`.
3. Place the `libzmq.dll` file inside `C:\Users\[User]\AppData\Roaming\MetaQuotes\Terminal\[Instance_ID]\MQL5\Libraries\`.

---

## 3. Integration & Testing Phases

The deployment is split into two phases to ensure safety and stability before injecting massive data arrays.

### Phase 1: Mock Pipeline Validation (Logic & Bridge Test)
In Phase 1, we test the communication bridge latency and grid trading logic without freezing the PC with neural network training.

1. **Start the Python Engine:**
   Open your terminal, ensure the `jmathfx_env` is activated, and run the main engine in `mock` mode.
   ```bash
   python SCG_jMath_Pro3/python_engine/main.py
   ```
   *Expected Output: `[PHASE 1] Loading Mock Data...` followed by `[ZMQ Bridge] Initialized...`*

2. **Start the MT5 EA:**
   * Compile `jMathFx_EA.mq5` in MetaEditor.
   * Attach it to the `EURUSD` 1-Minute (M1) chart.
   * Verify the "Experts" tab in MT5 shows `jMathFx Bridge Connected.`

3. **Verify Communication:**
   * Watch the Python terminal. You should see ticks streaming in real-time.
   * When a new 1-minute bar forms (i.e., `tick_volume == 1`), Python should output `[Engine] Processed new bar...`.
   * *Success Criteria:* Python engine registers trades, tracks open positions in the Grid System Manager, and successfully pushes a `TRADE|OPEN|...` string back to the MT5 Experts tab.

### Phase 2: Terminal Deployment (Neural Network Training)
Once the bridge latency is confirmed to be <3ms and the GSM (Grid System Manager) successfully enforces X and Y constraints, transition to the heavy ML load.

1. **Update Data Paths:**
   Open `python_engine/data_handler.py` and ensure the `historical_path` variable points directly to your 72GB dataset on your D:/ or C:/ drive.
2. **Switch Mode:**
   In `python_engine/main.py`, change `DecisionEngine(mode="mock")` to `DecisionEngine(mode="terminal")`.
3. **Train & Run:**
   Run the Python engine. The engine will allocate your 32GB RAM and utilize your 16 Ryzen cores to parse the massive Pandas matrix and pre-train the SCG model weights.
   Once training completes, it will automatically start polling the MT5 sockets for real-time tick data.

---

## 4. Key Considerations & Operational Safety

*   **Threading on MT5:** The MT5 EA runs the ZeroMQ polling on an asynchronous `EventSetMillisecondTimer(10)`. Ensure the chart does not have other heavy custom indicators attached, as it could disrupt the 10ms execution loop.
*   **Escape Routes:** The `BasketEquitySystemManager` inside Python evaluates PnL on every single tick. Ensure the Python loop does not use blocking functions (`time.sleep()` inside the tick processor) to maintain strict sub-millisecond reactions.
*   **Orphaned Trades:** Always close out the Python engine *after* MT5 is shut down or disabled. If the Python engine crashes or is closed while MT5 is running, MT5 will continue to push data into a closed socket, potentially leading to TCP buffer overflow.
