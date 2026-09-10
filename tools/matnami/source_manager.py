import json
from pathlib import Path
from typing import List, Dict, Any, Optional
from .config import SOURCES_JSON_PATH

class SourceManager:
    def __init__(self, path: Path = SOURCES_JSON_PATH):
        self.path = path

    def list_sources(self) -> List[Dict[str, Any]]:
        if not self.path.exists():
            return []
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []

    def get_source(self, source_id: str) -> Optional[Dict[str, Any]]:
        sources = self.list_sources()
        for s in sources:
            if s.get("id") == source_id:
                return s
        return None

    def save_source(self, new_config: Dict[str, Any]) -> bool:
        sources = self.list_sources()
        s_id = new_config.get("id")

        updated = False
        for idx, s in enumerate(sources):
            if s.get("id") == s_id:
                sources[idx] = new_config
                updated = True
                break

        if not updated:
            sources.append(new_config)

        try:
            with open(self.path, "w", encoding="utf-8") as f:
                json.dump(sources, f, indent=2, ensure_ascii=False)
            return True
        except Exception:
            return False

    def remove_source(self, source_id: str) -> bool:
        sources = self.list_sources()
        new_list = [s for s in sources if s.get("id") != source_id]
        if len(new_list) == len(sources):
            return False

        try:
            with open(self.path, "w", encoding="utf-8") as f:
                json.dump(new_list, f, indent=2, ensure_ascii=False)
            return True
        except Exception:
            return False

