import SwiftUI

struct OnboardingView: View {
    let photoLibrary: PhotoLibraryService
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isShowingWalkthrough = false
    @State private var isRequestingAccess = false

    var body: some View {
        ZStack {
            if isShowingWalkthrough {
                GestureWalkthroughView(
                    photoLibrary: photoLibrary,
                    onFinish: requestAccess
                )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                privacyIntroduction
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if isRequestingAccess {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                ProgressView("Requesting Photos Access…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityIdentifier("onboarding-requesting-access")
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.28),
            value: isShowingWalkthrough
        )
    }

    private var privacyIntroduction: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.12),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            GeometryReader { geometry in
                let usesExpandedLayout =
                    geometry.size.height >= 700
                    && !dynamicTypeSize.isAccessibilitySize
                let verticalPadding: CGFloat =
                    usesExpandedLayout ? 28 : 18

                ScrollView {
                    VStack(spacing: 0) {
                        Image(systemName: "photo.stack")
                            .font(
                                .system(
                                    size: usesExpandedLayout ? 56 : 46,
                                    weight: .medium
                                )
                            )
                            .foregroundStyle(.indigo)
                            .accessibilityHidden(true)

                        Text("A calmer camera roll")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .padding(.top, usesExpandedLayout ? 18 : 12)

                        adaptiveSpacer(
                            usesExpandedLayout: usesExpandedLayout,
                            compactLength: 24,
                            expandedMinimum: 32
                        )

                        VStack(
                            alignment: .leading,
                            spacing: usesExpandedLayout ? 22 : 12
                        ) {
                            PrivacyPromiseRow(
                                icon: "iphone",
                                title: "On your device",
                                detail: "Media, history, and categories stay local."
                            )
                            PrivacyPromiseRow(
                                icon: "checkmark.shield",
                                title: "Deletion stays deliberate",
                                detail: "Nothing is deleted until you confirm the queue."
                            )
                            PrivacyPromiseRow(
                                icon: "sparkles.rectangle.stack",
                                title: "Private categorization",
                                detail: "Optional Apple Vision categorization stays on-device."
                            )
                            PrivacyPromiseRow(
                                icon: "person.crop.circle.badge.xmark",
                                title: "No account or tracking",
                                detail: "No backend, analytics, ads, or subscription."
                            )
                        }

                        adaptiveSpacer(
                            usesExpandedLayout: usesExpandedLayout,
                            compactLength: 20,
                            expandedMinimum: 28
                        )

                        Text(
                            "The tour uses a sample photo. Photos access is requested only when you continue."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520)
                        .accessibilityIdentifier("onboarding-privacy-note")

                        if usesExpandedLayout {
                            Spacer(minLength: 28)
                        }
                    }
                    .frame(
                        minHeight: max(
                            0,
                            geometry.size.height - (verticalPadding * 2)
                        )
                    )
                    .padding(.horizontal, usesExpandedLayout ? 28 : 20)
                    .padding(.vertical, verticalPadding)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            introductionActions
        }
    }

    @ViewBuilder
    private func adaptiveSpacer(
        usesExpandedLayout: Bool,
        compactLength: CGFloat,
        expandedMinimum: CGFloat
    ) -> some View {
        if usesExpandedLayout {
            Spacer(minLength: expandedMinimum)
        } else {
            Color.clear
                .frame(height: compactLength)
                .accessibilityHidden(true)
        }
    }

    private var introductionActions: some View {
        VStack {
            HStack(spacing: 10) {
                Button(action: requestAccess) {
                    Text("Skip Tour")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("onboarding-skip-tour")

                Button {
                    isShowingWalkthrough = true
                } label: {
                    Text("See How It Works")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("onboarding-start")
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .disabled(isRequestingAccess)
    }

    private func requestAccess() {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        Task {
            _ = await photoLibrary.requestAuthorization()
            isRequestingAccess = false
            onComplete()
        }
    }
}

private struct PrivacyPromiseRow: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
