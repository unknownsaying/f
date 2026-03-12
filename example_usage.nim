import std/[asyncdispatch, json, times]
import brain_system, core_types, security, gestures

proc demo() {.async.} =
  # Create brain system
  let brain = newBrainSystem()
  
  # Register devices
  let smartphone = brain.securityManager.registerDevice(
    dtSmartphone,
    {dcTouchScreen, dcMotionSensor, dcBiometrics}
  )
  
  let tablet = brain.securityManager.registerDevice(
    dtTablet,
    {dcTouchScreen, dcStylus, dcCamera}
  )
  
  let smartwatch = brain.securityManager.registerDevice(
    dtSmartwatch,
    {dcTouchScreen, dcMotionSensor, dcHapticFeedback}
  )
  
  echo &"Registered devices:"
  echo &"  Smartphone: {smartphone.deviceId}"
  echo &"  Tablet: {tablet.deviceId}"
  echo &"  Smartwatch: {smartwatch.deviceId}"
  
  # Add routing rules
  brain.addRouteRule(RouteRule(
    sourceDevice: smartphone.deviceId,
    destDevices: @[tablet.deviceId, smartwatch.deviceId],
    dataTypes: @["gesture", "touch"],
    priority: 1
  ))
  
  # Test gesture recognition
  let engine = brain.gestureEngine
  
  # Simulate tap gesture
  let tapTouches = @[
    TouchPoint(id: 1, x: 100, y: 200, timestamp: epochTime()),
    TouchPoint(id: 1, x: 101, y: 201, timestamp: epochTime() + 0.1),
    TouchPoint(id: 1, x: 102, y: 202, timestamp: epochTime() + 0.2)
  ]
  
  for touch in tapTouches:
    let gestures = engine.processTouch(touch)
    for gesture in gestures:
      if gesture.gestureType == gtTap and gesture.state == gsEnded:
        echo &"Tap detected at ({gesture.location.x}, {gesture.location.y})"
  
  # Simulate swipe gesture
  let swipeTouches = @[
    TouchPoint(id: 2, x: 100, y: 200, timestamp: epochTime()),
    TouchPoint(id: 2, x: 150, y: 205, timestamp: epochTime() + 0.1),
    TouchPoint(id: 2, x: 200, y: 210, timestamp: epochTime() + 0.2),
    TouchPoint(id: 2, x: 250, y: 215, timestamp: epochTime() + 0.3),
    TouchPoint(id: 2, x: 300, y: 220, timestamp: epochTime() + 0.4)
  ]
  
  for touch in swipeTouches:
    let gestures = engine.processTouch(touch)
    for gesture in gestures:
      if gesture.gestureType == gtSwipe and gesture.state == gsEnded:
        echo &"Swipe detected: {gesture.customData}"
  
  # Test WiFi processing
  let wp = brain.wifiProcessor
  
  # Simulate some WiFi packets
  for i in 0..<10:
    let packet = WiFiPacket(
      sourceMAC: "AA:BB:CC:DD:EE:FF",
      destMAC: "11:22:33:44:55:66",
      bssid: "00:11:22:33:44:55",
      ssid: "TestNetwork",
      rssi: rand(-90..-30),
      channel: rand(1..11),
      packetType: "data",
      timestamp: epochTime() + i.float
    )
    wp.packets.add(packet)
  
  # Analyze signal quality
  let signalAnalysis = wp.analyzeSignalQuality("AA:BB:CC:DD:EE:FF")
  echo &"Signal analysis: {signalAnalysis}"
  
  # Get channel recommendations
  let channelOpt = wp.optimizeChannelSelection()
  echo &"Channel optimization: {channelOpt}"
  
  # Start server
  echo "Starting Brain server..."
  await brain.startServer()

when isMainModule:
  waitFor demo()