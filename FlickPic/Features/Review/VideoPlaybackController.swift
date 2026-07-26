@preconcurrency import AVFoundation
import Combine
import Foundation
import Observation
import OSLog

enum VideoPlaybackEvent {
    case playing
    case waiting
    case paused
    case ended
    case failed(Error)
    case interruptionBegan
    case outputRouteDisconnected
}

@MainActor
protocol VideoPlaybackEngine: AnyObject {
    var player: AVPlayer { get }
    var onEvent: ((VideoPlaybackEvent) -> Void)? { get set }

    func play()
    func pause()
    func invalidate()
}

@MainActor
protocol VideoPlaybackEngineFactory: AnyObject {
    func makeEngine(item: AVPlayerItem) -> any VideoPlaybackEngine
}

@MainActor
final class SystemVideoPlaybackEngineFactory:
    VideoPlaybackEngineFactory {
    func makeEngine(item: AVPlayerItem) -> any VideoPlaybackEngine {
        SystemVideoPlaybackEngine(item: item)
    }
}

@MainActor
final class SystemVideoPlaybackEngine: VideoPlaybackEngine {
    let player: AVPlayer
    var onEvent: ((VideoPlaybackEvent) -> Void)?

    private var cancellables: Set<AnyCancellable> = []

    init(
        item: AVPlayerItem,
        notificationCenter: NotificationCenter = .default
    ) {
        player = AVPlayer(playerItem: item)

        player.publisher(
            for: \.timeControlStatus,
            options: [.new]
        )
        .sink { [weak self] status in
            Task { @MainActor [weak self] in
                switch status {
                case .playing:
                    self?.onEvent?(.playing)
                case .waitingToPlayAtSpecifiedRate:
                    self?.onEvent?(.waiting)
                case .paused:
                    self?.onEvent?(.paused)
                @unknown default:
                    self?.onEvent?(.paused)
                }
            }
        }
        .store(in: &cancellables)

        item.publisher(for: \.status, options: [.new])
            .sink { [weak self, weak item] status in
                guard status == .failed else { return }
                Task { @MainActor [weak self, weak item] in
                    self?.onEvent?(
                        .failed(
                            item?.error
                                ?? PhotoLibraryError.imageUnavailable
                        )
                    )
                }
            }
            .store(in: &cancellables)

        notificationCenter.publisher(
            for: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onEvent?(.ended)
            }
        }
        .store(in: &cancellables)

        notificationCenter.publisher(
            for: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item
        )
        .sink { [weak self] notification in
            let error = notification.userInfo?[
                AVPlayerItemFailedToPlayToEndTimeErrorKey
            ] as? Error
            Task { @MainActor [weak self] in
                self?.onEvent?(
                    .failed(
                        error ?? PhotoLibraryError.imageUnavailable
                    )
                )
            }
        }
        .store(in: &cancellables)

        notificationCenter.publisher(
            for: AVAudioSession.interruptionNotification
        )
        .sink { [weak self] notification in
            let rawType = notification.userInfo?[
                AVAudioSessionInterruptionTypeKey
            ] as? UInt
            guard rawType == AVAudioSession
                .InterruptionType.began.rawValue else {
                return
            }
            Task { @MainActor [weak self] in
                self?.onEvent?(.interruptionBegan)
            }
        }
        .store(in: &cancellables)

        notificationCenter.publisher(
            for: AVAudioSession.routeChangeNotification
        )
        .sink { [weak self] notification in
            let rawReason = notification.userInfo?[
                AVAudioSessionRouteChangeReasonKey
            ] as? UInt
            guard rawReason == AVAudioSession
                .RouteChangeReason.oldDeviceUnavailable.rawValue else {
                return
            }
            Task { @MainActor [weak self] in
                self?.onEvent?(.outputRouteDisconnected)
            }
        }
        .store(in: &cancellables)
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func invalidate() {
        onEvent = nil
        cancellables.removeAll()
    }
}

enum VideoPlaybackError: LocalizedError {
    case audioUnavailable

    var errorDescription: String? {
        switch self {
        case .audioUnavailable:
            String(
                localized:
                    "FlickPic couldn’t start video sound. Try again."
            )
        }
    }
}

@Observable
@MainActor
final class VideoPlaybackController {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FlickPic",
        category: "VideoPlayback"
    )

    private(set) var player: AVPlayer?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored
    private let audioSession: any VideoAudioSessionClient
    @ObservationIgnored
    private let engineFactory: any VideoPlaybackEngineFactory
    @ObservationIgnored
    private var engine: (any VideoPlaybackEngine)?
    @ObservationIgnored
    private var loadTask: Task<Void, Never>?
    @ObservationIgnored
    private var activeRequestID: UUID?
    @ObservationIgnored
    private var isAudioSessionActive = false

    init(
        audioSession: any VideoAudioSessionClient =
            SystemVideoAudioSessionClient(),
        engineFactory: any VideoPlaybackEngineFactory =
            SystemVideoPlaybackEngineFactory()
    ) {
        self.audioSession = audioSession
        self.engineFactory = engineFactory
    }

    func play(
        identifier: String,
        photoLibrary: any PhotoLibraryClient
    ) {
        guard player == nil, !isLoading else { return }

        errorMessage = nil
        isLoading = true
        let requestID = UUID()
        activeRequestID = requestID

        loadTask = Task { @MainActor [weak self] in
            do {
                let item = try await photoLibrary.playerItem(
                    identifier: identifier
                )
                try Task.checkCancellation()
                guard let self,
                      self.activeRequestID == requestID else {
                    return
                }
                self.finishLoading(
                    item: item,
                    requestID: requestID
                )
            } catch is CancellationError {
                guard let self,
                      self.activeRequestID == requestID else {
                    return
                }
                self.finishCancelledLoad()
            } catch {
                guard let self,
                      self.activeRequestID == requestID else {
                    return
                }
                self.finishFailedLoad(error)
            }
        }
    }

    func handle(_ event: VideoPlaybackEvent) {
        switch event {
        case .playing, .waiting:
            guard engine != nil else { return }
            guard activateAudioIfNeeded() else {
                failForUnavailableAudio()
                return
            }
        case .paused:
            deactivateAudioIfNeeded()
        case .ended:
            engine?.pause()
            deactivateAudioIfNeeded()
        case let .failed(error):
            failPlayback(error)
        case .interruptionBegan, .outputRouteDisconnected:
            pauseForExternalEvent()
        }
    }

    func pauseForExternalEvent() {
        if isLoading {
            activeRequestID = nil
            loadTask?.cancel()
            loadTask = nil
            isLoading = false
        }
        engine?.pause()
        deactivateAudioIfNeeded()
    }

    func stopAndReset() {
        activeRequestID = nil
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        tearDownEngine()
        errorMessage = nil
    }

    private func finishLoading(
        item: AVPlayerItem,
        requestID: UUID
    ) {
        guard activeRequestID == requestID else { return }

        let newEngine = engineFactory.makeEngine(item: item)
        newEngine.onEvent = { [weak self, weak newEngine] event in
            guard let self,
                  let newEngine,
                  self.engine === newEngine else {
                return
            }
            self.handle(event)
        }

        guard activateAudioIfNeeded() else {
            newEngine.invalidate()
            finishAudioFailure()
            return
        }

        engine = newEngine
        player = newEngine.player
        activeRequestID = nil
        loadTask = nil
        isLoading = false
        newEngine.play()
    }

    private func finishCancelledLoad() {
        activeRequestID = nil
        loadTask = nil
        isLoading = false
    }

    private func finishFailedLoad(_ error: Error) {
        activeRequestID = nil
        loadTask = nil
        isLoading = false
        errorMessage = error.localizedDescription
    }

    private func activateAudioIfNeeded() -> Bool {
        guard !isAudioSessionActive else { return true }

        do {
            try audioSession.activate()
            isAudioSessionActive = true
            return true
        } catch {
            Self.logger.error(
                "Video audio activation failed: domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)"
            )
            return false
        }
    }

    private func deactivateAudioIfNeeded() {
        guard isAudioSessionActive else { return }
        isAudioSessionActive = false

        do {
            try audioSession.deactivate()
        } catch {
            Self.logger.error(
                "Video audio deactivation failed: domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)"
            )
        }
    }

    private func failForUnavailableAudio() {
        tearDownEngine()
        finishAudioFailure()
    }

    private func finishAudioFailure() {
        activeRequestID = nil
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        errorMessage = VideoPlaybackError.audioUnavailable
            .localizedDescription
    }

    private func failPlayback(_ error: Error) {
        tearDownEngine()
        errorMessage = error.localizedDescription
    }

    private func tearDownEngine() {
        let currentEngine = engine
        engine = nil
        player = nil
        currentEngine?.invalidate()
        currentEngine?.pause()
        deactivateAudioIfNeeded()
    }
}
