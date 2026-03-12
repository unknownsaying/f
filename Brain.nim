import std/[asyncnet, asyncdispatch, json, strformat, random, tables]
import wNim

type
  Client = ref object
    socket: AsyncSocket
    address: string

  BrainApp = ref object
    frame: wFrame
    statusBar: wStatusBar
    btnMove: wButton
    btnQuit: wButton
    clients: seq[Client]
    server: AsyncSocket
    running: bool

proc handleClient(brain: BrainApp, client: Client) {.async.} =
  ## Handle messages from a connected Hand client
  try:
    while brain.running:
      let data = await client.socket.recv(1024)
      if data.len == 0:
        echo &"Client {client.address} disconnected"
        brain.clients.keepItIf(it.address != client.address)
        brain.statusBar.setStatusText(&"Connected Hands: {brain.clients.len}")
        break
      
      try:
        let msg = parseJson(data)
        echo &"Received from {client.address}: {msg}"
        
        # Process incoming data (screen collect, touch events, etc.)
        if msg.hasKey("type") and msg["type"].getStr() == "position":
          let x = msg["x"].getFloat()
          let y = msg["y"].getFloat()
          echo &"Hand {client.address} moved to ({x:.1f}, {y:.1f})"
          
          # Here you could route data to other Hands or process it
          
      except:
        echo &"Invalid JSON from {client.address}: {data}"
        
  except:
    echo &"Error handling client {client.address}"
  finally:
    client.socket.close()

proc broadcast(brain: BrainApp, msg: JsonNode) {.async.} =
  ## Send a message to all connected clients
  let data = $msg
  for client in brain.clients:
    try:
      await client.socket.send(data & "\c\L")
    except:
      echo &"Failed to send to {client.address}"

proc acceptConnections(brain: BrainApp) {.async.} =
  ## Accept incoming Hand connections
  brain.server = newAsyncSocket()
  brain.server.bindAddr(Port(5000))
  brain.server.listen()
  echo "Brain listening on port 5000"
  
  while brain.running:
    try:
      let (clientSocket, address) = await brain.server.acceptAddr()
      let client = Client(socket: clientSocket, address: $address)
      brain.clients.add(client)
      echo &"Hand connected from {address}"
      brain.statusBar.setStatusText(&"Connected Hands: {brain.clients.len}")
      
      # Start client handler
      asyncCheck brain.handleClient(client)
      
    except:
      echo "Accept error"

proc moveAllRandom(brain: BrainApp) =
  ## Move all connected Hands to random positions
  let x = rand(50.0..400.0)
  let y = rand(50.0..400.0)
  
  let msg = %*{
    "type": "move",
    "x": x,
    "y": y
  }
  
  asyncCheck brain.broadcast(msg)
  echo &"Broadcasting move to ({x:.1f}, {y:.1f})"

proc quit(brain: BrainApp) =
  ## Shutdown the Brain application
  brain.running = false
  asyncCheck brain.broadcast(%*{"type": "quit"})
  brain.server.close()
  brain.frame.close()

proc initBrain(): BrainApp =
  ## Initialize the Brain application
  result = BrainApp(
    clients: @[],
    running: true
  )
  
  # Setup GUI
  let app = wApp()
  result.frame = wFrame(title="Brain Controller", size=(400, 200))
  
  # Status bar
  result.statusBar = result.frame.statusBar
  result.statusBar.setStatusText("Waiting for connections...")
  
  # Buttons panel
  let panel = wPanel(result.frame)
  let btnMove = wButton(panel, label="Move All Hands Randomly", pos=(100, 50))
  let btnQuit = wButton(panel, label="Quit", pos=(100, 90))
  
  # Connect events
  wConnect(btnMove, wEvent_Button) do ():
    result.moveAllRandom()
    
  wConnect(btnQuit, wEvent_Button) do ():
    result.quit()
  
  result.frame.center()
  result.frame.show()
  
  # Start async loop
  asyncCheck result.acceptConnections()

proc run(brain: BrainApp) =
  ## Main event loop
  wApp().run()

when isMainModule:
  randomize()
  let brain = initBrain()
  brain.run()