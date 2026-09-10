import os
from pathlib import Path

# Paths
ROOT_DIR = Path(__file__).resolve().parent.parent.parent
SOURCES_JSON_PATH = ROOT_DIR / "Sources" / "sources.json"

# User Agents
DESKTOP_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
IOS12_UA = "Mozilla/5.0 (iPad; CPU OS 12_5_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1"

# Edge Reverse Proxy
PROXIES_BASE = "https://manga-proxy.santamcyber.workers.dev/?url="

# Request Timeouts (seconds)
TIMEOUT_CONNECT = 10
TIMEOUT_READ = 25

# Compatibility Score Weights (Total: 100)
WEIGHT_NETWORK = 20
WEIGHT_CATALOG = 20
WEIGHT_DETAIL = 20
WEIGHT_SERVERS = 20
WEIGHT_STREAM = 20
