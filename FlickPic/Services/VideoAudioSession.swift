@preconcurrency import AVFoundation

@MainActor
protocol VideoAudioSessionClient: AnyObject {
    func activate() throws
    func deactivate() throws
}

@MainActor
final class SystemVideoAudioSessionClient: VideoAudioSessionClient {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func activate() throws {
        try session.setCategory(
            .playback,
            mode: .moviePlayback,
            options: []
        )
        try session.setActive(true)
    }

    func deactivate() throws {
        try session.setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
