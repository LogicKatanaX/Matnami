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

# Over-The-Air (OTA) Endpoint
OTA_ENDPOINT_URL = "https://raw.githubusercontent.com/LogicKatanaX/Matnami/main/Sources/sources.json"

# Request Timeouts (seconds - optimized for responsive batch audits)
TIMEOUT_CONNECT = 6
TIMEOUT_READ = 12

# Compatibility Score Weights (Total: 100)
WEIGHT_NETWORK = 15
WEIGHT_CATALOG = 15
WEIGHT_DETAIL_LANG = 25
WEIGHT_SERVERS = 25
WEIGHT_STREAM = 20

# Known Monetized CPM Link Shorteners & Ad Gates (Incompatible with direct iOS 12 downloads)
AD_SHORTENER_DOMAINS = {
    "shrink.pe", "cuty.io", "ouo.io", "ouo.press", "droplink.co",
    "gplinks.co", "clicksfly.com", "exe.io", "linkvertise.com",
    "hubcloud.club", "hubcloud.lol", "hubcloud.bt", "hubdrive.me",
    "shortzon.com", "adfly", "adfocus", "lnbz.la", "filepress",
    "gdflix", "gdtot", "shorte.st", "bc.vc", "adfa.st"
}

# Language Markers
LANG_ENGLISH_SUB_MARKERS = [
    "english sub", "eng sub", "[sub]", "(sub)", "subbed",
    "english subtitled", "eng-sub", "japanese (english sub)",
    "english subtitles", "eng subbed", "subbed series"
]

LANG_ENGLISH_DUB_MARKERS = [
    "english dub", "eng dub", "[dub]", "(dub)", "dubbed",
    "dual audio", "dual-audio", "english audio", "eng-dub",
    "english dubbed", "dubbed series"
]

LANG_JAPANESE_AUDIO_MARKERS = [
    "japanese", "jap sub", "jpn audio", "japanese audio",
    "japanese dubbed", "japines language", "raw"
]

LANG_NON_ENGLISH_MARKERS = [
    "sub indo", "subtitle indonesia", "bahasa indonesia",
    "dub indo", "sub esp", "sub español", "français",
    "português", "hindi dub", "tamil dub", "telugu dub"
]


