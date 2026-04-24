import pandas as pd
import numpy as np
import os

class GTSDataHandler:
    def __init__(self, mode="mock"):
        self.mode = mode

        # Phase 1: Mock Data (Lightweight, stored in the project folder for GitHub)
        # Using relative path from the engine's root
        self.mock_path = os.path.join(os.path.dirname(__file__), "data", "mock_eurusd_ticks.csv")

        # Phase 2: Terminal Historical Data (Massive 72GB file on Ryzen 9 Local Drive)
        self.historical_path = "D:/TradingData/Historical/5_Years/eurusd_5yr_ticks.csv"

    def load_data(self):
        """Loads the dataset based on the current testing phase."""
        if self.mode == "mock":
            print("[PHASE 1] Loading Mock Data from project directory...")
            # Load the small CSV for rapid logic testing
            return pd.read_csv(self.mock_path)

        elif self.mode == "terminal":
            print("[PHASE 2] Loading 72GB Historical Data from local terminal drive...")
            # Load the massive dataset strictly from the local SSD into the 32GB RAM
            return pd.read_csv(self.historical_path)
        else:
            raise ValueError("Invalid mode. Choose 'mock' or 'terminal'.")

    def test_pipeline(self):
        """
        Built-in function to test the transition from Mock to Terminal data.
        It verifies data integrity, shape, and readiness for the SCG neural network.
        """
        print(f"--- Running Pre-flight Test for Mode: {self.mode.upper()} ---")
        try:
            # 1. Test File Loading
            df = self.load_data()
            print(f"SUCCESS: Data loaded. Total Rows: {len(df)}")

            # 2. Test Expected Columns (Required for SCG Inputs)
            expected_columns = ['Time', 'Open', 'High', 'Low', 'Close', 'Volume']
            missing_cols = [col for col in expected_columns if col not in df.columns]

            if missing_cols:
                print(f"ERROR: Missing expected columns for neural network: {missing_cols}")
                return False
            else:
                print("SUCCESS: All required matrix columns (OHLCV) are present.")

            # 3. Test for Null Values (Data Cleaning Check)
            if df.isnull().values.any():
                print("WARNING: Null values detected in the dataset. Proceeding with data cleaning...")
                df = df.dropna()
                print(f"SUCCESS: Null values dropped. New Shape: {df.shape}")

            # 4. Neural Network Matrix Formatting Check
            # Ensure data can be converted to a NumPy array for TensorFlow/Keras [1]
            train_data_array = np.array(df[['Open', 'High', 'Low', 'Close', 'Volume']])
            print(f"SUCCESS: Data successfully cast to NumPy array for SCG ingestion. Matrix Shape: {train_data_array.shape}")

            print("--- Pre-flight Test Complete. System Ready for Neural Network Training. ---")
            return True

        except FileNotFoundError:
            print(f"FATAL ERROR: The data file was not found at the specified path for '{self.mode}' mode. ({self.mock_path if self.mode == 'mock' else self.historical_path})")
            return False
        except Exception as e:
            print(f"FATAL ERROR: An unexpected error occurred during data validation: {e}")
            return False
