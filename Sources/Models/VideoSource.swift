import Foundation

public enum VideoQuality: String, Codable, CaseIterable {
    case compact480p = "480p"
    case normal720p = "720p"
    case high1080p = "1080p"
    case auto = "Auto"

    public var displayName: String {
        switch self {
        case .compact480p: return "480p (Data Saver)"
        case .normal720p: return "720p (Recommended)"
        case .high1080p: return "1080p (Full HD)"
        case .auto: return "Auto (Adaptive)"
        }
    }
}

public enum VideoFormat: String, Codable {
    case mp4 = "mp4"
    case hls = "m3u8"
}

public struct VideoSource: Codable, Equatable {
    public let serverName: String
    public let quality: VideoQuality
    public let streamURL: URL
    public let referer: String
    public let isDirectDownload: Bool
    public let format: VideoFormat
    public let headers: [String: String]

    public init(
        serverName: String,
        quality: VideoQuality = .normal720p,
        streamURL: URL,
        referer: String = "",
        isDirectDownload: Bool = false,
        format: VideoFormat = .mp4,
        headers: [String: String] = [:]
    ) {
        self.serverName = serverName
        self.quality = quality
        self.streamURL = streamURL
        self.referer = referer
        self.isDirectDownload = isDirectDownload
        self.format = format
        self.headers = headers
    }

    /// Returns HTTP headers required for AVURLAsset and URLSession on iOS 12
    public var effectiveHeaders: [String: String] {
        var dict = headers
        if !referer.isEmpty && dict["Referer"] == nil {
            dict["Referer"] = referer
        }
        if dict["User-Agent"] == nil {
            dict["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        if dict["Accept"] == nil {
            dict["Accept"] = "*/*"
        }
        return dict
    }
}
