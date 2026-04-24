import zmq
import threading
import time

class ZMQBridge:
    def __init__(self, port_rep=5555, port_push=5556):
        self.context = zmq.Context()

        # Socket for receiving data from MT5
        self.pull_socket = self.context.socket(zmq.PULL)
        self.pull_socket.bind(f"tcp://*:{port_rep}")

        # Socket for sending commands to MT5
        self.push_socket = self.context.socket(zmq.PUSH)
        self.push_socket.bind(f"tcp://*:{port_push}")

        self.running = False
        self.thread = None
        self.callback = None

        print(f"[ZMQ Bridge] Initialized PULL on {port_rep}, PUSH on {port_push}")

    def start(self, callback):
        self.callback = callback
        self.running = True
        self.thread = threading.Thread(target=self._listen)
        self.thread.start()
        print("[ZMQ Bridge] Listening for MT5 data...")

    def stop(self):
        self.running = False
        if self.thread:
            self.thread.join()
        self.pull_socket.close()
        self.push_socket.close()
        self.context.term()
        print("[ZMQ Bridge] Stopped.")

    def _listen(self):
        while self.running:
            try:
                # Non-blocking receive
                message = self.pull_socket.recv_string(flags=zmq.NOBLOCK)

                if self.callback:
                    self.callback(message)

            except zmq.Again:
                time.sleep(0.001)  # 1ms sleep to prevent CPU pegging
            except Exception as e:
                if self.running:
                    print(f"[ZMQ Bridge] Error: {e}")

    def send_command(self, command: str):
        """
        Sends an execution command to MT5.
        Format: TRADE|OPEN|BUY|SYMBOL|PRICE
        """
        try:
            self.push_socket.send_string(command)
            print(f"[ZMQ Bridge] Sent Command: {command}")
        except Exception as e:
            print(f"[ZMQ Bridge] Send Error: {e}")
