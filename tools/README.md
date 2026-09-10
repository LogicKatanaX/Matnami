# 🧪 Matnami Source Tester & Compatibility Suite

The **Matnami Source Tester** is an automated validation and audit tool designed to verify if anime streaming and download websites are 100% compatible with the **iPad Air 1 (2013, Apple A7, 1GB RAM) running iOS 12.0 – 12.5.7/12.5.8**.

---

## 🚀 Quick Start

### Option 1: Double-Click Launcher (Windows)
Double-click `test_website.bat` in the root folder of Matnami.

### Option 2: CLI Usage (Terminal)
```bash
# Interactive Dashboard
python tools/matnami_tester.py

# List Active Sources in Sources/sources.json
python tools/matnami_tester.py list

# Audit a Specific Website
python tools/matnami_tester.py test https://v2.samehadaku.how

# Audit All Configured Sources
python tools/matnami_tester.py test-all

# Audit and Automatically Save to Sources/sources.json
python tools/matnami_tester.py add https://v2.samehadaku.how

# Remove a Source
python tools/matnami_tester.py remove samehadaku
```

---

## 📊 The 4-Hop Compatibility Rubric (Total: 100 Points)

| Hop | Stage | Max Score | What is Verified |
| :--- | :--- | :---: | :--- |
| **Hop 0** | **Network & Anti-Bot** | 20 pts | Direct HTTP 200 vs Cloudflare Bot Wall / JS challenge. Verifies if Edge Proxy (`manga-proxy.santamcyber.workers.dev`) is required. |
| **Hop 1** | **Catalog & Search** | 20 pts | Detects CMS (Eastheme, DooPlay, Toroflix), parses anime cards, titles, and checks cover image formats (WebP vs JPEG/PNG). |
| **Hop 2** | **Detail & Episodes** | 20 pts | Traverses to series detail page, parses synopsis, genres, and extracts complete episode listing with episode numbers. |
| **Hop 3** | **Video Player & Embeds** | 20 pts | Resolves player iframe embeds, WordPress AJAX endpoints (`player_ajax` / `doo_player_ajax`), and runs video unpackers (Streamtape, Filemoon). |
| **Hop 4** | **Stream Codec & Download** | 20 pts | Tests direct MP4/HLS stream: checks HTTP 206 Partial Content (seeking support), detects H.264 (Hardware AVC) vs H.265 (HEVC reject), and measures download throughput. |

**Verdict Threshold**:
* **$\ge 70$ Points + Hardware H.264 / HLS**: **COMPATIBLE**
* **$< 70$ Points OR Software-only Codec (HEVC / VP9)**: **STRICT REJECTION**

