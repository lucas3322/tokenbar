import SwiftUI

/// Anel de progresso: o elemento de leitura rápida do painel.
struct Ring: View {
    let percent: Double
    let caption: String
    let window: String
    let detail: String?
    let color: Color
    /// Quando não há percentual calculável, o anel fica vazio em vez de mostrar 0%.
    var isEmpty = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: isEmpty ? 0 : min(percent, 100) / 100)
                    .stroke(
                        AngularGradient(colors: [color.opacity(0.65), color],
                                        center: .center,
                                        startAngle: .degrees(-90),
                                        endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: percent)

                Text(isEmpty ? "–" : Fmt.percent(percent))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isEmpty ? Color.secondary : Color.primary)
                    .monospacedDigit()
            }
            .frame(width: 50, height: 50)

            VStack(spacing: 1) {
                Text(caption)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Text(window)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(detail ?? " ")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Linha de anéis no topo do painel: o que importa antes de qualquer clique.
struct RingRow: View {
    let snapshot: Snapshot

    var body: some View {
        HStack(spacing: 2) {
            ring(snapshot.claude.sessionLimit, "Claude", "sessão 5h")
            ring(snapshot.claude.weeklyLimit, "Claude", "semanal")
            ring(snapshot.codex.sessionLimit, "Codex", "sessão 5h")
            ring(snapshot.codex.weeklyLimit, "Codex", "semanal")
        }
    }

    private func ring(_ gauge: LimitGauge?, _ caption: String, _ window: String) -> some View {
        let detail: String?
        if let reset = gauge?.resetsAt {
            // Reset distante vira dia da semana; perto, o horário.
            detail = reset.timeIntervalSinceNow > 36 * 3_600
                ? "reseta \(Fmt.weekday(reset))"
                : "reseta \(Fmt.clock(reset))"
        } else if gauge != nil {
            detail = gauge?.exact == true ? nil : "estimado"
        } else {
            detail = "calibrar"
        }
        return Ring(percent: gauge?.usedPercent ?? 0,
                    caption: caption,
                    window: window,
                    detail: detail,
                    color: gauge?.severity.color ?? .secondary,
                    isEmpty: gauge == nil)
    }
}
