import Foundation

/// Configuração opcional em ~/.tokenbar/config.json. Tudo tem padrão sensato.
struct Config {
    var refreshSeconds: Double = 20
    var openHoverDelay: Double = 0.25
    /// Teto de custo (USD) de uma janela de 5h do Claude. Se ausente, calibra pelo pico histórico.
    var claudeSessionCostCeiling: Double?
    /// Teto de custo (USD) do ciclo semanal do Claude.
    var claudeWeeklyCostCeiling: Double?
    /// Dia da semana em que o limite semanal reseta (1 = domingo ... 5 = quinta).
    var claudeWeeklyResetWeekday: Int = 5
    /// Hora do reset semanal, no fuso local.
    var claudeWeeklyResetHour: Int = 12
    /// Preços OpenAI por MTok, ex.: {"gpt-5.6-sol": {"input": 5, "output": 30}}
    var openaiPrices: [String: Rate] = [:]
    /// Repositório consultado para atualizações. Precisa ser público.
    var updateRepo: String = "lucas3322/tokenbar"
    var autoCheckUpdates: Bool = true
    var updateCheckHours: Double = 6
    /// Avisos de limite.
    var notifyEnabled: Bool = true
    var notifyThreshold: Double = 80

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tokenbar/config.json")
    }

    static private(set) var shared = Config.load()

    static func reload() { shared = load() }

    /// Grava uma única chave preservando o resto do arquivo, inclusive comentários
    /// em chaves que começam com "_".
    static func escrever(chave: String, valor: Any) {
        var raiz: [String: Any] = [:]
        if let dados = try? Data(contentsOf: url),
           let existente = try? JSONSerialization.jsonObject(with: dados) as? [String: Any] {
            raiz = existente
        }
        raiz[chave] = valor
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let dados = try? JSONSerialization.data(withJSONObject: raiz,
                                                   options: [.prettyPrinted, .sortedKeys]) {
            try? dados.write(to: url, options: .atomic)
        }
        reload()
    }

    static func load() -> Config {
        var config = Config()
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return config }

        if let value = root["refreshSeconds"] as? NSNumber { config.refreshSeconds = max(5, value.doubleValue) }
        if let value = root["hoverDelaySeconds"] as? NSNumber { config.openHoverDelay = max(0, value.doubleValue) }
        config.claudeSessionCostCeiling = (root["claudeSessionCostCeiling"] as? NSNumber)?.doubleValue
        config.claudeWeeklyCostCeiling = (root["claudeWeeklyCostCeiling"] as? NSNumber)?.doubleValue
        if let day = (root["claudeWeeklyResetWeekday"] as? NSNumber)?.intValue, (1...7).contains(day) {
            config.claudeWeeklyResetWeekday = day
        }
        if let hour = (root["claudeWeeklyResetHour"] as? NSNumber)?.intValue, (0...23).contains(hour) {
            config.claudeWeeklyResetHour = hour
        }

        if let repo = root["updateRepo"] as? String { config.updateRepo = repo }
        if let auto = root["autoCheckUpdates"] as? Bool { config.autoCheckUpdates = auto }
        if let horas = (root["updateCheckHours"] as? NSNumber)?.doubleValue { config.updateCheckHours = max(1, horas) }

        if let ligado = root["notifyEnabled"] as? Bool { config.notifyEnabled = ligado }
        if let limiar = (root["notifyThreshold"] as? NSNumber)?.doubleValue {
            config.notifyThreshold = min(max(limiar, 1), 100)
        }

        if let prices = root["openaiPrices"] as? [String: [String: Any]] {
            for (model, entry) in prices {
                let input = (entry["input"] as? NSNumber)?.doubleValue ?? 0
                let output = (entry["output"] as? NSNumber)?.doubleValue ?? 0
                let cacheRead = (entry["cachedInput"] as? NSNumber)?.doubleValue ?? input * 0.1
                config.openaiPrices[model.lowercased()] = Rate(input: input, output: output,
                                                               cacheRead: cacheRead,
                                                               cacheWrite5m: 0, cacheWrite1h: 0)
            }
        }
        Pricing.openaiOverrides = config.openaiPrices
        return config
    }
}
