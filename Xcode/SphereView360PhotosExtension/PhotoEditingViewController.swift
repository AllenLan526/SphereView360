import AVFoundation
import Cocoa
import Photos
import PhotosUI

final class PhotoEditingViewController: NSViewController, PHContentEditingController {
    private var input: PHContentEditingInput?
    private var player: AVPlayer?
    private var image: PlatformImage?
    private let sceneView = SphereSceneView(frame: .zero)
    private let messageLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.black.cgColor

        sceneView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(sceneView)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 15, weight: .medium)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 3
        messageLabel.isHidden = true
        rootView.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: rootView.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: rootView.widthAnchor, multiplier: 0.72)
        ])

        view = rootView
    }

    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        false
    }

    func startContentEditing(with contentEditingInput: PHContentEditingInput, placeholderImage: NSImage) {
        input = contentEditingInput

        if let asset = contentEditingInput.audiovisualAsset {
            showVideo(asset)
            return
        }

        if let imageURL = contentEditingInput.fullSizeImageURL,
           let fullSizeImage = NSImage(contentsOf: imageURL) {
            showImage(fullSizeImage)
            return
        }

        showImage(placeholderImage)
    }

    private func showVideo(_ asset: AVAsset) {
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        player.actionAtItemEnd = .none
        self.player = player
        image = nil

        messageLabel.isHidden = true
        sceneView.setMedia(player: player, image: nil)
        sceneView.resetCamera(animated: false)
        player.play()
    }

    private func showImage(_ image: PlatformImage) {
        player?.pause()
        player = nil
        self.image = image

        messageLabel.isHidden = true
        sceneView.setMedia(player: nil, image: image)
        sceneView.resetCamera(animated: false)
    }

    func finishContentEditing(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
        player?.pause()
        image = nil
        completionHandler(nil)
    }

    var shouldShowCancelConfirmation: Bool {
        false
    }

    func cancelContentEditing() {
        player?.pause()
        player = nil
        image = nil
        input = nil
    }

    private func showMessage(_ message: String) {
        player?.pause()
        player = nil
        image = nil
        messageLabel.stringValue = message
        messageLabel.isHidden = false
    }
}
