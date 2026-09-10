import Foundation

public enum DownloadState: String, Codable {
    case queued
    case downloading
    case paused
    case completed
    case failed

    public var statusDescription: String {
        switch self {
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Downloaded"
        case .failed: return "Failed"
        }
    }
}

public struct DownloadItem: Codable, Equatable {
    public let id: String
    public let episodeId: String
    public let animeId: String
    public let animeTitle: String
    public let episodeNumber: String
    public let episodeTitle: String
    public let coverURL: String?
    public let streamURL: String
    public let serverName: String
    public let quality: String
    public let localFileName: String
    public var state: DownloadState
    public var progress: Float
    public var bytesDownloaded: Int64
    public var totalBytes: Int64
    public let createdAt: Date
    public var completedAt: Date?
    public var errorMessage: String?

    public init(
        id: String,
        episodeId: String,
        animeId: String,
        animeTitle: String,
        episodeNumber: String,
        episodeTitle: String,
        coverURL: String? = nil,
        streamURL: String,
        serverName: String = "Default",
        quality: String = "720p",
        localFileName: String,
        state: DownloadState = .queued,
        progress: Float = 0.0,
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64 = 0,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.episodeId = episodeId
        self.animeId = animeId
        self.animeTitle = animeTitle
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.coverURL = coverURL
        self.streamURL = streamURL
        self.serverName = serverName
        self.quality = quality
        self.localFileName = localFileName
        self.state = state
        self.progress = progress
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }

    public var formattedSize: String {
        if totalBytes > 0 {
            let downloadedMB = Double(bytesDownloaded) / (1024 * 1024)
            let totalMB = Double(totalBytes) / (1024 * 1024)
            return String(format: "%.1f / %.1f MB", downloadedMB, totalMB)
        } else if bytesDownloaded > 0 {
            let downloadedMB = Double(bytesDownloaded) / (1024 * 1024)
            return String(format: "%.1f MB", downloadedMB)
        } else {
            return "0 MB"
        }
    }
}
