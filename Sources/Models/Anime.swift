import Foundation

public struct Anime: Codable, Equatable {
    public let id: String
    public let title: String
    public let coverURL: String
    public let synopsis: String
    public let score: String
    public let status: String
    public let type: String
    public let genres: [String]
    public let detailURL: String
    public let sourceId: String
    public let totalEpisodes: Int?

    public init(
        id: String,
        title: String,
        coverURL: String,
        synopsis: String = "",
        score: String = "",
        status: String = "Unknown",
        type: String = "Anime",
        genres: [String] = [],
        detailURL: String,
        sourceId: String,
        totalEpisodes: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.synopsis = synopsis
        self.score = score
        self.status = status
        self.type = type
        self.genres = genres
        self.detailURL = detailURL
        self.sourceId = sourceId
        self.totalEpisodes = totalEpisodes
    }
}
