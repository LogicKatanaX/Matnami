import UIKit

public final class TorrentActionHelper: NSObject, UIDocumentInteractionControllerDelegate {
    public static let shared = TorrentActionHelper()
    private var activeDocController: UIDocumentInteractionController?

    private override init() {
        super.init()
    }

    /// Copies magnet link to clipboard and offers to open in installed torrent app
    public func copyMagnet(uri: String, from viewController: UIViewController) {
        UIPasteboard.general.string = uri
        let alert = UIAlertController(
            title: "🧲 Magnet Copied",
            message: "Magnet link copied to clipboard!\n\nYou can paste it into iTorrent, Seedr, or any torrent app.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Open Torrent App", style: .default) { _ in
            if let url = URL(string: uri) {
                if #available(iOS 10.0, *) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                } else {
                    UIApplication.shared.openURL(url)
                }
            }
        })
        alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
        viewController.present(alert, animated: true)
    }

    /// Downloads .torrent file and saves into Documents/Downloads
    public func downloadTorrentFile(from url: URL, fileName: String, viewController: UIViewController, completion: ((URL?) -> Void)? = nil) {
        let task = URLSession.shared.downloadTask(with: url) { [weak self] localTmp, _, error in
            guard let self = self else { return }
            guard let localTmp = localTmp, error == nil else {
                DispatchQueue.main.async {
                    let alert = UIAlertController(
                        title: "Download Failed",
                        message: error?.localizedDescription ?? "Could not download .torrent file",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                    viewController.present(alert, animated: true)
                    completion?(nil)
                }
                return
            }

            let cleanName = fileName.replacingOccurrences(of: "/", with: "-")
            let safeName = cleanName.hasSuffix(".torrent") ? cleanName : "\(cleanName).torrent"
            let targetURL = StorageManager.shared.localFileURL(for: safeName)
            try? FileManager.default.removeItem(at: targetURL)
            try? FileManager.default.moveItem(at: localTmp, to: targetURL)

            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "⬇ Torrent File Ready",
                    message: "Saved to Files app:\nOn My iPad → Matnami → Downloads → \(safeName)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "🚀 Open in iTorrent / Share", style: .default) { [weak self] _ in
                    self?.presentFileShareSheet(fileURL: targetURL, from: viewController)
                })
                alert.addAction(UIAlertAction(title: "Done", style: .cancel, handler: nil))
                viewController.present(alert, animated: true)
                completion?(targetURL)
            }
        }
        task.resume()
    }

    /// Presents standard iOS Open In / Share menu
    public func presentFileShareSheet(fileURL: URL, from viewController: UIViewController) {
        activeDocController = UIDocumentInteractionController(url: fileURL)
        activeDocController?.delegate = self
        let rect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 1, height: 1)
        activeDocController?.presentOptionsMenu(from: rect, in: viewController.view, animated: true)
    }

    /// Opens file in VLC for iOS or presents Open In menu
    public func openInVLC(fileURL: URL, from viewController: UIViewController) {
        let pathStr = fileURL.path
        let escapedPath = pathStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pathStr
        let vlcURLString = "vlc-x-callback://x-callback-url/stream?url=file://\(escapedPath)"

        if let vlcURL = URL(string: vlcURLString), UIApplication.shared.canOpenURL(vlcURL) {
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(vlcURL, options: [:], completionHandler: nil)
            } else {
                UIApplication.shared.openURL(vlcURL)
            }
        } else {
            // Present Open In Menu
            activeDocController = UIDocumentInteractionController(url: fileURL)
            activeDocController?.delegate = self
            let rect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 1, height: 1)
            let success = activeDocController?.presentOpenInMenu(from: rect, in: viewController.view, animated: true) ?? false
            if !success {
                activeDocController?.presentOptionsMenu(from: rect, in: viewController.view, animated: true)
            }
        }
    }
}
