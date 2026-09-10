import Foundation
import SwiftSoup

public final class AnimeScraperEngine {
    public static let shared = AnimeScraperEngine()

    private let desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private var proxyBase: String {
        return AppSettings.shared.proxyBaseUrl
    }

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20.0
        config.timeoutIntervalForResource = 30.0
        self.session = URLSession(configuration: config)
    }

    private func makeURLRequest(url: URL, useProxy: Bool, referer: String? = nil) -> URLRequest {
        let targetURL: URL
        if useProxy {
            let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString
            targetURL = URL(string: proxyBase + encoded) ?? url
        } else {
            targetURL = url
        }

        var request = URLRequest(url: targetURL)
        request.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        if let referer = referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        return request
    }

    // MARK: - 1. Fetch Catalog
    public func fetchCatalog(source: AnimeSourceConfig, page: Int = 1, completion: @escaping (Result<[Anime], Error>) -> Void) {
        let pageStr = String(page)
        let formatted = source.catalogPattern.replacingOccurrences(of: "{page}", with: pageStr)
        guard let url = URL(string: formatted) else {
            completion(.failure(NSError(domain: "AnimeScraper", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid catalog URL"])))
            return
        }

        let request = makeURLRequest(url: url, useProxy: source.useProxy)
        session.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data, let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "AnimeScraper", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to decode catalog HTML"])))
                }
                return
            }

            do {
                let animeList = try self.parseAnimeList(html: html, baseURL: url, source: source)
                DispatchQueue.main.async { completion(.success(animeList)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    // MARK: - 2. Search Anime
    public func searchAnime(source: AnimeSourceConfig, query: String, completion: @escaping (Result<[Anime], Error>) -> Void) {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(.failure(NSError(domain: "AnimeScraper", code: 400, userInfo: [NSLocalizedDescriptionKey: "Query encoding failed"])))
            return
        }
        let formatted = source.searchPattern.replacingOccurrences(of: "{query}", with: encodedQuery)
        guard let url = URL(string: formatted) else {
            completion(.failure(NSError(domain: "AnimeScraper", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid search URL"])))
            return
        }

        let request = makeURLRequest(url: url, useProxy: source.useProxy)
        session.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data, let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "AnimeScraper", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to decode search HTML"])))
                }
                return
            }

            do {
                let animeList = try self.parseAnimeList(html: html, baseURL: url, source: source)
                DispatchQueue.main.async { completion(.success(animeList)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    private func parseAnimeList(html: String, baseURL: URL, source: AnimeSourceConfig) throws -> [Anime] {
        let doc = try SwiftSoup.parse(html, baseURL.absoluteString)
        let cards = try doc.select(source.cardSelector)
        var results: [Anime] = []

        for card in cards.array() {
            let linkEl = try? card.select(source.linkSelector).first()
            let titleEl = try? card.select(source.titleSelector).first()
            let coverEl = try? card.select(source.coverSelector).first()

            guard let rawHref = try? linkEl?.attr("href"), !rawHref.isEmpty,
                  let detailURL = URL(string: rawHref, relativeTo: baseURL)?.absoluteString else {
                continue
            }

            let title = (try? titleEl?.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Anime"
            var cover = (try? coverEl?.attr("src")) ?? ""
            if cover.isEmpty || cover.contains("data:image") {
                cover = (try? coverEl?.attr("data-src")) ?? (try? coverEl?.attr("data-lazy-src")) ?? ""
            }

            var score = ""
            if let scoreSel = source.scoreSelector, let sEl = try? card.select(scoreSel).first() {
                score = (try? sEl.text()) ?? ""
            }

            let id = "\(source.id)_\(abs(detailURL.hashValue))"
            results.append(Anime(
                id: id,
                title: title,
                coverURL: cover,
                score: score,
                detailURL: detailURL,
                sourceId: source.id
            ))
        }

        return results
    }

    // MARK: - 3. Fetch Anime Detail & Episodes
    public func fetchAnimeDetail(source: AnimeSourceConfig, anime: Anime, completion: @escaping (Result<(Anime, [Episode]), Error>) -> Void) {
        guard let url = URL(string: anime.detailURL) else {
            completion(.failure(NSError(domain: "AnimeScraper", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid anime detail URL"])))
            return
        }

        let request = makeURLRequest(url: url, useProxy: source.useProxy)
        session.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data, let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "AnimeScraper", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to decode detail HTML"])))
                }
                return
            }

            do {
                let doc = try SwiftSoup.parse(html, anime.detailURL)
                var synopsis = ""
                if let synSel = source.synopsisSelector, let synEl = try? doc.select(synSel).first() {
                    synopsis = (try? synEl.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }

                var genres: [String] = []
                if let genreElements = try? doc.select("a[href*='/genre/'], a[href*='/tag/'], .genre a").array() {
                    for g in genreElements {
                        if let text = try? g.text(), !text.isEmpty {
                            genres.append(text)
                        }
                    }
                }

                // Parse episodes
                let episodeItems = try doc.select(source.episodeListSelector)
                var episodes: [Episode] = []

                for (idx, item) in episodeItems.array().enumerated() {
                    let linkEl = try? item.select(source.episodeLinkSelector).first()
                    let titleEl = try? item.select(source.episodeTitleSelector).first()

                    guard let rawHref = try? linkEl?.attr("href"), !rawHref.isEmpty,
                          let epURL = URL(string: rawHref, relativeTo: url)?.absoluteString else {
                        continue
                    }

                    let title = (try? titleEl?.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Episode \(idx + 1)"
                    let epId = "\(anime.id)_ep_\(idx + 1)"
                    episodes.append(Episode(
                        id: epId,
                        animeId: anime.id,
                        number: "\(idx + 1)",
                        title: title,
                        episodeURL: epURL,
                        sourceId: source.id
                    ))
                }

                let updatedAnime = Anime(
                    id: anime.id,
                    title: anime.title,
                    coverURL: anime.coverURL,
                    synopsis: synopsis.isEmpty ? anime.synopsis : synopsis,
                    score: anime.score,
                    status: anime.status,
                    type: anime.type,
                    genres: genres.isEmpty ? anime.genres : genres,
                    detailURL: anime.detailURL,
                    sourceId: anime.sourceId,
                    totalEpisodes: episodes.count
                )

                DispatchQueue.main.async {
                    completion(.success((updatedAnime, episodes)))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    // MARK: - 4. Fetch Episode Video Sources & Resolvers
    public func fetchEpisodeSources(source: AnimeSourceConfig, episode: Episode, completion: @escaping (Result<[VideoSource], Error>) -> Void) {
        guard let url = URL(string: episode.episodeURL) else {
            completion(.failure(NSError(domain: "AnimeScraper", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid episode URL"])))
            return
        }

        let request = makeURLRequest(url: url, useProxy: source.useProxy)
        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data, let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "AnimeScraper", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to decode episode HTML"])))
                }
                return
            }

            var videoSources: [VideoSource] = []

            // 1. Direct MP4 and mirror resolution from the episode page
            let directSources = DirectMP4Resolver.shared.resolveFromHTML(html, pageURL: url)
            videoSources.append(contentsOf: directSources)

            // 2. Parse iframe player embeds
            if let doc = try? SwiftSoup.parse(html, episode.episodeURL) {
                let iframeSelector = source.playerIframeSelector ?? "iframe[src]"
                if let iframes = try? doc.select(iframeSelector) {
                    for iframe in iframes.array() {
                        var src = (try? iframe.attr("src")) ?? ""
                        if src.isEmpty {
                            src = (try? iframe.attr("data-src")) ?? ""
                        }
                        guard !src.isEmpty, let iframeURL = URL(string: src, relativeTo: url)?.absoluteURL else {
                            continue
                        }

                        // Streamtape
                        if StreamtapeResolver.shared.canHandle(url: iframeURL) {
                            if let resolved = self.resolveStreamtapeSync(iframeURL: iframeURL) {
                                videoSources.append(resolved)
                            }
                        } else if FilemoonResolver.shared.canHandle(url: iframeURL) {
                            if let resolved = self.resolveFilemoonSync(iframeURL: iframeURL) {
                                videoSources.append(resolved)
                            }
                        } else if DirectMP4Resolver.shared.isDirectMediaURL(iframeURL) {
                            videoSources.append(VideoSource(
                                serverName: iframeURL.host ?? "Player",
                                quality: .normal720p,
                                streamURL: iframeURL,
                                referer: episode.episodeURL,
                                isDirectDownload: iframeURL.pathExtension.lowercased() == "mp4",
                                format: iframeURL.pathExtension.lowercased() == "m3u8" ? .hls : .mp4,
                                headers: ["Referer": episode.episodeURL]
                            ))
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                completion(.success(videoSources))
            }
        }.resume()
    }

    private func resolveStreamtapeSync(iframeURL: URL) -> VideoSource? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: VideoSource?
        let req = makeURLRequest(url: iframeURL, useProxy: false, referer: iframeURL.absoluteString)

        session.dataTask(with: req) { data, _, _ in
            if let data = data, let html = String(data: data, encoding: .utf8) {
                result = StreamtapeResolver.shared.resolve(html: html, pageURL: iframeURL)
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 5.0)
        return result
    }

    private func resolveFilemoonSync(iframeURL: URL) -> VideoSource? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: VideoSource?
        let req = makeURLRequest(url: iframeURL, useProxy: false, referer: iframeURL.absoluteString)

        session.dataTask(with: req) { data, _, _ in
            if let data = data, let html = String(data: data, encoding: .utf8) {
                result = FilemoonResolver.shared.resolve(html: html, pageURL: iframeURL)
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 5.0)
        return result
    }
}

