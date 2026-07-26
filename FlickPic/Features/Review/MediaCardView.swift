import AVKit
import PhotosUI
import SwiftUI

struct MediaCardView: View {
    let asset: MediaAssetDescriptor
    let photoLibrary: any PhotoLibraryClient
    let onLater: () -> Void

    @State private var image: UIImage?
    @State private var gifAnimation: GIFAnimation?
    @State private var livePhoto: PHLivePhoto?
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var isLoadingVideo = false
    @State private var errorMessage: String?
    @State private var retryToken = UUID()
    @State private var isPlayingLivePhoto = false
    @State private var showingInspector = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(white: 0.08)

                if let player {
                    VideoPlayer(player: player)
                        .onDisappear {
                            player.pause()
                        }
                } else if let image {
                    ZStack {
                        if let gifAnimation {
                            GIFPlaybackView(animation: gifAnimation)
                                .frame(
                                    width: proxy.size.width,
                                    height: proxy.size.height
                                )
                                .accessibilityHidden(true)
                        } else {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        if let livePhoto, asset.isLivePhoto {
                            LivePhotoRepresentable(
                                livePhoto: livePhoto,
                                isPlaying: isPlayingLivePhoto
                            )
                            .frame(
                                width: proxy.size.width,
                                height: proxy.size.height
                            )
                            .clipped()
                            .opacity(isPlayingLivePhoto ? 1 : 0)
                            .allowsHitTesting(false)
                        }

                        if asset.mediaKind == .video {
                            Button {
                                playVideo()
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 68, height: 68)
                                    .background(.black.opacity(0.55), in: Circle())
                            }
                            .accessibilityLabel("Play video")
                        }
                    }
                    .contentShape(Rectangle())
                    .modifier(
                        LivePhotoPreviewGesture(
                            isEnabled: asset.isLivePhoto && livePhoto != nil,
                            isPlaying: $isPlayingLivePhoto
                        )
                    )
                    .modifier(
                        PhotoInspectionGesture(
                            isEnabled: asset.mediaKind == .photo,
                            onInspect: inspectPhoto
                        )
                    )
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                }

                if isLoadingVideo {
                    ProgressView("Loading video…")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(0.65), in: Capsule())
                }

                if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "icloud.slash")
                            .font(.largeTitle)
                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        HStack {
                            Button("Retry") {
                                retryToken = UUID()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Later", action: onLater)
                                .buttonStyle(.bordered)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                }
            }
            .overlay(alignment: .topLeading) {
                metadataBadges
                    .padding(14)
            }
            .overlay(alignment: .bottomLeading) {
                if let creationDate = asset.creationDate {
                    Text(creationDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.58), in: Capsule())
                        .padding(14)
                }
            }
            .task(id: MediaLoadRequest(assetIdentifier: asset.id, retryToken: retryToken)) {
                await loadMedia(targetSize: proxy.size)
            }
        }
        .fullScreenCover(isPresented: $showingInspector) {
            ImageInspectorView(
                asset: asset,
                initialImage: image,
                initialGIFAnimation: gifAnimation,
                photoLibrary: photoLibrary
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier(
            asset.mediaKind == .photo ? "inspectable-media" : "media-card"
        )
        .accessibilityAction(named: "Inspect Details") {
            inspectPhoto()
        }
    }

    private var metadataBadges: some View {
        HStack(spacing: 7) {
            if asset.isScreenshot {
                MediaBadge(title: "Screenshot", systemImage: "rectangle.inset.filled")
            }
            if asset.isLivePhoto {
                MediaBadge(title: "Live", systemImage: "livephoto")
            }
            if gifAnimation != nil {
                MediaBadge(title: "GIF", systemImage: "play.rectangle")
                    .accessibilityIdentifier("animated-gif-badge")
            }
            if asset.mediaKind == .video {
                MediaBadge(
                    title: asset.duration.formattedDuration,
                    systemImage: "video.fill"
                )
            }
            if asset.isFavorite {
                MediaBadge(title: "Favorite", systemImage: "heart.fill")
            }
        }
    }

    private var accessibilityDescription: String {
        var parts = [asset.mediaKind.title]
        if asset.isScreenshot { parts.append("screenshot") }
        if asset.isLivePhoto { parts.append("Live Photo") }
        if gifAnimation != nil { parts.append("animated GIF") }
        if asset.isFavorite { parts.append("favorite") }
        if let date = asset.creationDate {
            parts.append(date.formatted(date: .long, time: .shortened))
        }
        return parts.joined(separator: ", ")
    }

    private func loadMedia(targetSize: CGSize) async {
        isLoading = true
        errorMessage = nil
        player?.pause()
        player = nil
        image = nil
        gifAnimation = nil
        livePhoto = nil
        isPlayingLivePhoto = false

        let scale = UIScreen.main.scale
        let requestedSize = CGSize(
            width: max(targetSize.width * scale, 800),
            height: max(targetSize.height * scale, 1_000)
        )

        do {
            let loadedImage = try await photoLibrary.thumbnail(
                identifier: asset.id,
                targetSize: requestedSize
            )
            try Task.checkCancellation()
            image = loadedImage

            if asset.isPlayableGIF,
               let data = try await photoLibrary.gifData(
                identifier: asset.id
               ) {
                let animation = try await GIFAnimationDecoder.decode(
                    data: data,
                    maximumPixelDimension: max(
                        requestedSize.width,
                        requestedSize.height
                    )
                )
                try Task.checkCancellation()
                if animation.frameCount > 1 {
                    gifAnimation = animation
                    image = animation.posterImage
                }
            } else if asset.isLivePhoto {
                let loadedLivePhoto = try? await photoLibrary.livePhoto(
                    identifier: asset.id,
                    targetSize: requestedSize
                )
                guard !Task.isCancelled else { return }
                livePhoto = loadedLivePhoto
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func playVideo() {
        guard player == nil, !isLoadingVideo else { return }
        isLoadingVideo = true
        Task {
            do {
                let item = try await photoLibrary.playerItem(identifier: asset.id)
                let newPlayer = AVPlayer(playerItem: item)
                player = newPlayer
                newPlayer.play()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingVideo = false
        }
    }

    private func inspectPhoto() {
        guard image != nil, asset.mediaKind == .photo else { return }
        showingInspector = true
    }
}

private struct MediaLoadRequest: Equatable {
    let assetIdentifier: String
    let retryToken: UUID
}

private struct LivePhotoPreviewGesture: ViewModifier {
    let isEnabled: Bool
    @Binding var isPlaying: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.onLongPressGesture(
                minimumDuration: 0.1,
                pressing: { pressing in
                    isPlaying = pressing
                },
                perform: {}
            )
        } else {
            content
        }
    }
}

private struct PhotoInspectionGesture: ViewModifier {
    let isEnabled: Bool
    let onInspect: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.onTapGesture(count: 2, perform: onInspect)
        } else {
            content
        }
    }
}

private struct MediaBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.black.opacity(0.58), in: Capsule())
    }
}

private struct LivePhotoRepresentable: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let isPlaying: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.livePhoto = livePhoto
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        view.livePhoto = livePhoto
        guard context.coordinator.wasPlaying != isPlaying else { return }
        context.coordinator.wasPlaying = isPlaying

        if isPlaying {
            view.startPlayback(with: .full)
        } else {
            view.stopPlayback()
        }
    }

    final class Coordinator {
        var wasPlaying = false
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        let totalSeconds = max(Int(self.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
