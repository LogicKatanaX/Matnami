import Foundation

public struct KitsuAnimeMeta {
    public let posterURL: String?
    public let synopsis: String?
    public let score: String?
}

public final class KitsuMetadataService {
    public static let shared = KitsuMetadataService()

    private var cache: [String: KitsuAnimeMeta] = [:]
    private let lock = NSLock()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        self.session = URLSession(configuration: config)
    }

    public func fetchMetadata(for title: String, completion: @escaping (KitsuAnimeMeta?) -> Void) {
        let cleanKey = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanKey.isEmpty {
            completion(nil)
            return
        }

        lock.lock()
        if let cached = cache[cleanKey] {
            lock.unlock()
            completion(cached)
            return
        }
        lock.unlock()

        guard let encoded = cleanKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://kitsu.io/api/edge/anime?filter[text]=\(encoded)&page[limit]=1") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 Matnami/1.0", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]],
                  let first = dataArray.first,
                  let attributes = first["attributes"] as? [String: Any] else {
                completion(nil)
                return
            }

            var poster: String? = nil
            if let posterObj = attributes["posterImage"] as? [String: Any] {
                poster = posterObj["medium"] as? String ?? posterObj["small"] as? String ?? posterObj["original"] as? String
            }

            let synopsis = attributes["synopsis"] as? String
            let rating = attributes["averageRating"] as? String

            let meta = KitsuAnimeMeta(posterURL: poster, synopsis: synopsis, score: rating)

            self.lock.lock()
            self.cache[cleanKey] = meta
            self.lock.unlock()

            DispatchQueue.main.async {
                completion(meta)
            }
        }.resume()
    }
}
