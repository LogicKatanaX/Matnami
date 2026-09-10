import re
import urllib.parse
from typing import List

def extract_urls_from_text(text: str) -> List[str]:
    """
    Extracts, normalizes, and deduplicates URLs from any text format:
    - Markdown links: [Title](https://domain.com/)
    - Plain URLs: https://domain.com/path
    - Plain domains: domain.com, sub.domain.tv
    """
    candidates = []

    # 1. Extract markdown links: [label](url)
    md_links = re.findall(r'\[([^\]]*)\]\((https?://[^\s\)]+)\)', text)
    for _, url in md_links:
        candidates.append(url)

    # 2. Extract explicit http/https URLs
    raw_urls = re.findall(r'https?://[^\s\'"<>\[\]\(\)]+', text)
    candidates.extend(raw_urls)

    # 3. If no standard URLs found, extract bare domain patterns
    if not candidates:
        bare_domains = re.findall(r'\b(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}\b', text)
        for d in bare_domains:
            candidates.append(f"https://{d}")

    # 4. Normalize and deduplicate
    cleaned_urls = []
    seen = set()

    for item in candidates:
        item = item.strip().rstrip(".,;)")
        if not item:
            continue
        if not item.startswith("http://") and not item.startswith("https://"):
            item = "https://" + item

        try:
            parsed = urllib.parse.urlparse(item)
            if parsed.netloc:
                # Normalize to base URL scheme://netloc
                norm_base = f"{parsed.scheme}://{parsed.netloc}"
                if norm_base not in seen:
                    seen.add(norm_base)
                    cleaned_urls.append(norm_base)
        except Exception:
            continue

    return cleaned_urls

