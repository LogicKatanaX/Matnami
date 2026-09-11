import Foundation

public final class SourceManager {
    public static let shared = SourceManager()

    public private(set) var sources: [AnimeSourceConfig] = []
    public var activeSource: AnimeSourceConfig?

    private let userDefaultsKey = "com.matnami.saved_sources_v3"
    private let activeSourceIdKey = "com.matnami.active_source_id"

    private init() {
        loadSources()
    }

    public func loadSources() {
        // 1. Try loading from UserDefaults (OTA cache)
        if let savedData = UserDefaults.standard.data(forKey: userDefaultsKey),
           let savedList = try? JSONDecoder().decode([AnimeSourceConfig].self, from: savedData),
           !savedList.isEmpty {
            self.sources = savedList
        } else if let bundleURL = Bundle.main.url(forResource: "sources", withExtension: "json"),
                  let bundleData = try? Data(contentsOf: bundleURL),
                  let bundleList = try? JSONDecoder().decode([AnimeSourceConfig].self, from: bundleData) {
            // 2. Fallback to bundled sources.json
            self.sources = bundleList
        } else {
            // 3. Fallback hardcoded defaults (Nyaa & AnimeTosho)
            self.sources = [
                AnimeSourceConfig(
                    id: "nyaa_en",
                    name: "Nyaa (Anime - English)",
                    baseURL: "https://nyaa.si",
                    catalogPattern: "https://nyaa.si/?page=rss&c=1_2",
                    searchPattern: "https://nyaa.si/?page=rss&q={query}&c=1_2",
                    cardSelector: "item",
                    linkSelector: "link",
                    titleSelector: "title",
                    coverSelector: "",
                    scoreSelector: nil,
                    synopsisSelector: "description",
                    episodeListSelector: "item",
                    episodeLinkSelector: "link",
                    episodeTitleSelector: "title",
                    playerIframeSelector: nil,
                    serverItemSelector: nil,
                    ajaxAction: nil,
                    useProxy: false
                ),
                AnimeSourceConfig(
                    id: "animetosho",
                    name: "AnimeTosho (Torrents & Mirrors)",
                    baseURL: "https://animetosho.org",
                    catalogPattern: "https://feed.animetosho.org/json",
                    searchPattern: "https://feed.animetosho.org/json?q={query}",
                    cardSelector: "",
                    linkSelector: "",
                    titleSelector: "",
                    coverSelector: "",
                    scoreSelector: nil,
                    synopsisSelector: nil,
                    episodeListSelector: "",
                    episodeLinkSelector: "",
                    episodeTitleSelector: "",
                    playerIframeSelector: nil,
                    serverItemSelector: nil,
                    ajaxAction: nil,
                    useProxy: false
                ),
                AnimeSourceConfig(
                    id: "nyaa_all",
                    name: "Nyaa (All Anime)",
                    baseURL: "https://nyaa.si",
                    catalogPattern: "https://nyaa.si/?page=rss&c=1_0",
                    searchPattern: "https://nyaa.si/?page=rss&q={query}&c=1_0",
                    cardSelector: "item",
                    linkSelector: "link",
                    titleSelector: "title",
                    coverSelector: "",
                    scoreSelector: nil,
                    synopsisSelector: "description",
                    episodeListSelector: "item",
                    episodeLinkSelector: "link",
                    episodeTitleSelector: "title",
                    playerIframeSelector: nil,
                    serverItemSelector: nil,
                    ajaxAction: nil,
                    useProxy: false
                ),
                AnimeSourceConfig(
                    id: "sukebei",
                    name: "Sukebei (18+ NSFW)",
                    baseURL: "https://sukebei.nyaa.si",
                    catalogPattern: "https://sukebei.nyaa.si/?page=rss&c=1_1",
                    searchPattern: "https://sukebei.nyaa.si/?page=rss&q={query}&c=1_1",
                    cardSelector: "item",
                    linkSelector: "link",
                    titleSelector: "title",
                    coverSelector: "",
                    scoreSelector: nil,
                    synopsisSelector: "description",
                    episodeListSelector: "item",
                    episodeLinkSelector: "link",
                    episodeTitleSelector: "title",
                    playerIframeSelector: nil,
                    serverItemSelector: nil,
                    ajaxAction: nil,
                    useProxy: false
                )
            ]
        }

        // Restore active source
        let savedActiveId = UserDefaults.standard.string(forKey: activeSourceIdKey)
        self.activeSource = sources.first(where: { $0.id == savedActiveId }) ?? sources.first
    }

    public func setActiveSource(id: String) {
        if let found = sources.first(where: { $0.id == id }) {
            self.activeSource = found
            UserDefaults.standard.set(id, forKey: activeSourceIdKey)
            NotificationCenter.default.post(name: .sourceDidChange, object: found)
        }
    }

    /// Adds or updates a custom anime source and persists to disk
    public func addSource(_ config: AnimeSourceConfig, makeActive: Bool = true) {
        if let idx = sources.firstIndex(where: { $0.id == config.id }) {
            sources[idx] = config
        } else {
            sources.append(config)
        }
        saveSourcesToDisk()
        if makeActive {
            setActiveSource(id: config.id)
        } else {
            NotificationCenter.default.post(name: .sourcesDidUpdate, object: sources)
        }
    }

    /// Removes a custom source if more than one source exists
    public func deleteSource(id: String) -> Bool {
        guard sources.count > 1 else { return false }
        guard let idx = sources.firstIndex(where: { $0.id == id }) else { return false }
        sources.remove(at: idx)
        saveSourcesToDisk()
        if activeSource?.id == id {
            if let first = sources.first {
                setActiveSource(id: first.id)
            }
        } else {
            NotificationCenter.default.post(name: .sourcesDidUpdate, object: sources)
        }
        return true
    }

    /// Imports a source or list of sources from a JSON string
    public func importSource(from jsonString: String) throws -> AnimeSourceConfig {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "SourceManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid text encoding"])
        }
        let decoder = JSONDecoder()
        if let single = try? decoder.decode(AnimeSourceConfig.self, from: data) {
            addSource(single, makeActive: true)
            return single
        } else if let list = try? decoder.decode([AnimeSourceConfig].self, from: data), let first = list.first {
            for s in list {
                addSource(s, makeActive: false)
            }
            setActiveSource(id: first.id)
            return first
        } else {
            throw NSError(domain: "SourceManager", code: 422, userInfo: [NSLocalizedDescriptionKey: "JSON does not match AnimeSourceConfig schema"])
        }
    }

    /// Saves the current list of sources to UserDefaults
    private func saveSourcesToDisk() {
        if let data = try? JSONEncoder().encode(sources) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    /// Live test of source catalog extraction and connectivity
    public func testSourceConnection(_ config: AnimeSourceConfig, completion: @escaping (Result<SourceTestSummary, Error>) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()
        AnimeScraperEngine.shared.fetchCatalog(source: config, page: 1) { result in
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            switch result {
            case .success(let animes):
                let sampleTitle = animes.first?.title ?? "No anime cards found"
                let firstURL = animes.first?.detailURL ?? "N/A"
                let summary = SourceTestSummary(
                    sourceName: config.name,
                    latencyMs: latencyMs,
                    itemsFound: animes.count,
                    sampleTitle: sampleTitle,
                    firstAnimeURL: firstURL,
                    isProxyUsed: config.useProxy
                )
                DispatchQueue.main.async { completion(.success(summary)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Resets sources to bundled defaults and clears cached OTA configurations
    public func resetToDefaultSources() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: activeSourceIdKey)
        loadSources()
        if let first = sources.first {
            self.activeSource = first
            NotificationCenter.default.post(name: .sourceDidChange, object: first)
        }
    }

    /// Fetches OTA source definitions from a GitHub Gist or raw JSON endpoint
    public func syncOTA(from urlString: String, completion: @escaping (Result<Int, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "SourceManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid OTA URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15.0

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "SourceManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Empty response data"])))
                }
                return
            }

            do {
                let updatedSources = try JSONDecoder().decode([AnimeSourceConfig].self, from: data)
                guard !updatedSources.isEmpty else {
                    throw NSError(domain: "SourceManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "No sources parsed"])
                }

                self.sources = updatedSources
                UserDefaults.standard.set(data, forKey: self.userDefaultsKey)

                // Revalidate active source
                if let currentActive = self.activeSource,
                   let updatedActive = updatedSources.first(where: { $0.id == currentActive.id }) {
                    self.activeSource = updatedActive
                } else {
                    self.activeSource = updatedSources.first
                }

                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .sourcesDidUpdate, object: updatedSources)
                    completion(.success(updatedSources.count))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
}

public struct SourceTestSummary {
    public let sourceName: String
    public let latencyMs: Int
    public let itemsFound: Int
    public let sampleTitle: String
    public let firstAnimeURL: String
    public let isProxyUsed: Bool
}

public extension Notification.Name {
    static let sourceDidChange = Notification.Name("com.matnami.sourceDidChange")
    static let sourcesDidUpdate = Notification.Name("com.matnami.sourcesDidUpdate")
}

