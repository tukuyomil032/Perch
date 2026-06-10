import Defaults
import Foundation
import SwiftUI

@MainActor @Observable
final class AIUsageStore {
    var usageByProvider: [String: AIUsageData] = [:]
    var activeProviderId: String?
    var isRefreshing: Bool = false
    var errors: [String: String] = [:]

    private var providers: [any AIProvider] = []
    private let scheduler = RefreshScheduler()
    private var refreshTask: Task<Void, Never>?

    var activeUsage: AIUsageData? {
        guard let id = activeProviderId else { return nil }
        return usageByProvider[id]
    }

    var configuredProviders: [any AIProvider] {
        providers.filter { $0.isConfigured }
    }

    func registerProvider(_ provider: any AIProvider) {
        providers.append(provider)
        if activeProviderId == nil && provider.isConfigured {
            activeProviderId = provider.id
        }
    }

    func startAutoRefresh() {
        let interval = Defaults[.aiRefreshInterval]
        Task {
            await scheduler.setInterval(interval)
            await scheduler.start { [weak self] in
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        Task {
            await scheduler.stop()
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let configured = configuredProviders
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
                    errors[id] = error.localizedDescription
                }
            }
        }
    }

    func refreshProvider(_ id: String) async {
        guard let provider = providers.first(where: { $0.id == id }),
            provider.isConfigured
        else { return }
        do {
            let data = try await provider.fetchUsage()
            usageByProvider[id] = data
            errors.removeValue(forKey: id)
        } catch {
            errors[id] = error.localizedDescription
        }
    }

    func selectProvider(_ id: String) {
        activeProviderId = id
    }
}
