import Foundation

public final class StorageManager {
    public static let shared = StorageManager()

    public let downloadsDirectory: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.downloadsDirectory = docs.appendingPathComponent("Downloads", isDirectory: true)

        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    /// Returns local file URL for an episode filename
    public func localFileURL(for fileName: String) -> URL {
        return downloadsDirectory.appendingPathComponent(fileName)
    }

    /// Checks if a file exists locally in the Downloads folder
    public func fileExists(fileName: String) -> Bool {
        let path = localFileURL(for: fileName).path
        return FileManager.default.fileExists(atPath: path)
    }

    /// Deletes a file from Downloads
    public func deleteFile(fileName: String) -> Bool {
        let fileURL = localFileURL(for: fileName)
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                return true
            }
        } catch {
            print("StorageManager: Delete error: \(error)")
        }
        return false
    }

    /// Returns file size in bytes
    public func fileSize(fileName: String) -> Int64 {
        let path = localFileURL(for: fileName).path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// Total storage on iPad (in bytes)
    public var totalDiskSpace: Int64 {
        let docPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
        guard let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: docPath),
              let space = (systemAttributes[.systemSize] as? NSNumber)?.int64Value else {
            return 0
        }
        return space
    }

    /// Free storage on iPad (in bytes)
    public var freeDiskSpace: Int64 {
        let docPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
        guard let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: docPath),
              let space = (systemAttributes[.systemFreeSize] as? NSNumber)?.int64Value else {
            return 0
        }
        return space
    }

    /// Total bytes occupied by downloaded anime episodes
    public var totalDownloadsSpace: Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let resources = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let size = resources.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    public func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
