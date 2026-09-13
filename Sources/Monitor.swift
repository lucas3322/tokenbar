import Foundation
import Combine

/// Roda as coletas fora da main thread e publica o snapshot para a UI.
final class UsageMonitor: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var isRefreshing = false

    private let queue = DispatchQueue(label: "tokenbar.collector", qos: .utility)
    private var timer: Timer?
    private let cache = TokenCache.load()

    func start() {
        refresh()
        let interval = Config.shared.refreshSeconds
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        queue.async { [weak self] in
            guard let self else { return }
            let began = Date()
            Config.reload()

            var next = Snapshot()
            next.claude = ClaudeCollector.collect(cache: self.cache)
            next.codex = CodexCollector.collect(cache: self.cache)
            next.scanDuration = Date().timeIntervalSince(began)
            self.cache.save(pruningBefore: Date().addingTimeInterval(-retentionWindow))

            DispatchQueue.main.async {
                self.snapshot = next
                self.isRefreshing = false
            }
        }
    }
}
