import Foundation
import SwiftSoup

public final class DirectMP4Resolver {
    public static let shared = DirectMP4Resolver()

    private let desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private init() {}

    /// Checks if a URL is already a direct playable video URL (.mp4, .m3u8, or known direct CDNs)
    public func isDirectMediaURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "mp4" || ext == "m3u8" {
            return true
        }
        let host = url.host?.lowercased() ?? ""
        if host.contains("wibufile.com") || host.contains("blogger.com") || host.contains("googleusercontent.com") {
            return true
        }
        return false
    }

    /// Extracts direct video source from HTML page containing video/source tags or direct CDN links
    public func resolveFromHTML(_ html: String, pageURL: URL) -> [VideoSource] {
        var sources: [VideoSource] = []

        guard let doc = try? SwiftSoup.parse(html, pageURL.absoluteString) else {
            return sources
        }

        // 1. Direct <source> or <video> tags
        if let videoElements = try? doc.select("video, source") {
            for el in videoElements.array() {
                var src = (try? el.attr("src")) ?? ""
                if src.isEmpty {
                    src = (try? el.attr("data-src")) ?? ""
                }
                guard !src.isEmpty, let streamURL = URL(string: src, relativeTo: pageURL)?.absoluteURL else {
                    continue
                }

                let ext = streamURL.pathExtension.lowercased()
                let format: VideoFormat = (ext == "m3u8" || src.contains(".m3u8")) ? .hls : .mp4
                let label = (try? el.attr("label")) ?? (try? el.attr("title")) ?? "Direct"
                let quality = parseQuality(from: label + " " + src)

                sources.append(VideoSource(
                    serverName: "Direct (\(label))",
                    quality: quality,
                    streamURL: streamURL,
                    referer: pageURL.absoluteString,
                    isDirectDownload: format == .mp4,
                    format: format,
                    headers: [
                        "Referer": pageURL.absoluteString,
                        "User-Agent": desktopUA
                    ]
                ))
            }
        }

        // 2. Scan download mirror buttons (Gofile, Pixeldrain, Wibufile)
        if let linkElements = try? doc.select("a[href]") {
            for link in linkElements.array() {
                let href = (try? link.attr("href")) ?? ""
                let text = (try? link.text()) ?? ""
                guard let targetURL = URL(string: href, relativeTo: pageURL)?.absoluteURL else { continue }
                let host = targetURL.host?.lowercased() ?? ""

                if isDirectMediaURL(targetURL) || host.contains("pixeldrain.com") || host.contains("gofile.io") {
                    let quality = parseQuality(from: text + " " + href)
                    let name = host.replacingOccurrences(of: "www.", with: "").capitalized
                    sources.append(VideoSource(
                        serverName: name.isEmpty ? "Mirror" : name,
                        quality: quality,
                        streamURL: targetURL,
                        referer: pageURL.absoluteString,
                        isDirectDownload: true,
                        format: .mp4,
                        headers: [
                            "Referer": pageURL.absoluteString,
                            "User-Agent": desktopUA
                        ]
                    ))
                }
            }
        }

        return sources
    }

    private func parseQuality(from text: String) -> VideoQuality {
        let lower = text.lowercased()
        if lower.contains("1080") {
            return .high1080p
        } else if lower.contains("720") {
            return .normal720p
        } else if lower.contains("480") || lower.contains("360") {
            return .compact480p
        }
        return .normal720p
    }
}

