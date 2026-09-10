import Foundation

public final class AppSettings {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private let keyQuality = "com.matnami.pref_quality"
    private let keyProxy = "com.matnami.pref_use_proxy"
    private let keyOTAUrl = "com.matnami.pref_ota_url"

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

    /// Global Cloudflare Worker reverse proxy toggle
    public var useProxyByDefault: Bool {
        get {
            return defaults.bool(forKey: keyProxy)
        }
        set {
            defaults.set(newValue, forKey: keyProxy)
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

    private let keyProxyUrl = "com.matnami.pref_proxy_url"

    /// Cloudflare Worker Reverse Proxy Base Endpoint
    public var proxyBaseUrl: String {
        get {
            return defaults.string(forKey: keyProxyUrl) ?? "https://manga-proxy.santamcyber.workers.dev/?url="
        }
        set {
            defaults.set(newValue, forKey: keyProxyUrl)
        }
    }
}

