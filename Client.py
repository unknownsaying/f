import socket
import threading
import json
import tkinter as tk

class HandClient:
    def __init__(self, brain_host='127.0.0.1', brain_port=5000):
        self.brain_host = brain_host
        self.brain_port = brain_port
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.connect_to_brain()

        # GUI setup
        self.root = tk.Tk()
        self.root.title("Hand")
        self.canvas = tk.Canvas(self.root, width=500, height=500, bg='white')
        self.canvas.pack()
        self.point = self.canvas.create_oval(240, 240, 260, 260, fill='red')
        self.drag_data = {"x": 0, "y": 0, "item": None}

        # Bind mouse events for dragging
        self.canvas.tag_bind(self.point, '<Button-1>', self.on_click)
        self.canvas.tag_bind(self.point, '<B1-Motion>', self.on_drag)
        self.canvas.tag_bind(self.point, '<ButtonRelease-1>', self.on_release)

        # Start listening thread for brain commands
        threading.Thread(target=self.listen_to_brain, daemon=True).start()

    def connect_to_brain(self):
        try:
            self.socket.connect((self.brain_host, self.brain_port))
            print("Connected to brain")
        except Exception as e:
            print(f"Failed to connect: {e}")

    def listen_to_brain(self):
        while True:
            try:
                data = self.socket.recv(1024)
                if not data:
                    break
                message = json.loads(data.decode('utf-8'))
                self.handle_command(message)
            except:
                break

    def handle_command(self, message):
        if message['type'] == 'move':
            x, y = message['x'], message['y']
            # Move the point to new coordinates (centered on the point)
            self.canvas.coords(self.point, x-10, y-10, x+10, y+10)

    def send_to_brain(self, message):
        try:
            self.socket.sendall(json.dumps(message).encode('utf-8'))
        except:
            pass

    def on_click(self, event):
        # Record the item and its location
        self.drag_data["item"] = self.point
        self.drag_data["x"] = event.x
        self.drag_data["y"] = event.y

    def on_drag(self, event):
        # Move the point
        if self.drag_data["item"]:
            dx = event.x - self.drag_data["x"]
            dy = event.y - self.drag_data["y"]
            self.canvas.move(self.drag_data["item"], dx, dy)
            self.drag_data["x"] = event.x
            self.drag_data["y"] = event.y

    def on_release(self, event):
        # Send new position to brain
        x1, y1, x2, y2 = self.canvas.coords(self.point)
        center_x = (x1 + x2) / 2
        center_y = (y1 + y2) / 2
        self.send_to_brain({"type": "position", "x": center_x, "y": center_y})
        self.drag_data["item"] = None

    def run(self):
        self.root.mainloop()

if __name__ == "__main__":
    hand = HandClient()
    hand.run()