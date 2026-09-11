import Foundation

public struct ParsedTorrentMetadata {
    public let rawTitle: String
    public let releaseGroup: String?
    public let cleanTitle: String
    public let episodeString: String
    public let resolution: String
    public let codec: String
    public let audio: String
    public let container: String
    public let isMKV: Bool
    public let isMP4: Bool

    public init(
        rawTitle: String,
        releaseGroup: String? = nil,
        cleanTitle: String,
        episodeString: String = "1",
        resolution: String = "1080p",
        codec: String = "H.264",
        audio: String = "Sub",
        container: String = "MKV",
        isMKV: Bool = true,
        isMP4: Bool = false
    ) {
        self.rawTitle = rawTitle
        self.releaseGroup = releaseGroup
        self.cleanTitle = cleanTitle
        self.episodeString = episodeString
        self.resolution = resolution
        self.codec = codec
        self.audio = audio
        self.container = container
        self.isMKV = isMKV
        self.isMP4 = isMP4
    }
}

public final class TorrentTitleParser {

    public static func parse(_ raw: String) -> ParsedTorrentMetadata {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Detect Container
        let lower = str.lowercased()
        let isMP4 = lower.hasSuffix(".mp4") || lower.contains(".mp4")
        let isMKV = lower.hasSuffix(".mkv") || lower.contains(".mkv")
        let container = isMP4 ? "MP4" : (isMKV ? "MKV" : "Video")

        // 2. Detect Resolution
        var resolution = "1080p"
        if lower.contains("2160p") || lower.contains("4k") {
            resolution = "4K 2160p"
        } else if lower.contains("1080p") {
            resolution = "1080p"
        } else if lower.contains("720p") {
            resolution = "720p"
        } else if lower.contains("480p") {
            resolution = "480p"
        }

        // 3. Detect Codec
        var codec = "H.264"
        if lower.contains("x265") || lower.contains("hevc") || lower.contains("h.265") || lower.contains("h265") {
            codec = "HEVC x265"
        } else if lower.contains("av1") {
            codec = "AV1"
        } else if lower.contains("x264") || lower.contains("h.264") || lower.contains("avc") || lower.contains("h264") {
            codec = "AVC x264"
        }

        // 4. Detect Audio
        var audio = "Sub"
        if lower.contains("dual audio") || lower.contains("dual-audio") || lower.contains("multi-audio") {
            audio = "Dual Audio"
        } else if lower.contains("dub") || lower.contains("english dub") {
            audio = "English Dub"
        } else if lower.contains("sub") || lower.contains("multi-sub") {
            audio = "Subbed"
        }

        // 5. Extract Release Group (e.g. [SubsPlease] or [Judas])
        var releaseGroup: String? = nil
        if str.hasPrefix("["), let closingIdx = str.firstIndex(of: "]") {
            let start = str.index(after: str.startIndex)
            releaseGroup = String(str[start..<closingIdx]).trimmingCharacters(in: .whitespaces)
            str = String(str[str.index(after: closingIdx)...]).trimmingCharacters(in: .whitespaces)
        }

        // Remove trailing file extension
        if let dotIdx = str.range(of: ".", options: .backwards) {
            let ext = String(str[dotIdx.upperBound...]).lowercased()
            if ext == "mkv" || ext == "mp4" || ext == "avi" {
                str = String(str[..<dotIdx.lowerBound])
            }
        }

        // 6. Extract Episode number (e.g. - 01 or S01E02)
        var episodeStr = "1"
        if lower.contains("batch") || lower.contains("season") && !lower.contains("s0") {
            episodeStr = "Batch"
        } else {
            // Check for patterns like "- 05" or "E05"
            let patterns = [
                "-\\s*([0-9]{1,4})(?:v[0-9])?\\b",
                "[eE]([0-9]{1,3})\\b",
                "\\bEpisode\\s*([0-9]{1,3})\\b"
            ]
            for pat in patterns {
                if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
                   let match = regex.firstMatch(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count)) {
                    if let range = Range(match.range(at: 1), in: str) {
                        episodeStr = String(str[range])
                        break
                    }
                }
            }
        }

        // 7. Clean title (strip brackets like [1080p] or (1080p))
        var clean = str
        if let regex = try? NSRegularExpression(pattern: "\\[[^\\]]*\\]|\\([^\\)]*\\)", options: []) {
            clean = regex.stringByReplacingMatches(in: clean, options: [], range: NSRange(location: 0, length: clean.utf16.count), withTemplate: "")
        }

        // Strip "- 01" from title if present
        if let regex = try? NSRegularExpression(pattern: "-\\s*[0-9]{1,4}(?:v[0-9])?\\s*$", options: []) {
            clean = regex.stringByReplacingMatches(in: clean, options: [], range: NSRange(location: 0, length: clean.utf16.count), withTemplate: "")
        }

        clean = clean.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_ ")))
        if clean.isEmpty {
            clean = raw
        }

        return ParsedTorrentMetadata(
            rawTitle: raw,
            releaseGroup: releaseGroup,
            cleanTitle: clean,
            episodeString: episodeStr,
            resolution: resolution,
            codec: codec,
            audio: audio,
            container: container,
            isMKV: isMKV,
            isMP4: isMP4
        )
    }
}
