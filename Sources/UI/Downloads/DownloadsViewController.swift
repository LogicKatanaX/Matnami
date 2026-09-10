import UIKit

public final class DownloadsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let storageHeaderView = UIView()
    private let storageLabel = UILabel()
    private let emptyLabel = UILabel()

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Offline Downloads"
        view.backgroundColor = AppTheme.background

        setupTableView()
        setupStorageHeader()
        setupEmptyState()
        setupObservers()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateStorageMeter()
        tableView.reloadData()
        updateEmptyState()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = AppTheme.background
        tableView.separatorColor = AppTheme.separator
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DownloadCell.self, forCellReuseIdentifier: DownloadCell.reuseIdentifier)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupStorageHeader() {
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        storageHeaderView.frame = CGRect(x: 0, y: 0, width: width, height: 44)
        storageHeaderView.backgroundColor = AppTheme.secondaryBackground

        storageLabel.translatesAutoresizingMaskIntoConstraints = false
        storageLabel.textColor = AppTheme.textSecondary
        storageLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        storageHeaderView.addSubview(storageLabel)

        NSLayoutConstraint.activate([
            storageLabel.leadingAnchor.constraint(equalTo: storageHeaderView.leadingAnchor, constant: 16),
            storageLabel.trailingAnchor.constraint(equalTo: storageHeaderView.trailingAnchor, constant: -16),
            storageLabel.centerYAnchor.constraint(equalTo: storageHeaderView.centerYAnchor)
        ])

        tableView.tableHeaderView = storageHeaderView
    }

    private func setupEmptyState() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = AppTheme.textSecondary
        emptyLabel.font = UIFont.systemFont(ofSize: 15)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = "No downloaded episodes yet.\nTap 'Download' on any episode to watch offline."
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleProgressNotification(_:)), name: .downloadProgress, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleStateChanged), name: .downloadStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleStateChanged), name: .downloadCompleted, object: nil)
    }

    @objc private func handleProgressNotification(_ notification: Notification) {
        guard let episodeId = notification.object as? String,
              let idx = DownloadManager.shared.items.firstIndex(where: { $0.id == episodeId }) else {
            return
        }

        let indexPath = IndexPath(row: idx, section: 0)
        if let cell = tableView.cellForRow(at: indexPath) as? DownloadCell {
            let item = DownloadManager.shared.items[idx]
            cell.configure(with: item)
        }
    }

    @objc private func handleStateChanged() {
        updateStorageMeter()
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateStorageMeter() {
        let downloadsSpace = StorageManager.shared.formatBytes(StorageManager.shared.totalDownloadsSpace)
        let freeSpace = StorageManager.shared.formatBytes(StorageManager.shared.freeDiskSpace)
        storageLabel.text = "💾 Downloaded: \(downloadsSpace)  •  Available on iPad: \(freeSpace)"
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !DownloadManager.shared.items.isEmpty
    }

    // MARK: - UITableViewDataSource
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return DownloadManager.shared.items.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DownloadCell.reuseIdentifier, for: indexPath) as! DownloadCell
        let item = DownloadManager.shared.items[indexPath.row]

        cell.configure(with: item)
        cell.onActionTapped = { [weak self] in
            self?.handleCellAction(for: item)
        }
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = DownloadManager.shared.items[indexPath.row]
        if item.state == .completed {
            playOfflineItem(item)
        }
    }

    // MARK: - Actions
    private func handleCellAction(for item: DownloadItem) {
        switch item.state {
        case .completed:
            playOfflineItem(item)
        case .downloading:
            DownloadManager.shared.pauseDownload(id: item.id)
        case .paused:
            DownloadManager.shared.resumeDownload(id: item.id)
        case .queued:
            DownloadManager.shared.cancelDownload(id: item.id)
        case .failed:
            DownloadManager.shared.resumeDownload(id: item.id)
        }
    }

    private func playOfflineItem(_ item: DownloadItem) {
        guard let localURL = DownloadManager.shared.localPlaybackURL(for: item.episodeId) else {
            let alert = UIAlertController(title: "File Missing", message: "The downloaded video file could not be found on disk.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true)
            return
        }

        let playerVC = VideoPlayerViewController(
            animeTitle: item.animeTitle,
            episodeTitle: "Episode \(item.episodeNumber)",
            mediaURL: localURL,
            isOffline: true
        )
        present(playerVC, animated: true)
    }

    // Swipe to delete
    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let item = DownloadManager.shared.items[indexPath.row]
            DownloadManager.shared.deleteDownload(id: item.id)
        }
    }
}

