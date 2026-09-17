import Foundation

/// Delayed work belongs to one focus request, never to a later window/app selection.
@MainActor
final class FocusRequests {
    typealias Work = @MainActor @Sendable () -> Void
    typealias Scheduler = (TimeInterval, @escaping Work) -> Void

    private var generation: UInt64 = 0
    private let schedule: Scheduler

    init(schedule: @escaping Scheduler = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }) {
        self.schedule = schedule
    }

    func begin() -> UInt64 {
        generation &+= 1
        return generation
    }

    func after(_ delay: TimeInterval, request: UInt64, perform work: @escaping Work) {
        schedule(delay) { [weak self] in
            guard self?.generation == request else { return }
            work()
        }
    }
}
