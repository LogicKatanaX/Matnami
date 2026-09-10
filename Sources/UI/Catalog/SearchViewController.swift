import UIKit

public final class SearchViewController: UIViewController, UISearchBarDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    private let searchBar = UISearchBar()
    private var collectionView: UICollectionView!
    private let activityIndicator = UIActivityIndicatorView(style: .whiteLarge)
    private let messageLabel = UILabel()

    private var searchResults: [Anime] = []
    private var isSearching = false

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search"
        view.backgroundColor = AppTheme.background

        setupSearchBar()
        setupCollectionView()
        setupMessageLabel()
    }

    private func setupSearchBar() {
        searchBar.delegate = self
        searchBar.placeholder = "Search anime..."
        searchBar.barTintColor = AppTheme.background
        searchBar.tintColor = AppTheme.primaryAccent
        searchBar.isTranslucent = false
        if let textField = searchBar.value(forKey: "searchField") as? UITextField {
            textField.textColor = .white
            textField.backgroundColor = AppTheme.cardBackground
        }
        navigationItem.titleView = searchBar
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
        collectionView.keyboardDismissMode = .onDrag
        collectionView.register(AnimeGridCell.self, forCellWithReuseIdentifier: AnimeGridCell.reuseIdentifier)
        view.addSubview(collectionView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = AppTheme.primaryAccent
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupMessageLabel() {
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textColor = AppTheme.textSecondary
        messageLabel.font = UIFont.systemFont(ofSize: 15)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.text = "Search for any anime title above"
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    // MARK: - UISearchBarDelegate
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        guard let query = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { return }
        performSearch(query: query)
    }

    private func performSearch(query: String) {
        guard let source = SourceManager.shared.activeSource else { return }
        isSearching = true
        activityIndicator.startAnimating()
        messageLabel.isHidden = true
        searchResults = []
        collectionView.reloadData()

        AnimeScraperEngine.shared.searchAnime(source: source, query: query) { [weak self] result in
            guard let self = self else { return }
            self.isSearching = false
            self.activityIndicator.stopAnimating()

            switch result {
            case .success(let items):
                self.searchResults = items
                self.collectionView.reloadData()
                self.messageLabel.isHidden = !items.isEmpty
                self.messageLabel.text = "No results found for \"\(query)\""
            case .failure(let error):
                self.messageLabel.text = "Search error:\n\(error.localizedDescription)"
                self.messageLabel.isHidden = false
            }
        }
    }

    // MARK: - UICollectionViewDataSource
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return searchResults.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AnimeGridCell.reuseIdentifier, for: indexPath) as! AnimeGridCell
        cell.configure(with: searchResults[indexPath.item])
        return cell
    }

    // MARK: - UICollectionViewDelegateFlowLayout
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        let padding: CGFloat = 16
        let spacing: CGFloat = 12
        let columns: CGFloat = width > 700 ? 5 : (width > 480 ? 3 : 2)
        let totalSpacing = (padding * 2) + (spacing * (columns - 1))
        let itemWidth = floor((width - totalSpacing) / columns)
        let itemHeight = floor(itemWidth * 1.48)
        return CGSize(width: itemWidth, height: itemHeight)
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let anime = searchResults[indexPath.item]
        let detailVC = AnimeDetailViewController(anime: anime)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}
