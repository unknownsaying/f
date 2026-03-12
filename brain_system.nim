import std/[asyncdispatch, json, times, tables, strutils, logging]
import std / [net, nativesockets]
import core_types, security, wifi_processor, gestures

type
  BrainSystem* = ref object
    # Core components
    securityManager*: SecurityManager
    wifiProcessor*: WiFiProcessor
    gestureEngine*: GestureEngine
    
    # Device management
    connectedHands*: Table[string, HandConnection]
    deviceRoutes*: Table[string, seq[string]]  # source -> [destinations]
    
    # Network
    server*: AsyncSocket
    running*: bool
    
    # Event handlers
    eventHandlers*: Table[string, seq[proc(data: JsonNode)]]
  
  HandConnection* = ref object
    session*: HandSession
    socket*: AsyncSocket
    deviceType*: DeviceType
    capabilities*: set[DeviceCapability]
    lastSeen*: float
    metadata*: JsonNode
    gestureCallbacks*: seq[proc(gesture: Gesture)]
  
  RouteRule* = object
    sourceDevice*: string
    destDevices*: seq[string]
    dataTypes*: seq[string]
    transform*: proc(data: JsonNode): JsonNode
    priority*: int

proc newBrainSystem*(): BrainSystem =
  result = BrainSystem(
    securityManager: newSecurityManager(),
    wifiProcessor: newWiFiProcessor(),
    gestureEngine: newGestureEngine(),
    connectedHands: initTable[string, HandConnection](),
    deviceRoutes: initTable[string, seq[string]](),
    eventHandlers: initTable[string, seq[proc(data: JsonNode)]](),
    running: true
  )
  
  # Setup logging
  addHandler(newConsoleLogger())
  
  # Initialize gesture callbacks
  setupGestureHandlers(result)

proc setupGestureHandlers(brain: BrainSystem) =
  ## Setup gesture recognition handlers
  
  # Tap gesture handler
  brain.gestureEngine.registerCallback(gtTap) do (gesture: Gesture):
    info "Tap detected at ", gesture.location
    # Route tap to appropriate device
    brain.routeGestureToDevices(gesture, @[dtSmartphone, dtTablet])
  
  # Swipe gesture handler
  brain.gestureEngine.registerCallback(gtSwipe) do (gesture: Gesture):
    info "Swipe detected: ", gesture.customData
    # Control multiple devices with swipe
    case gesture.customData{"direction"}.getStr():
    of "left":
      brain.broadcastToType(dtSmartwatch, %*{"action": "next_page"})
    of "right":
      brain.broadcastToType(dtSmartwatch, %*{"action": "prev_page"})
    of "up":
      brain.broadcastToType(dtVRHeadset, %*{"action": "scroll_up"})
    of "down":
      brain.broadcastToType(dtVRHeadset, %*{"action": "scroll_down"})
  
  # Pinch gesture handler
  brain.gestureEngine.registerCallback(gtPinch) do (gesture: Gesture):
    info "Pinch scale: ", gesture.scale
    # Zoom on all displays
    brain.broadcastToAll(%*{
      "command": "zoom",
      "scale": gesture.scale,
      "location": gesture.location
    })
  
  # Three finger swipe for device switching
  brain.gestureEngine.registerCallback(gtThreeFingerSwipe) do (gesture: Gesture):
    info "Switching active device"
    brain.switchActiveDevice()

proc startServer*(brain: BrainSystem, port: int = 5000) {.async.} =
  ## Start the Brain server
  brain.server = newAsyncSocket()
  brain.server.bindAddr(Port(port))
  brain.server.listen()
  
  info &"Brain system listening on port {port}"
  
  while brain.running:
    try:
      let (clientSocket, address) = await brain.server.acceptAddr()
      info &"New connection from {address}"
      
      # Start hand handler
      asyncCheck brain.handleHand(clientSocket, $address)
      
    except:
      error "Accept error: ", getCurrentExceptionMsg()

proc handleHand*(brain: BrainSystem, socket: AsyncSocket, address: string) {.async.} =
  ## Handle a connected Hand device
  var buffer = ""
  var authenticated = false
  var sessionId = ""
  
  try:
    while brain.running:
      let data = await socket.recv(1024)
      if data.len == 0:
        break
      
      buffer.add(data)
      
      # Process complete messages (newline separated)
      while buffer.contains("\n"):
        let lineEnd = buffer.find("\n")
        let line = buffer[0..<lineEnd]
        buffer = buffer[lineEnd+1..^1]
        
        let msg = parseJson(line)
        
        if not authenticated:
          # Handle authentication
          if msg{"type"}.getStr() == "auth":
            let authResult = brain.securityManager.authenticate(
              msg["device_id"].getStr(),
              msg["auth_data"]
            )
            
            if authResult.success:
              authenticated = true
              sessionId = authResult.session.sessionId
              
              # Register hand
              let hand = HandConnection(
                session: authResult.session,
                socket: socket,
                deviceType: parseDeviceType(msg["device_type"].getStr()),
                capabilities: parseCapabilities(msg["capabilities"]),
                lastSeen: epochTime(),
                metadata: msg.getOrDefault("metadata", %*{})
              )
              
              brain.connectedHands[sessionId] = hand
              
              await socket.send($%*{
                "type": "auth_success",
                "session_id": sessionId,
                "token": authResult.session.authToken
              } & "\n")
              
              info &"Hand authenticated: {hand.deviceType}"
              
              # Trigger connection event
              brain.triggerEvent("hand_connected", %*{
                "session_id": sessionId,
                "device_type": $hand.deviceType
              })
              
            else:
              await socket.send($%*{
                "type": "auth_failed",
                "error": authResult.error
              } & "\n")
              await sleepAsync(1000)
              break
        else:
          # Process authenticated messages
          let decrypted = brain.securityManager.decryptData(sessionId, msg["data"].getStr())
          let command = parseJson(decrypted)
          
          # Update hand
          if brain.connectedHands.hasKey(sessionId):
            brain.connectedHands[sessionId].lastSeen = epochTime()
          
          case command["type"].getStr():
          of "touch_data":
            # Process touch input for gesture recognition
            let touches = parseTouches(command["touches"])
            for touch in touches:
              let gestures = brain.gestureEngine.processTouch(touch)
              if gestures.len > 0:
                brain.handleGestures(sessionId, gestures)
          
          of "screen_data":
            # Process screen capture
            brain.processScreenData(sessionId, command["data"])
          
          of "wifi_scan":
            # Process WiFi scan results
            let packets = parseWiFiPackets(command["packets"])
            for packet in packets:
              brain.wifiProcessor.capturePacket(packet)
            
            # Analyze and respond
            let threats = brain.wifiProcessor.detectNetworkThreats()
            if threats.len > 0:
              await brain.sendToHand(sessionId, %*{
                "type": "security_alert",
                "threats": threats
              })
          
          of "gesture_result":
            # Handle ML gesture results
            brain.processMLGestureResult(sessionId, command)
          
          else:
            # Route data according to rules
            brain.routeData(sessionId, command)
          
  except:
    error &"Error handling hand {address}: ", getCurrentExceptionMsg()
  finally:
    socket.close()
    if sessionId != "" and brain.connectedHands.hasKey(sessionId):
      brain.connectedHands.del(sessionId)
      info &"Hand {sessionId} disconnected"
      brain.triggerEvent("hand_disconnected", %*{"session_id": sessionId})

proc routeData*(brain: BrainSystem, sourceId: string, data: JsonNode) =
  ## Route data from one hand to others based on rules
  let destinations = brain.deviceRoutes.getOrDefault(sourceId)
  
  for destId in destinations:
    if brain.connectedHands.hasKey(destId):
      # Check permissions
      if brain.securityManager.checkPermission(
        brain.connectedHands[destId].session.sessionId,
        "receive_data"
      ):
        asyncCheck brain.sendToHand(destId, data)

proc sendToHand*(brain: BrainSystem, sessionId: string, data: JsonNode) {.async.} =
  ## Send encrypted data to a specific hand
  let hand = brain.connectedHands.getOrDefault(sessionId)
  if hand != nil:
    let encrypted = brain.securityManager.encryptData(
      sessionId,
      $data
    )
    
    let msg = %*{
      "type": "command",
      "data": encrypted,
      "timestamp": epochTime()
    }
    
    try:
      await hand.socket.send($msg & "\n")
    except:
      error "Failed to send to hand: ", sessionId

proc broadcastToType*(brain: BrainSystem, deviceType: DeviceType, data: JsonNode) =
  ## Broadcast to all hands of a specific type
  for sessionId, hand in brain.connectedHands:
    if hand.deviceType == deviceType:
      asyncCheck brain.sendToHand(sessionId, data)

proc broadcastToAll*(brain: BrainSystem, data: JsonNode) =
  ## Broadcast to all connected hands
  for sessionId in brain.connectedHands.keys:
    asyncCheck brain.sendToHand(sessionId, data)

proc addRouteRule*(brain: BrainSystem, rule: RouteRule) =
  ## Add a routing rule
  for dest in rule.destDevices:
    if not brain.deviceRoutes.hasKey(rule.sourceDevice):
      brain.deviceRoutes[rule.sourceDevice] = @[]
    brain.deviceRoutes[rule.sourceDevice].add(dest)

proc on*(brain: BrainSystem, event: string, handler: proc(data: JsonNode)) =
  ## Register event handler
  if not brain.eventHandlers.hasKey(event):
    brain.eventHandlers[event] = @[]
  brain.eventHandlers[event].add(handler)

proc triggerEvent*(brain: BrainSystem, event: string, data: JsonNode) =
  ## Trigger an event
  if brain.eventHandlers.hasKey(event):
    for handler in brain.eventHandlers[event]:
      handler(data)

proc handleGestures*(brain: BrainSystem, sessionId: string, gestures: seq[Gesture]) =
  ## Handle recognized gestures
  for gesture in gestures:
    info &"Gesture recognized: {gesture.gestureType} (confidence: {gesture.confidence})"
    
    # Log gesture for ML training
    brain.logGestureForTraining(sessionId, gesture)
    
    # Trigger gesture event
    brain.triggerEvent("gesture", %*{
      "session_id": sessionId,
      "gesture_type": $gesture.gestureType,
      "location": %*{"x": gesture.location.x, "y": gesture.location.y},
      "confidence": gesture.confidence,
      "data": gesture.customData
    })

proc logGestureForTraining*(brain: BrainSystem, sessionId: string, gesture: Gesture) =
  ## Log gestures for ML model training
  # Implementation would store gesture data for later training
  discard

proc processScreenData*(brain: BrainSystem, sessionId: string, screenData: JsonNode) =
  ## Process screen capture data
  info &"Processing screen data from {sessionId}"
  # Implementation would handle screen sharing, analysis, etc.

proc processMLGestureResult*(brain: BrainSystem, sessionId: string, result: JsonNode) =
  ## Process ML-based gesture recognition results
  info &"ML gesture result from {sessionId}: {result}"

proc switchActiveDevice*(brain: BrainSystem) =
  ## Switch the currently active controlled device
  # Implementation would cycle through connected devices
  info "Switching active device"

# Helper functions
proc parseDeviceType(typ: string): DeviceType = 
  parseEnum[DeviceType](typ)

proc parseCapabilities(caps: JsonNode): set[DeviceCapability] = 
  result = {}
  for cap in caps:
    result.incl(parseEnum[DeviceCapability](cap.getStr()))

proc parseTouches(touches: JsonNode): seq[TouchPoint] = 
  result = @[]
  for touch in touches:
    result.add(TouchPoint(
      id: touch["id"].getInt(),
      x: touch["x"].getFloat(),
      y: touch["y"].getFloat(),
      pressure: touch.getOrDefault("pressure", %0.0).getFloat(),
      timestamp: epochTime()
    ))

proc parseWiFiPackets(packets: JsonNode): seq[WiFiPacket] = 
  result = @[]

when isMainModule:
  # Create brain system
  let brain = newBrainSystem()
  
  # Add routing rules
  brain.addRouteRule(RouteRule(
    sourceDevice: "smartphone_1",
    destDevices: @["tablet_1", "laptop_1"],
    dataTypes: @["touch", "gesture"],
    priority: 1
  ))
  
  # Register event handlers
  brain.on("hand_connected") do (data: JsonNode):
    info &"Event - Hand connected: {data}"
  
  brain.on("gesture") do (data: JsonNode):
    info &"Event - Gesture detected: {data}"
  
  # Start server
  waitFor brain.startServer()