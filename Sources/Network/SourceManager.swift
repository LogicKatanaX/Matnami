import Foundation

public final class SourceManager {
    public static let shared = SourceManager()

    public private(set) var sources: [AnimeSourceConfig] = []
    public var activeSource: AnimeSourceConfig?

    private let userDefaultsKey = "com.matnami.saved_sources"
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
            // 3. Fallback hardcoded defaults
            self.sources = [
                AnimeSourceConfig(
                    id: "samehadaku",
                    name: "Samehadaku",
                    baseURL: "https://v2.samehadaku.how",
                    catalogPattern: "https://v2.samehadaku.how/daftar-anime-2/page/{page}/",
                    searchPattern: "https://v2.samehadaku.how/?s={query}",
                    cardSelector: ".animepost, .animpost, article.animpost",
                    linkSelector: "a[href*='/anime/'], .animposx a",
                    titleSelector: ".title, .tt h4, h2",
                    coverSelector: ".content-thumb img, img",
                    scoreSelector: ".score",
                    synopsisSelector: ".desc, .entry-content",
                    episodeListSelector: ".lstepsiode ul li, .episodelst ul li",
                    episodeLinkSelector: "a",
                    episodeTitleSelector: ".eps a, .title a, a",
                    playerIframeSelector: "#pembed iframe, .player-embed iframe",
                    serverItemSelector: ".server-item, .east_player_option",
                    ajaxAction: "player_ajax",
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

public extension Notification.Name {
    static let sourceDidChange = Notification.Name("com.matnami.sourceDidChange")
    static let sourcesDidUpdate = Notification.Name("com.matnami.sourcesDidUpdate")
}

