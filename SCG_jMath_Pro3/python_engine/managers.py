class GridSystemManager:
    def __init__(self, x_threshold_bars=15, y_threshold_price=0.00020, max_operations=13):
        self.x_threshold_bars = x_threshold_bars
        self.y_threshold_price = y_threshold_price
        self.max_operations = max_operations

        # State
        self.current_operations = 0
        self.last_trade_bar_index = -1
        self.last_trade_price = 0.0

        print(f"[GSM] Initialized with X-Threshold: {x_threshold_bars} bars, Y-Threshold: {y_threshold_price} price dist, Max Ops: {max_operations}")

    def reset_grid(self):
        self.current_operations = 0
        self.last_trade_bar_index = -1
        self.last_trade_price = 0.0

    def register_trade(self, current_bar_index, price):
        self.current_operations += 1
        self.last_trade_bar_index = current_bar_index
        self.last_trade_price = price
        print(f"[GSM] Registered trade {self.current_operations}/{self.max_operations} at bar {current_bar_index}, price {price}")

    def can_open_grid_trade(self, current_bar_index, current_price, is_long_basket=True):
        if self.current_operations == 0:
            return True # Can always open the first trade

        if self.current_operations >= self.max_operations:
            print("[GSM] Max operations reached. Cannot open new grid trade.")
            return False

        # Check X-Threshold (Time/Distance)
        bars_passed = current_bar_index - self.last_trade_bar_index
        if bars_passed < self.x_threshold_bars:
            print(f"[GSM] X-Threshold not met. Passed: {bars_passed}, Required: {self.x_threshold_bars}")
            return False

        # Check Y-Threshold (Price Distance)
        # For a long basket, price must be LOWER by y_threshold
        # For a short basket, price must be HIGHER by y_threshold
        price_diff = self.last_trade_price - current_price if is_long_basket else current_price - self.last_trade_price

        if price_diff < self.y_threshold_price:
            print(f"[GSM] Y-Threshold not met. Diff: {price_diff:.5f}, Required: {self.y_threshold_price:.5f}")
            return False

        return True


class BasketEquitySystemManager:
    def __init__(self, profit_target_usd=5.0):
        self.profit_target_usd = profit_target_usd
        print(f"[BESM] Initialized Basket Manager. Target: ${profit_target_usd}")

    def check_target_exit(self, open_positions_pnl):
        """
        Checks if the sum of all open positions exceeds the profit threshold.
        """
        total_pnl = sum(open_positions_pnl)
        if total_pnl >= self.profit_target_usd:
            print(f"[BESM] Profit target reached (${total_pnl:.2f} >= ${self.profit_target_usd:.2f}). Triggering Basket Exit.")
            return True
        return False

    def calculate_escape_route(self, open_positions, current_time):
        """
        Calculates the multi-dimensional exchange rate required to exit the basket
        at break-even or acceptable cost.

        NOTE: This is a placeholder interface for the proprietary jMathFx algorithm.
        Currently, it implements a basic time-weighted average entry price decay.
        """
        if not open_positions:
            return None

        total_volume = sum(p['volume'] for p in open_positions)
        weighted_sum = sum(p['price'] * p['volume'] for p in open_positions)
        base_avg_price = weighted_sum / total_volume

        # Placeholder multi-dimensional decay:
        # Over time, we lower the escape route target slightly to get out faster.
        # This is NOT the true jMathFx proprietary formula.
        time_decay_factor = 0.00001 # Simulated decay

        # Assume long positions for placeholder
        escape_price = base_avg_price - time_decay_factor

        return escape_price
