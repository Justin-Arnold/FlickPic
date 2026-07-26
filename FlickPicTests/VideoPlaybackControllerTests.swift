@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import FlickPic

@MainActor
struct VideoPlaybackControllerTests {
    @Test
    func activationPrecedesPlaybackForItemsWithoutAudioTracks() async {
        let events = PlaybackEventRecorder()
        let audioSession = RecordingVideoAudioSessionClient(
            events: events
        )
        let engineFactory = RecordingVideoPlaybackEngineFactory(
            events: events
        )
        let controller = VideoPlaybackController(
            audioSession: audioSession,
            engineFactory: engineFactory
        )
        let library = FakePhotoLibraryClient()

        controller.play(identifier: "silent-video", photoLibrary: library)
        await waitUntil { controller.player != nil }

        #expect(events.values == ["activate", "play"])
        #expect(library.playerItemRequests == ["silent-video"])
        #expect(!controller.isLoading)
        #expect(controller.errorMessage == nil)
    }

    @Test
    func activationFailureKeepsPosterAndCanRetry() async {
        let audioSession = RecordingVideoAudioSessionClient()
        audioSession.activationError = TestVideoPlaybackError.activation
        let engineFactory = RecordingVideoPlaybackEngineFactory()
        let controller = VideoPlaybackController(
            audioSession: audioSession,
            engineFactory: engineFactory
        )
        let library = FakePhotoLibraryClient()

        controller.play(identifier: "video", photoLibrary: library)
        await waitUntil { controller.errorMessage != nil }

        #expect(controller.player == nil)
        #expect(
            controller.errorMessage
                == "FlickPic couldn’t start video sound. Try again."
        )
        #expect(engineFactory.engines.count == 1)
        #expect(engineFactory.engines[0].playCount == 0)
        #expect(audioSession.invocations == [.activate])

        audioSession.activationError = nil
        controller.play(identifier: "video", photoLibrary: library)
        await waitUntil { controller.player != nil }

        #expect(audioSession.invocations == [.activate, .activate])
        #expect(engineFactory.engines.count == 2)
        #expect(engineFactory.engines[1].playCount == 1)
    }

    @Test
    func nativePauseBufferAndResumeManageAudioIdempotently() async {
        let audioSession = RecordingVideoAudioSessionClient()
        let engineFactory = RecordingVideoPlaybackEngineFactory()
        let controller = VideoPlaybackController(
            audioSession: audioSession,
            engineFactory: engineFactory
        )
        let library = FakePhotoLibraryClient()

        controller.play(identifier: "video", photoLibrary: library)
        await waitUntil { controller.player != nil }
        let engine = engineFactory.engines[0]

        engine.send(.waiting)
        #expect(audioSession.invocations == [.activate])

        engine.send(.paused)
        engine.send(.paused)
        #expect(
            audioSession.invocations == [.activate, .deactivate]
        )

        engine.send(.playing)
        engine.send(.playing)
        #expect(
            audioSession.invocations
                == [.activate, .deactivate, .activate]
        )
    }

    @Test
    func completionAndFailureReleaseAudio() async {
        let audioSession = RecordingVideoAudioSessionClient()
        let engineFactory = RecordingVideoPlaybackEngineFactory()
        let controller = VideoPlaybackController(
            audioSession: audioSession,
            engineFactory: engineFactory
        )
        let library = FakePhotoLibraryClient()

        controller.play(identifier: "video", photoLibrary: library)
        await waitUntil { controller.player != nil }
        let engine = engineFactory.engines[0]

        engine.send(.ended)
        #expect(controller.player != nil)
        #expect(controller.errorMessage == nil)
        #expect(engine.pauseCount == 1)
        #expect(
            audioSession.invocations == [.activate, .deactivate]
        )

        engine.send(.playing)
        #expect(audioSession.invocations.last == .activate)

        engine.send(
            .failed(
                NSError(
                    domain: "VideoPlaybackTests",
                    code: 9,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Playback failed."
                    ]
                )
            )
        )
        #expect(controller.player == nil)
        #expect(controller.errorMessage == "Playback failed.")
        #expect(engine.invalidated)
        #expect(engine.pauseCount == 2)
        #expect(audioSession.invocations.last == .deactivate)
    }

    @Test
    func interruptionRouteLossAndInactivityNeverAutoResume() async {
        let audioSession = RecordingVideoAudioSessionClient()
        let engineFactory = RecordingVideoPlaybackEngineFactory()
        let controller = VideoPlaybackController(
            audioSession: audioSession,
            engineFactory: engineFactory
        )
        let library = FakePhotoLibraryClient()

        controller.play(identifier: "video", photoLibrary: library)
        await waitUntil { controller.player != nil }
        let engine = engineFactory.engines[0]

        engine.send(.interruptionBegan)
        #expect(engine.pauseCount == 1)
        #expect(audioSession.invocations.last == .deactivate)

        engine.send(.playing)
        engine.send(.outputRouteDisconnected)
        #expect(engine.pauseCount == 2)
        #expect(audioSession.invocations.last == .deactivate)

        engine.send(.playing)
        controller.pauseForExternalEvent()
        #expect(engine.pauseCount == 3)
        #expect(audioSession.invocations.last == .deactivate)
        #expect(controller.player != nil)
    }

    @Test
    func deactivationFailureDoesNotBlockLaterReactivation() async {
        let audioSession = RecordingVideoAudioSessionClient()
        let engineFactory = RecordingVideoPlaybackEngineFactory()
        let controller = VideoPlaybackController(
            audioSession: audioSession,
            engineFactory: engineFactory
        )
        let library = FakePhotoLibraryClient()

        controller.play(identifier: "video", photoLibrary: library)
        await waitUntil { controller.player != nil }
        let engine = engineFactory.engines[0]

        audioSession.deactivationError =
            TestVideoPlaybackError.deactivation
        engine.send(.paused)
        audioSession.deactivationError = nil
        engine.send(.playing)

        #expect(
            audioSession.invocations
                == [.activate, .deactivate, .activate]
        )
        #expect(controller.errorMessage == nil)
    }

    @Test
    func stoppedStaleLoadCannotPublishOrActivate() async {
        let gate = PlayerItemGate()
        let audioSession = RecordingVideoAudioSessionClient()
        let engineFactory = RecordingVideoPlaybackEngineFactory()
        let controller = VideoPlaybackController(
            audioSession: audioSession,
            engineFactory: engineFactory
        )
        let library = FakePhotoLibraryClient()
        library.playerItemHandler = { _ in
            await gate.wait()
        }

        controller.play(identifier: "video", photoLibrary: library)
        await waitUntil { gate.isWaiting }
        #expect(controller.isLoading)

        controller.stopAndReset()
        controller.stopAndReset()
        gate.resume()
        await Task.yield()
        await Task.yield()

        #expect(controller.player == nil)
        #expect(!controller.isLoading)
        #expect(audioSession.invocations.isEmpty)
        #expect(engineFactory.engines.isEmpty)
    }

    @Test
    func itemLoadFailureDoesNotTouchAudioSession() async {
        let audioSession = RecordingVideoAudioSessionClient()
        let controller = VideoPlaybackController(
            audioSession: audioSession,
            engineFactory: RecordingVideoPlaybackEngineFactory()
        )
        let library = FakePhotoLibraryClient()
        library.playerItemError =
            PhotoLibraryError.iCloudDownloadRequired

        controller.play(identifier: "cloud-video", photoLibrary: library)
        await waitUntil { controller.errorMessage != nil }

        #expect(
            controller.errorMessage
                == "This item needs to download from iCloud. Check your connection and try again."
        )
        #expect(controller.player == nil)
        #expect(audioSession.invocations.isEmpty)
    }

    @Test
    func systemEngineMapsOnlyRelevantSystemNotifications() async {
        let notificationCenter = NotificationCenter()
        let item = AVPlayerItem(
            url: URL(fileURLWithPath: "/dev/null")
        )
        let engine = SystemVideoPlaybackEngine(
            item: item,
            notificationCenter: notificationCenter
        )
        let recorder = VideoPlaybackEventRecorder()
        engine.onEvent = { recorder.record($0) }

        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey:
                    AVAudioSession.InterruptionType.ended.rawValue
            ]
        )
        notificationCenter.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    AVAudioSession.RouteChangeReason
                        .newDeviceAvailable.rawValue
            ]
        )
        await Task.yield()
        #expect(recorder.values.isEmpty)

        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey:
                    AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        notificationCenter.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    AVAudioSession.RouteChangeReason
                        .oldDeviceUnavailable.rawValue
            ]
        )
        notificationCenter.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )
        await waitUntil { recorder.values.count == 3 }

        #expect(
            recorder.values
                == [
                    .interruptionBegan,
                    .outputRouteDisconnected,
                    .ended
                ]
        )
        engine.invalidate()
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("Condition did not become true.")
    }
}

private enum TestVideoPlaybackError: Error {
    case activation
    case deactivation
}

@MainActor
private final class PlaybackEventRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }
}

@MainActor
private final class RecordingVideoAudioSessionClient:
    VideoAudioSessionClient {
    enum Invocation: Equatable {
        case activate
        case deactivate
    }

    private(set) var invocations: [Invocation] = []
    var activationError: Error?
    var deactivationError: Error?
    private let events: PlaybackEventRecorder?

    init(events: PlaybackEventRecorder? = nil) {
        self.events = events
    }

    func activate() throws {
        invocations.append(.activate)
        events?.record("activate")
        if let activationError {
            throw activationError
        }
    }

    func deactivate() throws {
        invocations.append(.deactivate)
        events?.record("deactivate")
        if let deactivationError {
            throw deactivationError
        }
    }
}

@MainActor
private final class RecordingVideoPlaybackEngineFactory:
    VideoPlaybackEngineFactory {
    private(set) var engines: [RecordingVideoPlaybackEngine] = []
    private let events: PlaybackEventRecorder?

    init(events: PlaybackEventRecorder? = nil) {
        self.events = events
    }

    func makeEngine(item: AVPlayerItem) -> any VideoPlaybackEngine {
        let engine = RecordingVideoPlaybackEngine(events: events)
        engines.append(engine)
        return engine
    }
}

@MainActor
private final class RecordingVideoPlaybackEngine:
    VideoPlaybackEngine {
    let player = AVPlayer()
    var onEvent: ((VideoPlaybackEvent) -> Void)?
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var invalidated = false
    private let events: PlaybackEventRecorder?

    init(events: PlaybackEventRecorder? = nil) {
        self.events = events
    }

    func play() {
        playCount += 1
        events?.record("play")
    }

    func pause() {
        pauseCount += 1
        events?.record("pause")
    }

    func invalidate() {
        invalidated = true
        onEvent = nil
    }

    func send(_ event: VideoPlaybackEvent) {
        onEvent?(event)
    }
}

@MainActor
private final class PlayerItemGate {
    private var continuation:
        CheckedContinuation<AVPlayerItem, Never>?
    private(set) var isWaiting = false

    func wait() async -> AVPlayerItem {
        isWaiting = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        isWaiting = false
        continuation?.resume(
            returning: AVPlayerItem(
                url: URL(fileURLWithPath: "/dev/null")
            )
        )
        continuation = nil
    }
}

@MainActor
private final class VideoPlaybackEventRecorder {
    private(set) var values: [RecordedVideoPlaybackEvent] = []

    func record(_ event: VideoPlaybackEvent) {
        switch event {
        case .interruptionBegan:
            values.append(.interruptionBegan)
        case .outputRouteDisconnected:
            values.append(.outputRouteDisconnected)
        case .ended:
            values.append(.ended)
        default:
            break
        }
    }
}

private enum RecordedVideoPlaybackEvent: Equatable {
    case interruptionBegan
    case outputRouteDisconnected
    case ended
}
