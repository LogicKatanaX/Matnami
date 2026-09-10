import Foundation

public final class FilemoonResolver {
    public static let shared = FilemoonResolver()

    private let desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private init() {}

    public func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("filemoon.sx") || host.contains("filemoon.to") || host.contains("filemoon.me")
    }

    /// Unpacks Dean Edwards packed javascript
    public func unpackPackedJS(_ packed: String) -> String {
        let pattern = #"\}\('(.*)',\s*(\d+),\s*(\d+),\s*'([^']+)'\.split\('\|'\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: packed, options: [], range: NSRange(location: 0, length: packed.utf16.count)) else {
            return packed
        }

        guard let payloadRange = Range(match.range(at: 1), in: packed),
              let radixRange = Range(match.range(at: 2), in: packed),
              let symtabRange = Range(match.range(at: 4), in: packed) else {
            return packed
        }

        let payload = String(packed[payloadRange])
        let radix = Int(packed[radixRange]) ?? 10
        let syms = packed[symtabRange].components(separatedBy: "|")

        let wordRegex = try? NSRegularExpression(pattern: #"\b\w+\b"#, options: [])
        guard let wordRegex = wordRegex else { return payload }

        let nsPayload = payload as NSString
        let matches = wordRegex.matches(in: payload, options: [], range: NSRange(location: 0, length: payload.utf16.count))

        var result = payload
        // Replace from end to beginning to preserve character indexes
        for m in matches.reversed() {
            let word = nsPayload.substring(with: m.range)
            var index = -1
            if let val = Int(word, radix: radix) {
                index = val
            }
            if index >= 0 && index < syms.count && !syms[index].isEmpty {
                if let swiftRange = Range(m.range, in: result) {
                    result.replaceSubrange(swiftRange, with: syms[index])
                }
            }
        }

        return result
    }

    /// Resolves direct stream URL from Filemoon HTML or packed JS
    public func resolve(html: String, pageURL: URL) -> VideoSource? {
        let unpacked = unpackPackedJS(html)

        // Find .m3u8 or .mp4 inside unpacked or raw HTML
        let sourcePattern = #"['"](https?://[^'"]+?\.(?:m3u8|mp4)[^'"]*?)['"]"#
        guard let regex = try? NSRegularExpression(pattern: sourcePattern, options: .caseInsensitive) else {
            return nil
        }

        let searchSpace = unpacked + "\n" + html
        let range = NSRange(location: 0, length: searchSpace.utf16.count)
        if let match = regex.firstMatch(in: searchSpace, options: [], range: range),
           let urlRange = Range(match.range(at: 1), in: searchSpace) {
            let streamStr = String(searchSpace[urlRange])
            if let streamURL = URL(string: streamStr) {
                let isHLS = streamStr.contains(".m3u8")
                return VideoSource(
                    serverName: "Filemoon",
                    quality: .normal720p,
                    streamURL: streamURL,
                    referer: pageURL.absoluteString,
                    isDirectDownload: !isHLS,
                    format: isHLS ? .hls : .mp4,
                    headers: [
                        "Referer": pageURL.absoluteString,
                        "User-Agent": desktopUA
                    ]
                )
            }
        }

        return nil
    }
}
