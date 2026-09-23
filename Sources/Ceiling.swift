import Foundation

/// Teto de consumo do Claude, aprendido em vez de fixado.
///
/// O Claude Code não expõe o percentual do limite. Converter consumo em custo e comparar
/// com um teto funciona — desde que o teto esteja certo. Fixá-lo à mão não se sustenta:
/// ele muda com plano, com promoção e com o passar do tempo, e quando fica baixo demais o
/// painel chega a mostrar 114%, que é obviamente falso.
///
/// Aqui o teto se corrige sozinho com duas evidências vindas dos próprios registros:
///
/// - **Passou sem ser recusado.** Se uma janela acumulou mais do que o teto e a API não
///   recusou nada, o limite era maior: o teto sobe para aquele valor.
/// - **Foi recusado.** Um 429 por limite marca o ponto exato do teto. Essa evidência é
///   forte e pode baixá-lo, ao contrário da anterior.
struct Ceiling: Codable {
    var sessao: Double = 0
    var semanal: Double = 0
    /// Marca que o valor veio de uma recusa real, não de inferência.
    var sessaoExata = false
    var semanalExata = false

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tokenbar/teto.json")
    }

    static func carregar() -> Ceiling {
        guard let dados = try? Data(contentsOf: url),
              let t = try? JSONDecoder().decode(Ceiling.self, from: dados) else { return Ceiling() }
        return t
    }

    func salvar() {
        try? FileManager.default.createDirectory(at: Ceiling.url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let dados = try? JSONEncoder().encode(self) { try? dados.write(to: Ceiling.url, options: .atomic) }
    }

    /// Valor em uso. O config continua podendo fixar um teto, mas quem manda por padrão
    /// é o aprendizado: um número fixo envelhece e foi o que produziu "114%".
    func valor(paraSessao: Bool) -> Double {
        let doConfig = paraSessao ? Config.shared.claudeSessionCostCeiling : Config.shared.claudeWeeklyCostCeiling
        if let doConfig, doConfig > 0 { return doConfig }
        let aprendido = paraSessao ? sessao : semanal
        return aprendido
    }

    /// Fixa o teto a partir do percentual real informado pelo usuário.
    mutating func acertar(percentualReal: Double, custoAtual: Double, paraSessao: Bool) -> String {
        guard percentualReal > 0, custoAtual > 0 else {
            return "Informe o percentual que o app do Claude mostra."
        }
        let novo = custoAtual / (percentualReal / 100)
        if paraSessao { sessao = novo; sessaoExata = true } else { semanal = novo; semanalExata = true }
        salvar()
        return String(format: "Ajustado: teto de $%.2f", novo)
    }

    /// Aprende com o consumo observado. `recusado` indica que houve 429 nesta janela.
    mutating func aprender(custo: Double, recusado: Bool, paraSessao: Bool) {
        guard custo > 0 else { return }
        let exata = paraSessao ? sessaoExata : semanalExata
        let atual = paraSessao ? sessao : semanal

        var novo = atual
        var novoExata = exata

        if recusado {
            // Evidência forte: este foi o ponto em que a API disse não.
            novo = custo
            novoExata = true
        } else if custo > atual {
            // Passou do teto sem recusa: o limite é pelo menos isto. Sem folga inventada —
            // o teto vira o piso conhecido, e a janela em curso que o ultrapassa aparece
            // como "acima do teto", não como um percentual falsamente preciso.
            novo = custo
            novoExata = false
        }

        guard novo != atual || novoExata != exata else { return }
        if paraSessao { sessao = novo; sessaoExata = novoExata }
        else { semanal = novo; semanalExata = novoExata }
        salvar()
    }
}
