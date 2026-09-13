import AppKit
import SwiftUI

/// Painel flutuante que desce da barra de menus. Sem barra de título, cantos arredondados,
/// fundo translúcido e sem roubar o foco da janela em que você está trabalhando.
final class HUDPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        // Uma camada sólida por cima do blur: sem ela um wallpaper claro atravessa o painel
        // e o texto perde contraste.
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(tint)

        content.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(content)
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            tint.topAnchor.constraint(equalTo: blur.topAnchor),
            tint.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            content.topAnchor.constraint(equalTo: blur.topAnchor),
            content.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        contentView = blur
    }

    override var canBecomeKey: Bool { true }

    /// Desce a partir da barra, com fade. É o gesto que dá a sensação de "abrir do topo".
    func present(below anchor: NSRect, on screen: NSScreen) {
        let size = contentView?.fittingSize ?? frame.size
        let width = max(size.width, 420)
        let height = max(size.height, 260)

        var x = anchor.midX - width / 2
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - width - 8)
        let finalY = anchor.minY - height - 6

        setFrame(NSRect(x: x, y: finalY + 14, width: width, height: height), display: false)
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.17
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(NSRect(x: x, y: finalY, width: width, height: height), display: true)
        }
    }

    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}
