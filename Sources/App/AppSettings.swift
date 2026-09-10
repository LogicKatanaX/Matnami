import Foundation

public final class AppSettings {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private let keyQuality = "com.matnami.pref_quality"
    private let keyProxy = "com.matnami.pref_use_proxy"
    private let keyOTAUrl = "com.matnami.pref_ota_url"
    private let keyProxyUrl = "com.matnami.pref_proxy_url"

    /// Default Cloudflare Worker Reverse Proxy Base Endpoint (Always-on architecture)
    public static let defaultProxyBase = "https://manga-proxy.santamcyber.workers.dev/?url="

    private init() {}

    /// Preferred video quality for iPad Air 1 hardware playback (Defaults to 720p)
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

    /// Global Cloudflare Worker reverse proxy toggle (Default: true)
    public var useProxyByDefault: Bool {
        get {
            if defaults.object(forKey: keyProxy) == nil {
                return true
            }
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

    /// Cloudflare Worker Reverse Proxy Base Endpoint
    public var proxyBaseUrl: String {
        get {
            return defaults.string(forKey: keyProxyUrl) ?? AppSettings.defaultProxyBase
        }
        set {
            defaults.set(newValue, forKey: keyProxyUrl)
        }
    }

    /// Resets all user settings back to initial factory defaults
    public func resetToDefaults() {
        defaults.removeObject(forKey: keyQuality)
        defaults.removeObject(forKey: keyProxy)
        defaults.removeObject(forKey: keyOTAUrl)
        defaults.removeObject(forKey: keyProxyUrl)
    }
}

public extension Notification.Name {
    static let appDidReset = Notification.Name("com.matnami.appDidReset")
}


