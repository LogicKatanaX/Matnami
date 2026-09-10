import UIKit

public final class DownloadCell: UITableViewCell {
    public static let reuseIdentifier = "DownloadCell"

    private let coverImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let statusLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    public var onActionTapped: (() -> Void)?

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = AppTheme.secondaryBackground
        selectionStyle = .none

        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.layer.cornerRadius = 6
        coverImageView.clipsToBounds = true
        coverImageView.backgroundColor = AppTheme.cardBackground
        contentView.addSubview(coverImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = AppTheme.textPrimary
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.numberOfLines = 1
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.textColor = AppTheme.textSecondary
        subtitleLabel.font = UIFont.systemFont(ofSize: 13)
        contentView.addSubview(subtitleLabel)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = AppTheme.primaryAccent
        progressView.trackTintColor = AppTheme.cardBackground
        contentView.addSubview(progressView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = AppTheme.textTertiary
        statusLabel.font = UIFont.systemFont(ofSize: 12)
        contentView.addSubview(statusLabel)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.layer.cornerRadius = 6
        actionButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
        contentView.addSubview(actionButton)

        NSLayoutConstraint.activate([
            coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            coverImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverImageView.widthAnchor.constraint(equalToConstant: 50),
            coverImageView.heightAnchor.constraint(equalToConstant: 70),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),

            progressView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12),
            progressView.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -12),
            progressView.heightAnchor.constraint(equalToConstant: 4),

            statusLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 74),
            actionButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    public func configure(with item: DownloadItem) {
        titleLabel.text = item.animeTitle
        subtitleLabel.text = "Episode \(item.episodeNumber) • \(item.quality) (\(item.serverName))"

        if let cover = item.coverURL, !cover.isEmpty {
            _ = ImageLoader.shared.loadImage(from: cover, maxDimension: 256) { [weak self] img in
                self?.coverImageView.image = img
            }
        }

        switch item.state {
        case .completed:
            progressView.isHidden = true
            statusLabel.text = "✓ Downloaded • \(item.formattedSize)"
            statusLabel.textColor = AppTheme.success
            actionButton.setTitle("▶ Play", for: .normal)
            actionButton.backgroundColor = AppTheme.success
        case .downloading:
            progressView.isHidden = false
            progressView.progress = item.progress
            if item.totalBytes > 0 {
                let pct = Int(item.progress * 100)
                statusLabel.text = "Downloading \(pct)% • \(item.formattedSize)"
            } else {
                statusLabel.text = "Downloading • \(item.formattedSize)"
            }
            statusLabel.textColor = AppTheme.secondaryAccent
            actionButton.setTitle("⏸ Pause", for: .normal)
            actionButton.backgroundColor = AppTheme.cardBackground
        case .paused:
            progressView.isHidden = false
            progressView.progress = item.progress
            statusLabel.text = "Paused • \(item.formattedSize)"
            statusLabel.textColor = AppTheme.textSecondary
            actionButton.setTitle("▶ Resume", for: .normal)
            actionButton.backgroundColor = AppTheme.cardBackground
        case .queued:
            progressView.isHidden = true
            statusLabel.text = "Queued for download..."
            statusLabel.textColor = AppTheme.textSecondary
            actionButton.setTitle("⏳ Queued", for: .normal)
            actionButton.backgroundColor = AppTheme.cardBackground
        case .failed:
            progressView.isHidden = true
            statusLabel.text = "Failed: \(item.errorMessage ?? "Error")"
            statusLabel.textColor = AppTheme.primaryAccent
            actionButton.setTitle("↻ Retry", for: .normal)
            actionButton.backgroundColor = AppTheme.primaryAccent
        }
    }

    @objc private func handleAction() {
        onActionTapped?()
    }
}

