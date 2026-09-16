import AppKit
import SwiftUI

/// Aviso desenhado pelo próprio app.
///
/// O caminho natural seria UNUserNotificationCenter, mas ele recusa apps assinados
/// ad-hoc ("Notifications are not allowed for this application"): sem conta paga de
/// desenvolvedor da Apple, o sistema não entrega. Como o aviso de limite é a razão
/// de existir do recurso, ele não pode depender disso — este banner é uma janela
/// nossa, e aparece em qualquer configuração.
@MainActor
final class AlertBanner {
    private static var janelaAtual: NSWindow?

    static func mostrar(titulo: String, corpo: String, cor: Color, aoClicar: @escaping () -> Void) {
        janelaAtual?.orderOut(nil)

        let conteudo = NSHostingView(rootView: BannerView(titulo: titulo, corpo: corpo, cor: cor,
                                                          aoClicar: aoClicar, aoFechar: { fechar() }))
        conteudo.frame = NSRect(x: 0, y: 0, width: 330, height: 78)

        let janela = NSPanel(contentRect: conteudo.frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        janela.isFloatingPanel = true
        janela.level = .statusBar
        janela.isOpaque = false
        janela.backgroundColor = .clear
        janela.hasShadow = true
        janela.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        janela.contentView = conteudo

        if let tela = NSScreen.main {
            let x = tela.visibleFrame.maxX - conteudo.frame.width - 14
            let y = tela.visibleFrame.maxY - conteudo.frame.height - 10
            janela.setFrameOrigin(NSPoint(x: x, y: y + 12))
            janela.alphaValue = 0
            janela.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                janela.animator().alphaValue = 1
                janela.animator().setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
        janelaAtual = janela
        NSSound(named: "Ping")?.play()

        // Some sozinho, como um aviso do sistema faria.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { fechar(se: janela) }
    }

    static func fechar(se janela: NSWindow? = nil) {
        guard let alvo = janela ?? janelaAtual, alvo === janelaAtual else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            alvo.animator().alphaValue = 0
        }, completionHandler: {
            alvo.orderOut(nil)
            if janelaAtual === alvo { janelaAtual = nil }
        })
    }
}

private struct BannerView: View {
    let titulo: String
    let corpo: String
    let cor: Color
    let aoClicar: () -> Void
    let aoFechar: () -> Void

    @State private var sobre = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 17))
                .foregroundStyle(cor)
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.system(size: 12.5, weight: .semibold))
                Text(corpo).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            if sobre {
                Button(action: aoFechar) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 330, height: 78, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(cor.opacity(0.35), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { sobre = $0 }
        .onTapGesture { aoClicar(); aoFechar() }
    }
}
