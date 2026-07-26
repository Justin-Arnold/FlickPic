import SwiftUI

struct ReviewSessionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var model: ReviewSessionModel
    let photoLibrary: PhotoLibraryService
    let onEndSession: () -> Void

    @State private var cardOffset: CGSize = .zero
    @State private var showingRescueActions = false
    @State private var rescueRoute: RescueRoute?
    @State private var decisionAssetID: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                topBar

                Group {
                    if model.isLoading {
                        ProgressView("Loading your library…")
                            .tint(.white)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage = model.errorMessage,
                              model.assets.isEmpty {
                        ContentUnavailableView {
                            Label("Couldn’t Load Photos", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Try Again") {
                                Task { await model.retry() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .foregroundStyle(.white)
                    } else if let asset = model.currentAsset {
                        reviewCard(asset)
                    } else {
                        ContentUnavailableView {
                            Label("Nothing to Review", systemImage: "checkmark.circle")
                        } description: {
                            Text("There are no matching items left in this queue.")
                        } actions: {
                            Button("End Session", action: onEndSession)
                                .buttonStyle(.borderedProminent)
                        }
                        .foregroundStyle(.white)
                    }
                }

                if model.currentAsset != nil {
                    actionControls
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .task {
            await model.load()
        }
        .onDisappear {
            model.endSession()
        }
        .confirmationDialog(
            "Rescue this item",
            isPresented: $showingRescueActions,
            titleVisibility: .visible
        ) {
            if model.currentAsset?.mediaKind == .photo {
                Button("Extract Text & Queue Delete") {
                    if let asset = model.currentAsset {
                        rescueRoute = .text(asset)
                    }
                }
            }

            if RescueCapabilities.canShareCopy(model.currentAsset) {
                Button("Share a Copy & Queue Delete") {
                    if let asset = model.currentAsset {
                        rescueRoute = .share(asset)
                    }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            if model.currentAsset?.isLivePhoto == true {
                Text(
                    "FlickPic can extract text from this Live Photo, but cannot yet preserve its complete motion and sound when sharing a copy. The item stays in Photos until you confirm the deletion queue."
                )
            } else {
                Text(
                    "The item stays in Photos until you later review and confirm the deletion queue."
                )
            }
        }
        .sheet(item: $rescueRoute) { route in
            switch route {
            case let .share(asset):
                ShareCopyRescueView(
                    asset: asset,
                    photoLibrary: photoLibrary,
                    onCompleted: {
                        rescueRoute = nil
                        model.queueCurrentForDeletion(
                            source: .sharedCopy,
                            expectedIdentifier: asset.id
                        )
                    },
                    onCancel: {
                        rescueRoute = nil
                    }
                )
            case let .text(asset):
                TextRescueView(
                    asset: asset,
                    photoLibrary: photoLibrary,
                    textExtractor: TextExtractionService(),
                    onCompleted: {
                        rescueRoute = nil
                        model.queueCurrentForDeletion(
                            source: .extractedText,
                            expectedIdentifier: asset.id
                        )
                    },
                    onCancel: {
                        rescueRoute = nil
                    }
                )
            }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil && !model.assets.isEmpty },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                onEndSession()
            } label: {
                Label("End Session", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("End Session")

            Spacer()

            if let position = model.positionText {
                Text(position)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "trash")
                Text("\(model.pendingCount)")
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(model.pendingCount == 0 ? .white.opacity(0.65) : .red)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("\(model.pendingCount) pending deletions")
        }
        .foregroundStyle(.white)
    }

    private func reviewCard(_ asset: MediaAssetDescriptor) -> some View {
        MediaCardView(
            asset: asset,
            photoLibrary: photoLibrary,
            onLater: moveCurrentToLater
        )
        .id(asset.id)
        .overlay {
            decisionOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .offset(cardOffset)
        .rotationEffect(.degrees(Double(cardOffset.width / 28)))
        .gesture(cardGesture)
        .accessibilityAction(named: "Keep") {
            performDecision(.keep)
        }
        .accessibilityAction(named: "Queue Delete") {
            performDecision(.delete)
        }
        .accessibilityAction(named: "Rescue") {
            guard decisionAssetID == nil else { return }
            showingRescueActions = true
        }
        .accessibilityAction(named: "Later") {
            moveCurrentToLater()
        }
    }

    @ViewBuilder
    private var decisionOverlay: some View {
        let horizontalStrength = min(abs(cardOffset.width) / 160, 1)
        let upwardStrength = min(max(-cardOffset.height, 0) / 160, 1)

        if cardOffset.width < -20 {
            DecisionOverlay(
                title: "Queue Delete",
                systemImage: "trash",
                color: .red,
                opacity: horizontalStrength
            )
        } else if cardOffset.width > 20 {
            DecisionOverlay(
                title: "Keep",
                systemImage: "checkmark",
                color: .green,
                opacity: horizontalStrength
            )
        } else if cardOffset.height < -20 {
            DecisionOverlay(
                title: "Rescue",
                systemImage: "arrow.up.doc",
                color: .indigo,
                opacity: upwardStrength
            )
        }
    }

    private var cardGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard decisionAssetID == nil else { return }
                let translation = value.translation
                if abs(translation.width) > abs(translation.height) {
                    cardOffset = CGSize(width: translation.width, height: 0)
                } else if translation.height < 0 {
                    cardOffset = CGSize(width: 0, height: translation.height)
                }
            }
            .onEnded { _ in
                guard decisionAssetID == nil else { return }
                if cardOffset.width <= -110 {
                    performDecision(.delete)
                } else if cardOffset.width >= 110 {
                    performDecision(.keep)
                } else if cardOffset.height <= -110 {
                    resetCard()
                    showingRescueActions = true
                } else {
                    resetCard()
                }
            }
    }

    private var actionControls: some View {
        HStack(spacing: 18) {
            ReviewActionButton(
                title: "Undo",
                systemImage: "arrow.uturn.backward",
                color: .white,
                isEnabled: model.canUndo && decisionAssetID == nil
            ) {
                resetCard()
                model.undoLastDecision()
            }

            ReviewActionButton(
                title: "Delete",
                systemImage: "trash",
                color: .red,
                isEnabled: decisionAssetID == nil
            ) {
                performDecision(.delete)
            }

            ReviewActionButton(
                title: "Rescue",
                systemImage: "arrow.up.doc",
                color: .indigo,
                isEnabled: decisionAssetID == nil
            ) {
                resetCard()
                showingRescueActions = true
            }

            ReviewActionButton(
                title: "Keep",
                systemImage: "checkmark",
                color: .green,
                isEnabled: decisionAssetID == nil
            ) {
                performDecision(.keep)
            }
        }
        .padding(.vertical, 4)
    }

    private func performDecision(_ decision: CardDecision) {
        guard decisionAssetID == nil,
              let identifier = model.currentAsset?.id else {
            return
        }
        decisionAssetID = identifier

        let target: CGSize = switch decision {
        case .delete: CGSize(width: -600, height: 0)
        case .keep: CGSize(width: 600, height: 0)
        }

        if reduceMotion {
            cardOffset = .zero
            apply(decision, expectedIdentifier: identifier)
            decisionAssetID = nil
        } else {
            withAnimation(.easeIn(duration: 0.18)) {
                cardOffset = target
            } completion: {
                cardOffset = .zero
                guard decisionAssetID == identifier else { return }
                apply(decision, expectedIdentifier: identifier)
                decisionAssetID = nil
            }
        }
    }

    private func apply(
        _ decision: CardDecision,
        expectedIdentifier: String
    ) {
        switch decision {
        case .delete:
            model.queueCurrentForDeletion(
                expectedIdentifier: expectedIdentifier
            )
        case .keep:
            model.keepCurrent(expectedIdentifier: expectedIdentifier)
        }
    }

    private func moveCurrentToLater() {
        guard decisionAssetID == nil else { return }
        model.moveCurrentToLater()
    }

    private func resetCard() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
            cardOffset = .zero
        }
    }
}

private enum CardDecision {
    case delete
    case keep
}

enum RescueCapabilities {
    static func canShareCopy(_ asset: MediaAssetDescriptor?) -> Bool {
        asset?.isLivePhoto == false
    }
}

private enum RescueRoute: Identifiable {
    case share(MediaAssetDescriptor)
    case text(MediaAssetDescriptor)

    var id: String {
        switch self {
        case let .share(asset): "share-\(asset.id)"
        case let .text(asset): "text-\(asset.id)"
        }
    }
}

private struct DecisionOverlay: View {
    let title: String
    let systemImage: String
    let color: Color
    let opacity: Double

    var body: some View {
        ZStack {
            color.opacity(0.2 * opacity)
            Label(title, systemImage: systemImage)
                .font(.title2.bold())
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
                .opacity(opacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ReviewActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 50, height: 42)
                    .background(color.opacity(isEnabled ? 0.2 : 0.08), in: Circle())
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(isEnabled ? color : .gray)
        }
        .disabled(!isEnabled)
        .frame(minWidth: 52, minHeight: 58)
    }
}
