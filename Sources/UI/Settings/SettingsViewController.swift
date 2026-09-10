import UIKit

public final class SettingsViewController: UITableViewController {

    private let qualityOptions: [VideoQuality] = [.normal720p, .high1080p, .compact480p]

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
        return 5
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return qualityOptions.count // Video Quality
        case 1: return 2 // Storage & Cache
        case 2: return 2 // Sources & OTA
        case 3: return 1 // Network Proxy
        case 4: return 2 // About & Device info
        default: return 0
        }
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Preferred Video Quality"
        case 1: return "Storage & Memory Management"
        case 2: return "Anime Sources & OTA Updates"
        case 3: return "Network & Proxy"
        case 4: return "Device & Architecture"
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
                cell.textLabel?.text = "Offline Downloads"
                cell.detailTextLabel?.text = StorageManager.shared.formatBytes(bytes)
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Clear Image Cache"
                cell.detailTextLabel?.text = "Free RAM (< 180MB)"
                cell.textLabel?.textColor = AppTheme.secondaryAccent
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
            cell.textLabel?.text = "Cloudflare Worker Proxy"
            let switchView = UISwitch()
            switchView.isOn = AppSettings.shared.useProxyByDefault
            switchView.onTintColor = AppTheme.primaryAccent
            switchView.addTarget(self, action: #selector(toggleProxy(_:)), for: .valueChanged)
            cell.accessoryView = switchView

        case 4:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Hardware Target"
                cell.detailTextLabel?.text = "iPad Air 1 (Apple A7 • 1GB RAM)"
            } else {
                cell.textLabel?.text = "Architecture"
                cell.detailTextLabel?.text = "Download-First (Hardware H.264)"
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
            } else {
                ImageLoader.shared.clearCache()
                showAlert(title: "Image Cache Cleared", message: "Bitmap cache purged to preserve iPad Air 1GB RAM.")
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

    @objc private func toggleProxy(_ sender: UISwitch) {
        AppSettings.shared.useProxyByDefault = sender.isOn
    }

    private func confirmClearDownloads() {
        let alert = UIAlertController(title: "Clear All Downloads?", message: "This will remove all downloaded offline episodes from storage.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            for item in DownloadManager.shared.items {
                DownloadManager.shared.deleteDownload(id: item.id)
            }
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
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
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
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

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true)
    }
}

