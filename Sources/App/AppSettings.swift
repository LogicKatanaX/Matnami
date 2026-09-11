import Foundation

public final class AppSettings {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private let keyQuality = "com.matnami.pref_quality"
    private let keyProxy = "com.matnami.pref_use_proxy"
    private let keyOTAUrl = "com.matnami.pref_ota_url"
    private let keyProxyUrl = "com.matnami.pref_proxy_url"
    private let keyProxyStreams = "com.matnami.pref_proxy_streams"
    private let keyDebridProvider = "com.matnami.pref_debrid_provider"
    private let keyDebridToken = "com.matnami.pref_debrid_token"
    private let keyPreferVLC = "com.matnami.pref_prefer_vlc"

    /// Default Cloudflare Worker endpoint (verified active and online)
    public static let defaultProxyBase = "https://animemovie.santamrelax.workers.dev/?url="

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

    /// Global Cloudflare Worker reverse proxy toggle (Default: true with active edge worker)
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

    /// Whether to route video streams and downloads through the edge proxy (Default: true for ISP bypass)
    public var useProxyForStreams: Bool {
        get {
            if defaults.object(forKey: keyProxyStreams) == nil {
                return true
            }
            return defaults.bool(forKey: keyProxyStreams)
        }
        set {
            defaults.set(newValue, forKey: keyProxyStreams)
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

    /// Cloudflare Worker Reverse Proxy Base Endpoint (format: https://<worker>.workers.dev/?url=)
    public var proxyBaseUrl: String {
        get {
            let saved = defaults.string(forKey: keyProxyUrl) ?? ""
            return saved.isEmpty ? AppSettings.defaultProxyBase : saved
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keyProxyUrl)
        }
    }

    /// True if an active proxy endpoint is available
    public var isCustomProxyConfigured: Bool {
        return !proxyBaseUrl.isEmpty && proxyBaseUrl.contains("http")
    }

    /// Debrid Provider for Cloud Torrent-to-HTTP Streaming
    public var debridProvider: DebridProvider {
        get {
            guard let raw = defaults.string(forKey: keyDebridProvider),
                  let p = DebridProvider(rawValue: raw) else {
                return .none
            }
            return p
        }
        set {
            defaults.set(newValue.rawValue, forKey: keyDebridProvider)
        }
    }

    /// Debrid API token (Torbox / Real-Debrid)
    public var debridApiToken: String {
        get {
            return defaults.string(forKey: keyDebridToken) ?? ""
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keyDebridToken)
        }
    }

    /// Whether to prefer opening video playback in VLC for iOS (recommended for MKV/HEVC on iPad Air 1)
    public var preferVLC: Bool {
        get {
            return defaults.bool(forKey: keyPreferVLC)
        }
        set {
            defaults.set(newValue, forKey: keyPreferVLC)
        }
    }

    /// Resets all user settings back to initial factory defaults
    public func resetToDefaults() {
        defaults.removeObject(forKey: keyQuality)
        defaults.removeObject(forKey: keyProxy)
        defaults.removeObject(forKey: keyProxyStreams)
        defaults.removeObject(forKey: keyOTAUrl)
        defaults.removeObject(forKey: keyProxyUrl)
        defaults.removeObject(forKey: keyDebridProvider)
        defaults.removeObject(forKey: keyDebridToken)
        defaults.removeObject(forKey: keyPreferVLC)
    }
}

public extension Notification.Name {
    static let appDidReset = Notification.Name("com.matnami.appDidReset")
}
