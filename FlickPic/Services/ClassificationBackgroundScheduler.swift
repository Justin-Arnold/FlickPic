@preconcurrency import BackgroundTasks
import Foundation

@MainActor
final class ClassificationBackgroundScheduler: @unchecked Sendable {
    static let shared = ClassificationBackgroundScheduler()
    static let taskIdentifier = "com.justin-arnold.FlickPic.classification"

    private var isRegistered = false
    private var handler: (@MainActor @Sendable () async -> Bool)?

    private init() {}

    func register(
        handler: @escaping @MainActor @Sendable () async -> Bool
    ) {
        self.handler = handler
        guard !isRegistered else { return }

        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }

            let work = Task { @MainActor [weak self] in
                await self?.handler?() ?? false
            }
            processingTask.expirationHandler = {
                work.cancel()
            }
            Task { @MainActor [weak self] in
                let success = await work.value
                processingTask.setTaskCompleted(success: success)
                if !success {
                    self?.schedule()
                }
            }
        }
    }

    func schedule() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Foreground indexing remains the reliable path. The system can reject
            // duplicate or unavailable background requests without affecting it.
        }
    }
}
