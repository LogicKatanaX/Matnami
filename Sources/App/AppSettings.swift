import Foundation

public final class AppSettings {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private let keyQuality = "com.matnami.pref_quality"
    private let keyOTAUrl = "com.matnami.pref_ota_url"

    /// Cloudflare Worker Reverse Proxy Base Endpoint (Always-on architecture)
    public let proxyBaseUrl: String = "https://manga-proxy.santamcyber.workers.dev/?url="

    private init() {}

    /// Default video quality preference (Defaults to 720p for optimal iPad Air 1 hardware playback)
    public var preferredQuality: VideoQuality {
        get {
            guard let raw = defaults.string(forKey: keyQuality),
                  let q = VideoQuality(rawValue: raw) else {
                return .normal720p
            }
            return q
        }
        set {
            defaults.set(newValue.rawValue, forKey: keyQuality)
        }
    }

    /// Custom OTA sources.json URL
    public var customOTAUrl: String {
        get {
            return defaults.string(forKey: keyOTAUrl) ?? "https://raw.githubusercontent.com/LogicKatanaX/Matnami/main/Sources/sources.json"
        }
        set {
            defaults.set(newValue, forKey: keyOTAUrl)
        }
    }
}

