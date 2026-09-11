import Foundation

public struct ToshoItem: Codable, Equatable {
    public let id: Int
    public let title: String
    public let link: String
    public let timestamp: Int?
    public let nyaaId: Int?
    public let torrentURL: String?
    public let infoHash: String?
    public let magnetURI: String?
    public let seeders: Int?
    public let leechers: Int?
    public let totalSize: Int64?
    public let numFiles: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case link
        case timestamp
        case nyaaId = "nyaa_id"
        case torrentURL = "torrent_url"
        case infoHash = "info_hash"
        case magnetURI = "magnet_uri"
        case seeders
        case leechers
        case totalSize = "total_size"
        case numFiles = "num_files"
    }

    public var formattedSize: String {
        guard let bytes = totalSize, bytes > 0 else { return "Unknown size" }
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        if gb >= 1.0 {
            return String(format: "%.1f GiB", gb)
        }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.1f MiB", mb)
    }
}

public final class AnimeToshoClient {
    public static let shared = AnimeToshoClient()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        self.session = URLSession(configuration: config)
    }

    public func fetchFeed(query: String? = nil, completion: @escaping (Result<[ToshoItem], Error>) -> Void) {
        var urlString = "https://feed.animetosho.org/json"
        if let q = query, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            urlString += "?q=\(encoded)"
        }

        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "AnimeTosho", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Matnami/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "AnimeTosho", code: 500, userInfo: [NSLocalizedDescriptionKey: "Empty response data"])))
                }
                return
            }

            do {
                let items = try JSONDecoder().decode([ToshoItem].self, from: data)
                DispatchQueue.main.async { completion(.success(items)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
}
