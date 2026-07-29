import Foundation
import IOKit.ps

/// Watches `IOPowerSources` for battery percentage / charging state.
///
/// No permission dialog: `IOPSCopyPowerSourcesInfo` is public API with no entitlement or
/// TCC category behind it.
@MainActor
@Observable
final class BatteryMonitor {
    private(set) var percentage: Int?
    private(set) var isCharging = false
    private(set) var isPresent = false

    // `nonisolated(unsafe)`: written once on the main actor in `observe()` and read only
    // from the nonisolated `deinit`, matching `IslandHost`'s observation-token pattern —
    // no concurrent access is possible since nothing else touches this property.
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    init() {
        refresh()
        observe()
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        }
    }

    private func observe() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard
            let source = IOPSNotificationCreateRunLoopSource(
                { context in
                    guard let context else { return }
                    let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
                    Task { @MainActor in monitor.refresh() }
                },
                context
            )?.takeRetainedValue()
        else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
    }

    private func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let first = sources.first,
            let description = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue()
                as? [String: AnyObject]
        else {
            isPresent = false
            percentage = nil
            isCharging = false
            return
        }
        isPresent = true
        percentage = description[kIOPSCurrentCapacityKey] as? Int
        isCharging = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
    }
}
