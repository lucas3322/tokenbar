import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: HUDPanel!
    private var outsideClickMonitor: Any?
    private let isPreview = CommandLine.arguments.contains("--preview")
    private let monitor = UsageMonitor()
    private let updater = Updater()
    private let notifier = Notifier()
    private var cancellables = Set<AnyCancellable>()
    private var hoverWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let initial: Tab = CommandLine.arguments.contains("--tab=claude") ? .claude
            : CommandLine.arguments.contains("--tab=codex") ? .codex
            : CommandLine.arguments.contains("--tab=ajustes") ? .settings : .overview
        let host = NSHostingView(rootView: PopoverView(monitor: monitor, updater: updater, notifier: notifier, tab: initial))
        panel = HUDPanel(content: host)

        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.renderTitle($0) }
            .store(in: &cancellables)

        installHoverTracking()
        monitor.start()
        updater.iniciar()
        notifier.iniciar()

        // Cada leitura nova passa pelo avaliador de avisos.
        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.notifier.avaliar($0) }
            .store(in: &cancellables)

        // Modo de inspeção visual: abre o painel sozinho, sem depender do mouse.
        if CommandLine.arguments.contains("--preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                guard let self else { return }
                self.showPanel(fechaSozinho: false)
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

    /// Clicar no app no Finder ou no Launchpad quando ele já está rodando: sem janela
    /// e sem ícone no Dock, isso não dava retorno nenhum e parecia que estava quebrado.
    /// Agora abre o painel, que é a única interface que o app tem.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Sem fechamento automático: o ponteiro está no Finder, longe do painel,
        // e o temporizador do hover o fecharia meio segundo depois de abrir.
        showPanel(fechaSozinho: false)
        return true
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
        let work = DispatchWorkItem { [weak self] in self?.showPanel(fechaSozinho: true) }
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
        // Clique no ícone: fica aberto até clicar fora ou o ponteiro se afastar.
        panel.isVisible ? panel.dismiss() : showPanel(fechaSozinho: true)
    }

    private func showPanel(fechaSozinho: Bool) {
        guard let button = statusItem.button,
              let window = button.window,
              let screen = window.screen ?? NSScreen.main else { return }
        monitor.refresh()
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.present(below: anchor, on: screen)
        installOutsideClickMonitor()
        if fechaSozinho { scheduleAutoClose() }
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

// O código de topo roda fora do contexto isolado; o delegate precisa nascer
// na main thread porque observa estado de UI.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Mantém a referência viva: o NSApplication guarda o delegate fracamente.
    objc_setAssociatedObject(app, "tokenbar.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.setActivationPolicy(.accessory)
    app.run()
}
