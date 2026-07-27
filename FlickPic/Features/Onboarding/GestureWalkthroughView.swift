import SwiftUI
import UIKit

enum ReviewTutorialInteraction: Equatable {
    case drag(ReviewCardGestureAction)
    case doubleTap
}

enum ReviewTutorialStep: String, CaseIterable, Identifiable {
    case queueDelete = "queue-delete"
    case keep
    case rescue
    case inspect

    var id: String { rawValue }

    var interaction: ReviewTutorialInteraction {
        switch self {
        case .queueDelete: .drag(.queueDelete)
        case .keep: .drag(.keep)
        case .rescue: .drag(.rescue)
        case .inspect: .doubleTap
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .queueDelete: "Swipe left to queue"
        case .keep: "Swipe right to keep"
        case .rescue: "Swipe up to rescue"
        case .inspect: "Double-tap to inspect"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .queueDelete:
            "A left swipe only adds the item to your deletion queue. Nothing is deleted from Photos until you review and confirm that queue."
        case .keep:
            "A right swipe marks the item reviewed and leaves it safely in your Photos library."
        case .rescue:
            "A swipe up opens Rescue, where you can extract text or share a copy before queueing the original."
        case .inspect:
            "Double-tap a photo card to open it full screen for a closer look before deciding."
        }
    }

    var gesturePrompt: LocalizedStringKey {
        switch self {
        case .queueDelete: "Try swiping left"
        case .keep: "Try swiping right"
        case .rescue: "Try swiping up"
        case .inspect: "Try double-tapping"
        }
    }

    var systemImage: String {
        switch self {
        case .queueDelete: "trash"
        case .keep: "checkmark"
        case .rescue: "arrow.up.doc"
        case .inspect: "viewfinder"
        }
    }

    var tint: Color {
        switch self {
        case .queueDelete: .red
        case .keep: .green
        case .rescue: .indigo
        case .inspect: .cyan
        }
    }

    var cueTranslation: CGSize {
        switch self {
        case .queueDelete: CGSize(width: -18, height: 0)
        case .keep: CGSize(width: 18, height: 0)
        case .rescue: CGSize(width: 0, height: -14)
        case .inspect: .zero
        }
    }

    func constrainedOffset(for translation: CGSize) -> CGSize {
        switch interaction {
        case .drag(.queueDelete):
            CGSize(width: min(translation.width, 0), height: 0)
        case .drag(.keep):
            CGSize(width: max(translation.width, 0), height: 0)
        case .drag(.rescue):
            CGSize(width: 0, height: min(translation.height, 0))
        case .doubleTap:
            .zero
        }
    }
}

struct GestureWalkthroughView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let photoLibrary: any PhotoLibraryClient
    let onFinish: () -> Void

    @State private var stepIndex = 0
    @State private var cardOffset: CGSize = .zero
    @State private var isCompletingStep = false
    @State private var isInspecting = false

    private var steps: [ReviewTutorialStep] {
        ReviewTutorialStep.allCases
    }

    private var step: ReviewTutorialStep {
        steps[stepIndex]
    }

    private var isLastStep: Bool {
        stepIndex == steps.index(before: steps.endIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            LinearGradient(
                colors: [
                    step.tint.opacity(0.2),
                    .clear,
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.25),
                value: step
            )

            GeometryReader { geometry in
                let usesAccessibilityLayout =
                    dynamicTypeSize.isAccessibilitySize
                let cardHeight = min(
                    max(
                        geometry.size.height
                            * (usesAccessibilityLayout ? 0.28 : 0.42),
                        usesAccessibilityLayout ? 140 : 220
                    ),
                    usesAccessibilityLayout ? 240 : 390
                )

                VStack(spacing: 0) {
                    coachMark
                        .id(step.id)

                    tutorialCard
                        .frame(maxWidth: .infinity)
                        .frame(height: cardHeight)
                        .padding(.top, usesAccessibilityLayout ? 8 : 14)

                    progress
                        .padding(.top, usesAccessibilityLayout ? 8 : 14)

                    if !usesAccessibilityLayout {
                        TutorialGestureCue(step: step)
                            .id(step.id)
                            .padding(.top, 12)
                    }

                    Spacer(minLength: usesAccessibilityLayout ? 4 : 8)

                    nextButton
                        .padding(.top, usesAccessibilityLayout ? 4 : 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, usesAccessibilityLayout ? 6 : 10)
                .padding(.bottom, usesAccessibilityLayout ? 8 : 12)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
        .foregroundStyle(.white)
        .fullScreenCover(isPresented: $isInspecting) {
            ImageInspectorView(
                asset: TutorialSampleImage.asset,
                initialImage: TutorialSampleImage.image,
                initialGIFAnimation: nil,
                photoLibrary: photoLibrary,
                loadsDetailedImage: false
            )
            .dynamicTypeSize(dynamicTypeSize)
        }
    }

    private var progress: some View {
        HStack(spacing: 7) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, item in
                Capsule()
                    .fill(
                        index == stepIndex
                            ? item.tint
                            : Color.white.opacity(0.22)
                    )
                    .frame(
                        width: index == stepIndex ? 30 : 9,
                        height: 7
                    )
            }

            Spacer()

            Text("Step \(stepIndex + 1) of \(steps.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.65))
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
            value: stepIndex
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stepIndex + 1) of \(steps.count)")
        .accessibilityIdentifier("onboarding-progress")
    }

    private var coachMark: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: step.systemImage)
                .font(.title2.weight(.bold))
                .foregroundStyle(step.tint)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.title3.bold())
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding-step-\(step.id)")
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var tutorialCard: some View {
        TutorialSampleCard(
            image: TutorialSampleImage.image
        )
        .overlay {
            tutorialDecisionOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle())
        .offset(cardOffset)
        .rotationEffect(.degrees(Double(cardOffset.width / 28)))
        .highPriorityGesture(cardGesture)
        .onTapGesture(count: 2) {
            guard step.interaction == .doubleTap,
                  !isCompletingStep else {
                return
            }
            completeInspectionStep()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sample photo")
        .accessibilityHint("Perform the gesture, or use the Next button.")
        .accessibilityIdentifier("onboarding-demo-card")
        .accessibilityAction(named: Text(step.gesturePrompt)) {
            completeStepWithoutGesture()
        }
    }

    @ViewBuilder
    private var tutorialDecisionOverlay: some View {
        let horizontalStrength = min(
            abs(cardOffset.width)
                / ReviewCardGesturePolicy.fullOverlayDistance,
            1
        )
        let upwardStrength = min(
            max(-cardOffset.height, 0)
                / ReviewCardGesturePolicy.fullOverlayDistance,
            1
        )

        if cardOffset.width < -ReviewCardGesturePolicy.overlayThreshold {
            TutorialDecisionOverlay(
                title: "Queue Delete",
                systemImage: "trash",
                color: .red,
                opacity: horizontalStrength
            )
        } else if cardOffset.width
                    > ReviewCardGesturePolicy.overlayThreshold {
            TutorialDecisionOverlay(
                title: "Keep",
                systemImage: "checkmark",
                color: .green,
                opacity: horizontalStrength
            )
        } else if cardOffset.height
                    < -ReviewCardGesturePolicy.overlayThreshold {
            TutorialDecisionOverlay(
                title: "Rescue",
                systemImage: "arrow.up.doc",
                color: .indigo,
                opacity: upwardStrength
            )
        }
    }

    private var cardGesture: some Gesture {
        DragGesture(minimumDistance: ReviewCardGesturePolicy.minimumDistance)
            .onChanged { value in
                guard !isCompletingStep else { return }
                cardOffset = step.constrainedOffset(
                    for: value.translation
                )
            }
            .onEnded { _ in
                guard !isCompletingStep else { return }
                let action = ReviewCardGesturePolicy.action(for: cardOffset)
                guard step.interaction == action.map(
                    ReviewTutorialInteraction.drag
                ) else {
                    resetCard()
                    return
                }
                completeDragStep(action)
            }
    }

    private var nextButton: some View {
        Button {
            if isLastStep {
                onFinish()
            } else {
                advance()
            }
        } label: {
            Text(isLastStep ? "Continue to Photos Access" : "Next")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .buttonStyle(.borderedProminent)
        .tint(step.tint)
        .controlSize(.large)
        .disabled(isCompletingStep)
        .accessibilityIdentifier(
            isLastStep ? "onboarding-continue" : "onboarding-next"
        )
    }

    private func completeDragStep(
        _ action: ReviewCardGestureAction?
    ) {
        guard let action else {
            resetCard()
            return
        }
        isCompletingStep = true

        let target: CGSize = switch action {
        case .queueDelete: CGSize(width: -600, height: 0)
        case .keep: CGSize(width: 600, height: 0)
        case .rescue: CGSize(width: 0, height: -170)
        }

        if reduceMotion {
            advance()
            return
        }

        withAnimation(.easeIn(duration: 0.18)) {
            cardOffset = target
        } completion: {
            advance()
        }
    }

    private func completeInspectionStep() {
        isInspecting = true
    }

    private func completeStepWithoutGesture() {
        if step == .inspect {
            completeInspectionStep()
        } else {
            advance()
        }
    }

    private func advance() {
        guard !isLastStep else {
            isCompletingStep = false
            return
        }
        cardOffset = .zero
        isInspecting = false
        isCompletingStep = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            stepIndex += 1
        }
    }

    private func resetCard() {
        withAnimation(
            reduceMotion
                ? nil
                : .spring(response: 0.32, dampingFraction: 0.82)
        ) {
            cardOffset = .zero
        }
    }
}

@MainActor
private enum TutorialSampleImage {
    static let asset = MediaAssetDescriptor(
        id: "onboarding-sample",
        mediaKind: .photo,
        creationDate: nil,
        modificationDate: nil,
        pixelWidth: 1_200,
        pixelHeight: 1_600,
        duration: 0,
        isFavorite: false,
        isScreenshot: false,
        isLivePhoto: false
    )

    static let image: UIImage = {
        let size = CGSize(width: 1_200, height: 1_600)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(
            size: size,
            format: format
        ).image { rendererContext in
            let context = rendererContext.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let sky = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(
                        red: 0.19,
                        green: 0.48,
                        blue: 0.78,
                        alpha: 1
                    ).cgColor,
                    UIColor(
                        red: 0.93,
                        green: 0.54,
                        blue: 0.46,
                        alpha: 1
                    ).cgColor
                ] as CFArray,
                locations: [0, 1]
            )
            if let sky {
                context.drawLinearGradient(
                    sky,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }

            UIColor(
                red: 1,
                green: 0.82,
                blue: 0.24,
                alpha: 0.94
            ).setFill()
            UIBezierPath(
                ovalIn: CGRect(
                    x: 790,
                    y: 190,
                    width: 230,
                    height: 230
                )
            ).fill()

            let distantMountain = UIBezierPath()
            distantMountain.move(to: CGPoint(x: -120, y: 1_180))
            distantMountain.addLine(to: CGPoint(x: 390, y: 560))
            distantMountain.addLine(to: CGPoint(x: 760, y: 1_100))
            distantMountain.addLine(to: CGPoint(x: 1_020, y: 720))
            distantMountain.addLine(to: CGPoint(x: 1_360, y: 1_170))
            distantMountain.addLine(to: CGPoint(x: 1_360, y: 1_700))
            distantMountain.addLine(to: CGPoint(x: -120, y: 1_700))
            distantMountain.close()
            UIColor(
                red: 0.20,
                green: 0.39,
                blue: 0.35,
                alpha: 1
            ).setFill()
            distantMountain.fill()

            let foregroundMountain = UIBezierPath()
            foregroundMountain.move(to: CGPoint(x: -180, y: 1_420))
            foregroundMountain.addLine(to: CGPoint(x: 360, y: 830))
            foregroundMountain.addLine(to: CGPoint(x: 650, y: 1_130))
            foregroundMountain.addLine(to: CGPoint(x: 900, y: 900))
            foregroundMountain.addLine(to: CGPoint(x: 1_390, y: 1_460))
            foregroundMountain.addLine(to: CGPoint(x: 1_390, y: 1_700))
            foregroundMountain.addLine(to: CGPoint(x: -180, y: 1_700))
            foregroundMountain.close()
            UIColor(
                red: 0.08,
                green: 0.20,
                blue: 0.25,
                alpha: 1
            ).setFill()
            foregroundMountain.fill()
        }
    }()
}

private struct TutorialSampleCard: View {
    let image: UIImage

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.62)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack {
                    HStack {
                        Label("Practice Photo", systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.5), in: Capsule())
                        Spacer()
                    }

                    Spacer()

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("A sample memory")
                                .font(.title3.bold())
                            Text("Try each review gesture here")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.76))
                        }
                        Spacer()
                    }
                }
                .padding(16)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .background(Color(white: 0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(0.35),
            radius: 12,
            y: 8
        )
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
    }
}

private struct TutorialGestureCue: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let step: ReviewTutorialStep

    @State private var isAnimating = false

    var body: some View {
        Label(
            step.gesturePrompt,
            systemImage: step == .inspect ? "hand.tap.fill" : "hand.draw.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(step.tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.white.opacity(0.1), in: Capsule())
        .offset(
            x: isAnimating ? step.cueTranslation.width : 0,
            y: isAnimating ? step.cueTranslation.height : 0
        )
        .scaleEffect(
            step == .inspect && isAnimating ? 1.08 : 1
        )
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 0.72)
                    .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }
}

private struct TutorialDecisionOverlay: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color
    let opacity: Double

    var body: some View {
        VStack {
            Label(title, systemImage: systemImage)
                .font(.title2.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.72), in: Capsule())
                .rotationEffect(.degrees(-6))
            Spacer()
        }
        .padding(.top, 34)
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
