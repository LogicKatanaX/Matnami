import Foundation
import UIKit
import ImageIO

public final class ImageLoader {
    public static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)

        // Strict iPad Air 1GB RAM budget: 40MB max image cache to prevent Jetsam SIGKILL
        cache.totalCostLimit = 40 * 1024 * 1024
        cache.countLimit = 60

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc public func clearCache() {
        cache.removeAllObjects()
    }

    /// Loads, downsamples, and caches an image safely for iPad Air 1 hardware
    public func loadImage(
        from urlString: String,
        maxDimension: CGFloat = 1536,
        completion: @escaping (UIImage?) -> Void
    ) -> URLSessionDataTask? {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return nil
        }

        let cacheKey = NSString(string: "\(urlString)_\(Int(maxDimension))")
        if let cachedImage = cache.object(forKey: cacheKey) {
            completion(cachedImage)
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPad; CPU OS 12_5_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let task = session.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Background decode & downsample off main thread
            DispatchQueue.global(qos: .userInitiated).async {
                let decodedImage = self.decodeAndDownsample(data: data, maxDimension: maxDimension)
                if let image = decodedImage {
                    let cost = Int(image.size.width * image.size.height * 4)
                    self.cache.setObject(image, forKey: cacheKey, cost: cost)
                }

                DispatchQueue.main.async {
                    completion(decodedImage)
                }
            }
        }
        task.resume()
        return task
    }

    /// Downsamples JPEG/PNG using CoreGraphics, or bridges WebP via libwebp
    private func decodeAndDownsample(data: Data, maxDimension: CGFloat) -> UIImage? {
        // Check for WebP on iOS 12
        if WebPDecoder.isWebPData(data) {
            let targetSize = CGSize(width: maxDimension, height: maxDimension)
            return WebPDecoder.decodeWebPData(data, targetSize: targetSize)
        }

        // Standard JPEG/PNG CoreGraphics thumbnail decode
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return UIImage(data: data)
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: thumbnail)
    }
}
