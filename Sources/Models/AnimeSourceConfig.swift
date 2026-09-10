import Foundation

public struct AnimeSourceConfig: Codable, Equatable {
    public let id: String
    public let name: String
    public let baseURL: String
    public let catalogPattern: String
    public let searchPattern: String
    public let cardSelector: String
    public let linkSelector: String
    public let titleSelector: String
    public let coverSelector: String
    public let scoreSelector: String?
    public let synopsisSelector: String?
    public let episodeListSelector: String
    public let episodeLinkSelector: String
    public let episodeTitleSelector: String
    public let playerIframeSelector: String?
    public let serverItemSelector: String?
    public let ajaxAction: String?
    public let useProxy: Bool

    public init(
        id: String,
        name: String,
        baseURL: String,
        catalogPattern: String,
        searchPattern: String,
        cardSelector: String,
        linkSelector: String,
        titleSelector: String,
        coverSelector: String,
        scoreSelector: String? = nil,
        synopsisSelector: String? = nil,
        episodeListSelector: String,
        episodeLinkSelector: String,
        episodeTitleSelector: String,
        playerIframeSelector: String? = nil,
        serverItemSelector: String? = nil,
        ajaxAction: String? = nil,
        useProxy: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.catalogPattern = catalogPattern
        self.searchPattern = searchPattern
        self.cardSelector = cardSelector
        self.linkSelector = linkSelector
        self.titleSelector = titleSelector
        self.coverSelector = coverSelector
        self.scoreSelector = scoreSelector
        self.synopsisSelector = synopsisSelector
        self.episodeListSelector = episodeListSelector
        self.episodeLinkSelector = episodeLinkSelector
        self.episodeTitleSelector = episodeTitleSelector
        self.playerIframeSelector = playerIframeSelector
        self.serverItemSelector = serverItemSelector
        self.ajaxAction = ajaxAction
        self.useProxy = useProxy
    }
}

