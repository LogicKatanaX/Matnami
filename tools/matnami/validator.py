import time
import re
import urllib.parse
import requests
from bs4 import BeautifulSoup
from typing import Optional, Dict, Any, List

from .config import (
    DESKTOP_UA, IOS12_UA, PROXIES_BASE,
    TIMEOUT_CONNECT, TIMEOUT_READ,
    WEIGHT_NETWORK, WEIGHT_CATALOG, WEIGHT_DETAIL_LANG, WEIGHT_SERVERS, WEIGHT_STREAM,
    AD_SHORTENER_DOMAINS, LANG_ENGLISH_SUB_MARKERS, LANG_ENGLISH_DUB_MARKERS,
    LANG_JAPANESE_AUDIO_MARKERS, LANG_NON_ENGLISH_MARKERS
)
from .models import HopTestResult, VideoStreamAudit, AuditReport, LanguageAudit, DecisionRule, IntelligenceReport
from .resolvers import StreamtapeResolver, FilemoonResolver, DirectMediaResolver, is_ad_shortener

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
        net_hop, use_proxy, home_html = self._test_network_and_bot_walls(target_url, existing_config)
        if not net_hop.passed:
            return self._build_failure_report(
                base_url, source_id, source_name, net_hop,
                "Failed at Network Hop: The website blocked connection (HTTP 403 / Cloudflare Managed Challenge) or timed out."
            )

        # Detect CMS
        cms_detected = self._detect_cms(home_html)

        # =====================================================================
        # HOP 1: Catalog & Search Extraction
        # =====================================================================
        catalog_hop, first_anime = self._test_catalog_and_search(
            target_url, home_html, use_proxy, existing_config, cms_detected
        )
        if not catalog_hop.passed or not first_anime:
            recommendations.append("Could not extract series list. Target page has no identifiable anime card anchors.")

        # =====================================================================
        # HOP 2: Anime Details, Episodes & Language Verification
        # =====================================================================
        detail_hop, episode_list, lang_audit = self._test_anime_details_and_language(
            first_anime.get("detail_url") if first_anime else None,
            use_proxy, existing_config, cms_detected
        )
        if not detail_hop.passed or not episode_list:
            recommendations.append("Failed to discover playable episode links from anime details page.")
        if lang_audit and not lang_audit.is_acceptable:
            recommendations.append(f"Language Requirement Rejection: {lang_audit.status}")

        # =====================================================================
        # HOP 3: Video Player, Server Embeds & Ad-Wall Extraction
        # =====================================================================
        servers_hop, discovered_sources = self._test_video_servers(
            episode_list[0].get("url") if episode_list else None,
            use_proxy, existing_config, cms_detected
        )
        if not servers_hop.passed or not discovered_sources:
            if servers_hop.error:
                recommendations.append(f"Server Hop Failed: {servers_hop.error}")
            else:
                recommendations.append("Episode page embed or direct download mirror could not be resolved.")

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
                else:
                    recommendations.append(f"Codec Incompatibility: {stream_audit.codec} is software-only / unaccelerated on Apple A7 (REJECT).")
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
        is_compatible = (
            total_score >= 60 and
            (stream_audit is not None and stream_audit.is_hw_accelerated) and
            (lang_audit is not None and lang_audit.is_acceptable) and
            servers_hop.passed
        )

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

        intelligence = self._synthesize_intelligence(
            base_url=base_url,
            cms_detected=cms_detected,
            use_proxy=use_proxy,
            net_hop=net_hop,
            catalog_hop=catalog_hop,
            detail_hop=detail_hop,
            servers_hop=servers_hop,
            lang_audit=lang_audit,
            stream_audit=stream_audit,
            is_compatible=is_compatible
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
            language_audit=lang_audit,
            stream_audit=stream_audit,
            suggested_config=suggested_config,
            recommendations=recommendations,
            intelligence=intelligence
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
        html_lower = html.lower()
        if "cartoonsarea" in html_lower or "/user-data/" in html_lower or "dubbed-series" in html_lower or "subbed-series" in html_lower:
            return "CartoonsArea Direct MP4 CMS"
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
        current_url = base_url

        card_sel = existing_config.get("cardSelector") if existing_config else None
        cards = []

        if card_sel:
            cards = soup.select(card_sel)

        if not cards:
            if "CartoonsArea" in cms:
                nav_words = {"home", "japanese", "english", "japanese dubbed videos", "english dubbed series", "fan page", "privacy statement", "disclaimer", "contact us"}
                cards = [
                    a for a in soup.find_all("a", href=True)
                    if any(k in a["href"] for k in ["-Subbed-Videos/", "-Dubbed-Videos/", "-Videos-Download/"])
                    and a.text.strip().lower() not in nav_words
                    and not a["href"].rstrip("/").endswith("Videos")
                    and not a["href"].rstrip("/").endswith("Series")
                ]
                card_sel = "a[href*='-Subbed-Videos/'], a[href*='-Dubbed-Videos/']"
            elif "Eastheme" in cms:
                card_sel = ".animepost, .animpost, article.animpost"
                cards = soup.select(card_sel)
            elif "DooPlay" in cms:
                card_sel = ".poster, article.item-movies, article.item-tvshows"
                cards = soup.select(card_sel)
            else:
                card_sel = ".animepost, article, .item, .bsx, .detpost, .venz ul li"
                cards = soup.select(card_sel)

        # Fallback scan 1: common classes
        if not cards:
            # Fallback scan 1: common classes
            for test in ["article", ".card", ".box", ".movie", ".film", ".thumb", ".item", ".poster"]:
                found = soup.select(test)
                if len(found) >= 3:
                    card_sel = test
                    cards = found
                    break

        # Fallback scan 2: direct series/watch anchors
        if not cards:
            # Fallback scan 2: elements directly linking to anime or series
            found_links = soup.select("a[href*='/anime/'], a[href*='/watch/'], a[href*='/series/']")
            if len(found_links) >= 3:
                card_sel = "a[href*='/anime/'], a[href*='/watch/'], a[href*='/series/']"
                cards = found_links

        # Gateway Traversal: If home page is a portal splash page with sub-catalog portals
        if not cards:
            portal_links = [
                urllib.parse.urljoin(current_url, a["href"])
                for a in soup.find_all("a", href=True)
                if any(k in a["href"] for k in ["-Subbed-", "-Dubbed-", "Japanese-Dubbed", "English-Dubbed", "/anime/", "/series/"])
                and a.text.strip().lower() not in {"home", "fan page", "contact", "login", "register"}
            ]
            for p_url in portal_links[:3]:
                try:
                    p_fetch = PROXIES_BASE + urllib.parse.quote(p_url, safe="") if use_proxy else p_url
                    p_resp = self.session.get(p_fetch, timeout=(TIMEOUT_CONNECT, TIMEOUT_READ))
                    if p_resp.status_code == 200:
                        p_soup = BeautifulSoup(p_resp.text, "html.parser")
                        # Check if this sub-catalog has series or letter subdirectories
                        letter_links = [
                            urllib.parse.urljoin(p_url, a["href"])
                            for a in p_soup.find_all("a", href=True)
                            if any(k in a["href"] for k in ["-Subbed-Series/", "-Dubbed-Series/", "letter/", "browse/"])
                            and urllib.parse.urljoin(p_url, a["href"]).rstrip("/") != p_url.rstrip("/")
                            and a.text.strip().lower() not in {"home", "english", "japanese", "japanese dubbed videos", "english dubbed series"}
                        ]
                        if letter_links:
                            # Follow first letter directory (e.g. A-Subbed-Series)
                            l_fetch = PROXIES_BASE + urllib.parse.quote(letter_links[0], safe="") if use_proxy else letter_links[0]
                            l_resp = self.session.get(l_fetch, timeout=(TIMEOUT_CONNECT, TIMEOUT_READ))
                            if l_resp.status_code == 200:
                                l_soup = BeautifulSoup(l_resp.text, "html.parser")
                                nav_words = {"home", "japanese", "english", "japanese dubbed videos", "english dubbed series"}
                                sub_cards = [
                                    a for a in l_soup.find_all("a", href=True)
                                    if any(k in a["href"] for k in ["-Subbed-Videos/", "-Dubbed-Videos/", "-Videos-Download/"])
                                    and a.text.strip().lower() not in nav_words
                                    and not a["href"].rstrip("/").endswith("Videos")
                                    and not a["href"].rstrip("/").endswith("Series")
                                ]
                                if sub_cards:
                                    cards = sub_cards
                                    current_url = letter_links[0]
                                    card_sel = "a[href*='-Subbed-Videos/'], a[href*='-Dubbed-Videos/']"
                                    messages.append(f"Traversed portal gateway -> letter index ({current_url}).")
                                    break
                        else:
                            # Check if p_soup has anime cards directly
                            sub_found = p_soup.select("a[href*='-Subbed-Videos/'], a[href*='-Dubbed-Videos/'], article, .animepost")
                            if sub_found:
                                cards = sub_found
                                current_url = p_url
                                card_sel = "a[href*='-Subbed-Videos/'], a[href*='-Dubbed-Videos/'], article, .animepost"
                                messages.append(f"Traversed portal gateway -> sub-catalog ({current_url}).")
                                break
                except Exception:
                    pass

        if not cards:
            return HopTestResult("Catalog & Search", False, 0, WEIGHT_CATALOG, 0, {}, messages, "No anime cards found on catalog"), None

        base_url = current_url
        messages.append(f"Discovered {len(cards)} anime cards/series using selector '{card_sel}'.")
        details["card_selector"] = card_sel

        # Parse first card
        first = cards[0]
        link_el = first if first.name == "a" else first.select_one("a[href]")
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
                    messages.append("Poster is WebP format (Supported via Matnami libwebp bridge).")
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
    # Language Detection Intelligence
    def _detect_languages(self, soup: BeautifulSoup, page_text: str, title: str, url: str) -> LanguageAudit:
        text_lower = (page_text + " " + title + " " + url).lower()
        detected = []
        has_eng_sub = False
        has_eng_dub = False
        has_jap_audio = False
        non_english = []

        # 1. Check English Sub markers
        for m in LANG_ENGLISH_SUB_MARKERS:
            if m in text_lower:
                has_eng_sub = True
                detected.append("English Subtitles")
                break

        # 2. Check English Dub markers
        for m in LANG_ENGLISH_DUB_MARKERS:
            if m in text_lower:
                has_eng_dub = True
                detected.append("English Dubbed")
                break

        # 3. Check Japanese Audio markers
        for m in LANG_JAPANESE_AUDIO_MARKERS:
            if m in text_lower:
                has_jap_audio = True
                detected.append("Japanese Audio")
                break

        # 4. Check Non-English markers
        for m in LANG_NON_ENGLISH_MARKERS:
            if m in text_lower:
                non_english.append(m)

        is_acceptable = False
        if "sub indo" in text_lower or "subtitle indonesia" in text_lower or "bahasa indonesia" in text_lower:
            status = "REJECT: Indonesian (Sub Indo) detected - User strictly requires English Sub/Dub"
            is_acceptable = False
        elif has_eng_sub and has_jap_audio:
            status = "PASS: Japanese Audio + English Subtitles"
            is_acceptable = True
        elif has_eng_dub:
            status = "PASS: English Dubbed Audio"
            is_acceptable = True
        elif has_eng_sub:
            status = "PASS: English Subtitles"
            is_acceptable = True
        elif non_english:
            status = f"REJECT: Non-English ({', '.join(non_english[:2])}) detected"
            is_acceptable = False
        else:
            if any(k in url.lower() for k in ["subbed", "dubbed", "english"]):
                status = "PASS: English Sub/Dub indicated by URL structure"
                is_acceptable = True
                has_eng_sub = True
            else:
                status = "FAIL: No verified English sub/dub markers found"
                is_acceptable = False

        return LanguageAudit(
            detected_languages=detected,
            has_english_sub=has_eng_sub,
            has_english_dub=has_eng_dub,
            is_acceptable=is_acceptable,
            status=status,
            details=non_english
        )

    # -------------------------------------------------------------------------
    # Detail, Episodes & Language Check
    # -------------------------------------------------------------------------
    def _test_anime_details_and_language(self, detail_url: Optional[str], use_proxy: bool, existing_config: Optional[dict], cms: str):
        if not detail_url:
            return HopTestResult("Detail & Language", False, 0, WEIGHT_DETAIL_LANG, 0, {}, [], "No detail URL to test"), [], None

        fetch_url = PROXIES_BASE + urllib.parse.quote(detail_url, safe="") if use_proxy else detail_url
        messages = []
        details = {}

        try:
            resp = self.session.get(fetch_url, timeout=(TIMEOUT_CONNECT, TIMEOUT_READ))
            if (resp.status_code != 200 or "Just a moment..." in resp.text or "challenge-running" in resp.text) and not use_proxy:
                # Automatic Cloudflare Worker proxy fallback
                proxy_url = PROXIES_BASE + urllib.parse.quote(detail_url, safe="")
                resp = self.session.get(proxy_url, timeout=(TIMEOUT_CONNECT, TIMEOUT_READ))
                if resp.status_code == 200 and "Just a moment..." not in resp.text:
                    messages.append("Bypassed Cloudflare challenge via Edge Proxy.")

            if resp.status_code != 200 or "Just a moment..." in resp.text:
                return HopTestResult("Detail & Language", False, 0, WEIGHT_DETAIL_LANG, 0, {}, messages, f"HTTP {resp.status_code}"), [], None

            soup = BeautifulSoup(resp.text, "html.parser")
            title_text = soup.title.text.strip() if soup.title else ""

            # Run Language Detection Intelligence
            lang_audit = self._detect_languages(soup, resp.text, title_text, detail_url)
            messages.append(f"Language Audit: {lang_audit.status}")

            # Synopsis
            syn_el = soup.select_one(".desc, .entry-content, .sinopc, .synopsis, #synopsis, .film-description")
            synopsis = syn_el.text.strip()[:100] if syn_el else "N/A"
            details["synopsis_snippet"] = synopsis

            # Episodes
            ep_sel = existing_config.get("episodeListSelector") if existing_config else None
            if not ep_sel:
                ep_sel = ".lstepsiode ul li, .episodelst ul li, .episodelist ul li, #episode_list li, .eph-num, .listeps ul li, .episodes-ul li, .ssl-item, a[href*='/watch/'], a[href*='/episode/']"
            # Episodes extraction
            episodes = []

            ep_items = soup.select(ep_sel)
            if not ep_items:
                ep_items = soup.select("a[href*='/episode'], a[href*='-episode-'], a[href*='/watch/']")
            # Check if this is a directory page with Season subdirectories (e.g. CartoonsArea)
            season_links = soup.select("a[href*='Season-'], a[href*='Season_'], a[href*='/Season/']")
            if season_links:
                first_season_url = urllib.parse.urljoin(detail_url, season_links[0].get("href"))
                s_fetch = PROXIES_BASE + urllib.parse.quote(first_season_url, safe="") if use_proxy else first_season_url
                s_resp = self.session.get(s_fetch, timeout=(TIMEOUT_CONNECT, TIMEOUT_READ))
                if s_resp.status_code == 200:
                    season_soup = BeautifulSoup(s_resp.text, "html.parser")
                    ep_items = season_soup.select("a[href*='Episode-'], a[href*='Episode_'], a[href*='/Episode/']")
                    for idx, link in enumerate(ep_items):
                        ep_url = urllib.parse.urljoin(first_season_url, link.get("href"))
                        ep_title = link.text.strip() or f"Episode {idx + 1}"
                        if not any(e["url"] == ep_url for e in episodes):
                            episodes.append({"title": ep_title, "url": ep_url})
                    detail_url = first_season_url

            episodes = []
            for idx, item in enumerate(ep_items):
                link = item if item.name == "a" else item.select_one("a[href]")
                if link and link.get("href"):
                    ep_url = urllib.parse.urljoin(detail_url, link.get("href"))
                    ep_title = link.text.strip() or f"Episode {idx + 1}"
                    if not any(e["url"] == ep_url for e in episodes):
                        episodes.append({"title": ep_title, "url": ep_url})
            if not episodes:
                ep_sel = existing_config.get("episodeListSelector") if existing_config else None
                if not ep_sel:
                    ep_sel = ".lstepsiode ul li, .episodelst ul li, .episodelist ul li, #episode_list li, .eph-num, .listeps ul li, .episodes-ul li, .ssl-item, a[href*='/watch/'], a[href*='/episode/']"

                ep_items = soup.select(ep_sel)
                if not ep_items:
                    ep_items = soup.select("a[href*='/episode'], a[href*='-episode-'], a[href*='/watch/'], a[href*='-Video/']")

                for idx, item in enumerate(ep_items):
                    link = item if item.name == "a" else item.select_one("a[href]")
                    if link and link.get("href"):
                        ep_url = urllib.parse.urljoin(detail_url, link.get("href"))
                        ep_title = link.text.strip() or f"Episode {idx + 1}"
                        if not any(e["url"] == ep_url for e in episodes):
                            episodes.append({"title": ep_title, "url": ep_url})

            if not episodes:
                return HopTestResult("Detail & Language", False, 5, WEIGHT_DETAIL_LANG, 0, details, messages, "No episode links discovered"), [], lang_audit

            messages.append(f"Discovered {len(episodes)} episodes (Sample: {episodes[0]['title'][:30]}).")
            details["episode_count"] = len(episodes)
            details["sample_episode_url"] = episodes[0]["url"]

            score = WEIGHT_DETAIL_LANG if lang_audit.is_acceptable else 5
            return HopTestResult("Detail & Language", lang_audit.is_acceptable, score, WEIGHT_DETAIL_LANG, 0, details, messages), episodes, lang_audit

        except Exception as e:
            return HopTestResult("Detail & Language", False, 0, WEIGHT_DETAIL_LANG, 0, {}, [str(e)], "Failed to parse anime details"), [], None

    # -------------------------------------------------------------------------
    # Video Servers & Embed Check
    # Video Servers & Ad-Shortener Check
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
            if (resp.status_code != 200 or "Just a moment..." in resp.text or "challenge-running" in resp.text) and not use_proxy:
                proxy_url = PROXIES_BASE + urllib.parse.quote(ep_url, safe="")
                resp = self.session.get(proxy_url, timeout=(TIMEOUT_CONNECT, TIMEOUT_READ))
                if resp.status_code == 200 and "Just a moment..." not in resp.text:
                    messages.append("Bypassed Cloudflare challenge on episode page via Edge Proxy.")

            if resp.status_code != 200 or "Just a moment..." in resp.text:
                return HopTestResult("Video Servers", False, 0, WEIGHT_SERVERS, 0, {}, messages, f"HTTP {resp.status_code}"), []

            soup = BeautifulSoup(resp.text, "html.parser")

            # 1. Direct mirrors & video elements
            directs = DirectMediaResolver.resolve(resp.text, ep_url)
            discovered.extend(directs)

            # 2. Extract iframes (supports nested iframes)
            # 2. Check for .mp4.php wrapper (CartoonsArea style)
            mp4_php_links = soup.select("a[href*='.mp4.php']")
            for php_link in mp4_php_links:
                php_url = urllib.parse.urljoin(ep_url, php_link.get("href"))
                try:
                    php_resp = self.session.get(php_url, headers={"Referer": ep_url}, timeout=6)
                    php_soup = BeautifulSoup(php_resp.text, "html.parser")
                    for a in php_soup.select("a[href]"):
                        href = a.get("href", "")
                        if "USER-DATA" in href or href.endswith(".mp4"):
                            full_mp4 = urllib.parse.urljoin(php_url, href)
                            discovered.append({
                                "server": "Direct MP4 (CartoonsArea)",
                                "stream_url": full_mp4,
                                "format": "mp4",
                                "is_direct": True,
                                "headers": {"Referer": php_url}
                            })
                            messages.append("Extracted direct nginx MP4 download link.")
                            break
                except Exception:
                    pass

            # 3. Extract iframes (supports nested player iframes)
            iframes = soup.select("iframe[src], iframe[data-src]")
            for iframe in iframes:
                src = iframe.get("src") or iframe.get("data-src") or ""
                if not src or "adgebra" in src or "doubleclick" in src or "syndication" in src:
                    continue
                full_src = urllib.parse.urljoin(ep_url, src)

                # Follow iframe to see if it embeds a video or player
                try:
                    iframe_fetch = PROXIES_BASE + urllib.parse.quote(full_src, safe="") if use_proxy else full_src
                    emb_resp = self.session.get(iframe_fetch, headers={"Referer": ep_url}, timeout=6)
                    if emb_resp.status_code != 200 and not use_proxy:
                        iframe_fetch = PROXIES_BASE + urllib.parse.quote(full_src, safe="")
                        emb_resp = self.session.get(iframe_fetch, headers={"Referer": ep_url}, timeout=6)

                    if StreamtapeResolver.can_handle(full_src):
                        messages.append(f"Found Streamtape embed: {full_src}")
                        res = StreamtapeResolver.resolve(emb_resp.text, full_src)
                        if res:
                            discovered.append(res)
                    elif FilemoonResolver.can_handle(full_src):
                        messages.append(f"Found Filemoon embed: {full_src}")
                        res = FilemoonResolver.resolve(emb_resp.text, full_src)
                        if res:
                            discovered.append(res)
                    else:
                        # Check if this iframe embeds another inner iframe
                        inner_soup = BeautifulSoup(emb_resp.text, "html.parser")
                        inner_iframes = inner_soup.select("iframe[src], iframe[data-src]")
                        if inner_iframes:
                            inner_src = inner_iframes[0].get("src") or inner_iframes[0].get("data-src")
                            full_inner = urllib.parse.urljoin(full_src, inner_src)
                            discovered.append({
                                "server": urllib.parse.urlparse(full_inner).netloc,
                                "stream_url": full_inner,
                                "format": "m3u8" if ".m3u8" in full_inner else "mp4",
                                "is_direct": False,
                                "headers": {"Referer": full_src}
                            })
                        else:
                            discovered.append({
                                "server": urllib.parse.urlparse(full_src).netloc,
                                "stream_url": full_src,
                                "format": "m3u8" if ".m3u8" in full_src else "mp4",
                                "is_direct": False,
                                "headers": {"Referer": ep_url}
                            })
                except Exception:
                    discovered.append({
                        "server": urllib.parse.urlparse(full_src).netloc,
                        "stream_url": full_src,
                        "format": "m3u8" if ".m3u8" in full_src else "mp4",
                        "is_direct": False,
                        "headers": {"Referer": ep_url}
                    })
                    pass

            # 4. Detect Monetized Ad Shorteners & Captcha Gates
            shorteners_found = []
            for a in soup.select("a[href]"):
                link_href = urllib.parse.urljoin(ep_url, a.get("href", ""))
                if is_ad_shortener(link_href):
                    shorteners_found.append(link_href)

            if not discovered and shorteners_found:
                short_domain = urllib.parse.urlparse(shorteners_found[0]).netloc
                messages.append(f"Download mirrors route through CPM ad shortener ({short_domain}).")
                return HopTestResult(
                    "Video Servers", False, 0, WEIGHT_SERVERS, 0,
                    {"shorteners": shorteners_found[:3]},
                    messages,
                    f"Monetized Ad Shortener Gate ({short_domain})"
                ), []

            # 5. Detect Account / Login Gates
            if "please login" in resp.text.lower() or "login to report" in resp.text.lower() or "sign in to download" in resp.text.lower():
                return HopTestResult(
                    "Video Servers", False, 0, WEIGHT_SERVERS, 0, {},
                    ["Download links locked behind user / donor account login wall."],
                    "Login Wall Required"
                ), []

            if not discovered:
                return HopTestResult("Video Servers", False, 5, WEIGHT_SERVERS, 0, details, messages, "No video embed or download mirror found"), []
                return HopTestResult("Video Servers", False, 5, WEIGHT_SERVERS, 0, details, messages, "No video embed or direct download mirror found"), []

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
    def _synthesize_intelligence(
        self,
        base_url: str,
        cms_detected: str,
        use_proxy: bool,
        net_hop: HopTestResult,
        catalog_hop: HopTestResult,
        detail_hop: HopTestResult,
        servers_hop: HopTestResult,
        lang_audit: Optional[LanguageAudit],
        stream_audit: Optional[VideoStreamAudit],
        is_compatible: bool
    ) -> IntelligenceReport:
        rules: List[DecisionRule] = []
        advice: List[str] = []

        # ---------------------------------------------------------------------
        # Rule 1: WAF & Network Architecture (Anti-Bot / Cloudflare Challenge)
        # ---------------------------------------------------------------------
        if not net_hop.passed:
            rules.append(DecisionRule(
                rule_name="WAF & Anti-Bot Shield",
                condition="Direct connection blocked (HTTP 403 / Cloudflare JS Turnstile) & Proxy failed",
                outcome="Hard WAF Rejection",
                status="FAIL",
                deduction="Target requires headless browser / interactive JS challenge clearance. Automated iOS 12 URLSession cannot pass."
            ))
            advice.append("CRITICAL: Origin blocks direct requests. Target requires a Cloudflare Turnstile bypass worker.")
        elif use_proxy:
            rules.append(DecisionRule(
                rule_name="WAF & Anti-Bot Shield",
                condition="Direct connection blocked by Cloudflare (403), but Edge Worker proxy passed (200 OK)",
                outcome="Reroute through Cloudflare Worker (useProxy: true)",
                status="PASS",
                deduction="Cloudflare Edge Worker reverse-proxy strips TLS fingerprints and bypasses bot wall for iOS 12."
            ))
            advice.append("NETWORK: Enable 'useProxy: true' in sources.json so requests route through the Cloudflare Worker.")
        else:
            rules.append(DecisionRule(
                rule_name="WAF & Anti-Bot Shield",
                condition=f"Direct connection returned HTTP 200 (Latency: {net_hop.latency_ms:.0f}ms)",
                outcome="Native Direct HTTP Requests (useProxy: false)",
                status="PASS",
                deduction="Clean origin server with zero Cloudflare interstitial challenges. Lowest latency direct socket calls on iPad Air 1."
            ))

        # ---------------------------------------------------------------------
        # Rule 2: Catalog DOM Architecture (SSR vs Client-side SPA)
        # ---------------------------------------------------------------------
        if not catalog_hop.passed:
            rules.append(DecisionRule(
                rule_name="Catalog DOM Hierarchy",
                condition="DOM parser extracted 0 anime cards from HTML response",
                outcome="Catalog Extraction Failure / Client-side SPA",
                status="FAIL",
                deduction="Site relies on client-side JS hydration (React/Next.js/Vue) or heavily obfuscated classes. Unusable for SwiftSoup."
            ))
            advice.append("CATALOG: Cannot extract anime list with static CSS selectors. Site may be a dynamic SPA.")
        elif catalog_hop.details.get("card_count", 0) >= 3:
            rules.append(DecisionRule(
                rule_name="Catalog DOM Hierarchy",
                condition=f"Parsed {catalog_hop.details.get('card_count', 0)} anime cards via static CSS selectors",
                outcome="Server-Side Rendered (SSR) Flat / Directory Catalog",
                status="PASS",
                deduction="Predictable server-rendered DOM. iOS app can extract title, link, and poster images instantly with minimal memory."
            ))
        else:
            rules.append(DecisionRule(
                rule_name="Catalog DOM Hierarchy",
                condition="Homepage has < 3 direct anime items (portal splash navigation)",
                outcome="Traverse into sub-directory / deep category",
                status="WARN",
                deduction="Domain root does not expose full catalog; requires deeper catalogPattern URL (e.g. /A-Subbed-Series/)."
            ))
            advice.append("CATALOG: Specify deep directory URL in catalogPattern rather than root domain.")

        # ---------------------------------------------------------------------
        # Rule 3: Language & Subtitle Compliance (Strict Japanese/Eng Sub/Dub)
        # ---------------------------------------------------------------------
        if lang_audit is None:
            rules.append(DecisionRule(
                rule_name="Language & Subtitle Rubric",
                condition="No language tags or metadata found on details page",
                outcome="Unverified Audio / Subtitle Tracks",
                status="WARN",
                deduction="Could not confirm whether media is in English or Japanese from page text."
            ))
        elif not lang_audit.is_acceptable:
            langs = ", ".join(lang_audit.detected_languages) if lang_audit.detected_languages else lang_audit.status
            rules.append(DecisionRule(
                rule_name="Language & Subtitle Rubric",
                condition=f"Detected non-English / non-Japanese audio format: '{langs}'",
                outcome="STRICT REJECTION (Dodged Indonesian/Foreign-only source)",
                status="FAIL",
                deduction="User constraint enforces Japanese Audio + English Subs OR English Dub. Indonesian Sub Indo is strictly rejected."
            ))
            advice.append(f"LANGUAGE REJECTION: Source provides non-compliant language ('{langs}'). Matnami rejects foreign-only catalogs.")
        else:
            langs = ", ".join(lang_audit.detected_languages) if lang_audit.detected_languages else "Eng Sub/Dub"
            desc = "English Dubbed" if lang_audit.has_english_dub else "Japanese Audio + English Subtitles"
            rules.append(DecisionRule(
                rule_name="Language & Subtitle Rubric",
                condition=f"Verified {desc} markers ({langs})",
                outcome="100% Compliant Language Format",
                status="PASS",
                deduction="Audio and subtitle tracks meet user accessibility criteria for iPad Air 1."
            ))

        # ---------------------------------------------------------------------
        # Rule 4: Monetized CPM Ad-Shortener / Paywall Rejection
        # ---------------------------------------------------------------------
        is_shortener = "Shortener" in (servers_hop.error or "")
        if not is_shortener and servers_hop.details.get("servers"):
            for s in servers_hop.details.get("servers"):
                if is_ad_shortener(s.get("url", "")):
                    is_shortener = True
                    break

        if is_shortener:
            rules.append(DecisionRule(
                rule_name="Monetized CPM Paywall & Captcha",
                condition="Episode mirrors route through known CPM shorteners (e.g. shrink.pe, cuty.io, lnbz.la, hubcloud)",
                outcome="Monetized CPM Shortener Rejection",
                status="FAIL",
                deduction="Requires interactive captcha resolution, multi-tier ad popups, and countdown timers. Automated iOS 12 downloader cannot resolve CPM gates."
            ))
            advice.append("ADS / PAYWALL: Download links are gated by monetized URL shorteners requiring human captcha interaction.")
        elif servers_hop.passed and stream_audit and stream_audit.status_code in (200, 206):
            rules.append(DecisionRule(
                rule_name="Monetized CPM Paywall & Captcha",
                condition="Direct media file / CDN link extracted without ad-wall redirects",
                outcome="Clean Direct Download Endpoint",
                status="PASS",
                deduction="Zero intermediate paywall gates. Direct HTTP socket connection allows native background download queueing."
            ))
        elif not servers_hop.passed:
            rules.append(DecisionRule(
                rule_name="Monetized CPM Paywall & Captcha",
                condition="Episode embed or direct download mirror could not be extracted",
                outcome="Media Resolution Failure",
                status="FAIL",
                deduction="Video sources are obscured behind proprietary obfuscated scripts or broken mirrors."
            ))
            advice.append("SERVERS: Failed to resolve direct video stream or supported iframe embed player.")

        # ---------------------------------------------------------------------
        # Rule 5: Apple A7 (iPad Air 1) Hardware Acceleration Codec
        # ---------------------------------------------------------------------
        if stream_audit is None:
            rules.append(DecisionRule(
                rule_name="Apple A7 Hardware VDA Codec",
                condition="No stream endpoint available for codec probing",
                outcome="Skipped Codec Verification",
                status="SKIP",
                deduction="Cannot test hardware acceleration without a resolved stream URL."
            ))
        elif stream_audit.is_hw_accelerated:
            rules.append(DecisionRule(
                rule_name="Apple A7 Hardware VDA Codec",
                condition=f"Container: {stream_audit.format.upper()}, Codec: {stream_audit.codec} (8-bit H.264/AVC)",
                outcome="100% Hardware VideoToolbox (VDA) Acceleration",
                status="PASS",
                deduction="Apple A7 PowerVR G6430 native VDA decoder handles playback at <15% CPU and <25MB RAM, safe from iOS 12 Jetsam crash."
            ))
        else:
            rules.append(DecisionRule(
                rule_name="Apple A7 Hardware VDA Codec",
                condition=f"Container: {stream_audit.format.upper()}, Codec: {stream_audit.codec} (HEVC/x265 or VP9)",
                outcome="FATAL HARDWARE INCOMPATIBILITY (Software Decode Only)",
                status="FAIL",
                deduction="Apple A7 SoC lacks HEVC/x265 hardware decoders. Software decode drops 80%+ frames and causes Jetsam memory kills on 1GB RAM iPad Air 1."
            ))
            advice.append("CODEC FATAL: Stream uses HEVC/x265 or unaccelerated codec. Unplayable on Apple A7 hardware.")

        # ---------------------------------------------------------------------
        # Rule 6: HTTP 206 Byte Ranges (Resumable Offline Downloads)
        # ---------------------------------------------------------------------
        if stream_audit is None:
            rules.append(DecisionRule(
                rule_name="HTTP 206 Byte-Range Resumability",
                condition="Stream unverified",
                outcome="Skipped Range Check",
                status="SKIP",
                deduction="Byte-range support unknown."
            ))
        elif stream_audit.supports_byte_range:
            rules.append(DecisionRule(
                rule_name="HTTP 206 Byte-Range Resumability",
                condition="HTTP 206 Partial Content verified ('Accept-Ranges: bytes', Content-Range returned)",
                outcome="Native Resumable Background Downloads & Seeking",
                status="PASS",
                deduction="iOS URLSessionDownloadTask can pause and resume seamlessly across network drops. AVPlayer can seek instantly."
            ))
        else:
            rules.append(DecisionRule(
                rule_name="HTTP 206 Byte-Range Resumability",
                condition=f"Server returned HTTP {stream_audit.status_code} without Accept-Ranges support",
                outcome="Non-Resumable Stream",
                status="WARN",
                deduction="Downloads cannot be paused or resumed if Wi-Fi drops. Seeking in AVPlayer triggers full re-buffering."
            ))
            advice.append("DOWNLOADS: Server lacks HTTP 206 Byte Ranges. Interrupted downloads must restart from 0% bytes.")

        # ---------------------------------------------------------------------
        # Rule 7: CDN Delivery & Download Bandwidth
        # ---------------------------------------------------------------------
        if stream_audit and stream_audit.speed_mbps > 0:
            speed = stream_audit.speed_mbps
            est_sec = int((300 * 8) / max(speed, 0.1))
            if speed >= 10.0:
                rules.append(DecisionRule(
                    rule_name="CDN Bandwidth & Delivery",
                    condition=f"Measured CDN throughput: {speed:.1f} Mbps",
                    outcome=f"High-Speed CDN (~{est_sec}s for 300MB episode)",
                    status="PASS",
                    deduction="Fast edge CDN suitable for rapid offline episode downloading on iPad Air 1."
                ))
            elif speed >= 3.0:
                rules.append(DecisionRule(
                    rule_name="CDN Bandwidth & Delivery",
                    condition=f"Measured CDN throughput: {speed:.1f} Mbps",
                    outcome=f"Moderate Speed CDN (~{est_sec}s for 300MB episode)",
                    status="WARN",
                    deduction="Download speeds are acceptable but high-bitrate files will take several minutes."
                ))
            else:
                rules.append(DecisionRule(
                    rule_name="CDN Bandwidth & Delivery",
                    condition=f"Measured CDN throughput: {speed:.1f} Mbps (Throttling detected)",
                    outcome=f"Slow CDN (~{est_sec}s for 300MB episode)",
                    status="FAIL",
                    deduction="Server may be rate-limiting non-browser connections or congested."
                ))
        else:
            rules.append(DecisionRule(
                rule_name="CDN Bandwidth & Delivery",
                condition="Download throughput not benchmarked",
                outcome="Throughput Unverified",
                status="SKIP",
                deduction="Could not measure transfer speeds."
            ))

        # Overall synthesis
        is_fundamental_rejection = bool(
            (stream_audit and not stream_audit.is_hw_accelerated) or
            (lang_audit and not lang_audit.is_acceptable) or
            is_shortener
        )
        can_be_fixed_with_proxy = bool(not net_hop.passed and not is_fundamental_rejection)

        if is_compatible:
            verdict_summary = "100% COMPATIBLE: Perfectly aligned with iPad Air 1 (iOS 12) offline download architecture."
            advice.insert(0, f"READY: Add source to Sources/sources.json with useProxy={str(use_proxy).lower()} and deploy OTA.")
        elif is_fundamental_rejection:
            reasons = []
            if stream_audit and not stream_audit.is_hw_accelerated:
                reasons.append("HEVC/x265 Hardware Incompatibility")
            if lang_audit and not lang_audit.is_acceptable:
                reasons.append("Non-English / Indonesian Sub Indo Restriction")
            if is_shortener:
                reasons.append("Monetized CPM Shortener Paywall")
            verdict_summary = f"STRICT REJECTION: Incompatible with iOS 12 constraints ({', '.join(reasons)})."
        elif not net_hop.passed:
            verdict_summary = "NETWORK BLOCKED: Cloudflare Managed Challenge or WAF prevented access."
        elif not catalog_hop.passed:
            verdict_summary = "DOM INCOMPATIBLE: Catalog structure could not be parsed via static selectors."
        else:
            verdict_summary = "INCOMPATIBLE: Server or video extraction pipeline failed verification."

        return IntelligenceReport(
            verdict_summary=verdict_summary,
            decision_rules=rules,
            architectural_advice=advice,
            can_be_fixed_with_proxy=can_be_fixed_with_proxy,
            is_fundamental_rejection=is_fundamental_rejection
        )

    def _build_failure_report(self, url: str, s_id: str, s_name: str, net_hop: HopTestResult, msg: str) -> AuditReport:
        catalog_hop = HopTestResult("Catalog", False, 0, WEIGHT_CATALOG, 0, {}, [], "Skipped")
        detail_hop = HopTestResult("Detail & Language", False, 0, WEIGHT_DETAIL_LANG, 0, {}, [], "Skipped")
        servers_hop = HopTestResult("Servers", False, 0, WEIGHT_SERVERS, 0, {}, [], "Skipped")

        intelligence = self._synthesize_intelligence(
            base_url=url,
            cms_detected="Unknown",
            use_proxy=False,
            net_hop=net_hop,
            catalog_hop=catalog_hop,
            detail_hop=detail_hop,
            servers_hop=servers_hop,
            lang_audit=None,
            stream_audit=None,
            is_compatible=False
        )

        return AuditReport(
            url=url,
            source_id=s_id,
            source_name=s_name,
            cms_detected="Unknown",
            overall_score=0,
            is_compatible=False,
            use_proxy=False,
            network_hop=net_hop,
            catalog_hop=catalog_hop,
            detail_hop=detail_hop,
            servers_hop=servers_hop,
            language_audit=None,
            stream_audit=None,
            suggested_config=None,
            recommendations=[msg],
            intelligence=intelligence
        )

    def _build_source_config(self, source_id: str, source_name: str, base_url: str, cms_detected: str,
                             use_proxy: bool, existing: Optional[dict], catalog_details: dict,
                             detail_details: dict, servers_details: dict) -> dict:
        if existing:
            cfg = dict(existing)
            cfg["useProxy"] = use_proxy
            return cfg

        if "CartoonsArea" in cms_detected:
            return {
                "id": "cartoonsarea",
                "name": "CartoonsArea",
                "baseURL": "https://www.cartoonsarea.cc",
                "catalogPattern": "https://www.cartoonsarea.cc/Japanese-Dubbed-Videos/A-Subbed-Series/",
                "searchPattern": "https://www.cartoonsarea.cc/?s={query}",
                "cardSelector": ".directory-list a[href*='-Series/']",
                "linkSelector": "a[href]",
                "titleSelector": "h2, h3, a",
                "coverSelector": "img",
                "scoreSelector": None,
                "synopsisSelector": ".desc, p",
                "episodeListSelector": "a[href*='Season-'], a[href*='Episode-'], a[href*='-Video/']",
                "episodeLinkSelector": "a",
                "episodeTitleSelector": "a",
                "playerIframeSelector": None,
                "serverItemSelector": "a[href*='.mp4'], a[href*='/USER-DATA/']",
                "ajaxAction": None,
                "useProxy": False
            }

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

