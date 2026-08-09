import AVFoundation
import Foundation

@MainActor
final class ViewerStore: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var displayName = ""
    @Published private(set) var player: AVPlayer?
    @Published private(set) var image: PlatformImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var isLooping = true
    @Published var volume: Double = 1.0 {
        didSet {
            player?.volume = Float(volume)
        }
    }
    @Published var alertMessage: String?
    @Published private(set) var viewResetID = UUID()

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?

    var hasVideo: Bool {
        player != nil
    }

    var hasMedia: Bool {
        player != nil || image != nil
    }

    func openFirstSupported(_ urls: [URL]) {
        guard let url = urls.first(where: SupportedVideoTypes.isLikelyMedia) else {
            alertMessage = "No supported 360 video or image file was found."
            return
        }
        open(url)
    }

    func open(_ url: URL) {
        guard let mediaKind = SupportedVideoTypes.mediaKind(for: url) else {
            alertMessage = "\(url.lastPathComponent) is not a supported 360 video or image file."
            return
        }

        switch mediaKind {
        case .video:
            openVideo(url)
        case .image:
            openImage(url)
        }
    }

    private func openVideo(_ url: URL) {
        tearDownPlayer()
        image = nil

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .none
        newPlayer.volume = Float(volume)

        currentURL = url
        displayName = url.lastPathComponent
        player = newPlayer
        currentTime = 0
        duration = 0
        installObservers(for: newPlayer, item: item)
        requestViewReset()
        play()
    }

    private func openImage(_ url: URL) {
        guard let loadedImage = Self.loadImage(from: url) else {
            alertMessage = "\(url.lastPathComponent) could not be loaded as an image."
            return
        }

        tearDownPlayer()

        currentURL = url
        displayName = url.lastPathComponent
        image = loadedImage
        currentTime = 0
        duration = 0
        requestViewReset()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else {
            return
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        guard let player else {
            return
        }

        let boundedSeconds = max(0, min(seconds, duration > 0 ? duration : seconds))
        player.seek(
            to: CMTime(seconds: boundedSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = boundedSeconds
    }

    func requestViewReset() {
        viewResetID = UUID()
    }

    private func installObservers(for player: AVPlayer, item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.updatePlaybackTime(time)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }

        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "The video could not be played."

            Task { @MainActor in
                self?.alertMessage = message
                self?.pause()
            }
        }
    }

    private func updatePlaybackTime(_ time: CMTime) {
        currentTime = time.seconds.isFinite ? time.seconds : 0

        if let itemDuration = player?.currentItem?.duration.seconds, itemDuration.isFinite {
            duration = itemDuration
        }

        if player?.timeControlStatus != .playing, isPlaying {
            isPlaying = false
        }
    }

    private func handlePlaybackEnded() {
        guard isLooping else {
            isPlaying = false
            return
        }

        seek(to: 0)
        play()
    }

    private func tearDownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil

        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
        }
        failedObserver = nil

        player?.pause()
        player = nil
        isPlaying = false
    }

    private static func loadImage(from url: URL) -> PlatformImage? {
        #if os(macOS)
        PlatformImage(contentsOf: url)
        #elseif os(iOS)
        PlatformImage(contentsOfFile: url.path)
        #endif
    }
}

#if os(macOS)
extension ViewerStore {
    func presentOpenPanel() {
        guard let url = VideoOpenPanel.chooseMedia() else {
            return
        }
        open(url)
    }

    func registerOpenWithOption() {
        do {
            try OpenWithRegistrationService.registerCurrentAppBundle()
            alertMessage = "SphereView360 was registered as an Open With option. It was not made the default app for videos or images."
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
#endif
