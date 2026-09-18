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
    /// Texto do centro. Em modo tempo mostra o que falta, não um percentual.
    var centro: String?

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

                Text(centro ?? (isEmpty ? "–" : Fmt.percent(percent)))
                    .font(.system(size: centro != nil ? 12 : 14, weight: .semibold, design: .rounded))
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
///
/// Claude e Codex medem coisas diferentes de propósito. O Codex informa o percentual
/// real do limite; o Claude não expõe isso em lugar nenhum acessível localmente, então
/// ali o anel mede o tempo da janela — que é exato — em vez de inventar um consumo.
struct RingRow: View {
    let snapshot: Snapshot

    var body: some View {
        HStack(spacing: 2) {
            limite(snapshot.claude.sessionLimit, "Claude", "sessão 5h", Tint.claude)
            limite(snapshot.claude.weeklyLimit, "Claude", "ciclo", Tint.claude)
            limite(snapshot.codex.sessionLimit, "Codex", "sessão 5h", Tint.codex)
            limite(snapshot.codex.weeklyLimit, "Codex", "semanal", Tint.codex)
        }
    }

    /// Anel de tempo: o quanto da janela já correu.
    private func tempo(_ janela: (start: Date, end: Date)?, _ caption: String,
                       _ window: String, _ tint: Color) -> some View {
        guard let janela else {
            return AnyView(Ring(percent: 0, caption: caption, window: window,
                                detail: "sem uso", color: .secondary, isEmpty: true, centro: "–"))
        }
        let total = janela.end.timeIntervalSince(janela.start)
        let corrido = Date().timeIntervalSince(janela.start)
        let fracao = total > 0 ? min(max(corrido / total * 100, 0), 100) : 0
        return AnyView(Ring(percent: fracao, caption: caption, window: window,
                            detail: "reseta \(rotuloReset(janela.end))",
                            color: tint,
                            centro: Fmt.countdown(to: janela.end) ?? "—"))
    }

    /// Anel de limite: percentual real informado pelo servidor.
    private func limite(_ gauge: LimitGauge?, _ caption: String,
                        _ window: String, _ tint: Color) -> some View {
        let detail: String?
        if let reset = gauge?.resetsAt {
            detail = "reseta \(rotuloReset(reset))"
        } else if let gauge {
            detail = gauge.exact ? nil : gauge.label
        } else {
            detail = "sem dado"
        }
        return Ring(percent: gauge?.usedPercent ?? 0,
                    caption: caption,
                    window: window,
                    detail: detail,
                    color: gauge?.color(tint: tint) ?? .secondary,
                    isEmpty: gauge == nil)
    }

    private func rotuloReset(_ data: Date) -> String {
        data.timeIntervalSinceNow > 36 * 3_600 ? Fmt.weekday(data) : Fmt.clock(data)
    }
}
