import Foundation
import SwiftUI

/// Contagem bruta de tokens de uma requisição, antes de qualquer precificação.
struct RawUsage: Codable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0

    var total: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }

    static func += (lhs: inout RawUsage, rhs: RawUsage) {
        lhs.input += rhs.input
        lhs.output += rhs.output
        lhs.cacheRead += rhs.cacheRead
        lhs.cacheWrite5m += rhs.cacheWrite5m
        lhs.cacheWrite1h += rhs.cacheWrite1h
    }
}

/// Uso agregado por modelo dentro de uma janela de tempo.
struct Aggregate {
    var byModel: [String: RawUsage] = [:]

    mutating func add(model: String, _ usage: RawUsage) {
        byModel[model, default: RawUsage()] += usage
    }

    mutating func merge(_ other: Aggregate) {
        for (model, usage) in other.byModel { byModel[model, default: RawUsage()] += usage }
    }

    var totals: RawUsage {
        var out = RawUsage()
        for usage in byModel.values { out += usage }
        return out
    }

    var cost: Double {
        byModel.reduce(0) { $0 + Pricing.cost(model: $1.key, usage: $1.value) }
    }

    var isEmpty: Bool { byModel.isEmpty }
}

/// Uma janela de 5h de atividade, no estilo dos "blocos" de limite de sessão.
struct Block {
    var start: Date
    var end: Date
    var aggregate: Aggregate
    var isActive: Bool { Date() < end }
}

/// Um limite com percentual de uso e horário de reset.
struct LimitGauge {
    var usedPercent: Double
    var resetsAt: Date?
    /// `true` quando o percentual veio do servidor; `false` quando foi estimado localmente.
    var exact: Bool
    var label: String

    var severity: Severity {
        switch usedPercent {
        case ..<60: return .ok
        case ..<85: return .warn
        default: return .critical
        }
    }
}

enum Severity { case ok, warn, critical }

extension LimitGauge {
    /// Abaixo de 60% vale a cor da ferramenta; a partir daí, o alerta assume.
    func color(tint: Color) -> Color {
        severity == .ok ? tint : severity.color
    }
}

/// Sessão em execução no momento.
struct ActiveSession {
    var project: String
    var model: String
    var contextUsed: Int
    var contextWindow: Int
    var contextPercent: Double { contextWindow > 0 ? Double(contextUsed) / Double(contextWindow) * 100 : 0 }
}

/// Tudo que uma das ferramentas (Claude ou Codex) reporta.
struct ProviderSnapshot {
    var name: String
    var available = false
    var note: String?

    var sessionLimit: LimitGauge?
    var weeklyLimit: LimitGauge?

    var today = Aggregate()
    var week = Aggregate()
    var currentBlock: Aggregate = Aggregate()

    var activeSession: ActiveSession?
    var plan: String?

    /// Início da janela semanal informado pelo servidor, quando existe.
    var weeklyWindowStart: Date?

    /// `true` quando o total semanal cobre a janela real do limite, e não 7 dias corridos.
    var weekIsCycle = false
    var weekLabel: String { weekIsCycle ? "ciclo" : "7 dias" }

    /// Cor de identidade da ferramenta.
    var tint: Color { Tint.of(name) }
}

struct Snapshot {
    var claude = ProviderSnapshot(name: "Claude Code")
    var codex = ProviderSnapshot(name: "Codex")
    var generatedAt = Date()
    var scanDuration: TimeInterval = 0
}
