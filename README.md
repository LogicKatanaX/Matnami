# 🎬 Matnami

**High-Performance Anime & Video Streaming/Download App for iOS 12.5.7 (iPad Air 1, Apple A7, 1GB RAM)**

[![Build Matnami IPA (iOS 12)](https://github.com/LogicKatanaX/Matnami/actions/workflows/build.yml/badge.svg)](https://github.com/LogicKatanaX/Matnami/actions/workflows/build.yml)
[![Target OS](https://img.shields.io/badge/iOS-12.0_--_12.5.8-blue.svg)](https://en.wikipedia.org/wiki/IOS_12)
[![Device](https://img.shields.io/badge/Device-iPad_Air_1_(2013)-orange.svg)](https://support.apple.com/en-us/111956)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 📖 Overview

**Matnami** is the anime and video streaming/offline counterpart to **Dragonami**, engineered specifically to push the vintage **iPad Air 1 (2013, Model A1474 / A1475)** to its maximum potential without succumbing to the strict iOS 12 kernel memory limits (~180MB Jetsam ceiling).

Rather than relying purely on buffered online streaming—which causes thermal buildup, network jitter, and CDN rate-limiting on legacy hardware—Matnami adopts a **Download-First Architecture**:
1. Download full episodes in the background directly to `Documents/Downloads/` using `URLSessionConfiguration.background`.
2. Play back locally using Apple's dedicated hardware **VideoToolbox H.264 decoder** with $< 25$ MB RAM active memory and zero WiFi antenna power drain.
3. Fall back to direct on-demand streaming with custom header injection (`AVURLAssetHTTPHeaderFieldsKey`) whenever instant playback is desired.

---

## ⚡ Key Architectural Pillars

### 1. The Download-First Superpower
* **Immunity to CDN Buffering**: Free video CDNs throttle seeking. Downloading in raw chunks bypasses rate-limiting.
* **Expanded Source Ecosystem**: Unlocks direct file host mirrors (Gofile, Pixeldrain, Wibufile, Blogger direct MP4 tokens).
* **Thermal & Battery Longevity**: The Broadcom BCM43342 WiFi chip stays cool during playback; battery life is effectively doubled.
* **Hardware 60fps Playback**: Apple A7 hardware handles 720p/1080p H.264 with effortless ease.

### 2. Strict Memory Protection (< 180 MB Jetsam Ceiling)
* **Decode-Time Downsampling**: Image decodes are strictly downsampled to a max dimension of 1536px via CoreGraphics `CGImageSourceCreateThumbnailAtIndex`.
* **Static `libwebp` Bridge**: iOS 12 lacks native WebP decoding in `UIImage`. Matnami bridges Google's `libwebp` with custom scaled decode in `WebPDecoder.m`.
* **Zero In-Memory Media Buffering**: Video downloads stream directly to disk temporary files.

### 3. Native iOS 12 Picture-in-Picture (PiP)
* iPad Air 1 natively supports Picture-in-Picture mode on iOS 12 using `AVPictureInPictureController`.
* Configured with `AVAudioSession` category `.playback` to ensure uninterrupted background audio and multitasking.

### 4. Autonomous 3-Hop Scraper & JS Unpacker
* Traverses `Catalog -> Anime Detail -> Episode -> Video Host Server`.
* Integrated Dean Edwards `p,a,c,k,e,d` JavaScript unpacker (`FilemoonResolver`).
* Dedicated token extractor for Streamtape and direct MP4 mirrors.
* Over-The-Air (OTA) source synchronization from GitHub Gist / JSON.

---

## 🛠️ Build & Installation

### Option 1: Download Pre-Built IPA from GitHub Actions
1. Navigate to the [GitHub Actions tab](https://github.com/LogicKatanaX/Matnami/actions).
2. Select the latest successful run of **Build Matnami IPA (iOS 12)**.
3. Download the artifact `Matnami-iOS12-IPA`.
4. Sideload `Matnami.ipa` onto your iPad Air 1 using:
   * **Sideloadly**
   * **AltStore**
   * **TrollStore**
   * **Xcode / Apple Configurator**

### Option 2: Build Locally with XcodeGen & CocoaPods
```bash
# Clone the repository
git clone https://github.com/LogicKatanaX/Matnami.git
cd Matnami

# Generate Xcode project from project.yml
xcodegen generate

# Install CocoaPods dependencies (SwiftSoup, libwebp)
pod install

# Open workspace in Xcode
open Matnami.xcworkspace
```

---

## 📱 Hardware Compatibility

| Spec | iPad Air 1 (2013) Value | Matnami Optimization |
| :--- | :--- | :--- |
| **SoC** | Apple A7 (Cyclone dual-core 1.4 GHz) | Hardware H.264 (AVC) VDA; HEVC/WebM strictly rejected |
| **RAM** | 1 GB LPDDR3 (Total) | $< 180$ MB memory footprint; 40MB total image cache limit |
| **Display** | 9.7" Retina (2048 x 1536 @ 264 ppi) | Downsampled covers to 512px–1536px |
| **OS** | iOS 12.0 – iOS 12.5.7/12.5.8 | Bundled Swift 5.0 stdlib (`ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES`) |
| **Audio/PiP**| Hardware AVC decoder + PiP Controller | Full `AVPictureInPictureController` integration |

---

## 📄 License
MIT License. Created by [Santam Sarkar](https://github.com/LogicKatanaX).
