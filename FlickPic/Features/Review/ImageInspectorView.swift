import SwiftUI
import UIKit

struct ImageInspectorView: View {
    @Environment(\.dismiss) private var dismiss

    let asset: MediaAssetDescriptor
    let initialImage: UIImage?
    let photoLibrary: any PhotoLibraryClient

    @State private var detailedImage: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var retryToken = UUID()
    @State private var zoomController = ImageZoomController()

    private var displayedImage: UIImage? {
        detailedImage ?? initialImage
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let displayedImage {
                ZoomableImageView(
                    image: displayedImage,
                    controller: zoomController
                )
                .ignoresSafeArea()
                .accessibilityLabel("Zoomable photo detail")
            }

            if displayedImage == nil, isLoading {
                ProgressView("Loading detail…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            if displayedImage == nil, let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Detail", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        retryToken = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .top) {
            inspectorToolbar
        }
        .safeAreaInset(edge: .bottom) {
            zoomControls
        }
        .task(id: InspectorLoadRequest(
            assetIdentifier: asset.id,
            retryToken: retryToken
        )) {
            await loadDetail()
        }
        .accessibilityIdentifier("image-inspector")
    }

    private var inspectorToolbar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label("Done", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.64), in: Circle())
            }
            .accessibilityLabel("Close detail")

            Spacer()

            if isLoading, displayedImage != nil {
                ProgressView()
                    .tint(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.64), in: Circle())
                    .accessibilityLabel("Loading higher resolution")
            }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var zoomControls: some View {
        HStack(spacing: 12) {
            Button {
                zoomController.zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Zoom out")

            Button {
                zoomController.reset()
            } label: {
                Text("Fit")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Fit whole image")

            Button {
                zoomController.zoomIn()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Zoom in")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .background(.black.opacity(0.64), in: Capsule())
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityHint("You can also pinch, pan, or double-tap the image.")
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil

        do {
            let image = try await photoLibrary.inspectionImage(
                identifier: asset.id,
                targetSize: InspectionImageSizing.targetSize(for: asset)
            )
            try Task.checkCancellation()
            detailedImage = image
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

enum InspectionImageSizing {
    static let maximumPixelCount = 16_000_000.0
    static let maximumDimension = 20_000.0

    static func targetSize(
        for asset: MediaAssetDescriptor,
        maximumPixelCount: Double = maximumPixelCount,
        maximumDimension: Double = maximumDimension
    ) -> CGSize {
        let width = Double(max(asset.pixelWidth, 1))
        let height = Double(max(asset.pixelHeight, 1))
        let pixelScale = sqrt(maximumPixelCount / (width * height))
        let dimensionScale = maximumDimension / max(width, height)
        let scale = min(1, pixelScale, dimensionScale)

        return CGSize(
            width: max(1, floor(width * scale)),
            height: max(1, floor(height * scale))
        )
    }

    static func displaySize(for image: UIImage) -> CGSize {
        image.size
    }
}

private struct InspectorLoadRequest: Equatable {
    let assetIdentifier: String
    let retryToken: UUID
}

@MainActor
private final class ImageZoomController {
    weak var scrollView: ZoomingImageScrollView?

    func zoomIn() {
        scrollView?.zoomIn()
    }

    func zoomOut() {
        scrollView?.zoomOut()
    }

    func reset() {
        scrollView?.resetZoom()
    }
}

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let controller: ImageZoomController

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let view = ZoomingImageScrollView()
        view.setImage(image)
        controller.scrollView = view
        return view
    }

    func updateUIView(_ view: ZoomingImageScrollView, context: Context) {
        if view.image !== image {
            view.setImage(image)
        }
        controller.scrollView = view
    }

    static func dismantleUIView(
        _ view: ZoomingImageScrollView,
        coordinator: Void
    ) {
        view.image = nil
    }
}

@MainActor
private final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var lastBoundsSize: CGSize = .zero
    fileprivate var image: UIImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .black
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = true
        bouncesZoom = true
        decelerationRate = .fast

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastBoundsSize else {
            centerImage()
            return
        }
        lastBoundsSize = bounds.size
        configureZoomScales(reset: true)
    }

    func setImage(_ image: UIImage) {
        self.image = image
        lastBoundsSize = .zero
        setNeedsLayout()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    func zoomIn() {
        setZoomScale(min(zoomScale * 2, maximumZoomScale), animated: true)
    }

    func zoomOut() {
        setZoomScale(max(zoomScale / 2, minimumZoomScale), animated: true)
    }

    func resetZoom() {
        setZoomScale(minimumZoomScale, animated: true)
    }

    @objc
    private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.05 {
            resetZoom()
            return
        }

        let targetScale = min(
            max(scaleToFillWidth, minimumZoomScale * 2.5),
            maximumZoomScale
        )
        let location = recognizer.location(in: imageView)
        let width = bounds.width / targetScale
        let height = bounds.height / targetScale
        zoom(
            to: CGRect(
                x: location.x - width / 2,
                y: location.y - height / 2,
                width: width,
                height: height
            ),
            animated: true
        )
    }

    private var scaleToFillWidth: CGFloat {
        guard imageView.bounds.width > 0 else { return minimumZoomScale }
        return bounds.width / imageView.bounds.width
    }

    private func configureZoomScales(reset: Bool) {
        guard let image, bounds.width > 0, bounds.height > 0 else { return }

        let imageSize = InspectionImageSizing.displaySize(for: image)
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        if reset {
            // A higher-resolution image can replace the initial card image while
            // the image view is already transformed by UIScrollView. Restore an
            // identity transform before changing its frame or UIKit will derive
            // the new bounds from the old zoom scale.
            minimumZoomScale = 0.01
            maximumZoomScale = 100
            setZoomScale(1, animated: false)
        }

        imageView.frame = CGRect(origin: .zero, size: imageSize)
        contentSize = imageSize

        let fitScale = min(
            bounds.width / imageSize.width,
            bounds.height / imageSize.height
        )
        minimumZoomScale = fitScale
        maximumZoomScale = max(
            fitScale * 8,
            (bounds.width / imageSize.width) * 3
        )

        if reset {
            zoomScale = fitScale
        } else {
            zoomScale = min(max(zoomScale, fitScale), maximumZoomScale)
        }
        centerImage()
    }

    private func centerImage() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }
}
