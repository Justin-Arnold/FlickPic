import SwiftUI

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
}

struct GestureWalkthroughView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            header
                            progress
                            coachMark
                                .id(step.id)

                            tutorialCard
                                .frame(maxWidth: .infinity)
                                .frame(
                                    height: min(
                                        max(geometry.size.height * 0.4, 240),
                                        390
                                    )
                                )

                            TutorialGestureCue(step: step)
                                .id(step.id)
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                        .frame(
                            minHeight: max(geometry.size.height - 76, 0),
                            alignment: .top
                        )
                    }
                    .scrollBounceBehavior(.basedOnSize)

                    nextButton
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .background(.black.opacity(0.92))
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("A quick tour")
                    .font(.headline)
                Text("Practice on this sample—nothing is saved.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()

            Button("Skip to Photos Access", action: onFinish)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("onboarding-skip")
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
            isInspecting: isInspecting
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
                if let constrainedOffset =
                    ReviewCardGesturePolicy.constrainedOffset(
                        for: value.translation
                    ) {
                    cardOffset = constrainedOffset
                }
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
        isCompletingStep = true
        if reduceMotion {
            isInspecting = true
            isCompletingStep = false
            return
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
            isInspecting = true
        } completion: {
            isCompletingStep = false
        }
    }

    private func completeStepWithoutGesture() {
        if isLastStep {
            onFinish()
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

private struct TutorialSampleCard: View {
    let isInspecting: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.19, green: 0.48, blue: 0.78),
                        Color(red: 0.93, green: 0.54, blue: 0.46)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(.yellow.opacity(0.9))
                    .frame(
                        width: geometry.size.width * 0.25,
                        height: geometry.size.width * 0.25
                    )
                    .blur(radius: 2)
                    .position(
                        x: geometry.size.width * 0.76,
                        y: geometry.size.height * 0.2
                    )

                Image(systemName: "mountain.2.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(
                        Color(red: 0.08, green: 0.2, blue: 0.25),
                        Color(red: 0.2, green: 0.39, blue: 0.35)
                    )
                    .frame(width: geometry.size.width * 1.15)
                    .position(
                        x: geometry.size.width * 0.5,
                        y: geometry.size.height * 0.67
                    )

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

                if isInspecting {
                    ZStack {
                        Rectangle()
                            .fill(.black.opacity(0.34))
                        VStack(spacing: 12) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 56, weight: .light))
                            Text("Inspection mode")
                                .font(.headline)
                            Text("Pinch and pan for a closer look")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .background(Color(white: 0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(0.35),
            radius: isInspecting ? 24 : 12,
            y: 8
        )
        .scaleEffect(isInspecting ? 1.025 : 1)
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
