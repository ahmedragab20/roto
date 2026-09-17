import Testing
@testable import Roto

@MainActor
struct FocusRequestsTests {
    @Test(arguments: [0.08, 0.3])
    func newerRequestCancelsDelayedRaiseAndActivation(delay: Double) {
        var pending: [FocusRequests.Work] = []
        let requests = FocusRequests(schedule: { _, work in pending.append(work) })
        var raised: [String] = []
        let first = requests.begin()
        requests.after(delay, request: first) { raised.append("old window") }
        let second = requests.begin()
        requests.after(delay, request: second) { raised.append("new window") }

        // A late callback must not override a newer one, regardless of delivery order.
        pending.reversed().forEach { $0() }
        #expect(raised == ["new window"])
    }

    @Test func immediateRequestCancelsAllPriorDelayedWork() {
        var pending: [FocusRequests.Work] = []
        let requests = FocusRequests(schedule: { _, work in pending.append(work) })
        var calls = 0
        let request = requests.begin()
        requests.after(0.08, request: request) { calls += 1 }
        requests.after(0.3, request: request) { calls += 1 }
        _ = requests.begin() // An open/activation request with no delayed raise of its own.
        pending.forEach { $0() }
        #expect(calls == 0)
    }

    @Test func currentRequestRetainsBothCallbacks() {
        var pending: [FocusRequests.Work] = []
        let requests = FocusRequests(schedule: { _, work in pending.append(work) })
        var calls = 0
        let request = requests.begin()
        requests.after(0.08, request: request) { calls += 1 }
        requests.after(0.3, request: request) { calls += 1 }
        pending.forEach { $0() }
        #expect(calls == 2)
    }
}
