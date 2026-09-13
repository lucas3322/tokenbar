import AppKit
import SwiftUI

/// Ações de manutenção do próprio app: início automático, configuração e remoção.
final class SettingsStore: ObservableObject {
    @Published var launchesAtLogin: Bool = false
    @Published var cacheSize: String = "—"

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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
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
