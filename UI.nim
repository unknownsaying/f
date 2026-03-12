import std/[asyncdispatch, json, times, tables, strformat, math, random, sequtils]
import wNim, wNim/private/wBitmaps
import core_types, security, wifi_processor, gestures, brain_system

# Type definitions for UI components
type
  HandUI* = ref object of RootObj
    # Main window
    frame: wFrame
    notebook: wNotebook
    
    # Control panels
    dashboardPanel: wPanel
    handsPanel: wPanel
    networkPanel: wPanel
    gesturesPanel: wPanel
    securityPanel: wPanel
    analyticsPanel: wPanel
    settingsPanel: wPanel
    
    # Dashboard components
    handGrid: wListView
    statusBar: wStatusBar
    activityLog: wTextCtrl
    systemMetrics: wPanel
    
    # Hand visualization panels
    handViews: Table[string, HandView]
    selectedHand: string
    
    # Network visualization
    networkGraph: NetworkGraph
    signalMeter: wGauge
    spectrumAnalyzer: SpectrumView
    
    # Gesture visualization
    gestureCanvas: GestureCanvas
    gestureLog: wListBox
    
    # Security status
    securityIndicator: wBitmapButton
    authLog: wListBox
    
    # Analytics
    metricCharts: Table[string, ChartWidget]
    
    # System state
    brain: BrainSystem
    running: bool
    updateTimer: wTimer
    theme: UITheme
    
  HandView = ref object
    panel: wPanel
    deviceIcon: wStaticBitmap
    deviceName: wStaticText
    statusLED: wPanel
    batteryLevel: wGauge
    signalStrength: wGauge
    lastSeen: wStaticText
    touchCanvas: TouchCanvas
    gestureIndicator: wStaticText
    controls: wPanel
    
  TouchCanvas = ref object of wPanel
    touches: seq[TouchPoint]
    gestures: seq[Gesture]
    history: seq[tuple[x, y: int]]
    recording: bool
    
  GestureCanvas = ref object of wPanel
    currentGesture: Gesture
    gesturePath: seq[tuple[x, y: int]]
    recognizedGestures: seq[Gesture]
    
  NetworkGraph = ref object of wPanel
    nodes: seq[NetworkNode]
    connections: seq[NetworkConnection]
    selectedNode: string
    
  NetworkNode = object
    id: string
    deviceType: DeviceType
    position: tuple[x, y: int]
    signalStrength: int
    active: bool
    
  NetworkConnection = object
    source: string
    dest: string
    quality: float
    dataRate: float
    
  SpectrumView = ref object of wPanel
    frequencies: array[14, float]
    activeChannels: seq[int]
    interference: float
    
  ChartWidget = ref object of wPanel
    dataPoints: seq[float]
    chartType: ChartType
    min, max: float
    color: wColour
    
  ChartType = enum
    ctLine, ctBar, ctPie, ctGauge
    
  UITheme = object
    bgColor: wColour
    textColor: wColour
    accentColor: wColour
    successColor: wColour
    warningColor: wColour
    errorColor: wColour
    font: wFont
    titleFont: wFont

# Global instances
var uiInstance: HandUI

# ==================== Main UI Construction ====================

proc newHandUI*(brain: BrainSystem): HandUI =
  ## Create the main Hand-Brain UI
  result = HandUI(
    brain: brain,
    running: true,
    handViews: initTable[string, HandView](),
    theme: UITheme(
      bgColor: wxColour(30, 30, 30),
      textColor: wxWhite,
      accentColor: wxColour(0, 120, 215),
      successColor: wxColour(0, 200, 0),
      warningColor: wxColour(255, 165, 0),
      errorColor: wxColour(255, 0, 0),
      font: wFont(size: 10, family: wxFONTFAMILY_DEFAULT),
      titleFont: wFont(size: 14, family: wxFONTFAMILY_DEFAULT, weight: wxFONTWEIGHT_BOLD)
    )
  )
  
  # Create main frame
  result.frame = wFrame(title="Hand-Brain Control System", size=(1400, 900),
                       style=wxDEFAULT_FRAME_STYLE or wxFULL_REPAINT_ON_RESIZE)
  result.frame.setBackgroundColour(result.theme.bgColor)
  result.frame.center()
  
  # Create notebook for tabs
  result.notebook = wNotebook(result.frame, style=wxNB_TOP)
  result.notebook.setBackgroundColour(result.theme.bgColor)
  
  # Create all panels
  result.createDashboardPanel()
  result.createHandsPanel()
  result.createNetworkPanel()
  result.createGesturesPanel()
  result.createSecurityPanel()
  result.createAnalyticsPanel()
  result.createSettingsPanel()
  
  # Create status bar
  result.statusBar = result.frame.createStatusBar(number=3)
  result.statusBar.setStatusText("System Ready", 0)
  result.statusBar.setStatusText("0 Hands Connected", 1)
  result.statusBar.setStatusText(format(now(), "yyyy-MM-dd HH:mm:ss"), 2)
  
  # Setup update timer (60 FPS)
  result.updateTimer = wTimer(result.frame, id=wxID_ANY)
  result.updateTimer.start(16)  # ~60 FPS
  
  # Bind events
  wConnect(result.updateTimer, wEvent_Timer, result.onUpdate)
  wConnect(result.frame, wEvent_Close, result.onClose)
  
  uiInstance = result

proc createDashboardPanel*(ui: HandUI) =
  ## Create the main dashboard overview
  ui.dashboardPanel = wPanel(ui.notebook, style=wxTAB_TRAVERSAL)
  ui.dashboardPanel.setBackgroundColour(ui.theme.bgColor)
  ui.notebook.addPage(ui.dashboardPanel, "Dashboard")
  
  # Create main sizer
  let mainSizer = wBoxSizer(wxVERTICAL)
  
  # Top metrics bar
  let metricsBar = wPanel(ui.dashboardPanel, style=wxBORDER_NONE)
  metricsBar.setBackgroundColour(ui.theme.bgColor)
  let metricsSizer = wBoxSizer(wxHORIZONTAL)
  
  # Metric cards
  metricsSizer.add(createMetricCard(metricsBar, "Connected Hands", "0", 
                                    ui.theme.accentColor), 1, wxALL, 5)
  metricsSizer.add(createMetricCard(metricsBar, "Active Gestures", "0", 
                                    ui.theme.successColor), 1, wxALL, 5)
  metricsSizer.add(createMetricCard(metricsBar, "Network Load", "0%", 
                                    ui.theme.warningColor), 1, wxALL, 5)
  metricsSizer.add(createMetricCard(metricsBar, "Security Status", "Secure", 
                                    ui.theme.successColor), 1, wxALL, 5)
  
  metricsBar.setSizer(metricsSizer)
  mainSizer.add(metricsBar, 0, wxEXPAND or wxALL, 5)
  
  # Split view for hands and activity
  let splitSizer = wBoxSizer(wxHORIZONTAL)
  
  # Left side - Hand grid
  let leftPanel = wPanel(ui.dashboardPanel)
  leftPanel.setBackgroundColour(ui.theme.bgColor)
  let leftSizer = wBoxSizer(wxVERTICAL)
  
  let handLabel = wStaticText(leftPanel, label="Connected Hands", 
                             style=wxALIGN_CENTER)
  handLabel.setFont(ui.theme.titleFont)
  handLabel.setForegroundColour(ui.theme.textColor)
  leftSizer.add(handLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  ui.handGrid = wListView(leftPanel, style=wxLC_REPORT or wxLC_SINGLE_SEL)
  ui.handGrid.setBackgroundColour(wxColour(45, 45, 45))
  ui.handGrid.setForegroundColour(ui.theme.textColor)
  ui.handGrid.appendColumn("Device", width=120)
  ui.handGrid.appendColumn("Type", width=100)
  ui.handGrid.appendColumn("Status", width=80)
  ui.handGrid.appendColumn("Battery", width=80)
  ui.handGrid.appendColumn("Signal", width=80)
  ui.handGrid.appendColumn("Last Seen", width=150)
  leftSizer.add(ui.handGrid, 1, wxEXPAND or wxALL, 5)
  
  # Hand controls
  let controlPanel = wPanel(leftPanel)
  controlPanel.setBackgroundColour(ui.theme.bgColor)
  let controlSizer = wBoxSizer(wxHORIZONTAL)
  
  let btnSelectAll = wButton(controlPanel, label="Select All")
  let btnBroadcast = wButton(controlPanel, label="Broadcast")
  let btnDisconnect = wButton(controlPanel, label="Disconnect")
  
  controlSizer.add(btnSelectAll, 1, wxALL, 2)
  controlSizer.add(btnBroadcast, 1, wxALL, 2)
  controlSizer.add(btnDisconnect, 1, wxALL, 2)
  
  controlPanel.setSizer(controlSizer)
  leftSizer.add(controlPanel, 0, wxEXPAND or wxALL, 5)
  
  leftPanel.setSizer(leftSizer)
  splitSizer.add(leftPanel, 1, wxEXPAND or wxALL, 5)
  
  # Right side - Activity log and system metrics
  let rightPanel = wPanel(ui.dashboardPanel)
  rightPanel.setBackgroundColour(ui.theme.bgColor)
  let rightSizer = wBoxSizer(wxVERTICAL)
  
  # Activity log
  let logLabel = wStaticText(rightPanel, label="System Activity", 
                            style=wxALIGN_CENTER)
  logLabel.setFont(ui.theme.titleFont)
  logLabel.setForegroundColour(ui.theme.textColor)
  rightSizer.add(logLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  ui.activityLog = wTextCtrl(rightPanel, style=wxTE_MULTILINE or wxTE_READONLY or 
                             wxTE_RICH2, size=(400, 300))
  ui.activityLog.setBackgroundColour(wxColour(45, 45, 45))
  ui.activityLog.setForegroundColour(ui.theme.textColor)
  ui.activityLog.setFont(ui.theme.font)
  rightSizer.add(ui.activityLog, 2, wxEXPAND or wxALL, 5)
  
  # System metrics
  let metricsLabel = wStaticText(rightPanel, label="System Metrics", 
                                style=wxALIGN_CENTER)
  metricsLabel.setFont(ui.theme.titleFont)
  metricsLabel.setForegroundColour(ui.theme.textColor)
  rightSizer.add(metricsLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  ui.systemMetrics = wPanel(rightPanel)
  ui.systemMetrics.setBackgroundColour(wxColour(45, 45, 45))
  ui.systemMetrics.setMinSize((400, 200))
  
  let metricsGrid = wFlexGridSizer(cols=2, vgap=5, hgap=5)
  metricsGrid.addGrowableCol(1)
  
  # Add system metrics
  metricsGrid.add(wStaticText(ui.systemMetrics, label="CPU Usage:"))
  metricsGrid.add(createProgressBar(ui.systemMetrics, 45))
  
  metricsGrid.add(wStaticText(ui.systemMetrics, label="Memory:"))
  metricsGrid.add(createProgressBar(ui.systemMetrics, 62))
  
  metricsGrid.add(wStaticText(ui.systemMetrics, label="Network:"))
  metricsGrid.add(createProgressBar(ui.systemMetrics, 28))
  
  metricsGrid.add(wStaticText(ui.systemMetrics, label="Storage:"))
  metricsGrid.add(createProgressBar(ui.systemMetrics, 34))
  
  ui.systemMetrics.setSizer(metricsGrid)
  rightSizer.add(ui.systemMetrics, 1, wxEXPAND or wxALL, 5)
  
  rightPanel.setSizer(rightSizer)
  splitSizer.add(rightPanel, 1, wxEXPAND or wxALL, 5)
  
  mainSizer.add(splitSizer, 1, wxEXPAND or wxALL, 5)
  
  ui.dashboardPanel.setSizer(mainSizer)

proc createHandsPanel*(ui: HandUI) =
  ## Create the hands management panel
  ui.handsPanel = wPanel(ui.notebook, style=wxTAB_TRAVERSAL)
  ui.handsPanel.setBackgroundColour(ui.theme.bgColor)
  ui.notebook.addPage(ui.handsPanel, "Hands")
  
  let mainSizer = wBoxSizer(wxHORIZONTAL)
  
  # Left side - Hand list
  let listPanel = wPanel(ui.handsPanel)
  listPanel.setBackgroundColour(ui.theme.bgColor)
  listPanel.setMinSize((250, -1))
  let listSizer = wBoxSizer(wxVERTICAL)
  
  let searchCtrl = wSearchCtrl(listPanel, style=wxTE_PROCESS_ENTER)
  searchCtrl.setDescriptiveText("Search hands...")
  searchCtrl.setMinSize((230, 25))
  listSizer.add(searchCtrl, 0, wxEXPAND or wxALL, 5)
  
  let handList = wListBox(listPanel, style=wxLB_SINGLE)
  handList.setBackgroundColour(wxColour(45, 45, 45))
  handList.setForegroundColour(ui.theme.textColor)
  listSizer.add(handList, 1, wxEXPAND or wxALL, 5)
  
  # Hand type filters
  let filterPanel = wPanel(listPanel)
  filterPanel.setBackgroundColour(ui.theme.bgColor)
  let filterSizer = wBoxSizer(wxVERTICAL)
  
  filterSizer.add(wStaticText(filterPanel, label="Filter by type:"))
  
  let chkSmartphone = wCheckBox(filterPanel, label="Smartphones")
  let chkTablet = wCheckBox(filterPanel, label="Tablets")
  let chkLaptop = wCheckBox(filterPanel, label="Laptops")
  let chkWatch = wCheckBox(filterPanel, label="Smartwatches")
  
  filterSizer.add(chkSmartphone, 0, wxALL, 2)
  filterSizer.add(chkTablet, 0, wxALL, 2)
  filterSizer.add(chkLaptop, 0, wxALL, 2)
  filterSizer.add(chkWatch, 0, wxALL, 2)
  
  filterPanel.setSizer(filterSizer)
  listSizer.add(filterPanel, 0, wxEXPAND or wxALL, 5)
  
  listPanel.setSizer(listSizer)
  mainSizer.add(listPanel, 0, wxEXPAND or wxALL, 5)
  
  # Right side - Hand detail view with tabs
  let detailNotebook = wNotebook(ui.handsPanel, style=wxNB_TOP)
  detailNotebook.setBackgroundColour(ui.theme.bgColor)
  
  # Create detail panels for different aspects
  createHandInfoPanel(detailNotebook, ui)
  createHandControlPanel(detailNotebook, ui)
  createHandDataPanel(detailNotebook, ui)
  createHandGesturePanel(detailNotebook, ui)
  
  mainSizer.add(detailNotebook, 1, wxEXPAND or wxALL, 5)
  
  ui.handsPanel.setSizer(mainSizer)

proc createNetworkPanel*(ui: HandUI) =
  ## Create the network visualization panel
  ui.networkPanel = wPanel(ui.notebook, style=wxTAB_TRAVERSAL)
  ui.networkPanel.setBackgroundColour(ui.theme.bgColor)
  ui.notebook.addPage(ui.networkPanel, "Network")
  
  let mainSizer = wBoxSizer(wxVERTICAL)
  
  # Top controls
  let topPanel = wPanel(ui.networkPanel)
  topPanel.setBackgroundColour(ui.theme.bgColor)
  let topSizer = wBoxSizer(wxHORIZONTAL)
  
  let btnScan = wButton(topPanel, label="Scan Networks")
  let btnAnalyze = wButton(topPanel, label="Analyze")
  let btnOptimize = wButton(topPanel, label="Optimize Channels")
  let spinctrl = wSpinCtrl(topPanel, value="1", min=1, max=14)
  
  topSizer.add(btnScan, 0, wxALL, 5)
  topSizer.add(btnAnalyze, 0, wxALL, 5)
  topSizer.add(btnOptimize, 0, wxALL, 5)
  topSizer.addStretchSpacer()
  topSizer.add(wStaticText(topPanel, label="Channel:"), 0, wxALIGN_CENTER or wxALL, 5)
  topSizer.add(spinctrl, 0, wxALL, 5)
  
  topPanel.setSizer(topSizer)
  mainSizer.add(topPanel, 0, wxEXPAND or wxALL, 5)
  
  # Main content split
  let contentSizer = wBoxSizer(wxHORIZONTAL)
  
  # Left side - Network graph
  let graphPanel = wPanel(ui.networkPanel)
  graphPanel.setBackgroundColour(wxColour(45, 45, 45))
  graphPanel.setMinSize((600, 400))
  let graphSizer = wBoxSizer(wxVERTICAL)
  
  let graphLabel = wStaticText(graphPanel, label="Network Topology", 
                              style=wxALIGN_CENTER)
  graphLabel.setFont(ui.theme.titleFont)
  graphLabel.setForegroundColour(ui.theme.textColor)
  graphSizer.add(graphLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  ui.networkGraph = NetworkGraph(graphPanel)
  ui.networkGraph.setBackgroundColour(wxColour(30, 30, 30))
  ui.networkGraph.setMinSize((580, 350))
  graphSizer.add(ui.networkGraph, 1, wxEXPAND or wxALL, 5)
  
  graphPanel.setSizer(graphSizer)
  contentSizer.add(graphPanel, 2, wxEXPAND or wxALL, 5)
  
  # Right side - Signal analysis
  let analysisPanel = wPanel(ui.networkPanel)
  analysisPanel.setBackgroundColour(ui.theme.bgColor)
  analysisPanel.setMinSize((400, -1))
  let analysisSizer = wBoxSizer(wxVERTICAL)
  
  # Spectrum analyzer
  let spectrumLabel = wStaticText(analysisPanel, label="Spectrum Analyzer", 
                                  style=wxALIGN_CENTER)
  spectrumLabel.setFont(ui.theme.titleFont)
  spectrumLabel.setForegroundColour(ui.theme.textColor)
  analysisSizer.add(spectrumLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  ui.spectrumAnalyzer = SpectrumView(analysisPanel)
  ui.spectrumAnalyzer.setBackgroundColour(wxColour(45, 45, 45))
  ui.spectrumAnalyzer.setMinSize((380, 200))
  analysisSizer.add(ui.spectrumAnalyzer, 1, wxEXPAND or wxALL, 5)
  
  # Signal meter
  let meterLabel = wStaticText(analysisPanel, label="Signal Strength", 
                               style=wxALIGN_CENTER)
  meterLabel.setFont(ui.theme.titleFont)
  meterLabel.setForegroundColour(ui.theme.textColor)
  analysisSizer.add(meterLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  ui.signalMeter = wGauge(analysisPanel, range=100, style=wxGA_HORIZONTAL)
  ui.signalMeter.setMinSize((380, 30))
  ui.signalMeter.setBackgroundColour(wxColour(45, 45, 45))
  ui.signalMeter.setForegroundColour(ui.theme.accentColor)
  ui.signalMeter.setValue(75)
  analysisSizer.add(ui.signalMeter, 0, wxEXPAND or wxALL, 5)
  
  # Network stats
  let statsPanel = wPanel(analysisPanel)
  statsPanel.setBackgroundColour(wxColour(45, 45, 45))
  statsPanel.setMinSize((380, 150))
  let statsGrid = wFlexGridSizer(cols=2, vgap=5, hgap=10)
  statsGrid.addGrowableCol(1)
  
  statsGrid.add(wStaticText(statsPanel, label="Connected Devices:"))
  statsGrid.add(wStaticText(statsPanel, label="5"))
  
  statsGrid.add(wStaticText(statsPanel, label="Networks Found:"))
  statsGrid.add(wStaticText(statsPanel, label="8"))
  
  statsGrid.add(wStaticText(statsPanel, label="Avg. Signal:"))
  statsGrid.add(wStaticText(statsPanel, label="-62 dBm"))
  
  statsGrid.add(wStaticText(statsPanel, label="Interference:"))
  statsGrid.add(wStaticText(statsPanel, label="Low"))
  
  statsGrid.add(wStaticText(statsPanel, label="Channel Load:"))
  statsGrid.add(createProgressBar(statsPanel, 45))
  
  statsPanel.setSizer(statsGrid)
  analysisSizer.add(statsPanel, 0, wxEXPAND or wxALL, 5)
  
  analysisPanel.setSizer(analysisSizer)
  contentSizer.add(analysisPanel, 1, wxEXPAND or wxALL, 5)
  
  mainSizer.add(contentSizer, 1, wxEXPAND or wxALL, 5)
  
  ui.networkPanel.setSizer(mainSizer)

proc createGesturesPanel*(ui: HandUI) =
  ## Create the gesture recognition panel
  ui.gesturesPanel = wPanel(ui.notebook, style=wxTAB_TRAVERSAL)
  ui.gesturesPanel.setBackgroundColour(ui.theme.bgColor)
  ui.notebook.addPage(ui.gesturesPanel, "Gestures")
  
  let mainSizer = wBoxSizer(wxVERTICAL)
  
  # Top controls
  let topPanel = wPanel(ui.gesturesPanel)
  topPanel.setBackgroundColour(ui.theme.bgColor)
  let topSizer = wBoxSizer(wxHORIZONTAL)
  
  let btnTrain = wButton(topPanel, label="Train Model")
  let btnTest = wButton(topPanel, label="Test Gesture")
  let btnClear = wButton(topPanel, label="Clear")
  let chkRecord = wCheckBox(topPanel, label="Record")
  
  topSizer.add(btnTrain, 0, wxALL, 5)
  topSizer.add(btnTest, 0, wxALL, 5)
  topSizer.add(btnClear, 0, wxALL, 5)
  topSizer.addStretchSpacer()
  topSizer.add(chkRecord, 0, wxALIGN_CENTER or wxALL, 5)
  
  topPanel.setSizer(topSizer)
  mainSizer.add(topPanel, 0, wxEXPAND or wxALL, 5)
  
  # Main content split
  let contentSizer = wBoxSizer(wxHORIZONTAL)
  
  # Left side - Gesture canvas
  let canvasPanel = wPanel(ui.gesturesPanel)
  canvasPanel.setBackgroundColour(wxColour(45, 45, 45))
  canvasPanel.setMinSize((600, 400))
  let canvasSizer = wBoxSizer(wxVERTICAL)
  
  let canvasLabel = wStaticText(canvasPanel, label="Gesture Input", 
                                style=wxALIGN_CENTER)
  canvasLabel.setFont(ui.theme.titleFont)
  canvasLabel.setForegroundColour(ui.theme.textColor)
  canvasSizer.add(canvasLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  ui.gestureCanvas = GestureCanvas(canvasPanel)
  ui.gestureCanvas.setBackgroundColour(wxBLACK)
  ui.gestureCanvas.setMinSize((580, 350))
  ui.gestureCanvas.setForegroundColour(wxWHITE)
  canvasSizer.add(ui.gestureCanvas, 1, wxEXPAND or wxALL, 5)
  
  canvasPanel.setSizer(canvasSizer)
  contentSizer.add(canvasPanel, 2, wxEXPAND or wxALL, 5)
  
  # Right side - Gesture info
  let infoPanel = wPanel(ui.gesturesPanel)
  infoPanel.setBackgroundColour(ui.theme.bgColor)
  infoPanel.setMinSize((400, -1))
  let infoSizer = wBoxSizer(wxVERTICAL)
  
  # Recognized gestures
  let recogLabel = wStaticText(infoPanel, label="Recognized Gestures", 
                               style=wxALIGN_CENTER)
  recogLabel.setFont(ui.theme.titleFont)
  recogLabel.setForegroundColour(ui.theme.textColor)
  infoSizer.add(recogLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  ui.gestureLog = wListBox(infoPanel, style=wxLB_SINGLE)
  ui.gestureLog.setBackgroundColour(wxColour(45, 45, 45))
  ui.gestureLog.setForegroundColour(ui.theme.textColor)
  ui.gestureLog.setMinSize((380, 200))
  infoSizer.add(ui.gestureLog, 1, wxEXPAND or wxALL, 5)
  
  # Gesture stats
  let statsPanel = wPanel(infoPanel)
  statsPanel.setBackgroundColour(wxColour(45, 45, 45))
  statsPanel.setMinSize((380, 150))
  let statsGrid = wFlexGridSizer(cols=2, vgap=5, hgap=10)
  statsGrid.addGrowableCol(1)
  
  statsGrid.add(wStaticText(statsPanel, label="Total Gestures:"))
  statsGrid.add(wStaticText(statsPanel, label="127"))
  
  statsGrid.add(wStaticText(statsPanel, label="Accuracy:"))
  statsGrid.add(createProgressBar(statsPanel, 94))
  
  statsGrid.add(wStaticText(statsPanel, label="Most Common:"))
  statsGrid.add(wStaticText(statsPanel, label="Swipe"))
  
  statsGrid.add(wStaticText(statsPanel, label="Model Status:"))
  statsGrid.add(wStaticText(statsPanel, label="Trained (v2.3)"))
  
  statsPanel.setSizer(statsGrid)
  infoSizer.add(statsPanel, 0, wxEXPAND or wxALL, 5)
  
  # Gesture library
  let libLabel = wStaticText(infoPanel, label="Gesture Library", 
                             style=wxALIGN_CENTER)
  libLabel.setFont(ui.theme.titleFont)
  libLabel.setForegroundColour(ui.theme.textColor)
  infoSizer.add(libLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  let gestureLib = wListCtrl(infoPanel, style=wxLC_REPORT)
  gestureLib.setBackgroundColour(wxColour(45, 45, 45))
  gestureLib.setForegroundColour(ui.theme.textColor)
  gestureLib.appendColumn("Gesture", width=150)
  gestureLib.appendColumn("Confidence", width=100)
  gestureLib.appendColumn("Count", width=80)
  infoSizer.add(gestureLib, 1, wxEXPAND or wxALL, 5)
  
  infoPanel.setSizer(infoSizer)
  contentSizer.add(infoPanel, 1, wxEXPAND or wxALL, 5)
  
  mainSizer.add(contentSizer, 1, wxEXPAND or wxALL, 5)
  
  ui.gesturesPanel.setSizer(mainSizer)

proc createSecurityPanel*(ui: HandUI) =
  ## Create the security monitoring panel
  ui.securityPanel = wPanel(ui.notebook, style=wxTAB_TRAVERSAL)
  ui.securityPanel.setBackgroundColour(ui.theme.bgColor)
  ui.notebook.addPage(ui.securityPanel, "Security")
  
  let mainSizer = wBoxSizer(wxVERTICAL)
  
  # Top status bar
  let statusPanel = wPanel(ui.securityPanel)
  statusPanel.setBackgroundColour(wxColour(45, 45, 45))
  statusPanel.setMinSize((-1, 60))
  let statusSizer = wBoxSizer(wxHORIZONTAL)
  
  ui.securityIndicator = wBitmapButton(statusPanel, 
    bitmap=createColourBitmap(20, 20, ui.theme.successColor))
  statusSizer.add(ui.securityIndicator, 0, wxALIGN_CENTER or wxALL, 10)
  
  let statusText = wStaticText(statusPanel, label="System Security: ACTIVE - All systems secure")
  statusText.setFont(ui.theme.titleFont)
  statusText.setForegroundColour(ui.theme.successColor)
  statusSizer.add(statusText, 1, wxALIGN_CENTER or wxALL, 5)
  
  statusPanel.setSizer(statusSizer)
  mainSizer.add(statusPanel, 0, wxEXPAND or wxALL, 5)
  
  # Main content
  let contentSizer = wBoxSizer(wxHORIZONTAL)
  
  # Left side - Security events
  let eventsPanel = wPanel(ui.securityPanel)
  eventsPanel.setBackgroundColour(ui.theme.bgColor)
  let eventsSizer = wBoxSizer(wxVERTICAL)
  
  let eventsLabel = wStaticText(eventsPanel, label="Security Events", 
                                style=wxALIGN_CENTER)
  eventsLabel.setFont(ui.theme.titleFont)
  eventsLabel.setForegroundColour(ui.theme.textColor)
  eventsSizer.add(eventsLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  let eventList = wListCtrl(eventsPanel, style=wxLC_REPORT)
  eventList.setBackgroundColour(wxColour(45, 45, 45))
  eventList.setForegroundColour(ui.theme.textColor)
  eventList.appendColumn("Time", width=150)
  eventList.appendColumn("Event", width=250)
  eventList.appendColumn("Severity", width=100)
  eventList.appendColumn("Status", width=100)
  eventsSizer.add(eventList, 1, wxEXPAND or wxALL, 5)
  
  eventsPanel.setSizer(eventsSizer)
  contentSizer.add(eventsPanel, 2, wxEXPAND or wxALL, 5)
  
  # Right side - Security controls
  let controlsPanel = wPanel(ui.securityPanel)
  controlsPanel.setBackgroundColour(ui.theme.bgColor)
  controlsPanel.setMinSize((350, -1))
  let controlsSizer = wBoxSizer(wxVERTICAL)
  
  # Authentication log
  let authLabel = wStaticText(controlsPanel, label="Authentication Log", 
                              style=wxALIGN_CENTER)
  authLabel.setFont(ui.theme.titleFont)
  authLabel.setForegroundColour(ui.theme.textColor)
  controlsSizer.add(authLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  ui.authLog = wListBox(controlsPanel, style=wxLB_SINGLE)
  ui.authLog.setBackgroundColour(wxColour(45, 45, 45))
  ui.authLog.setForegroundColour(ui.theme.textColor)
  ui.authLog.setMinSize((330, 200))
  controlsSizer.add(ui.authLog, 1, wxEXPAND or wxALL, 5)
  
  # Security settings
  let settingsLabel = wStaticText(controlsPanel, label="Security Settings", 
                                  style=wxALIGN_CENTER)
  settingsLabel.setFont(ui.theme.titleFont)
  settingsLabel.setForegroundColour(ui.theme.textColor)
  controlsSizer.add(settingsLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  let settingsPanel = wPanel(controlsPanel)
  settingsPanel.setBackgroundColour(wxColour(45, 45, 45))
  settingsPanel.setMinSize((330, 200))
  let settingsGrid = wFlexGridSizer(cols=2, vgap=10, hgap=10)
  settingsGrid.addGrowableCol(1)
  
  settingsGrid.add(wStaticText(settingsPanel, label="Encryption:"))
  settingsGrid.add(wChoice(settingsPanel, choices=@["AES-256", "AES-128", "None"]))
  
  settingsGrid.add(wStaticText(settingsPanel, label="Auth Method:"))
  settingsGrid.add(wChoice(settingsPanel, choices=@["2FA", "Biometric", "Password"]))
  
  settingsGrid.add(wStaticText(settingsPanel, label="Session Timeout:"))
  settingsGrid.add(wSpinCtrl(settingsPanel, value="3600", min=60, max=86400))
  
  settingsGrid.add(wStaticText(settingsPanel, label="Max Attempts:"))
  settingsGrid.add(wSpinCtrl(settingsPanel, value="5", min=1, max=10))
  
  settingsPanel.setSizer(settingsGrid)
  controlsSizer.add(settingsPanel, 0, wxEXPAND or wxALL, 5)
  
  # Action buttons
  let btnPanel = wPanel(controlsPanel)
  btnPanel.setBackgroundColour(ui.theme.bgColor)
  let btnSizer = wBoxSizer(wxVERTICAL)
  
  let btnLockdown = wButton(btnPanel, label="Lockdown System")
  let btnReset = wButton(btnPanel, label="Reset Security")
  let btnAudit = wButton(btnPanel, label="Run Audit")
  
  btnSizer.add(btnLockdown, 0, wxEXPAND or wxALL, 2)
  btnSizer.add(btnReset, 0, wxEXPAND or wxALL, 2)
  btnSizer.add(btnAudit, 0, wxEXPAND or wxALL, 2)
  
  btnPanel.setSizer(btnSizer)
  controlsSizer.add(btnPanel, 0, wxEXPAND or wxALL, 5)
  
  controlsPanel.setSizer(controlsSizer)
  contentSizer.add(controlsPanel, 1, wxEXPAND or wxALL, 5)
  
  mainSizer.add(contentSizer, 1, wxEXPAND or wxALL, 5)
  
  ui.securityPanel.setSizer(mainSizer)

proc createAnalyticsPanel*(ui: HandUI) =
  ## Create the analytics and reporting panel
  ui.analyticsPanel = wPanel(ui.notebook, style=wxTAB_TRAVERSAL)
  ui.analyticsPanel.setBackgroundColour(ui.theme.bgColor)
  ui.notebook.addPage(ui.analyticsPanel, "Analytics")
  
  let mainSizer = wBoxSizer(wxVERTICAL)
  
  # Time range selector
  let topPanel = wPanel(ui.analyticsPanel)
  topPanel.setBackgroundColour(ui.theme.bgColor)
  let topSizer = wBoxSizer(wxHORIZONTAL)
  
  topSizer.add(wStaticText(topPanel, label="Time Range:"), 0, wxALIGN_CENTER or wxALL, 5)
  topSizer.add(wChoice(topPanel, choices=@["Last Hour", "Last 24 Hours", "Last Week", "Last Month", "Custom"]), 0, wxALL, 5)
  topSizer.addStretchSpacer()
  topSizer.add(wButton(topPanel, label="Export Report"), 0, wxALL, 5)
  topSizer.add(wButton(topPanel, label="Refresh"), 0, wxALL, 5)
  
  topPanel.setSizer(topSizer)
  mainSizer.add(topPanel, 0, wxEXPAND or wxALL, 5)
  
  # Charts grid
  let chartsGrid = wFlexGridSizer(cols=2, vgap=10, hgap=10)
  chartsGrid.addGrowableCol(0, 1)
  chartsGrid.addGrowableCol(1, 1)
  chartsGrid.addGrowableRow(0, 1)
  chartsGrid.addGrowableRow(1, 1)
  
  # Connection chart
  let connChart = createChart(ui.analyticsPanel, "Connections Over Time", ctLine)
  connChart.setMinSize((450, 250))
  chartsGrid.add(connChart, 0, wxEXPAND or wxALL, 5)
  
  # Gesture chart
  let gestureChart = createChart(ui.analyticsPanel, "Gesture Types", ctPie)
  gestureChart.setMinSize((450, 250))
  chartsGrid.add(gestureChart, 0, wxEXPAND or wxALL, 5)
  
  # Network chart
  let netChart = createChart(ui.analyticsPanel, "Network Load", ctBar)
  netChart.setMinSize((450, 250))
  chartsGrid.add(netChart, 0, wxEXPAND or wxALL, 5)
  
  # Security chart
  let secChart = createChart(ui.analyticsPanel, "Security Events", ctLine)
  secChart.setMinSize((450, 250))
  chartsGrid.add(secChart, 0, wxEXPAND or wxALL, 5)
  
  mainSizer.add(chartsGrid, 1, wxEXPAND or wxALL, 5)
  
  ui.analyticsPanel.setSizer(mainSizer)

proc createSettingsPanel*(ui: HandUI) =
  ## Create the system settings panel
  ui.settingsPanel = wPanel(ui.notebook, style=wxTAB_TRAVERSAL)
  ui.settingsPanel.setBackgroundColour(ui.theme.bgColor)
  ui.notebook.addPage(ui.settingsPanel, "Settings")
  
  let mainSizer = wBoxSizer(wxHORIZONTAL)
  
  # Settings categories
  let catPanel = wPanel(ui.settingsPanel)
  catPanel.setBackgroundColour(wxColour(45, 45, 45))
  catPanel.setMinSize((200, -1))
  let catSizer = wBoxSizer(wxVERTICAL)
  
  catSizer.add(wStaticText(catPanel, label="Categories", 
              style=wxALIGN_CENTER), 0, wxALL, 5)
  
  let catList = wListBox(catPanel, choices=@["General", "Network", "Security", 
                        "Gestures", "Display", "Notifications", "Advanced"])
  catList.setBackgroundColour(wxColour(60, 60, 60))
  catSizer.add(catList, 1, wxEXPAND or wxALL, 5)
  
  catPanel.setSizer(catSizer)
  mainSizer.add(catPanel, 0, wxEXPAND or wxALL, 5)
  
  # Settings form
  let formPanel = wPanel(ui.settingsPanel)
  formPanel.setBackgroundColour(ui.theme.bgColor)
  let formSizer = wBoxSizer(wxVERTICAL)
  
  let formLabel = wStaticText(formPanel, label="General Settings", 
                             style=wxALIGN_CENTER)
  formLabel.setFont(ui.theme.titleFont)
  formSizer.add(formLabel, 0, wxALIGN_CENTER or wxALL, 5)
  
  let settingsGrid = wFlexGridSizer(cols=2, vgap=10, hgap=20)
  settingsGrid.addGrowableCol(1)
  
  # General settings
  settingsGrid.add(wStaticText(formPanel, label="System Name:"))
  settingsGrid.add(wTextCtrl(formPanel, value="Hand-Brain System", 
                 style=wxTE_PROCESS_ENTER))
  
  settingsGrid.add(wStaticText(formPanel, label="Auto-start:"))
  let chkAuto = wCheckBox(formPanel, label="")
  chkAuto.setValue(true)
  settingsGrid.add(chkAuto)
  
  settingsGrid.add(wStaticText(formPanel, label="Update Interval:"))
  settingsGrid.add(wSpinCtrl(formPanel, value="100", min=10, max=1000))
  
  settingsGrid.add(wStaticText(formPanel, label="Theme:"))
  settingsGrid.add(wChoice(formPanel, choices=@["Dark", "Light", "System"]))
  
  settingsGrid.add(wStaticText(formPanel, label="Language:"))
  settingsGrid.add(wChoice(formPanel, choices=@["English", "Spanish", "Chinese", "Japanese"]))
  
  formSizer.add(settingsGrid, 1, wxEXPAND or wxALL, 20)
  
  # Action buttons
  let btnPanel = wPanel(formPanel)
  btnPanel.setBackgroundColour(ui.theme.bgColor)
  let btnSizer = wBoxSizer(wxHORIZONTAL)
  
  btnSizer.addStretchSpacer()
  btnSizer.add(wButton(btnPanel, label="Save"), 0, wxALL, 5)
  btnSizer.add(wButton(btnPanel, label="Apply"), 0, wxALL, 5)
  btnSizer.add(wButton(btnPanel, label="Cancel"), 0, wxALL, 5)
  btnSizer.addStretchSpacer()
  
  btnPanel.setSizer(btnSizer)
  formSizer.add(btnPanel, 0, wxEXPAND or wxALL, 5)
  
  formPanel.setSizer(formSizer)
  mainSizer.add(formPanel, 1, wxEXPAND or wxALL, 5)
  
  ui.settingsPanel.setSizer(mainSizer)

# ==================== Helper Components ====================

proc createMetricCard(parent: wWindow, label, value: string, 
                      color: wColour): wPanel =
  ## Create a metric card for dashboard
  result = wPanel(parent, style=wxBORDER_RAISED)
  result.setBackgroundColour(wxColour(45, 45, 45))
  result.setMinSize((200, 80))
  
  let sizer = wBoxSizer(wxVERTICAL)
  
  let labelCtrl = wStaticText(result, label=label, style=wxALIGN_CENTER)
  labelCtrl.setForegroundColour(wxWHITE)
  sizer.add(labelCtrl, 1, wxALIGN_CENTER or wxALL, 5)
  
  let valueCtrl = wStaticText(result, label=value, style=wxALIGN_CENTER)
  valueCtrl.setFont(wFont(size=24, weight=wxFONTWEIGHT_BOLD))
  valueCtrl.setForegroundColour(color)
  sizer.add(valueCtrl, 1, wxALIGN_CENTER or wxALL, 5)
  
  result.setSizer(sizer)

proc createProgressBar(parent: wWindow, value: int): wGauge =
  ## Create a styled progress bar
  result = wGauge(parent, range=100, style=wxGA_HORIZONTAL)
  result.setMinSize((150, 20))
  result.setValue(value)
  result.setBackgroundColour(wxColour(60, 60, 60))
  result.setForegroundColour(uiInstance.theme.accentColor)

proc createChart(parent: wWindow, title: string, chartType: ChartType): ChartWidget =
  ## Create a chart widget
  result = ChartWidget(parent)
  result.setBackgroundColour(wxColour(45, 45, 45))
  result.chartType = chartType
  result.color = uiInstance.theme.accentColor
  
  let sizer = wBoxSizer(wxVERTICAL)
  
  let titleCtrl = wStaticText(result, label=title, style=wxALIGN_CENTER)
  titleCtrl.setForegroundColour(wxWHITE)
  sizer.add(titleCtrl, 0, wxALIGN_CENTER or wxALL, 5)
  
  # Generate sample data
  result.dataPoints = @[]
  for i in 0..<20:
    result.dataPoints.add(rand(100).float)
  
  result.setSizer(sizer)

proc createColourBitmap(width, height: int, color: wColour): wBitmap =
  ## Create a bitmap with solid color
  result = wBitmap(width, height)
  let dc = wMemoryDC(result)
  dc.setBackground(wBrush(color))
  dc.clear()

# ==================== Event Handlers ====================

proc onUpdate*(ui: HandUI, event: wEvent) =
  ## Timer update handler - refresh UI
  # Update status bar time
  ui.statusBar.setStatusText(format(now(), "yyyy-MM-dd HH:mm:ss"), 2)
  
  # Update hand count
  ui.statusBar.setStatusText(&"{ui.brain.connectedHands.len} Hands Connected", 1)
  
  # Update hand grid
  ui.refreshHandGrid()
  
  # Update network graph
  if ui.networkGraph != nil:
    ui.networkGraph.refresh()
  
  # Update spectrum analyzer
  if ui.spectrumAnalyzer != nil:
    ui.spectrumAnalyzer.refresh()
  
  # Update gesture canvas
  if ui.gestureCanvas != nil:
    ui.gestureCanvas.refresh()

proc onClose*(ui: HandUI, event: wEvent) =
  ## Window close handler
  ui.running = false
  ui.updateTimer.stop()
  event.skip()

proc refreshHandGrid*(ui: HandUI) =
  ## Refresh the hand grid display
  if ui.handGrid == nil: return
  
  ui.handGrid.deleteAllItems()
  
  for sessionId, hand in ui.brain.connectedHands:
    let index = ui.handGrid.insertItem(ui.handGrid.getItemCount(), 
                                       hand.session.deviceId)
    ui.handGrid.setItem(index, 1, $hand.deviceType)
    ui.handGrid.setItem(index, 2, "Connected")
    ui.handGrid.setItem(index, 3, "95%")
    ui.handGrid.setItem(index, 4, "-45 dBm")
    ui.handGrid.setItem(index, 5, format(hand.lastSeen.fromUnix, "HH:mm:ss"))

# ==================== Custom Widget Drawing ====================

method onPaint*(canvas: TouchCanvas, event: wPaintEvent) =
  ## Draw touch points on canvas
  let dc = canvas.paint()
  dc.clear()
  
  # Draw grid
  dc.setPen(wPen(wxColour(60, 60, 60), style=wxDOT))
  for i in countup(0, canvas.getWidth(), 20):
    dc.drawLine(i, 0, i, canvas.getHeight())
  for i in countup(0, canvas.getHeight(), 20):
    dc.drawLine(0, i, canvas.getWidth(), i)
  
  # Draw touch history
  if canvas.history.len > 1:
    dc.setPen(wPen(wxColour(100, 100, 255), width=2))
    for i in 1..<canvas.history.len:
      dc.drawLine(canvas.history[i-1].x, canvas.history[i-1].y,
                  canvas.history[i].x, canvas.history[i].y)
  
  # Draw current touches
  for touch in canvas.touches:
    # Touch point
    dc.setBrush(wBrush(wxColour(255, 100, 100)))
    dc.setPen(wPen(wxWHITE, width=2))
    dc.drawCircle(touch.x.int, touch.y.int, 20)
    
    # Touch ID
    dc.setFont(wFont(size=12, weight=wxFONTWEIGHT_BOLD))
    dc.setPen(wPen(wxWHITE))
    dc.drawText($touch.id, touch.x.int - 5, touch.y.int - 10)
    
    # Pressure indicator
    if touch.pressure > 0:
      let pressureSize = 10 + (touch.pressure * 20).int
      dc.setBrush(wBrush(wxColour(100, 255, 100, 128)))
      dc.setPen(wPen(wxGREEN, style=wxPENSTYLE_TRANSPARENT))
      dc.drawCircle(touch.x.int, touch.y.int, pressureSize)

method onPaint*(canvas: GestureCanvas, event: wPaintEvent) =
  ## Draw gesture recognition
  let dc = canvas.paint()
  dc.clear()
  
  # Draw gesture path
  if canvas.gesturePath.len > 1:
    dc.setPen(wPen(wxColour(0, 200, 255), width=3))
    for i in 1..<canvas.gesturePath.len:
      dc.drawLine(canvas.gesturePath[i-1].x, canvas.gesturePath[i-1].y,
                  canvas.gesturePath[i].x, canvas.gesturePath[i].y)
    
    # Start point
    dc.setBrush(wBrush(wxGREEN))
    dc.drawCircle(canvas.gesturePath[0].x, canvas.gesturePath[0].y, 5)
    
    # End point
    dc.setBrush(wBrush(wxRED))
    dc.drawCircle(canvas.gesturePath[^1].x, canvas.gesturePath[^1].y, 5)
  
  # Draw recognized gesture info
  if canvas.currentGesture.gestureType != nil:
    let y = canvas.getHeight() - 50
    dc.setFont(wFont(size=16, weight=wxFONTWEIGHT_BOLD))
    dc.setPen(wPen(wxWHITE))
    dc.drawText("Gesture: " & $canvas.currentGesture.gestureType, 10, y)
    dc.drawText(&"Confidence: {canvas.currentGesture.confidence:.1%}", 10, y + 25)

method onPaint*(graph: NetworkGraph, event: wPaintEvent) =
  ## Draw network topology graph
  let dc = graph.paint()
  dc.clear()
  
  let w = graph.getWidth()
  let h = graph.getHeight()
  
  # Draw connections
  for conn in graph.connections:
    var srcPos: tuple[x, y: int]
    var dstPos: tuple[x, y: int]
    
    for node in graph.nodes:
      if node.id == conn.source:
        srcPos = node.position
      if node.id == conn.dest:
        dstPos = node.position
    
    if srcPos != (0, 0) and dstPos != (0, 0):
      # Connection line with quality indicator
      let color = if conn.quality > 0.8: wxGREEN
                 elif conn.quality > 0.5: wxYELLOW
                 else: wxRED
      
      dc.setPen(wPen(color, width=2))
      dc.drawLine(srcPos.x, srcPos.y, dstPos.x, dstPos.y)
      
      # Data rate indicator
      let midX = (srcPos.x + dstPos.x) div 2
      let midY = (srcPos.y + dstPos.y) div 2
      dc.setPen(wPen(wxWHITE))
      dc.drawText(&"{conn.dataRate:.1f} Mbps", midX, midY - 15)
  
  # Draw nodes
  for node in graph.nodes:
    # Node color based on type and status
    let color = if not node.active: wxColour(100, 100, 100)
                elif node.deviceType == dtSmartphone: wxColour(0, 150, 255)
                elif node.deviceType == dtTablet: wxColour(150, 0, 255)
                elif node.deviceType == dtLaptop: wxColour(0, 255, 150)
                else: wxColour(255, 150, 0)
    
    dc.setBrush(wBrush(color))
    dc.setPen(wPen(wxWHITE, width=2))
    dc.drawCircle(node.position.x, node.position.y, 20)
    
    # Node ID
    dc.setFont(wFont(size=10))
    dc.setPen(wPen(wxWHITE))
    dc.drawText(node.id[0..7], node.position.x - 25, node.position.y + 25)
    
    # Signal strength indicator
    if node.signalStrength > -50:
      dc.setPen(wPen(wxGREEN))
    elif node.signalStrength > -70:
      dc.setPen(wPen(wxYELLOW))
    else:
      dc.setPen(wPen(wxRED))
    
    let signalY = node.position.y - 30
    let bars = ((node.signalStrength + 100) / 50 * 4).int
    for i in 0..<bars:
      dc.drawRectangle(node.position.x - 10 + i*5, signalY - i*3, 3, 5 + i*3)

method onPaint*(spectrum: SpectrumView, event: wPaintEvent) =
  ## Draw spectrum analyzer
  let dc = spectrum.paint()
  dc.clear()
  
  let w = spectrum.getWidth()
  let h = spectrum.getHeight()
  let barWidth = w div spectrum.frequencies.len
  
  # Draw frequency bars
  for i, level in spectrum.frequencies:
    let x = i * barWidth
    let barHeight = (level / 100.0 * h).int
    
    # Color based on level
    let color = if level < 30: wxColour(0, 255, 0)
                elif level < 60: wxColour(255, 255, 0)
                else: wxColour(255, 0, 0)
    
    dc.setBrush(wBrush(color))
    dc.setPen(wPen(wxBLACK, style=wxPENSTYLE_TRANSPARENT))
    dc.drawRectangle(x, h - barHeight, barWidth - 2, barHeight)
    
    # Channel number
    if i < 14:
      dc.setPen(wPen(wxWHITE))
      dc.drawText($(i+1), x + 5, h - 20)
  
  # Draw active channels
  for channel in spectrum.activeChannels:
    if channel >= 0 and channel < spectrum.frequencies.len:
      let x = channel * barWidth
      dc.setPen(wPen(wxWHITE, width=3, style=wxSOLID))
      dc.drawLine(x, 0, x, h)
  
  # Interference indicator
  dc.setFont(wFont(size=12))
  dc.setPen(wPen(wxWHITE))
  dc.drawText(&"Interference: {spectrum.interference:.1f}%", 10, 10)

# ==================== Mouse Interaction ====================

method onMouse*(canvas: TouchCanvas, event: wMouseEvent) =
  ## Handle mouse input for touch simulation
  let (x, y) = event.getPosition()
  
  case event.getEventType():
  of wEvent_MouseLeftDown:
    # Add touch point
    let touch = TouchPoint(
      id: canvas.touches.len + 1,
      x: x.float,
      y: y.float,
      pressure: 1.0,
      timestamp: epochTime()
    )
    canvas.touches.add(touch)
    canvas.history.add((x, y))
    canvas.recording = true
    
  of wEvent_MouseMotion:
    if event.leftIsDown() and canvas.recording:
      # Update last touch
      if canvas.touches.len > 0:
        canvas.touches[^1].x = x.float
        canvas.touches[^1].y = y.float
        canvas.touches[^1].timestamp = epochTime()
      canvas.history.add((x, y))
      
  of wEvent_MouseLeftUp:
    canvas.recording = false
    
  else:
    discard
  
  canvas.refresh()

method onMouse*(canvas: GestureCanvas, event: wMouseEvent) =
  ## Handle mouse input for gesture drawing
  let (x, y) = event.getPosition()
  
  case event.getEventType():
  of wEvent_MouseLeftDown:
    canvas.gesturePath = @[(x, y)]
    
  of wEvent_MouseMotion:
    if event.leftIsDown() and canvas.gesturePath.len > 0:
      canvas.gesturePath.add((x, y))
      
  of wEvent_MouseLeftUp:
    # Recognize gesture
    if canvas.gesturePath.len > 10:
      # Simple gesture recognition
      let first = canvas.gesturePath[0]
      let last = canvas.gesturePath[^1]
      let dx = last.x - first.x
      let dy = last.y - first.y
      let distance = sqrt(dx*dx + dy*dy).int
      
      if distance < 20:
        canvas.currentGesture = Gesture(
          gestureType: gtTap,
          confidence: 0.95,
          location: (x: last.x.float, y: last.y.float)
        )
      elif abs(dx) > abs(dy) * 2:
        canvas.currentGesture = Gesture(
          gestureType: if dx > 0: gtSwipe else: gtSwipe,
          confidence: 0.85,
          customData: %*{"direction": if dx > 0: "right" else: "left"}
        )
      elif abs(dy) > abs(dx) * 2:
        canvas.currentGesture = Gesture(
          gestureType: gtSwipe,
          confidence: 0.85,
          customData: %*{"direction": if dy > 0: "down" else: "up"}
        )
      else:
        canvas.currentGesture = Gesture(
          gestureType: gtPan,
          confidence: 0.75
        )
      
      # Add to log
      if uiInstance.gestureLog != nil:
        uiInstance.gestureLog.append(
          &"{canvas.currentGesture.gestureType} - " &
          &"Conf: {canvas.currentGesture.confidence:.1%}"
        )
  
  canvas.refresh()

# ==================== Main Entry Point ====================

proc launchHandBrainUI*(brain: BrainSystem) =
  ## Launch the Hand-Brain UI
  let app = wApp()
  
  # Set app properties
  app.setVendorName("HandBrain")
  app.setAppName("HandBrain Control System")
  
  # Create UI
  let ui = newHandUI(brain)
  ui.frame.show()
  
  # Start app
  app.mainLoop()

# Export for external use
export HandUI, BrainSystem, launchHandBrainUI

when isMainModule:
  # Create brain system
  import brain_system
  let brain = newBrainSystem()
  
  # Launch UI
  launchHandBrainUI(brain)