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
        return 5
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return qualityOptions.count // Preferred Video Quality
        case 1: return 3                    // Storage & Deletion Management
        case 2: return 5                    // Anime Sources & Custom Websites
        case 3: return 4                    // Cloudflare Edge Proxy (ISP Bypass)
        case 4: return 2                    // Device & Architecture Info
        default: return 0
        }
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Preferred Video Quality"
        case 1: return "Storage & Deletion Management"
        case 2: return "Anime Sources & Custom Websites"
        case 3: return "Cloudflare Edge Proxy (ISP Bypass)"
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
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Add Custom Website / Source (+)"
                cell.detailTextLabel?.text = "URL / JSON"
                cell.textLabel?.textColor = AppTheme.primaryAccent
                cell.accessoryType = .disclosureIndicator
            } else if indexPath.row == 2 {
                cell.textLabel?.text = "Test Active Source Connection"
                cell.detailTextLabel?.text = "Run Diagnosis"
                cell.textLabel?.textColor = AppTheme.success
                cell.accessoryType = .disclosureIndicator
            } else if indexPath.row == 3 {
                cell.textLabel?.text = "Sync Sources from Cloud (OTA)"
                cell.detailTextLabel?.text = "Check Updates"
                cell.textLabel?.textColor = AppTheme.primaryAccent
            } else {
                cell.textLabel?.text = "Custom OTA Feed URL"
                let currentUrl = AppSettings.shared.customOTAUrl
                cell.detailTextLabel?.text = currentUrl.contains("LogicKatanaX") ? "Default (GitHub)" : "Custom"
                cell.accessoryType = .disclosureIndicator
            }

        case 3:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Custom Worker Proxy URL"
                let current = AppSettings.shared.proxyBaseUrl
                cell.detailTextLabel?.text = current.contains("santamcyber") ? "Default" : (current.contains("workers.dev") ? "Custom Worker" : "Configured")
                cell.accessoryType = .disclosureIndicator
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Proxy Video Streams & Downloads"
                let on = AppSettings.shared.useProxyForStreams
                cell.detailTextLabel?.text = on ? "Enabled" : "Disabled"
                cell.detailTextLabel?.textColor = on ? AppTheme.success : AppTheme.textSecondary
                cell.accessoryType = .disclosureIndicator
            } else if indexPath.row == 2 {
                cell.textLabel?.text = "⚡ Test Worker Reachability"
                cell.detailTextLabel?.text = "Ping Proxy"
                cell.textLabel?.textColor = AppTheme.success
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Reset Proxy to Default"
                cell.detailTextLabel?.text = "Restore"
                cell.accessoryType = .none
            }

        case 4:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Hardware Target"
                cell.detailTextLabel?.text = "iPad Air 1 (Apple A7 • 1GB RAM)"
            } else {
                cell.textLabel?.text = "Playback Mode"
                cell.detailTextLabel?.text = "Hardware AVC/H.264 (Stream & Offline)"
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
                promptSelectSource(from: indexPath)
            } else if indexPath.row == 1 {
                promptAddCustomSource(from: indexPath)
            } else if indexPath.row == 2 {
                runSourceConnectionTest()
            } else if indexPath.row == 3 {
                triggerOTASync()
            } else {
                promptEditOTAUrl()
            }

        case 3:
            if indexPath.row == 0 {
                promptEditProxyUrl()
            } else if indexPath.row == 1 {
                AppSettings.shared.useProxyForStreams.toggle()
                tableView.reloadRows(at: [indexPath], with: .none)
            } else if indexPath.row == 2 {
                testProxyReachability()
            } else {
                AppSettings.shared.proxyBaseUrl = AppSettings.defaultProxyBase
                AppSettings.shared.useProxyForStreams = false
                tableView.reloadSections(IndexSet(integer: 3), with: .none)
                showAlert(title: "Proxy Reset", message: "Worker proxy restored to default endpoint.")
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

    // MARK: - Custom Source Addition & Testing
    private func promptAddCustomSource(from indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Add Custom Website / Source",
            message: "You can add any website by entering its URL or pasting a custom JSON configuration.",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "Quick Add by URL (Auto-Configure)", style: .default) { [weak self] _ in
            self?.promptQuickAddByURL()
        })

        alert.addAction(UIAlertAction(title: "Import from Clipboard / JSON", style: .default) { [weak self] _ in
            self?.promptImportJSON()
        })

        alert.addAction(UIAlertAction(title: "Import from Remote JSON URL", style: .default) { [weak self] _ in
            self?.promptImportRemoteURL()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView.cellForRow(at: indexPath) ?? view
            popover.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = [.up, .down]
        }

        present(alert, animated: true)
    }

    private func promptQuickAddByURL() {
        let alert = UIAlertController(
            title: "Quick Add Website",
            message: "Enter the website name and base URL. Matnami will auto-configure resilient scraping rules and direct MP4 extraction.",
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.placeholder = "Source Name (e.g. My Anime)"
            field.autocapitalizationType = .words
        }

        alert.addTextField { field in
            field.placeholder = "Base URL (e.g. https://example.com)"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
        }

        alert.addTextField { field in
            field.placeholder = "Catalog URL (optional, e.g. /anime/)"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Add Source", style: .default) { [weak self] _ in
            guard let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let rawBase = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines), !rawBase.isEmpty else {
                self?.showAlert(title: "Missing Information", message: "Please provide both a name and a valid website URL.")
                return
            }

            let base = rawBase.hasSuffix("/") ? String(rawBase.dropLast()) : rawBase
            let rawCatalog = alert.textFields?[2].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let catalog: String
            if rawCatalog.isEmpty {
                catalog = "\(base)/"
            } else if rawCatalog.hasPrefix("http://") || rawCatalog.hasPrefix("https://") {
                catalog = rawCatalog
            } else {
                let cleanCat = rawCatalog.hasPrefix("/") ? String(rawCatalog.dropFirst()) : rawCatalog
                catalog = "\(base)/\(cleanCat)"
            }

            let sourceId = name.lowercased().replacingOccurrences(of: " ", with: "_").filter { $0.isLetter || $0.isNumber || $0 == "_" }

            let newConfig = AnimeSourceConfig(
                id: sourceId.isEmpty ? "custom_\(Int(Date().timeIntervalSince1970))" : sourceId,
                name: name,
                baseURL: base,
                catalogPattern: catalog,
                searchPattern: "\(base)/?s={query}",
                cardSelector: "article.type-post, article.post, .animepost, .item, .bsx, .detpost, .directory-list a[href], a[href*='-Series/']",
                linkSelector: "a[href]",
                titleSelector: "h2.entry-title a, h2, h3, .title, a",
                coverSelector: "img",
                scoreSelector: nil,
                synopsisSelector: ".entry-content, .entry-summary, .desc, p",
                episodeListSelector: "a[href*='Season-'], a[href*='Episode-'], a[href*='-Video/'], a[href*='/episode/'], a[href*='-episode-']",
                episodeLinkSelector: "a",
                episodeTitleSelector: "a",
                playerIframeSelector: nil,
                serverItemSelector: "a[href*='.mp4'], source[src*='.mp4'], a[href*='/USER-DATA/']",
                ajaxAction: nil,
                useProxy: false
            )

            SourceManager.shared.addSource(newConfig, makeActive: true)
            self?.tableView.reloadData()

            let successAlert = UIAlertController(
                title: "Source Added!",
                message: "'\(name)' is now your active source. Would you like to run a connectivity test now?",
                preferredStyle: .alert
            )
            successAlert.addAction(UIAlertAction(title: "Later", style: .cancel, handler: nil))
            successAlert.addAction(UIAlertAction(title: "Test Now", style: .default) { [weak self] _ in
                self?.runSourceConnectionTest()
            })
            self?.present(successAlert, animated: true)
        })

        present(alert, animated: true)
    }

    private func promptImportJSON() {
        let clipboardText = UIPasteboard.general.string ?? ""
        let isJSONCandidate = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") ||
                              clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")

        let alert = UIAlertController(
            title: "Import Source from JSON",
            message: "Paste an AnimeSourceConfig JSON object below or import directly from clipboard.",
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.placeholder = "{\n  \"id\": \"mysource\",\n  \"name\": ...\n}"
            if isJSONCandidate {
                field.text = clipboardText
            }
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Import", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                self?.showAlert(title: "Empty Input", message: "Please paste a valid JSON string.")
                return
            }

            do {
                let imported = try SourceManager.shared.importSource(from: text)
                self?.tableView.reloadData()
                self?.showAlert(title: "Source Imported!", message: "Successfully imported and activated '\(imported.name)'.")
            } catch {
                self?.showAlert(title: "Import Error", message: "Failed to parse JSON: \(error.localizedDescription)")
            }
        })

        present(alert, animated: true)
    }

    private func promptImportRemoteURL() {
        let alert = UIAlertController(
            title: "Import from Remote JSON URL",
            message: "Enter the URL of a raw JSON file (e.g. GitHub Gist or raw JSON file) containing source configurations.",
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.placeholder = "https://raw.githubusercontent.com/.../sources.json"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Fetch & Import", style: .default) { [weak self] _ in
            guard let urlStr = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: urlStr) else {
                self?.showAlert(title: "Invalid URL", message: "Please enter a valid HTTP/HTTPS URL.")
                return
            }

            let loading = UIAlertController(title: "Fetching...", message: "Downloading source definition...", preferredStyle: .alert)
            self?.present(loading, animated: true)

            URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        if let error = error {
                            self?.showAlert(title: "Download Failed", message: error.localizedDescription)
                            return
                        }
                        guard let data = data, let jsonStr = String(data: data, encoding: .utf8) else {
                            self?.showAlert(title: "Download Failed", message: "Invalid or empty response from server.")
                            return
                        }

                        do {
                            let imported = try SourceManager.shared.importSource(from: jsonStr)
                            self?.tableView.reloadData()
                            self?.showAlert(title: "Import Successful", message: "Imported and activated '\(imported.name)'.")
                        } catch {
                            self?.showAlert(title: "Parse Error", message: error.localizedDescription)
                        }
                    }
                }
            }.resume()
        })

        present(alert, animated: true)
    }

    private func runSourceConnectionTest() {
        guard let active = SourceManager.shared.activeSource else {
            showAlert(title: "No Active Source", message: "Please select or add a source first.")
            return
        }

        let progress = UIAlertController(
            title: "Auditing Source Connection",
            message: "Contacting '\(active.name)'...\nParsing catalog and testing hardware compatibility...",
            preferredStyle: .alert
        )
        present(progress, animated: true)

        SourceManager.shared.testSourceConnection(active) { [weak self] result in
            progress.dismiss(animated: true) {
                switch result {
                case .success(let summary):
                    let msg = """
                    • Source: \(summary.sourceName)
                    • HTTP Response: 200 OK
                    • Network Latency: \(summary.latencyMs) ms
                    • Catalog Items Found: \(summary.itemsFound)
                    • Sample Anime: "\(summary.sampleTitle)"
                    • Route: \(summary.isProxyUsed ? "Cloudflare Edge Proxy" : "Direct Connection")
                    • iPad Air 1 VDA: Ready for Hardware H.264
                    """
                    self?.showAlert(title: "✅ Connection Test Passed", message: msg)

                case .failure(let error):
                    let msg = """
                    Failed to extract anime catalog:
                    \(error.localizedDescription)

                    Diagnostics:
                    • Check if the website URL is accessible.
                    • If protected by Cloudflare bot wall, set "useProxy: true" in source config.
                    """
                    self?.showAlert(title: "❌ Connection Test Failed", message: msg)
                }
            }
        }
    }

    private func promptSelectSource(from indexPath: IndexPath) {
        let alert = UIAlertController(title: "Select Active Source", message: nil, preferredStyle: .actionSheet)
        let currentId = SourceManager.shared.activeSource?.id

        for s in SourceManager.shared.sources {
            let title = (s.id == currentId) ? "✓ \(s.name)" : s.name
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                SourceManager.shared.setActiveSource(id: s.id)
                self?.tableView.reloadData()
            })
        }

        if SourceManager.shared.sources.count > 1 {
            alert.addAction(UIAlertAction(title: "🗑️ Delete a Source...", style: .destructive) { [weak self] _ in
                self?.promptDeleteSource(from: indexPath)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView.cellForRow(at: indexPath) ?? view
            popover.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = [.up, .down]
        }
        present(alert, animated: true)
    }

    private func promptDeleteSource(from indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Delete Source",
            message: "Select a source to remove from Matnami:",
            preferredStyle: .actionSheet
        )

        for s in SourceManager.shared.sources {
            alert.addAction(UIAlertAction(title: "Delete \(s.name)", style: .destructive) { [weak self] _ in
                let ok = SourceManager.shared.deleteSource(id: s.id)
                self?.tableView.reloadData()
                if ok {
                    self?.showAlert(title: "Source Removed", message: "'\(s.name)' has been removed.")
                } else {
                    self?.showAlert(title: "Cannot Delete", message: "Matnami requires at least one configured source.")
                }
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView.cellForRow(at: indexPath) ?? view
            popover.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = [.up, .down]
        }
        present(alert, animated: true)
    }

    private func promptEditOTAUrl() {
        let alert = UIAlertController(
            title: "Custom OTA Feed URL",
            message: "Provide a custom raw JSON URL to sync sources from your own repository or GitHub Gist.",
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.text = AppSettings.shared.customOTAUrl
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.clearButtonMode = .whileEditing
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Reset to Default", style: .destructive) { [weak self] _ in
            AppSettings.shared.customOTAUrl = "https://raw.githubusercontent.com/LogicKatanaX/Matnami/main/Sources/sources.json"
            self?.tableView.reloadData()
            self?.showAlert(title: "OTA URL Reset", message: "Reset to default official repository feed.")
        })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            if let newUrl = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !newUrl.isEmpty {
                AppSettings.shared.customOTAUrl = newUrl
                self?.tableView.reloadData()
                self?.showAlert(title: "OTA Feed Saved", message: "Remote sync feed updated.")
            }
        })

        present(alert, animated: true)
    }

    private func promptEditProxyUrl() {
        let alert = UIAlertController(
            title: "Cloudflare Worker Proxy",
            message: "Enter your Cloudflare Worker URL to bypass ISP blocks on HentaiFreak & restricted media hosts:\n\nFormat: https://<worker>.workers.dev/?url=",
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.text = AppSettings.shared.proxyBaseUrl
            field.placeholder = "https://<worker>.workers.dev/?url="
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.clearButtonMode = .whileEditing
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            if var text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                if !text.contains("?url=") && text.contains("workers.dev") {
                    if !text.hasSuffix("/") { text += "/" }
                    text += "?url="
                }
                AppSettings.shared.proxyBaseUrl = text
                AppSettings.shared.useProxyForStreams = true
                self?.tableView.reloadData()
                self?.showAlert(title: "Proxy Configured", message: "Edge worker set to:\n\(text)\n\nStreaming & Download proxy has been enabled.")
            }
        })

        present(alert, animated: true)
    }

    private func testProxyReachability() {
        let proxyBase = AppSettings.shared.proxyBaseUrl
        guard let testURL = URL(string: proxyBase + "https://httpbin.org/get") ?? URL(string: proxyBase) else {
            showAlert(title: "Invalid URL", message: "Configured worker URL is invalid.")
            return
        }

        let alert = UIAlertController(title: "Testing Worker Proxy", message: "Pinging Cloudflare edge...", preferredStyle: .alert)
        present(alert, animated: true)

        let start = CACurrentMediaTime()
        var req = URLRequest(url: testURL)
        req.timeoutInterval = 10.0
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let elapsed = Int((CACurrentMediaTime() - start) * 1000)
            DispatchQueue.main.async {
                alert.dismiss(animated: true) {
                    if let error = error {
                        self?.showAlert(title: "Worker Unreachable", message: "Error:\n\(error.localizedDescription)\n\nPlease check your worker URL or internet connection.")
                    } else if let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) {
                        self?.showAlert(title: "Worker Online! ⚡", message: "Status: \(http.statusCode) OK\nLatency: \(elapsed) ms\nCloudflare edge proxy is active and ready to stream.")
                    } else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        self?.showAlert(title: "Worker Response HTTP \(code)", message: "Worker reached but returned status \(code).")
                    }
                }
            }
        }.resume()
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true)
    }
}


