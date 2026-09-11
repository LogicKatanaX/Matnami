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
        request.timeoutInterval = 15.0
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

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

    /// Generates a rich, high-resolution procedural anime poster card for iOS 12
    public func generatePosterPlaceholder(for title: String, size: CGSize = CGSize(width: 300, height: 420)) -> UIImage {
        let cacheKey = NSString(string: "poster_placeholder_\(title)")
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let palettes: [[(r: CGFloat, g: CGFloat, b: CGFloat)]] = [
            [(15/255.0, 12/255.0, 41/255.0), (48/255.0, 43/255.0, 99/255.0), (36/255.0, 36/255.0, 62/255.0)],
            [(20/255.0, 10/255.0, 15/255.0), (65/255.0, 20/255.0, 35/255.0), (30/255.0, 12/255.0, 25/255.0)],
            [(10/255.0, 25/255.0, 20/255.0), (25/255.0, 55/255.0, 45/255.0), (12/255.0, 30/255.0, 25/255.0)],
            [(15/255.0, 20/255.0, 35/255.0), (25/255.0, 50/255.0, 80/255.0), (18/255.0, 28/255.0, 50/255.0)],
            [(25/255.0, 15/255.0, 45/255.0), (68/255.0, 32/255.0, 98/255.0), (35/255.0, 18/255.0, 55/255.0)]
        ]

        let hashVal = abs(title.hashValue)
        let selectedPalette = palettes[hashVal % palettes.count]

        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            return UIImage()
        }

        // Draw smooth vertical linear gradient
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var components: [CGFloat] = []
        for color in selectedPalette {
            components.append(contentsOf: [color.r, color.g, color.b, 1.0])
        }
        let locations: [CGFloat] = [0.0, 0.5, 1.0]
        if let gradient = CGGradient(colorSpace: colorSpace, colorComponents: components, locations: locations, count: 3) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: size.width / 2, y: 0), end: CGPoint(x: size.width / 2, y: size.height), options: [])
        }

        // Draw decorative subtle inner frame
        ctx.setStrokeColor(UIColor(white: 1.0, alpha: 0.12).cgColor)
        ctx.setLineWidth(1.5)
        let frameRect = CGRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24)
        ctx.stroke(frameRect)

        // Draw stylized film reel / anime icon watermark in upper center
        let iconSize: CGFloat = 54
        let iconRect = CGRect(x: (size.width - iconSize) / 2, y: size.height * 0.28, width: iconSize, height: iconSize)
        ctx.setFillColor(UIColor(white: 1.0, alpha: 0.15).cgColor)
        ctx.fillEllipse(in: iconRect)
        ctx.setStrokeColor(UIColor(white: 1.0, alpha: 0.35).cgColor)
        ctx.setLineWidth(2.0)
        ctx.strokeEllipse(in: iconRect)

        // Draw anime play triangle inside watermark
        ctx.setFillColor(UIColor(white: 1.0, alpha: 0.45).cgColor)
        let triPath = CGMutablePath()
        let cx = iconRect.midX
        let cy = iconRect.midY
        triPath.move(to: CGPoint(x: cx - 8, y: cy - 12))
        triPath.addLine(to: CGPoint(x: cx + 12, y: cy))
        triPath.addLine(to: CGPoint(x: cx - 8, y: cy + 12))
        triPath.closeSubpath()
        ctx.addPath(triPath)
        ctx.fillPath()

        // Draw title text
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let textRect = CGRect(x: 20, y: size.height * 0.50, width: size.width - 40, height: size.height * 0.42)
        (cleanTitle as NSString).draw(in: textRect, withAttributes: titleAttrs)

        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()

        let cost = Int(size.width * size.height * 4)
        cache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }
}

