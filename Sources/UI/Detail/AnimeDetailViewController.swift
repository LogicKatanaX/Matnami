import UIKit

public final class AnimeDetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private var anime: Anime
    private var episodes: [Episode] = []

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerView = UIView()
    private let coverImageView = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let synopsisTextView = UITextView()
    private let activityIndicator = UIActivityIndicatorView(style: .whiteLarge)

    public init(anime: Anime) {
        self.anime = anime
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = anime.title
        view.backgroundColor = AppTheme.background

        setupTableView()
        setupHeaderView()
        setupObservers()
        loadEpisodes()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNavBarButtons()
        tableView.reloadData()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = AppTheme.background
        tableView.separatorColor = AppTheme.separator
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EpisodeCell.self, forCellReuseIdentifier: EpisodeCell.reuseIdentifier)
        view.addSubview(tableView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = AppTheme.primaryAccent
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupHeaderView() {
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        headerView.frame = CGRect(x: 0, y: 0, width: width, height: 260)
        headerView.backgroundColor = AppTheme.secondaryBackground

        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.layer.cornerRadius = 8
        coverImageView.clipsToBounds = true
        coverImageView.backgroundColor = AppTheme.cardBackground
        headerView.addSubview(coverImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = AppTheme.textPrimary
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.numberOfLines = 2
        titleLabel.text = anime.title
        headerView.addSubview(titleLabel)

        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.textColor = AppTheme.textSecondary
        metaLabel.font = UIFont.systemFont(ofSize: 13)
        var meta = ""
        if !anime.score.isEmpty { meta += "★ \(anime.score)  •  " }
        meta += "\(anime.status)  •  \(anime.genres.prefix(3).joined(separator: ", "))"
        metaLabel.text = meta
        headerView.addSubview(metaLabel)

        synopsisTextView.translatesAutoresizingMaskIntoConstraints = false
        synopsisTextView.backgroundColor = .clear
        synopsisTextView.textColor = AppTheme.textSecondary
        synopsisTextView.font = UIFont.systemFont(ofSize: 13)
        synopsisTextView.isEditable = false
        synopsisTextView.text = anime.synopsis.isEmpty ? "No synopsis available." : anime.synopsis
        headerView.addSubview(synopsisTextView)

        NSLayoutConstraint.activate([
            coverImageView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            coverImageView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            coverImageView.widthAnchor.constraint(equalToConstant: 120),
            coverImageView.heightAnchor.constraint(equalToConstant: 170),

            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),

            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            metaLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 16),
            metaLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),

            synopsisTextView.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 8),
            synopsisTextView.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12),
            synopsisTextView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            synopsisTextView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -12)
        ])

        tableView.tableHeaderView = headerView

        if !anime.coverURL.isEmpty {
            _ = ImageLoader.shared.loadImage(from: anime.coverURL, maxDimension: 512) { [weak self] img in
                self?.coverImageView.image = img
            }
        }
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleProgressNotification(_:)), name: .downloadProgress, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleStateChangedNotification), name: .downloadCompleted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleStateChangedNotification), name: .downloadStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleStateChangedNotification), name: .appDidReset, object: nil)
    }

    @objc private func handleProgressNotification(_ notification: Notification) {
        guard let episodeId = notification.object as? String,
              let row = episodes.firstIndex(where: { $0.id == episodeId }) else {
            return
        }
        let indexPath = IndexPath(row: row, section: 0)
        if let cell = tableView.cellForRow(at: indexPath) as? EpisodeCell {
            let ep = episodes[row]
            let item = DownloadManager.shared.item(for: ep.id)
            cell.configure(with: ep, downloadItem: item)
        }
    }

    @objc private func handleStateChangedNotification() {
        updateNavBarButtons()
        tableView.reloadData()
    }

    private func loadEpisodes() {
        guard let source = SourceManager.shared.activeSource else { return }
        activityIndicator.startAnimating()

        AnimeScraperEngine.shared.fetchAnimeDetail(source: source, anime: anime) { [weak self] result in
            guard let self = self else { return }
            self.activityIndicator.stopAnimating()

            switch result {
            case .success(let (updatedAnime, epList)):
                self.anime = updatedAnime
                self.episodes = epList
                self.synopsisTextView.text = updatedAnime.synopsis.isEmpty ? "No synopsis available." : updatedAnime.synopsis
                self.titleLabel.text = updatedAnime.title
                self.tableView.reloadData()
            case .failure(let error):
                let alert = UIAlertController(title: "Failed to load episodes", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(alert, animated: true)
            }
        }
    }


    private func updateNavBarButtons() {
        let hasDownloads = DownloadManager.shared.items.contains { $0.animeId == anime.id }
        if hasDownloads {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "🗑️ Clean",
                style: .plain,
                target: self,
                action: #selector(confirmDeleteAnimeDownloads)
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc private func confirmDeleteAnimeDownloads() {
        let alert = UIAlertController(
            title: "Delete All Downloads?",
            message: "This will remove all offline episodes downloaded for '\(anime.title)' from your iPad.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            DownloadManager.shared.deleteDownloads(forAnimeId: self.anime.id)
            self.updateNavBarButtons()
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    // MARK: - UITableViewDataSource
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return episodes.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: EpisodeCell.reuseIdentifier, for: indexPath) as! EpisodeCell
        let ep = episodes[indexPath.row]
        let item = DownloadManager.shared.item(for: ep.id)

        cell.configure(with: ep, downloadItem: item)
        cell.onActionTapped = { [weak self] in
            self?.handleEpisodeAction(ep)
        }
        cell.onDeleteTapped = { [weak self] in
            self?.confirmDeleteSingleEpisode(ep)
        }

        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let ep = episodes[indexPath.row]
        handleEpisodeAction(ep)
    }

    // MARK: - Actions
    private func handleEpisodeAction(_ episode: Episode) {
        let item = DownloadManager.shared.item(for: episode.id)

        if let it = item {
            switch it.state {
            case .completed:
                presentDownloadedEpisodeOptions(episode)
                return
            case .downloading:
                presentActiveDownloadingOptions(episode, item: it)
                return
            case .paused, .failed:
                presentPausedEpisodeOptions(episode, item: it)
                return
            case .queued:
                DownloadManager.shared.cancelDownload(id: episode.id)
                return
            }
        }

        // Not yet downloaded: resolve sources and present Play / Download choices
        resolveSources(for: episode) { [weak self] sources in
            self?.presentPlayOrDownloadPicker(sources: sources, episode: episode)
        }
    }

    private func presentDownloadedEpisodeOptions(_ episode: Episode) {
        let sheet = UIAlertController(
            title: episode.title,
            message: "Offline download is ready on this iPad.",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "▶ Play Offline", style: .default) { [weak self] _ in
            self?.playOfflineEpisode(episode)
        })
        sheet.addAction(UIAlertAction(title: "▶ Stream Online", style: .default) { [weak self] _ in
            self?.resolveSources(for: episode) { sources in
                self?.presentStreamingQualityPicker(sources: sources, episode: episode)
            }
        })
        sheet.addAction(UIAlertAction(title: "🗑️ Delete Download", style: .destructive) { [weak self] _ in
            self?.confirmDeleteSingleEpisode(episode)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func presentActiveDownloadingOptions(_ episode: Episode, item: DownloadItem) {
        let sheet = UIAlertController(
            title: episode.title,
            message: "Currently downloading (\(item.formattedSize)). You can stream immediately while downloading.",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "▶ Play Online (Instant Stream)", style: .default) { [weak self] _ in
            self?.resolveSources(for: episode) { sources in
                self?.presentStreamingQualityPicker(sources: sources, episode: episode)
            }
        })
        sheet.addAction(UIAlertAction(title: "⏸ Pause Download", style: .default) { _ in
            DownloadManager.shared.pauseDownload(id: episode.id)
        })
        sheet.addAction(UIAlertAction(title: "🛑 Cancel Download", style: .destructive) { _ in
            DownloadManager.shared.cancelDownload(id: episode.id)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func presentPausedEpisodeOptions(_ episode: Episode, item: DownloadItem) {
        let sheet = UIAlertController(
            title: episode.title,
            message: "Download paused or failed (\(item.formattedSize)).",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "▶ Play Online (Instant Stream)", style: .default) { [weak self] _ in
            self?.resolveSources(for: episode) { sources in
                self?.presentStreamingQualityPicker(sources: sources, episode: episode)
            }
        })
        sheet.addAction(UIAlertAction(title: "↻ Resume Download", style: .default) { _ in
            DownloadManager.shared.resumeDownload(id: episode.id)
        })
        sheet.addAction(UIAlertAction(title: "🗑️ Delete Download", style: .destructive) { [weak self] _ in
            self?.confirmDeleteSingleEpisode(episode)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func playOfflineEpisode(_ episode: Episode) {
        guard let localURL = DownloadManager.shared.localPlaybackURL(for: episode.id) else {
            showError(message: "Offline video file is missing from iPad storage.")
            return
        }

        let playerVC = VideoPlayerViewController(
            animeTitle: anime.title,
            episodeTitle: episode.title,
            mediaURL: localURL,
            isOffline: true
        )
        present(playerVC, animated: true)
    }

    private func playOnlineEpisode(_ episode: Episode, source: VideoSource) {
        var mediaURL = source.streamURL
        if AppSettings.shared.useProxyForStreams && AppSettings.shared.isCustomProxyConfigured {
            mediaURL = AnimeScraperEngine.proxiedURL(for: mediaURL)
        }

        let playerVC = VideoPlayerViewController(
            animeTitle: anime.title,
            episodeTitle: episode.title,
            mediaURL: mediaURL,
            httpHeaders: source.effectiveHeaders,
            isOffline: false
        )
        present(playerVC, animated: true)
    }

    private func resolveSources(for episode: Episode, completion: @escaping ([VideoSource]) -> Void) {
        guard let source = SourceManager.shared.activeSource else { return }
        activityIndicator.startAnimating()

        AnimeScraperEngine.shared.fetchEpisodeSources(source: source, episode: episode) { [weak self] result in
            guard let self = self else { return }
            self.activityIndicator.stopAnimating()

            switch result {
            case .success(let sources):
                guard !sources.isEmpty else {
                    self.showError(message: "No video sources available for this episode.")
                    return
                }
                completion(sources)

            case .failure(let error):
                self.showError(message: "Failed to resolve video sources:\n\(error.localizedDescription)")
            }
        }
    }

    private func presentPlayOrDownloadPicker(sources: [VideoSource], episode: Episode) {
        let sheet = UIAlertController(
            title: episode.title,
            message: "Choose playback method for this episode:",
            preferredStyle: .actionSheet
        )

        sheet.addAction(UIAlertAction(title: "▶ Play Online (Instant Stream)", style: .default) { [weak self] _ in
            self?.presentStreamingQualityPicker(sources: sources, episode: episode)
        })

        sheet.addAction(UIAlertAction(title: "⬇ Download to iPad (Offline)", style: .default) { [weak self] _ in
            self?.presentDownloadQualityPicker(sources: sources, episode: episode)
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func presentStreamingQualityPicker(sources: [VideoSource], episode: Episode) {
        if sources.count == 1, let first = sources.first {
            playOnlineEpisode(episode, source: first)
            return
        }

        let sheet = UIAlertController(
            title: "Select Stream Quality",
            message: "\(episode.title)\nPick video server/resolution:",
            preferredStyle: .actionSheet
        )

        let preferred = AppSettings.shared.preferredQuality
        let sortedSources = sources.sorted { a, b in
            if a.quality == preferred && b.quality != preferred { return true }
            if b.quality == preferred && a.quality != preferred { return false }
            return a.quality.rawValue > b.quality.rawValue
        }

        for s in sortedSources {
            let prefTag = (s.quality == preferred) ? " ★ Preferred" : ""
            let label = "▶ \(s.serverName) [\(s.quality.displayName)]\(prefTag)"

            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.playOnlineEpisode(episode, source: s)
            })
        }

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func presentDownloadQualityPicker(sources: [VideoSource], episode: Episode) {
        if sources.count == 1, let first = sources.first {
            DownloadManager.shared.startDownload(anime: anime, episode: episode, videoSource: first)
            updateNavBarButtons()
            tableView.reloadData()
            return
        }

        let sheet = UIAlertController(
            title: "Select Download Quality",
            message: "\(episode.title)\nPick resolution to save offline:",
            preferredStyle: .actionSheet
        )

        let preferred = AppSettings.shared.preferredQuality
        let sortedSources = sources.sorted { a, b in
            if a.quality == preferred && b.quality != preferred { return true }
            if b.quality == preferred && a.quality != preferred { return false }
            return a.quality.rawValue > b.quality.rawValue
        }

        for s in sortedSources {
            let prefTag = (s.quality == preferred) ? " ★ Preferred" : ""
            let directTag = s.isDirectDownload ? " ⚡Direct" : ""
            let label = "⬇ \(s.serverName) [\(s.quality.displayName)]\(prefTag)\(directTag)"

            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                guard let self = self else { return }
                DownloadManager.shared.startDownload(anime: self.anime, episode: episode, videoSource: s)
                self.updateNavBarButtons()
                self.tableView.reloadData()
            })
        }

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func confirmDeleteSingleEpisode(_ episode: Episode) {
        let alert = UIAlertController(
            title: "Delete Episode Download?",
            message: "Remove offline file for '\(episode.title)' to free storage?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            DownloadManager.shared.deleteDownload(id: episode.id)
            self.updateNavBarButtons()
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    private func showError(message: String) {
        let alert = UIAlertController(title: "Notice", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true)
    }
}

