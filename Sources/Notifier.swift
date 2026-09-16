import AppKit
import Foundation
import UserNotifications

/// Avisa quando uma janela de limite passa do limiar configurado.
///
/// Dispara no máximo uma vez por janela e por ferramenta: o aviso serve para você
/// decidir o que fazer, não para repetir a cada atualização até o limite estourar.
@MainActor
final class Notifier: ObservableObject {
    @Published var ativo: Bool = Config.shared.notifyEnabled {
        didSet {
            Config.escrever(chave: "notifyEnabled", valor: ativo)
            if ativo { pedirPermissao() }
        }
    }
    @Published var limiar: Double = Config.shared.notifyThreshold {
        didSet { Config.escrever(chave: "notifyThreshold", valor: limiar) }
    }
    @Published private(set) var permissao: String = "—"

    /// Janelas já avisadas, para não repetir. Persistido: reiniciar o app não
    /// deve fazer o aviso voltar para a mesma janela.
    private var avisadas: Set<String> = Notifier.carregarAvisadas()

    private static var arquivoEstado: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tokenbar/avisos.json")
    }

    private static func carregarAvisadas() -> Set<String> {
        guard let dados = try? Data(contentsOf: arquivoEstado),
              let lista = try? JSONDecoder().decode([String].self, from: dados) else { return [] }
        return Set(lista)
    }

    private func salvarAvisadas() {
        // Mantém o arquivo pequeno: só as janelas recentes importam.
        if avisadas.count > 40 { avisadas = Set(avisadas.suffix(20)) }
        try? FileManager.default.createDirectory(
            at: Notifier.arquivoEstado.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let dados = try? JSONEncoder().encode(Array(avisadas)) {
            try? dados.write(to: Notifier.arquivoEstado, options: .atomic)
        }
    }

    func iniciar() {
        // Nada a preparar: o aviso é uma janela nossa. A autorização do sistema é
        // solicitada só junto do envio, como tentativa extra.
    }

    func pedirPermissao() {
        let centro = UNUserNotificationCenter.current()
        centro.requestAuthorization(options: [.alert, .sound]) { [weak self] concedida, erro in
            Task { @MainActor in
                if let erro {
                    self?.permissao = "indisponível: \(erro.localizedDescription)"
                } else {
                    self?.permissao = concedida ? "autorizado" : "negado nos Ajustes do sistema"
                }
            }
        }
    }

    /// Chamado depois de cada leitura. Avalia as janelas de sessão das duas ferramentas.
    func avaliar(_ snapshot: Snapshot) {
        guard ativo else { return }
        for provedor in [snapshot.claude, snapshot.codex] {
            guard let medidor = provedor.sessionLimit, medidor.usedPercent >= limiar else { continue }

            // A identidade da janela é o horário de reset: virou a janela, pode avisar de novo.
            let janela = medidor.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "sem-reset"
            let chave = "\(provedor.name)|\(janela)|\(Int(limiar))"
            guard !avisadas.contains(chave) else { continue }

            avisadas.insert(chave)
            salvarAvisadas()
            enviar(provedor: provedor, medidor: medidor)
        }
    }

    /// Chamado quando o usuário clica no aviso.
    var aoAbrirPainel: (() -> Void)?

    private func enviar(provedor: ProviderSnapshot, medidor: LimitGauge) {
        var partes = ["janela de 5h"]
        if let reset = Fmt.countdown(to: medidor.resetsAt) { partes.append("reseta em \(reset)") }
        if !medidor.exact { partes.append("estimado") }

        AlertBanner.mostrar(titulo: String(format: "%@ em %.0f%%", provedor.name, medidor.usedPercent),
                            corpo: partes.joined(separator: " · "),
                            cor: medidor.color(tint: provedor.tint),
                            aoClicar: { [weak self] in self?.aoAbrirPainel?() })
        enviarPeloSistema(provedor: provedor, medidor: medidor)
    }

    /// Tentativa adicional pelo Centro de Notificações — funciona só se o app estiver
    /// autorizado, o que não acontece com assinatura ad-hoc. Falha em silêncio.
    private func enviarPeloSistema(provedor: ProviderSnapshot, medidor: LimitGauge) {
        let conteudo = UNMutableNotificationContent()
        conteudo.title = String(format: "%@ em %.0f%%", provedor.name, medidor.usedPercent)

        var partes = ["janela de 5h"]
        if let reset = Fmt.countdown(to: medidor.resetsAt) { partes.append("reseta em \(reset)") }
        if !medidor.exact { partes.append("estimado") }
        conteudo.body = partes.joined(separator: " · ")
        conteudo.sound = .default

        let pedido = UNNotificationRequest(identifier: UUID().uuidString, content: conteudo, trigger: nil)
        UNUserNotificationCenter.current().add(pedido) { [weak self] erro in
            guard let erro else { return }
            Task { @MainActor in self?.permissao = "falhou: \(erro.localizedDescription)" }
        }
    }

    /// Mostra um aviso de exemplo.
    func testar() {
        AlertBanner.mostrar(titulo: "TokenBar",
                            corpo: String(format: "É assim que o aviso aparece ao passar de %.0f%%.", limiar),
                            cor: Tint.claude,
                            aoClicar: { [weak self] in self?.aoAbrirPainel?() })
    }
}
