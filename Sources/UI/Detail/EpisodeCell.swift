import UIKit

public final class EpisodeCell: UITableViewCell {
    public static let reuseIdentifier = "EpisodeCell"

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    public var onActionTapped: (() -> Void)?
    public var onDeleteTapped: (() -> Void)?

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

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setTitle("⬇ Download", for: .normal)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.backgroundColor = AppTheme.primaryAccent
        actionButton.layer.cornerRadius = 6
        actionButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        actionButton.addTarget(self, action: #selector(handleActionTap), for: .touchUpInside)
        contentView.addSubview(actionButton)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.setTitle("🗑️", for: .normal)
        deleteButton.backgroundColor = AppTheme.cardBackground
        deleteButton.layer.cornerRadius = 6
        deleteButton.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        deleteButton.addTarget(self, action: #selector(handleDeleteTap), for: .touchUpInside)
        deleteButton.isHidden = true
        contentView.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -8),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -8),

            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 32),

            deleteButton.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 36),
            deleteButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    public func configure(with episode: Episode, downloadItem: DownloadItem?) {
        titleLabel.text = episode.title

        if let item = downloadItem {
            deleteButton.isHidden = false
            switch item.state {
            case .completed:
                statusLabel.text = "✓ Offline Ready (\(item.formattedSize))"
                statusLabel.textColor = AppTheme.success
                actionButton.setTitle("▶ Play", for: .normal)
                actionButton.backgroundColor = AppTheme.success

            case .downloading:
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
                statusLabel.text = "Paused • \(item.formattedSize)"
                statusLabel.textColor = AppTheme.textSecondary
                actionButton.setTitle("▶ Resume", for: .normal)
                actionButton.backgroundColor = AppTheme.cardBackground

            case .queued:
                statusLabel.text = "Queued for download"
                statusLabel.textColor = AppTheme.textSecondary
                actionButton.setTitle("⏳ Queued", for: .normal)
                actionButton.backgroundColor = AppTheme.cardBackground

            case .failed:
                statusLabel.text = "Failed: \(item.errorMessage ?? "Error")"
                statusLabel.textColor = AppTheme.primaryAccent
                actionButton.setTitle("↻ Retry", for: .normal)
                actionButton.backgroundColor = AppTheme.primaryAccent
            }
        } else {
            statusLabel.text = "Online Stream / Offline Download"
            statusLabel.textColor = AppTheme.textSecondary
            actionButton.setTitle("▶ Play", for: .normal)
            actionButton.backgroundColor = AppTheme.primaryAccent
            deleteButton.isHidden = true
        }
    }

    @objc private func handleActionTap() {
        onActionTapped?()
    }

    @objc private func handleDeleteTap() {
        onDeleteTapped?()
    }
}

