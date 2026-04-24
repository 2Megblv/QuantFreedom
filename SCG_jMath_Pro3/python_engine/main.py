import time
from zmq_bridge import ZMQBridge
from scg_model import SCGNeuralNetworkPlaceholder
from managers import GridSystemManager, BasketEquitySystemManager
from retracement import RetracementWaveMechanics
from data_handler import GTSDataHandler

class DecisionEngine:
    def __init__(self, mode="mock"):
        print("Starting jMathFx Institutional Decision Engine...")
        self.bridge = ZMQBridge()
        self.scg_model = SCGNeuralNetworkPlaceholder(mode=mode)
        self.gsm = GridSystemManager()
        self.besm = BasketEquitySystemManager()
        self.retracement = RetracementWaveMechanics()
        self.data_handler = GTSDataHandler(mode=mode)

        # State
        self.historical_data = [] # For SCG training
        self.live_data_window = [] # Rolling window of recent bars
        self.forecast_history = [] # Rolling window of model forecasts
        self.current_bar_index = 0
        self.open_positions = [] # Track open trades

        # Start Bridge
        self.bridge.start(self.handle_mt5_message)

    def initialize(self):
        """Pre-trains model and preps engine."""
        if self.data_handler.test_pipeline():
            df = self.data_handler.load_data()
            self.historical_data = df[['Open', 'High', 'Low', 'Close', 'Volume']].values
            self.scg_model.pre_train(self.historical_data)
        else:
            print("Initialization failed. Halting engine.")
            self.bridge.stop()

    def handle_mt5_message(self, message: str):
        """
        Parses incoming ZMQ strings from MT5.
        Format: TICK|<Bid>|<Ask>  or  TICK|<Bid>|<Ask>|BAR|<High>|<Low>|<Open>|<Close>
        """
        parts = message.split('|')
        if len(parts) >= 3 and parts[0] == "TICK":
            bid = float(parts[1])
            ask = float(parts[2])

            # If a new bar just closed, process it
            if len(parts) == 8 and parts[3] == "BAR":
                high = float(parts[4])
                low = float(parts[5])
                open_p = float(parts[6])
                close = float(parts[7])

                self.process_new_bar(open_p, high, low, close)

            # Always process tick for escape routes / targets
            self.process_tick(bid, ask)

    def process_new_bar(self, open_p, high, low, close):
        self.current_bar_index += 1
        self.live_data_window.append({'open': open_p, 'high': high, 'low': low, 'close': close})

        # Keep rolling window manageable
        if len(self.live_data_window) > 100:
            self.live_data_window.pop(0)

        # Generate and store forecast for the *next* close based on this updated window
        if self.scg_model.is_trained:
            forecast = self.scg_model.predict_next_close(self.live_data_window)
            self.forecast_history.append(forecast)
            if len(self.forecast_history) > 10:
                self.forecast_history.pop(0)

        print(f"[Engine] Processed new bar {self.current_bar_index}: C={close}")

        # Evaluate Trading Logic
        self.evaluate_market()

    def process_tick(self, bid, ask):
        """Evaluate fast-moving exit conditions on every tick."""
        if not self.open_positions:
            return

        # Example PnL check for BESM (Assume fixed 1 lot size = 100k for simplicity)
        current_pnl = []
        for pos in self.open_positions:
            if pos['type'] == 'BUY':
                pnl = (bid - pos['price']) * 100000
            else:
                pnl = (pos['price'] - ask) * 100000
            current_pnl.append(pnl)

        if self.besm.check_target_exit(current_pnl):
            self.close_basket()
            return

        # Check Escape Route
        escape_price = self.besm.calculate_escape_route(self.open_positions, time.time())
        if escape_price is not None:
            # If long and price reaches or exceeds escape route
            # Note: simplified logic
            if self.open_positions[0]['type'] == 'BUY' and bid >= escape_price:
                print(f"[Engine] Escape Route reached at {escape_price}. Flattening.")
                self.close_basket()

    def evaluate_market(self):
        """Core logic to enter or grid trade."""
        if len(self.live_data_window) < 3 or len(self.forecast_history) < 3:
            return

        # 1. SCG Forecast & Trend using historical forecasts
        _, _, trend = self.scg_model.calculate_derivatives(self.forecast_history)

        current_close = self.live_data_window[-1]['close']

        # 2. Grid Management if already in position
        if self.open_positions:
            is_long = self.open_positions[0]['type'] == 'BUY'
            if self.gsm.can_open_grid_trade(self.current_bar_index, current_close, is_long_basket=is_long):
                # Open grid trade
                trade_type = "BUY" if is_long else "SELL"
                self.execute_trade(trade_type, current_close)
            return

        # 3. New Entry via Retracement if no positions
        if trend != "NEUTRAL":
            max_ret = self.retracement.scan_longest_retracement(self.live_data_window, trend)

            # Find latest swing extreme (simplified)
            latest_swing = self.live_data_window[-2]['low'] if trend == "LONG" else self.live_data_window[-2]['high']

            key_level = self.retracement.calculate_key_break_level(latest_swing, max_ret, trend)

            if key_level:
                # Check for Break
                if trend == "LONG" and current_close > key_level:
                    print(f"[Engine] Key Level {key_level} broken LONG. Entering.")
                    self.execute_trade("BUY", current_close)
                elif trend == "SHORT" and current_close < key_level:
                    print(f"[Engine] Key Level {key_level} broken SHORT. Entering.")
                    self.execute_trade("SELL", current_close)

    def execute_trade(self, trade_type, price):
        symbol = "EURUSD" # Fixed for now
        cmd = f"TRADE|OPEN|{trade_type}|{symbol}|{price}"
        self.bridge.send_command(cmd)

        self.open_positions.append({'type': trade_type, 'price': price, 'volume': 1.0})
        self.gsm.register_trade(self.current_bar_index, price)

    def close_basket(self):
        symbol = "EURUSD"
        cmd = f"TRADE|CLOSE_ALL|{symbol}"
        self.bridge.send_command(cmd)
        self.open_positions.clear()
        self.gsm.reset_grid()

    def run(self):
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            self.bridge.stop()

if __name__ == "__main__":
    engine = DecisionEngine(mode="mock")
    engine.initialize()
    engine.run()
