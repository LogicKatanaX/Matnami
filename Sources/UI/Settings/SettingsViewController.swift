import UIKit

public final class SettingsViewController: UITableViewController {

    private let qualityOptions: [VideoQuality] = [.normal720p, .compact480p, .high1080p]

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = AppTheme.background
        tableView.backgroundColor = AppTheme.background
        tableView.separatorColor = AppTheme.separator
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    // MARK: - Table view data source
    public override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return qualityOptions.count // Preferred Video Quality
        case 1: return 3                    // Storage & Deletion Management (Delete All, Clear Cache, Reset App)
        case 2: return 2                    // Anime Sources & OTA
        case 3: return 3                    // Device & Architecture Info
        default: return 0
        }
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Preferred Video Quality"
        case 1: return "Storage & Deletion Management"
        case 2: return "Anime Sources & OTA Updates"
        case 3: return "Device & Architecture"
        default: return nil
        }
    }

    public override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = AppTheme.primaryAccent
            header.textLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        }
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "SettingsCell")
        cell.backgroundColor = AppTheme.secondaryBackground
        cell.textLabel?.textColor = AppTheme.textPrimary
        cell.detailTextLabel?.textColor = AppTheme.textSecondary

        switch indexPath.section {
        case 0:
            let q = qualityOptions[indexPath.row]
            cell.textLabel?.text = q.displayName
            if q == AppSettings.shared.preferredQuality {
                cell.accessoryType = .checkmark
                cell.tintColor = AppTheme.primaryAccent
            } else {
                cell.accessoryType = .none
            }

        case 1:
            if indexPath.row == 0 {
                let bytes = StorageManager.shared.totalDownloadsSpace
                cell.textLabel?.text = "Delete All Offline Downloads"
                cell.detailTextLabel?.text = StorageManager.shared.formatBytes(bytes)
                cell.accessoryType = .disclosureIndicator
                cell.textLabel?.textColor = AppTheme.primaryAccent
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Clear Image & Web Cache"
                cell.detailTextLabel?.text = "Free RAM (< 180MB)"
                cell.textLabel?.textColor = AppTheme.secondaryAccent
            } else {
                cell.textLabel?.text = "⚠️ Reset Application"
                cell.textLabel?.textColor = UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1.0)
                cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
                cell.detailTextLabel?.text = "Factory State"
            }

        case 2:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Active Source"
                cell.detailTextLabel?.text = SourceManager.shared.activeSource?.name ?? "None"
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Sync Sources from Cloud (OTA)"
                cell.detailTextLabel?.text = "Check Updates"
                cell.textLabel?.textColor = AppTheme.primaryAccent
            }

        case 3:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Hardware Target"
                cell.detailTextLabel?.text = "iPad Air 1 (Apple A7 • 1GB RAM)"
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Playback Mode"
                cell.detailTextLabel?.text = "Pure Offline (Zero-Buffer H.264)"
            } else {
                cell.textLabel?.text = "Edge Proxy"
                cell.detailTextLabel?.text = "Cloudflare Worker (Always-On)"
                cell.detailTextLabel?.textColor = AppTheme.success
            }

        default: break
        }

        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case 0:
            let selected = qualityOptions[indexPath.row]
            AppSettings.shared.preferredQuality = selected
            tableView.reloadSections(IndexSet(integer: 0), with: .none)

        case 1:
            if indexPath.row == 0 {
                confirmClearDownloads()
            } else if indexPath.row == 1 {
                clearCaches()
            } else {
                confirmResetApplication()
            }

        case 2:
            if indexPath.row == 0 {
                promptSelectSource()
            } else {
                triggerOTASync()
            }

        default: break
        }
    }

    // MARK: - Actions
    private func confirmClearDownloads() {
        let count = DownloadManager.shared.items.count
        let space = StorageManager.shared.formatBytes(StorageManager.shared.totalDownloadsSpace)

        let alert = UIAlertController(
            title: "Delete All Offline Downloads?",
            message: "This will remove all \(count) downloaded episode files from iPad storage to free \(space).",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            DownloadManager.shared.deleteAllDownloads()
            self?.tableView.reloadData()
            self?.showAlert(title: "Downloads Cleared", message: "All offline episodes have been deleted from iPad storage.")
        })
        present(alert, animated: true)
    }

    private func clearCaches() {
        ImageLoader.shared.clearCache()
        StorageManager.shared.clearTempDirectory()
        URLCache.shared.removeAllCachedResponses()
        showAlert(title: "Cache Cleared", message: "Image thumbnails and temporary web caches have been purged to optimize 1GB RAM.")
    }

    private func confirmResetApplication() {
        let alert = UIAlertController(
            title: "Reset Application to Defaults?",
            message: "This will:\n• Cancel all active downloads\n• Delete ALL offline video files\n• Clear all image and network caches\n• Reset all app settings to initial install state\n\nThis cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        alert.addAction(UIAlertAction(title: "Reset Everything", style: .destructive) { [weak self] _ in
            self?.performFactoryReset()
        })
        present(alert, animated: true)
    }

    private func triggerOTASync() {
        let alert = UIAlertController(title: "Syncing Sources", message: "Contacting remote server...", preferredStyle: .alert)
        present(alert, animated: true)

        SourceManager.shared.syncOTA(from: AppSettings.shared.customOTAUrl) { [weak self] result in
            alert.dismiss(animated: true) {
                switch result {
                case .success(let count):
                    self?.showAlert(title: "Sync Complete", message: "Successfully updated \(count) anime sources.")
                    self?.tableView.reloadData()
                case .failure(let error):
                    self?.showAlert(title: "Sync Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func performFactoryReset() {
        // 1. Reset Download Engine & Disk
        DownloadManager.shared.resetDownloadEngine()

        // 2. Clear Caches
        ImageLoader.shared.clearCache()
        StorageManager.shared.clearTempDirectory()
        URLCache.shared.removeAllCachedResponses()

        // 3. Reset Settings & Sources
        AppSettings.shared.resetToDefaults()
        SourceManager.shared.resetToDefaultSources()

        // 4. Notify app
        NotificationCenter.default.post(name: .appDidReset, object: nil)

        // 5. Reload UI
        tableView.reloadData()
        showAlert(title: "Application Reset", message: "Matnami has been completely reset to factory install state.")
    }

    private func promptSelectSource() {
        let alert = UIAlertController(title: "Select Active Source", message: nil, preferredStyle: .actionSheet)
        for s in SourceManager.shared.sources {
            alert.addAction(UIAlertAction(title: s.name, style: .default) { [weak self] _ in
                SourceManager.shared.setActiveSource(id: s.id)
                self?.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true)
    }
}


