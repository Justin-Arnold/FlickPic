import SwiftUI

struct SessionSetupView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (ReviewConfiguration) -> Void
    @State private var configuration: ReviewConfiguration

    init(
        configuration: ReviewConfiguration,
        onSave: @escaping (ReviewConfiguration) -> Void
    ) {
        _configuration = State(initialValue: configuration)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                ReviewConfigurationSections(
                    configuration: $configuration
                )
            }
            .navigationTitle("Review Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if configuration.scope == .unreviewed {
                            configuration.includeReviewed = false
                        }
                        onSave(configuration)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct ReviewConfigurationSections: View {
    @Binding var configuration: ReviewConfiguration

    var body: some View {
        Section("What to Review") {
            Picker("Scope", selection: $configuration.scope) {
                ForEach(ReviewScopeKind.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .accessibilityIdentifier("scope-filter")

            if configuration.scope == .recent {
                Picker("Range", selection: $configuration.recentDays) {
                    Text("7 Days").tag(7)
                    Text("14 Days").tag(14)
                    Text("30 Days").tag(30)
                    Text("90 Days").tag(90)
                }
                .accessibilityIdentifier("recent-range")
            }

            if configuration.scope == .custom {
                DatePicker(
                    "From",
                    selection: $configuration.customStart,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("custom-range-start")

                DatePicker(
                    "Through",
                    selection: $configuration.customEnd,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("custom-range-end")
            }

            Picker("Media", selection: $configuration.mediaFilter) {
                ForEach(MediaFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .accessibilityIdentifier("media-filter")
        }

        Section("Order") {
            Picker("Direction", selection: $configuration.order) {
                ForEach(ReviewOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("review-order")
        }

        Section {
            Toggle(
                "Include Previously Reviewed",
                isOn: $configuration.includeReviewed
            )
            .disabled(configuration.scope == .unreviewed)
            .accessibilityIdentifier("include-reviewed")

            Toggle(
                "Include Favorites",
                isOn: $configuration.includeFavorites
            )
            .accessibilityIdentifier("include-favorites")
        } header: {
            Text("Options")
        } footer: {
            Text(
                "Hidden items are never included. Favorites stay protected unless you explicitly include them."
            )
        }
    }
}
