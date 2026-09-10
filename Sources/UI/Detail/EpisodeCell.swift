import UIKit

public final class EpisodeCell: UITableViewCell {
    public static let reuseIdentifier = "EpisodeCell"

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)

    public var onDownloadAction: (() -> Void)?
    public var onPlayAction: (() -> Void)?

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

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = AppTheme.textPrimary
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        contentView.addSubview(titleLabel)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = AppTheme.textSecondary
        statusLabel.font = UIFont.systemFont(ofSize: 12)
        contentView.addSubview(statusLabel)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.setTitle("▶ Play", for: .normal)
        playButton.setTitleColor(.white, for: .normal)
        playButton.backgroundColor = AppTheme.cardBackground
        playButton.layer.cornerRadius = 6
        playButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        playButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        contentView.addSubview(playButton)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setTitle("⬇ Download", for: .normal)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.backgroundColor = AppTheme.primaryAccent
        actionButton.layer.cornerRadius = 6
        actionButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        actionButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)
        contentView.addSubview(actionButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: playButton.leadingAnchor, constant: -8),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: playButton.leadingAnchor, constant: -8),

            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 32),

            playButton.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
            playButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            playButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    public func configure(with episode: Episode, downloadItem: DownloadItem?) {
        titleLabel.text = episode.title

        if let item = downloadItem {
            switch item.state {
            case .completed:
                statusLabel.text = "✓ Downloaded (\(item.formattedSize))"
                statusLabel.textColor = AppTheme.success
                actionButton.setTitle("▶ Offline", for: .normal)
                actionButton.backgroundColor = AppTheme.success
                playButton.isHidden = true
            case .downloading:
                let pct = Int(item.progress * 100)
                statusLabel.text = "Downloading \(pct)% • \(item.formattedSize)"
                statusLabel.textColor = AppTheme.secondaryAccent
                actionButton.setTitle("⏸ Pause", for: .normal)
                actionButton.backgroundColor = AppTheme.cardBackground
                playButton.isHidden = false
            case .paused:
                statusLabel.text = "Paused • \(item.formattedSize)"
                statusLabel.textColor = AppTheme.textSecondary
                actionButton.setTitle("▶ Resume", for: .normal)
                actionButton.backgroundColor = AppTheme.cardBackground
                playButton.isHidden = false
            case .queued:
                statusLabel.text = "Queued for download"
                statusLabel.textColor = AppTheme.textSecondary
                actionButton.setTitle("⏳ Queued", for: .normal)
                actionButton.backgroundColor = AppTheme.cardBackground
                playButton.isHidden = false
            case .failed:
                statusLabel.text = "Download failed: \(item.errorMessage ?? "Error")"
                statusLabel.textColor = AppTheme.primaryAccent
                actionButton.setTitle("↻ Retry", for: .normal)
                actionButton.backgroundColor = AppTheme.primaryAccent
                playButton.isHidden = false
            }
        } else {
            statusLabel.text = "Online Stream"
            statusLabel.textColor = AppTheme.textSecondary
            actionButton.setTitle("⬇ Download", for: .normal)
            actionButton.backgroundColor = AppTheme.primaryAccent
            playButton.isHidden = false
        }
    }

    @objc private func downloadTapped() {
        onDownloadAction?()
    }

    @objc private func playTapped() {
        onPlayAction?()
    }
}

