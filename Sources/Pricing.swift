import Foundation

/// Tabela de preços por milhão de tokens (USD).
struct Rate {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite5m: Double
    var cacheWrite1h: Double

    /// Os multiplicadores padrão da Anthropic: leitura de cache 0.1x, escrita 1.25x (5m) e 2x (1h).
    static func anthropic(input: Double, output: Double, cacheRead: Double? = nil) -> Rate {
        Rate(input: input,
             output: output,
             cacheRead: cacheRead ?? input * 0.1,
             cacheWrite5m: input * 1.25,
             cacheWrite1h: input * 2.0)
    }

    /// OpenAI cobra input cacheado a 0.1x e não cobra escrita de cache separadamente.
    static func openai(input: Double, output: Double) -> Rate {
        Rate(input: input, output: output, cacheRead: input * 0.1, cacheWrite5m: 0, cacheWrite1h: 0)
    }
}

enum Pricing {
    /// Preços de tabela da API Anthropic (USD por MTok).
    static let anthropic: [String: Rate] = [
        "claude-fable-5-1":  .anthropic(input: 10, output: 50, cacheRead: 0.25),
        "claude-mythos-5-1": .anthropic(input: 10, output: 50, cacheRead: 0.25),
        "claude-fable-5":    .anthropic(input: 10, output: 50),
        "claude-mythos-5":   .anthropic(input: 10, output: 50),
        "claude-opus-5":     .anthropic(input: 5,  output: 25),
        "claude-opus-4-8":   .anthropic(input: 5,  output: 25),
        "claude-opus-4-7":   .anthropic(input: 5,  output: 25),
        "claude-opus-4-6":   .anthropic(input: 5,  output: 25),
        "claude-sonnet-5":   .anthropic(input: 2,  output: 10),
        "claude-sonnet-4-6": .anthropic(input: 3,  output: 15),
        "claude-haiku-4-5":  .anthropic(input: 1,  output: 5),
    ]

    /// Preços OpenAI. Editáveis em ~/.tokenbar/config.json porque mudam com frequência.
    static let openaiDefaults: [String: Rate] = [
        "gpt-5.6-sol":   .openai(input: 5.00, output: 30.00),
        "gpt-5.6-terra": .openai(input: 2.00, output: 12.00),
        "gpt-5.6-luna":  .openai(input: 0.20, output: 1.20),
        "gpt-5.3-codex": Rate(input: 1.75, output: 14.00, cacheRead: 0.175, cacheWrite5m: 0, cacheWrite1h: 0),
    ]

    static var openaiOverrides: [String: Rate] = [:]

    /// O modo rápido do Opus 5/4.8 é cobrado como tier premium.
    static let fastModeRate = Rate.anthropic(input: 10, output: 50)

    static func rate(for model: String) -> Rate? {
        let key = normalize(model)
        if key.hasSuffix("|fast") {
            let base = String(key.dropLast(5))
            if base.hasPrefix("claude-opus-5") || base.hasPrefix("claude-opus-4-8") { return fastModeRate }
            return lookup(base)
        }
        return lookup(key)
    }

    private static func lookup(_ key: String) -> Rate? {
        if let exact = anthropic[key] ?? openaiOverrides[key] ?? openaiDefaults[key] { return exact }
        // Prefixo mais longo que casa, para variantes futuras (ex.: sufixos de data).
        let tables: [[String: Rate]] = [anthropic, openaiOverrides, openaiDefaults]
        var best: (String, Rate)?
        for table in tables {
            for (name, rate) in table where key.hasPrefix(name) {
                if best == nil || name.count > best!.0.count { best = (name, rate) }
            }
        }
        if let best { return best.1 }
        // Modelos OpenAI que ainda não estão na tabela (ex.: modelos internos de review)
        // são precificados pelo tier principal, para o custo total não sumir silenciosamente.
        if key.hasPrefix("gpt-") || key.hasPrefix("codex-") || key.hasPrefix("o3") || key.hasPrefix("o4") {
            return openaiOverrides["gpt-5.6-sol"] ?? openaiDefaults["gpt-5.6-sol"]
        }
        return nil
    }

    /// Remove sufixos como "[1m]" (contexto estendido) mantendo o marcador de modo rápido.
    static func normalize(_ model: String) -> String {
        var m = model.lowercased()
        if let range = m.range(of: "[1m]") { m.removeSubrange(range) }
        return m.trimmingCharacters(in: .whitespaces)
    }

    static func cost(model: String, usage: RawUsage) -> Double {
        guard let rate = rate(for: model) else { return 0 }
        let m = 1_000_000.0
        return Double(usage.input) / m * rate.input
            + Double(usage.output) / m * rate.output
            + Double(usage.cacheRead) / m * rate.cacheRead
            + Double(usage.cacheWrite5m) / m * rate.cacheWrite5m
            + Double(usage.cacheWrite1h) / m * rate.cacheWrite1h
    }

    /// Janela de contexto por modelo, para a barra de contexto da sessão ativa.
    static func contextWindow(for model: String) -> Int {
        if model.contains("[1m]") { return 1_000_000 }
        let key = normalize(model)
        if key.hasPrefix("claude-haiku") { return 200_000 }
        if key.hasPrefix("claude-") { return 1_000_000 }
        return 272_000
    }
}
