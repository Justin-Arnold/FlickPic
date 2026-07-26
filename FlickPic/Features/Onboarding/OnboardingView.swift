import SwiftUI

struct OnboardingView: View {
    let photoLibrary: PhotoLibraryService
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isShowingWalkthrough = false
    @State private var isRequestingAccess = false

    var body: some View {
        ZStack {
            if isShowingWalkthrough {
                GestureWalkthroughView(onFinish: requestAccess)
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
                ScrollView {
                    VStack(spacing: 28) {
                        Spacer()

                        Image(systemName: "photo.stack")
                            .font(.system(size: 58, weight: .medium))
                            .foregroundStyle(.indigo)
                            .accessibilityHidden(true)

                        VStack(spacing: 12) {
                            Text("A calmer camera roll")
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)

                            Text("Review your library one item at a time. Nothing is deleted until you inspect and confirm the queue.")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 18) {
                            PrivacyPromiseRow(
                                icon: "iphone",
                                title: "On your device",
                                detail: "Your media, review history, and image categories stay local."
                            )
                            PrivacyPromiseRow(
                                icon: "checkmark.shield",
                                title: "Deletion stays deliberate",
                                detail: "A swipe only adds an item to your review queue."
                            )
                            PrivacyPromiseRow(
                                icon: "sparkles.rectangle.stack",
                                title: "Private categorization",
                                detail: "If you choose, Apple Vision discovers image categories entirely on this iPhone."
                            )
                            PrivacyPromiseRow(
                                icon: "person.crop.circle.badge.xmark",
                                title: "No account or tracking",
                                detail: "No backend, analytics, ads, or subscription."
                            )
                        }
                        .padding(.vertical, 12)

                        Spacer()

                        Button {
                            isShowingWalkthrough = true
                        } label: {
                            Text("See How It Works")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("onboarding-start")

                        Text("The quick tour uses a sample card and never touches your library. FlickPic asks for read and write access only after the tour.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(24)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
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
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.indigo)
                .frame(width: 28)
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
