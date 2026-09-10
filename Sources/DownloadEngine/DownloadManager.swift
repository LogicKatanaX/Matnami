import Foundation
import UIKit
import QuartzCore

public final class DownloadManager: NSObject, URLSessionDownloadDelegate {
    public static let shared = DownloadManager()

    public private(set) var items: [DownloadItem] = []
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var resumeDataMap: [String: Data] = [:]
    private var lastProgressPostTime: [String: TimeInterval] = [:]
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    public var backgroundCompletionHandler: (() -> Void)?

    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 86400.0 // 24 hours for large video files
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private func beginBackgroundTaskIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.backgroundTaskId == .invalid else { return }
            self.backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "MatnamiDownload") { [weak self] in
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.backgroundTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskId)
                self.backgroundTaskId = .invalid
            }
        }
    }

    private let metadataFileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("downloads_metadata.json")
    }()

    private override init() {
        super.init()
        loadMetadata()
    }

    // MARK: - Metadata Persistence
    private func loadMetadata() {
        guard FileManager.default.fileExists(atPath: metadataFileURL.path),
              let data = try? Data(contentsOf: metadataFileURL),
              let list = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            return
        }

        // Verify local file existence for completed items
        var validated: [DownloadItem] = []
        for var item in list {
            if item.state == .completed {
                if !StorageManager.shared.fileExists(fileName: item.localFileName) {
                    item.state = .failed
                    item.errorMessage = "File missing from disk"
                }
            } else if item.state == .downloading {
                // If app was terminated while downloading, mark paused
                item.state = .paused
            }
            validated.append(item)
        }
        self.items = validated
    }

    private func saveMetadata() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: metadataFileURL)
        }
    }

    // MARK: - Query Status
    public func isEpisodeDownloaded(episodeId: String) -> Bool {
        guard let item = items.first(where: { $0.episodeId == episodeId }) else { return false }
        return item.state == .completed && StorageManager.shared.fileExists(fileName: item.localFileName)
    }

    public func localPlaybackURL(for episodeId: String) -> URL? {
        guard let item = items.first(where: { $0.episodeId == episodeId }),
              item.state == .completed,
              StorageManager.shared.fileExists(fileName: item.localFileName) else {
            return nil
        }
        return StorageManager.shared.localFileURL(for: item.localFileName)
    }

    public func item(for episodeId: String) -> DownloadItem? {
        return items.first(where: { $0.episodeId == episodeId })
    }

    // MARK: - Download Control
    public func startDownload(anime: Anime, episode: Episode, videoSource: VideoSource) {
        let cleanEpNum = episode.number.replacingOccurrences(of: "/", with: "-")
        let fileName = "\(episode.id).mp4"

        // If already completed and exists, ignore
        if isEpisodeDownloaded(episodeId: episode.id) {
            return
        }

        let item = DownloadItem(
            id: episode.id,
            episodeId: episode.id,
            animeId: anime.id,
            animeTitle: anime.title,
            episodeNumber: cleanEpNum,
            episodeTitle: episode.title,
            coverURL: anime.coverURL,
            streamURL: videoSource.streamURL.absoluteString,
            serverName: videoSource.serverName,
            quality: videoSource.quality.rawValue,
            localFileName: fileName,
            state: .downloading
        )

        // Upsert into items list
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.insert(item, at: 0)
        }
        saveMetadata()

        var request = URLRequest(url: videoSource.streamURL)
        for (k, v) in videoSource.effectiveHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.timeoutInterval = 60.0

        let task = downloadSession.downloadTask(with: request)
        task.taskDescription = episode.id
        activeTasks[episode.id] = task
        beginBackgroundTaskIfNeeded()
        task.resume()

        NotificationCenter.default.post(name: .downloadStateChanged, object: episode.id)
    }

    public func pauseDownload(id: String) {
        guard let task = activeTasks[id] else { return }
        task.cancel { [weak self] resumeData in
            guard let self = self else { return }
            if let data = resumeData {
                self.resumeDataMap[id] = data
            }
            self.activeTasks.removeValue(forKey: id)
            self.updateItemState(id: id, state: .paused)
            if self.activeTasks.isEmpty {
                self.endBackgroundTask()
            }
        }
    }

    public func resumeDownload(id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[idx]

        let task: URLSessionDownloadTask
        if let resumeData = resumeDataMap[id] {
            task = downloadSession.downloadTask(withResumeData: resumeData)
            resumeDataMap.removeValue(forKey: id)
        } else if let url = URL(string: item.streamURL) {
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            req.setValue("*/*", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 60.0
            task = downloadSession.downloadTask(with: req)
        } else {
            return
        }

        task.taskDescription = id
        activeTasks[id] = task
        beginBackgroundTaskIfNeeded()
        task.resume()

        updateItemState(id: id, state: .downloading)
    }

    public func cancelDownload(id: String) {
        if let task = activeTasks[id] {
            task.cancel()
            activeTasks.removeValue(forKey: id)
        }
        resumeDataMap.removeValue(forKey: id)
        updateItemState(id: id, state: .failed, errorMessage: "Download canceled")
        if activeTasks.isEmpty {
            endBackgroundTask()
        }
    }

    public func deleteDownload(id: String) {
        if let task = activeTasks[id] {
            task.cancel()
            activeTasks.removeValue(forKey: id)
        }
        resumeDataMap.removeValue(forKey: id)

        if let idx = items.firstIndex(where: { $0.id == id }) {
            let item = items[idx]
            _ = StorageManager.shared.deleteFile(fileName: item.localFileName)
            items.remove(at: idx)
            saveMetadata()
            NotificationCenter.default.post(name: .downloadStateChanged, object: id)
        }
    }

    /// Deletes all downloaded episodes for a specific anime series
    public func deleteDownloads(forAnimeId animeId: String) {
        let matching = items.filter { $0.animeId == animeId }
        for it in matching {
            if let task = activeTasks[it.id] {
                task.cancel()
                activeTasks.removeValue(forKey: it.id)
            }
            resumeDataMap.removeValue(forKey: it.id)
            _ = StorageManager.shared.deleteFile(fileName: it.localFileName)
        }
        items.removeAll(where: { $0.animeId == animeId })
        saveMetadata()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .downloadStateChanged, object: nil)
        }
    }

    /// Deletes all downloaded episodes across all anime
    public func deleteAllDownloads() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        resumeDataMap.removeAll()
        _ = StorageManager.shared.deleteAllDownloads()
        items.removeAll()
        saveMetadata()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .downloadStateChanged, object: nil)
        }
    }

    /// Completely resets the download engine, cancels tasks, and deletes metadata
    public func resetDownloadEngine() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        resumeDataMap.removeAll()
        _ = StorageManager.shared.deleteAllDownloads()
        items.removeAll()
        try? FileManager.default.removeItem(at: metadataFileURL)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .downloadStateChanged, object: nil)
        }
    }

    private func updateItemState(id: String, state: DownloadState, errorMessage: String? = nil) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].state = state
        if state == .completed {
            items[idx].completedAt = Date()
            items[idx].progress = 1.0
        }
        if let msg = errorMessage {
            items[idx].errorMessage = msg
        }
        saveMetadata()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .downloadStateChanged, object: id)
        }
    }

    // MARK: - URLSessionDownloadDelegate
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let episodeId = downloadTask.taskDescription else { return }

        let targetURL = StorageManager.shared.localFileURL(for: "\(episodeId).mp4")
        _ = StorageManager.shared.deleteFile(fileName: "\(episodeId).mp4")

        do {
            try FileManager.default.moveItem(at: location, to: targetURL)
            if let idx = items.firstIndex(where: { $0.id == episodeId }) {
                items[idx].bytesDownloaded = StorageManager.shared.fileSize(fileName: "\(episodeId).mp4")
                items[idx].totalBytes = items[idx].bytesDownloaded
            }
            updateItemState(id: episodeId, state: .completed)
            activeTasks.removeValue(forKey: episodeId)
            if activeTasks.isEmpty {
                endBackgroundTask()
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .downloadCompleted, object: episodeId)
            }
        } catch {
            updateItemState(id: episodeId, state: .failed, errorMessage: error.localizedDescription)
            activeTasks.removeValue(forKey: episodeId)
            if activeTasks.isEmpty {
                endBackgroundTask()
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let episodeId = downloadTask.taskDescription,
              let idx = items.firstIndex(where: { $0.id == episodeId }) else { return }

        let progress = Float(totalBytesWritten) / Float(max(totalBytesExpectedToWrite, 1))
        items[idx].progress = progress
        items[idx].bytesDownloaded = totalBytesWritten
        items[idx].totalBytes = max(totalBytesExpectedToWrite, totalBytesWritten)

        let now = CACurrentMediaTime()
        let lastTime = lastProgressPostTime[episodeId] ?? 0
        if now - lastTime >= 0.25 || progress >= 1.0 {
            lastProgressPostTime[episodeId] = now
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .downloadProgress,
                    object: episodeId,
                    userInfo: [
                        "episodeId": episodeId,
                        "progress": progress,
                        "bytesWritten": totalBytesWritten,
                        "totalBytes": totalBytesExpectedToWrite
                    ]
                )
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let episodeId = task.taskDescription else { return }
        activeTasks.removeValue(forKey: episodeId)
        if activeTasks.isEmpty {
            endBackgroundTask()
        }

        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            updateItemState(id: episodeId, state: .failed, errorMessage: error.localizedDescription)
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            if let handler = self?.backgroundCompletionHandler {
                self?.backgroundCompletionHandler = nil
                handler()
            }
        }
    }
}

public extension Notification.Name {
    static let downloadProgress = Notification.Name("com.matnami.downloadProgress")
    static let downloadCompleted = Notification.Name("com.matnami.downloadCompleted")
    static let downloadStateChanged = Notification.Name("com.matnami.downloadStateChanged")
}

