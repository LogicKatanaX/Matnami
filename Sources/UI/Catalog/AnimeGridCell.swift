import UIKit

public final class AnimeGridCell: UICollectionViewCell {
    public static let reuseIdentifier = "AnimeGridCell"

    private let coverImageView = UIImageView()
    private let titleLabel = UILabel()
    private let scoreBadge = UILabel()
    private let gradientView = UIView()
    private var imageTask: URLSessionDataTask?
    private var currentAnimeId: String?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.backgroundColor = AppTheme.cardBackground
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true

        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        contentView.addSubview(coverImageView)

        // Gradient overlay at the bottom for title readability
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        gradientView.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        contentView.addSubview(gradientView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = AppTheme.textPrimary
        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)

        scoreBadge.translatesAutoresizingMaskIntoConstraints = false
        scoreBadge.backgroundColor = AppTheme.primaryAccent
        scoreBadge.textColor = .white
        scoreBadge.font = UIFont.systemFont(ofSize: 11, weight: .heavy)
        scoreBadge.textAlignment = .center
        scoreBadge.layer.cornerRadius = 4
        scoreBadge.clipsToBounds = true
        scoreBadge.isHidden = true
        contentView.addSubview(scoreBadge)

        NSLayoutConstraint.activate([
            coverImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            coverImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            gradientView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            gradientView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            scoreBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            scoreBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            scoreBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            scoreBadge.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    public func configure(with anime: Anime) {
        currentAnimeId = anime.id
        titleLabel.text = anime.title

        if !anime.score.isEmpty {
            scoreBadge.text = anime.score.hasPrefix("★") || anime.score.hasPrefix("▲") ? anime.score : "★ \(anime.score)"
            scoreBadge.isHidden = false
        } else {
            scoreBadge.isHidden = true
        }

        imageTask?.cancel()

        // 1. Immediately present procedural anime gradient poster (zero latency, never black)
        let placeholder = ImageLoader.shared.generatePosterPlaceholder(for: anime.title)
        coverImageView.image = placeholder

        // 2. If anime has an explicit coverURL, load it
        if !anime.coverURL.isEmpty {
            imageTask = ImageLoader.shared.loadImage(from: anime.coverURL, maxDimension: 512) { [weak self] image in
                guard let self = self, self.currentAnimeId == anime.id, let img = image else { return }
                UIView.transition(with: self.coverImageView, duration: 0.25, options: .transitionCrossDissolve, animations: {
                    self.coverImageView.image = img
                }, completion: nil)
            }
        } else {
            // 3. Query Kitsu metadata asynchronously to fetch official anime artwork
            let clean = TorrentTitleParser.parse(anime.title).cleanTitle
            KitsuMetadataService.shared.fetchMetadata(for: clean) { [weak self] kitsuMeta in
                guard let self = self, self.currentAnimeId == anime.id, let posterURL = kitsuMeta?.posterURL, !posterURL.isEmpty else { return }
                self.imageTask = ImageLoader.shared.loadImage(from: posterURL, maxDimension: 512) { [weak self] image in
                    guard let self = self, self.currentAnimeId == anime.id, let img = image else { return }
                    UIView.transition(with: self.coverImageView, duration: 0.3, options: .transitionCrossDissolve, animations: {
                        self.coverImageView.image = img
                    }, completion: nil)
                }
            }
        }
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentAnimeId = nil
        coverImageView.image = nil
        titleLabel.text = nil
        scoreBadge.isHidden = true
    }
}

