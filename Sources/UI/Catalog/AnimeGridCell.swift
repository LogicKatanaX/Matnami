import UIKit

public final class AnimeGridCell: UICollectionViewCell {
    public static let reuseIdentifier = "AnimeGridCell"

    private let coverImageView = UIImageView()
    private let titleLabel = UILabel()
    private let scoreBadge = UILabel()
    private let gradientView = UIView()
    private var imageTask: URLSessionDataTask?

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
        titleLabel.text = anime.title

        if !anime.score.isEmpty {
            scoreBadge.text = "★ \(anime.score)"
            scoreBadge.isHidden = false
        } else {
            scoreBadge.isHidden = true
        }

        imageTask?.cancel()
        coverImageView.image = nil

        if !anime.coverURL.isEmpty {
            imageTask = ImageLoader.shared.loadImage(from: anime.coverURL, maxDimension: 512) { [weak self] image in
                self?.coverImageView.image = image
            }
        }
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        coverImageView.image = nil
        titleLabel.text = nil
        scoreBadge.isHidden = true
    }
}

