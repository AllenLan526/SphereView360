import AVFoundation
import Foundation

#if os(macOS)
import Cocoa

final class ShareViewController: NSViewController {
    private let sceneView = SphereSceneView(frame: .zero)
    private let messageLabel = NSTextField(labelWithString: "Loading media...")
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private var player: AVPlayer?

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
        rootView.addSubview(messageLabel)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.target = self
        doneButton.action = #selector(done)
        doneButton.bezelStyle = .rounded
        rootView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: rootView.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: rootView.widthAnchor, multiplier: 0.72),

            doneButton.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
            doneButton.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 14)
        ])

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 920, height: 580)
        loadSharedMedia()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        player?.pause()
    }

    @objc private func done() {
        player?.pause()
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func loadSharedMedia() {
        SharedVideoLoader.loadFirstMedia(from: extensionContext) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleLoadedMedia(result)
            }
        }
    }

    private func handleLoadedMedia(_ result: Result<SharedVideoLoader.LoadedMedia, Error>) {
        switch result {
        case .success(.video(let url)):
            let player = AVPlayer(url: url)
            player.actionAtItemEnd = .none
            self.player = player
            messageLabel.isHidden = true
            sceneView.setMedia(player: player, image: nil)
            sceneView.resetCamera(animated: false)
            player.play()
        case .success(.image(let image)):
            player?.pause()
            player = nil
            messageLabel.isHidden = true
            sceneView.setMedia(player: nil, image: image)
            sceneView.resetCamera(animated: false)
        case .failure(let error):
            messageLabel.stringValue = error.localizedDescription
            messageLabel.isHidden = false
        }
    }
}
#elseif os(iOS)
import UIKit

final class ShareViewController: UIViewController {
    private let sceneView = SphereSceneView(frame: .zero)
    private let messageLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private var player: AVPlayer?

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .black

        sceneView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(sceneView)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = "Loading media..."
        messageLabel.textAlignment = .center
        messageLabel.font = .systemFont(ofSize: 15, weight: .medium)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 3
        rootView.addSubview(messageLabel)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)
        rootView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: rootView.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: rootView.widthAnchor, multiplier: 0.72),

            doneButton.trailingAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            doneButton.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSharedMedia()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        player?.pause()
    }

    @objc private func done() {
        player?.pause()
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func loadSharedMedia() {
        SharedVideoLoader.loadFirstMedia(from: extensionContext) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleLoadedMedia(result)
            }
        }
    }

    private func handleLoadedMedia(_ result: Result<SharedVideoLoader.LoadedMedia, Error>) {
        switch result {
        case .success(.video(let url)):
            let player = AVPlayer(url: url)
            player.actionAtItemEnd = .none
            self.player = player
            messageLabel.isHidden = true
            sceneView.setMedia(player: player, image: nil)
            sceneView.resetCamera(animated: false)
            player.play()
        case .success(.image(let image)):
            player?.pause()
            player = nil
            messageLabel.isHidden = true
            sceneView.setMedia(player: nil, image: image)
            sceneView.resetCamera(animated: false)
        case .failure(let error):
            messageLabel.text = error.localizedDescription
            messageLabel.isHidden = false
        }
    }
}
#endif
