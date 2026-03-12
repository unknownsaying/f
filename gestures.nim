import std/[json, times, tables, math, strutils, sequtils]
import core_types

type
  GestureType* = enum
    gtTap = "tap"
    gtDoubleTap = "double_tap"
    gtLongPress = "long_press"
    gtSwipe = "swipe"
    gtPinch = "pinch"
    gtRotate = "rotate"
    gtPan = "pan"
    gtFlick = "flick"
    gtDrag = "drag"
    gtDrop = "drop"
    gtZoom = "zoom"
    gtThreeFingerSwipe = "three_finger_swipe"
    gtFourFingerSwipe = "four_finger_swipe"
    gtRotateThreeFinger = "rotate_three_finger"
    gtPressAndTap = "press_and_tap"
    gtPressAndDrag = "press_and_drag"
    gtEdgeSwipe = "edge_swipe"
  
  GestureState* = enum
    gsPossible
    gsBegan
    gsChanged
    gsEnded
    gsCancelled
    gsFailed
  
  TouchPoint* = object
    id*: int
    x*, y*: float
    pressure*: float
    radius*: float
    timestamp*: float
    velocity*: tuple[vx, vy: float]
    acceleration*: tuple[ax, ay: float]
  
  Gesture* = object
    gestureType*: GestureType
    state*: GestureState
    location*: tuple[x, y: float]
    velocity*: tuple[vx, vy: float]
    scale*: float
    rotation*: float
    translation*: tuple[dx, dy: float]
    numberOfTouches*: int
    confidence*: float
    timestamp*: float
    customData*: JsonNode
  
  GestureRecognizer* = ref object
    name*: string
    gestureType*: GestureType
    minTouches*: int
    maxTouches*: int
    minDuration*: float
    maxDuration*: float
    minMovement*: float
    maxMovement*: float
    requireTapCount*: int
    allowableMovement*: float
    cancelsTouchesInView*: bool
    delaysTouches*: bool
    callback*: proc(gesture: Gesture)
  
  GestureEngine* = ref object
    recognizers*: seq[GestureRecognizer]
    activeGestures*: Table[int, Gesture]
    touchHistory*: Table[int, seq[TouchPoint]]
    multiTouchSequences*: Table[string, seq[TouchPoint]]
    gestureCallbacks*: Table[GestureType, seq[proc(gesture: Gesture)]]
    config*: GestureConfig
    mlModel*: MLModel  # For ML-based gesture recognition
  
  GestureConfig = object
    tapMaxDuration: float
    doubleTapMaxInterval: float
    longPressMinDuration: float
    swipeMinDistance: float
    swipeMaxDuration: float
    pinchMinScale: float
    rotationMinAngle: float
    edgeSwipeThreshold: float
    useMachineLearning: bool
    learningRate: float
  
  MLModel = object
    weights: seq[float]
    layers: seq[int]
    trained: bool

proc newGestureEngine*(config: GestureConfig = GestureConfig()): GestureEngine =
  ## Create a new gesture recognition engine
  result = GestureEngine(
    recognizers: @[],
    activeGestures: initTable[int, Gesture](),
    touchHistory: initTable[int, seq[TouchPoint]](),
    multiTouchSequences: initTable[string, seq[TouchPoint]](),
    gestureCallbacks: initTable[GestureType, seq[proc(gesture: Gesture)]](),
    config: config,
    mlModel: MLModel(layers: @[10, 20, 10], trained: false)
  )
  
  # Register default recognizers
  result.addRecognizer(createTapRecognizer())
  result.addRecognizer(createDoubleTapRecognizer())
  result.addRecognizer(createLongPressRecognizer())
  result.addRecognizer(createSwipeRecognizer())
  result.addRecognizer(createPinchRecognizer())
  result.addRecognizer(createRotateRecognizer())
  result.addRecognizer(createPanRecognizer())
  result.addRecognizer(createThreeFingerSwipeRecognizer())
  result.addRecognizer(createEdgeSwipeRecognizer())

proc addRecognizer*(engine: GestureEngine, recognizer: GestureRecognizer) =
  engine.recognizers.add(recognizer)

proc registerCallback*(engine: GestureEngine, gestureType: GestureType, 
                       callback: proc(gesture: Gesture)) =
  if not engine.gestureCallbacks.hasKey(gestureType):
    engine.gestureCallbacks[gestureType] = @[]
  engine.gestureCallbacks[gestureType].add(callback)

proc processTouch*(engine: GestureEngine, touch: TouchPoint): seq[Gesture] =
  ## Process a new touch point and detect gestures
  result = @[]
  let now = epochTime()
  
  # Update touch history
  if not engine.touchHistory.hasKey(touch.id):
    engine.touchHistory[touch.id] = @[]
  
  var history = engine.touchHistory[touch.id]
  history.add(touch)
  
  # Keep last 50 points
  if history.len > 50:
    history.delete(0)
  engine.touchHistory[touch.id] = history
  
  # Calculate velocity and acceleration
  if history.len >= 3:
    let last = history[^1]
    let prev = history[^2]
    let older = history[^3]
    
    let dt1 = last.timestamp - prev.timestamp
    let dt2 = prev.timestamp - older.timestamp
    
    if dt1 > 0 and dt2 > 0:
      let vx = (last.x - prev.x) / dt1
      let vy = (last.y - prev.y) / dt1
      
      let vxPrev = (prev.x - older.x) / dt2
      let vyPrev = (prev.y - older.y) / dt2
      
      let ax = (vx - vxPrev) / ((dt1 + dt2) / 2)
      let ay = (vy - vyPrev) / ((dt1 + dt2) / 2)
      
      engine.touchHistory[touch.id][^1].velocity = (vx: vx, vy: vy)
      engine.touchHistory[touch.id][^1].acceleration = (ax: ax, ay: ay)
  
  # Run all recognizers
  for recognizer in engine.recognizers:
    let gesture = recognizeGesture(engine, recognizer, touch)
    if gesture.state != gsFailed and gesture.state != gsCancelled:
      result.add(gesture)
      
      # Call specific callbacks
      if engine.gestureCallbacks.hasKey(gesture.gestureType):
        for callback in engine.gestureCallbacks[gesture.gestureType]:
          callback(gesture)
  
  # ML-based gesture recognition
  if engine.config.useMachineLearning:
    let mlGestures = recognizeWithML(engine, touch)
    result.add(mlGestures)

proc recognizeGesture(engine: GestureEngine, recognizer: GestureRecognizer, 
                      touch: TouchPoint): Gesture =
  ## Recognize a specific gesture type
  result = Gesture(
    gestureType: recognizer.gestureType,
    state: gsPossible,
    timestamp: touch.timestamp,
    numberOfTouches: 1
  )
  
  # Get relevant touches
  let activeTouches = getActiveTouches(engine, touch.timestamp)
  if activeTouches.len < recognizer.minTouches or 
     activeTouches.len > recognizer.maxTouches:
    result.state = gsFailed
    return
  
  case recognizer.gestureType:
  of gtTap:
    result = recognizeTap(engine, recognizer, touch)
  of gtDoubleTap:
    result = recognizeDoubleTap(engine, recognizer, touch)
  of gtLongPress:
    result = recognizeLongPress(engine, recognizer, touch)
  of gtSwipe:
    result = recognizeSwipe(engine, recognizer, touch)
  of gtPinch:
    result = recognizePinch(engine, recognizer, activeTouches)
  of gtRotate:
    result = recognizeRotate(engine, recognizer, activeTouches)
  of gtPan:
    result = recognizePan(engine, recognizer, activeTouches)
  else:
    result.state = gsFailed

proc recognizeTap(engine: GestureEngine, recognizer: GestureRecognizer, 
                  touch: TouchPoint): Gesture =
  result = Gesture(gestureType: gtTap, state: gsPossible)
  
  let history = engine.touchHistory.getOrDefault(touch.id)
  if history.len < 2:
    return
  
  let firstTouch = history[0]
  let lastTouch = history[^1]
  let duration = lastTouch.timestamp - firstTouch.timestamp
  
  # Calculate total movement
  var totalMovement = 0.0
  for i in 1..<history.len:
    let dx = history[i].x - history[i-1].x
    let dy = history[i].y - history[i-1].y
    totalMovement += sqrt(dx*dx + dy*dy)
  
  if duration < engine.config.tapMaxDuration and 
     totalMovement < recognizer.allowableMovement:
    result.state = gsEnded
    result.location = (x: lastTouch.x, y: lastTouch.y)
    result.confidence = 1.0 - (totalMovement / recognizer.allowableMovement)

proc recognizeSwipe(engine: GestureEngine, recognizer: GestureRecognizer, 
                    touch: TouchPoint): Gesture =
  result = Gesture(gestureType: gtSwipe, state: gsPossible)
  
  let history = engine.touchHistory.getOrDefault(touch.id)
  if history.len < 5:
    return
  
  let firstTouch = history[0]
  let lastTouch = history[^1]
  let duration = lastTouch.timestamp - firstTouch.timestamp
  
  if duration > engine.config.swipeMaxDuration:
    return
  
  let dx = lastTouch.x - firstTouch.x
  let dy = lastTouch.y - firstTouch.y
  let distance = sqrt(dx*dx + dy*dy)
  
  if distance > engine.config.swipeMinDistance:
    result.state = gsEnded
    result.location = (x: lastTouch.x, y: lastTouch.y)
    result.velocity = (vx: dx / duration, vy: dy / duration)
    result.confidence = min(1.0, distance / (engine.config.swipeMinDistance * 2))
    
    # Determine swipe direction
    if abs(dx) > abs(dy):
      result.customData = %*{"direction": if dx > 0: "right" else: "left"}
    else:
      result.customData = %*{"direction": if dy > 0: "down" else: "up"}

proc recognizePinch(engine: GestureEngine, recognizer: GestureRecognizer, 
                    touches: seq[TouchPoint]): Gesture =
  result = Gesture(gestureType: gtPinch, state: gsPossible)
  
  if touches.len != 2:
    return
  
  let touch1 = touches[0]
  let touch2 = touches[1]
  
  # Calculate distance between touches
  let dx = touch2.x - touch1.x
  let dy = touch2.y - touch1.y
  let distance = sqrt(dx*dx + dy*dy)
  
  # Get initial distance from history
  let key = getTouchSequenceKey(touches)
  var sequence = engine.multiTouchSequences.getOrDefault(key)
  
  if sequence.len == 0:
    # Start of pinch
    sequence.add(touch1)
    sequence.add(touch2)
    engine.multiTouchSequences[key] = sequence
    result.state = gsBegan
    result.scale = 1.0
  else:
    # Update pinch
    let firstTouch1 = sequence[0]
    let firstTouch2 = sequence[1]
    let initialDx = firstTouch2.x - firstTouch1.x
    let initialDy = firstTouch2.y - firstTouch1.y
    let initialDistance = sqrt(initialDx*initialDx + initialDy*initialDy)
    
    if initialDistance > 0:
      let scale = distance / initialDistance
      result.scale = scale
      result.state = gsChanged
      
      if abs(scale - 1.0) > engine.config.pinchMinScale:
        result.confidence = min(1.0, abs(scale - 1.0) / engine.config.pinchMinScale)
    
    # Update sequence
    sequence = @[touch1, touch2]
    engine.multiTouchSequences[key] = sequence

proc recognizeWithML(engine: GestureEngine, touch: TouchPoint): seq[Gesture] =
  ## Use machine learning for advanced gesture recognition
  result = @[]
  
  if not engine.mlModel.trained:
    # Simple placeholder - in production, would use actual ML model
    return
  
  # Extract features
  let features = extractFeatures(engine, touch)
  
  # Run inference (placeholder)
  let predictions = runInference(engine.mlModel, features)
  
  for prediction in predictions:
    if prediction.confidence > 0.8:
      result.add(Gesture(
        gestureType: prediction.gestureType,
        state: gsEnded,
        confidence: prediction.confidence,
        timestamp: touch.timestamp,
        customData: prediction.data
      ))

proc trainModel*(engine: GestureEngine, trainingData: seq[tuple[touches: seq[TouchPoint], gesture: GestureType]]) =
  ## Train the ML model on gesture data
  # Feature extraction
  var features: seq[seq[float]]
  var labels: seq[int]
  
  for data in trainingData:
    let featureVec = extractFeaturesFromSequence(engine, data.touches)
    features.add(featureVec)
    labels.add(data.gestureType.ord)
  
  # Train neural network (simplified)
  trainNeuralNetwork(engine.mlModel, features, labels)
  engine.mlModel.trained = true

# Helper functions
proc getActiveTouches(engine: GestureEngine, currentTime: float): seq[TouchPoint] =
  result = @[]
  for id, history in engine.touchHistory:
    if history.len > 0 and currentTime - history[^1].timestamp < 0.5:
      result.add(history[^1])

proc getTouchSequenceKey(touches: seq[TouchPoint]): string =
  let ids = touches.mapIt($it.id).sorted.join("-")
  result = ids

proc extractFeatures(engine: GestureEngine, touch: TouchPoint): seq[float] = @[1.0, 2.0, 3.0]
proc extractFeaturesFromSequence(engine: GestureEngine, touches: seq[TouchPoint]): seq[float] = @[1.0, 2.0, 3.0]
proc runInference(model: MLModel, features: seq[float]): seq[tuple[gestureType: GestureType, confidence: float, data: JsonNode]] = @[]
proc trainNeuralNetwork(model: var MLModel, features: seq[seq[float]], labels: seq[int]) = discard

# Recognizer factories
proc createTapRecognizer(): GestureRecognizer =
  GestureRecognizer(
    name: "Tap",
    gestureType: gtTap,
    minTouches: 1,
    maxTouches: 1,
    maxDuration: 0.3,
    allowableMovement: 10.0
  )

proc createDoubleTapRecognizer(): GestureRecognizer =
  GestureRecognizer(
    name: "Double Tap",
    gestureType: gtDoubleTap,
    minTouches: 1,
    maxTouches: 1,
    maxDuration: 0.3,
    requireTapCount: 2
  )

proc createLongPressRecognizer(): GestureRecognizer =
  GestureRecognizer(
    name: "Long Press",
    gestureType: gtLongPress,
    minTouches: 1,
    maxTouches: 1,
    minDuration: 0.5,
    allowableMovement: 10.0
  )

proc createSwipeRecognizer(): GestureRecognizer =
  GestureRecognizer(
    name: "Swipe",
    gestureType: gtSwipe,
    minTouches: 1,
    maxTouches: 1,
    minMovement: 50.0,
    maxDuration: 0.5
  )

proc createPinchRecognizer(): GestureRecognizer =
  GestureRecognizer(
    name: "Pinch",
    gestureType: gtPinch,
    minTouches: 2,
    maxTouches: 2,
    cancelsTouchesInView: true
  )

proc createRotateRecognizer(): GestureRecognizer =
  GestureRecognizer(
    name: "Rotate",
    gestureType: gtRotate,
    minTouches: 2,
    maxTouches: 2,
    cancelsTouchesInView: true
  )

proc createPanRecognizer(): GestureRecognizer =
  GestureRecognizer(
    name: "Pan",
    gestureType: gtPan,
    minTouches: 1,
    maxTouches: 1
  )

proc createThreeFingerSwipeRecognizer(): GestureRecognizer =
  GestureRecognizer(
    name: "Three Finger Swipe",
    gestureType: gtThreeFingerSwipe,
    minTouches: 3,
    maxTouches: 3,
    minMovement: 50.0,
    maxDuration: 0.5
  )

proc createEdgeSwipeRecognizer(): GestureRecognizer =
  GestureRecognizer(
    name: "Edge Swipe",
    gestureType: gtEdgeSwipe,
    minTouches: 1,
    maxTouches: 1,
    minMovement: 30.0,
    maxDuration: 0.3
  )