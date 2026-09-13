import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: HUDPanel!
    private var outsideClickMonitor: Any?
    private let isPreview = CommandLine.arguments.contains("--preview")
    private let monitor = UsageMonitor()
    private var cancellables = Set<AnyCancellable>()
    private var hoverWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let initial: Tab = CommandLine.arguments.contains("--tab=claude") ? .claude
            : CommandLine.arguments.contains("--tab=codex") ? .codex : .overview
        let host = NSHostingView(rootView: PopoverView(monitor: monitor, tab: initial))
        panel = HUDPanel(content: host)

        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.renderTitle($0) }
            .store(in: &cancellables)

        installHoverTracking()
        monitor.start()

        // Modo de inspeção visual: abre o painel sozinho, sem depender do mouse.
        if CommandLine.arguments.contains("--preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                guard let self else { return }
                self.showPanel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if let screen = NSScreen.main {
                        let f = self.panel.frame
                        print("CAPTURE_RECT=\(Int(f.minX)),\(Int(screen.frame.maxY - f.maxY)),\(Int(f.width)),\(Int(f.height))")
                        fflush(stdout)
                    }
                }
            }
        }
    }

    // MARK: Barra de menus

    /// Título compacto: percentual da janela de 5h de cada ferramenta, colorido pelo nível.
    private func renderTitle(_ snapshot: Snapshot) {
        guard let button = statusItem.button else { return }
        let title = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        func append(_ symbol: String, _ provider: ProviderSnapshot) {
            let gauge = provider.sessionLimit
            let color: NSColor
            switch gauge?.severity {
            case .critical: color = NSColor.systemRed
            case .warn: color = NSColor.systemOrange
            case .ok: color = NSColor.labelColor
            case nil: color = NSColor.tertiaryLabelColor
            }
            let text = gauge.map { String(format: "%.0f%%", $0.usedPercent) } ?? "–"
            title.append(NSAttributedString(string: "\(symbol) ", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            title.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        }

        append("CC", snapshot.claude)
        title.append(NSAttributedString(string: "  "))
        append("CX", snapshot.codex)
        button.attributedTitle = title
        button.toolTip = tooltip(snapshot)
    }

    private func tooltip(_ snapshot: Snapshot) -> String {
        let claudeCost = Fmt.money(snapshot.claude.today.cost)
        let codexCost = Fmt.money(snapshot.codex.today.cost)
        return """
        Claude Code — hoje \(Fmt.tokens(snapshot.claude.today.totals.total)) tokens · \(claudeCost)
        Codex — hoje \(Fmt.tokens(snapshot.codex.today.totals.total)) tokens · \(codexCost)
        """
    }

    // MARK: Abrir no hover

    private func installHoverTracking() {
        guard let button = statusItem.button else { return }
        button.addTrackingArea(NSTrackingArea(rect: button.bounds,
                                              options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                              owner: self,
                                              userInfo: nil))
    }

    @objc func mouseEntered(with event: NSEvent) {
        closeWork?.cancel()
        guard !panel.isVisible else { return }
        let work = DispatchWorkItem { [weak self] in self?.showPanel() }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.shared.openHoverDelay, execute: work)
    }

    @objc func mouseExited(with event: NSEvent) {
        hoverWork?.cancel()
        scheduleAutoClose()
    }

    /// Fecha quando o ponteiro sai tanto do ícone quanto do painel — sem isso o painel
    /// sumiria no caminho entre um e outro.
    private func scheduleAutoClose() {
        guard !isPreview else { return }
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.panel.isVisible else { return }
            if self.pointerIsOverPanelOrButton {
                self.scheduleAutoClose()
            } else {
                self.panel.dismiss()
                self.removeOutsideClickMonitor()
            }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private var pointerIsOverPanelOrButton: Bool {
        let pointer = NSEvent.mouseLocation
        if panel.frame.insetBy(dx: -10, dy: -10).contains(pointer) { return true }
        if let button = statusItem.button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if rect.insetBy(dx: -6, dy: -10).contains(pointer) { return true }
        }
        return false
    }

    @objc private func togglePopover() {
        panel.isVisible ? panel.dismiss() : showPanel()
    }

    private func showPanel() {
        guard let button = statusItem.button,
              let window = button.window,
              let screen = window.screen ?? NSScreen.main else { return }
        monitor.refresh()
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.present(below: anchor, on: screen)
        installOutsideClickMonitor()
        scheduleAutoClose()
    }

    /// Um clique fora fecha o painel, como qualquer menu do sistema.
    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            if !self.pointerIsOverPanelOrButton {
                self.panel.dismiss()
                self.removeOutsideClickMonitor()
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
