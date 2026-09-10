import re
import urllib.parse
from bs4 import BeautifulSoup

def unpack_packed_js(packed_code: str) -> str:
    """Unpacks Dean Edwards p,a,c,k,e,d JavaScript"""
    pattern = r"\}\('(.*)',\s*(\d+),\s*(\d+),\s*'([^']+)'\.split\('\|'\)"
    match = re.search(pattern, packed_code)
    if not match:
        return packed_code

    payload, radix, count, symtab = match.groups()
    radix = int(radix)
    syms = symtab.split('|')

    def lookup(w):
        try:
            val = int(w, radix) if w.isalnum() else -1
            return syms[val] if 0 <= val < len(syms) and syms[val] else w
        except ValueError:
            return w

    return re.sub(r'\b\w+\b', lambda m: lookup(m.group(0)), payload)

class StreamtapeResolver:
    @staticmethod
    def can_handle(url: str) -> bool:
        host = urllib.parse.urlparse(url).netloc.lower()
        return "streamtape" in host or "streamta.pe" in host or "tapecontent" in host

    @staticmethod
    def resolve(html: str, page_url: str) -> dict | None:
        soup = BeautifulSoup(html, "html.parser")
        robotlink = soup.select_one("#robotlink, #ideoolink")
        if robotlink and robotlink.text.strip():
            link = robotlink.text.strip()
            if link.startswith("//"):
                link = "https:" + link
            return {
                "server": "Streamtape",
                "stream_url": link,
                "format": "mp4",
                "is_direct": True,
                "headers": {"Referer": page_url}
            }

        pattern = r"document\.getElementById\(['\"]robotlink['\"]\)\.innerHTML\s*=\s*['\"]([^'\"]+)['\"]\s*\+\s*\('([^']+)'\.substring\(\d+\)\)"
        match = re.search(pattern, html)
        if match:
            p1, p2 = match.groups()
            full = "https:" + p1 + p2
            return {
                "server": "Streamtape",
                "stream_url": full,
                "format": "mp4",
                "is_direct": True,
                "headers": {"Referer": page_url}
            }
        return None

class FilemoonResolver:
    @staticmethod
    def can_handle(url: str) -> bool:
        host = urllib.parse.urlparse(url).netloc.lower()
        return "filemoon" in host

    @staticmethod
    def resolve(html: str, page_url: str) -> dict | None:
        unpacked = unpack_packed_js(html)
        search_space = unpacked + "\n" + html

        m3u8_match = re.search(r'["\'](https?://[^"\']+\.m3u8[^"\']*)["\']', search_space)
        if m3u8_match:
            return {
                "server": "Filemoon",
                "stream_url": m3u8_match.group(1),
                "format": "m3u8",
                "is_direct": False,
                "headers": {"Referer": page_url}
            }

        mp4_match = re.search(r'["\'](https?://[^"\']+\.mp4[^"\']*)["\']', search_space)
        if mp4_match:
            return {
                "server": "Filemoon",
                "stream_url": mp4_match.group(1),
                "format": "mp4",
                "is_direct": True,
                "headers": {"Referer": page_url}
            }
        return None

class DirectMediaResolver:
    @staticmethod
    def resolve(html: str, page_url: str) -> list[dict]:
        results = []
        soup = BeautifulSoup(html, "html.parser")

        # 1. Direct <source> or <video> tags
        for el in soup.select("video, source"):
            src = el.get("src") or el.get("data-src") or ""
            if not src:
                continue
            full_url = urllib.parse.urljoin(page_url, src)
            is_m3u8 = ".m3u8" in full_url.lower()
            results.append({
                "server": "Direct Media",
                "stream_url": full_url,
                "format": "m3u8" if is_m3u8 else "mp4",
                "is_direct": not is_m3u8,
                "headers": {"Referer": page_url}
            })

        # 2. Direct download mirror links
        for a in soup.select("a[href]"):
            href = a.get("href", "").strip()
            if not href:
                continue
            full_url = urllib.parse.urljoin(page_url, href)
            host = urllib.parse.urlparse(full_url).netloc.lower()

            if any(k in host for k in ["pixeldrain.com", "gofile.io", "wibufile.com", "blogger.com"]) or full_url.lower().endswith(".mp4"):
                name = host.replace("www.", "").split(".")[0].capitalize()
                results.append({
                    "server": name if name else "Mirror",
                    "stream_url": full_url,
                    "format": "mp4",
                    "is_direct": True,
                    "headers": {"Referer": page_url}
                })

        return results
