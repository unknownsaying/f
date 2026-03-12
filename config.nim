const 
  ServerConfig* = """
{
  "server": {
    "port": 5000,
    "max_connections": 1000,
    "ssl": true
  },
  "security": {
    "session_timeout": 3600,
    "max_auth_attempts": 5,
    "encryption": "AES-256-GCM"
  },
  "wifi": {
    "channel_scan_interval": 60,
    "threat_detection": true,
    "signal_history_size": 10000
  },
  "gestures": {
    "use_ml": true,
    "learning_rate": 0.01,
    "tap_max_duration": 0.3,
    "swipe_min_distance": 50
  }
}
"""