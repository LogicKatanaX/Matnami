# MATNAMI: System Architecture Blueprint & Kickoff Specification
## High-Performance Anime & Video Streaming/Download App for iOS 12.5.7 (iPad Air 1, Apple A7, 1GB RAM)

---

## 1. Project Vision & Identity

* **Project Name**: **Matnami** (Anime & Video counterpart to Dragonami)
* **Target Hardware**: **iPad Air 1 (2013, Model A1474 / A1475)**
* **SoC**: Apple A7 (Dual-core 1.4 GHz Cyclone, PowerVR G6430, 1 GB LPDDR3 RAM)
* **Target OS**: **iOS 12.0 – iOS 12.5.7** (Final OS for iPad Air 1)
* **Repository Visibility**: **Public** (Grants unlimited free GitHub Actions macOS runner minutes; avoids private repo minute burning)
* **Core Philosophy**: **Download-First Architecture** with seamless on-demand streaming fallback.

---

## 2. "Download-First" Strategy: Why It Unlocks 10x More Sources

> [!IMPORTANT]
> **User Question Answered**: *"If we majorly download first and watch second, do we get more choices?"*
> **Answer: YES, DRAMATICALLY MORE CHOICES.** Here is why:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      Streaming-First vs Download-First                      │
├───────────────────────────────┬─────────────────────────────────────────────┤
│ Streaming-First Constraints   │ Download-First Superpowers                  │
├───────────────────────────────┼─────────────────────────────────────────────┤
│ • CDN must allow instant seek │ • Can fetch from ANY direct file host       │
│ • Expiring 10-min tokens break│ • Token only needs to live for 10s to start │
│ • High jitter on old WiFi chip│ • Downloads queue in background resiliently │
│ • Live decoding + WiFi drain  │ • Zero WiFi antenna drain during playback   │
│ • Limited to live HLS streams │ • Supports Gofile, Pixeldrain, Mediafire,   │
│                               │   Streamtape, Filemoon, Wibufile, Direct MP4│
└───────────────────────────────┴─────────────────────────────────────────────┘
```

### Why Download-First Wins on iPad Air 1:
1. **Immunity to CDN Rate-Limiting & Buffering**: Free video hosts (Streamtape, Filemoon, MegaCloud) aggressively throttle video seek buffers for streaming users. When downloading in chunks, the connection uses full socket bandwidth.
2. **Huge Expansion of Available Host Sources**:
   Almost every anime website (Samehadaku, NekoPoi, Oploverz, Otakudesu) provides **direct download mirrors** that are often faster and higher quality than their embedded stream players:
   * **Gofile / Pixeldrain / FileDon**: Ultra-fast direct HTTP download links.
   * **Direct MP4 CDNs** (`s0.wibufile.com`, Google Blogger Video tokens): Download at 15–30 MB/s.
   * **Streamtape / Mp4Upload**: Direct file resolution.
3. **Thermal & Battery Preservation**: The iPad Air's Broadcom BCM43342 WiFi chip gets hot when continuously receiving video data. Downloading an episode in 40 seconds over WiFi, then playing it from local flash storage keeps the device completely cool and doubles battery life.
4. **Zero-RAM Hardware Playback**: Playing a local `.mp4` file from `Documents/Downloads/` uses Apple's dedicated hardware VideoToolbox decoder with **< 25 MB RAM active footprint**, safely staying well beneath the 180 MB Jetsam ceiling.

---

## 3. Hard-Won Lessons from Dragonami (Pitfalls to Avoid)

When starting Matnami, **never repeat these mistakes**:

### Pitfall 1: Memory & The Jetsam SIGKILL Trap
* **The Reality**: The iPad Air has 1GB physical RAM. The iOS 12 kernel and SpringBoard take ~650MB. **Your app will be killed by Jetsam (`SIGKILL`) if active RAM exceeds ~180MB–220MB.**
* **Solution**:
  * Downsample every catalog image/poster at decode time using `CGImageSourceCreateThumbnailAtIndex` to max **1536px** (native screen resolution). Never load full $3000\times 4000$ posters into memory.
  * In table/collection views, pre-scan card aspect ratios without decoding pixel buffers.
  * Never buffer video chunks in memory (`Data`). Always stream downloads directly to disk using `URLSessionDownloadTask` writing to a temporary file.

### Pitfall 2: Swift Runtime Crash on Launch (`dyld: Library not loaded`)
* **The Reality**: iOS 12 **does not include the Swift Standard Library in OS ROM** (Swift ABI stability in OS only started in iOS 12.2).
* **The Fix**: In `project.yml`, you **MUST** set:
  ```yaml
  ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES: "YES"
  ```
  Without this, the app crashes immediately on launch with:
  `dyld: Library not loaded: @rpath/libswiftCore.dylib`.

### Pitfall 3: Burning GitHub Actions Private Runner Quotas
* **The Reality**: Private repositories have tight monthly quotas (2,000 minutes), and macOS runners have a **10x multiplier** (a 2-minute build burns 20 minutes; an iOS simulator test burns 80 minutes!).
* **The Fix**:
  * Keep the Matnami repository **Public** (unlimited free macOS minutes).
  * Do **NOT** run the heavy iOS simulator test on every `git push`. Guard the simulator job behind `workflow_dispatch` (manual trigger).
  * Build the `.ipa` directly using `xcodebuild -exportArchive` in under 2 minutes.

### Pitfall 4: Cloudflare 403 Bot Walls & Mobile Safari Rejection
* **The Reality**: Direct Python scripts or iOS 12 `CFNetwork` handshakes get rejected by Cloudflare Managed Challenges / Bot Fight Mode.
* **The Fix**:
  * During discovery/scraping, use a modern Desktop User-Agent (`Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36...`) for initial HTML requests.
  * For Cloudflare-protected sites, route requests through our Cloudflare Worker proxy (`https://manga-proxy.santamcyber.workers.dev/?url=`).
  * For video streams that check referers, inject headers via `AVURLAssetHTTPHeaderFieldsKey`:
    ```swift
    let headers = ["Referer": videoHostURL, "User-Agent": "Mozilla/5.0..."]
    let asset = AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    ```

### Pitfall 5: WebP & Video Codec Incompatibilities
* **WebP**: iOS 12 has **no native WebP support** in `UIImage`. If anime posters are served as `.webp`, link `pod 'libwebp'` and bridge with `WebPDecoder.m`.
* **Video Codecs**:
  * **H.264 (AVC)**: 100% hardware-accelerated up to 1080p @ 60fps. (**PASS**)
  * **HLS (`.m3u8`)**: 100% native hardware acceleration in `AVPlayer`. (**PASS**)
  * **H.265 (HEVC)**: Software-only on Apple A7 (causes thermal throttling, 100% CPU burn, and dropped frames). (**STRICT REJECT**)
  * **WebM / VP9 / AV1**: Unsupported by iOS 12 `AVPlayer`. (**STRICT REJECT**)

### Pitfall 6: The "3-Hop" Hierarchy of Anime Sites
* In manga, a chapter URL directly lists images.
* In anime, you must traverse:
  $$\text{Homepage} \xrightarrow{\text{cards}} \text{Series Page} \xrightarrow{\text{episodes}} \text{Episode Page} \xrightarrow{\text{ajax/iframe}} \text{Player / Direct Stream}$$
* Anime sites use AJAX buttons (`POST /wp-admin/admin-ajax.php` with `action="player_ajax"` or `action="doo_player_ajax"`). Your scrapers must simulate these AJAX calls to retrieve real video embeds.

---

## 4. Matnami Core Technical Architecture

```
Matnami/
├── Sources/
│   ├── App/
│   │   ├── AppDelegate.swift             # AudioSession (.playback), Background URLSession delegate
│   │   ├── AppSettings.swift             # Quality (720p/1080p), Download location, Proxy toggle
│   │   └── TabBarController.swift        # 4-Tab Main Navigation
│   ├── Models/
│   │   ├── Anime.swift                   # ID, Title, CoverURL, Synopsis, Score, Status
│   │   ├── Episode.swift                 # ID, Number, Title, EpisodeURL, Duration
│   │   ├── DownloadItem.swift            # Episode metadata, localFilePath, progress, state
│   │   └── VideoSource.swift             # Server name, quality (720p/1080p), streamURL, headers
│   ├── Network/
│   │   ├── AnimeScraperEngine.swift      # 3-Hop parser + WordPress AJAX resolver
│   │   ├── SourceManager.swift           # OTA sources.json synchronization from Secret Gist
│   │   └── Resolvers/
│   │       ├── StreamtapeResolver.swift  # Streamtape token unpacker
│   │       ├── FilemoonResolver.swift    # Filemoon / packed JS unpacker
│   │       └── DirectMP4Resolver.swift   # Wibufile, Blogger, Gofile, Pixeldrain
│   ├── DownloadEngine/
│   │   ├── DownloadManager.swift         # Background URLSessionDownloadTask, pause/resume
│   │   └── StorageManager.swift          # Documents/Downloads management, disk free space meter
│   ├── Player/
│   │   ├── VideoPlayerViewController.swift # Custom AVPlayer with gestures, seek, PiP
│   │   └── PictureInPictureManager.swift # AVPictureInPictureController integration
│   └── UI/
│       ├── Catalog/                      # Anime grid with thumbnail downsampling
│       ├── Detail/                       # Anime info, synopsis, episode download list
│       ├── Downloads/                    # Active downloads with progress bars & offline player
│       └── Settings/                     # Storage meter, quality picker, source updates
├── Podfile                               # libwebp, SwiftSoup
├── project.yml                           # XcodeGen configuration
└── .github/
    └── workflows/
        └── build.yml                     # Fast GitHub Actions CI pipeline
```

---

## 5. The Download Manager (Background URLSession)

To support downloading 200MB episodes even when the iPad is locked or the app is in the background:

```swift
import Foundation

final class EpisodeDownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = EpisodeDownloadManager()

    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.matnami.background-downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func startDownload(episode: Episode, videoSource: VideoSource) {
        var request = URLRequest(url: videoSource.streamURL)
        for (header, value) in videoSource.requiredHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let task = backgroundSession.downloadTask(with: request)
        task.taskDescription = episode.id
        task.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let episodeId = downloadTask.taskDescription else { return }
        
        let destinationDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let targetFile = destinationDir.appendingPathComponent("\(episodeId).mp4")
        try? FileManager.default.removeItem(at: targetFile)
        try? FileManager.default.moveItem(at: location, to: targetFile)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .episodeDownloadCompleted, object: episodeId)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten) / Float(max(totalBytesExpectedToWrite, 1))
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .episodeDownloadProgress, object: nil, userInfo: [
                "episodeId": downloadTask.taskDescription ?? "",
                "progress": progress
            ])
        }
    }
}
```

---

## 6. Video Codecs & Quality Resolution Rubric

| Quality Tier | Target Resolution | Bitrate Range | Typical File Size (24 min) | iPad Air 1 Performance | Recommendation |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Normal (Default)** | **720p H.264** | 1.0 – 1.8 Mbps | **150 MB – 250 MB** | Zero stutter, 60fps hardware decode, cool thermals | **RECOMMENDED DEFAULT** |
| **High** | **1080p H.264** | 2.5 – 4.5 Mbps | **350 MB – 550 MB** | Full Retina clarity, flawless hardware decode | Optional user setting |
| **Compact / Data Saver** | **480p H.264** | 500 – 800 Kbps | **70 MB – 110 MB** | Negligible storage, rapid downloads | For limited storage |
| **HEVC (H.265)** | Any | Any | Variable | Software decode on A7 $\to$ Drops frames, battery drain | **REJECT / AVOID** |

---

## 7. Recommended Initial Verified Video Sources

1. **Samehadaku (`https://v2.samehadaku.how`)**:
   * CMS: WordPress Eastheme
   * Resolution: 480p, 720p, 1080p direct MP4 (`s0.wibufile.com` and Blogger video token)
   * Suitability Score: **100/100 (EXCELLENT)**
2. **NekoPoi (`https://nekopoi.care`)**:
   * CMS: WordPress Media
   * Resolution: 720p HLS (`.m3u8`) and direct MP4
   * Suitability Score: **100/100 (EXCELLENT)**
3. **Gofile / Pixeldrain Direct Mirror Sources**:
   * Ultra-high-speed download endpoints for offline storage.

---

## 8. XcodeGen Configuration Template (`project.yml`)

```yaml
name: Matnami
options:
  bundleIdPrefix: com.matnami
  deploymentTarget:
    iOS: "12.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true

targets:
  Matnami:
    type: application
    platform: iOS
    deploymentTarget: "12.0"
    sources:
      - Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.matnami.app
        INFOPLIST_FILE: Sources/Info.plist
        SWIFT_VERSION: "5.0"
        TARGETED_DEVICE_FAMILY: "1,2"
        IPHONEOS_DEPLOYMENT_TARGET: "12.0"
        ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES: "YES"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        HEADER_SEARCH_PATHS:
          - $(inherited)
          - $(PODS_ROOT)/Headers/Public
```

---

## 9. Fast GitHub Actions Workflow Template (`.github/workflows/build.yml`)

```yaml
name: Build Matnami IPA (iOS 12)

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-13
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Set Xcode Version
        run: sudo xcode-select -s /Applications/Xcode_15.2.app

      - name: Install Tools
        run: brew install xcodegen cocoapods

      - name: Generate Xcode Project
        run: xcodegen generate

      - name: Install Pods
        run: pod install --repo-update

      - name: Build Archive
        run: |
          xcodebuild archive \
            -workspace Matnami.xcworkspace \
            -scheme Matnami \
            -configuration Release \
            -archivePath build/Matnami.xcarchive \
            -destination 'generic/platform=iOS' \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO

      - name: Package Unsigned IPA
        run: |
          mkdir -p build/Payload
          cp -r build/Matnami.xcarchive/Products/Applications/Matnami.app build/Payload/
          cd build && zip -r Matnami.ipa Payload

      - name: Upload IPA Artifact
        uses: actions/upload-artifact@v4
        with:
          name: Matnami-iOS12-IPA
          path: build/Matnami.ipa
```

---

## 10. Copy-Paste Kickoff Prompt for New Repository

When you create the new public GitHub repository for **Matnami**, copy and paste this exact prompt to start the project with full context:

> *"We are starting a new public iOS project called **Matnami**, an anime streaming and offline download application specifically optimized for the **iPad Air 1 (2013, Apple A7 SoC, 1GB RAM) running iOS 12.5.7**.*
>
> *Please read the master specification file `MATNAMI_BLUEPRINT.md` before writing code.*
>
> *Key Architectural Requirements:*
> * *Architecture: **Download-First** (offline playback from `Documents/Downloads/` using `URLSessionConfiguration.background`), with on-demand streaming as secondary.*
> * *Codec: Hardware-accelerated **H.264 (AVC)** and **HLS (`.m3u8`)** only. Strictly reject HEVC (H.265) and WebM/VP9.*
> * *Quality: Default to **720p H.264** (~180MB/episode) for zero-stutter playback and cool thermals, with user toggle for 1080p and 480p.*
> * *Memory Safety: All image decodes downsampled to max 1536px via CoreGraphics; strict memory limit of 180MB to prevent Jetsam SIGKILL.*
> * *Build System: XcodeGen (`project.yml`) targeting iOS 12.0 with `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES`.*
> * *Source Engine: Scraper with autonomous 3-hop navigation (Catalog -> Series -> Episode -> Server) and WordPress player AJAX resolution (`player_ajax` / `doo_player_ajax`), synced OTA via Secret Gist.*
>
> *Let's set up the initial repository structure, XcodeGen `project.yml`, `Podfile`, and GitHub Actions workflow."*

