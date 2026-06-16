import Defaults
import Foundation
import SwiftUI

@MainActor @Observable
final class AIUsageStore {
    var usageByProvider: [String: AIUsageData] = [:]
    var activeProviderId: String?
    var isRefreshing: Bool = false
    var errors: [String: String] = [:]
    var lastRefreshError: String?

    private var providers: [any AIProvider] = []
    private let scheduler = RefreshScheduler()

    var activeUsage: AIUsageData? {
        guard let id = activeProviderId else { return nil }
        return usageByProvider[id]
    }

    var configuredProviders: [any AIProvider] {
        providers.filter { $0.isConfigured }
    }

    /// Provider with highest today cost — used to show its logo in compact pill.
    var mostUsedProviderId: String? {
        usageByProvider
            .filter { $0.value.cost?.todayUSD ?? 0 > 0 }
            .max(by: { ($0.value.cost?.todayUSD ?? 0) < ($1.value.cost?.todayUSD ?? 0) })
            .map(\.key)
            ?? activeProviderId
    }

    func registerProvider(_ provider: any AIProvider) {
        providers.append(provider)
        if activeProviderId == nil && provider.isConfigured {
            activeProviderId = provider.id
        }
    }

    func startAutoRefresh() async {
        let interval = Defaults[.aiRefreshInterval]
        await scheduler.setInterval(interval)
        await scheduler.start { [weak self] in
            await self?.refresh()
        }
    }

    func stopAutoRefresh() async {
        await scheduler.stop()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let configured = configuredProviders
        var refreshError: String?
        await withTaskGroup(of: (String, Result<AIUsageData, Error>).self) { group in
            for provider in configured {
                // Capture id before entering the task to avoid crossing
                // into MainActor-isolated context from inside the child task.
                let providerId = provider.id
                group.addTask {
                    do {
                        let data = try await provider.fetchUsage()
                        return (providerId, .success(data))
                    } catch {
                        return (providerId, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let data):
                    usageByProvider[id] = data
                    errors.removeValue(forKey: id)
                case .failure(let error):
                    let description = error.localizedDescription
                    errors[id] = description
                    refreshError = description
                }
            }
        }
        lastRefreshError = refreshError
    }

    func refreshProvider(_ id: String) async {
        guard let provider = providers.first(where: { $0.id == id }),
            provider.isConfigured
        else { return }
        do {
            let data = try await provider.fetchUsage()
            usageByProvider[id] = data
            errors.removeValue(forKey: id)
            lastRefreshError = nil
        } catch {
            let description = error.localizedDescription
            errors[id] = description
            lastRefreshError = description
        }
    }

    func selectProvider(_ id: String) {
        activeProviderId = id
    }
}
