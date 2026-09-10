import Foundation
import AVKit

public final class PictureInPictureManager: NSObject, AVPictureInPictureControllerDelegate {
    public static let shared = PictureInPictureManager()

    public private(set) var pipController: AVPictureInPictureController?

    public var isPictureInPictureSupported: Bool {
        return AVPictureInPictureController.isPictureInPictureSupported()
    }

    public var isPictureInPictureActive: Bool {
        return pipController?.isPictureInPictureActive ?? false
    }

    public func setupPictureInPicture(with playerLayer: AVPlayerLayer) {
        guard isPictureInPictureSupported else { return }

        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
    }

    public func startPictureInPicture() {
        pipController?.startPictureInPicture()
    }

    public func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }

    // MARK: - AVPictureInPictureControllerDelegate
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP: Will Start")
    }

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP: Did Start")
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("PiP: Failed with error \(error)")
    }

    public func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP: Will Stop")
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP: Did Stop")
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
