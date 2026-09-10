import time
import re
import urllib.parse
import requests
from bs4 import BeautifulSoup
from typing import Optional, Dict, Any, List

from .config import (
    DESKTOP_UA, IOS12_UA, PROXIES_BASE,
    TIMEOUT_CONNECT, TIMEOUT_READ,
    WEIGHT_NETWORK, WEIGHT_CATALOG, WEIGHT_DETAIL, WEIGHT_SERVERS, WEIGHT_STREAM
)
from .models import HopTestResult, VideoStreamAudit, AuditReport
from .resolvers import StreamtapeResolver, FilemoonResolver, DirectMediaResolver

class WebsiteAuditor:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": DESKTOP_UA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        })

    def audit_url(self, target_url: str, existing_config: Optional[Dict[str, Any]] = None) -> AuditReport:
        parsed_target = urllib.parse.urlparse(target_url)
        base_url = f"{parsed_target.scheme}://{parsed_target.netloc}"
        source_id = parsed_target.netloc.replace("www.", "").split(".")[0].lower()
        source_name = source_id.capitalize()

        recommendations: List[str] = []

        # =====================================================================
        # HOP 0: Network Connectivity & Anti-Bot / Cloudflare Challenge Check
        # =====================================================================
        net_hop, use_proxy, home_html = self._test_network_and_bot_walls(base_url, existing_config)
        if not net_hop.passed:
            return self._build_failure_report(
                base_url, source_id, source_name, net_hop,
                "Failed at Network Hop. The website blocked connection or timed out."
            )

        # Detect CMS
        cms_detected = self._detect_cms(home_html)

        # =====================================================================
        # HOP 1: Catalog & Search Extraction
        # =====================================================================
        catalog_hop, first_anime = self._test_catalog_and_search(
            base_url, home_html, use_proxy, existing_config, cms_detected
        )
        if not catalog_hop.passed or not first_anime:
            recommendations.append("Adjust card/title CSS selectors in sources.json to properly extract series list.")

        # =====================================================================
        # HOP 2: Anime Details & Episodes Extraction
        # =====================================================================
        detail_hop, episode_list = self._test_anime_details(
            first_anime.get("detail_url") if first_anime else None,
            use_proxy, existing_config, cms_detected
        )
        if not detail_hop.passed or not episode_list:
            recommendations.append("Ensure episode list selector targets chapter/episode links accurately.")

        # =====================================================================
        # HOP 3: Video Player & Server Embed Extraction
        # =====================================================================
        servers_hop, discovered_sources = self._test_video_servers(
            episode_list[0].get("url") if episode_list else None,
            use_proxy, existing_config, cms_detected
        )
        if not servers_hop.passed or not discovered_sources:
            recommendations.append("Episode page embed or AJAX server switcher could not be resolved.")

        # =====================================================================
        # HOP 4: Video Stream Compatibility for iPad Air 1 (iOS 12)
        # =====================================================================
        stream_audit = None
        stream_score = 0
        if discovered_sources:
            stream_audit = self._audit_stream_compatibility(discovered_sources[0])
            if stream_audit.status_code in (200, 206):
                stream_score = 10
                if stream_audit.is_hw_accelerated:
                    stream_score += 5
                if stream_audit.supports_byte_range:
                    stream_score += 5
                else:
                    recommendations.append("Server does not support HTTP 206 Byte Ranges. AVPlayer seeking will re-buffer.")
            else:
                recommendations.append(f"Media stream responded with HTTP {stream_audit.status_code}.")

        total_score = (
            net_hop.score +
            catalog_hop.score +
            detail_hop.score +
            servers_hop.score +
            stream_score
        )
        is_compatible = total_score >= 70 and (stream_audit is not None and stream_audit.is_hw_accelerated)

        # Build suggested sources.json entry
        suggested_config = self._build_source_config(
            source_id=source_id,
            source_name=source_name,
            base_url=base_url,
            cms_detected=cms_detected,
            use_proxy=use_proxy,
            existing=existing_config,
            catalog_details=catalog_hop.details,
            detail_details=detail_hop.details,
            servers_details=servers_hop.details
        )

        return AuditReport(
            url=base_url,
            source_id=source_id,
            source_name=source_name,
            cms_detected=cms_detected,
            overall_score=total_score,
            is_compatible=is_compatible,
            use_proxy=use_proxy,
            network_hop=net_hop,
            catalog_hop=catalog_hop,
            detail_hop=detail_hop,
            servers_hop=servers_hop,
            stream_audit=stream_audit,
            suggested_config=suggested_config,
            recommendations=recommendations
        )

    # -------------------------------------------------------------------------
    # Network & Bot Check
    # -------------------------------------------------------------------------
    def _test_network_and_bot_walls(self, base_url: str, existing_config: Optional[dict]):
        start = time.time()
        use_proxy = existing_config.get("useProxy", False) if existing_config else False
        messages = []

        # 1. Test Direct Connection
        try:
            resp = self.session.get(base_url, timeout=(TIMEOUT_CONNECT, TIMEOUT_READ))
            latency = (time.time() - start) * 1000

            if resp.status_code == 200:
                # Check for Cloudflare challenge strings
                if "cf-browser-verification" in resp.text or "Just a moment..." in resp.text or "challenge-running" in resp.text:
                    messages.append("Direct request encountered Cloudflare Managed Challenge (JS wall).")
                    use_proxy = True
                else:
                    messages.append(f"Direct connection OK (HTTP 200, {latency:.0f}ms). No proxy needed.")
                    return HopTestResult("Network & TLS", True, WEIGHT_NETWORK, WEIGHT_NETWORK, latency, {"use_proxy": False}, messages), False, resp.text
            else:
                messages.append(f"Direct request returned HTTP {resp.status_code}.")
                use_proxy = True
        except Exception as e:
            messages.append(f"Direct connection failed: {e}")
            use_proxy = True

        # 2. Test Proxy Connection if direct failed or blocked
        if use_proxy:
            proxy_url = PROXIES_BASE + urllib.parse.quote(base_url, safe="")
            messages.append(f"Testing Cloudflare Worker proxy: {proxy_url}")
            try:
                start_p = time.time()
                resp = self.session.get(proxy_url, timeout=(TIMEOUT_CONNECT, TIMEOUT_READ))
                latency = (time.time() - start_p) * 1000
                if resp.status_code == 200 and len(resp.text) > 500:
                    messages.append(f"Proxy successfully bypassed Cloudflare wall (HTTP 200, {latency:.0f}ms).")
                    return HopTestResult("Network & TLS", True, WEIGHT_NETWORK - 2, WEIGHT_NETWORK, latency, {"use_proxy": True}, messages), True, resp.text
                else:
                    messages.append(f"Proxy returned HTTP {resp.status_code}.")
            except Exception as e:
                messages.append(f"Proxy connection failed: {e}")

        return HopTestResult("Network & TLS", False, 0, WEIGHT_NETWORK, 0.0, {"use_proxy": False}, messages, "Site unreachable"), False, ""

    def _detect_cms(self, html: str) -> str:
        if "wp-content" in html or "wp-includes" in html:
            if "animpost" in html or "animepost" in html or "east_player" in html:
                return "WordPress Eastheme"
            if "dooplay" in html or "doo_player" in html:
                return "WordPress DooPlay"
            if "toroflix" in html:
                return "WordPress Toroflix"
            return "WordPress (Generic)"
        if "next/static" in html:
            return "Next.js Single Page App"
        if "nuxt" in html:
            return "Nuxt.js Single Page App"
        return "Custom HTML5 CMS"

    # -------------------------------------------------------------------------
    # Catalog & Search Check
    # -------------------------------------------------------------------------
    def _test_catalog_and_search(self, base_url: str, html: str, use_proxy: bool, existing_config: Optional[dict], cms: str):
        soup = BeautifulSoup(html, "html.parser")
        messages = []
        details = {}

        card_sel = existing_config.get("cardSelector") if existing_config else None
        if not card_sel:
            if "Eastheme" in cms:
                card_sel = ".animepost, .animpost, article.animpost"
            elif "DooPlay" in cms:
                card_sel = ".poster, article.item-movies, article.item-tvshows"
            else:
                card_sel = ".animepost, article, .item, .bsx, .detpost, .venz ul li"

        cards = soup.select(card_sel)
        if not cards:
            # Fallback scan
            for test in ["article", ".card", ".box", ".movie", ".film", ".thumb"]:
                found = soup.select(test)
                if len(found) >= 3:
                    card_sel = test
                    cards = found
                    break

        if not cards:
            return HopTestResult("Catalog & Search", False, 0, WEIGHT_CATALOG, 0, {}, messages, "No anime cards found on catalog"), None

        messages.append(f"Discovered {len(cards)} anime cards using selector '{card_sel}'.")
        details["card_selector"] = card_sel

        # Parse first card
        first = cards[0]
        link_el = first.select_one("a[href]")
        title_el = first.select_one("h2, h3, h4, .title, .tt, .entry-title") or link_el
        img_el = first.select_one("img")

        href = link_el.get("href", "") if link_el else ""
        title = title_el.text.strip() if title_el else "Unknown"
        cover = img_el.get("src") or img_el.get("data-src") or "" if img_el else ""

        full_link = urllib.parse.urljoin(base_url, href)
        full_cover = urllib.parse.urljoin(base_url, cover) if cover else ""

        details["sample_title"] = title
        details["sample_url"] = full_link
        details["sample_cover"] = full_cover

        # Validate cover image format for iOS 12
        if full_cover:
            try:
                head_resp = self.session.head(full_cover, timeout=5)
                c_type = head_resp.headers.get("Content-Type", "")
                if "webp" in c_type.lower() or full_cover.lower().endswith(".webp"):
                    messages.append("Poster is WebP format (Supported via Matnami's libwebp bridge).")
                elif "jpeg" in c_type.lower() or "png" in c_type.lower():
                    messages.append(f"Poster format: {c_type} (Direct iOS 12 hardware support).")
            except Exception:
                pass

        score = WEIGHT_CATALOG
        return HopTestResult("Catalog & Search", True, score, WEIGHT_CATALOG, 0, details, messages), {
            "title": title,
            "detail_url": full_link,
            "cover_url": full_cover
        }

    # -------------------------------------------------------------------------
    # Detail & Episodes Check
    # -------------------------------------------------------------------------
    def _test_anime_details(self, detail_url: Optional[str], use_proxy: bool, existing_config: Optional[dict], cms: str):
        if not detail_url:
            return HopTestResult("Detail & Episodes", False, 0, WEIGHT_DETAIL, 0, {}, [], "No detail URL to test"), []

        fetch_url = PROXIES_BASE + urllib.parse.quote(detail_url, safe="") if use_proxy else detail_url
        messages = []
        details = {}

        try:
            resp = self.session.get(fetch_url, timeout=(TIMEOUT_CONNECT, TIMEOUT_READ))
            if resp.status_code != 200:
                return HopTestResult("Detail & Episodes", False, 0, WEIGHT_DETAIL, 0, {}, messages, f"HTTP {resp.status_code}"), []

            soup = BeautifulSoup(resp.text, "html.parser")

            # Synopsis
            syn_el = soup.select_one(".desc, .entry-content, .sinopc, .synopsis, #synopsis")
            synopsis = syn_el.text.strip()[:100] if syn_el else "N/A"
            details["synopsis_snippet"] = synopsis

            # Episodes
            ep_sel = existing_config.get("episodeListSelector") if existing_config else None
            if not ep_sel:
                ep_sel = ".lstepsiode ul li, .episodelst ul li, .episodelist ul li, #episode_list li, .eph-num, .listeps ul li"

            ep_items = soup.select(ep_sel)
            if not ep_items:
                # Fallback search for any episode links
                ep_items = soup.select("a[href*='/episode'], a[href*='-episode-']")

            episodes = []
            for idx, item in enumerate(ep_items):
                link = item if item.name == "a" else item.select_one("a[href]")
                if link and link.get("href"):
                    ep_url = urllib.parse.urljoin(detail_url, link.get("href"))
                    ep_title = link.text.strip() or f"Episode {idx + 1}"
                    episodes.append({"title": ep_title, "url": ep_url})

            if not episodes:
                return HopTestResult("Detail & Episodes", False, 5, WEIGHT_DETAIL, 0, details, messages, "No episode links discovered"), []

            messages.append(f"Discovered {len(episodes)} episodes (Sample: {episodes[0]['title']}).")
            details["episode_count"] = len(episodes)
            details["sample_episode_url"] = episodes[0]["url"]

            return HopTestResult("Detail & Episodes", True, WEIGHT_DETAIL, WEIGHT_DETAIL, 0, details, messages), episodes

        except Exception as e:
            return HopTestResult("Detail & Episodes", False, 0, WEIGHT_DETAIL, 0, {}, [str(e)], "Failed to parse anime details"), []

    # -------------------------------------------------------------------------
    # Video Servers & Embed Check
    # -------------------------------------------------------------------------
    def _test_video_servers(self, ep_url: Optional[str], use_proxy: bool, existing_config: Optional[dict], cms: str):
        if not ep_url:
            return HopTestResult("Video Servers", False, 0, WEIGHT_SERVERS, 0, {}, [], "No episode URL"), []

        fetch_url = PROXIES_BASE + urllib.parse.quote(ep_url, safe="") if use_proxy else ep_url
        messages = []
        details = {}
        discovered = []

        try:
            resp = self.session.get(fetch_url, timeout=(TIMEOUT_CONNECT, TIMEOUT_READ))
            if resp.status_code != 200:
                return HopTestResult("Video Servers", False, 0, WEIGHT_SERVERS, 0, {}, messages, f"HTTP {resp.status_code}"), []

            soup = BeautifulSoup(resp.text, "html.parser")

            # 1. Direct mirrors & video elements
            directs = DirectMediaResolver.resolve(resp.text, ep_url)
            discovered.extend(directs)

            # 2. Extract iframes
            iframes = soup.select("iframe[src], iframe[data-src]")
            for iframe in iframes:
                src = iframe.get("src") or iframe.get("data-src") or ""
                if not src:
                    continue
                full_src = urllib.parse.urljoin(ep_url, src)

                if StreamtapeResolver.can_handle(full_src):
                    messages.append(f"Found Streamtape embed: {full_src}")
                    # Try resolving
                    try:
                        emb_resp = self.session.get(full_src, headers={"Referer": ep_url}, timeout=8)
                        res = StreamtapeResolver.resolve(emb_resp.text, full_src)
                        if res:
                            discovered.append(res)
                    except Exception:
                        pass

                elif FilemoonResolver.can_handle(full_src):
                    messages.append(f"Found Filemoon embed: {full_src}")
                    try:
                        emb_resp = self.session.get(full_src, headers={"Referer": ep_url}, timeout=8)
                        res = FilemoonResolver.resolve(emb_resp.text, full_src)
                        if res:
                            discovered.append(res)
                    except Exception:
                        pass
                else:
                    discovered.append({
                        "server": urllib.parse.urlparse(full_src).netloc,
                        "stream_url": full_src,
                        "format": "m3u8" if ".m3u8" in full_src else "mp4",
                        "is_direct": False,
                        "headers": {"Referer": ep_url}
                    })

            if not discovered:
                return HopTestResult("Video Servers", False, 5, WEIGHT_SERVERS, 0, details, messages, "No video embed or download mirror found"), []

            messages.append(f"Extracted {len(discovered)} stream/download endpoint(s). Primary: {discovered[0]['server']}")
            details["sources_count"] = len(discovered)
            details["primary_server"] = discovered[0]["server"]
            details["primary_url"] = discovered[0]["stream_url"]

            return HopTestResult("Video Servers", True, WEIGHT_SERVERS, WEIGHT_SERVERS, 0, details, messages), discovered

        except Exception as e:
            return HopTestResult("Video Servers", False, 0, WEIGHT_SERVERS, 0, {}, [str(e)], "Failed to resolve video servers"), []

    # -------------------------------------------------------------------------
    # Hop 4: Stream Codec & Download Test for iOS 12 / Apple A7
    # -------------------------------------------------------------------------
    def _audit_stream_compatibility(self, source_dict: dict) -> VideoStreamAudit:
        url = source_dict["stream_url"]
        server_name = source_dict["server"]
        fmt = source_dict["format"]
        headers = dict(source_dict.get("headers", {}))
        headers["User-Agent"] = DESKTOP_UA

        diagnostics = []
        status_code = 0
        content_type = ""
        supports_byte_range = False
        codec = "Unknown"
        is_hw_accelerated = False
        speed_mbps = 0.0

        try:
            # Request 512KB chunk with HTTP Range
            range_headers = dict(headers)
            range_headers["Range"] = "bytes=0-524288"

            start_t = time.time()
            resp = self.session.get(url, headers=range_headers, timeout=12, stream=True)
            elapsed = time.time() - start_t
            status_code = resp.status_code
            content_type = resp.headers.get("Content-Type", "")

            supports_byte_range = (status_code == 206) or ("bytes" in resp.headers.get("Accept-Ranges", "").lower())
            if supports_byte_range:
                diagnostics.append("HTTP 206 Partial Content supported (Fast seeking in AVPlayer).")

            chunk = resp.raw.read(524288)
            chunk_size_bytes = len(chunk)

            if elapsed > 0 and chunk_size_bytes > 0:
                speed_mbps = (chunk_size_bytes * 8) / (elapsed * 1024 * 1024)

            # Analyze container / codec for iPad Air 1
            if fmt == "m3u8" or "mpegurl" in content_type.lower() or ".m3u8" in url:
                fmt = "m3u8"
                codec = "HLS Adaptive (H.264)"
                is_hw_accelerated = True
                diagnostics.append("Native Apple HLS stream (100% AVPlayer hardware acceleration).")
            elif chunk_size_bytes > 16:
                # Check for MP4 ftyp box
                if b"ftyp" in chunk[:32]:
                    fmt = "mp4"
                    if b"hev1" in chunk[:64] or b"hvc1" in chunk[:64]:
                        codec = "H.265 (HEVC)"
                        is_hw_accelerated = False
                        diagnostics.append("HEVC (H.265) detected: Software-only on Apple A7 (REJECT for iPad Air 1).")
                    else:
                        codec = "H.264 (AVC)"
                        is_hw_accelerated = True
                        diagnostics.append("Standard H.264 MP4 (Apple A7 VideoToolbox hardware accelerated).")
                else:
                    codec = "Direct Stream"
                    is_hw_accelerated = True

        except Exception as e:
            diagnostics.append(f"Stream verification error: {e}")

        return VideoStreamAudit(
            url=url,
            server_name=server_name,
            format=fmt,
            status_code=status_code,
            content_type=content_type,
            supports_byte_range=supports_byte_range,
            codec=codec,
            is_hw_accelerated=is_hw_accelerated,
            speed_mbps=speed_mbps,
            required_headers=headers,
            diagnostics=diagnostics
        )

    # -------------------------------------------------------------------------
    # Helper & Synthesis
    # -------------------------------------------------------------------------
    def _build_failure_report(self, url: str, s_id: str, s_name: str, net_hop: HopTestResult, msg: str) -> AuditReport:
        return AuditReport(
            url=url,
            source_id=s_id,
            source_name=s_name,
            cms_detected="Unknown",
            overall_score=0,
            is_compatible=False,
            use_proxy=False,
            network_hop=net_hop,
            catalog_hop=HopTestResult("Catalog", False, 0, WEIGHT_CATALOG, 0, {}, [], "Skipped"),
            detail_hop=HopTestResult("Detail", False, 0, WEIGHT_DETAIL, 0, {}, [], "Skipped"),
            servers_hop=HopTestResult("Servers", False, 0, WEIGHT_SERVERS, 0, {}, [], "Skipped"),
            stream_audit=None,
            suggested_config=None,
            recommendations=[msg]
        )

    def _build_source_config(self, source_id: str, source_name: str, base_url: str, cms_detected: str,
                             use_proxy: bool, existing: Optional[dict], catalog_details: dict,
                             detail_details: dict, servers_details: dict) -> dict:
        if existing:
            cfg = dict(existing)
            cfg["useProxy"] = use_proxy
            return cfg

        card_sel = catalog_details.get("card_selector", ".animepost, article")
        return {
            "id": source_id,
            "name": source_name,
            "baseURL": base_url,
            "catalogPattern": f"{base_url}/page/{{page}}/",
            "searchPattern": f"{base_url}/?s={{query}}",
            "cardSelector": card_sel,
            "linkSelector": "a[href]",
            "titleSelector": "h2, h3, .title",
            "coverSelector": "img",
            "scoreSelector": ".score, .rating",
            "synopsisSelector": ".desc, .entry-content",
            "episodeListSelector": ".episodelist ul li, .lstepsiode ul li, a[href*='/episode']",
            "episodeLinkSelector": "a",
            "episodeTitleSelector": "a",
            "playerIframeSelector": "#pembed iframe, .player-embed iframe, iframe[src]",
            "serverItemSelector": ".server-item, .mirror",
            "ajaxAction": "player_ajax" if "Eastheme" in cms_detected else None,
            "useProxy": use_proxy
        }
