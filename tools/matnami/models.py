from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any

@dataclass
class HopTestResult:
    name: str
    passed: bool
    score: int
    max_score: int
    latency_ms: float = 0.0
    details: Dict[str, Any] = field(default_factory=dict)
    messages: List[str] = field(default_factory=list)
    error: Optional[str] = None

@dataclass
class VideoStreamAudit:
    url: str
    server_name: str
    format: str # "mp4" or "m3u8"
    status_code: int
    content_type: str
    supports_byte_range: bool
    codec: str # "H.264 (AVC)", "H.265 (HEVC)", "VP9", "Unknown"
    is_hw_accelerated: bool
    speed_mbps: float
    required_headers: Dict[str, str] = field(default_factory=dict)
    diagnostics: List[str] = field(default_factory=list)

@dataclass
class AuditReport:
    url: str
    source_id: str
    source_name: str
    cms_detected: str
    overall_score: int
    is_compatible: bool
    use_proxy: bool
    network_hop: HopTestResult
    catalog_hop: HopTestResult
    detail_hop: HopTestResult
    servers_hop: HopTestResult
    stream_audit: Optional[VideoStreamAudit] = None
    suggested_config: Optional[Dict[str, Any]] = None
    recommendations: List[str] = field(default_factory=list)

