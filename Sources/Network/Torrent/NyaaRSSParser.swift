import Foundation

public struct TorrentItem: Codable, Equatable {
    public let title: String
    public let torrentURL: String
    public let guid: String
    public let pubDate: String
    public let seeders: Int
    public let leechers: Int
    public let downloads: Int
    public let infoHash: String
    public let category: String
    public let size: String
    public let magnetURI: String

    public init(
        title: String,
        torrentURL: String,
        guid: String,
        pubDate: String,
        seeders: Int,
        leechers: Int,
        downloads: Int,
        infoHash: String,
        category: String,
        size: String,
        magnetURI: String
    ) {
        self.title = title
        self.torrentURL = torrentURL
        self.guid = guid
        self.pubDate = pubDate
        self.seeders = seeders
        self.leechers = leechers
        self.downloads = downloads
        self.infoHash = infoHash
        self.category = category
        self.size = size
        self.magnetURI = magnetURI
    }
}

public final class NyaaRSSParser: NSObject, XMLParserDelegate {
    private var items: [TorrentItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentGuid = ""
    private var currentPubDate = ""
    private var currentSeeders = 0
    private var currentLeechers = 0
    private var currentDownloads = 0
    private var currentInfoHash = ""
    private var currentCategory = ""
    private var currentSize = ""
    private var isInsideItem = false

    public static func parse(data: Data) -> [TorrentItem] {
        let parserInstance = NyaaRSSParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parserInstance
        xmlParser.shouldProcessNamespaces = true
        xmlParser.parse()
        return parserInstance.items
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "item" {
            isInsideItem = true
            currentTitle = ""
            currentLink = ""
            currentGuid = ""
            currentPubDate = ""
            currentSeeders = 0
            currentLeechers = 0
            currentDownloads = 0
            currentInfoHash = ""
            currentCategory = ""
            currentSize = ""
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "guid":
            currentGuid += string
        case "pubdate":
            currentPubDate += string
        case "seeders":
            if let num = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                currentSeeders = num
            }
        case "leechers":
            if let num = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                currentLeechers = num
            }
        case "downloads":
            if let num = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                currentDownloads = num
            }
        case "infohash":
            currentInfoHash += string.trimmingCharacters(in: .whitespacesAndNewlines)
        case "category":
            currentCategory += string
        case "size":
            currentSize += string
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased() == "item" {
            let cleanTitle = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanLink = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanGuid = currentGuid.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanHash = currentInfoHash.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanSize = currentSize.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanCat = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines)

            var magnet = ""
            if !cleanHash.isEmpty {
                let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanTitle
                magnet = "magnet:?xt=urn:btih:\(cleanHash)&dn=\(encodedTitle)"
                magnet += "&tr=http%3A%2F%2Fnyaa.tracker.wf%3A7777%2Fannounce"
                magnet += "&tr=udp%3A%2F%2Fopen.stealth.si%3A80%2Fannounce"
                magnet += "&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce"
                magnet += "&tr=udp%3A%2F%2Fexodus.desync.com%3A6969%2Fannounce"
                magnet += "&tr=udp%3A%2F%2Ftracker.torrent.eu.org%3A451%2Fannounce"
            }

            let item = TorrentItem(
                title: cleanTitle,
                torrentURL: cleanLink,
                guid: cleanGuid,
                pubDate: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines),
                seeders: currentSeeders,
                leechers: currentLeechers,
                downloads: currentDownloads,
                infoHash: cleanHash,
                category: cleanCat,
                size: cleanSize,
                magnetURI: magnet
            )
            items.append(item)
            isInsideItem = false
        }
    }
}
