import std/[asyncdispatch, os, logging]
import brain_system, hand_brain_ui, core_types, security

proc main() =
  # Setup logging
  addHandler(newConsoleLogger())
  
  echo """
  ╔══════════════════════════════════════════════════════════╗
  ║         Hand-Brain Control System - UI Launcher          ║
  ╚══════════════════════════════════════════════════════════╝
  """
  
  # Create brain system
  let brain = newBrainSystem()
  
  # Register some sample devices
  let securityMgr = brain.securityManager
  
  # Simulate some registered devices
  let smartphone = securityMgr.registerDevice(
    dtSmartphone,
    {dcTouchScreen, dcMotionSensor, dcBiometrics, dcCamera}
  )
  
  let tablet = securityMgr.registerDevice(
    dtTablet,
    {dcTouchScreen, dcStylus, dcCamera, dcMicrophone}
  )
  
  let laptop = securityMgr.registerDevice(
    dtLaptop,
    {dcCamera, dcMicrophone, dcHapticFeedback}
  )
  
  let smartwatch = securityMgr.registerDevice(
    dtSmartwatch,
    {dcTouchScreen, dcMotionSensor, dcHapticFeedback}
  )
  
  echo &"Registered sample devices:"
  echo &"  - Smartphone: {smartphone.deviceId}"
  echo &"  - Tablet: {tablet.deviceId}"
  echo &"  - Laptop: {laptop.deviceId}"
  echo &"  - Smartwatch: {smartwatch.deviceId}"
  
  # Add some routing rules
  brain.addRouteRule(RouteRule(
    sourceDevice: smartphone.deviceId,
    destDevices: @[tablet.deviceId, laptop.deviceId],
    dataTypes: @["gesture", "touch", "screen"],
    priority: 1
  ))
  
  # Launch UI
  echo "\nLaunching Hand-Brain UI..."
  launchHandBrainUI(brain)

when isMainModule:
  main()