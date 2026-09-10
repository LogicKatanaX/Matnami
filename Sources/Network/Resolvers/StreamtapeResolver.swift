import Foundation
import SwiftSoup

public final class StreamtapeResolver {
    public static let shared = StreamtapeResolver()

    private let desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private init() {}

    public func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("streamtape.com") || host.contains("streamta.pe") || host.contains("tapecontent.net")
    }

    /// Resolves direct stream URL from Streamtape HTML
    public func resolve(html: String, pageURL: URL) -> VideoSource? {
        // Pattern 1: Direct robotlink element
        if let doc = try? SwiftSoup.parse(html, pageURL.absoluteString),
           let el = try? doc.select("#robotlink, #ideoolink").first(),
           let text = try? el.text(), !text.isEmpty {
            let full = text.hasPrefix("//") ? "https:" + text : text
            if let url = URL(string: full) {
                return VideoSource(
                    serverName: "Streamtape",
                    quality: .normal720p,
                    streamURL: url,
                    referer: pageURL.absoluteString,
                    isDirectDownload: true,
                    format: .mp4,
                    headers: [
                        "Referer": pageURL.absoluteString,
                        "User-Agent": desktopUA
                    ]
                )
            }
        }

        // Pattern 2: Script token extraction
        // document.getElementById('robotlink').innerHTML = '//streamtape.com/get_video?' + ... + '&token=...'
        let pattern = #"document\.getElementById\(['"]robotlink['"]\)\.innerHTML\s*=\s*['"]([^'"]+)['"]\s*\+\s*\('([^']+)'\.substring\(\d+\)\)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: html.utf16.count)
            if let match = regex.firstMatch(in: html, options: [], range: range) {
                if let r1 = Range(match.range(at: 1), in: html),
                   let r2 = Range(match.range(at: 2), in: html) {
                    let part1 = String(html[r1])
                    let part2 = String(html[r2])
                    let full = "https:" + part1 + part2
                    if let url = URL(string: full) {
                        return VideoSource(
                            serverName: "Streamtape",
                            quality: .normal720p,
                            streamURL: url,
                            referer: pageURL.absoluteString,
                            isDirectDownload: true,
                            format: .mp4,
                            headers: [
                                "Referer": pageURL.absoluteString,
                                "User-Agent": desktopUA
                            ]
                        )
                    }
                }
            }
        }

        return nil
    }
}

