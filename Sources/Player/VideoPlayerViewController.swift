import UIKit
import AVKit
import MediaPlayer

public final class VideoPlayerViewController: UIViewController {

    // MARK: - Properties
    public let episodeTitle: String
    public let animeTitle: String
    public let mediaURL: URL
    public let httpHeaders: [String: String]
    public let isOffline: Bool

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var timeObserverToken: Any?
    private var isSeeking = false
    private var controlsTimer: Timer?

    // UI Elements
    private let controlsOverlayView = UIView()
    private let topBarView = UIView()
    private let bottomBarView = UIView()

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let pipButton = UIButton(type: .system)

    private let playPauseButton = UIButton(type: .system)
    private let rewindButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .whiteLarge)

    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let seekSlider = UISlider()

    // MARK: - Initializer
    public init(
        animeTitle: String,
        episodeTitle: String,
        mediaURL: URL,
        httpHeaders: [String: String] = [:],
        isOffline: Bool = false
    ) {
        self.animeTitle = animeTitle
        self.episodeTitle = episodeTitle
        self.mediaURL = mediaURL
        self.httpHeaders = httpHeaders
        self.isOffline = isOffline
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removePlayerObservers()
    }

    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupPlayer()
        setupUI()
        setupGestures()
        setupNowPlaying()
        startControlsTimer()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = view.bounds
        controlsOverlayView.frame = view.bounds
    }

    public override var prefersStatusBarHidden: Bool {
        return controlsOverlayView.alpha == 0.0
    }

    // MARK: - AVPlayer Setup
    private func setupPlayer() {
        let playerItem: AVPlayerItem
        if mediaURL.isFileURL {
            playerItem = AVPlayerItem(url: mediaURL)
        } else {
            var options: [String: Any] = [:]
            if !httpHeaders.isEmpty {
                options["AVURLAssetHTTPHeaderFieldsKey"] = httpHeaders
            }
            let asset = AVURLAsset(url: mediaURL, options: options)
            playerItem = AVPlayerItem(asset: asset)
        }

        player = AVPlayer(playerItem: playerItem)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        view.layer.addSublayer(layer)
        self.playerLayer = layer

        if PictureInPictureManager.shared.isPictureInPictureSupported {
            PictureInPictureManager.shared.setupPictureInPicture(with: layer)
        }

        activityIndicator.startAnimating()

        // Time observer (update slider every 0.5s)
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updatePlaybackProgress(currentTime: time)
        }

        playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.new], context: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        player?.play()
    }

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(AVPlayerItem.status) {
            if let item = object as? AVPlayerItem {
                if item.status == .readyToPlay {
                    activityIndicator.stopAnimating()
                    let duration = CMTimeGetSeconds(item.duration)
                    if !duration.isNaN && duration > 0 {
                        seekSlider.maximumValue = Float(duration)
                        durationLabel.text = formatTime(seconds: duration)
                    }
                } else if item.status == .failed {
                    activityIndicator.stopAnimating()
                    showPlaybackError(message: item.error?.localizedDescription ?? "Failed to load video stream")
                }
            }
        }
    }

    private func removePlayerObservers() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.currentItem?.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        player?.pause()
        player = nil
    }

    // MARK: - UI Layout
    private func setupUI() {
        controlsOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        view.addSubview(controlsOverlayView)

        // Activity Indicator
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        controlsOverlayView.addSubview(activityIndicator)

        // Top Bar
        topBarView.translatesAutoresizingMaskIntoConstraints = false
        controlsOverlayView.addSubview(topBarView)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("✕ Close", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        topBarView.addSubview(closeButton)

        pipButton.translatesAutoresizingMaskIntoConstraints = false
        pipButton.setTitle("PiP ⧉", for: .normal)
        pipButton.setTitleColor(.white, for: .normal)
        pipButton.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        pipButton.isHidden = !PictureInPictureManager.shared.isPictureInPictureSupported
        pipButton.addTarget(self, action: #selector(handlePiP), for: .touchUpInside)
        topBarView.addSubview(pipButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "\(animeTitle) • \(episodeTitle)"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textAlignment = .center
        topBarView.addSubview(titleLabel)

        // Center Controls
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.setTitle("⏸", for: .normal)
        playPauseButton.setTitleColor(.white, for: .normal)
        playPauseButton.titleLabel?.font = UIFont.systemFont(ofSize: 48)
        playPauseButton.addTarget(self, action: #selector(handlePlayPause), for: .touchUpInside)
        controlsOverlayView.addSubview(playPauseButton)

        rewindButton.translatesAutoresizingMaskIntoConstraints = false
        rewindButton.setTitle("⏪ -10s", for: .normal)
        rewindButton.setTitleColor(.white, for: .normal)
        rewindButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        rewindButton.addTarget(self, action: #selector(handleRewind), for: .touchUpInside)
        controlsOverlayView.addSubview(rewindButton)

        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.setTitle("+10s ⏩", for: .normal)
        forwardButton.setTitleColor(.white, for: .normal)
        forwardButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        forwardButton.addTarget(self, action: #selector(handleForward), for: .touchUpInside)
        controlsOverlayView.addSubview(forwardButton)

        // Bottom Bar
        bottomBarView.translatesAutoresizingMaskIntoConstraints = false
        controlsOverlayView.addSubview(bottomBarView)

        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        currentTimeLabel.text = "00:00"
        currentTimeLabel.textColor = .white
        currentTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        bottomBarView.addSubview(currentTimeLabel)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.text = "--:--"
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        durationLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        bottomBarView.addSubview(durationLabel)

        seekSlider.translatesAutoresizingMaskIntoConstraints = false
        seekSlider.minimumValue = 0.0
        seekSlider.tintColor = UIColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1.0)
        seekSlider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        seekSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        seekSlider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside])
        bottomBarView.addSubview(seekSlider)

        // Auto Layout Constraints
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: controlsOverlayView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: controlsOverlayView.centerYAnchor),

            // Top Bar
            topBarView.topAnchor.constraint(equalTo: controlsOverlayView.topAnchor, constant: 20),
            topBarView.leadingAnchor.constraint(equalTo: controlsOverlayView.leadingAnchor, constant: 20),
            topBarView.trailingAnchor.constraint(equalTo: controlsOverlayView.trailingAnchor, constant: -20),
            topBarView.heightAnchor.constraint(equalToConstant: 44),

            closeButton.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),

            pipButton.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor),
            pipButton.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: pipButton.leadingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),

            // Center Controls
            playPauseButton.centerXAnchor.constraint(equalTo: controlsOverlayView.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: controlsOverlayView.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 80),
            playPauseButton.heightAnchor.constraint(equalToConstant: 80),

            rewindButton.trailingAnchor.constraint(equalTo: playPauseButton.leadingAnchor, constant: -40),
            rewindButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),

            forwardButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 40),
            forwardButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),

            // Bottom Bar
            bottomBarView.leadingAnchor.constraint(equalTo: controlsOverlayView.leadingAnchor, constant: 24),
            bottomBarView.trailingAnchor.constraint(equalTo: controlsOverlayView.trailingAnchor, constant: -24),
            bottomBarView.bottomAnchor.constraint(equalTo: controlsOverlayView.bottomAnchor, constant: -30),
            bottomBarView.heightAnchor.constraint(equalToConstant: 50),

            currentTimeLabel.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor),
            currentTimeLabel.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 50),

            durationLabel.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor),
            durationLabel.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 50),

            seekSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 12),
            seekSlider.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -12),
            seekSlider.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor)
        ])
    }

    // MARK: - Gestures
    private func setupGestures() {
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        view.addGestureRecognizer(singleTap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        singleTap.require(toFail: doubleTap)
    }

    @objc private func handleSingleTap() {
        let isVisible = controlsOverlayView.alpha > 0.0
        UIView.animate(withDuration: 0.25) {
            self.controlsOverlayView.alpha = isVisible ? 0.0 : 1.0
            self.setNeedsStatusBarAppearanceUpdate()
        }
        if !isVisible {
            startControlsTimer()
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        let width = view.bounds.width
        if location.x < width * 0.35 {
            handleRewind()
        } else if location.x > width * 0.65 {
            handleForward()
        } else {
            handlePlayPause()
        }
    }

    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) {
                self?.controlsOverlayView.alpha = 0.0
                self?.setNeedsStatusBarAppearanceUpdate()
            }
        }
    }

    // MARK: - Playback Actions
    @objc private func handlePlayPause() {
        guard let player = player else { return }
        if player.rate > 0 {
            player.pause()
            playPauseButton.setTitle("▶️", for: .normal)
        } else {
            player.play()
            playPauseButton.setTitle("⏸", for: .normal)
        }
        startControlsTimer()
    }

    @objc private func handleRewind() {
        seekBy(offset: -10)
    }

    @objc private func handleForward() {
        seekBy(offset: 10)
    }

    private func seekBy(offset: Double) {
        guard let player = player else { return }
        let current = CMTimeGetSeconds(player.currentTime())
        let target = max(0, current + offset)
        player.seek(to: CMTime(seconds: target, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), toleranceBefore: .zero, toleranceAfter: .zero)
        startControlsTimer()
    }

    @objc private func handleClose() {
        removePlayerObservers()
        dismiss(animated: true, completion: nil)
    }

    @objc private func handlePiP() {
        PictureInPictureManager.shared.startPictureInPicture()
    }

    @objc private func sliderTouchDown() {
        isSeeking = true
        controlsTimer?.invalidate()
    }

    @objc private func sliderValueChanged() {
        currentTimeLabel.text = formatTime(seconds: Double(seekSlider.value))
    }

    @objc private func sliderTouchUp() {
        let targetTime = CMTime(seconds: Double(seekSlider.value), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.isSeeking = false
            self?.startControlsTimer()
        }
    }

    private func updatePlaybackProgress(currentTime: CMTime) {
        guard !isSeeking else { return }
        let seconds = CMTimeGetSeconds(currentTime)
        if !seconds.isNaN {
            seekSlider.value = Float(seconds)
            currentTimeLabel.text = formatTime(seconds: seconds)
        }
    }

    @objc private func playerItemDidReachEnd() {
        playPauseButton.setTitle("▶️", for: .normal)
        controlsOverlayView.alpha = 1.0
    }

    private func showPlaybackError(message: String) {
        let alert = UIAlertController(title: "Playback Failed", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .cancel) { [weak self] _ in
            self?.handleClose()
        })
        present(alert, animated: true)
    }

    private func formatTime(seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        if mins >= 60 {
            let hrs = mins / 60
            let remainderMins = mins % 60
            return String(format: "%02d:%02d:%02d", hrs, remainderMins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - Lockscreen & Control Center Now Playing
    private func setupNowPlaying() {
        let nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: episodeTitle,
            MPMediaItemPropertyArtist: animeTitle
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            self?.playPauseButton.setTitle("⏸", for: .normal)
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.playPauseButton.setTitle("▶️", for: .normal)
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.handleForward()
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.handleRewind()
            return .success
        }
    }
}

