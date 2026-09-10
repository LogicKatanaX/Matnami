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
        let path = url.path
        if path.contains("USER-DATA") || path.contains(".mp4") {
            return true
        }
        let abs = url.absoluteString.lowercased()
        if abs.contains(".mp4") || abs.contains("user-data") {
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
        try? doc.select("noscript").remove()

        // 1. Direct <source> or <video> tags
        if let videoElements = try? doc.select("video, source") {
            for el in videoElements.array() {
                var src = (try? el.attr("src")) ?? ""
                if src.isEmpty {
                    src = (try? el.attr("data-src")) ?? ""
                }
                var safeSrc = src.trimmingCharacters(in: .whitespacesAndNewlines)
                if safeSrc.isEmpty { continue }
                if safeSrc.hasPrefix("//") { safeSrc = "https:" + safeSrc }
                let encodedSrc = safeSrc.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? safeSrc
                guard let streamURL = URL(string: encodedSrc, relativeTo: pageURL)?.absoluteURL else {
                    continue
                }

                let ext = streamURL.pathExtension.lowercased()
                let format: VideoFormat = (ext == "m3u8" || safeSrc.contains(".m3u8")) ? .hls : .mp4
                let label = (try? el.attr("label")) ?? (try? el.attr("title")) ?? "Direct"
                let quality = parseQuality(from: label + " " + safeSrc)

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

        // 2. Scan download mirror buttons (CartoonsArea Direct MP4, Pixeldrain, Gofile)
        if let linkElements = try? doc.select("a[href]") {
            for link in linkElements.array() {
                let href = (try? link.attr("href")) ?? ""
                let text = (try? link.text()) ?? ""
                var safeHref = href.trimmingCharacters(in: .whitespacesAndNewlines)
                if safeHref.isEmpty { continue }
                if safeHref.hasPrefix("//") { safeHref = "https:" + safeHref }
                let encodedHref = safeHref.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? safeHref
                guard let targetURL = URL(string: encodedHref, relativeTo: pageURL)?.absoluteURL else { continue }
                let host = targetURL.host?.lowercased() ?? ""

                var streamURL = targetURL
                var isDirect = false

                if host.contains("pixeldrain.com") {
                    let path = targetURL.path
                    if path.contains("/u/") {
                        let fileId = path.replacingOccurrences(of: "/u/", with: "")
                        if let apiURL = URL(string: "https://pixeldrain.com/api/file/\(fileId)") {
                            streamURL = apiURL
                            isDirect = true
                        }
                    }
                } else if isDirectMediaURL(targetURL) {
                    isDirect = true
                } else if host.contains("gofile.io") || host.contains("krakenfiles.com") {
                    isDirect = true
                } else {
                    continue
                }

                let parentText = (try? link.parent()?.text()) ?? ""
                let quality = parseQuality(from: parentText + " " + text + " " + safeHref)
                let name = host.replacingOccurrences(of: "www.", with: "").capitalized

                sources.append(VideoSource(
                    serverName: name.isEmpty ? "Direct MP4" : name,
                    quality: quality,
                    streamURL: streamURL,
                    referer: pageURL.absoluteString,
                    isDirectDownload: isDirect,
                    format: .mp4,
                    headers: [
                        "Referer": pageURL.absoluteString,
                        "User-Agent": desktopUA
                    ]
                ))
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

