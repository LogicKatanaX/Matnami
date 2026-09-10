import Foundation

public struct Episode: Codable, Equatable {
    public let id: String
    public let animeId: String
    public let number: String
    public let title: String
    public let episodeURL: String
    public let uploadDate: String?
    public let sourceId: String

    public init(
        id: String,
        animeId: String,
        number: String,
        title: String,
        episodeURL: String,
        uploadDate: String? = nil,
        sourceId: String
    ) {
        self.id = id
        self.animeId = animeId
        self.number = number
        self.title = title
        self.episodeURL = episodeURL
        self.uploadDate = uploadDate
        self.sourceId = sourceId
    }
}

