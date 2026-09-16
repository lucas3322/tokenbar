import AppKit
import SwiftUI

/// Ações de manutenção do próprio app: início automático, configuração e remoção.
final class SettingsStore: ObservableObject {
    @Published var launchesAtLogin: Bool = false
    @Published var cacheSize: String = "—"
    @Published var calibrationResult: String?

    static let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/local.tokenbar.plist"
    static var configURL: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.tokenbar/config.json")
    }

    init() { refresh() }

    func refresh() {
        launchesAtLogin = FileManager.default.fileExists(atPath: Self.plistPath)
        let cache = TokenCache.url
        if let size = (try? FileManager.default.attributesOfItem(atPath: cache.path)[.size]) as? Int {
            cacheSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        } else {
            cacheSize = "vazio"
        }
    }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (build \(build))"
    }

    /// Cria ou remove o LaunchAgent que faz o app subir no login.
    func setLaunchAtLogin(_ enabled: Bool) {
        let path = Self.plistPath
        if enabled {
            let executable = Bundle.main.executablePath ?? ""
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>local.tokenbar</string>
                <key>ProgramArguments</key><array><string>\(executable)</string></array>
                <key>RunAtLoad</key><true/>
                <key>KeepAlive</key><false/>
                <key>ProcessType</key><string>Interactive</string>
            </dict>
            </plist>
            """
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try? plist.write(toFile: path, atomically: true, encoding: .utf8)
            shell("launchctl load '\(path)' 2>/dev/null")
        } else {
            shell("launchctl unload '\(path)' 2>/dev/null")
            try? FileManager.default.removeItem(atPath: path)
        }
        refresh()
    }

    /// Abre o config no editor padrão, criando um arquivo comentado se ainda não existir.
    func openConfig() {
        let url = Self.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            let seed = """
            {
              "refreshSeconds": 20,
              "hoverDelaySeconds": 0.25,

              "_como_calibrar": "Abra o app do Claude em Configurações > Uso e veja o percentual da Sessão atual. Divida o custo do ciclo que o TokenBar mostra por esse percentual. Ex.: $9.00 com 20% usado -> teto = 45.",
              "claudeSessionCostCeiling": 45.0,
              "claudeWeeklyCostCeiling": 555.0,
              "claudeWeeklyResetWeekday": 5,
              "claudeWeeklyResetHour": 12
            }
            """
            try? seed.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// Remove app, início automático, cache e configuração. Precisa rodar de fora do próprio
    /// binário, porque o app não consegue apagar a si mesmo enquanto está em execução.
    func uninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Desinstalar o TokenBar?"
        alert.informativeText = """
        Serão removidos:

        • o app (\(Bundle.main.bundleURL.path))
        • o início automático no login
        • o cache e a sua configuração calibrada

        O código-fonte do projeto não é apagado. Esta ação não pode ser desfeita.
        """
        alert.addButton(withTitle: "Desinstalar")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let bundle = Bundle.main.bundleURL.path
        let script = """
        sleep 1
        launchctl unload '\(Self.plistPath)' 2>/dev/null
        rm -f '\(Self.plistPath)'
        rm -rf '\(bundle)'
        rm -rf '\(NSHomeDirectory())/.tokenbar'
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Converte o percentual real (lido no app do Claude) no teto de custo correspondente,
    /// e grava no config. O teto muda quando a Anthropic mexe nos limites ou concede bônus,
    /// então isso precisa ser refeito de vez em quando — daqui leva cinco segundos.
    func calibrate(realPercent: Double, currentCost: Double, key: String, label: String) {
        guard realPercent > 0, currentCost > 0 else {
            calibrationResult = "Informe o percentual que o app do Claude está mostrando."
            return
        }
        let ceiling = currentCost / (realPercent / 100)
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: Self.configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }
        root[key] = (ceiling * 100).rounded() / 100
        root["_calibrado_em"] = ISO8601DateFormatter().string(from: Date())

        try? FileManager.default.createDirectory(at: Self.configURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: root,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Self.configURL, options: .atomic)
        }
        Config.reload()
        calibrationResult = String(format: "%@ calibrado: teto de $%.2f", label, ceiling)
    }

    private func shell(_ command: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        try? task.run()
        task.waitUntilExit()
    }
}

struct SettingsTab: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var updater: Updater
    @ObservedObject var notifier: Notifier

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Panel(title: "COMPORTAMENTO") {
                Toggle(isOn: Binding(
                    get: { store.launchesAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Abrir junto com o login").font(.system(size: 11.5))
                        Text("mantém o ícone na barra sempre que você ligar o Mac")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Panel(title: "AVISOS") {
                NotifyBox(notifier: notifier)
            }

            Panel(title: "ATUALIZAÇÕES") {
                UpdateBox(updater: updater)
            }

            Panel(title: "CALIBRAR O CLAUDE") {
                CalibrationBox(store: store, snapshot: monitor.snapshot.claude)
            }

            Panel(title: "CONFIGURAÇÃO") {
                ActionRow(icon: "slider.horizontal.3",
                          title: "Abrir arquivo de configuração",
                          detail: "tetos de limite, preços e intervalo") { store.openConfig() }
                ActionRow(icon: "arrow.clockwise",
                          title: "Atualizar agora",
                          detail: "cache: \(store.cacheSize)") {
                    monitor.refresh()
                    store.refresh()
                }
                ActionRow(icon: "folder",
                          title: "Mostrar o app no Finder",
                          detail: Bundle.main.bundleURL.deletingLastPathComponent().path) {
                    store.revealApp()
                }
            }

            Panel(title: "APP") {
                HStack {
                    Text("Versão").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text(store.appVersion).font(.system(size: 11, design: .monospaced))
                }
                ActionRow(icon: "power", title: "Sair do TokenBar", detail: nil) {
                    NSApplication.shared.terminate(nil)
                }
                ActionRow(icon: "trash", title: "Desinstalar o TokenBar…",
                          detail: "remove o app, o início automático e o cache",
                          destructive: true) {
                    store.uninstall()
                }
            }
        }
        .onAppear { store.refresh() }
    }
}

/// Aviso ao passar do limiar de uso.
struct NotifyBox: View {
    @ObservedObject var notifier: Notifier

    private let opcoes: [Double] = [60, 70, 80, 90, 95]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $notifier.ativo) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Avisar ao passar do limite").font(.system(size: 11.5))
                    Text("um aviso por janela de 5h, de cada ferramenta")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if notifier.ativo {
                HStack(spacing: 8) {
                    Text("Avisar em").font(.system(size: 11)).foregroundStyle(.secondary)
                    Picker("", selection: $notifier.limiar) {
                        ForEach(opcoes, id: \.self) { Text("\(Int($0))%").tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 78)
                    Spacer()
                    Button("Testar") { notifier.testar() }
                        .font(.system(size: 10.5))
                        .controlSize(.small)
                }
                Text("O aviso é desenhado pelo próprio app: o Centro de Notificações do macOS recusa aplicativos sem conta paga de desenvolvedor da Apple.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Estado e ações de atualização.
struct UpdateBox: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                icone
                Text(mensagem)
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                botao
            }

            Toggle(isOn: $updater.verificarAutomaticamente) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Verificar automaticamente").font(.system(size: 11))
                    Text("única conexão de rede do app: consulta as versões publicadas, sem enviar nada")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    @ViewBuilder private var icone: some View {
        switch updater.estado {
        case .verificando, .baixando, .instalando:
            ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 15)
        case .disponivel:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 12)).foregroundStyle(Tint.codex).frame(width: 15)
        case .erro:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11)).foregroundStyle(Severity.warn.color).frame(width: 15)
        default:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 15)
        }
    }

    private var mensagem: String {
        switch updater.estado {
        case .parado: return "Versão \(updater.versaoAtual)"
        case .verificando: return "Procurando versão nova…"
        case .atualizado(let v): return "Você está na versão mais recente (\(v))"
        case .disponivel(let v, _, let tamanho):
            let mb = Double(tamanho) / 1_048_576
            return tamanho > 0
                ? String(format: "Versão %@ disponível · %.1f MB", v, mb)
                : "Versão \(v) disponível"
        case .baixando: return "Baixando…"
        case .instalando: return "Instalando — o app vai reabrir sozinho"
        case .erro(let texto): return texto
        }
    }

    @ViewBuilder private var botao: some View {
        switch updater.estado {
        case .disponivel:
            Button("Instalar") { Task { await updater.baixarEInstalar() } }
                .font(.system(size: 10.5)).controlSize(.small)
        case .verificando, .baixando, .instalando:
            EmptyView()
        default:
            Button("Verificar") { Task { await updater.verificar() } }
                .font(.system(size: 10.5)).controlSize(.small)
        }
    }
}

/// Converte o percentual mostrado pelo app do Claude no teto de custo do TokenBar.
struct CalibrationBox: View {
    @ObservedObject var store: SettingsStore
    let snapshot: ProviderSnapshot

    @State private var sessionPercent = ""
    @State private var weeklyPercent = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Abra o app do Claude em Configurações › Uso e copie os percentuais para cá. O TokenBar calcula o teto sozinho.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            field(title: "Sessão 5h",
                  placeholder: "ex.: 42",
                  text: $sessionPercent,
                  current: snapshot.currentBlock.cost,
                  key: "claudeSessionCostCeiling",
                  label: "Sessão")

            field(title: "Semanal",
                  placeholder: "ex.: 16",
                  text: $weeklyPercent,
                  current: snapshot.week.cost,
                  key: "claudeWeeklyCostCeiling",
                  label: "Semanal")

            if let result = store.calibrationResult {
                Text(result)
                    .font(.system(size: 10))
                    .foregroundStyle(Severity.ok.color)
            }
        }
    }

    private func field(title: String, placeholder: String, text: Binding<String>,
                       current: Double, key: String, label: String) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 11))
                .frame(width: 66, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 62)
            Text("%").font(.system(size: 10)).foregroundStyle(.tertiary)
            Text(Fmt.money(current))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Calibrar") {
                let value = Double(text.wrappedValue.replacingOccurrences(of: ",", with: ".")) ?? 0
                store.calibrate(realPercent: value, currentCost: current, key: key, label: label)
            }
            .font(.system(size: 10.5))
            .controlSize(.small)
            .disabled(text.wrappedValue.isEmpty || current <= 0)
        }
    }
}

/// Linha clicável com ícone, título e um detalhe discreto.
struct ActionRow: View {
    let icon: String
    let title: String
    let detail: String?
    var destructive = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 15)
                    .foregroundStyle(destructive ? Color.red : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(destructive ? Color.red : Color.primary)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(hovering ? 0.07 : 0.03),
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
