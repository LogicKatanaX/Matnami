import UIKit
import AVFoundation

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // 1. Configure AudioSession for background playback & Picture-in-Picture
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AppDelegate: Failed to initialize AVAudioSession: \(error)")
        }

        // 2. Apply theme
        AppTheme.applyGlobalAppearance()

        // 3. Initialize root navigation
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.backgroundColor = AppTheme.background
        win.rootViewController = TabBarController()
        win.makeKeyAndVisible()
        self.window = win

        // 4. Background OTA sync for latest anime sources
        DispatchQueue.global(qos: .utility).async {
            SourceManager.shared.syncOTA(from: AppSettings.shared.customOTAUrl) { result in
                switch result {
                case .success(let count):
                    print("AppDelegate: OTA sources successfully synced (\(count) active sources).")
                case .failure(let error):
                    print("AppDelegate: OTA sync skipped/offline: \(error.localizedDescription)")
                }
            }
        }

        return true
    }

    // Background URLSession event handling for downloads
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == "com.matnami.background-downloads" {
            DownloadManager.shared.backgroundCompletionHandler = completionHandler
        }
    }
}

