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

    def publish_ota(self, commit_message: str = "chore(sources): update anime sources OTA") -> tuple:
        """Commits Sources/sources.json and pushes to origin main so iPads update Over-The-Air."""
        import subprocess
        try:
            repo_dir = self.path.parent.parent
            # 1. git add Sources/sources.json
            p1 = subprocess.run(["git", "add", "Sources/sources.json"], capture_output=True, text=True, cwd=repo_dir)
            if p1.returncode != 0:
                return False, f"Git add failed: {p1.stderr.strip()}"

            # 2. git commit
            p2 = subprocess.run(["git", "commit", "-m", commit_message], capture_output=True, text=True, cwd=repo_dir)
            output = (p2.stdout + p2.stderr).lower()
            if p2.returncode != 0 and "nothing to commit" not in output:
                return False, f"Git commit failed: {p2.stderr.strip()}"

            # 3. git push origin main
            p3 = subprocess.run(["git", "push", "origin", "main"], capture_output=True, text=True, cwd=repo_dir)
            if p3.returncode != 0:
                return False, f"Git push failed: {p3.stderr.strip()}"

            return True, "Successfully deployed sources.json to GitHub! All connected iPad Air devices will update Over-The-Air."
        except Exception as e:
            return False, f"Exception during OTA publish: {str(e)}"

    def check_remote_ota(self) -> tuple:
        """Fetches the live OTA JSON from GitHub and compares with local sources."""
        import urllib.request
        from .config import OTA_ENDPOINT_URL

        try:
            req = urllib.request.Request(OTA_ENDPOINT_URL, headers={"User-Agent": "Matnami-OTA-Client"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                if resp.status == 200:
                    remote_data = json.loads(resp.read().decode("utf-8"))
                    local_data = self.list_sources()
                    return True, "Live OTA endpoint reachable", remote_data, local_data
                else:
                    return False, f"HTTP status {resp.status}", [], []
        except Exception as e:
            return False, f"Could not contact OTA endpoint: {str(e)}", [], []

