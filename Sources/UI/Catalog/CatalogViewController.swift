import UIKit

public final class CatalogViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    private var collectionView: UICollectionView!
    private let refreshControl = UIRefreshControl()
    private let activityIndicator = UIActivityIndicatorView(style: .whiteLarge)
    private let emptyLabel = UILabel()

    private var animeList: [Anime] = []
    private var currentPage = 1
    private var isLoading = false
    private var canLoadMore = true

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Matnami Catalog"
        view.backgroundColor = AppTheme.background

        setupCollectionView()
        setupUI()
        setupNavigationBar()

        NotificationCenter.default.addObserver(self, selector: #selector(sourceChanged), name: .sourceDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sourceChanged), name: .appDidReset, object: nil)
        loadData(reset: true)
    }

    private func setupNavigationBar() {
        let sourceName = SourceManager.shared.activeSource?.name ?? "Anime"
        title = "Matnami (\(sourceName))"
        if SourceManager.shared.sources.count > 1 {
            let sourceBtn = UIBarButtonItem(title: "📡 \(sourceName)", style: .plain, target: self, action: #selector(promptSourceSelection))
            navigationItem.rightBarButtonItem = sourceBtn
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc private func sourceChanged() {
        setupNavigationBar()
        loadData(reset: true)
    }

    @objc private func promptSourceSelection() {
        let alert = UIAlertController(title: "Select Anime Source", message: nil, preferredStyle: .actionSheet)
        for s in SourceManager.shared.sources {
            alert.addAction(UIAlertAction(title: s.name, style: .default) { _ in
                SourceManager.shared.setActiveSource(id: s.id)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = AppTheme.background
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(AnimeGridCell.self, forCellWithReuseIdentifier: AnimeGridCell.reuseIdentifier)

        refreshControl.tintColor = AppTheme.primaryAccent
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        collectionView.addSubview(refreshControl)

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupUI() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = AppTheme.primaryAccent
        view.addSubview(activityIndicator)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = AppTheme.textSecondary
        emptyLabel.font = UIFont.systemFont(ofSize: 15)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    @objc private func handleRefresh() {
        loadData(reset: true)
    }

    private func loadData(reset: Bool) {
        guard !isLoading else { return }
        guard let source = SourceManager.shared.activeSource else {
            emptyLabel.text = "No source configured. Check Settings."
            emptyLabel.isHidden = false
            return
        }

        if reset {
            currentPage = 1
            canLoadMore = true
            if animeList.isEmpty {
                activityIndicator.startAnimating()
            }
        }

        isLoading = true
        emptyLabel.isHidden = true

        AnimeScraperEngine.shared.fetchCatalog(source: source, page: currentPage) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            self.activityIndicator.stopAnimating()
            self.refreshControl.endRefreshing()

            switch result {
            case .success(let items):
                if reset {
                    self.animeList = items
                } else {
                    self.animeList.append(contentsOf: items)
                }

                if items.isEmpty {
                    self.canLoadMore = false
                } else {
                    self.currentPage += 1
                }

                self.emptyLabel.isHidden = !self.animeList.isEmpty
                self.emptyLabel.text = "No anime found for this source."
                self.collectionView.reloadData()

            case .failure(let error):
                if self.animeList.isEmpty {
                    self.emptyLabel.text = "Failed to load catalog:\n\(error.localizedDescription)"
                    self.emptyLabel.isHidden = false
                }
            }
        }
    }

    // MARK: - UICollectionViewDataSource
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return animeList.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AnimeGridCell.reuseIdentifier, for: indexPath) as! AnimeGridCell
        cell.configure(with: animeList[indexPath.item])
        return cell
    }

    // MARK: - UICollectionViewDelegateFlowLayout
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        let padding: CGFloat = 16
        let spacing: CGFloat = 12
        // On iPad (width > 600) show 4 to 5 columns; on iPhone show 2 or 3
        let columns: CGFloat = width > 700 ? 5 : (width > 480 ? 3 : 2)
        let totalSpacing = (padding * 2) + (spacing * (columns - 1))
        let itemWidth = floor((width - totalSpacing) / columns)
        let itemHeight = floor(itemWidth * 1.48) // Poster aspect ratio
        return CGSize(width: itemWidth, height: itemHeight)
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let anime = animeList[indexPath.item]
        let detailVC = AnimeDetailViewController(anime: anime)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let screenHeight = scrollView.frame.height

        if offsetY > contentHeight - (screenHeight * 1.8) && canLoadMore && !isLoading {
            loadData(reset: false)
        }
    }
}

