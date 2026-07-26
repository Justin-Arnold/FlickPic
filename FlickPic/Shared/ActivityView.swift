import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onCompletion: @MainActor (Bool, String?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, error in
            Task { @MainActor in
                onCompletion(completed, error?.localizedDescription)
            }
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
