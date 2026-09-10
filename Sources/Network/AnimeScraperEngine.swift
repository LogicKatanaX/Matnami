import Foundation
import SwiftSoup

public final class AnimeScraperEngine {
    public static let shared = AnimeScraperEngine()

    private let desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    public static let proxyBase = "https://manga-proxy.santamcyber.workers.dev/?url="

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20.0
        config.timeoutIntervalForResource = 30.0
        self.session = URLSession(configuration: config)
    }

    /// Wraps any URL through the Cloudflare Edge Worker reverse proxy (always-on architecture)
    public static func proxiedURL(for url: URL) -> URL {
        if url.absoluteString.hasPrefix(proxyBase) || url.isFileURL {
            return url
        }
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString
        return URL(string: proxyBase + encoded) ?? url
    }

    private func makeURLRequest(url: URL, useProxy: Bool = false, referer: String? = nil) -> URLRequest {
        let targetURL = useProxy ? AnimeScraperEngine.proxiedURL(for: url) : url
        var request = URLRequest(url: targetURL)
        request.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        if let referer = referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        return request
    }

    private func makePOSTRequest(url: URL, bodyData: Data, useProxy: Bool = false, referer: String? = nil) -> URLRequest {
        let targetURL = useProxy ? AnimeScraperEngine.proxiedURL(for: url) : url
        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
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
            var linkEl = try? card.select(source.linkSelector).first()
            if let el = linkEl, let href = try? el.attr("href"), href.contains("/genre/") || href.contains("/tag/") {
                if let betterLink = try? card.select("a[href*='/anime/'], a[href*='/watch/'], a[href*='/series/'], a[href*='-Videos/'], .animposx a").first() {
                    linkEl = betterLink
                }
            }

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

                if episodes.isEmpty {
                    episodes.append(Episode(
                        id: "\(anime.id)_ep_1",
                        animeId: anime.id,
                        number: "1",
                        title: anime.title,
                        episodeURL: anime.detailURL,
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
            let lock = NSLock()

            // 1. Direct MP4 and mirror resolution from the episode page (e.g. CartoonsArea direct MP4, Pixeldrain)
            let directSources = DirectMP4Resolver.shared.resolveFromHTML(html, pageURL: url)
            videoSources.append(contentsOf: directSources)

            guard let doc = try? SwiftSoup.parse(html, episode.episodeURL) else {
                DispatchQueue.main.async { completion(.success(videoSources)) }
                return
            }

            // 2. Parse server options / AJAX player options (e.g. Samehadaku east_player_option)
            let serverSelector = source.serverItemSelector ?? ".server-item, .east_player_option, [data-post]"
            let serverElements = (try? doc.select(serverSelector)) ?? Elements()

            let group = DispatchGroup()

            for serverEl in serverElements.array() {
                guard let post = try? serverEl.attr("data-post"), !post.isEmpty else { continue }
                let nume = (try? serverEl.attr("data-nume")) ?? "1"
                let type = (try? serverEl.attr("data-type")) ?? "schtml"
                let serverTitle = ((try? serverEl.text()) ?? "Server \(nume)").trimmingCharacters(in: .whitespacesAndNewlines)

                let lower = serverTitle.lowercased()
                if lower.contains("chat") || lower.contains("discord") || lower.contains("komentar") {
                    continue
                }

                let quality: VideoQuality
                if lower.contains("1080") {
                    quality = .high1080p
                } else if lower.contains("720") {
                    quality = .normal720p
                } else if lower.contains("480") || lower.contains("360") {
                    quality = .compact480p
                } else {
                    quality = .normal720p
                }

                let cleanBase = source.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let ajaxEndpoint = "\(cleanBase)/wp-admin/admin-ajax.php"
                guard let ajaxURL = URL(string: ajaxEndpoint) else { continue }

                let formBody = "action=\(source.ajaxAction ?? "player_ajax")&post=\(post)&nume=\(nume)&type=\(type)"
                guard let bodyData = formBody.data(using: .utf8) else { continue }

                let ajaxReq = self.makePOSTRequest(url: ajaxURL, bodyData: bodyData, useProxy: source.useProxy, referer: episode.episodeURL)

                group.enter()
                self.session.dataTask(with: ajaxReq) { ajaxData, _, _ in
                    defer { group.leave() }
                    guard let ajaxData = ajaxData,
                          let rawResp = String(data: ajaxData, encoding: .utf8) else { return }

                    if let parsed = self.extractStreamFromAJAX(html: rawResp, pageURL: episode.episodeURL) {
                        let finalStreamURL = source.useProxy ? AnimeScraperEngine.proxiedURL(for: parsed.url) : parsed.url
                        let vs = VideoSource(
                            serverName: serverTitle,
                            quality: quality,
                            streamURL: finalStreamURL,
                            referer: episode.episodeURL,
                            isDirectDownload: parsed.isDirect,
                            format: .mp4,
                            headers: [
                                "Referer": episode.episodeURL,
                                "User-Agent": self.desktopUA
                            ]
                        )
                        lock.lock()
                        if !videoSources.contains(where: { $0.streamURL == finalStreamURL }) {
                            videoSources.append(vs)
                        }
                        lock.unlock()
                    }
                }.resume()
            }

            // 3. Parse direct static iframes (for non-AJAX sources)
            let iframeSelector = source.playerIframeSelector ?? "iframe[src]"
            if let iframes = try? doc.select(iframeSelector) {
                for iframe in iframes.array() {
                    var src = (try? iframe.attr("src")) ?? ""
                    if src.isEmpty { src = (try? iframe.attr("data-src")) ?? "" }
                    guard !src.isEmpty, let iframeURL = URL(string: src, relativeTo: url)?.absoluteURL else { continue }

                    if StreamtapeResolver.shared.canHandle(url: iframeURL) {
                        if let resolved = self.resolveStreamtapeSync(iframeURL: iframeURL) {
                            lock.lock()
                            videoSources.append(resolved)
                            lock.unlock()
                        }
                    } else if FilemoonResolver.shared.canHandle(url: iframeURL) {
                        if let resolved = self.resolveFilemoonSync(iframeURL: iframeURL) {
                            lock.lock()
                            videoSources.append(resolved)
                            lock.unlock()
                        }
                    } else if DirectMP4Resolver.shared.isDirectMediaURL(iframeURL) {
                        let isHLS = iframeURL.pathExtension.lowercased() == "m3u8"
                        let finalURL = source.useProxy ? AnimeScraperEngine.proxiedURL(for: iframeURL) : iframeURL
                        lock.lock()
                        videoSources.append(VideoSource(
                            serverName: iframeURL.host ?? "Player",
                            quality: .normal720p,
                            streamURL: finalURL,
                            referer: episode.episodeURL,
                            isDirectDownload: !isHLS,
                            format: isHLS ? .hls : .mp4,
                            headers: ["Referer": episode.episodeURL]
                        ))
                        lock.unlock()
                    }
                }
            }

            // Wait up to 5 seconds for background AJAX server resolution before returning
            DispatchQueue.global(qos: .userInitiated).async {
                _ = group.wait(timeout: .now() + 5.0)
                DispatchQueue.main.async {
                    completion(.success(videoSources))
                }
            }
        }.resume()
    }

    /// Extracts direct MP4 or stream URL from WordPress AJAX response (cleans malformed tags)
    private func extractStreamFromAJAX(html: String, pageURL: String) -> (url: URL, isDirect: Bool)? {
        // 1. Clean malformed closing tags inside quotes from CMS typos
        var cleaned = html.replacingOccurrences(of: "\\/", with: "/")
        if let regexIframe = try? NSRegularExpression(pattern: #"\"\s*(?:FRAMEBORDER=[^>]*|frameborder=[^>]*)\s*></iframe>"#, options: .caseInsensitive) {
            let ns = cleaned as NSString
            cleaned = regexIframe.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }
        if let regexIframe2 = try? NSRegularExpression(pattern: #"\"[^>]*></iframe>"#, options: .caseInsensitive) {
            let ns = cleaned as NSString
            cleaned = regexIframe2.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "\"></iframe>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\">", with: "")

        // 2. Direct MP4 link in cleaned text (e.g. s0.wibufile.com)
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\s"'<>\\]+\.mp4[^\s"'<>\\]*"#, options: .caseInsensitive) {
            let nsStr = cleaned as NSString
            if let match = regex.firstMatch(in: cleaned, options: [], range: NSRange(location: 0, length: nsStr.length)) {
                var urlStr = nsStr.substring(with: match.range)
                urlStr = urlStr.trimmingCharacters(in: CharacterSet(charactersIn: "\"]'"))
                if let directURL = URL(string: urlStr) {
                    return (directURL, true)
                }
            }
        }

        // 3. Iframe embed (e.g. Blogger, Streamtape, Gogo)
        if let doc = try? SwiftSoup.parse(html, pageURL),
           let iframe = try? doc.select("iframe[src]").first(),
           let src = try? iframe.attr("src"),
           let iframeURL = URL(string: src) {
            return (iframeURL, false)
        }

        // 4. Fallback search for any media URL
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\s"'<>\\]+(?:\.m3u8|video\.g\?token=[^\s"'<>\\]+)"#, options: .caseInsensitive) {
            let nsStr = cleaned as NSString
            if let match = regex.firstMatch(in: cleaned, options: [], range: NSRange(location: 0, length: nsStr.length)) {
                let urlStr = nsStr.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: "\"]'"))
                if let foundURL = URL(string: urlStr) {
                    return (foundURL, false)
                }
            }
        }

        return nil
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

