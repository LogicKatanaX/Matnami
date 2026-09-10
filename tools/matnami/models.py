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
class LanguageAudit:
    detected_languages: List[str] = field(default_factory=list)
    has_english_sub: bool = False
    has_english_dub: bool = False
    is_acceptable: bool = False  # True if (Japanese + Eng Sub) or Eng Dub or Eng Sub
    status: str = "UNKNOWN"
    details: List[str] = field(default_factory=list)

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
class DecisionRule:
    rule_name: str
    condition: str
    outcome: str
    status: str  # "PASS", "FAIL", "WARN", "INFO"
    deduction: str

@dataclass
class IntelligenceReport:
    verdict_summary: str
    decision_rules: List[DecisionRule] = field(default_factory=list)
    architectural_advice: List[str] = field(default_factory=list)
    can_be_fixed_with_proxy: bool = False
    is_fundamental_rejection: bool = False

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
    language_audit: Optional[LanguageAudit] = None
    stream_audit: Optional[VideoStreamAudit] = None
    suggested_config: Optional[Dict[str, Any]] = None
    recommendations: List[str] = field(default_factory=list)
    intelligence: Optional[IntelligenceReport] = None
