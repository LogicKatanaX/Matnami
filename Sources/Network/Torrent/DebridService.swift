import Foundation

public enum DebridProvider: String, Codable, CaseIterable {
    case none = "None (Direct / Torrent Only)"
    case torbox = "Torbox (Free / Pro)"
    case realDebrid = "Real-Debrid"

    public var displayName: String { rawValue }
}

public final class DebridService {
    public static let shared = DebridService()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25.0
        self.session = URLSession(configuration: config)
    }

    /// Resolves a magnet link into a direct HTTP download link via configured Debrid service
    public func resolveMagnetToDirectURL(magnetURI: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let provider = AppSettings.shared.debridProvider
        let token = AppSettings.shared.debridApiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard provider != .none, !token.isEmpty else {
            completion(.failure(NSError(domain: "DebridService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No Debrid provider configured. Configure Torbox or Real-Debrid in Settings."])))
            return
        }

        switch provider {
        case .torbox:
            resolveTorbox(magnetURI: magnetURI, token: token, completion: completion)
        case .realDebrid:
            resolveRealDebrid(magnetURI: magnetURI, token: token, completion: completion)
        case .none:
            break
        }
    }

    private func resolveTorbox(magnetURI: String, token: String, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let url = URL(string: "https://api.torbox.app/v1/api/torrents/createtorrent") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["magnet": magnetURI]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { [weak self] data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let torrentId = dataObj["torrent_id"] as? Int ?? (dataObj["torrent_id"] as? String).flatMap({ Int($0) }) else {
                let msg = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["detail"] as? String ?? "Failed to add torrent to Torbox"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "Torbox", code: 500, userInfo: [NSLocalizedDescriptionKey: msg])))
                }
                return
            }

            // Request download link for file 1
            let dlURLString = "https://api.torbox.app/v1/api/torrents/requestdl?token=\(token)&torrent_id=\(torrentId)&file_id=1&redirect=true"
            if let dlURL = URL(string: dlURLString) {
                DispatchQueue.main.async {
                    completion(.success(dlURL))
                }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "Torbox", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid download link"])))
                }
            }
        }.resume()
    }

    private func resolveRealDebrid(magnetURI: String, token: String, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let url = URL(string: "https://api.real-debrid.com/rest/1.0/torrents/addMagnet") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let postBody = "magnet=" + (magnetURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? magnetURI)
        request.httpBody = postBody.data(using: .utf8)

        session.dataTask(with: request) { [weak self] data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let torrentId = json["id"] as? String else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "RealDebrid", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to add magnet to Real-Debrid"])))
                }
                return
            }

            self?.realDebridSelectFiles(torrentId: torrentId, token: token, completion: completion)
        }.resume()
    }

    private func realDebridSelectFiles(torrentId: String, token: String, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let url = URL(string: "https://api.real-debrid.com/rest/1.0/torrents/selectFiles/\(torrentId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "files=all".data(using: .utf8)

        session.dataTask(with: request) { [weak self] _, _, _ in
            self?.realDebridGetInfo(torrentId: torrentId, token: token, completion: completion)
        }.resume()
    }

    private func realDebridGetInfo(torrentId: String, token: String, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let url = URL(string: "https://api.real-debrid.com/rest/1.0/torrents/info/\(torrentId)") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let links = json["links"] as? [String],
                  let firstLink = links.first else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "RealDebrid", code: 500, userInfo: [NSLocalizedDescriptionKey: "Torrent is downloading or no links generated yet."])))
                }
                return
            }

            self?.realDebridUnrestrict(link: firstLink, token: token, completion: completion)
        }.resume()
    }

    private func realDebridUnrestrict(link: String, token: String, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let url = URL(string: "https://api.real-debrid.com/rest/1.0/unrestrict/link") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyStr = "link=" + (link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? link)
        request.httpBody = bodyStr.data(using: .utf8)

        session.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let downloadUrlStr = json["download"] as? String,
                  let downloadURL = URL(string: downloadUrlStr) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "RealDebrid", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to unrestrict Real-Debrid link"])))
                }
                return
            }

            DispatchQueue.main.async {
                completion(.success(downloadURL))
            }
        }.resume()
    }
}
