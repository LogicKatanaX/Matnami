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
        updateNavBar()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateStorageMeter()
        updateNavBar()
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateNavBar() {
        if !DownloadManager.shared.items.isEmpty {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "🗑️ Clear All",
                style: .plain,
                target: self,
                action: #selector(confirmClearAllDownloads)
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc private func confirmClearAllDownloads() {
        let downloadsSpace = StorageManager.shared.formatBytes(StorageManager.shared.totalDownloadsSpace)
        let alert = UIAlertController(
            title: "Delete All Offline Downloads?",
            message: "This will delete all offline anime episodes from your iPad to free \(downloadsSpace) of storage.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            DownloadManager.shared.deleteAllDownloads()
            self?.updateNavBar()
            self?.updateStorageMeter()
            self?.tableView.reloadData()
            self?.updateEmptyState()
        })
        present(alert, animated: true)
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleStateChanged), name: .appDidReset, object: nil)
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
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < DownloadManager.shared.items.count else { return }
        let item = DownloadManager.shared.items[indexPath.row]
        if item.state == .completed {
            playOfflineItem(item)
        } else {
            promptIncompleteItemOptions(item)
        }
    }

    // MARK: - Actions
    private func handleCellAction(for item: DownloadItem) {
        switch item.state {
        case .completed:
            playOfflineItem(item)
        case .downloading:
            promptIncompleteItemOptions(item)
        case .paused:
            DownloadManager.shared.resumeDownload(id: item.id)
        case .queued:
            DownloadManager.shared.cancelDownload(id: item.id)
        case .failed:
            DownloadManager.shared.resumeDownload(id: item.id)
        }
    }

    private func promptIncompleteItemOptions(_ item: DownloadItem) {
        let sheet = UIAlertController(
            title: "\(item.animeTitle) - Ep \(item.episodeNumber)",
            message: "Status: \(item.state.statusDescription) (\(item.formattedSize))",
            preferredStyle: .actionSheet
        )

        sheet.addAction(UIAlertAction(title: "▶ Stream Online Now", style: .default) { [weak self] _ in
            self?.playStreamItem(item)
        })

        if item.state == .downloading {
            sheet.addAction(UIAlertAction(title: "⏸ Pause Download", style: .default) { _ in
                DownloadManager.shared.pauseDownload(id: item.id)
            })
        } else if item.state == .paused || item.state == .failed {
            sheet.addAction(UIAlertAction(title: "↻ Resume Download", style: .default) { _ in
                DownloadManager.shared.resumeDownload(id: item.id)
            })
        }

        sheet.addAction(UIAlertAction(title: "🗑️ Cancel & Remove", style: .destructive) { _ in
            DownloadManager.shared.deleteDownload(id: item.id)
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func playStreamItem(_ item: DownloadItem) {
        guard let url = URL(string: item.streamURL) else { return }
        var targetURL = url
        if AppSettings.shared.useProxyForStreams && AppSettings.shared.isCustomProxyConfigured {
            targetURL = AnimeScraperEngine.proxiedURL(for: targetURL)
        }

        let playerVC = VideoPlayerViewController(
            animeTitle: item.animeTitle,
            episodeTitle: "Episode \(item.episodeNumber)",
            mediaURL: targetURL,
            isOffline: false
        )
        present(playerVC, animated: true)
    }

    private func playOfflineItem(_ item: DownloadItem) {
        guard let localURL = DownloadManager.shared.localPlaybackURL(for: item.episodeId) else {
            let alert = UIAlertController(title: "File Missing", message: "The downloaded video file could not be found on disk.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true)
            return
        }

        let sheet = UIAlertController(
            title: "\(item.animeTitle) - Ep \(item.episodeNumber)",
            message: "Offline Playback & Sharing Options:",
            preferredStyle: .actionSheet
        )

        sheet.addAction(UIAlertAction(title: "▶ Play in Matnami Player", style: .default) { [weak self] _ in
            let playerVC = VideoPlayerViewController(
                animeTitle: item.animeTitle,
                episodeTitle: "Episode \(item.episodeNumber)",
                mediaURL: localURL,
                isOffline: true
            )
            self?.present(playerVC, animated: true)
        })

        sheet.addAction(UIAlertAction(title: "▶ Open in VLC for iOS", style: .default) { [weak self] _ in
            guard let self = self else { return }
            TorrentActionHelper.shared.openInVLC(fileURL: localURL, from: self)
        })

        sheet.addAction(UIAlertAction(title: "📤 Share / Export to Files", style: .default) { [weak self] _ in
            guard let self = self else { return }
            TorrentActionHelper.shared.presentFileShareSheet(fileURL: localURL, from: self)
        })

        sheet.addAction(UIAlertAction(title: "🗑️ Delete Download", style: .destructive) { [weak self] _ in
            DownloadManager.shared.deleteDownload(id: item.id)
            self?.updateNavBar()
            self?.updateStorageMeter()
            self?.tableView.reloadData()
            self?.updateEmptyState()
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    // Swipe to delete
    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let item = DownloadManager.shared.items[indexPath.row]
            DownloadManager.shared.deleteDownload(id: item.id)
        }
    }
}

