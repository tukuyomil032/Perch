// perchTests/Core/RefreshSchedulerTests.swift
import Foundation
import Testing

@testable import perch

@Suite("RefreshScheduler")
struct RefreshSchedulerTests {
    @Test("starts in not-running state")
    func initialStateNotRunning() async {
        let scheduler = RefreshScheduler()
        let running = await scheduler.isRunning
        #expect(!running)
    }

    @Test("start sets isRunning for non-manual interval")
    func startSetsRunning() async {
        let scheduler = RefreshScheduler(interval: .oneMinute)
        await scheduler.start(action: {})
        let running = await scheduler.isRunning
        #expect(running)
        await scheduler.stop()
    }

    @Test("manual interval does not set isRunning after start")
    func manualIntervalNotRunning() async {
        let scheduler = RefreshScheduler(interval: .manual)
        await scheduler.start(action: {})
        let running = await scheduler.isRunning
        #expect(!running)
    }

    @Test("stop sets isRunning to false")
    func stopSetsNotRunning() async {
        let scheduler = RefreshScheduler(interval: .oneMinute)
        await scheduler.start(action: {})
        await scheduler.stop()
        let running = await scheduler.isRunning
        #expect(!running)
    }

    @Test("triggerNow invokes action immediately")
    func triggerNowInvokesAction() async throws {
        let scheduler = RefreshScheduler(interval: .manual)
        let called = LockIsolated(false)
        await scheduler.start(action: { called.withLock { $0 = true } })
        await scheduler.triggerNow()
        // Give triggered Task a chance to run
        try await Task.sleep(for: .milliseconds(100))
        #expect(called.withLock { $0 })
    }

    @Test("setInterval restarts scheduler with new interval")
    func setIntervalRestarts() async {
        let scheduler = RefreshScheduler(interval: .manual)
        await scheduler.start(action: {})
        await scheduler.setInterval(.oneMinute)
        let interval = await scheduler.interval
        let running = await scheduler.isRunning
        #expect(interval == .oneMinute)
        #expect(running)
        await scheduler.stop()
    }
}

// シンプルなスレッドセーフ値コンテナ
private final class LockIsolated<Value: Sendable>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()
    init(_ value: Value) { _value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}
