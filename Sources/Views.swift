import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case overview = "Visão geral"
    case claude = "Claude"
    case codex = "Codex"
    case settings = "Ajustes"
    var id: String { rawValue }
}

struct PopoverView: View {
    @ObservedObject var monitor: UsageMonitor
    @StateObject private var settings = SettingsStore()
    @ObservedObject var updater: Updater
    @State var tab: Tab = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            RingRow(snapshot: monitor.snapshot)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            TabBar(selection: $tab)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .overview:
                        ProviderRow(provider: monitor.snapshot.claude)
                        ProviderRow(provider: monitor.snapshot.codex)
                        totalsRow
                    case .claude:
                        ProviderDetail(provider: monitor.snapshot.claude)
                    case .codex:
                        ProviderDetail(provider: monitor.snapshot.codex)
                    case .settings:
                        SettingsTab(store: settings, monitor: monitor, updater: updater)
                    }
                }
                .padding(14)
            }

            Divider()
            footer
        }
        .frame(width: 440)
        .frame(minHeight: 430, maxHeight: 600)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .foregroundStyle(.tint)
            Text("TokenBar")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if case .disponivel = updater.estado {
                Button { tab = .settings } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 9))
                        Text("atualizar").font(.system(size: 10))
                    }
                    .foregroundStyle(Tint.codex)
                }
                .buttonStyle(.plain)
            }
            if monitor.isRefreshing {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            Text(Fmt.clock(monitor.snapshot.generatedAt))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var totalsRow: some View {
        let claude = monitor.snapshot.claude
        let codex = monitor.snapshot.codex
        return VStack(alignment: .leading, spacing: 6) {
            Text("SOMA DAS DUAS FERRAMENTAS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            HStack {
                StatBox(title: "Hoje",
                        value: Fmt.tokens(claude.today.totals.total + codex.today.totals.total),
                        detail: Fmt.money(claude.today.cost + codex.today.cost))
                StatBox(title: "7 dias",
                        value: Fmt.tokens(claude.week.totals.total + codex.week.totals.total),
                        detail: Fmt.money(claude.week.cost + codex.week.cost))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                monitor.refresh()
            } label: {
                Label("Atualizar", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Text(String(format: "scan %.1fs", monitor.snapshot.scanDuration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            Button {
                tab = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Ajustes")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

/// Cartão resumido usado na aba "Visão geral".
struct ProviderCard: View {
    let provider: ProviderSnapshot
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(provider.available ? Color.accentColor : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(provider.name).font(.system(size: 12, weight: .semibold))
                if let plan = provider.plan {
                    Text(plan.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Fmt.money(provider.today.cost))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let note = provider.note {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                GaugeRow(title: "Sessão 5h", gauge: provider.sessionLimit, tint: provider.tint)
                GaugeRow(title: "Semanal", gauge: provider.weeklyLimit, tint: provider.tint,
                         emptyHint: "defina o teto no config")

                if let session = provider.activeSession {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(provider.tint)
                        Text(session.project).lineLimit(1)
                        Text("·").foregroundStyle(.tertiary)
                        Text("ctx \(Fmt.percent(session.contextPercent))")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Fmt.tokens(provider.today.totals.total)) hoje")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 10))
                    .padding(.top, 1)
                }
            }
        }
        .padding(11)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Aba detalhada de um provedor.
struct ProviderDetail: View {
    let provider: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let note = provider.note {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Panel(title: "LIMITES") {
                GaugeRow(title: "Sessão 5h", gauge: provider.sessionLimit, tint: provider.tint)
                GaugeRow(title: "Semanal", gauge: provider.weeklyLimit, tint: provider.tint,
                         emptyHint: "defina claudeWeeklyCostCeiling no config")
                if provider.sessionLimit?.exact == false {
                    Text("Estimado (\(provider.sessionLimit?.label ?? "")): o Claude Code não expõe o limite localmente. Confira em Ajustes › Calibrar o Claude.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let session = provider.activeSession {
                Panel(title: "SESSÃO ATIVA") {
                    HStack {
                        Text(session.project).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Spacer()
                        Text(Fmt.modelLabel(session.model))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Bar(percent: session.contextPercent, color: provider.tint)
                    HStack {
                        Text("contexto \(Fmt.tokens(session.contextUsed)) / \(Fmt.tokens(session.contextWindow))")
                        Spacer()
                        Text(Fmt.percent(session.contextPercent))
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }

            Panel(title: "TOKENS") {
                HStack {
                    StatBox(title: "Hoje", value: Fmt.tokens(provider.today.totals.total), detail: Fmt.money(provider.today.cost))
                    StatBox(title: provider.weekLabel, value: Fmt.tokens(provider.week.totals.total), detail: Fmt.money(provider.week.cost))
                }
                UsageBreakdown(usage: provider.today.totals)
            }

            if !provider.today.byModel.isEmpty {
                Panel(title: "POR MODELO (HOJE)") {
                    ForEach(provider.today.byModel.sorted { $0.value.total > $1.value.total }, id: \.key) { model, usage in
                        HStack {
                            Text(Fmt.modelLabel(model))
                                .font(.system(size: 10.5, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Text(Fmt.tokens(usage.total))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(Fmt.money(Pricing.cost(model: model, usage: usage)))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            content
        }
    }
}

struct GaugeRow: View {
    let title: String
    let gauge: LimitGauge?
    /// Cor de identidade da ferramenta; a severidade sobrepõe quando há alerta.
    var tint: Color = Tint.claude
    /// Texto mostrado quando não há como calcular o percentual.
    var emptyHint: String = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
                if let gauge, !gauge.exact {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .help("estimado localmente — \(gauge.label)")
                }
                Spacer()
                if let gauge {
                    if let reset = Fmt.countdown(to: gauge.resetsAt) {
                        Text("reset \(reset)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Text(Fmt.percent(gauge.usedPercent))
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(gauge.color(tint: tint))
                } else {
                    Text(emptyHint)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            if let gauge {
                Bar(percent: gauge.usedPercent, color: gauge.color(tint: tint))
            } else {
                // Sem dado: trilho vazio, para não sugerir "0% usado".
                Capsule().fill(Color.primary.opacity(0.06)).frame(height: 5)
            }
        }
    }
}

struct Bar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(color)
                    .frame(width: max(2, geo.size.width * min(percent, 100) / 100))
            }
        }
        .frame(height: 5)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9.5)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 15, weight: .medium, design: .rounded))
            Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Quebra input / output / cache — onde os tokens realmente foram.
struct UsageBreakdown: View {
    let usage: RawUsage

    var body: some View {
        let rows: [(String, Int)] = [
            ("entrada", usage.input),
            ("saída", usage.output),
            ("cache lido", usage.cacheRead),
            ("cache escrito", usage.cacheWrite5m + usage.cacheWrite1h),
        ]
        VStack(spacing: 3) {
            ForEach(rows, id: \.0) { label, value in
                HStack {
                    Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text(Fmt.tokens(value)).font(.system(size: 10, design: .monospaced))
                }
            }
        }
    }
}

/// Linha compacta da visão geral: consumo e sessão ativa. Os limites já estão nos anéis.
struct ProviderRow: View {
    let provider: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(provider.activeSession != nil ? provider.tint : Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(provider.name).font(.system(size: 12, weight: .semibold))
                if let plan = provider.plan {
                    Text(plan.uppercased())
                        .font(.system(size: 8.5, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Fmt.money(provider.today.cost))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            }

            if let note = provider.note {
                Text(note).font(.system(size: 10.5)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 0) {
                    metric("hoje", Fmt.tokens(provider.today.totals.total))
                    metric(provider.weekLabel, Fmt.tokens(provider.week.totals.total))
                    metric("cache", Fmt.percent(cacheShare))
                }

                if let session = provider.activeSession {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(provider.tint)
                        Text(session.project).lineLimit(1)
                        Text("·").foregroundStyle(.tertiary)
                        Text(Fmt.modelLabel(session.model)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text("ctx \(Fmt.percent(session.contextPercent))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.system(size: 10))
                }
            }
        }
        .padding(11)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
    }

    /// Quanto do consumo veio de cache — a métrica que explica volume alto com custo baixo.
    private var cacheShare: Double {
        let totals = provider.today.totals
        guard totals.total > 0 else { return 0 }
        return Double(totals.cacheRead) / Double(totals.total) * 100
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Seletor de abas próprio. O `Picker` segmentado do sistema tem largura intrínseca e não
/// preenche o painel — aqui cada aba divide o espaço em partes iguais.
struct TabBar: View {
    @Binding var selection: Tab
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { tab in
                let isSelected = tab == selection
                Text(tab.rawValue)
                    .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.14))
                                .matchedGeometryEffect(id: "aba", in: highlight)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.16)) { selection = tab }
                    }
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
