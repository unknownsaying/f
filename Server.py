import socket
import threading
import json
import random
import tkinter as tk
from tkinter import messagebox

class BrainServer:
    def __init__(self, host='127.0.0.1', port=5000):
        self.host = host
        self.port = port
        self.clients = []  # list of client sockets
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(5)
        print(f"Brain listening on {self.host}:{self.port}")

        # GUI setup
        self.root = tk.Tk()
        self.root.title("Brain Controller")
        self.status_label = tk.Label(self.root, text="Waiting for connections...")
        self.status_label.pack(pady=10)
        self.move_button = tk.Button(self.root, text="Move All Hands Randomly", command=self.move_all_random)
        self.move_button.pack(pady=5)
        self.quit_button = tk.Button(self.root, text="Quit", command=self.quit)
        self.quit_button.pack(pady=5)

        # Start listening thread
        threading.Thread(target=self.accept_connections, daemon=True).start()

    def accept_connections(self):
        while True:
            client_socket, addr = self.server_socket.accept()
            self.clients.append(client_socket)
            print(f"New hand connected from {addr}")
            self.status_label.config(text=f"Connected hands: {len(self.clients)}")
            # Start a thread to handle messages from this hand
            threading.Thread(target=self.handle_client, args=(client_socket,), daemon=True).start()

    def handle_client(self, client_socket):
        try:
            while True:
                data = client_socket.recv(1024)
                if not data:
                    break
                message = json.loads(data.decode('utf-8'))
                print(f"Received from hand: {message}")
                # Process incoming data (e.g., route to other hands or log)
                # For now, just print
        except:
            pass
        finally:
            client_socket.close()
            self.clients.remove(client_socket)
            print("Hand disconnected")
            self.status_label.config(text=f"Connected hands: {len(self.clients)}")

    def send_to_all(self, message):
        for client in self.clients[:]:  # iterate over a copy
            try:
                client.sendall(json.dumps(message).encode('utf-8'))
            except:
                self.clients.remove(client)

    def move_all_random(self):
        x = random.randint(50, 400)
        y = random.randint(50, 400)
        self.send_to_all({"type": "move", "x": x, "y": y})

    def quit(self):
        self.server_socket.close()
        self.root.quit()

    def run(self):
        self.root.mainloop()

if __name__ == "__main__":
    brain = BrainServer()
    brain.run()