import std/[asyncnet, asyncdispatch, json, strformat]
import wNim

type
  HandApp = ref object
    frame: wFrame
    canvas: wCanvas
    point: wBitmap
    pointX, pointY: int
    dragging: bool
    dragStartX, dragStartY: int
    socket: AsyncSocket
    connected: bool
    brainHost: string
    brainPort: int

proc connectToBrain(hand: HandApp) {.async.} =
  ## Connect to the Brain server
  try:
    hand.socket = newAsyncSocket()
    await hand.socket.connect(hand.brainHost, Port(hand.brainPort))
    hand.connected = true
    hand.frame.setStatusText("Connected to Brain")
    echo "Connected to Brain"
  except:
    hand.connected = false
    hand.frame.setStatusText("Failed to connect to Brain")
    echo "Connection failed"

proc listenToBrain(hand: HandApp) {.async.} =
  ## Listen for commands from the Brain
  while hand.connected:
    try:
      let data = await hand.socket.recvLine()
      if data.len == 0:
        hand.connected = false
        hand.frame.setStatusText("Disconnected from Brain")
        break
      
      let msg = parseJson(data)
      echo &"Received from Brain: {msg}"
      
      if msg.hasKey("type"):
        case msg["type"].getStr():
        of "move":
          let x = msg["x"].getFloat().int
          let y = msg["y"].getFloat().int
          hand.pointX = x
          hand.pointY = y
          hand.canvas.refresh()
          
        of "quit":
          hand.connected = false
          hand.frame.close()
          
    except:
      hand.connected = false
      break

proc sendToBrain(hand: HandApp, msg: JsonNode) {.async.} =
  ## Send data to the Brain
  if hand.connected:
    try:
      await hand.socket.send($msg & "\c\L")
    except:
      echo "Failed to send to Brain"

proc drawPoint(hand: HandApp) =
  ## Draw the draggable point on canvas
  let dc = hand.canvas.paint()
  dc.clear()
  
  # Draw crosshair lines
  dc.setPen(wPen(wxWHITE, style=wxSOLID))
  dc.drawLine(hand.pointX - 30, hand.pointY, hand.pointX + 30, hand.pointY)
  dc.drawLine(hand.pointX, hand.pointY - 30, hand.pointX, hand.pointY + 30)
  
  # Draw the main point
  dc.setBrush(wBrush(wxRED))
  dc.setPen(wPen(wxWHITE, width=2))
  dc.drawCircle(hand.pointX, hand.pointY, 10)
  
  # Draw coordinates
  dc.setFont(wFont(size=12, family=wxFONTFAMILY_DEFAULT))
  dc.setPen(wPen(wxWHITE))
  dc.drawText(&"({hand.pointX}, {hand.pointY})", hand.pointX + 15, hand.pointY - 15)

proc onMouse(hand: HandApp, event: wMouseEvent) =
  ## Handle mouse events for dragging
  let (x, y) = event.getPosition()
  
  case event.getEventType():
  of wEvent_MouseLeftDown:
    # Check if click is within the point (simple hit testing)
    let dx = x - hand.pointX
    let dy = y - hand.pointY
    if dx*dx + dy*dy <= 225:  # Within 15 pixels radius
      hand.dragging = true
      hand.dragStartX = x
      hand.dragStartY = y
      hand.frame.setStatusText("Dragging...")
      
  of wEvent_MouseMotion:
    if hand.dragging and event.leftIsDown():
      # Move the point
      hand.pointX = x
      hand.pointY = y
      hand.canvas.refresh()
      
  of wEvent_MouseLeftUp:
    if hand.dragging:
      hand.dragging = false
      hand.frame.setStatusText(&"Position: ({hand.pointX}, {hand.pointY})")
      
      # Send new position to Brain
      let msg = %*{
        "type": "position",
        "x": hand.pointX.float,
        "y": hand.pointY.float,
        "device": "Hand"
      }
      asyncCheck hand.sendToBrain(msg)
      
  else:
    discard

proc initHand(brainHost: string = "127.0.0.1", brainPort: int = 5000): HandApp =
  ## Initialize the Hand application
  result = HandApp(
    pointX: 250,
    pointY: 250,
    dragging: false,
    brainHost: brainHost,
    brainPort: brainPort,
    connected: false
  )
  
  # Setup GUI
  let app = wApp()
  result.frame = wFrame(title="Hand Device", size=(500, 550))
  
  # Status bar
  result.frame.statusBar
  
  # Canvas for drawing
  result.canvas = wCanvas(result.frame, style=wxBORDER_SIMPLE)
  result.canvas.setBackgroundColour(wxBLACK)
  
  # Bind events
  wConnect(result.canvas, wEvent_Paint) do (event: wPaintEvent):
    result.drawPoint()
  
  wConnect(result.canvas, wEvent_Mouse, result.onMouse)
  
  # Bind window close event
  wConnect(result.frame, wEvent_Close) do (event: wCloseEvent):
    result.connected = false
    if result.socket != nil:
      result.socket.close()
    event.skip()
  
  # Center and show
  result.frame.setSize(500, 550)
  result.frame.center()
  result.frame.show()
  
  # Connect to Brain
  asyncCheck result.connectToBrain()
  asyncCheck result.listenToBrain()

proc run(hand: HandApp) =
  ## Main event loop
  wApp().run()

when isMainModule:
  # Parse command line arguments
  var brainHost = "127.0.0.1"
  var brainPort = 5000
  
  if paramCount() >= 1:
    brainHost = paramStr(1)
  if paramCount() >= 2:
    brainPort = parseInt(paramStr(2))
  
  let hand = initHand(brainHost, brainPort)
  hand.run()